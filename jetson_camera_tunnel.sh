#!/bin/bash
# Long-running SSH tunnel to the camera link service on the Jetson, run by the
# `jetson-camera-tunnel` compose service. The service listens on 127.0.0.1 on
# the Jetson (not reachable from the network), so the PC action server
# (capture_camera_frames_action_server, link_host 127.0.0.1) reaches it through
#     127.0.0.1:$JETSON_LINK_PORT  ->  jetson:127.0.0.1:$JETSON_LINK_REMOTE_PORT
# using the `jetson` alias set up by jetson_ssh_setup.sh (key in the jetson_ssh
# volume). The Jetson-side code and camera service are brought up by
# jetson_code_sync.sh, which this service starts after.
#
# Exit codes drive the compose `restart: on-failure` policy:
#   0  - the rover/Jetson is not reachable at start (sim-only host): nothing to do,
#        stay stopped.
#   !=0 - the tunnel dropped after it was up (wifi blip, Jetson reboot): restart.
#
# Note: the camera service accepts ONE client at a time and the newest connection
# wins, so this script never connects through the forward (no probing); readiness
# is judged from the ssh process and its local listener only.
set -u

PORT="${JETSON_LINK_PORT:-7788}"
REMOTE_PORT="${JETSON_LINK_REMOTE_PORT:-$PORT}"
BOARD_HOST="${VOGUI_HOST:-192.168.0.200}"
SSH_DIR=/home/robot/.ssh

log() { echo "[jetson-tunnel] $*"; }

if [ ! -f "$SSH_DIR/config" ]; then
    log "no ssh config in $SSH_DIR (jetson-ssh-setup has not run), exiting"
    exit 0
fi
if ! timeout 3 bash -c "exec 3<>/dev/tcp/$BOARD_HOST/22" 2>/dev/null; then
    log "$BOARD_HOST unreachable (not on the rover's network?), not starting the tunnel"
    exit 0
fi
# Listening check without `ss` (not in the image): state 0A in /proc/net/tcp.
HEXPORT=$(printf '%04X' "$PORT")
if awk -v a="0100007F:$HEXPORT" '$4=="0A" && $2==a {f=1} END{exit !f}' /proc/net/tcp; then
    log "WARNING: 127.0.0.1:$PORT is already in use (a manual tunnel?). Stop it or set JETSON_LINK_PORT." >&2
    exit 1
fi

log "tunnel 127.0.0.1:$PORT -> jetson:127.0.0.1:$REMOTE_PORT"
exec ssh -F "$SSH_DIR/config" -N \
    -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=8 \
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
    -L "127.0.0.1:$PORT:127.0.0.1:$REMOTE_PORT" jetson
