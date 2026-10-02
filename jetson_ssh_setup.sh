#!/bin/bash
# One-shot, idempotent SSH bootstrap for the Jetson behind the Vogui main board
# (the ZED camera host). Run by the `jetson-ssh-setup` compose service; the
# resulting /home/robot/.ssh volume is what every other service mounts, so
# `ssh jetson` works inside them without any per-host setup.
#
# What it does:
#   1. Generates a dedicated ed25519 key in the volume (once).
#   2. Writes ~/.ssh/config with the `vogui-board` and `jetson` aliases
#      (jetson is reached with ProxyJump through the main board).
#   3. If key login to the board or the Jetson does not work yet, installs this
#      container's public key AND the host's public key (if mounted at
#      /host_id.pub) into authorized_keys on both, using the passwords from
#      .env (VOGUI_PASSWORD, JETSON_PASSWORD) or, when run with a TTY, by
#      prompting. Afterwards the host can reach the Jetson without a password:
#          ssh -J robot@192.168.0.200 jetson@192.168.1.60
#      (or via the `jetson` alias, see ssh_config.jetson).
#
# Host keys are trusted on first use (StrictHostKeyChecking accept-new); a
# *changed* host key is still refused. Non-fatal by design: it always exits 0
# so a sim-only host or an unreachable robot never blocks other services.
set -u

SSH_DIR=/home/robot/.ssh
BOARD_USER="${VOGUI_SSH_USER:-robot}"
BOARD_HOST="${VOGUI_HOST:-192.168.0.200}"
JETSON_USER="${JETSON_SSH_USER:-jetson}"
JETSON_HOST="${JETSON_HOST:-192.168.1.60}"
HOST_PUBKEY=/host_id.pub
CFG="$SSH_DIR/config"
KEY="$SSH_DIR/id_ed25519"

log()  { echo "[jetson-ssh] $*"; }
warn() { echo "[jetson-ssh] WARNING: $*" >&2; }

mkdir -p "$SSH_DIR"

if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "renee-sim-container" -f "$KEY" && log "generated $KEY"
fi

cat > "$CFG" <<EOF
Host vogui-board
    HostName $BOARD_HOST
    User $BOARD_USER

Host jetson
    HostName $JETSON_HOST
    User $JETSON_USER
    ProxyJump vogui-board

Host vogui-board jetson
    IdentityFile $KEY
    IdentitiesOnly yes
    UserKnownHostsFile $SSH_DIR/known_hosts
    StrictHostKeyChecking accept-new
    ServerAliveInterval 15
    ServerAliveCountMax 3
EOF

fix_perms() {
    chown -R 1000:1000 "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chmod 600 "$KEY" "$CFG" 2>/dev/null
    chmod 644 "$KEY.pub" "$SSH_DIR/known_hosts" 2>/dev/null
    return 0
}
trap fix_perms EXIT

SSH=(ssh -F "$CFG" -o ConnectTimeout=6)

key_login_ok() { "${SSH[@]}" -o BatchMode=yes "$1" true 2>/dev/null; }

# ssh asks for "user@host's password:"; answer from the matching variable.
ASKPASS=$(mktemp)
cat > "$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *"@$BOARD_HOST"*)  [ -n "${VOGUI_PASSWORD:-}" ]  && printf '%s' "$VOGUI_PASSWORD" ;;
  *"@$JETSON_HOST"*) [ -n "${JETSON_PASSWORD:-}" ] && printf '%s' "$JETSON_PASSWORD" ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$ASKPASS"
trap 'rm -f "$ASKPASS"; fix_perms' EXIT
export BOARD_HOST JETSON_HOST

# Keys to authorise: this container's, plus the host's when it was mounted.
KEYS="$(cat "$KEY.pub")"
if [ -s "$HOST_PUBKEY" ] && [ -f "$HOST_PUBKEY" ]; then
    KEYS="$KEYS"$'\n'"$(cat "$HOST_PUBKEY")"
else
    warn "no host public key at $HOST_PUBKEY (set HOST_SSH_PUBKEY_FILE in .env); only the container key will be installed"
fi

# install_keys <alias> <password-var>
install_keys() {
    local target="$1" pw_var="$2" opts=()
    if [ -n "${!pw_var:-}" ]; then
        opts=(-o NumberOfPasswordPrompts=1)
        export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force
    elif [ -t 0 ]; then
        log "no $pw_var set, prompting for the $target password"
        unset SSH_ASKPASS SSH_ASKPASS_REQUIRE
    else
        warn "key login to $target failed and $pw_var is unset (and no TTY): skipping. Set it in .env or run: docker compose run --rm jetson-ssh-setup"
        return 1
    fi
    printf '%s\n' "$KEYS" | "${SSH[@]}" "${opts[@]}" "$target" \
        'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys;
         while IFS= read -r k; do [ -n "$k" ] && { grep -qxF "$k" ~/.ssh/authorized_keys || echo "$k" >> ~/.ssh/authorized_keys; }; done' \
        2>&1 | sed 's/^/[jetson-ssh]   /'
    [ "${PIPESTATUS[1]}" -eq 0 ]
}

if ! timeout 3 bash -c "exec 3<>/dev/tcp/$BOARD_HOST/22" 2>/dev/null; then
    log "$BOARD_HOST unreachable (not on the rover's network?), skipping"
    exit 0
fi

if key_login_ok vogui-board; then
    log "vogui-board: key login already works"
else
    log "vogui-board: installing keys"
    install_keys vogui-board VOGUI_PASSWORD || warn "could not install keys on vogui-board"
fi

# The Jetson is only reachable through the board, so this needs board key login.
if key_login_ok jetson; then
    log "jetson: key login already works"
elif ! key_login_ok vogui-board; then
    warn "skipping jetson: vogui-board key login is not working yet"
else
    log "jetson: installing keys"
    install_keys jetson JETSON_PASSWORD || warn "could not install keys on jetson"
fi

if key_login_ok jetson; then
    log "OK: 'ssh jetson' works from containers; from the host use: ssh -J $BOARD_USER@$BOARD_HOST $JETSON_USER@$JETSON_HOST"
else
    warn "'ssh jetson' still does not work (check JETSON_PASSWORD, the Jetson's IP $JETSON_HOST, and that it is powered)"
fi
exit 0
