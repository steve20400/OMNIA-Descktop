#!/usr/bin/env bash
# Lancement réel d'OMNIA sous Linux, sur un écran virtuel (Xvfb).
#
# 1. OMNIA démarre avec un son en argument, comme par « Ouvrir avec », et doit
#    rester ouvert : libmpv, la fenêtre GTK et le stockage local sont prêts.
# 2. Une seconde instance reçoit un PDF, comme un fichier déposé sur l'icône :
#    elle doit le confier à la première fenêtre et se terminer aussitôt.
# 3. L'historique doit contenir les deux fichiers : les deux ouvertures ont
#    réellement eu lieu.
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

# Fin d'un journal, encodée pour tenir dans une annotation.
log_tail() {
  [ -f "$1" ] || return 0
  tail -n 30 "$1" | sed -e 's/%/%25/g' -e 's/\r$//' | awk '{ printf "%s%%0A", $0 }'
}

fail() {
  local message=$1
  local tail
  tail=$(log_tail "$out/omnia.log")
  [ -n "$tail" ] && message="$message%0A%0ASortie d'OMNIA :%0A$tail"
  echo "::error title=Lancement réel (Linux)::$message"
  pkill -f "$bundle/omnia" || true
  exit 1
}

shot() {
  import -window root "$out/$1" 2>/dev/null ||
    echo "::warning title=Capture d'écran::$1 non capturée."
}

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
  fail "La seconde instance est restée ouverte : le PDF n'a pas été confié à la première fenêtre."
fi
if wait "$second"; then :; else
  fail "La seconde instance s'est terminée en erreur (code $?)."
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
for name in essai.wav essai.pdf; do
  grep -aq "$name" "$history" || fail "$name est absent de l'historique : son ouverture n'a pas eu lieu."
done

echo "Lancement réel réussi : démarrage, ouverture du son, PDF confié par une seconde instance."
