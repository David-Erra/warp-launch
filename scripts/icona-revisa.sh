#!/bin/bash
# Dibuixa la icona tal com la mostra macOS, amb l'ictool d'Icon Composer (dins d'Xcode), en una sola làmina:
# clara, fosca, tenyida i transparent a 256 pt, i clara a 32 i 16 pt.
# Ús: scripts/icona-revisa.sh [AppIcon.icon] [sortida.png]   (per defecte, build/icona-revisio.png)
# Compila abans (scripts/icona-compila.sh): si falta una capa, ictool dibuixa un fons buit i acaba amb 0.
# Adaptat de BAMA (daveebbelaar/bama, MIT): vegeu .claude/skills/app-icon/LICENSE-BAMA.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ICONA="${1:-$REPO/Recursos/AppIcon.icon}"
SORTIDA="${2:-$REPO/build/icona-revisio.png}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ICTOOL="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
    echo "icona-revisa: no trobo ictool; cal Xcode 26 o posterior: $ICTOOL" >&2
    exit 1
fi

TREBALL="$(mktemp -d)"
trap 'rm -rf "$TREBALL"' EXIT

dibuixa() { # aspecte mida fitxer
    "$ICTOOL" "$ICONA" --export-image --output-file "$TREBALL/$3" \
        --platform macOS --rendition "$1" --width "$2" --height "$2" --scale 2 > /dev/null
}
dibuixa Default 256 1.png
dibuixa Dark 256 2.png
dibuixa TintedDark 256 3.png
dibuixa ClearLight 256 4.png
dibuixa Default 32 5.png
dibuixa Default 16 6.png

mkdir -p "$(dirname "$SORTIDA")"
swift "$REPO/scripts/icona-full.swift" "$SORTIDA" "$TREBALL"/{1,2,3,4,5,6}.png
echo "$SORTIDA"
