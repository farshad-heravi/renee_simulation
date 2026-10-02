#!/bin/bash
# Keeps renee_perception on the Jetson (the ZED camera host) in step with this
# host's copy. Run at compose start-up by the `jetson-code-sync` service, or by
# hand:  docker compose run --rm jetson-code-sync   |   ./jetson_code_sync.sh
#
# What is compared: the host repo's version id vs the one recorded on the Jetson
# in <target>/.jetson_sync (the Jetson tree is not a git repo). The version id is
# the host HEAD commit (JETSON_SYNC_SOURCE=head, default) or HEAD plus a content
# hash of the working tree (JETSON_SYNC_SOURCE=worktree: tracked + untracked,
# non-ignored files, handy while developing uncommitted code).
# Equal -> nothing happens (one ssh round trip). Different ->
#   1. stream the files over ssh (tar) into a staging dir on the Jetson,
#   2. install with `rsync -c --backup` (only files whose content differs are
#      replaced, the old versions go to ~/.renee_sync_backups/<timestamp>/),
#   3. record the new version + a sha256 manifest in <target>/.jetson_sync,
#   4. optionally run JETSON_POST_SYNC_CMD on the Jetson in the target dir (default:
#      none; there is nothing to build there: no ROS, Python scripts run in place),
#   5. restart the camera service (it is NOT a systemd unit): `bash
#      <target>/tools/camera_link_ctl.sh restart` on the Jetson (nohup + pidfile, no
#      sudo, shipped in renee_perception; head mode only ships it once it is
#      committed there). Contract used: `{start|stop|restart|status}`, exit 0 = ok,
#      and for `status` exit 0 = running, non-zero = not running.
# When the versions are equal and the camera service is not running, it is started
# (JETSON_CAMERA_AUTOSTART=0 disables that). Neither ever happens while a manual
# capture or the ROS ZED wrapper holds the camera (record_data.py, zed_aruco_detect.py,
# zed_wrapper_node; override the list with JETSON_CAMERA_HOLDERS='a|b'): a notice is
# printed instead. If tools/camera_link_ctl.sh is not in the synced tree, a notice is
# printed and the camera service is left alone. JETSON_CAMERA_RESTART=0 disables
# every start/restart.
#
# Safety (this overwrites code on a real robot):
#   - Nothing is ever deleted outright. Files that disappeared from the host since
#     the last sync (and only those, from the recorded manifest) are moved to the
#     backup dir. Jetson-only files (data/, config/, ...) are never touched.
#   - Files edited on the Jetson since the last sync are detected from the
#     manifest. If the sync would overwrite/remove one, or on the first sync
#     (no manifest) would overwrite differing files, it refuses unless
#     JETSON_SYNC_FORCE=1 or you confirm at a TTY. Backups are kept either way.
#     On that first adoption the host copy is expected to be the newer one (host
#     wins): the differing files are listed and replaced, old versions backed up.
#   - JETSON_SYNC_DRY_RUN=1 only prints the plan (including what it would
#     start/restart). JETSON_SYNC=0 disables it.
# Non-fatal: exits 0 on skip/refusal/failure so start-up is never blocked
# (JETSON_SYNC_STRICT=1 returns 1 instead, for manual runs).
#
# Env: RENEE_PERCEPTION_DIR (host repo), JETSON_TARGET_DIR (default
# renee_ws/src/renee_perception, relative to the Jetson's $HOME),
# JETSON_CAMERA_RESTART=0, JETSON_CAMERA_AUTOSTART=0, JETSON_CAMERA_HOLDERS,
# JETSON_POST_SYNC_CMD, JETSON_SSH_CONFIG (-F file), VOGUI_HOST (reachability
# probe, default 192.168.0.200). JETSON_SYNC_RESTART is a deprecated alias of
# JETSON_CAMERA_RESTART.
set -u
export LC_ALL=C

SRC="${RENEE_PERCEPTION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/renee_perception}"
TARGET="${JETSON_TARGET_DIR:-renee_ws/src/renee_perception}"
MODE="${JETSON_SYNC_SOURCE:-head}"
BOARD_HOST="${VOGUI_HOST:-192.168.0.200}"
CAM_RESTART="${JETSON_CAMERA_RESTART:-${JETSON_SYNC_RESTART:-1}}"
CAM_AUTOSTART="${JETSON_CAMERA_AUTOSTART:-1}"
CAM_HOLDERS="${JETSON_CAMERA_HOLDERS:-record_data.py|zed_aruco_detect.py|zed_wrapper_node}"
POST_CMD="${JETSON_POST_SYNC_CMD:-}"
STRICT="${JETSON_SYNC_STRICT:-0}"

