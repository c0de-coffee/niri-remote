#!/bin/bash
# On the host: start kde-e2e.sh in the container as rltest, connect with xfreerdp3, collect logs.
# Usage: kde-e2e-run.sh [seconds] [extra xfreerdp3 args...]
DUR="${1:-15}"; shift
PORT=3398
SSH="$HOME/.local/share/niri-rl/ssh"
$SSH "systemctl --user -M rltest@ stop kde-e2e 2>/dev/null; systemctl --user -M rltest@ reset-failed kde-e2e 2>/dev/null; systemd-run -q -M rltest@ --user --unit kde-e2e \
  -p RuntimeMaxSec=$((DUR + 20)) -E PORT=$PORT -E CLIENT='${CLIENT:-}' -E BRIDGE_LOG='${BRIDGE_LOG:-}' -E KWIN_LOG_RULES='${KWIN_LOG_RULES:-}' -E PW_MON='${PW_MON:-}' \
  /opt/niri/remote-login-tests/container/kde-e2e.sh"
for i in $(seq 1 50); do ss -ltnH "sport = :$PORT" | grep -q . && break; sleep 0.3; done
if [ -n "${SHOT:-}" ]; then
  # xfreerdp3 on a hidden Xvfb in the container, screenshot after $SHOT_AFTER seconds into $SHOT
  # (a host path). Nothing shows up on the host's screen.
  $SSH "pkill -x Xvfb 2>/dev/null; (Xvfb :77 -screen 0 1400x800x24 >/dev/null 2>&1 &); sleep 1
    (DISPLAY=:77 timeout $DUR xfreerdp3 /v:127.0.0.1:$PORT /u:test /p:test /cert:ignore /size:1280x720 $* > /tmp/kde-e2e-rdp.log 2>&1 &)
    sleep ${SHOT_AFTER:-6}; ${SHOT_CMD:-true}; sleep 1
    xwd -root -display :77 -silent | ffmpeg -loglevel error -y -i - /tmp/kde-e2e-shot.png
    sleep \$(( $DUR - ${SHOT_AFTER:-6} )); pkill -x Xvfb"
  scp -q -i "$HOME/.local/share/niri-rl/id_ed25519" -P 2222 -o UserKnownHostsFile="$HOME/.local/share/niri-rl/known_hosts" \
    root@127.0.0.1:/tmp/kde-e2e-shot.png "$SHOT" && echo "[e2e] screenshot: $SHOT"
else
  timeout "$DUR" xfreerdp3 /v:127.0.0.1:$PORT /u:test /p:test /cert:ignore /size:1280x720 "$@" > /tmp/kde-e2e-rdp.log 2>&1
  echo "[e2e] xfreerdp3 exit: $?"
fi
$SSH "systemctl --user -M rltest@ stop kde-e2e; cd /tmp/kde-e2e; for f in bridge grd kwin; do echo \"=== \$f\"; tail -n ${LOG_LINES:-40} \$f.log; done"
