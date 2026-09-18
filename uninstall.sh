#!/usr/bin/env bash
# ==============================================================================
# Script de désinstallation d'OMNIA (Ubuntu / Debian / Linux)
# ==============================================================================
# Ce script supprime proprement toute version précédente d'OMNIA afin de
# permettre une réinstallation saine (paquet .deb, archive /opt/omnia,
# liens symboliques, lanceurs .desktop, icônes et caches du bureau).
# ==============================================================================

set -e

echo "=== Désinstallation d'OMNIA ==="

# 1. Désinstallation si installé via paquet Debian (.deb / dpkg / apt)
if command -v dpkg >/dev/null 2>&1; then
    for pkg in omnia dev.omnia.omnia OMNIA; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "--> Suppression du paquet système $pkg via apt/dpkg..."
            sudo apt-get remove --purge -y "$pkg" 2>/dev/null || sudo dpkg -r "$pkg" 2>/dev/null || true
        fi
    done
fi

# 2. Suppression des fichiers installés dans /opt ou ~/.local
echo "--> Suppression des répertoires de l'application..."
sudo rm -rf /opt/omnia
rm -rf "$HOME/.local/opt/omnia"

# 3. Suppression des exécutables / liens symboliques
echo "--> Suppression des liens exécutables..."
sudo rm -f /usr/local/bin/omnia
sudo rm -f /usr/bin/omnia
rm -f "$HOME/.local/bin/omnia"

# 4. Suppression des lanceurs d'applications (.desktop)
echo "--> Nettoyage des raccourcis du menu des applications..."
sudo rm -f /usr/share/applications/omnia.desktop
sudo rm -f /usr/share/applications/dev.omnia.omnia.desktop
rm -f "$HOME/.local/share/applications/omnia.desktop"
rm -f "$HOME/.local/share/applications/dev.omnia.omnia.desktop"

# 5. Suppression des icônes du système
echo "--> Nettoyage des icônes..."
sudo rm -f /usr/share/pixmaps/omnia.png
sudo rm -f /usr/share/pixmaps/dev.omnia.omnia.png
rm -f "$HOME/.local/share/pixmaps/omnia.png"
rm -f "$HOME/.local/share/pixmaps/dev.omnia.omnia.png"

# Suppression dans les thèmes hicolor
sudo find /usr/share/icons/hicolor/ -name "omnia.*" -delete 2>/dev/null || true
sudo find /usr/share/icons/hicolor/ -name "dev.omnia.omnia.*" -delete 2>/dev/null || true
find "$HOME/.local/share/icons/hicolor/" -name "omnia.*" -delete 2>/dev/null || true
find "$HOME/.local/share/icons/hicolor/" -name "dev.omnia.omnia.*" -delete 2>/dev/null || true

# 6. Actualisation des bases de données et caches du bureau
echo "--> Mise à jour des caches du bureau..."
if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo "==> OMNIA a été entièrement désinstallé avec succès."
echo "Vous pouvez désormais installer une nouvelle version proprement."