log()  { echo "[jetson-sync] $*"; }
warn() { echo "[jetson-sync] WARNING: $*" >&2; }
RC=0
finish() { [ "$STRICT" = 1 ] && RC=1; exit "$RC"; }   # refusals and failures
skip()   { log "$*"; exit 0; }                          # nothing to do / not applicable

[ "${JETSON_SYNC:-1}" = 0 ] && skip "disabled (JETSON_SYNC=0)"
export GIT_OPTIONAL_LOCKS=0
git_src() { git -c safe.directory='*' -C "$SRC" "$@"; }
git_src rev-parse --git-dir >/dev/null 2>&1 || skip "$SRC is not a git repo, skipping"

TMP=$(mktemp -d)
CTL="/tmp/jcs-$$"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=6 -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=60)
[ -n "${JETSON_SSH_CONFIG:-}" ] && SSH+=(-F "$JETSON_SSH_CONFIG")
SSH+=(jetson)
cleanup() { "${SSH[@]}" -O exit >/dev/null 2>&1; rm -rf "$TMP" "$CTL"; }
trap cleanup EXIT

if ! timeout 3 bash -c "exec 3<>/dev/tcp/$BOARD_HOST/22" 2>/dev/null; then
    skip "$BOARD_HOST unreachable (not on the rover's network?), skipping"
fi

# ---- host side: version id, file set, manifest -----------------------------
HEAD_COMMIT=$(git_src rev-parse HEAD 2>/dev/null) || skip "$SRC has no commits, skipping"
DIRTY=$(git_src status --porcelain 2>/dev/null | wc -l)
STAGE="$TMP/stage"; mkdir -p "$STAGE"
case "$MODE" in
  head)
    git_src archive HEAD | tar -x -C "$STAGE" || { warn "git archive failed"; finish; }
    ;;
  worktree)
    git_src ls-files -z -co --exclude-standard > "$TMP/list0"
    : > "$TMP/list"
    while IFS= read -r -d '' f; do [ -f "$SRC/$f" ] && printf '%s\0' "$f" >> "$TMP/list"; done < "$TMP/list0"
    (cd "$SRC" && tar -c --null -T "$TMP/list") | tar -x -C "$STAGE" || { warn "tar of worktree failed"; finish; }
    ;;
  *) warn "unknown JETSON_SYNC_SOURCE '$MODE' (head|worktree)"; finish ;;
esac
find "$STAGE" \( -name __pycache__ -o -name '*.pyc' -o -name .git \) -prune -exec rm -rf {} + 2>/dev/null
(cd "$STAGE" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum | sed 's#  \./#  #') > "$TMP/manifest"
NFILES=$(wc -l < "$TMP/manifest")
if [ "$MODE" = worktree ]; then
    VERSION="${HEAD_COMMIT}+wt.$(sha256sum < "$TMP/manifest" | cut -c1-12)"
else
    VERSION="$HEAD_COMMIT"
    [ "$DIRTY" -gt 0 ] && log "note: host repo has $DIRTY uncommitted change(s), not synced (JETSON_SYNC_SOURCE=worktree includes them)"
fi

