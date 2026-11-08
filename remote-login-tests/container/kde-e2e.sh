#!/bin/bash
# KDE end-to-end test, run inside the niri-rl container as a user (via kde-e2e-run.sh):
# headless KWin + kwin-mutter-bridge + gnome-remote-desktop --headless + konsole.
# Connect from the host with xfreerdp3 to 127.0.0.1:$PORT (user test / test).
set -u
T=/tmp/kde-e2e; PORT="${PORT:-3398}"
BRIDGE="${BRIDGE:-/usr/local/bin/kwin-mutter-bridge}"  # from kde-install.sh
rm -rf "$T"; mkdir -p "$T"/{config,data,cache}
export XDG_CONFIG_HOME="$T/config" XDG_DATA_HOME="$T/data" XDG_CACHE_HOME="$T/cache"
export GSETTINGS_BACKEND=keyfile
openssl req -new -newkey rsa:2048 -days 7 -nodes -x509 -subj /CN=kde-test \
  -keyout "$T/tls.key" -out "$T/tls.crt" >/dev/null 2>&1
mkdir -p "$XDG_CONFIG_HOME/glib-2.0/settings"
cat > "$XDG_CONFIG_HOME/glib-2.0/settings/keyfile" <<KEYS
[org/gnome/desktop/remote-desktop/rdp]
tls-cert='$T/tls.crt'
tls-key='$T/tls.key'
[org/gnome/desktop/remote-desktop/rdp/headless]
enable=true
port=uint16 $PORT
negotiate-port=false
KEYS
timeout 10 grdctl --headless rdp set-credentials test test || echo "[e2e] set-credentials failed"

# Runs inside KWin (it is KWin's child, so it has WAYLAND_DISPLAY).
cat > "$T/inside.sh" <<INNER
#!/bin/bash
RUST_LOG=\${BRIDGE_LOG:-kwin_mutter_bridge=debug} "$BRIDGE" > "$T/bridge.log" 2>&1 &
for i in \$(seq 1 50); do busctl --user status org.gnome.Mutter.ScreenCast >/dev/null 2>&1 && break; sleep 0.2; done
[ -n "${PW_MON:-}" ] && pw-mon -N > "$T/pwmon.log" 2>&1 &
${CLIENT:-konsole} > "$T/client.log" 2>&1 &
G_MESSAGES_DEBUG=all /usr/lib/gnome-remote-desktop-daemon --headless > "$T/grd.log" 2>&1
INNER
chmod +x "$T/inside.sh"
QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="${KWIN_LOG_RULES:-}" exec kwin_wayland --virtual --width 1280 --height 720 --socket wl-kde-e2e --no-lockscreen \
  "$T/inside.sh" > "$T/kwin.log" 2>&1
