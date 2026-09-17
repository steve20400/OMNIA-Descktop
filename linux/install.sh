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
  cp "$SCRIPT_DIR/dev.omnia.omnia.desktop" "$APP_DIR/"
elif [ -f "$ROOT_DIR/linux/dev.omnia.omnia.desktop" ]; then
  cp "$ROOT_DIR/linux/dev.omnia.omnia.desktop" "$APP_DIR/"
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
fi

# 4. Icône pixmaps pour compatibilité maximale (menus GNOME / KDE / XFCE)
if [ -f "$SCRIPT_DIR/dev.omnia.omnia.png" ]; then
  cp "$SCRIPT_DIR/dev.omnia.omnia.png" "$PIXMAPS_DIR/dev.omnia.omnia.png"
elif [ -f "$ROOT_DIR/linux/dev.omnia.omnia.png" ]; then
  cp "$ROOT_DIR/linux/dev.omnia.omnia.png" "$PIXMAPS_DIR/dev.omnia.omnia.png"
fi

# 5. Mise à jour des bases de données et caches d'icônes
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_BASE" || true
fi

echo "Installation d'OMNIA terminée avec succès !"
