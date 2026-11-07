#!/bin/bash
# Genera una imatge amb nano-banana (API d'imatges de Gemini) i la desa en PNG.
#
# Ús:
#   scripts/genera-imatge.sh "<prompt>" <sortida.png> [proporció]    # proporció per defecte: 1:1
#   scripts/genera-imatge.sh --models                                 # models d'imatge disponibles
#
# La clau es llegeix de la variable GEMINI_API_KEY. No l'escriguis mai al repo.
# El model es pot canviar amb NANO_BANANA_MODEL. Per defecte és gemini-3-pro-image (Nano Banana Pro), el
# de més qualitat; els altres són a `--models`.
# Només fa servir eines del sistema: bash, curl, jq (/usr/bin/jq), base64 i sips.
set -euo pipefail

: "${GEMINI_API_KEY:?genera-imatge: cal la variable GEMINI_API_KEY (vegeu CLAUDE.md)}"
API="https://generativelanguage.googleapis.com/v1beta"
MODEL="${NANO_BANANA_MODEL:-gemini-3-pro-image}"

# La clau va per un fitxer de capçaleres temporal, perquè no surti als arguments de curl (ps).
crida() {
    curl -sS --fail-with-body -H @<(printf 'x-goog-api-key: %s\n' "$GEMINI_API_KEY") "$@"
}

if [[ "${1:-}" == "--models" ]]; then
    crida "$API/models?pageSize=1000" \
        | jq -r '.models[] | select(.name | test("image")) | "\(.name | sub("models/"; ""))\t\(.displayName)"'
    exit 0
fi

PROMPT="${1:?genera-imatge: falta el prompt}"
SORTIDA="${2:?genera-imatge: falta el fitxer de sortida}"
PROPORCIO="${3:-1:1}"
if [[ -e "$SORTIDA" ]]; then
    echo "genera-imatge: $SORTIDA ja existeix; no el sobreescric" >&2
    exit 1
fi

RESPOSTA="$(mktemp)"
trap 'rm -f "$RESPOSTA"' EXIT

if ! jq -n --arg p "$PROMPT" --arg r "$PROPORCIO" \
        '{contents: [{parts: [{text: $p}]}],
          generationConfig: {responseModalities: ["IMAGE"], imageConfig: {aspectRatio: $r}}}' \
    | crida -X POST -H 'Content-Type: application/json' --data-binary @- \
        "$API/models/$MODEL:generateContent" -o "$RESPOSTA"; then
    echo "genera-imatge: l'API ha retornat un error:" >&2
    jq -c '.error // .' "$RESPOSTA" >&2 || cat "$RESPOSTA" >&2
    exit 1
fi

DADES="$(jq -r '[.candidates[0].content.parts[]? | select(.inlineData) | .inlineData.data][0] // empty' "$RESPOSTA")"
if [[ -z "$DADES" ]]; then
    echo "genera-imatge: la resposta no porta cap imatge:" >&2
    jq -c '{motiu: .candidates[0].finishReason, text: [.candidates[0].content.parts[]?.text // empty], bloqueig: .promptFeedback}' "$RESPOSTA" >&2
    exit 1
fi

mkdir -p "$(dirname "$SORTIDA")"
printf '%s' "$DADES" | base64 -D > "$SORTIDA"
MIDA="$(sips -g pixelWidth -g pixelHeight "$SORTIDA" | awk '/pixel/ {printf "%s", (n++ ? "×" : "") $2}')"
echo "$SORTIDA ($MODEL, $PROPORCIO, $MIDA px)"
