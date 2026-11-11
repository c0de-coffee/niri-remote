#!/bin/bash
# On the host: build niri-remote-desktop-git (from this repository) and remote-dm-git (from
# $REMOTE_DM_REPO, default ~/remote-dm) from their current working trees (uncommitted changes
# included, via throwaway clones with one temporary commit) and install them in the container with
# pacman -U.
#
# usage: install-packages.sh [niri|remote-dm|all]   (default all; niri takes a few minutes)
#
# Build dirs live under ~/.cache/niri-pkgbuild (niri's release build doesn't fit in /tmp);
# packages end up in $OUT. Nothing is written into the repository.
set -euo pipefail

WHAT=${1:-all}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
REMOTE_DM_REPO=${REMOTE_DM_REPO:-$HOME/remote-dm}
OUT=${OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/niri-pkgbuild/out}
WORK=${XDG_CACHE_HOME:-$HOME/.cache}/niri-pkgbuild
R=$HOME/.local/share/niri-rl/ssh

mkdir -p "$WORK" "$OUT"

snapshot() { # repo snapshot-dir
  local repo=$1 snapshot=$2
  rm -rf "$snapshot"
  git clone -q --branch "$(git -C "$repo" branch --show-current)" "$repo" "$snapshot"
  git -C "$repo" diff --binary HEAD | git -C "$snapshot" apply --allow-empty
  git -C "$repo" ls-files --others --exclude-standard -z \
    | (cd "$repo" && tar --null -cf - -T -) | tar -xf - -C "$snapshot"
  git -C "$snapshot" add -A
  git -C "$snapshot" -c user.name=snapshot -c user.email=snapshot@invalid \
    commit -qm "snapshot of the working tree" --allow-empty
}

build() { # package repo snapshot-dir
  local dir=$2/packaging/$1 snapshot=$3 pkgbuild branch
  # makepkg rewrites pkgver in the PKGBUILD; build from a copy.
  pkgbuild=$WORK/$1
  rm -rf "$pkgbuild"
  mkdir -p "$pkgbuild"
  cp "$dir/PKGBUILD" "$pkgbuild/"
  snapshot "$2" "$snapshot"
  branch=$(git -C "$snapshot" branch --show-current)
  (cd "$pkgbuild" && NIRI_REPO=$snapshot NIRI_BRANCH=$branch \
    REMOTE_DM_REPO=$snapshot REMOTE_DM_BRANCH=$branch \
    BUILDDIR=$WORK/build SRCDEST=$WORK/src PKGDEST=$OUT makepkg -fd --nocheck --noconfirm \
    > "$WORK/$1.log" 2>&1) || { tail -20 "$WORK/$1.log"; exit 1; }
  ls -t "$OUT"/"$1"-[0-9r]*-x86_64.pkg.tar.zst | head -1
}

build_niri() { build niri-remote-desktop-git "$REPO" "$WORK/snapshot"; }
build_remote_dm() { build remote-dm-git "$REMOTE_DM_REPO" "$WORK/snapshot-remote-dm"; }

pkgs=()
case $WHAT in
  niri) pkgs+=("$(build_niri)") ;;
  remote-dm) pkgs+=("$(build_remote_dm)") ;;
  all) pkgs+=("$(build_remote_dm)" "$(build_niri)") ;;
  *) echo "usage: $0 [niri|remote-dm|all]" >&2; exit 2 ;;
esac

remote=()
for pkg in "${pkgs[@]}"; do
  name=$(basename "$pkg")
  $R "mkdir -p /root/pkgs && cat > /root/pkgs/$name" < "$pkg"
  remote+=("/root/pkgs/$name")
done
$R "set -o pipefail; pacman -U --noconfirm ${remote[*]} | tail -3 && systemctl try-restart remote-dm" \
  || { echo "[install-packages] pacman failed" >&2; exit 1; }
echo "[install-packages] installed: ${pkgs[*]##*/}"
