#!/bin/bash
# On the host: connect to the container's system grd (remote login, port 3393) with xfreerdp3 on a
# hidden Xvfb in the container. Takes screenshots into $OUTDIR at the given times; before each
# one, runs the matching STEP_<n> command (xdotool etc., DISPLAY=:77). Then prints the logs.
# Usage: kde-login-shot.sh DURATION T1 [T2 ...]
DUR=$1; shift
OUTDIR=${OUTDIR:?}; mkdir -p "$OUTDIR"
R=$HOME/.local/share/niri-rl/ssh
since=$($R 'date "+%Y-%m-%d %H:%M:%S"')
steps=""; prev=0; n=1
for t in "$@"; do
  cmd_var="STEP_$n"; cmd="${!cmd_var:-true}"
  steps+="sleep $((t - prev)); export DISPLAY=:77; $cmd; sleep 1; xwd -root -display :77 -silent | ffmpeg -loglevel error -y -i - /tmp/kde-login-$n.png; "
  prev=$((t + 1)); n=$((n + 1))
done
$R "pkill -x Xvfb; (Xvfb :77 -screen 0 1400x800x24 >/dev/null 2>&1 &); sleep 1; rm -f /tmp/kde-login-*.png
  (DISPLAY=:77 timeout $DUR xfreerdp3 /v:127.0.0.1:3393 /u:rdp /p:rdp /cert:ignore /size:1280x720 ${RDP_ARGS:-} > /tmp/kde-login-rdp.log 2>&1 &)
  $steps
  sleep \$(( $DUR - $prev > 0 ? $DUR - $prev : 0 )); pkill -x Xvfb; true"
for i in $(seq 1 $((n - 1))); do
  scp -q -i "$HOME/.local/share/niri-rl/id_ed25519" -P 2222 -o UserKnownHostsFile="$HOME/.local/share/niri-rl/known_hosts" \
    root@127.0.0.1:/tmp/kde-login-$i.png "$OUTDIR/login-$i.png" && echo "[login] $OUTDIR/login-$i.png"
done
$R "journalctl --since '$since' --no-pager -o cat | grep -v '^\s*$'" > "$OUTDIR/journal.log"
echo "[login] journal: $OUTDIR/journal.log ($(wc -l < "$OUTDIR/journal.log") lines)"
