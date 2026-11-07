#!/bin/bash
# Copia Warp Launch a /Applications (pas 12 de docs/disseny.md). Al Mac d'en David, regla 3 de CLAUDE.md: només amb el seu OK.
#
# Ús:
#   scripts/instal·la.sh                     # mode de prova: diu què faria, i no copia res
#   scripts/instal·la.sh --aplica            # copia «build/Warp Launch.app» (substitueix la d'abans, si és de Warp Launch)
#   scripts/instal·la.sh --github [--aplica] [--versio 0.27.3]
#       # la baixa de GitHub, compilada (l'última versió publicada amb scripts/publica.sh, o la que diguis), sense el repo
#       # ni les eines de compilació. Cal `gh` amb una sessió que vegi el repo. Des de qualsevol carpeta, sense el repo:
#       #   s="$(gh api -H 'Accept: application/vnd.github.raw' repos/David-Erra/warp-launch/contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica
#       # (no `bash <(…)`: si gh falla, bash executaria el JSON de l'error). Cal un compte d'administrador del Mac, sense sudo.
#
# - No registra cap arrencada automàtica, no obre l'app i no toca la configuració (~/.config/warp-launch).
# - Si l'app és oberta, s'atura sense tancar-la: primer en surts tu.
# - Si a /Applications hi ha una «Warp Launch.app» que no és d'aquesta app (un altre identificador), no la toca.
# - Amb --github, només instal·la una app signada amb el certificat «Warp Launch Dev» d'en David (el requisit de sota).
# - Proves: WARP_LAUNCH_ORIGEN, WARP_LAUNCH_DESTI, WARP_LAUNCH_REPO i WARP_LAUNCH_REQUISIT canvien l'app d'origen, la carpeta
#   de destí, el repo de GitHub i el requisit de la signatura.
set -euo pipefail

IDENTIFICADOR="cat.davide.warp-launch"
REPO="${WARP_LAUNCH_REPO:-David-Erra/warp-launch}"
# El certificat «Warp Launch Dev» (D12 de docs/especificacio.md), fins al 2036: `codesign -dr - "/Applications/Warp Launch.app"`.
REQUISIT="${WARP_LAUNCH_REQUISIT:-identifier \"$IDENTIFICADOR\" and certificate leaf = H\"c1ec55b1cb87c881a2c48a4f5256b10ebc12bcc6\"}"
DESTI_CARPETA="${WARP_LAUNCH_DESTI:-/Applications}"
DESTI="$DESTI_CARPETA/Warp Launch.app"

