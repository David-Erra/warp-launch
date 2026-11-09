#!/bin/bash
# Publica a GitHub la versió de VERSION, compilada i signada, perquè altres Macs la instal·lin sense compilar, i posa al dia la
# recepta de Homebrew (README.md). Regla 3 de CLAUDE.md: només amb un OK explícit, cada vegada.
#
# Ús:
#   scripts/publica.sh            # mode de prova: compila, ho comprova tot i diu què publicaria i quin canvi faria a la recepta; no escriu res
#   scripts/publica.sh --aplica   # a més, signa el zip amb la clau del clauer, crea la versió vX.Y.Z a GitHub, amb WarpLaunch-X.Y.Z.zip i
#                                 # appcast.xml, i escriu la recepta nova. L'executa la persona que publica, al seu terminal, cap agent: arriba sol a tots els Macs.
#
# - Només publica el que hi ha a origin/main, sense canvis per fer commit, i una versió que encara no hi sigui.
# - Només amb la signatura «Warp Launch Dev» (D12): una app signada ad hoc no es pot instal·lar amb --github.
# - Abans de compilar llegeix la recepta (Casks/warp-launch.rb del tap) i refusa publicar si no s'hi pot arribar, si no té exactament
#   una línia `  version "X.Y.Z"`, una `  sha256 "…"` i la `  url` amb `#{version}`, si ja va per davant de VERSION, o si falten
#   git config user.name o user.email (l'autor del commit del tap).
# - Si, ja publicada la versió, no pot escriure la recepta, o GitHub no la dona com a última amb el seu appcast.xml, no esborra res: diu què
#   cal fer a mà i surt amb el codi 2. Una versió publicada ja no es desfà: es para com diu docs/disseny.md, «Aturar una versió dolenta».
# - Amb --aplica, cal GH_TOKEN d'un compte que pugui escriure al repo i al tap, passat només a aquesta ordre (la compilació no el veu).
# - Compila amb --amb-feed: només aquesta còpia porta l'adreça de les actualitzacions. Refusa si la recepta no té `auto_updates true`, si l'última
#   versió de GitHub ja és aquesta o una de més nova, si falta el framework o si alguna de les seves peces no és del nostre certificat.
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
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# D'aquí surten l'adreça i la clau que porta la còpia publicada. L'adreça ha de ser la d'aquest repo: si no, cap còpia no trobaria les versions noves.
FITXER_FEED="Recursos/Actualitzacions.plist"
FEED_ESPERAT="https://github.com/$REPO/releases/latest/download/appcast.xml"

llegeix_plist() { /usr/libexec/PlistBuddy -c "Print $1" "$2" 2>/dev/null || true; }
# La versió més gran de les dues, com a nombres: la 0.100 és posterior a la 0.28.
mes_gran() { printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

APLICA=0
case "${1:-}" in
    "") ;;
    --aplica) APLICA=1 ;;
    *) echo "ús: scripts/publica.sh [--aplica]" >&2; exit 64 ;;
esac

# Aquestes variables canvien qui signa i què es comprova: contra el repo de debò, una que hagi quedat definida publicaria sense les comprovacions.
if [[ "$(tr '[:upper:]' '[:lower:]' <<< "$REPO")" == david-erra/warp-launch ]]; then
    for VARIABLE in WARP_LAUNCH_SIGN_UPDATE WARP_LAUNCH_VERIFICA WARP_LAUNCH_REQUISIT WARP_LAUNCH_REQUISIT_SPARKLE; do
        if [[ -n "${!VARIABLE:-}" ]]; then
            echo "publica: ${VARIABLE} i les altres variables de signar i comprovar només valen per a proves, no contra ${REPO}. No s'ha publicat res." >&2
            exit 1
        fi
    done
fi

VERSIO="$(tr -d '[:space:]' < VERSION)"
# Va a l'etiqueta, a la URL i a la substitució de la recepta, i la recepta només en sap llegir aquesta forma.
FORMA_VERSIO='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ ! "$VERSIO" =~ $FORMA_VERSIO ]]; then
    echo "publica: VERSION («${VERSIO}») no té la forma X.Y.Z. No s'ha publicat res." >&2
    exit 1
