# gnome-remote-desktop patches

Optional patches on top of gnome-remote-desktop 51.0 for remote login with niri or KDE. Remote login
with niri works without them.

| Patch | |
|---|---|
| `0001-clipboard-rdp-Convert-text-with-WinPR-s-UTF-8-format.patch` | Non-ASCII text copied on the RDP client arrives as `\uXXXX` escapes with FreeRDP ≥ 3.32.2. Not upstream yet. |
| `0002-rdp-pipewire-stream-Tell-the-compositor-where-each-v.patch` | With several client monitors, niri doesn't know how the client arranges them or which one is primary: "monitor on the left/right" actions go the wrong way and windows open on the first monitor rather than the primary one. Adds each monitor's client position and primary flag next to its preferred scale. Optional; without it niri lays them out in creation order. Not upstream yet. |
| `0003-hwaccel-vulkan-Only-offer-single-plane-modifiers-for.patch` | grd offers multi-plane modifiers for its PipeWire streams but refuses multi-plane buffers. KWin (KDE) picks AMD's two-plane DCC modifiers, so the remote session ends right away with "Expected exactly 1 plane". **Needed for KDE on AMD**; niri doesn't need it. Not upstream yet. |
| `0004-session-Read-the-EIS-keymap-from-the-start.patch` | KWin (KDE) gives every EIS client the same keymap file, and grd reads it from wherever the shared offset is: reconnecting to a KDE session gets an empty keymap, "Keyboard layout was empty", and grd drops the connection. **Needed for KDE**; niri doesn't need it. Not upstream yet. |
| `0005-pipewire-utils-Ignore-buffers-flagged-as-corrupted.patch` | KWin (KDE) sends pointer-only screencast buffers with the old picture in them, flagged "corrupted" (PipeWire for "don't look at the contents"); grd only checks for an empty buffer like mutter sends, so the picture flickers back to old frames whenever the pointer moves. **Needed for KDE**; niri doesn't need it. Not upstream yet. |
| `0006-daemon-handover-Find-the-handover-again-after-the-sy.patch` | After the system daemon restarts (e.g. on a grd update), the `grd --handover` in an existing session often asks for its handover before the new daemon has registered the session again, then waits for an object-added signal that never comes (and would fail its session lookup anyway, as a user service isn't in a logind session). Reconnecting to that session then shows a black screen until it's logged out. Affects niri and KDE alike. Not upstream yet. |

On Arch, [`packaging/gnome-remote-desktop/build.sh`](../../packaging/gnome-remote-desktop/build.sh)
builds Arch's package with these patches applied, as pkgrel N.1 (so an Arch update to N+1
replaces it again; check whether the patches are still needed then):

```sh
packaging/gnome-remote-desktop/build.sh
sudo pacman -U ~/.cache/niri-pkgbuild/gnome-remote-desktop/gnome-remote-desktop-[0-9]*.pkg.tar.zst
```

It needs the package's build dependencies; `MAKEPKG_FLAGS=-s` lets makepkg install them.
