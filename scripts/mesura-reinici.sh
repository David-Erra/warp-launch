#!/bin/bash
# Després d'un reinici del Mac (la prova R7, amb la L5): resumeix què ha passat, només llegint.
# Llegeix: l'hora d'arrencada del Mac, el registre de l'app des de l'arrencada (obertures i «Obre-ho tot»), si l'app i Warp són
# oberts, i quants processos de Claude hi ha i quanta memòria fan servir. No obre, no tanca i no escriu res.
#
# Ús: scripts/mesura-reinici.sh
set -euo pipefail

arrencada="$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')"
ara="$(date +%s)"
echo "Mac engegat: $(date -r "$arrencada" '+%d/%m/%Y %H:%M:%S') (fa $(( (ara - arrencada) / 60 )) min)"

hora() { ps -o lstart= -p "$1" 2>/dev/null | xargs -I{} date -j -f '%a %b %d %T %Y' '{}' '+%H:%M:%S' 2>/dev/null || echo "?"; }
app="$(pgrep -x WarpLaunch | head -1 || true)"
if [[ -n "$app" ]]; then echo "Warp Launch: oberta des de les $(hora "$app") (pid $app)"; else echo "Warp Launch: no és oberta"; fi
warp="$(pgrep -x stable | head -1 || true)"
if [[ -n "$warp" ]]; then echo "Warp: obert des de les $(hora "$warp")"; else echo "Warp: no és obert"; fi

segons=$(( ara - arrencada + 60 ))
echo
echo "--- Registre de l'app des de l'arrencada (obertures):"
/usr/bin/log show --style compact --last "${segons}s" \
    --predicate 'subsystem == "cat.davide.warp-launch" AND category == "obertura"' 2>/dev/null \
    | grep -v -e '^Timestamp' -e 'swiftpm-testing' | sed -E 's/^[0-9-]+ ([0-9:]+)\.[0-9]+ .*\] /\1 /' | tail -30 || true

echo
claudes="$(pgrep -x claude || true)"
n="$(printf '%s\n' "$claudes" | grep -c . || true)"
if [[ "$n" -gt 0 ]]; then
    kb="$(ps -o rss= -p "$(printf '%s\n' "$claudes" | paste -sd, -)" | awk '{s += $1} END {print s}')"
    echo "Claude: $n processos, $(( kb / 1024 )) MB de memòria en total (uns $(( kb / 1024 / n )) MB cadascun)"
else
    echo "Claude: cap procés"
fi
echo "Memòria lliure del Mac: $(memory_pressure 2>/dev/null | grep -E 'free percentage' | sed -E 's/.*: //' || echo '?')"