fi
ETIQUETA="v$VERSIO"
ZIP="build/WarpLaunch-$VERSIO.zip"
URL_ZIP="https://github.com/$REPO/releases/download/$ETIQUETA/WarpLaunch-$VERSIO.zip"
APPCAST="build/appcast.xml"
SIGN_UPDATE="${WARP_LAUNCH_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
if [[ -n "${WARP_LAUNCH_VERIFICA:-}" ]]; then VERIFICA=("$WARP_LAUNCH_VERIFICA"); else VERIFICA=(swift scripts/verifica-signatura.swift); fi

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
if gh release view "$ETIQUETA" --repo "$REPO" > /dev/null 2>&1; then
    echo "publica: la ${ETIQUETA} ja és publicada a ${REPO}. Per publicar canvis, primer puja VERSION. No s'ha publicat res." >&2
    exit 1
fi
# Una etiqueta que ha quedat sense versió (la web de GitHub, o `gh release delete` sense --cleanup-tag, la deixen) faria que la
# versió nova hi quedés lligada, al seu commit: GitHub no fa cas de --target si l'etiqueta ja existeix.
REMOTA="$(git ls-remote --tags origin "refs/tags/$ETIQUETA" "refs/tags/$ETIQUETA^{}" | tail -n 1 | cut -f1)"
if [[ -n "$REMOTA" && "$REMOTA" != "$COMMIT" ]]; then
    echo "publica: l'etiqueta ${ETIQUETA} ja existeix a origin, al commit ${REMOTA:0:7}, sense versió publicada. Esborra-la (git push origin :refs/tags/${ETIQUETA}) o puja VERSION. No s'ha publicat res." >&2
    exit 1
fi
# L'última versió publicada (sense esborranys), per a les notes: el seu commit, sense desar l'etiqueta aquí.
ANTERIOR="$(gh release list --repo "$REPO" --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName // ""')"
BASE=""
if [[ -n "$ANTERIOR" ]]; then
    if ! git fetch -q origin "refs/tags/$ANTERIOR" 2> /dev/null; then
        echo "publica: no trobo l'etiqueta ${ANTERIOR} (l'última versió publicada) a origin, per a les notes. No s'ha publicat res." >&2
        exit 1
    fi
    BASE="$(git rev-parse 'FETCH_HEAD^{commit}')"
fi

# Abans de compilar res: l'autor del commit del tap ha de ser explícit (que no en surti cap altre correu), i la recepta s'ha de
# poder llegir i tenir la forma que aquest script sap canviar. Si no, no es publica res.
AUTOR_NOM="$(git config user.name || true)"
AUTOR_CORREU="$(git config user.email || true)"
if [[ -z "$AUTOR_NOM" || -z "$AUTOR_CORREU" ]]; then
    echo "publica: falta git config user.name o user.email, que seran l'autor del commit de la recepta de Homebrew. No s'ha publicat res." >&2
    exit 1
fi
TEMPORAL="$(mktemp -d)"
trap 'rm -rf "$TEMPORAL"' EXIT
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
# Si la recepta ja va per davant, VERSION és enrere: qui fes `brew upgrade` baixaria de versió.
if [[ "$(mes_gran "$VERSIO_ABANS" "$VERSIO")" != "$VERSIO" ]]; then
    echo "publica: la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) ja és a la ${VERSIO_ABANS}, més nova que la ${VERSIO} de VERSION: qui l'actualitzés baixaria de versió. No s'ha publicat res." >&2
    exit 1
fi

