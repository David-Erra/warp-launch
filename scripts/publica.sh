#!/bin/bash
# Publica a GitHub la versió de VERSION, compilada i signada, perquè altres Macs la instal·lin sense compilar:
# `scripts/instal·la.sh --github --aplica` (README.md). Regla 3 de CLAUDE.md: només amb l'OK d'en David, cada vegada.
#
# Ús:
#   scripts/publica.sh            # mode de prova: compila, ho comprova tot i diu què publicaria; no publica res
#   scripts/publica.sh --aplica   # a més, crea la versió vX.Y.Z al repo de GitHub, amb WarpLaunch-X.Y.Z.zip
#
# - Només publica el que hi ha a origin/main, sense canvis per fer commit, i una versió que encara no hi sigui.
# - Només amb la signatura «Warp Launch Dev» (D12): una app signada ad hoc no es pot instal·lar amb --github.
# - Proves: WARP_LAUNCH_REPO i WARP_LAUNCH_REQUISIT canvien el repo de GitHub i el requisit de la signatura.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTIFICADOR="cat.davide.warp-launch"
REPO="${WARP_LAUNCH_REPO:-David-Erra/warp-launch}"
TAP="${WARP_LAUNCH_TAP:-David-Erra/homebrew-tap}"
CAMI_RECEPTA="Casks/warp-launch.rb"
# El mateix requisit que comprova `instal·la.sh --github`.
REQUISIT="${WARP_LAUNCH_REQUISIT:-identifier \"$IDENTIFICADOR\" and certificate leaf = H\"c1ec55b1cb87c881a2c48a4f5256b10ebc12bcc6\"}"
APP="build/Warp Launch.app"

APLICA=0
case "${1:-}" in
    "") ;;
    --aplica) APLICA=1 ;;
    *) echo "ús: scripts/publica.sh [--aplica]" >&2; exit 64 ;;
esac

VERSIO="$(tr -d '[:space:]' < VERSION)"
ETIQUETA="v$VERSIO"
ZIP="build/WarpLaunch-$VERSIO.zip"

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
FORMA_BLOB='^[0-9a-f]{40}$'
if [[ "$(sed -n 1p <<< "$RESPOSTA")" != base64 || ! "$SHA_BLOB" =~ $FORMA_BLOB ]] || ! sed 1,2d <<< "$RESPOSTA" | base64 --decode > "$RECEPTA"; then
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
VERSIO_ABANS="$(LC_ALL=C sed -nE 's/^  version "(.*)"$/\1/p' "$RECEPTA")"
SHA256_ABANS="$(LC_ALL=C sed -nE 's/^  sha256 "(.*)"$/\1/p' "$RECEPTA")"

scripts/build-app.sh
if [[ "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || true)" != "$VERSIO" ]]; then
    echo "publica: «${APP}» no és la ${VERSIO}. No s'ha publicat res." >&2
    exit 1
fi
CODI=0
ERROR="$(codesign --verify --strict -R="$REQUISIT" "$APP" 2>&1)" || CODI=$?
if [[ "$CODI" -eq 3 ]]; then
    echo "publica: «${APP}» no està signada amb «Warp Launch Dev» (al clauer d'aquest Mac?). No s'ha publicat res." >&2
    exit 1
elif [[ "$CODI" -ne 0 ]]; then
    echo "publica: no s'ha pogut comprovar la signatura de «${APP}» (codesign, codi ${CODI}): ${ERROR}" >&2
    exit 1
fi
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
MIDA="$(du -h "$ZIP" | cut -f1 | tr -d ' ')"
SHA256_ZIP="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
# Amb LC_ALL=C, sed no refusa cap byte i deixa la resta com és (també si l'última línia no acaba amb un salt de línia).
LC_ALL=C sed -E -e "s/^  version \"[^\"]*\"\$/  version \"$VERSIO\"/" -e "s/^  sha256 \"[^\"]*\"\$/  sha256 \"$SHA256_ZIP\"/" "$RECEPTA" > "$RECEPTA_NOVA"
CONTINGUT_NOU="$(base64 < "$RECEPTA_NOVA" | tr -d '\n')"

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
    echo "Per instal·lar-la o actualitzar-la (Apple Silicon, macOS 26 o posterior i un compte d'administrador del Mac; cal \`gh auth login\`):"
    echo
    echo '```bash'
    echo "s=\"\$(gh api -H 'Accept: application/vnd.github.raw' repos/$REPO/contents/scripts/instal%C2%B7la.sh)\" && bash -c \"\$s\" instal·la --github --aplica"
    echo '```'
} > "$NOTES"

if [[ "$APLICA" -eq 0 ]]; then
    echo "Mode de prova: no s'ha publicat res."
    echo "Amb --aplica, publicaria Warp Launch $VERSIO a $REPO com a ${ETIQUETA} (commit ${COMMIT:0:7}), amb $ZIP ($MIDA)."
    echo "I canviaria la recepta de Homebrew (${CAMI_RECEPTA} de ${TAP}, amb l'autor ${AUTOR_NOM} <${AUTOR_CORREU}>):"
    echo "  version: ${VERSIO_ABANS} -> ${VERSIO}"
    echo "  sha256: ${SHA256_ABANS} -> ${SHA256_ZIP} (el d'aquest zip; amb --aplica, el del zip que es pugi)"
    echo "Notes ($NOTES):"
    sed 's/^/  /' "$NOTES"
    exit 0
fi

gh release create "$ETIQUETA" "$ZIP" --repo "$REPO" --target "$COMMIT" --title "Warp Launch $VERSIO" --notes-file "$NOTES"

# La versió ja és a GitHub: d'aquí endavant, un error no l'esborra. El sha és el del blob llegit abans de compilar: si algú ha canviat
# la recepta mentrestant, GitHub refusa l'escriptura en lloc de trepitjar-la.
if ! COMMIT_TAP="$(gh api --method PUT "repos/$TAP/contents/$CAMI_RECEPTA" \
    -f "message=chore: warp-launch passa a la $VERSIO" -f "branch=main" -f "sha=$SHA_BLOB" -f "content=$CONTINGUT_NOU" \
    -f "author[name]=$AUTOR_NOM" -f "author[email]=$AUTOR_CORREU" \
    -f "committer[name]=$AUTOR_NOM" -f "committer[email]=$AUTOR_CORREU" --jq '.commit.sha')"; then
    {
        echo "publica: la ${ETIQUETA} ja és publicada a ${REPO} (no s'ha esborrat), però no s'ha pogut escriure la recepta de Homebrew a ${TAP}."
        echo "Canvia a mà aquestes dues línies de ${CAMI_RECEPTA}, a la branca main de ${TAP}:"
        echo "  version \"${VERSIO}\""
        echo "  sha256 \"${SHA256_ZIP}\""
        echo "Mentre no ho facis, Homebrew continua instal·lant la ${VERSIO_ABANS}."
    } >&2
    exit 2
fi
echo "Fet: Warp Launch $VERSIO és publicada a $REPO (${ETIQUETA}), i la recepta de ${TAP} ja la instal·la (sha256 ${SHA256_ZIP})."
echo "Es desfà amb: gh release delete ${ETIQUETA} --repo $REPO --cleanup-tag, i revertint el commit ${COMMIT_TAP} de ${TAP} (git revert ${COMMIT_TAP} en un clon del tap, i push)."
