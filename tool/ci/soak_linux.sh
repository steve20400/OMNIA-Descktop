#!/usr/bin/env bash
# Essai d'endurance sous Linux : le scénario qui figeait la machine de Steve
# (19 novembre 2026). Trois fenêtres indépendantes — deux PDF de 40 pages
# qu'on fait défiler, une vidéo H.264 720p qui joue — pendant plusieurs
# minutes. Toutes les 15 secondes, pour chaque fenêtre : mémoire résidente,
# processeur, nombre de fils d'exécution ; et la mémoire disponible de la
# machine.
#
# Le rapport part en annotation, qu'il y ait problème ou non : une hausse
# régulière de la mémoire, un processeur qui ne redescend pas, des fils qui
# s'accumulent, c'est ce qui finit par figer une machine au bout de dix
# minutes. L'essai échoue franchement si une fenêtre meurt ou si la mémoire
# file.
#
# Usage : bash tool/ci/soak_linux.sh <bundle> <dossier de sortie> [minutes]
set -uo pipefail

bundle=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
minutes=${3:-6}

samples="${RUNNER_TEMP:-/tmp}/omnia-endurance"
mkdir -p "$samples/Documents-A" "$samples/Documents-B" "$samples/Films"
python3 -c "
import sys
sys.path.insert(0, 'tool/ci')
import make_samples as m
m.write_long_pdf('$samples/Documents-A/rapport.pdf')
m.write_long_pdf('$samples/Documents-B/cours.pdf')
"
# Une vraie vidéo, encodée comme celles de l'utilisateur : H.264 et AAC.
ffmpeg -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100" \
  -t $((minutes * 60 + 60)) -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -shortest "$samples/Films/film.mp4" ||
  { echo "::error title=Endurance Linux::ffmpeg n'a pas produit la vidéo d'essai."; exit 1; }

Xvfb :98 -screen 0 1600x900x24 >/dev/null 2>&1 &
xvfb=$!
export DISPLAY=:98
sleep 3

# Trois processus, comme trois fenêtres ouvertes par l'utilisateur.
declare -a pids names
launch() {
  "$bundle/omnia" --new-window "$2" >"$out/endurance-$1.log" 2>&1 &
  pids+=($!)
  names+=("$1")
  sleep 8
}
launch document-a "$samples/Documents-A/rapport.pdf"
launch document-b "$samples/Documents-B/cours.pdf"
launch video "$samples/Films/film.mp4"

ticks=$(getconf CLK_TCK)
csv="$out/endurance.csv"
echo "seconde,fenetre,rss_mo,cpu_pct,fils,memoire_dispo_mo" >"$csv"
declare -A last_ticks first_rss last_rss max_cpu first_threads last_threads cpu_sum cpu_n

cpu_ticks() { awk '{ print $14 + $15 }' "/proc/$1/stat" 2>/dev/null || echo 0; }
status_value() { awk -v key="$2:" '$1 == key { print $2 }' "/proc/$1/status" 2>/dev/null || echo 0; }

for i in "${!pids[@]}"; do last_ticks[$i]=$(cpu_ticks "${pids[$i]}"); done

# Défilement des documents : PageDown puis PageUp, comme une lecture.
scroll_documents() {
  local key=$1
  for i in 0 1; do
    local wid
    wid=$(xdotool search --pid "${pids[$i]}" 2>/dev/null | tail -n 1)
    [ -n "$wid" ] || continue
    xdotool windowactivate --sync "$wid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do xdotool key --window "$wid" "$key" 2>/dev/null || true; done
  done
}

died=""
samples_count=$((minutes * 4))
for n in $(seq 1 "$samples_count"); do
  if [ $((n % 2)) -eq 0 ]; then scroll_documents Next; else scroll_documents Prior; fi
  sleep 15
  available=$(awk '$1 == "MemAvailable:" { print int($2 / 1024) }' /proc/meminfo)
  for i in "${!pids[@]}"; do
    pid=${pids[$i]}
    if ! kill -0 "$pid" 2>/dev/null; then
      [[ "$died" == *"${names[$i]}"* ]] || died="$died ${names[$i]}"
      continue
    fi
    rss=$(( $(status_value "$pid" VmRSS) / 1024 ))
    threads=$(status_value "$pid" Threads)
    now=$(cpu_ticks "$pid")
    cpu=$(( (now - last_ticks[$i]) * 100 / (ticks * 15) ))
    last_ticks[$i]=$now
    echo "$((n * 15)),${names[$i]},$rss,$cpu,$threads,$available" >>"$csv"
    # La première minute sert de chauffe : caches remplis, polices chargées.
    if [ "$n" -eq 4 ]; then first_rss[$i]=$rss; first_threads[$i]=$threads; fi
    last_rss[$i]=$rss
    last_threads[$i]=$threads
    [ "$cpu" -gt "${max_cpu[$i]:-0}" ] && max_cpu[$i]=$cpu
    if [ "$n" -gt 4 ]; then
      cpu_sum[$i]=$(( ${cpu_sum[$i]:-0} + cpu ))
      cpu_n[$i]=$(( ${cpu_n[$i]:-0} + 1 ))
    fi
  done
  if [ "$n" -eq 4 ]; then first_available=$available; fi
done
last_available=${available:-0}

import -window root "$out/endurance-fin.png" 2>/dev/null || true

# Rapport : une ligne par fenêtre.
report=""
problem=""
elapsed=$(( (samples_count - 4) * 15 ))
for i in "${!pids[@]}"; do
  name=${names[$i]}
  if [[ "$died" == *"$name"* ]]; then
    report="$report%0A$name : ARRÊTÉE en cours d'essai"
    problem="$problem $name-arrêtée"
    continue
  fi
  start=${first_rss[$i]:-0}
  end=${last_rss[$i]:-0}
  growth=$(( end - start ))
  per_min=$(( elapsed > 0 ? growth * 60 / elapsed : 0 ))
  avg_cpu=$(( ${cpu_n[$i]:-0} > 0 ? ${cpu_sum[$i]:-0} / ${cpu_n[$i]} : 0 ))
  thread_growth=$(( ${last_threads[$i]:-0} - ${first_threads[$i]:-0} ))
  report="$report%0A$name : mémoire ${start} → ${end} Mo (${per_min} Mo/min), processeur moyen ${avg_cpu} %25 (pointe ${max_cpu[$i]:-0} %25), fils ${first_threads[$i]:-0} → ${last_threads[$i]:-0}"
  # Au-delà de 20 Mo par minute de façon soutenue, dix minutes suffisent à
  # entamer sérieusement la mémoire d'une machine ordinaire.
  [ "$per_min" -gt 20 ] && problem="$problem $name-mémoire"
  [ "$thread_growth" -gt 30 ] && problem="$problem $name-fils"
done
report="$report%0AMachine : mémoire disponible ${first_available:-0} → ${last_available} Mo, sur $((elapsed / 60)) min après la chauffe."

for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
sleep 5
for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
kill "$xvfb" 2>/dev/null || true

if [ -n "$problem" ]; then
  # Titre sans deux-points ni virgule : ils séparent les propriétés.
  echo "::error title=Endurance Linux — problème —$problem::$report"
  exit 1
fi
echo "::notice title=Endurance Linux — trois fenêtres — ${minutes} min::$report"