# ---- one ssh round trip: recorded state + how the host files compare -------
read -r -d '' PROBE <<'EOF'
case "$t" in /*) ;; *) t="$HOME/$t";; esac
echo "##TARGET $t"
if ! cd "$t" 2>/dev/null; then cat >/dev/null; echo "##END"; exit 0; fi
echo "##STATE"; cat .jetson_sync 2>/dev/null
echo "##CLASSIFY"
while read -r sum path; do
  if [ ! -e "$path" ]; then echo "new $path"
  elif [ "$(sha256sum -- "$path" | cut -d' ' -f1)" = "$sum" ]; then echo "same $path"
  else echo "differs $path"; fi
done
echo "##LOCALMOD"
grep -v '^#' .jetson_sync 2>/dev/null | while read -r sum path; do
  if [ ! -e "$path" ]; then echo "missing $path"
  elif [ "$(sha256sum -- "$path" | cut -d' ' -f1)" != "$sum" ]; then echo "modified $path"; fi
done
echo "##END"
EOF
if ! "${SSH[@]}" "t=$(printf '%q' "$TARGET")"$'\n'"$PROBE" < "$TMP/manifest" > "$TMP/probe.out" 2> "$TMP/probe.err"; then
    skip "cannot reach the Jetson over ssh ($(head -c 200 "$TMP/probe.err" | tr '\n' ' ')), skipping"
fi
grep -q '^##END' "$TMP/probe.out" || { warn "unexpected probe output from the Jetson"; finish; }
TARGET_ABS=$(sed -n 's/^##TARGET //p' "$TMP/probe.out")
awk -v d="$TMP" '/^##/{f=substr($1,3); next} f{print > (d "/probe." f)}' "$TMP/probe.out"
for s in STATE CLASSIFY LOCALMOD; do touch "$TMP/probe.$s"; done

PREV=$(sed -n 's/^# commit \([^ ]*\).*/\1/p' "$TMP/probe.STATE" | head -1)
grep -v '^#' "$TMP/probe.STATE" | sed 's/^[^ ]*  //' | sort > "$TMP/prev_paths"
sed 's/^[^ ]*  //' "$TMP/manifest" | sort > "$TMP/new_paths"
sed -n 's/^new //p'      "$TMP/probe.CLASSIFY" | sort > "$TMP/new_files"
sed -n 's/^differs //p'  "$TMP/probe.CLASSIFY" | sort > "$TMP/differs"
sed -n 's/^modified //p' "$TMP/probe.LOCALMOD" | sort > "$TMP/localmod"
grep -q '^##STATE' "$TMP/probe.out" || cp "$TMP/new_paths" "$TMP/new_files"   # target dir does not exist yet
comm -23 "$TMP/prev_paths" "$TMP/new_paths" > "$TMP/removed"
# Three-way: only files the HOST changed since the last sync (or all, on the first
# sync) plus files missing on the Jetson are applied. A file edited on the Jetson
# that the host did not change is left alone.
sort "$TMP/manifest" > "$TMP/man_sorted"
grep -v '^#' "$TMP/probe.STATE" | sort > "$TMP/prev_man_sorted"
if [ -n "$PREV" ]; then
    comm -13 "$TMP/prev_man_sorted" "$TMP/man_sorted" | sed 's/^[^ ]*  //' | sort > "$TMP/host_changed"
else
    cp "$TMP/new_paths" "$TMP/host_changed"
fi
comm -12 "$TMP/host_changed" "$TMP/differs" > "$TMP/changed"
sort -u "$TMP/new_files" "$TMP/changed" > "$TMP/apply"
sort -u "$TMP/apply" "$TMP/removed" > "$TMP/touched"
comm -12 "$TMP/localmod" "$TMP/touched" > "$TMP/conflicts"
comm -23 "$TMP/localmod" "$TMP/touched" > "$TMP/kept_local"
count() { wc -l < "$1" | tr -d ' '; }
show()  { head -n 15 "$1" | sed 's/^/[jetson-sync]     /'; [ "$(count "$1")" -gt 15 ] && echo "[jetson-sync]     ..."; return 0; }

