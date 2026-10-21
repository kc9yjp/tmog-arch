#!/usr/bin/env bash
# Build and install Dave Plummer's Task Manager TMOG (https://tmog.org) on Arch.
#
# TMOG is closed source, so "build" means: download the official Linux
# tarball, wrap it in a pacman package with makepkg, and install that package.
# Using pacman (rather than copying files into /usr) means it can be removed
# cleanly with `sudo pacman -R tmog`.
#
# Usage: ./install-tmog.sh [version]
#   version  optional, e.g. 1.0.0. Default: newest Linux tarball linked on tmog.org.
#
# Env: TMOG_BUILD_DIR  where to build (default: a temp dir, deleted afterwards)
#      TMOG_PKG_DIR    where the built .pkg.tar.zst is kept (default: this script's dir)
set -euo pipefail

pkgdir_out="$(realpath "${TMOG_PKG_DIR:-$(dirname -- "${BASH_SOURCE[0]}")}")"

BASE_URL="https://tmog.org"
PKGNAME="tmog"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }

[[ $EUID -ne 0 ]] || die "run as a normal user; makepkg will sudo for the install step"
command -v makepkg >/dev/null || die "makepkg not found (this script targets Arch-based systems)"
command -v curl >/dev/null || die "curl not found"

case "$(uname -m)" in
  x86_64)  carch=x86_64 ;;
  aarch64) carch=aarch64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# Resolve the version: the version.txt feed can run ahead of the files actually
# published, so trust the download link on the home page.
version="${1:-}"
if [[ -z $version ]]; then
  log "Looking up latest release on $BASE_URL"
  version="$(curl -fsSL --connect-timeout 15 --max-time 30 --retry 3 --retry-all-errors "$BASE_URL/" \
    | grep -oE "TaskManagerOG-[0-9][0-9.]*-linux-${carch}\.tar\.gz" \
    | sed -E 's/^TaskManagerOG-(.*)-linux-.*/\1/' \
    | sort -uV | tail -n1)" || true
  [[ -n $version ]] || die "could not find a Linux tarball link on $BASE_URL; pass a version explicitly"
fi
tarball="TaskManagerOG-${version}-linux-${carch}.tar.gz"
url="$BASE_URL/rtm/downloads/$tarball"
log "Version $version ($carch)"

if [[ -n ${TMOG_BUILD_DIR:-} ]]; then
  builddir="$TMOG_BUILD_DIR"
  mkdir -p "$builddir"
else
  builddir="$(mktemp -d -t tmog-build.XXXXXX)"
  trap 'rm -rf "$builddir"' EXIT
fi

log "Downloading $url"
curl -fL --retry 3 -o "$builddir/$tarball" "$url" || die "download failed: $url"
sha256="$(sha256sum "$builddir/$tarball" | cut -d' ' -f1)"
log "sha256 $sha256"

# Upstream ships a self-contained /usr-style tree (bin, libexec, share). The
# libexec screensaver wrapper finds its binary via ../../bin, so the tree is
# installed as-is under /usr to keep those relative paths valid.
cat > "$builddir/PKGBUILD" <<EOF
pkgname=$PKGNAME
pkgver=$version
pkgrel=2
pkgdesc="Task Manager TMOG, a native Qt 6 system monitor and task manager by Dave Plummer"
arch=('$carch')
url='$BASE_URL/'
license=('LicenseRef-proprietary')
depends=('glibc' 'gcc-libs' 'hicolor-icon-theme' 'libxcb' 'libglvnd' 'qt6-base'
         'qt6-svg' 'qt6-multimedia' 'systemd-libs')
optdepends=('qt6-wayland: native Wayland support'
            'python: tmog-register-screensaver helper'
            'xscreensaver: use TMOG as a screensaver')
conflicts=('tmog-bin')
provides=('tmog-bin')
options=('!strip' '!debug')
source=('$tarball')
sha256sums=('$sha256')

package() {
  local root="\$srcdir/TaskManagerOG-\$pkgver-linux-\$CARCH"
  [[ -d \$root ]] || { echo "unexpected tarball layout" >&2; return 1; }

  install -d "\$pkgdir/usr"
  cp -a "\$root/bin" "\$root/libexec" "\$root/share" "\$pkgdir/usr/"
  # Debian-style copyright file is redundant with the license install below.
  rm -rf "\$pkgdir/usr/share/doc/taskmanagerog"

  install -d "\$pkgdir/usr/share/licenses/\$pkgname"
  for f in "\$pkgdir"/usr/share/doc/tmog/*; do
    ln -s "/usr/share/doc/tmog/\${f##*/}" "\$pkgdir/usr/share/licenses/\$pkgname/"
  done

  # Short CLI name: \`tmog\` launches the task manager.
  ln -s tmog-task-manager "\$pkgdir/usr/bin/tmog"

  # Make the launcher entry findable as "tmog" and run it via the short name.
  local desktop="\$pkgdir/usr/share/applications/com.tmog.taskmanager.desktop"
  sed -i -e 's/^Exec=tmog-task-manager\$/Exec=tmog/' \
         -e '/^Categories=/a GenericName=Task Manager\nKeywords=tmog;task;manager;process;system;monitor;' \
         "\$desktop"

  chmod -R u=rwX,go=rX "\$pkgdir/usr"
  chmod 755 "\$pkgdir"/usr/bin/tmog-* "\$pkgdir"/usr/libexec/xscreensaver/*
}
EOF

log "Building package in $builddir"
cd "$builddir"
makepkg --syncdeps --cleanbuild --noconfirm
pkgfile="$(makepkg --packagelist | head -n1)"
mkdir -p "$pkgdir_out"
cp -f "$pkgfile" "$pkgdir_out/"
pkgfile="$pkgdir_out/${pkgfile##*/}"
log "Package saved to $pkgfile"

log "Installing with pacman (needs sudo)"
if ! sudo pacman -U --needed --noconfirm "$pkgfile"; then
  printf '\nerror: install step failed (sudo needs a terminal to ask for your password).\n' >&2
  printf 'Install the built package from a terminal with:\n  sudo pacman -U %q\n' "$pkgfile" >&2
  exit 1
fi

if pacman -Q qt6-wayland >/dev/null 2>&1; then :; elif [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  log "Tip: you're on Wayland; 'sudo pacman -S qt6-wayland' for native Wayland support"
fi
log "Installed $(pacman -Q "$PKGNAME"). Run: tmog   (remove: sudo pacman -R $PKGNAME)"
