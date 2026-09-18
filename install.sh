#!/usr/bin/env bash
# ==============================================================================
# Script d'installation automatique pour OMNIA (Linux)
# ==============================================================================
# Ce script :
# 1. Installe les bibliothèques multimédia requises (libmpv, codecs).
# 2. Détecte et installe le paquet (.deb ou .tar.gz) situé dans le dossier
#    courant ou dans le dossier Téléchargements de l'utilisateur.
# 3. Configure le lanceur d'applications (.desktop) et les icônes système.
# ==============================================================================

set -e

echo "=== Installation d'OMNIA Desktop ==="

# 1. Vérification / installation des dépendances système (libmpv)
echo "--> Vérification des dépendances système (libmpv)..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y libmpv2 libmpv-dev mpv
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y mpv mpv-libs mpv-devel
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm mpv
elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y mpv libmpv2
else
    echo "Avertissement : gestionnaire de paquets non reconnu. Assurez-vous que libmpv est installé."
fi

# 2. Localisation du fichier d'installation
TARGET_FILE=""

# Recherche d'abord dans le dossier courant
for pattern in ./OMNIA*.deb ./omnia*.deb ./OMNIA*.tar.gz ./omnia*.tar.gz; do
    if [ -f "$pattern" ]; then
        TARGET_FILE="$pattern"
        break
    fi
done

# Recherche dans le dossier de téléchargements si non trouvé localement
if [ -z "$TARGET_FILE" ]; then
    DL_DIR="$HOME/Téléchargements"
    [ ! -d "$DL_DIR" ] && DL_DIR="$HOME/Downloads"
    
    if [ -d "$DL_DIR" ]; then
        for pattern in "$DL_DIR"/OMNIA*.deb "$DL_DIR"/omnia*.deb "$DL_DIR"/OMNIA*.tar.gz "$DL_DIR"/omnia*.tar.gz; do
            if [ -f "$pattern" ]; then
                TARGET_FILE="$pattern"
                break
            fi
        done
    fi
fi

# 3. Procédure d'installation selon le fichier trouvé
if [ -n "$TARGET_FILE" ] && [[ "$TARGET_FILE" =~ \.deb$ ]]; then
    echo "--> Paquet Debian détecté : $TARGET_FILE"
    sudo dpkg -i "$TARGET_FILE" || sudo apt-get install -f -y
    echo "==> OMNIA a été installé avec succès via le paquet .deb !"

elif [ -n "$TARGET_FILE" ] && [[ "$TARGET_FILE" =~ \.tar\.gz$ ]]; then
    echo "--> Archive compressée détectée : $TARGET_FILE"
    INSTALL_DIR="/opt/omnia"
    
    sudo rm -rf "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo tar -xzf "$TARGET_FILE" -C "$INSTALL_DIR" --strip-components=1
    sudo ln -sf "$INSTALL_DIR/omnia" /usr/local/bin/omnia

    # Installation des icônes hicolor si disponibles
    if [ -d "$INSTALL_DIR/data/flutter_assets/assets/icons" ]; then
        sudo cp -r "$INSTALL_DIR/data/flutter_assets/assets/icons/"* /usr/share/icons/hicolor/ 2>/dev/null || true
    fi

    # Création du lanceur de bureau
    cat << 'EOF' | sudo tee /usr/share/applications/omnia.desktop > /dev/null
[Desktop Entry]
Name=OMNIA
Comment=Lecteur multimédia et visionneur universel
Exec=/usr/local/bin/omnia %U
Terminal=false
Type=Application
Icon=omnia
Categories=AudioVideo;Player;Viewer;
MimeType=video/mp4;video/x-matroska;video/quicktime;audio/mpeg;audio/flac;audio/wav;image/png;image/jpeg;image/webp;
EOF

    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    fi

    echo "==> OMNIA a été installé avec succès dans $INSTALL_DIR !"

else
    echo "Erreur : aucun fichier OMNIA (.deb ou .tar.gz) trouvé dans le dossier courant ou dans ~/Téléchargements."
    echo "Veuillez télécharger la dernière version d'OMNIA depuis les Releases GitHub avant de relancer le script."
    exit 1
fi

echo "Vous pouvez maintenant lancer OMNIA depuis vos applications ou en tapant : omnia"
