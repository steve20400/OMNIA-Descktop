#!/usr/bin/env bash
# ==============================================================================
# Script d'installation automatique pour OMNIA (Ubuntu / Debian / Linux)
# ==============================================================================
# Prend en charge :
# - Les archives GitHub Actions (.zip) : ex. OMNIA-0.1.0-Linux-x64.zip
# - Les archives tarball (.tar.gz)
# - Les paquets Debian (.deb)
# ==============================================================================

set -e

echo "=== Installation d'OMNIA Desktop ==="

# 1. Vérification et installation des bibliothèques nécessaires
echo "--> Installation des dépendances système (libmpv, unzip)..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y libmpv2 libmpv-dev mpv unzip tar
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y mpv mpv-libs mpv-devel unzip tar
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm mpv unzip tar
elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y mpv libmpv2 unzip tar
fi

# 2. Localisation du fichier d'installation
TARGET_FILE=""

# Dossiers à inspecter (dossier courant, puis Téléchargements / Downloads)
SEARCH_DIRS=(".")
[ -d "$HOME/Téléchargements" ] && SEARCH_DIRS+=("$HOME/Téléchargements")
[ -d "$HOME/Downloads" ] && SEARCH_DIRS+=("$HOME/Downloads")

# Recherche de tous les paquets OMNIA et tri par date de modification (le plus récent en premier)
ALL_CANDIDATES=()
for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] && ALL_CANDIDATES+=("$f")
    done < <(find "$dir" -maxdepth 2 -type f \( -iname "*omnia*linux*x64*.zip" -o -iname "*omnia*linux*x64*.tar.gz" -o -iname "*omnia*.deb" -o -iname "omnia*.zip" -o -iname "omnia*.tar.gz" \) ! -iname "*captures*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
done

if [ ${#ALL_CANDIDATES[@]} -gt 0 ]; then
    TARGET_FILE="${ALL_CANDIDATES[0]}"
fi

if [ -z "$TARGET_FILE" ]; then
    echo "Erreur : aucun fichier OMNIA (.zip, .deb ou .tar.gz) trouvé dans :"
    for d in "${SEARCH_DIRS[@]}"; do echo "  - $d"; done
    echo "Veuillez vérifier que l'artefact GitHub Actions ou la release est bien téléchargé."
    exit 1
fi

echo "--> Fichier détecté : $TARGET_FILE (dernière version téléchargée)"

INSTALL_DIR="/opt/omnia"
TEMP_DIR=$(mktemp -d /tmp/omnia_install_XXXXXX)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 3. Traitement selon le format du fichier
if [[ "$TARGET_FILE" =~ \.deb$ ]]; then
    echo "--> Installation du paquet Debian..."
    sudo dpkg -i "$TARGET_FILE" || sudo apt-get install -f -y

else
    # Si c'est un ZIP (artefact téléchargé depuis GitHub Actions)
    if [[ "$TARGET_FILE" =~ \.zip$ ]]; then
        echo "--> Extraction de l'archive ZIP GitHub Actions..."
        unzip -q "$TARGET_FILE" -d "$TEMP_DIR"

        # Vérifier si le ZIP contient une archive tar.gz interne (comme produit par la CI)
        INNER_TAR=( "$TEMP_DIR"/omnia*.tar.gz "$TEMP_DIR"/OMNIA*.tar.gz )
        if [ ${#INNER_TAR[@]} -gt 0 ] && [ -f "${INNER_TAR[0]}" ]; then
            echo "--> Archive tar.gz interne trouvée : $(basename "${INNER_TAR[0]}")"
            sudo rm -rf "$INSTALL_DIR"
            sudo mkdir -p "$INSTALL_DIR"
            sudo tar -xzf "${INNER_TAR[0]}" -C "$INSTALL_DIR" --strip-components=1
        else
            # Le ZIP contient directement le bundle ou un dossier extrait
            sudo rm -rf "$INSTALL_DIR"
            sudo mkdir -p "$INSTALL_DIR"
            if [ -f "$TEMP_DIR/omnia" ]; then
                sudo cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
            else
                SUBDIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
                if [ -n "$SUBDIR" ]; then
                    sudo cp -r "$SUBDIR"/* "$INSTALL_DIR/"
                else
                    sudo cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
                fi
            fi
        fi

    # Si c'est directement une archive tar.gz
    elif [[ "$TARGET_FILE" =~ \.tar\.gz$ ]]; then
        echo "--> Extraction de l'archive tar.gz..."
        sudo rm -rf "$INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
        sudo tar -xzf "$TARGET_FILE" -C "$INSTALL_DIR" --strip-components=1
    fi

    # 4. Vérification et configuration de l'exécutable
    if [ ! -f "$INSTALL_DIR/omnia" ]; then
        FOUND_BIN=$(find "$INSTALL_DIR" -maxdepth 2 -name "omnia" -type f | head -n 1)
        if [ -n "$FOUND_BIN" ] && [ "$FOUND_BIN" != "$INSTALL_DIR/omnia" ]; then
            SUBDIR=$(dirname "$FOUND_BIN")
            sudo cp -r "$SUBDIR"/* "$INSTALL_DIR/"
        fi
    fi

    if [ ! -f "$INSTALL_DIR/omnia" ]; then
        echo "Erreur : l'exécutable 'omnia' n'a pas été trouvé dans $INSTALL_DIR après extraction."
        echo "Contenu extrait dans $INSTALL_DIR :"
        ls -la "$INSTALL_DIR"
        exit 1
    fi

    sudo chmod +x "$INSTALL_DIR/omnia"
    sudo ln -sf "$INSTALL_DIR/omnia" /usr/local/bin/omnia
    sudo ln -sf "$INSTALL_DIR/omnia" /usr/bin/omnia

    # 5. Déploiement des icônes
    echo "--> Configuration des icônes..."
    sudo mkdir -p /usr/share/icons/hicolor /usr/share/pixmaps

    # 5.1 Déploiement de l'arborescence hicolor
    if [ -d "$INSTALL_DIR/icons/hicolor" ]; then
        sudo cp -r "$INSTALL_DIR/icons/hicolor/"* /usr/share/icons/hicolor/ 2>/dev/null || true
    elif [ -d "$INSTALL_DIR/data/flutter_assets/assets/icons" ]; then
        sudo cp -r "$INSTALL_DIR/data/flutter_assets/assets/icons/"* /usr/share/icons/hicolor/ 2>/dev/null || true
    fi

    # Dupliquer les icônes dans hicolor sous le nom "omnia" en plus de "dev.omnia.omnia"
    for icon in /usr/share/icons/hicolor/*/apps/dev.omnia.omnia.*; do
        if [ -f "$icon" ]; then
            dir=$(dirname "$icon")
            ext="${icon##*.}"
            sudo cp -f "$icon" "$dir/omnia.$ext" 2>/dev/null || true
        fi
    done

    # 5.2 Déploiement dans /usr/share/pixmaps (indispensable pour GNOME / XFCE / KDE)
    if [ -f "$INSTALL_DIR/dev.omnia.omnia.png" ]; then
        sudo cp -f "$INSTALL_DIR/dev.omnia.omnia.png" /usr/share/pixmaps/dev.omnia.omnia.png
        sudo cp -f "$INSTALL_DIR/dev.omnia.omnia.png" /usr/share/pixmaps/omnia.png
    fi
    if [ -f "$INSTALL_DIR/dev.omnia.omnia.svg" ]; then
        sudo cp -f "$INSTALL_DIR/dev.omnia.omnia.svg" /usr/share/pixmaps/dev.omnia.omnia.svg
        sudo cp -f "$INSTALL_DIR/dev.omnia.omnia.svg" /usr/share/pixmaps/omnia.svg
    fi

    # Fixer les droits de lecture sur les icônes
    sudo chmod -R 644 /usr/share/icons/hicolor/*/apps/*omnia* 2>/dev/null || true
    sudo chmod 644 /usr/share/pixmaps/*omnia* 2>/dev/null || true

    # 6. Création ou copie du lanceur .desktop
    echo "--> Configuration du lanceur de bureau..."
    sudo mkdir -p /usr/share/applications

    if [ -f "$INSTALL_DIR/dev.omnia.omnia.desktop" ]; then
        sudo cp -f "$INSTALL_DIR/dev.omnia.omnia.desktop" /usr/share/applications/dev.omnia.omnia.desktop
        sudo sed -i 's|^Exec=.*|Exec=/usr/local/bin/omnia %U|' /usr/share/applications/dev.omnia.omnia.desktop 2>/dev/null || true
    else
        cat << 'EOF' | sudo tee /usr/share/applications/dev.omnia.omnia.desktop > /dev/null
[Desktop Entry]
Version=1.0
Type=Application
Name=OMNIA
GenericName=Lecteur universel
GenericName[en]=Universal player
Comment=Vidéo, audio, PDF et texte dans une seule application
Exec=/usr/local/bin/omnia %U
Icon=dev.omnia.omnia
Terminal=false
Categories=AudioVideo;Player;Viewer;
StartupWMClass=dev.omnia.omnia
MimeType=video/mp4;video/x-matroska;video/quicktime;audio/mpeg;audio/flac;audio/wav;image/png;image/jpeg;image/webp;application/pdf;
EOF
    fi
    sudo chmod 644 /usr/share/applications/dev.omnia.omnia.desktop 2>/dev/null || true

    # Nettoyage impératif de tout vieux lanceur doublon pour éviter les icônes doubles
    sudo rm -f /usr/share/applications/omnia.desktop 2>/dev/null || true
    if [ -f "$HOME/.local/share/applications/omnia.desktop" ]; then
        rm -f "$HOME/.local/share/applications/omnia.desktop" 2>/dev/null || true
    fi
    if [ -f "$HOME/.local/share/applications/dev.omnia.omnia.desktop" ]; then
        rm -f "$HOME/.local/share/applications/dev.omnia.omnia.desktop" 2>/dev/null || true
    fi

    # 7. Actualisation immédiate des caches système
    echo "--> Actualisation des caches système (icônes et applications)..."
    for updater in gtk-update-icon-cache gtk-update-icon-cache-3.0; do
        if command -v "$updater" >/dev/null 2>&1; then
            sudo "$updater" -f -q /usr/share/icons/hicolor 2>/dev/null || sudo "$updater" -f -t /usr/share/icons/hicolor 2>/dev/null || true
        fi
    done
    if command -v update-icon-caches >/dev/null 2>&1; then
        sudo update-icon-caches /usr/share/icons/hicolor 2>/dev/null || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    fi
    sudo touch /usr/share/icons/hicolor 2>/dev/null || true
    sudo touch /usr/share/applications 2>/dev/null || true

    # 8. Épinglage automatique dans la barre des tâches / Dash (GNOME / Ubuntu)
    if command -v gsettings >/dev/null 2>&1; then
        echo "--> Épinglage d'OMNIA dans la barre des tâches..."
        python3 -c "
import subprocess, ast

try:
    res = subprocess.check_output(['gsettings', 'get', 'org.gnome.shell', 'favorite-apps'], text=True).strip()
    raw = res[4:] if res.startswith('@as ') else res
    favs = ast.literal_eval(raw)
    changed = False
    if 'omnia.desktop' in favs:
        favs = [f for f in favs if f != 'omnia.desktop']
        changed = True
    if 'dev.omnia.omnia.desktop' not in favs:
        favs.append('dev.omnia.omnia.desktop')
        changed = True
    if changed:
        subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'favorite-apps', str(favs)], check=True)
except Exception:
    pass
" 2>/dev/null || true
    fi
fi

echo ""
echo "=========================================================="
echo "  ==> OMNIA a été installé avec succès sur votre système !"
echo "=========================================================="
echo "Vous pouvez lancer l'application :"
echo "  1. Depuis votre menu des applications en tapant 'OMNIA'"
echo "  2. Directement depuis le terminal avec la commande : omnia"
echo ""