# `latest` és el que llegeixen totes les còpies: una versió que no hi passés al davant no arribaria a ningú.
ULTIMA=""
if ULTIMA="$(gh release view --repo "$REPO" --json tagName --jq '.tagName' 2> /dev/null)"; then
    FORMA_ETIQUETA='^v[0-9]+\.[0-9]+\.[0-9]+$'
    if [[ ! "$ULTIMA" =~ $FORMA_ETIQUETA ]]; then
        echo "publica: l'última versió de ${REPO} («${ULTIMA}») no té la forma vX.Y.Z. No s'ha publicat res." >&2
        exit 1
    fi
    if [[ "${ULTIMA#v}" == "$VERSIO" || "$(mes_gran "${ULTIMA#v}" "$VERSIO")" != "$VERSIO" ]]; then
        echo "publica: l'última versió de ${REPO} és la ${ULTIMA}, que no és anterior a la ${VERSIO} de VERSION: l'app no s'hi actualitzaria. No s'ha publicat res." >&2
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

# La compilació no necessita el token, i SwiftPM executa codi: que no el vegi.
env -u GH_TOKEN -u GITHUB_TOKEN scripts/build-app.sh release --amb-feed
if [[ "$(llegeix_plist CFBundleShortVersionString "$INFO")" != "$VERSIO" ]]; then
    echo "publica: «${APP}» no és la ${VERSIO}. No s'ha publicat res." >&2
    exit 1
fi
# Sparkle compara aquest número amb el de l'appcast: si no coincidissin, tothom es tornaria a actualitzar cada dia.
if [[ "$(llegeix_plist CFBundleVersion "$INFO")" != "$VERSIO" ]]; then
    echo "publica: el CFBundleVersion de «${APP}» no és ${VERSIO}. No s'ha publicat res." >&2
    exit 1
fi
if [[ "$(llegeix_plist SUFeedURL "$INFO")" != "$FEED_DEL_FITXER" || "$(llegeix_plist SUPublicEDKey "$INFO")" != "$CLAU_DEL_FITXER" ]]; then
    echo "publica: «${APP}» no porta l'adreça i la clau de «${FITXER_FEED}». No s'ha publicat res." >&2
    exit 1
fi
if [[ ! -d "$FRAMEWORK" ]]; then
    echo "publica: «${APP}» no porta Sparkle.framework. No s'ha publicat res." >&2
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
comprova_signatura "$APP" "$REQUISIT"
# `--deep` comprova que les peces de dins siguin vàlides, però no qui les signa.
for PECA in "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK"; do
    comprova_signatura "$PECA" "$REQUISIT_SPARKLE"
done
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
MIDA="$(du -h "$ZIP" | cut -f1 | tr -d ' ')"
MIDA_BYTES="$(stat -f %z "$ZIP")"
SHA256_ZIP="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
# Amb LC_ALL=C, sed no refusa cap byte i deixa la resta com és (també si l'última línia no acaba amb un salt de línia).
LC_ALL=C sed -E -e "s/^  version \"[^\"]*\"\$/  version \"$VERSIO\"/" -e "s/^  sha256 \"[^\"]*\"\$/  sha256 \"$SHA256_ZIP\"/" "$RECEPTA" > "$RECEPTA_NOVA"
CONTINGUT_NOU="$(base64 < "$RECEPTA_NOVA" | tr -d '\n')"
# Si ja diu això mateix (una versió esborrada i tornada a publicar amb el mateix zip), no hi ha res per escriure.
RECEPTA_CANVIA=1
if cmp -s "$RECEPTA" "$RECEPTA_NOVA"; then
    RECEPTA_CANVIA=0
fi

NOTES="build/notes-$VERSIO.md"
{
    if [[ -n "$BASE" ]]; then
        echo "Canvis des de la ${ANTERIOR}:"
        echo
        git log --no-merges --format='- %s' "$BASE..$COMMIT"
    else
        echo "Primera versió publicada."
    fi
    echo
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
    echo "s=\"\$(gh api -H 'Accept: application/vnd.github.raw' repos/$REPO/contents/scripts/instal%C2%B7la.sh)\" && bash -c \"\$s\" instal·la --github --aplica"
    echo '```'
    echo
    echo "**L'app s'actualitza sola** des de la 0.32: un cop al dia mira a GitHub si hi ha una versió nova (GitHub veu la teva adreça IP i la versió de l'app) i, quan no la fas servir, es reinicia. Warp i Claude no es tanquen. Va encès de sèrie; per apagar-ho, Configuració › «Actualitzacions» › «Actualitza automàticament»."
    echo
    echo "Si tens la 0.31.5 o una d'anterior, l'has d'actualitzar a mà una última vegada, amb les ordres d'aquí dalt. Des de llavors, és automàtic."
} > "$NOTES"

# El fitxer que llegeix cada còpia. Sense l'eina d'appcasts de Sparkle, que escriu a ~/Library/Caches i toca el clauer. Tots els valors són segurs per a l'XML:
# VERSION i la signatura tenen forma coneguda, i el repo és un nom de GitHub.
rm -f "$APPCAST"
MINIM_SISTEMA="$(llegeix_plist LSMinimumSystemVersion "$INFO")"
if [[ -z "$MINIM_SISTEMA" ]]; then
    echo "publica: «${APP}» no diu quina versió de macOS necessita. No s'ha publicat res." >&2
    exit 1
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
    echo "Avís: aquesta versió canvia l'actualitzador: passa les rondes A i C (docs/disseny.md) abans de publicar."
fi

if [[ "$APLICA" -eq 0 ]]; then
    APPCAST_PROVA="build/appcast-prova-$VERSIO.xml"
    escriu_appcast "$APPCAST_PROVA" SENSE-SIGNAR
    echo "Mode de prova: no s'ha publicat res."
    echo "Amb --aplica, publicaria Warp Launch $VERSIO a $REPO com a ${ETIQUETA} (commit ${COMMIT:0:7}), amb $ZIP ($MIDA)."
    echo "I el seu appcast.xml, signat amb la clau del clauer (aquí, sense signar: $APPCAST_PROVA)."
    if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then
        echo "I canviaria la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}, amb l'autor ${AUTOR_NOM} <${AUTOR_CORREU}>):"
        echo "  version: ${VERSIO_ABANS} -> ${VERSIO}"
        echo "  sha256: ${SHA256_ABANS} -> ${SHA256_ZIP} (el d'aquest zip; amb --aplica, el del zip que es pugi)"
    else
        echo "La recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}) ja diu la ${VERSIO} i el sha256 d'aquest zip: no caldria escriure-la."
    fi
    echo "Notes ($NOTES):"
    sed 's/^/  /' "$NOTES"
    exit 0
fi

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

# Publicar ja no es desfà: qui l'hagi baixada la instal·larà. $1, el commit de la recepta, si n'hi ha.
com_es_para() {
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

# Tots dos fitxers en una sola ordre: `latest` no canvia fins que hi són. Sense appcast, totes les còpies veurien un 404.
if ! gh release create "$ETIQUETA" "$ZIP" "$APPCAST" --repo "$REPO" --latest --target "$COMMIT" --title "Warp Launch $VERSIO" --notes-file "$NOTES"; then
    # `gh` pot fallar quan GitHub ja l'ha publicada (una resposta perduda): llavors, no es pot dir que no s'ha creat.
    if [[ "$(gh release view "$ETIQUETA" --repo "$REPO" --json isDraft --jq '.isDraft' 2> /dev/null || true)" == false ]]; then
        {
            echo "publica: \`gh release create\` ha fallat, però la ${ETIQUETA} ja és publicada a ${REPO} (no s'ha esborrat res): mira a la web de GitHub si hi ha el zip i l'appcast.xml, i si és l'última."
            if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then canvia_la_recepta_a_ma; fi
            com_es_para
        } >&2
        exit 2
    fi
    echo "publica: no s'ha pogut crear la ${ETIQUETA} a ${REPO}, i la recepta de Homebrew no s'ha tocat. Abans de tornar-ho a provar, mira si n'ha quedat un esborrany o l'etiqueta: gh release view ${ETIQUETA} --repo ${REPO}" >&2
    exit 1
fi

# GitHub ho ha de dir: si no, les còpies no la veuran, o veurien un 404 (de l'appcast, o del zip quan el vagin a baixar).
ESTAT_PUBLICADA="$(gh release view --repo "$REPO" --json tagName,assets --jq ".tagName, (any(.assets[]; .name == \"appcast.xml\") and any(.assets[]; .name == \"$(basename "$ZIP")\"))" 2> /dev/null || true)"
if [[ "$ESTAT_PUBLICADA" != "$ETIQUETA"$'\n'true ]]; then
    {
        echo "publica: la ${ETIQUETA} ja és publicada a ${REPO}, però GitHub no la dona com a última amb el seu appcast.xml i el seu zip (no s'ha esborrat res): les còpies no s'hi actualitzaran. Mira-ho a la web de GitHub."
        if [[ "$RECEPTA_CANVIA" -eq 1 ]]; then canvia_la_recepta_a_ma; fi
        com_es_para
    } >&2
    exit 2
fi

if [[ "$RECEPTA_CANVIA" -eq 0 ]]; then
    echo "Fet: Warp Launch $VERSIO és publicada a $REPO (${ETIQUETA}). La recepta de ${TAP} ja deia aquesta versió i aquest sha256, i no s'ha escrit."
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
echo "Fet: Warp Launch $VERSIO és publicada a $REPO (${ETIQUETA}), i la recepta de ${TAP} ja la instal·la (sha256 ${SHA256_ZIP})."
com_es_para "$COMMIT_TAP"
