#!/bin/bash
# Inside the niri-rl container, as root: install kwin-mutter-bridge and switch remote-dm to KDE
# (KDE=0 switches back to the niri config). remote-dm's KDE files come with its package
# (install-packages.sh remote-dm). The bridge is its own repo (~/kwin-mutter-bridge), which the
# container can't see, so copy the binary in first, from the host:
#   ~/.local/share/niri-rl/ssh 'cat > /tmp/kwin-mutter-bridge' < ~/kwin-mutter-bridge/target/release/kwin-mutter-bridge
set -euo pipefail
BRIDGE=${BRIDGE:-/tmp/kwin-mutter-bridge}
if [ "${KDE:-1}" = 0 ]; then
  [ -f /etc/remote-dm/config.toml.niri ] && cp /etc/remote-dm/config.toml.niri /etc/remote-dm/config.toml
  systemctl restart remote-dm; echo "remote-dm back to niri"; exit 0
fi
install -Dm755 "$BRIDGE" /usr/local/bin/kwin-mutter-bridge
rm -rf /etc/systemd/user/plasma-kwin_wayland.service.d  # from an earlier version of this script
[ -f /etc/remote-dm/config.toml.niri ] || cp /etc/remote-dm/config.toml /etc/remote-dm/config.toml.niri
cat > /etc/remote-dm/config.toml <<'CONF'
# KDE test config (the niri one is in config.toml.niri; kde-install.sh with KDE=0 restores it).
[greeter]
command = "exec /usr/lib/remote-dm/kde-greeter"

[session]
command = "systemctl --user restart gnome-remote-desktop-handover.service; exec startplasma-wayland"
CONF
systemctl restart remote-dm
echo "remote-dm switched to KDE"
