#!/usr/bin/env bash
# Installe OMNIA pour l'utilisateur courant, sans droits d'administrateur.
#
# Copie l'application dans ~/.local/share/omnia, pose le lanceur et l'icône là
# où le bureau les cherche, et met à jour la base des associations : OMNIA
# apparaît alors dans le menu des applications et dans « Ouvrir avec ».
#
# Lancer depuis le dossier extrait de l'archive :
#   ./installer-omnia.sh            installe (ou met à jour)
#   ./installer-omnia.sh --retirer  désinstalle
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$HOME/.local/share/omnia"
bin_dir="$HOME/.local/bin"
desktop_dir="$HOME/.local/share/applications"
icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
desktop_file="$desktop_dir/dev.omnia.omnia.desktop"

retirer() {
  rm -rf "$app_dir"
  rm -f "$bin_dir/omnia" "$desktop_file" "$icon_dir/dev.omnia.omnia.svg"
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$desktop_dir" || true
  echo "OMNIA retiré. Vos réglages et votre historique restent dans ~/.local/share/dev.omnia.omnia."
  exit 0
}

[ "${1:-}" = "--retirer" ] && retirer

[ -x "$source_dir/omnia" ] || {
  echo "omnia introuvable à côté de ce script : lancez-le depuis le dossier extrait de l'archive." >&2
  exit 1
}

# libmpv n'est pas embarqué dans le paquet Linux : sans lui, aucune lecture.
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "Il manque libmpv. Installez-le puis relancez ce script :"
  echo "    sudo apt install libmpv2 xdg-desktop-portal-gtk"
  exit 1
fi

mkdir -p "$app_dir" "$bin_dir" "$desktop_dir" "$icon_dir"
# Le dossier est remplacé, pour qu'une mise à jour ne laisse pas d'ancien
# fichier derrière elle.
rm -rf "${app_dir:?}/"*
cp -r "$source_dir/." "$app_dir/"
rm -f "$app_dir/installer-omnia.sh"
chmod +x "$app_dir/omnia"
ln -sf "$app_dir/omnia" "$bin_dir/omnia"

# Chemin absolu dans le lanceur : le bureau ne dépend plus du PATH, qui n'est
# pas le même selon la session. %F : tous les fichiers choisis d'un coup.
sed "s|^Exec=omnia %F$|Exec=$app_dir/omnia %F|" \
  "$source_dir/dev.omnia.omnia.desktop" > "$desktop_file"
cp "$source_dir/dev.omnia.omnia.svg" "$icon_dir/"

command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$desktop_dir" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 &&
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

echo "OMNIA est installé dans $app_dir."
echo
echo "  • Menu des applications : cherchez « OMNIA »."
echo "  • Terminal : omnia /chemin/vers/film.mkv"
echo "  • Clic droit sur un fichier : « Ouvrir avec » → OMNIA."
echo
echo "Pour qu'OMNIA ouvre un format par défaut : clic droit sur un fichier,"
echo "« Propriétés », onglet « Ouvrir avec », choisir OMNIA, « Définir par défaut »."
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo
     echo "Note : $bin_dir n'est pas dans votre PATH ; la commande « omnia »"
     echo "ne sera disponible qu'après une reconnexion." ;;
esac