APLICA=0
GITHUB=0
VERSIO_DEMANADA=""
US="ús: scripts/instal·la.sh [--aplica] | --github [--aplica] [--versio <x.y.z>]"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --aplica) APLICA=1 ;;
        --github) GITHUB=1 ;;
        --versio) [[ $# -ge 2 ]] || { echo "$US" >&2; exit 64; }; VERSIO_DEMANADA="$2"; shift ;;
        *) echo "$US" >&2; exit 64 ;;
    esac
    shift
done
if [[ -n "$VERSIO_DEMANADA" && "$GITHUB" -eq 0 ]]; then echo "$US" >&2; exit 64; fi
# Les etiquetes de GitHub porten la «v» (v0.27.3): s'accepta amb i sense.
VERSIO_DEMANADA="${VERSIO_DEMANADA#v}"

identificador() { /usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }
versio() { /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || true; }

# L'app oberta (de /Applications, de build/ o de .build/) faria servir els fitxers que se substitueixen.
if pgrep -x WarpLaunch > /dev/null; then
    echo "instal·la: Warp Launch és oberta. Surt-ne (menú de la icona › Surt) i torna-ho a provar. No s'ha copiat res." >&2
    exit 1
fi

# A /Applications només hi escriuen els administradors. Amb sudo no funcionaria: gh perdria la sessió.
if [[ ! -w "$DESTI_CARPETA" ]]; then
    echo "instal·la: aquest compte no pot escriure a «${DESTI_CARPETA}»: cal entrar amb un compte d'administrador del Mac (no amb sudo). No s'ha copiat res." >&2
    exit 1
fi

TEMPORAL=""
NOU=""
neteja() { rm -rf "$NOU"; [[ -z "$TEMPORAL" ]] || rm -rf "$TEMPORAL"; }
trap neteja EXIT

if [[ "$GITHUB" -eq 1 ]]; then
    if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]]; then
        echo "instal·la: Warp Launch només es compila per a Macs amb Apple Silicon (M1 o posterior). No s'ha copiat res." >&2
        exit 1
    fi
    MACOS="$(sw_vers -productVersion)"
    if [[ "${MACOS%%.*}" -lt 26 ]]; then
        echo "instal·la: cal macOS 26 o posterior (aquest Mac té el ${MACOS}). No s'ha copiat res." >&2
        exit 1
    fi
    if ! command -v gh > /dev/null; then
        echo "instal·la: cal l'eina de GitHub, \`gh\`: instal·la-la amb \`brew install gh\` o des de https://cli.github.com," >&2
        echo "i entra-hi amb \`gh auth login\`. No s'ha copiat res." >&2
        exit 1
    fi
    TEMPORAL="$(mktemp -d "${TMPDIR:-/tmp}/warp-launch-installa.XXXXXX")"
    ETIQUETA=()
    [[ -z "$VERSIO_DEMANADA" ]] || ETIQUETA=("v$VERSIO_DEMANADA")
    if ! gh release download ${ETIQUETA[@]+"${ETIQUETA[@]}"} --repo "$REPO" --pattern 'WarpLaunch-*.zip' --dir "$TEMPORAL" > /dev/null; then
        # (bash 3.2 no admet un apòstrof dins de «${…:-…}» entre cometes dobles: textos amb variables a part.)
        if [[ -n "$VERSIO_DEMANADA" ]]; then
            QUINA="la $VERSIO_DEMANADA"
            PISTA="Potser la ${VERSIO_DEMANADA} no està publicada: mira les que hi ha amb \`gh release list --repo ${REPO}\`."
        else
            QUINA="l'última versió"
            PISTA="Potser encara no hi ha cap versió publicada, o ha fallat la connexió."
        fi
        echo "instal·la: no s'ha pogut baixar ${QUINA} de Warp Launch de ${REPO}. ${PISTA}" >&2
        echo "Si no, mira \`gh auth status\`: has d'haver entrat a \`gh\` amb un compte de GitHub. No s'ha copiat res." >&2
        exit 1
    fi
    ZIPS=("$TEMPORAL"/WarpLaunch-*.zip)
    if [[ ${#ZIPS[@]} -ne 1 || ! -f "${ZIPS[0]}" ]]; then
        echo "instal·la: la versió de GitHub no porta un sol WarpLaunch-*.zip. No s'ha copiat res." >&2
        exit 1
    fi
    ditto -x -k "${ZIPS[0]}" "$TEMPORAL/app"
    ORIGEN="$TEMPORAL/app/Warp Launch.app"
    if [[ ! -d "$ORIGEN" || "$(identificador "$ORIGEN")" != "$IDENTIFICADOR" ]]; then
        echo "instal·la: el fitxer baixat no porta cap app de Warp Launch. No s'ha copiat res." >&2
        exit 1
    fi
    # codesign: 3 vol dir que no compleix el requisit; qualsevol altre error (el requisit mateix, una signatura trencada), es diu tal qual.
    CODI=0
    ERROR="$(codesign --verify --strict -R="$REQUISIT" "$ORIGEN" 2>&1)" || CODI=$?
    if [[ "$CODI" -eq 3 ]]; then
        echo "instal·la: l'app baixada no està signada amb el certificat d'en David («Warp Launch Dev»): no la instal·lo." >&2
        exit 1
    elif [[ "$CODI" -ne 0 ]]; then
        echo "instal·la: no s'ha pogut comprovar la signatura de l'app baixada (codesign, codi ${CODI}): ${ERROR}" >&2
        exit 1
    fi
    FONT="GitHub ($REPO)"
else
    cd "$(dirname "$0")/.."
    ORIGEN="${WARP_LAUNCH_ORIGEN:-build/Warp Launch.app}"
    if [[ ! -d "$ORIGEN" || "$(identificador "$ORIGEN")" != "$IDENTIFICADOR" ]]; then
        echo "instal·la: no hi ha cap app de Warp Launch a «${ORIGEN}»: primer scripts/build-app.sh" >&2
        exit 1
    fi
    codesign --verify --strict "$ORIGEN" || { echo "instal·la: la signatura de «${ORIGEN}» no és vàlida" >&2; exit 1; }
    FONT="«${ORIGEN}»"
fi

ANTIGA=""
if [[ -e "$DESTI" || -L "$DESTI" ]]; then
    if [[ -L "$DESTI" || ! -d "$DESTI" || "$(identificador "$DESTI")" != "$IDENTIFICADOR" ]]; then
        echo "instal·la: a «${DESTI}» hi ha una altra cosa que no és Warp Launch: no la toco." >&2
        exit 1
    fi
    ANTIGA="$(versio "$DESTI")"
fi

NOVA="$(versio "$ORIGEN")"
if [[ -n "$ANTIGA" ]]; then
    ACCIO="substituiria Warp Launch $ANTIGA per la $NOVA"
else
    ACCIO="copiaria Warp Launch $NOVA"
fi

if [[ "$APLICA" -eq 0 ]]; then
    echo "Mode de prova: no s'ha copiat res."
    echo "Amb --aplica, $ACCIO (de ${FONT}) a «${DESTI}»."
    exit 0
fi

# Primer, una còpia al costat; després, el canvi. Si alguna cosa falla, la d'abans continua al seu lloc.
NOU="$DESTI_CARPETA/.Warp Launch.app.nova-$$"
ditto "$ORIGEN" "$NOU"
codesign --verify --strict "$NOU"
if [[ "$GITHUB" -eq 1 ]]; then
    # Si el que l'ha baixat la marca com a baixada d'internet, macOS no l'obriria (no és signada per Apple). La signatura
    # ja s'ha comprovat amb el certificat d'en David.
    xattr -dr com.apple.quarantine "$NOU" 2> /dev/null || true
fi
if [[ -n "$ANTIGA" ]]; then
    VELLA="$DESTI_CARPETA/.Warp Launch.app.vella-$$"
    mv "$DESTI" "$VELLA"
    mv "$NOU" "$DESTI"
    # La nova ja és al seu lloc: si la d'abans no es pot esborrar (d'un altre compte, per exemple), només s'avisa.
    rm -rf "$VELLA" 2> /dev/null || AVIS_VELLA="$VELLA"
else
    mv "$NOU" "$DESTI"
fi
NOU=""

if [[ -n "$ANTIGA" ]]; then
    echo "Fet: s'ha substituït Warp Launch $ANTIGA per la $NOVA a «${DESTI}». No s'ha obert ni registrat res."
else
    echo "Fet: Warp Launch $NOVA és a «${DESTI}». No s'ha obert ni registrat res."
fi
if [[ -n "${AVIS_VELLA:-}" ]]; then
    echo "Avís: la versió d'abans ha quedat a «${AVIS_VELLA}» (amagada) i no s'ha pogut esborrar: esborra-la a mà." >&2
fi
cat <<EOF

Per desinstal·lar-la:
  1. Surt de l'app (menú de la icona › Surt).
  2. Esborra «${DESTI}».
  3. Si vols treure'n també les dades: ~/.config/warp-launch/ (la teva configuració; fes-ne còpia abans),
     ~/Library/Preferences/$IDENTIFICADOR.plist i ~/Library/Saved Application State/$IDENTIFICADOR.savedState.
  4. El permís per llegir les dades de Warp: tccutil reset All $IDENTIFICADOR
EOF