# camera_ctl <restart|ensure> <dry 0|1> <new_ctl 0|1>
# restart: restart the camera service; ensure: start it only if it is not running.
# Runs on the Jetson with the script on stdin (so the holder patterns are not in the
# remote shell's own command line, which pgrep -f would otherwise match).
# new_ctl=1 (dry run only): the ctl script is in the host tree about to be synced.
read -r -d '' CAMCTL <<'EOF'
case "$t" in /*) ;; *) t="$HOME/$t";; esac
ctl="$t/tools/camera_link_ctl.sh"
if [ ! -f "$ctl" ] && ! { [ "$dry" = 1 ] && [ "$new_ctl" = 1 ]; }; then
  echo "notice: tools/camera_link_ctl.sh is not in the synced tree (is it committed in renee_perception?): camera service left alone"
  echo "RESULT skipped"; exit 0
fi
held=""
oldifs="$IFS"; IFS='|'
for p in $holders; do
  [ -n "$p" ] || continue
  rest="${p#?}"; first="${p%"$rest"}"
  if pgrep -f "[$first]$rest" >/dev/null 2>&1; then held="$held $p"; fi
done
IFS="$oldifs"
if [ -n "$held" ]; then
  echo "notice: the camera is held by:$held; camera service not touched (stop it, then run: bash $ctl start)"
  echo "RESULT skipped"; exit 0
fi
act="$action"
if [ "$action" = ensure ]; then
  if bash "$ctl" status </dev/null >/dev/null 2>&1; then echo "camera service is running"; echo "RESULT ok"; exit 0; fi
  act=start
fi
if [ "$dry" = 1 ]; then echo "dry run: would run tools/camera_link_ctl.sh $act"; echo "RESULT ok"; exit 0; fi
if bash "$ctl" "$act" </dev/null; then echo "camera service: $act ok"; echo "RESULT ok"
else echo "camera service: $act FAILED (see ~/.camera_link/ logs on the Jetson)"; echo "RESULT failed"; fi
EOF
camera_ctl() {
    local action="$1" dry="$2" new_ctl="$3" out
    out=$(printf 't=%q\nholders=%q\naction=%q\ndry=%q\nnew_ctl=%q\n%s\n' \
        "$TARGET" "$CAM_HOLDERS" "$action" "$dry" "$new_ctl" "$CAMCTL" | "${SSH[@]}" 'bash -s' 2>&1)
    echo "$out" | grep -v '^RESULT' | sed 's/^/[jetson-sync]   /'
    if echo "$out" | grep -q '^RESULT failed'; then warn "camera service $action failed"; return 1; fi
    return 0
}

if [ "$PREV" = "$VERSION" ]; then
    log "up to date on $TARGET_ABS (${VERSION:0:12}, $NFILES files)"
    [ -s "$TMP/localmod" ] && log "note: $(count "$TMP/localmod") file(s) edited on the Jetson since the last sync (left alone)"
    if [ "$CAM_RESTART" != 0 ] && [ "$CAM_AUTOSTART" != 0 ]; then
        camera_ctl ensure "${JETSON_SYNC_DRY_RUN:-0}" 0 || finish
    fi
    exit 0
fi

if [ -n "$PREV" ]; then FROM="at ${PREV:0:12}"; else FROM="has no sync record"; fi
log "Jetson $FROM -> host ${VERSION:0:12} ($MODE, $NFILES files) at $TARGET_ABS"
log "plan: $(count "$TMP/new_files") new, $(count "$TMP/changed") changed, $(count "$TMP/removed") removed from host (moved to backup)"
[ -s "$TMP/new_files" ] && { log "  new:";     show "$TMP/new_files"; }
[ -s "$TMP/changed" ]   && { log "  changed:"; show "$TMP/changed"; }
[ -s "$TMP/removed" ]   && { log "  removed:"; show "$TMP/removed"; }
[ -s "$TMP/kept_local" ] && { log "note: $(count "$TMP/kept_local") file(s) edited on the Jetson are left alone (host did not change them):"; show "$TMP/kept_local"; }

if [ "${JETSON_SYNC_DRY_RUN:-0}" = 1 ]; then
    if [ "$CAM_RESTART" != 0 ]; then
        new_ctl=0; [ -f "$STAGE/tools/camera_link_ctl.sh" ] && new_ctl=1
        camera_ctl restart 1 "$new_ctl"
    else
        log "dry run: camera service restart is disabled (JETSON_CAMERA_RESTART=0)"
    fi
    skip "dry run (JETSON_SYNC_DRY_RUN=1): nothing changed"
fi

# ---- consent for anything that overwrites work we cannot vouch for ----------
NEED=""
[ -s "$TMP/conflicts" ] && NEED="$(count "$TMP/conflicts") file(s) were edited on the Jetson since the last sync and would be overwritten/removed"
[ -z "$PREV" ] && [ -s "$TMP/changed" ] && NEED="no sync record yet: $(count "$TMP/changed") existing Jetson file(s) differ from the host's and would be overwritten"
if [ -n "$NEED" ]; then
    [ -s "$TMP/conflicts" ] && { log "  edited on the Jetson:"; show "$TMP/conflicts"; }
    if [ -z "$PREV" ]; then
        log "  existing Jetson files that differ from the host's (the host copy is expected to be the newer one and wins):"
        show "$TMP/changed"
        log "  the old versions are kept in ~/.renee_sync_backups/<timestamp>/ on the Jetson"
    fi
    if [ "${JETSON_SYNC_FORCE:-0}" = 1 ]; then
        log "JETSON_SYNC_FORCE=1: proceeding ($NEED); old versions are backed up"
    elif [ -t 0 ] && [ -t 1 ]; then
        read -r -p "[jetson-sync] $NEED. Overwrite (backup kept)? [y/N] " ans
        [ "$ans" = y ] || [ "$ans" = Y ] || { log "aborted, nothing changed"; finish; }
    else
        warn "REFUSING: $NEED. Nothing changed. If the host copy is the newer one (the expected case on a first sync), confirm with: docker compose run --rm jetson-code-sync (answer y at the prompt) or set JETSON_SYNC_FORCE=1; the old files are backed up. Review first with JETSON_SYNC_DRY_RUN=1"
        finish
    fi
fi

# ---- transfer into a staging dir, then install -----------------------------
TS=$(date +%Y%m%d_%H%M%S)
RSTAGE=".renee_sync_stage_${TS}_$$"
if ! tar -C "$STAGE" -c -T "$TMP/apply" | "${SSH[@]}" "mkdir -p $RSTAGE && tar -x -C $RSTAGE"; then
    warn "transfer to the Jetson failed, nothing changed"
    "${SSH[@]}" "rm -rf $RSTAGE" >/dev/null 2>&1; finish
fi
{ echo "# commit $VERSION source $MODE synced $(date -u +%FT%TZ) host $(hostname)"; cat "$TMP/manifest"; } > "$TMP/state"

read -r -d '' INSTALL <<'EOF'
case "$t" in /*) ;; *) t="$HOME/$t";; esac
stage="$HOME/$stage"; bk="$HOME/.renee_sync_backups/$ts"
mkdir -p "$t" "$bk" "$stage.meta"
sect=prune
while IFS= read -r line; do
  case "$line" in "##APPLY") sect=apply; continue;; "##STATE") sect=state; continue;; esac
  printf '%s\n' "$line" >> "$stage.meta/$sect"
done
touch "$stage.meta/prune" "$stage.meta/apply" "$stage.meta/state"
rsync -lpt -c --backup --backup-dir="$bk" --files-from="$stage.meta/apply" "$stage"/ "$t"/ </dev/null || { echo "RESULT rsync"; exit 11; }
while IFS= read -r p; do
  if [ -e "$t/$p" ]; then mkdir -p "$bk/$(dirname "$p")"; mv "$t/$p" "$bk/$p" && echo "pruned $p"; fi
done < "$stage.meta/prune"
cp "$stage.meta/state" "$t/.jetson_sync"
rm -rf "$stage" "$stage.meta"
rmdir "$bk" 2>/dev/null || echo "BACKUP $bk"
ls -1dt "$HOME"/.renee_sync_backups/* 2>/dev/null | tail -n +6 | xargs -r rm -rf
if [ -n "$post" ]; then (cd "$t" && SYNC_COMMIT="$version" eval "$post") && echo "hook JETSON_POST_SYNC_CMD ok" || echo "hook JETSON_POST_SYNC_CMD FAILED"; fi
echo "RESULT ok"
EOF
VARS="t=$(printf '%q' "$TARGET"); stage=$(printf '%q' "$RSTAGE"); ts=$TS; version=$(printf '%q' "$VERSION"); post=$(printf '%q' "$POST_CMD")"$'\n'
{ cat "$TMP/removed"; echo "##APPLY"; cat "$TMP/apply"; echo "##STATE"; cat "$TMP/state"; } | "${SSH[@]}" "$VARS$INSTALL" > "$TMP/install.out" 2>&1
sed 's/^/[jetson-sync]   /' "$TMP/install.out" | grep -v 'RESULT'
RES=$(sed -n 's/^RESULT //p' "$TMP/install.out" | tail -1)
case "$RES" in
  ok) log "synced ${VERSION:0:12} to $TARGET_ABS" ;;
  *) warn "install failed ($RES); the Jetson tree may be partly updated, backups are in ~/.renee_sync_backups/$TS; the sync record was not updated"; finish ;;
esac

# ---- camera service: always restart after a sync (not a systemd unit) ---------
if [ "$CAM_RESTART" != 0 ]; then
    camera_ctl restart 0 0 || finish
else
    log "camera service restart disabled (JETSON_CAMERA_RESTART=0)"
fi
exit 0
