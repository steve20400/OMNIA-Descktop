#!/usr/bin/env bash
# Lancement réel d'OMNIA sous Linux, sur un écran virtuel (Xvfb).
#
# 0. Chaque bibliothèque du paquet trouve ses dépendances (libmpv est celle
#    du système, pdfium est embarqué).
# 1. OMNIA démarre avec un son en argument, comme par « Ouvrir avec », et doit
#    rester ouvert : libmpv, la fenêtre GTK et le stockage local sont prêts.
# 2. Une seconde instance reçoit un PDF, comme un fichier déposé sur l'icône :
#    elle doit le confier à la première fenêtre et se terminer aussitôt.
# 3. L'historique prouve que libmpv a ouvert le son et que pdfium a ouvert le
#    PDF (voir le détail à l'étape 3).
#
# Une capture d'écran est prise à chaque étape, dans <dossier de sortie>.
#
# Usage : bash tool/ci/smoke_linux.sh <bundle> <dossier de sortie>
set -euo pipefail

bundle=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)

samples="${RUNNER_TEMP:-/tmp}/omnia-essai"
python3 tool/ci/make_samples.py "$samples"
wav="$samples/Musique/essai.wav"
pdf="$samples/Documents/essai.pdf"

# Fin d'un journal, bornée puis encodée : GitHub ne garde que les 4096
# premiers caractères d'une annotation, et c'est la fin qui compte.
log_tail() {
  [ -f "$1" ] || return 0
  tail -n 30 "$1" | sed -e 's/\r$//' | tail -c 3000 | sed -e 's/%/%25/g' | awk '{ printf "%s%%0A", $0 }'
}

# fail <message> [journal] : le journal joint est celui de l'instance en cause.
fail() {
  local message=$1
  local log=${2:-$out/omnia.log}
  local tail
  tail=$(log_tail "$log")
  [ -n "$tail" ] && message="$message%0A%0ASortie ($(basename "$log")) :%0A$tail"
  echo "::error title=Lancement réel (Linux)::$message"
  pkill -f "$bundle/omnia" || true
  exit 1
}

shot() {
  import -window root "$out/$1" 2>/dev/null ||
    echo "::warning title=Capture d'écran::$1 non capturée."
}

# 0. Dépendances des bibliothèques natives.
missing=$(
  for lib in "$bundle/omnia" "$bundle"/lib/*.so; do
    ldd "$lib" | grep 'not found' | sed "s|^|$(basename "$lib") : |" || true
  done | awk '{ printf "%s%%0A", $0 }'
)
[ -z "$missing" ] || fail "Bibliothèques introuvables :%0A$missing"
compgen -G "$bundle/lib/*pdfium*" >/dev/null || fail "pdfium est absent du paquet (dossier lib/)."

Xvfb :99 -screen 0 1440x900x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 3

# 1. Première instance, avec le son.
"$bundle/omnia" "$wav" >"$out/omnia.log" 2>&1 &
first=$!
sleep 20
shot 1-lecture-audio.png
kill -0 "$first" 2>/dev/null || fail "OMNIA s'est arrêté au démarrage."

# 2. Seconde instance, avec le PDF : elle doit déléguer et se retirer.
"$bundle/omnia" "$pdf" >"$out/seconde-instance.log" 2>&1 &
second=$!
waited=0
while kill -0 "$second" 2>/dev/null && [ "$waited" -lt 30 ]; do
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$second" 2>/dev/null; then
  shot 2-seconde-instance.png
  fail "La seconde instance est restée ouverte : le PDF n'a pas été confié à la première fenêtre." "$out/seconde-instance.log"
fi
if wait "$second"; then :; else
  fail "La seconde instance s'est terminée en erreur (code $?)." "$out/seconde-instance.log"
fi
sleep 10
shot 2-document-pdf.png
kill -0 "$first" 2>/dev/null || fail "OMNIA s'est arrêté après avoir reçu le PDF."

# 3. Arrêt, puis lecture de l'historique (écrit sur disque à chaque ouverture).
kill -TERM "$first" 2>/dev/null || true
for _ in $(seq 1 20); do
  kill -0 "$first" 2>/dev/null || break
  sleep 1
done
kill -KILL "$first" 2>/dev/null || true

history=$(find "$HOME/.local/share" -name history.hive -print -quit 2>/dev/null || true)
[ -n "$history" ] || fail "Aucun historique trouvé sous ~/.local/share : le stockage local n'a pas été créé."
echo "Historique : $history"

# Chaque écriture de l'historique ajoute une trame qui contient deux fois le
# chemin (clé et valeur). L'ouverture en écrit une première, avant même que le
# fichier soit lu : elle ne prouve que la réception de la commande. Une
# seconde trame n'arrive qu'après une lecture réussie :
# - PDF : pdfium a ouvert le document et publié sa page, OMNIA mémorise la page ;
# - son : libmpv a ouvert le fichier et publié sa durée (position mémorisée en
#   changeant de fichier), ou atteint sa fin (fichier marqué terminé). Les
#   machines de la CI n'ont pas de sortie audio : c'est l'ouverture et le
#   décodage qui sont prouvés, pas l'écoute.
for name in essai.wav essai.pdf; do
  # « || true » : sans occurrence, grep échoue, et set -e arrêterait le script
  # avant le message d'erreur explicite.
  count=$(grep -ao "$name" "$history" | wc -l || true)
  [ "$count" -gt 0 ] || fail "$name est absent de l'historique : la commande d'ouverture n'est pas arrivée."
  [ "$count" -ge 4 ] || fail "$name a été reçu mais pas lu : libmpv ou pdfium n'ont pas pu l'ouvrir."
done

echo "Lancement réel réussi : démarrage, son ouvert par libmpv, PDF confié par une seconde instance et ouvert par pdfium."
