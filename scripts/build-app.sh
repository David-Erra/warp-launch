#!/bin/bash
# Crea «build/Warp Launch.app» a partir del paquet SwiftPM i el signa: amb el certificat propi «Warp Launch Dev»
# si és al clauer (D12 de docs/especificacio.md), i si no, ad hoc.
# Ús: scripts/build-app.sh [release|debug] [--amb-feed]   (per defecte, release i sense l'adreça de les actualitzacions)
# --amb-feed hi posa l'adreça i la clau pública (Recursos/Actualitzacions.plist): només per publicar. Sense, la còpia no s'actualitza
# mai sola (docs/disseny.md, secció 11, 2.4).
# No instal·la res ni obre l'app.
# Limitació: encara no copia bundles de recursos de SwiftPM (`resources:` a Package.swift).
# Quan se n'afegeixin, cal copiar-los aquí abans de signar.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
AMB_FEED=0
CONFIG_DONADA=0
for ARGUMENT in "$@"; do
    case "$ARGUMENT" in
        release|debug)
            if [[ "$CONFIG_DONADA" -eq 1 ]]; then echo "build-app: ús: scripts/build-app.sh [release|debug] [--amb-feed]" >&2; exit 64; fi
            CONFIG="$ARGUMENT"
            CONFIG_DONADA=1
            ;;
        --amb-feed) AMB_FEED=1 ;;
        *) echo "build-app: ús: scripts/build-app.sh [release|debug] [--amb-feed]" >&2; exit 64 ;;
    esac
done
VERSIO="$(tr -d '[:space:]' < VERSION)"
VERSIO_CODI="$(sed -n 's/.*static let versio = "\(.*\)".*/\1/p' Sources/WarpLaunchCore/Versio.swift)"
APP="build/Warp Launch.app"
FEED="Recursos/Actualitzacions.plist"
RPATH="@executable_path/../Frameworks"

if [[ "$VERSIO" != "$VERSIO_CODI" ]]; then
    echo "build-app: VERSION ($VERSIO) no coincideix amb WarpLaunch.versio ($VERSIO_CODI)" >&2
    exit 1
fi

# Una còpia amb l'adreça s'actualitza sola a tots els Macs on vagi: ha de ser la del certificat de debò.
if [[ "$AMB_FEED" -eq 1 && -n "${WARP_LAUNCH_IDENTITAT:-}" ]]; then
    echo "build-app: --amb-feed no accepta WARP_LAUNCH_IDENTITAT: una còpia per publicar es signa amb el certificat de debò." >&2
    exit 1
fi
if [[ "$AMB_FEED" -eq 1 && ! -f "$FEED" ]]; then
    echo "build-app: --amb-feed necessita «${FEED}», i no hi és." >&2
    exit 1
fi

# Amb el certificat propi, macOS reconeix l'app com la mateixa entre compilacions, i els permisos que se li donen
# (llegir les dades de Warp) no es perden. Amb la signatura ad hoc, cada compilació és una app nova per a macOS.
# La primera vegada, macOS pot demanar si `codesign` pot fer servir la clau: «Permet sempre».
IDENTITAT="${WARP_LAUNCH_IDENTITAT:-Warp Launch Dev}"
IDENTITATS="$(security find-identity -p codesigning)"
if grep -qF "\"$IDENTITAT\"" <<< "$IDENTITATS"; then
    FIRMA="$IDENTITAT"
elif [[ "$AMB_FEED" -eq 1 ]]; then
    echo "build-app: --amb-feed necessita el certificat «${IDENTITAT}», i no és al clauer." >&2
    exit 1
else
    FIRMA="-"
    echo "build-app: no hi ha el certificat «${IDENTITAT}» al clauer: signatura ad hoc." >&2
    echo "build-app: macOS tornarà a bloquejar la lectura de Warp fins que hi tornis a donar permís (D12)." >&2
fi

# SwiftPM no hi posa la ruta on l'app trobarà el framework dins del paquet.
swift build -c "$CONFIG" --product WarpLaunch -Xlinker -rpath -Xlinker "$RPATH"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/WarpLaunch" "$APP/Contents/MacOS/WarpLaunch"
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN/Sparkle.framework" "$FW"
# Els serveis XPC només calen amb sandbox, i aquesta app no en té.
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
sed "s/__VERSIO__/$VERSIO/g" Recursos/Info.plist > "$APP/Contents/Info.plist"
if [[ "$AMB_FEED" -eq 1 ]]; then
    /usr/libexec/PlistBuddy -c "Merge $FEED" "$APP/Contents/Info.plist" > /dev/null
fi
plutil -lint "$APP/Contents/Info.plist" > /dev/null
cp -R Recursos/ca.lproj "$APP/Contents/Resources/"
# La llicència (MIT) va dins de l'app: qui la rep compilada també la rep. I la de Sparkle, que hi va inclòs.
cp -X LICENSE "$APP/Contents/Resources/LICENSE"
cp -X .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/LICENSE-Sparkle"

# La icona ja compilada (scripts/icona-compila.sh, que necessita Xcode). Aquí n'hi ha prou amb les Command Line Tools.
if [[ -d Recursos/AppIcon.icon ]]; then
    if [[ ! -f Recursos/Assets.car || -n "$(find Recursos/AppIcon.icon -newer Recursos/Assets.car | head -1)" ]]; then
        echo "build-app: la icona ha canviat i cal tornar-la a compilar: scripts/icona-compila.sh" >&2
        exit 1
    fi
    cp -X Recursos/Assets.car Recursos/AppIcon.icns "$APP/Contents/Resources/"
fi

if ! otool -l "$APP/Contents/MacOS/WarpLaunch" | grep -qF "path $RPATH "; then
    echo "build-app: l'executable no porta la ruta «${RPATH}»: no trobaria Sparkle." >&2
    exit 1
fi

# De dins cap a fora: una signatura de fora tanca les de dins. Sense `--options runtime` fins que hi hagi Developer ID.
signa() { codesign --force --sign "$FIRMA" --timestamp=none "$1"; }
signa "$FW/Versions/B/Autoupdate"
signa "$FW/Versions/B/Updater.app"
signa "$FW"
signa "$APP"
# Sense `--deep`, no es veuria un framework a mig signar.
codesign --verify --deep --strict "$APP"

echo "$APP ($VERSIO, $CONFIG)"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => /identitat per a macOS: /p'
