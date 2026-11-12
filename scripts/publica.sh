#!/bin/bash
# Publica a GitHub la versió de VERSION, compilada i signada, perquè altres Macs la instal·lin sense compilar, i posa al dia la
# recepta de Homebrew (README.md). Regla 3 de CLAUDE.md: només amb un OK explícit, cada vegada.
#
# Ús:
#   scripts/publica.sh            # mode de prova: compila, ho comprova tot i diu què publicaria i quin canvi faria a la recepta; no escriu res
#   scripts/publica.sh --aplica   # a més, signa el zip amb la clau del clauer, crea la versió vX.Y.Z a GitHub, amb WarpLaunch-X.Y.Z.zip i
#                                 # appcast.xml, i escriu la recepta nova. L'executa la persona que publica, al seu terminal, cap agent: arriba sol a tots els Macs.
#   scripts/publica.sh --beta [--aplica]
#                                 # una versió de prova, per a uns quants provadors: igual, però com a pre-release de GitHub, que mai no és
#                                 # l'última (cap còpia no hi arriba sola), i sense tocar la recepta. S'instal·la amb `instal·la.sh --github --versio X.Y.Z`.
#   scripts/publica.sh --promou X.Y.Z [--aplica]
#                                 # passa la versió de prova vX.Y.Z, ja publicada, a l'última (arriba sola a tots els Macs), i posa a la recepta el
#                                 # sha256 del zip que hi ha publicat. No compila ni signa res: comprova el zip i l'appcast.xml que baixa.
#
# - Només publica el que hi ha a origin/main, sense canvis per fer commit, i una versió que encara no hi sigui.
# - Només amb la signatura «Warp Launch Dev» (D12): una app signada ad hoc no es pot instal·lar amb --github.
# - Abans de compilar llegeix la recepta (Casks/warp-launch.rb del tap) i refusa publicar si no s'hi pot arribar, si no té exactament
#   una línia `  version "X.Y.Z"`, una `  sha256 "…"` i la `  url` amb `#{version}`, si ja va per davant de VERSION, o si falten
#   git config user.name o user.email (l'autor del commit del tap). Amb --beta, no la llegeix.
# - Si, ja publicada la versió, no pot escriure la recepta, o GitHub no la dona com a última amb el seu appcast.xml, no esborra res: diu què
#   cal fer a mà i surt amb el codi 2. Una versió publicada ja no es desfà: es para com diu docs/disseny.md, «Aturar una versió dolenta».
# - Amb --aplica, cal GH_TOKEN d'un compte que pugui escriure al repo i al tap, passat només a aquesta ordre (la compilació no el veu).
# - Compila amb --amb-feed: només aquesta còpia porta l'adreça de les actualitzacions. Refusa si la recepta no té `auto_updates true`, si l'última
#   versió de GitHub ja és aquesta o una de més nova, si falta el framework o si alguna de les seves peces no és del nostre certificat.
# - Betes (docs/disseny.md, secció 11, «Betes»): VERSION, sense cap sufix (Sparkle llegeix 0.35.0-beta com la 0.35.0), ha de ser posterior a
#   l'última versió normal. GitHub no dona mai una pre-release com a última, i l'app només llegeix l'appcast.xml de l'última. Una versió de
#   prova no es torna a publicar amb el mateix número: per fer-la normal, --promou.
# - Proves: WARP_LAUNCH_REPO, WARP_LAUNCH_TAP, WARP_LAUNCH_REQUISIT i WARP_LAUNCH_REQUISIT_SPARKLE canvien el repo de GitHub, el tap i el
#   requisit de la signatura de l'app i de les peces de Sparkle; WARP_LAUNCH_SIGN_UPDATE i WARP_LAUNCH_VERIFICA, les eines de signar i comprovar. Contra el repo de debò, aquestes quatre no valen.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTIFICADOR="cat.davide.warp-launch"
REPO="${WARP_LAUNCH_REPO:-David-Erra/warp-launch}"
TAP="${WARP_LAUNCH_TAP:-David-Erra/homebrew-tap}"
CAMI_RECEPTA="Casks/warp-launch.rb"
# El mateix requisit que comprova `instal·la.sh --github`.
REQUISIT="${WARP_LAUNCH_REQUISIT:-identifier \"$IDENTIFICADOR\" and certificate leaf = H\"c1ec55b1cb87c881a2c48a4f5256b10ebc12bcc6\"}"
# Cada peça de Sparkle té el seu identificador: el que han de compartir amb l'app és el certificat.
REQUISIT_SPARKLE="${WARP_LAUNCH_REQUISIT_SPARKLE:-${REQUISIT#* and }}"
APP="build/Warp Launch.app"
INFO="$APP/Contents/Info.plist"
# D'aquí surten l'adreça i la clau que porta la còpia publicada. L'adreça ha de ser la d'aquest repo: si no, cap còpia no trobaria les versions noves.
FITXER_FEED="Recursos/Actualitzacions.plist"
FEED_ESPERAT="https://github.com/$REPO/releases/latest/download/appcast.xml"

