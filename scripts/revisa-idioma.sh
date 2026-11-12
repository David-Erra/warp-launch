#!/bin/bash
# Obre la Warp Launch compilada en una llengua, amb una configuració buida de prova, per revisar-ne els textos (F7 del multidioma).
#
# Sense --aplica, només diu què faria: obrir l'app demana l'OK de l'autor (regla 4).
# No toca Warp ni Claude:
# - amb --config en una carpeta temporal, l'app no llegeix ni canvia res de Warp fins que no s'hi accepta el permís, i encara
#   llavors l'ajust de Warp només el toca la carpeta de debò;
# - aquesta còpia no porta l'adreça de les actualitzacions (la de build-app.sh normal), i no s'actualitza.
# S'obre com una instància nova (open -n), al costat de la que hi hagi oberta.
#
# Ús: scripts/revisa-idioma.sh <llengua> [--aplica]
#     Les llengües són les de Sources/WarpLaunchCore/Textos/*.lproj.
set -euo pipefail
cd "$(dirname "${0}")/.."

LLENGUA="${1:-}"
APLICA=0
if [[ "${2:-}" == "--aplica" ]]; then APLICA=1; elif [[ -n "${2:-}" ]]; then echo "revisa-idioma: opció desconeguda «${2}»" >&2; exit 64; fi

DISPONIBLES=""
for carpeta in Sources/WarpLaunchCore/Textos/*.lproj; do
    nom="$(basename "$carpeta")"
    DISPONIBLES="$DISPONIBLES ${nom%.lproj}"
done
if [[ -z "${LLENGUA}" || " $DISPONIBLES " != *" $LLENGUA "* ]]; then
    echo "Ús: scripts/revisa-idioma.sh <llengua> [--aplica]. Llengües:${DISPONIBLES}" >&2
    exit 64
fi

APP="build/Warp Launch.app"
INFO="$APP/Contents/Info.plist"
if [[ ! -d "${APP}" ]]; then
    echo "revisa-idioma: no hi ha «${APP}». Primer: scripts/build-app.sh" >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c "Print SUFeedURL" "${INFO}" >/dev/null 2>&1; then
    echo "revisa-idioma: «${APP}» porta l'adreça de les actualitzacions (és la còpia de publica.sh). Torna a fer scripts/build-app.sh." >&2
    exit 1
fi
VERSIO="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${INFO}")"
if [[ "${VERSIO}" != "$(cat VERSION)" ]]; then
    echo "revisa-idioma: «${APP}» és la $VERSIO, i el codi és a la $(cat VERSION). Torna a fer scripts/build-app.sh." >&2
    exit 1
fi

CONFIG="${TMPDIR:-/tmp/}warp-launch-revisio-${LLENGUA}"
echo "Obriria «${APP}» ($VERSIO) en «${LLENGUA}», amb la configuració buida «${CONFIG}», com una instància nova."
echo "Què mirar: la pantalla del permís, l'editor buit (els tres passos), Configuració (⌘,) a cada pestanya, i el menú de la icona."
echo "No hi canviïs l'idioma de la Configuració: es desa per a l'app instal·lada."
if [[ "${APLICA}" -eq 0 ]]; then
    echo "Mode de prova: no s'ha obert res. Amb --aplica, l'obre."
    exit 0
fi
mkdir -p "${CONFIG}"
open -n "${APP}" --args --config "${CONFIG}" -AppleLanguages "($LLENGUA)"
echo "Oberta. Per tancar-la: la seva icona de la barra de menú › Surt. Després, la carpeta de prova: rm -rf \"$CONFIG\""
