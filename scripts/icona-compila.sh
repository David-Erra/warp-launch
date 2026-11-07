#!/bin/bash
# Compila la icona de l'app (fitxer d'Icon Composer) amb actool, que és a Xcode:
#   Recursos/Assets.car     icona de macOS 26 (vidre; aspectes clar, fosc, tenyit i transparent)
#   Recursos/AppIcon.icns   icona plana de reserva (vistes antigues del Finder i macOS 15)
# Ús: scripts/icona-compila.sh [AppIcon.icon] [carpeta de sortida]   (per defecte, Recursos/)
# Adaptat de BAMA (daveebbelaar/bama, MIT): vegeu .claude/skills/app-icon/LICENSE-BAMA.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ICONA="${1:-$REPO/Recursos/AppIcon.icon}"
SORTIDA="${2:-$REPO/Recursos}"
# xcode-select apunta a les Command Line Tools, que no porten actool.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Amb un altre nom, actool no escriu res i acaba igualment amb 0.
if [[ "$(basename "$ICONA")" != "AppIcon.icon" ]]; then
    echo "icona-compila: la carpeta s'ha de dir AppIcon.icon: $ICONA" >&2
    exit 1
fi

TREBALL="$(mktemp -d)"
trap 'rm -rf "$TREBALL"' EXIT

# actool falla si falta una capa, i per tant també fa de validador.
if ! xcrun actool "$ICONA" --compile "$TREBALL" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon \
        --output-partial-info-plist "$TREBALL/parcial.plist" \
        --output-format human-readable-text --errors --warnings > "$TREBALL/registre" 2>&1; then
    cat "$TREBALL/registre" >&2
    exit 1
fi
if [[ ! -f "$TREBALL/Assets.car" || ! -f "$TREBALL/AppIcon.icns" ]]; then
    cat "$TREBALL/registre" >&2
    echo "icona-compila: actool no ha escrit cap icona" >&2
    exit 1
fi

mkdir -p "$SORTIDA"
cp "$TREBALL/Assets.car" "$TREBALL/AppIcon.icns" "$SORTIDA/"
echo "$SORTIDA/Assets.car i $SORTIDA/AppIcon.icns"