llegeix_plist() { /usr/libexec/PlistBuddy -c "Print $1" "$2" 2>/dev/null || true; }
# La versió més gran de les dues, com a nombres: la 0.100 és posterior a la 0.28.
mes_gran() { printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

# normal: la versió de VERSION, que passa a ser l'última. beta: la de VERSION, com a versió de prova. promou: una versió de prova ja publicada.
MODE=normal
APLICA=0
VERSIO_PROMOU=""
US="ús: scripts/publica.sh [--beta] [--aplica] | --promou <x.y.z> [--aplica]"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --aplica) APLICA=1 ;;
        --beta) [[ "$MODE" == normal ]] || { echo "$US" >&2; exit 64; }; MODE=beta ;;
        --promou) [[ "$MODE" == normal && $# -ge 2 ]] || { echo "$US" >&2; exit 64; }; MODE=promou; VERSIO_PROMOU="$2"; shift ;;
        *) echo "$US" >&2; exit 64 ;;
    esac
    shift
done

# Aquestes variables canvien qui signa i què es comprova: contra el repo de debò, una que hagi quedat definida publicaria sense les comprovacions.
if [[ "$(tr '[:upper:]' '[:lower:]' <<< "$REPO")" == david-erra/warp-launch ]]; then
    for VARIABLE in WARP_LAUNCH_SIGN_UPDATE WARP_LAUNCH_VERIFICA WARP_LAUNCH_REQUISIT WARP_LAUNCH_REQUISIT_SPARKLE; do
        if [[ -n "${!VARIABLE:-}" ]]; then
            echo "publica: ${VARIABLE} i les altres variables de signar i comprovar només valen per a proves, no contra ${REPO}. No s'ha publicat res." >&2
            exit 1
        fi
    done
fi

if [[ "$MODE" == promou ]]; then
    # Les etiquetes de GitHub porten la «v» (v0.35.0): s'accepta amb i sense, com a instal·la.sh.
    VERSIO="${VERSIO_PROMOU#v}"
    D_ON="la versió demanada"
    DE_VERSION=""
else
    VERSIO="$(tr -d '[:space:]' < VERSION)"
    D_ON="VERSION"
    DE_VERSION=" de VERSION"
fi
# Va a l'etiqueta, a la URL i a la substitució de la recepta, i la recepta només en sap llegir aquesta forma.
FORMA_VERSIO='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ ! "$VERSIO" =~ $FORMA_VERSIO ]]; then
    PISTA=""
    if [[ "$MODE" == beta ]]; then PISTA=" Una versió de prova tampoc no porta cap sufix: Sparkle llegeix 0.35.0-beta com la 0.35.0."; fi
    echo "publica: ${D_ON} («${VERSIO}») no té la forma X.Y.Z.${PISTA} No s'ha publicat res." >&2
    exit 1
fi
ETIQUETA="v$VERSIO"
NOM_ZIP="WarpLaunch-$VERSIO.zip"
ZIP="build/$NOM_ZIP"
URL_ZIP="https://github.com/$REPO/releases/download/$ETIQUETA/$NOM_ZIP"
APPCAST="build/appcast.xml"
SIGN_UPDATE="${WARP_LAUNCH_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
if [[ -n "${WARP_LAUNCH_VERIFICA:-}" ]]; then VERIFICA=("$WARP_LAUNCH_VERIFICA"); else VERIFICA=(swift scripts/verifica-signatura.swift); fi
# L'estat d'una versió, per etiqueta: si és de prova, si és un esborrany, i si porta el zip i l'appcast.xml. Una línia per a cada cosa.
JQ_ESTAT=".isPrerelease, .isDraft, (any(.assets[]; .name == \"appcast.xml\") and any(.assets[]; .name == \"$NOM_ZIP\"))"
ESTAT_DE_PROVA=true$'\n'false$'\n'true

command -v gh > /dev/null || { echo "publica: cal l'eina de GitHub, \`gh\`" >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
    echo "publica: hi ha canvis sense fer commit. No s'ha publicat res." >&2
    exit 1
fi
git fetch -q origin main
COMMIT="$(git rev-parse HEAD)"
if [[ "$COMMIT" != "$(git rev-parse origin/main)" ]]; then
    echo "publica: aquest commit no és el d'origin/main (primer fes push, o posa't al dia). No s'ha publicat res." >&2
    exit 1
fi
if [[ "$MODE" == promou ]]; then
    # Ha de ser a GitHub com a versió de prova, publicada (no un esborrany), amb el zip i l'appcast.xml.
    if ! ESTAT="$(gh release view "$ETIQUETA" --repo "$REPO" --json isPrerelease,isDraft,assets --jq "$JQ_ESTAT" 2> /dev/null)"; then
        echo "publica: no trobo la ${ETIQUETA} a ${REPO}: primer s'ha de publicar com a versió de prova (--beta). No s'ha publicat res." >&2
        exit 1
    fi
    if [[ "$(sed -n 1p <<< "$ESTAT")" != true ]]; then
        echo "publica: la ${ETIQUETA} de ${REPO} no és una versió de prova (pre-release): no hi ha res per promoure. No s'ha publicat res." >&2
        exit 1
    fi
    if [[ "$ESTAT" != "$ESTAT_DE_PROVA" ]]; then
        echo "publica: la ${ETIQUETA} de ${REPO} és un esborrany, o no porta ${NOM_ZIP} i appcast.xml. No s'ha publicat res." >&2
        exit 1
    fi
    # Les notes i l'avís són del commit de la versió de prova, el de la seva etiqueta: no del d'ara.
    if ! git fetch -q origin "refs/tags/$ETIQUETA" 2> /dev/null; then
        echo "publica: no trobo l'etiqueta ${ETIQUETA} a origin. No s'ha publicat res." >&2
        exit 1
    fi
    COMMIT="$(git rev-parse 'FETCH_HEAD^{commit}')"
else
    # També una versió de prova: no es torna a publicar amb el mateix número (el CDN de GitHub serviria el zip d'abans).
    if JA_HI_ES="$(gh release view "$ETIQUETA" --repo "$REPO" --json isPrerelease --jq '.isPrerelease' 2> /dev/null)"; then
        if [[ "$JA_HI_ES" == true && "$MODE" == normal ]]; then
            echo "publica: la ${ETIQUETA} ja és publicada a ${REPO} com a versió de prova. Per fer-la normal, sense compilar-la de nou: scripts/publica.sh --promou ${VERSIO}. No s'ha publicat res." >&2
        elif [[ "$JA_HI_ES" == true ]]; then
            echo "publica: la ${ETIQUETA} ja és publicada a ${REPO} com a versió de prova. Per publicar-ne una altra, primer puja VERSION. No s'ha publicat res." >&2
        else
            echo "publica: la ${ETIQUETA} ja és publicada a ${REPO}. Per publicar canvis, primer puja VERSION. No s'ha publicat res." >&2
        fi
        exit 1
    fi
    # Una etiqueta que ha quedat sense versió (la web de GitHub, o `gh release delete` sense --cleanup-tag, la deixen) faria que la
    # versió nova hi quedés lligada, al seu commit: GitHub no fa cas de --target si l'etiqueta ja existeix.
    REMOTA="$(git ls-remote --tags origin "refs/tags/$ETIQUETA" "refs/tags/$ETIQUETA^{}" | tail -n 1 | cut -f1)"
    if [[ -n "$REMOTA" && "$REMOTA" != "$COMMIT" ]]; then
        echo "publica: l'etiqueta ${ETIQUETA} ja existeix a origin, al commit ${REMOTA:0:7}, sense versió publicada. Esborra-la (git push origin :refs/tags/${ETIQUETA}) o puja VERSION. No s'ha publicat res." >&2
        exit 1
    fi
fi
# L'última versió normal publicada (sense esborranys ni versions de prova), per a les notes: el seu commit, sense desar l'etiqueta aquí.
ANTERIOR="$(gh release list --repo "$REPO" --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName // ""')"
BASE=""
if [[ -n "$ANTERIOR" ]]; then
    if ! git fetch -q origin "refs/tags/$ANTERIOR" 2> /dev/null; then
        echo "publica: no trobo l'etiqueta ${ANTERIOR} (l'última versió publicada) a origin, per a les notes. No s'ha publicat res." >&2
        exit 1
    fi
    BASE="$(git rev-parse 'FETCH_HEAD^{commit}')"
fi

TEMPORAL="$(mktemp -d)"
trap 'rm -rf "$TEMPORAL"' EXIT
# Una versió de prova no toca la recepta: Homebrew continua instal·lant l'última normal.
RECEPTA_CANVIA=0
if [[ "$MODE" != beta ]]; then
    # Abans de compilar res: l'autor del commit del tap ha de ser explícit (que no en surti cap altre correu), i la recepta s'ha de
    # poder llegir i tenir la forma que aquest script sap canviar. Si no, no es publica res.
    AUTOR_NOM="$(git config user.name || true)"
    AUTOR_CORREU="$(git config user.email || true)"
    if [[ -z "$AUTOR_NOM" || -z "$AUTOR_CORREU" ]]; then
        echo "publica: falta git config user.name o user.email, que seran l'autor del commit de la recepta de Homebrew. No s'ha publicat res." >&2
        exit 1
    fi
    RECEPTA="$TEMPORAL/recepta.rb"
    RECEPTA_NOVA="$TEMPORAL/recepta-nova.rb"
    # Una sola lectura, perquè el sha del blob i el contingut siguin de la mateixa versió del fitxer. El contingut, sempre en un fitxer:
    # una variable de bash perdria els salts de línia finals, i la resta de la recepta ha de quedar byte a byte igual.
    if ! RESPOSTA="$(gh api "repos/$TAP/contents/$CAMI_RECEPTA?ref=main" --jq '.encoding, .sha, .content')"; then
        echo "publica: no s'ha pogut llegir la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}). No s'ha publicat res." >&2
        exit 1
    fi
    SHA_BLOB="$(sed -n 2p <<< "$RESPOSTA")"
    # El sha de git del que s'ha descodificat ha de ser el que diu GitHub: el base64 de macOS no falla amb una entrada tallada.
    if [[ "$(sed -n 1p <<< "$RESPOSTA")" != base64 ]] || ! sed 1,2d <<< "$RESPOSTA" | base64 --decode > "$RECEPTA" ||
       [[ "$(git hash-object --no-filters -- "$RECEPTA")" != "$SHA_BLOB" ]]; then
        echo "publica: GitHub no ha tornat la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) com s'esperava. No s'ha publicat res." >&2
        exit 1
    fi
    # Exactament una línia de cada, amb aquesta forma: una altra (dins d'un bloc, amb un comentari al final, amb CRLF…) voldria dir endevinar.
    compta_linies() { LC_ALL=C grep -Eac "$1" "$RECEPTA" || true; }
    if [[ "$(compta_linies '^[[:space:]]*version([^[:alnum:]_]|$)')" != 1 || "$(compta_linies '^  version "[0-9]+\.[0-9]+\.[0-9]+"$')" != 1 ||
          "$(compta_linies '^[[:space:]]*sha256([^[:alnum:]_]|$)')" != 1 || "$(compta_linies '^  sha256 "[0-9a-f]{64}"$')" != 1 ]]; then
        echo "publica: la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) no té exactament una línia «  version \"X.Y.Z\"» i una línia «  sha256 \"…\"». No s'ha publicat res." >&2
        exit 1
    fi
    # La URL ha de dependre de `version` i ser la d'aquest repo: si no, la recepta nova demanaria un altre zip amb el sha256 d'aquest.
    URL_RECEPTA="  url \"https://github.com/$REPO/releases/download/v#{version}/WarpLaunch-#{version}.zip\""
    if [[ "$(LC_ALL=C grep -aFxc -- "$URL_RECEPTA" "$RECEPTA" || true)" != 1 ]]; then
        echo "publica: la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) no té exactament una línia «${URL_RECEPTA}». No s'ha publicat res." >&2
        exit 1
    fi
    # Sense això, Homebrew tornaria a instal·lar per sobre del que l'app s'ha actualitzat sola.
    if [[ "$(compta_linies '^[[:space:]]*auto_updates([^[:alnum:]_]|$)')" != 1 || "$(compta_linies '^  auto_updates true$')" != 1 ]]; then
        echo "publica: la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) no té exactament una línia «  auto_updates true». No s'ha publicat res." >&2
        exit 1
    fi
    VERSIO_ABANS="$(LC_ALL=C sed -nE 's/^  version "(.*)"$/\1/p' "$RECEPTA")"
    SHA256_ABANS="$(LC_ALL=C sed -nE 's/^  sha256 "(.*)"$/\1/p' "$RECEPTA")"
    # Si la recepta ja va per davant, la versió és enrere: qui fes `brew upgrade` baixaria de versió.
    if [[ "$(mes_gran "$VERSIO_ABANS" "$VERSIO")" != "$VERSIO" ]]; then
        echo "publica: la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) ja és a la ${VERSIO_ABANS}, més nova que la ${VERSIO}${DE_VERSION}: qui l'actualitzés baixaria de versió. No s'ha publicat res." >&2
        exit 1
    fi
fi

# `latest` és el que llegeixen totes les còpies: una versió que no hi passés al davant no arribaria a ningú. GitHub no hi compta mai les
# versions de prova. Una versió de prova també hi ha d'anar al davant: si no, l'endemà les seves còpies tornarien soles a l'última.
ULTIMA=""
if ULTIMA="$(gh release view --repo "$REPO" --json tagName --jq '.tagName' 2> /dev/null)"; then
    FORMA_ETIQUETA='^v[0-9]+\.[0-9]+\.[0-9]+$'
    if [[ ! "$ULTIMA" =~ $FORMA_ETIQUETA ]]; then
        echo "publica: l'última versió de ${REPO} («${ULTIMA}») no té la forma vX.Y.Z. No s'ha publicat res." >&2
        exit 1
    fi
    if [[ "${ULTIMA#v}" == "$VERSIO" || "$(mes_gran "${ULTIMA#v}" "$VERSIO")" != "$VERSIO" ]]; then
        if [[ "$MODE" == beta ]]; then
            PER_QUE="una versió de prova ha de ser posterior a l'última normal: si no, l'endemà les seves còpies hi tornarien soles."
        else
            PER_QUE="l'app no s'hi actualitzaria."
        fi
        echo "publica: l'última versió de ${REPO} és la ${ULTIMA}, que no és anterior a la ${VERSIO}${DE_VERSION}: ${PER_QUE} No s'ha publicat res." >&2
        exit 1
    fi
elif [[ -n "$ANTERIOR" ]]; then
    echo "publica: no s'ha pogut saber quina és l'última versió de ${REPO}. No s'ha publicat res." >&2
    exit 1
else
    ULTIMA=""
fi

FEED_DEL_FITXER="$(llegeix_plist SUFeedURL "$FITXER_FEED")"
CLAU_DEL_FITXER="$(llegeix_plist SUPublicEDKey "$FITXER_FEED")"
if [[ "$FEED_DEL_FITXER" != "$FEED_ESPERAT" || -z "$CLAU_DEL_FITXER" ]]; then
    echo "publica: «${FITXER_FEED}» ha de portar SUFeedURL = ${FEED_ESPERAT} i SUPublicEDKey. No s'ha publicat res." >&2
    exit 1
fi

comprova_signatura() {
    local CODI=0 ERROR
    ERROR="$(codesign --verify --deep --strict -R="$2" "$1" 2>&1)" || CODI=$?
    if [[ "$CODI" -eq 3 ]]; then
        echo "publica: «${1}» no està signada amb «Warp Launch Dev» (al clauer d'aquest Mac?). No s'ha publicat res." >&2
        exit 1
    elif [[ "$CODI" -ne 0 ]]; then
        echo "publica: no s'ha pogut comprovar la signatura de «${1}» (codesign, codi ${CODI}): ${ERROR}" >&2
        exit 1
    fi
}
# El paquet que va als Macs: el que s'acaba de compilar o, amb --promou, el del zip publicat.
comprova_paquet() {
    local PAQUET="$1" PECA
    local INFO_PAQUET="$1/Contents/Info.plist" FRAMEWORK="$1/Contents/Frameworks/Sparkle.framework"
    if [[ "$(llegeix_plist CFBundleShortVersionString "$INFO_PAQUET")" != "$VERSIO" ]]; then
        echo "publica: «${PAQUET}» no és la ${VERSIO}. No s'ha publicat res." >&2
        exit 1
    fi
    # Sparkle compara aquest número amb el de l'appcast: si no coincidissin, tothom es tornaria a actualitzar cada dia.
    if [[ "$(llegeix_plist CFBundleVersion "$INFO_PAQUET")" != "$VERSIO" ]]; then
        echo "publica: el CFBundleVersion de «${PAQUET}» no és ${VERSIO}. No s'ha publicat res." >&2
        exit 1
    fi
    if [[ "$(llegeix_plist SUFeedURL "$INFO_PAQUET")" != "$FEED_DEL_FITXER" || "$(llegeix_plist SUPublicEDKey "$INFO_PAQUET")" != "$CLAU_DEL_FITXER" ]]; then
        echo "publica: «${PAQUET}» no porta l'adreça i la clau de «${FITXER_FEED}». No s'ha publicat res." >&2
        exit 1
    fi
    if [[ ! -d "$FRAMEWORK" ]]; then
        echo "publica: «${PAQUET}» no porta Sparkle.framework. No s'ha publicat res." >&2
        exit 1
    fi
    comprova_signatura "$PAQUET" "$REQUISIT"
    # `--deep` comprova que les peces de dins siguin vàlides, però no qui les signa.
    for PECA in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK"; do
        comprova_signatura "$PECA" "$REQUISIT_SPARKLE"
    done
}

if [[ "$MODE" == promou ]]; then
    # Res de compilar: el zip que passarà a ser l'última és el que ja hi ha publicat, i el seu sha256 és el que va a la recepta.
    PUBLICADA="$TEMPORAL/publicada"
    mkdir "$PUBLICADA"
    if ! gh release download "$ETIQUETA" --repo "$REPO" --pattern "$NOM_ZIP" --pattern appcast.xml --dir "$PUBLICADA" > /dev/null ||
       [[ ! -f "$PUBLICADA/$NOM_ZIP" || ! -f "$PUBLICADA/appcast.xml" ]]; then
        echo "publica: no s'han pogut baixar ${NOM_ZIP} i appcast.xml de la ${ETIQUETA} de ${REPO}. No s'ha publicat res." >&2
        exit 1
    fi
    ZIP="$PUBLICADA/$NOM_ZIP"
    APPCAST="$PUBLICADA/appcast.xml"
    if ! ditto -x -k "$ZIP" "$PUBLICADA/app" 2> /dev/null; then
        echo "publica: el ${NOM_ZIP} de la ${ETIQUETA} no es pot obrir. No s'ha publicat res." >&2
        exit 1
    fi
    comprova_paquet "$PUBLICADA/app/Warp Launch.app"
else
    # La compilació no necessita el token, i SwiftPM executa codi: que no el vegi.
    env -u GH_TOKEN -u GITHUB_TOKEN scripts/build-app.sh release --amb-feed
    comprova_paquet "$APP"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
fi
MIDA="$(du -h "$ZIP" | cut -f1 | tr -d ' ')"
MIDA_BYTES="$(stat -f %z "$ZIP")"
SHA256_ZIP="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

if [[ "$MODE" == promou ]]; then
    # L'appcast.xml que passarà a llegir tothom ha de ser el d'aquest zip (la versió, l'adreça i la mida), signat amb la clau que porten les apps.
    # Només la clau pública: no toca el clauer.
    compta_appcast() { LC_ALL=C grep -aFc -- "$1" "$APPCAST" || true; }
    ENCLOSURE="<enclosure url=\"$URL_ZIP\" length=\"$MIDA_BYTES\" type=\"application/octet-stream\" sparkle:edSignature=\""
    if ! xmllint --noout "$APPCAST" 2> /dev/null || [[ "$(compta_appcast '<item>')" != 1 ||
          "$(compta_appcast "<sparkle:version>$VERSIO</sparkle:version>")" != 1 ||
          "$(compta_appcast "<sparkle:shortVersionString>$VERSIO</sparkle:shortVersionString>")" != 1 || "$(compta_appcast "$ENCLOSURE")" != 1 ]]; then
        echo "publica: l'appcast.xml de la ${ETIQUETA} no és el del seu zip (la versió, l'adreça o la mida). No s'ha publicat res." >&2
        exit 1
    fi
    FORMA_ENCLOSURE='sparkle:edSignature="([A-Za-z0-9+/]{86}==)"/>$'
    if [[ ! "$(LC_ALL=C grep -aF -- "$ENCLOSURE" "$APPCAST")" =~ $FORMA_ENCLOSURE ]]; then
        echo "publica: la signatura de l'appcast.xml de la ${ETIQUETA} no té la forma esperada. No s'ha publicat res." >&2
        exit 1
    fi
    if ! env -u GH_TOKEN -u GITHUB_TOKEN "${VERIFICA[@]}" "$CLAU_DEL_FITXER" "${BASH_REMATCH[1]}" "$ZIP"; then
        echo "publica: la signatura de l'appcast.xml de la ${ETIQUETA} no és la del seu zip amb la clau que porten les apps. No s'ha publicat res." >&2
        exit 1
    fi
fi

if [[ "$MODE" != beta ]]; then
    # Amb LC_ALL=C, sed no refusa cap byte i deixa la resta com és (també si l'última línia no acaba amb un salt de línia).
    LC_ALL=C sed -E -e "s/^  version \"[^\"]*\"\$/  version \"$VERSIO\"/" -e "s/^  sha256 \"[^\"]*\"\$/  sha256 \"$SHA256_ZIP\"/" "$RECEPTA" > "$RECEPTA_NOVA"
    CONTINGUT_NOU="$(base64 < "$RECEPTA_NOVA" | tr -d '\n')"
    # Si ja diu això mateix (una versió esborrada i tornada a publicar amb el mateix zip), no hi ha res per escriure.
    RECEPTA_CANVIA=1
    if cmp -s "$RECEPTA" "$RECEPTA_NOVA"; then
        RECEPTA_CANVIA=0
    fi
fi

# Amb --promou, les notes passen a ser les d'una versió normal: les de prova deien com instal·lar-la a mà.
mkdir -p build
NOTES="build/notes-$VERSIO.md"
ORDRE_GITHUB="s=\"\$(gh api -H 'Accept: application/vnd.github.raw' repos/$REPO/contents/scripts/instal%C2%B7la.sh)\" && bash -c \"\$s\" instal·la --github"
{
    if [[ "$MODE" == beta ]]; then
        echo "**Versió de prova**, per a uns quants provadors. No és l'última versió de Warp Launch: Homebrew no la instal·la, i cap còpia no s'hi actualitza sola."
        echo
    fi
    if [[ -n "$BASE" ]]; then
        echo "Canvis des de la ${ANTERIOR}:"
        echo
        git log --no-merges --format='- %s' "$BASE..$COMMIT"
    else
        echo "Primera versió publicada."
    fi
    echo
    if [[ "$MODE" == beta ]]; then
        echo "Per instal·lar-la, amb l'eina de GitHub (cal \`gh auth login\`; Apple Silicon, macOS 26 o posterior i un compte d'administrador del Mac):"
        echo
        echo '```bash'
        echo "$ORDRE_GITHUB --versio $VERSIO --aplica"
        echo '```'
        echo
        echo "Les versions de prova següents també s'instal·len així, a mà. **Quan es publiqui una versió normal posterior, l'app s'hi actualitzarà sola** (amb «Actualitza automàticament» encès), i ja no tornarà a les de prova. Per tornar a l'última versió normal: la mateixa ordre, sense \`--versio $VERSIO\`."
    else
        echo "Per instal·lar-la amb Homebrew (Apple Silicon, macOS 26 o posterior i un compte d'administrador del Mac):"
        echo
        echo '```bash'
        echo "brew install --cask david-erra/tap/warp-launch"
        echo '```'
        echo
        echo "Per actualitzar-la a mà:"
        echo
        echo '```bash'
        echo "brew upgrade --cask warp-launch"
        echo '```'
        echo
        echo "Com a alternativa, per instal·lar-la o actualitzar-la sense Homebrew, amb l'eina de GitHub (cal \`gh auth login\`):"
        echo
        echo '```bash'
        echo "$ORDRE_GITHUB --aplica"
        echo '```'
        echo
        echo "**L'app s'actualitza sola** des de la 0.33.0: un cop al dia mira a GitHub si hi ha una versió nova (GitHub veu la teva adreça IP i la versió de l'app) i, quan no la fas servir, es reinicia. Warp i Claude no es tanquen. Va encès de sèrie; per apagar-ho, Configuració › «Actualitzacions» › «Actualitza automàticament»."
        echo
        echo "Si tens la 0.31.5 o una d'anterior, l'has d'actualitzar a mà una última vegada, amb les ordres d'aquí dalt. Des de llavors, és automàtic."
    fi
} > "$NOTES"

if [[ "$MODE" != promou ]]; then
    # El fitxer que llegeix cada còpia. Sense l'eina d'appcasts de Sparkle, que escriu a ~/Library/Caches i toca el clauer. Tots els valors són segurs per a l'XML:
    # VERSION i la signatura tenen forma coneguda, i el repo és un nom de GitHub.
    rm -f "$APPCAST"
    MINIM_SISTEMA="$(llegeix_plist LSMinimumSystemVersion "$INFO")"
    if [[ -z "$MINIM_SISTEMA" ]]; then
        echo "publica: «${APP}» no diu quina versió de macOS necessita. No s'ha publicat res." >&2
        exit 1
    fi
fi
escriu_appcast() {
    cat > "$1" <<APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Warp Launch</title>
        <item>
            <title>$VERSIO</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$VERSIO</sparkle:version>
            <sparkle:shortVersionString>$VERSIO</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MINIM_SISTEMA</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="$URL_ZIP" length="$MIDA_BYTES" type="application/octet-stream" sparkle:edSignature="$2"/>
        </item>
    </channel>
</rss>
APPCAST
    if ! xmllint --noout "$1"; then
        echo "publica: «${1}» no és un XML vàlid. No s'ha publicat res." >&2
        exit 1
    fi
}

# Sense res per comparar, tot és nou.
CANVIS="$(if [[ -n "$BASE" ]]; then git diff --name-only "$BASE..$COMMIT"; fi)"
if [[ -z "$BASE" ]] || grep -qFx -e Package.resolved -e Sources/WarpLaunchApp/ServeiActualitzacions.swift -e scripts/build-app.sh <<< "$CANVIS"; then
    echo "Avís: aquesta versió canvia l'actualitzador (Sparkle, ServeiActualitzacions.swift o build-app.sh). Si l'espatlla, les còpies que la rebin no s'arreglaran soles: com s'atura, docs/disseny.md, secció 11, apartat 7."
fi

if [[ "$APLICA" -eq 0 ]]; then
    if [[ "$MODE" == promou ]]; then
        echo "Mode de prova: no s'ha publicat res."
        echo "Amb --aplica, passaria la ${ETIQUETA} de ${REPO} (versió de prova, commit ${COMMIT:0:7}) a l'última versió: arribaria sola a tots els Macs."
        echo "Amb el zip ($MIDA) i l'appcast.xml que ja hi ha publicats, comprovats aquí: no compilaria ni signaria res."
    else
        APPCAST_PROVA="build/appcast-prova-$VERSIO.xml"
        escriu_appcast "$APPCAST_PROVA" SENSE-SIGNAR
        echo "Mode de prova: no s'ha publicat res."
        if [[ "$MODE" == beta ]]; then
            echo "Amb --aplica, publicaria Warp Launch $VERSIO a $REPO com a ${ETIQUETA} (commit ${COMMIT:0:7}), amb $ZIP ($MIDA), com a versió de prova: una pre-release, que no és l'última i a la qual no arriba sola cap còpia."
        else
            echo "Amb --aplica, publicaria Warp Launch $VERSIO a $REPO com a ${ETIQUETA} (commit ${COMMIT:0:7}), amb $ZIP ($MIDA)."
        fi
        echo "I el seu appcast.xml, signat amb la clau del clauer (aquí, sense signar: $APPCAST_PROVA)."
    fi
    if [[ "$MODE" == beta ]]; then
        echo "No tocaria la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP})."
    elif [[ "$RECEPTA_CANVIA" -eq 1 ]]; then
        echo "I canviaria la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}, amb l'autor ${AUTOR_NOM} <${AUTOR_CORREU}>):"
        echo "  version: ${VERSIO_ABANS} -> ${VERSIO}"
        if [[ "$MODE" == promou ]]; then
            echo "  sha256: ${SHA256_ABANS} -> ${SHA256_ZIP} (el del zip publicat)"
        else
            echo "  sha256: ${SHA256_ABANS} -> ${SHA256_ZIP} (el d'aquest zip; amb --aplica, el del zip que es pugi)"
        fi
    else
        echo "La recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) ja diu la ${VERSIO} i el sha256 d'aquest zip: no caldria escriure-la."
    fi
    echo "Notes ($NOTES):"
    sed 's/^/  /' "$NOTES"
    exit 0
fi

if [[ "$MODE" != promou ]]; then
    # El zip que es puja és el que es signa, i la clau ha de ser la que porten les apps: si no, totes les còpies baixarien la versió per refusar-la.
    # El token no fa falta per signar.
    if ! SORTIDA_SIGNATURA="$(env -u GH_TOKEN -u GITHUB_TOKEN "$SIGN_UPDATE" "$ZIP")"; then
        echo "publica: no s'ha pogut signar «${ZIP}» amb la clau del clauer. No s'ha publicat res." >&2
        exit 1
    fi
    FORMA_SIGNATURA='^sparkle:edSignature="([A-Za-z0-9+/]{86}==)" length="([0-9]+)"$'
    if [[ ! "$SORTIDA_SIGNATURA" =~ $FORMA_SIGNATURA ]]; then
        echo "publica: la signatura de «${ZIP}» no té la forma esperada. No s'ha publicat res." >&2
        exit 1
    fi
    SIGNATURA="${BASH_REMATCH[1]}"
    if [[ "${BASH_REMATCH[2]}" != "$MIDA_BYTES" ]]; then
        echo "publica: la signatura és d'un fitxer de ${BASH_REMATCH[2]} bytes, i «${ZIP}» en fa ${MIDA_BYTES}. No s'ha publicat res." >&2
        exit 1
    fi
    if ! env -u GH_TOKEN -u GITHUB_TOKEN "${VERIFICA[@]}" "$(llegeix_plist SUPublicEDKey "$INFO")" "$SIGNATURA" "$ZIP"; then
        echo "publica: la clau d'aquest clauer no és la que porten les apps. No s'ha publicat res." >&2
        exit 1
    fi
    escriu_appcast "$APPCAST" "$SIGNATURA"
fi

# Publicar ja no es desfà: qui l'hagi baixada la instal·larà. $1, el commit de la recepta, si n'hi ha.
com_es_para() {
    if [[ "$MODE" == beta ]]; then
        echo "Una versió de prova no arriba sola a cap còpia. Si surt malament, publica'n una altra amb una versió superior. No tornis a pujar un fitxer amb el mateix nom a la mateixa etiqueta."
        return
    fi
    echo "Publicar ja no es desfà. Per aturar aquesta versió (docs/disseny.md, «Aturar una versió dolenta»), en aquest ordre:"
    if [[ -n "$ULTIMA" ]]; then
        echo "  - gh release edit ${ULTIMA} --latest --repo $REPO"
    fi
    if [[ -n "${1:-}" ]]; then
        echo "  - git revert ${1} en un clon de ${TAP}, i push"
    fi
    echo "  - publica una correcció amb una versió superior. No tornis a pujar un fitxer amb el mateix nom a la mateixa etiqueta."
}

# Les dues línies que la recepta necessita, si s'han de posar a mà.
canvia_la_recepta_a_ma() {
    echo "Canvia a mà aquestes dues línies de ${CAMI_RECEPTA}, a la branca main de ${TAP}:"
    echo "  version \"${VERSIO}\""
    echo "  sha256 \"${SHA256_ZIP}\""
    if [[ "$VERSIO_ABANS" == "$VERSIO" ]]; then
        echo "Mentre no ho facis, Homebrew refusarà la ${VERSIO}: el sha256 de la recepta és el d'un altre zip."
    else
        echo "Mentre no ho facis, Homebrew continua instal·lant la ${VERSIO_ABANS}."
    fi
}

if [[ "$MODE" == promou ]]; then
    # Res més: el zip i l'appcast.xml ja hi són, i `latest` passa a aquesta en una sola ordre.
    if ! gh release edit "$ETIQUETA" --repo "$REPO" --prerelease=false --latest --notes-file "$NOTES"; then
        # Com amb `gh release create`, pot fallar quan GitHub ja l'ha canviada.
        if [[ "$(gh release view "$ETIQUETA" --repo "$REPO" --json isPrerelease,isDraft,assets --jq "$JQ_ESTAT" 2> /dev/null | sed -n 1p || true)" == false ]]; then
            {
                echo "publica: \`gh release edit\` ha fallat, però la ${ETIQUETA} de ${REPO} ja no és una versió de prova (no s'ha esborrat res): mira a la web de GitHub si és l'última."
                if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then canvia_la_recepta_a_ma; fi
                com_es_para
            } >&2
            exit 2
        fi
        echo "publica: no s'ha pogut passar la ${ETIQUETA} a l'última versió de ${REPO}: continua essent una versió de prova, i la recepta de Homebrew no s'ha tocat." >&2
        exit 1
    fi
else
    # Una versió de prova, mai com a l'última: és el que la separa de tothom.
    if [[ "$MODE" == beta ]]; then MARCA=(--prerelease --latest=false); else MARCA=(--latest); fi
    # Tots dos fitxers en una sola ordre: `latest` no canvia fins que hi són. Sense appcast, totes les còpies veurien un 404.
    if ! gh release create "$ETIQUETA" "$ZIP" "$APPCAST" --repo "$REPO" "${MARCA[@]}" --target "$COMMIT" --title "Warp Launch $VERSIO" --notes-file "$NOTES"; then
        # `gh` pot fallar quan GitHub ja l'ha publicada (una resposta perduda): llavors, no es pot dir que no s'ha creat.
        if [[ "$(gh release view "$ETIQUETA" --repo "$REPO" --json isDraft --jq '.isDraft' 2> /dev/null || true)" == false ]]; then
            if [[ "$MODE" == beta ]]; then QUE_MIRAR="i que sigui una versió de prova, no l'última"; else QUE_MIRAR="i si és l'última"; fi
            {
                echo "publica: \`gh release create\` ha fallat, però la ${ETIQUETA} ja és publicada a ${REPO} (no s'ha esborrat res): mira a la web de GitHub si hi ha el zip i l'appcast.xml, ${QUE_MIRAR}."
                if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then canvia_la_recepta_a_ma; fi
                com_es_para
            } >&2
            exit 2
        fi
        echo "publica: no s'ha pogut crear la ${ETIQUETA} a ${REPO}, i la recepta de Homebrew no s'ha tocat. Abans de tornar-ho a provar, mira si n'ha quedat un esborrany o l'etiqueta: gh release view ${ETIQUETA} --repo ${REPO}" >&2
        exit 1
    fi
fi

if [[ "$MODE" == beta ]]; then
    # GitHub no ha de donar mai una pre-release com a l'última: si ho fes, totes les còpies s'hi actualitzarien l'endemà.
    ULTIMA_DESPRES="$(gh release view --repo "$REPO" --json tagName --jq '.tagName' 2> /dev/null || true)"
    if [[ "$ULTIMA_DESPRES" == "$ETIQUETA" ]]; then
        {
            echo "publica: GitHub dona la ${ETIQUETA} com a l'última versió de ${REPO}: totes les còpies s'hi actualitzarien. Torna-ho enrere ara mateix, en aquest ordre:"
            if [[ -n "$ULTIMA" ]]; then echo "  - gh release edit ${ULTIMA} --latest --repo $REPO"; fi
            echo "  - gh release edit ${ETIQUETA} --prerelease --repo $REPO"
        } >&2
        exit 2
    fi
    if [[ "$(gh release view "$ETIQUETA" --repo "$REPO" --json isPrerelease,isDraft,assets --jq "$JQ_ESTAT" 2> /dev/null || true)" != "$ESTAT_DE_PROVA" ]]; then
        echo "publica: la ${ETIQUETA} ja és a ${REPO}, però GitHub no la dona com a versió de prova amb el seu zip i el seu appcast.xml (no s'ha esborrat res). Mira-ho a la web de GitHub." >&2
        exit 2
    fi
    echo "Fet: Warp Launch $VERSIO és publicada a $REPO com a versió de prova (${ETIQUETA}, pre-release). No és l'última: cap còpia no s'hi actualitza sola, i la recepta de Homebrew no s'ha tocat."
    echo "Les notes diuen com instal·lar-la (instal·la.sh --github --versio ${VERSIO}). Per fer-la normal, sense compilar-la de nou: scripts/publica.sh --promou ${VERSIO}."
    com_es_para
    exit 0
fi

# GitHub ho ha de dir: si no, les còpies no la veuran, o veurien un 404 (de l'appcast, o del zip quan el vagin a baixar).
ESTAT_PUBLICADA="$(gh release view --repo "$REPO" --json tagName,assets --jq ".tagName, (any(.assets[]; .name == \"appcast.xml\") and any(.assets[]; .name == \"$NOM_ZIP\"))" 2> /dev/null || true)"
if [[ "$ESTAT_PUBLICADA" != "$ETIQUETA"$'\n'true ]]; then
    {
        echo "publica: la ${ETIQUETA} ja és publicada a ${REPO}, però GitHub no la dona com a última amb el seu appcast.xml i el seu zip (no s'ha esborrat res): les còpies no s'hi actualitzaran. Mira-ho a la web de GitHub."
        if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then canvia_la_recepta_a_ma; fi
        com_es_para
    } >&2
    exit 2
fi

if [[ "$MODE" == promou ]]; then
    FET="Warp Launch $VERSIO (${ETIQUETA}) ja és l'última versió de $REPO, amb el zip que ja hi havia publicat"
else
    FET="Warp Launch $VERSIO és publicada a $REPO (${ETIQUETA})"
fi
if [[ "$RECEPTA_CANVIA" -eq 0 ]]; then
    echo "Fet: ${FET}. La recepta de ${TAP} ja deia aquesta versió i aquest sha256, i no s'ha escrit."
    com_es_para
    exit 0
fi

# La versió ja és a GitHub: d'aquí endavant, un error no l'esborra. El sha és el del blob llegit abans de compilar: si algú ha canviat
# la recepta mentrestant, GitHub refusa l'escriptura en lloc de trepitjar-la.
if ! COMMIT_TAP="$(gh api --method PUT "repos/$TAP/contents/$CAMI_RECEPTA" \
    -f "message=chore: warp-launch passa a la $VERSIO" -f "branch=main" -f "sha=$SHA_BLOB" -f "content=$CONTINGUT_NOU" \
    -f "author[name]=$AUTOR_NOM" -f "author[email]=$AUTOR_CORREU" \
    -f "committer[name]=$AUTOR_NOM" -f "committer[email]=$AUTOR_CORREU" --jq '.commit.sha')"; then
    {
        echo "publica: la ${ETIQUETA} ja és publicada a ${REPO} (no s'ha esborrat), però no s'ha pogut escriure la recepta de Homebrew a ${TAP}."
        canvia_la_recepta_a_ma
        com_es_para
    } >&2
    exit 2
fi
echo "Fet: ${FET}, i la recepta de ${TAP} ja la instal·la (sha256 ${SHA256_ZIP})."
com_es_para "$COMMIT_TAP"
