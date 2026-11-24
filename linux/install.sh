#!/usr/bin/env bash
# Installation d'OMNIA pour Linux (système ou utilisateur courant).
# Installe le binaire, le lanceur .desktop, les icônes SVG et PNG hicolor, et met à jour les caches.
set -euo pipefail

DEST_PREFIX="${DEST_PREFIX:-/usr/local}"
if [ "$EUID" -ne 0 ] && [ "$DEST_PREFIX" = "/usr/local" ]; then
  DEST_PREFIX="$HOME/.local"
fi

BIN_DIR="$DEST_PREFIX/bin"
APP_DIR="$DEST_PREFIX/share/applications"
ICON_BASE="$DEST_PREFIX/share/icons/hicolor"
PIXMAPS_DIR="$DEST_PREFIX/share/pixmaps"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installation d'OMNIA dans $DEST_PREFIX..."

mkdir -p "$BIN_DIR" "$APP_DIR" "$PIXMAPS_DIR"

# Fermeture propre de toute instance active avant mise à niveau en place
pkill -x omnia 2>/dev/null || true

# 0. libmpv, la bibliothèque de lecture, n'est pas dans l'archive : sans elle,
# OMNIA ne lit ni son ni image. Installé pour tout le système, le script a les
# droits de l'installer lui-même, comme le ferait un paquet .deb ou .rpm.
libmpv_present() {
  ldconfig -p 2>/dev/null | grep -q 'libmpv\.so\.2'
}
if ! libmpv_present && [ "$EUID" -eq 0 ]; then
  echo "Installation de libmpv (lecture audio et vidéo)..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y libmpv2 >/dev/null 2>&1 ||
      { apt-get update >/dev/null 2>&1 && apt-get install -y libmpv2 >/dev/null 2>&1; } || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y mpv-libs >/dev/null 2>&1 || true
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install libmpv2 >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm --needed mpv >/dev/null 2>&1 || true
  fi
  ldconfig 2>/dev/null || true
fi
if ! libmpv_present; then
  echo
  if ldconfig -p 2>/dev/null | grep -q 'libmpv\.so\.1'; then
    echo "Attention : ce système n'a que l'ancienne libmpv (libmpv.so.1)."
    echo "OMNIA demande libmpv 2 : Ubuntu 24.04, Debian 13, Fedora 39 ou plus récent."
  else
    echo "Attention : libmpv est introuvable, et OMNIA ne pourra rien lire."
    echo "Installez-la, puis relancez OMNIA :"
    echo "    Ubuntu, Debian : sudo apt install libmpv2"
    echo "    Fedora (RPM Fusion) : sudo dnf install mpv-libs"
    echo "    Arch : sudo pacman -S mpv"
  fi
  echo
fi

# 1. Binaire / Bundle
if [ -d "$ROOT_DIR/build/linux/x64/release/bundle" ]; then
  BUNDLE_DIR="$DEST_PREFIX/opt/omnia"
  mkdir -p "$BUNDLE_DIR"
  cp -r "$ROOT_DIR/build/linux/x64/release/bundle/"* "$BUNDLE_DIR/"
  ln -sf "$BUNDLE_DIR/omnia" "$BIN_DIR/omnia"
elif [ -f "$SCRIPT_DIR/omnia" ]; then
  cp "$SCRIPT_DIR/omnia" "$BIN_DIR/omnia"
fi

# 2. Fichier .desktop
if [ -f "$SCRIPT_DIR/dev.omnia.omnia.desktop" ]; then
  cp "$SCRIPT_DIR/dev.omnia.omnia.desktop" "$APP_DIR/dev.omnia.omnia.desktop"
  cp "$SCRIPT_DIR/dev.omnia.omnia.desktop" "$APP_DIR/omnia.desktop"
elif [ -f "$ROOT_DIR/linux/dev.omnia.omnia.desktop" ]; then
  cp "$ROOT_DIR/linux/dev.omnia.omnia.desktop" "$APP_DIR/dev.omnia.omnia.desktop"
  cp "$ROOT_DIR/linux/dev.omnia.omnia.desktop" "$APP_DIR/omnia.desktop"
fi

# 3. Icônes Hicolor (SVG vectoriel et matriciel PNG toutes résolutions)
ICONS_SRC=""
if [ -d "$SCRIPT_DIR/icons/hicolor" ]; then
  ICONS_SRC="$SCRIPT_DIR/icons/hicolor"
elif [ -d "$ROOT_DIR/linux/icons/hicolor" ]; then
  ICONS_SRC="$ROOT_DIR/linux/icons/hicolor"
fi

if [ -n "$ICONS_SRC" ]; then
  cp -r "$ICONS_SRC"/* "$ICON_BASE/"
  for icon in "$ICON_BASE"/*/apps/dev.omnia.omnia.*; do
    if [ -f "$icon" ]; then
      dir=$(dirname "$icon")
      ext="${icon##*.}"
      cp -f "$icon" "$dir/omnia.$ext" 2>/dev/null || true
    fi
  done
fi

# 4. Icône pixmaps pour compatibilité maximale (menus GNOME / KDE / XFCE)
if [ -f "$SCRIPT_DIR/dev.omnia.omnia.png" ]; then
  cp "$SCRIPT_DIR/dev.omnia.omnia.png" "$PIXMAPS_DIR/dev.omnia.omnia.png"
  cp "$SCRIPT_DIR/dev.omnia.omnia.png" "$PIXMAPS_DIR/omnia.png"
elif [ -f "$ROOT_DIR/linux/dev.omnia.omnia.png" ]; then
  cp "$ROOT_DIR/linux/dev.omnia.omnia.png" "$PIXMAPS_DIR/dev.omnia.omnia.png"
  cp "$ROOT_DIR/linux/dev.omnia.omnia.png" "$PIXMAPS_DIR/omnia.png"
fi

# 5. Mise à jour des bases de données et caches d'icônes
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_BASE" || true
fi

# 6. Pare-feu : OMNIA Connect reçoit le téléphone sur le port 41530. Un
# pare-feu actif (ufw sur Ubuntu, firewalld ailleurs) refuse par défaut toute
# connexion entrante, et l'appairage échouait sans rien dire. Installé pour
# tout le système, le script a les droits : il ouvre ce seul port, en TCP.
# Sans droits, OMNIA le proposera lui-même au premier appairage.
if [ "$EUID" -eq 0 ]; then
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "^status: active"; then
    ufw allow 41530/tcp comment 'OMNIA Connect' >/dev/null 2>&1 &&
      echo "Pare-feu (ufw) : OMNIA Connect autorisé sur le port 41530/tcp." || true
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    { firewall-cmd --permanent --add-port=41530/tcp && firewall-cmd --reload; } >/dev/null 2>&1 &&
      echo "Pare-feu (firewalld) : OMNIA Connect autorisé sur le port 41530/tcp." || true
  fi
fi

echo "Installation d'OMNIA terminée avec succès !"
