#!/bin/bash
# Crea «build/Warp Launch.app» a partir del paquet SwiftPM i el signa: amb el certificat propi «Warp Launch Dev»
# si és al clauer (D12 de docs/especificacio.md), i si no, ad hoc.
# Ús: scripts/build-app.sh [release|debug]   (per defecte, release)
# No instal·la res ni obre l'app.
# Limitació: encara no copia bundles de recursos de SwiftPM (`resources:` a Package.swift).
# Quan se n'afegeixin, cal copiar-los aquí abans de signar.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSIO="$(tr -d '[:space:]' < VERSION)"
VERSIO_CODI="$(sed -n 's/.*static let versio = "\(.*\)".*/\1/p' Sources/WarpLaunchCore/Versio.swift)"
APP="build/Warp Launch.app"

if [[ "$VERSIO" != "$VERSIO_CODI" ]]; then
    echo "build-app: VERSION ($VERSIO) no coincideix amb WarpLaunch.versio ($VERSIO_CODI)" >&2
    exit 1
fi

swift build -c "$CONFIG" --product WarpLaunch
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WarpLaunch" "$APP/Contents/MacOS/WarpLaunch"
sed "s/__VERSIO__/$VERSIO/g" Recursos/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null
cp -R Recursos/ca.lproj "$APP/Contents/Resources/"
# La llicència (MIT) va dins de l'app: qui la rep compilada també la rep.
cp -X LICENSE "$APP/Contents/Resources/LICENSE"

# La icona ja compilada (scripts/icona-compila.sh, que necessita Xcode). Aquí n'hi ha prou amb les Command Line Tools.
if [[ -d Recursos/AppIcon.icon ]]; then
    if [[ ! -f Recursos/Assets.car || -n "$(find Recursos/AppIcon.icon -newer Recursos/Assets.car | head -1)" ]]; then
        echo "build-app: la icona ha canviat i cal tornar-la a compilar: scripts/icona-compila.sh" >&2
        exit 1
    fi
    cp -X Recursos/Assets.car Recursos/AppIcon.icns "$APP/Contents/Resources/"
fi

# Amb el certificat propi, macOS reconeix l'app com la mateixa entre compilacions, i els permisos que se li donen
# (llegir les dades de Warp) no es perden. Amb la signatura ad hoc, cada compilació és una app nova per a macOS.
# La primera vegada, macOS pot demanar si `codesign` pot fer servir la clau: «Permet sempre».
IDENTITAT="${WARP_LAUNCH_IDENTITAT:-Warp Launch Dev}"
IDENTITATS="$(security find-identity -p codesigning)"
if grep -qF "\"$IDENTITAT\"" <<< "$IDENTITATS"; then
    codesign --force --sign "$IDENTITAT" --timestamp=none "$APP"
else
    echo "build-app: no hi ha el certificat «${IDENTITAT}» al clauer: signatura ad hoc." >&2
    echo "build-app: macOS tornarà a bloquejar la lectura de Warp fins que hi tornis a donar permís (D12)." >&2
    codesign --force --sign - --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"

echo "$APP ($VERSIO, $CONFIG)"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => /identitat per a macOS: /p'
