#!/bin/bash
# Mira o canvia la línia `restore_session` de `[general]` a ~/.warp/settings.toml. És l'única cosa de Warp que es pot
# escriure (excepció de la regla 7 de CLAUDE.md), per activar la restauració de sessió una estona i poder llegir les
# finestres i els títols. Cal l'OK d'en David per a cada vegada.
#
# Ús: scripts/warp-restauracio.sh estat
#     scripts/warp-restauracio.sh activa|desactiva [--aplica]
#
# Sense --aplica no escriu res: diu què canviaria (regla 4). No obre, tanca ni reinicia Warp.
# Si el fitxer no té exactament la forma esperada, no toca res.
set -euo pipefail

# Sense els dos punts: una variable buida per error no ha d'acabar al fitxer de debò.
FITXER="${WARP_SETTINGS-$HOME/.warp/settings.toml}"
ORDRE="${1:-}"
OPCIO="${2:-}"

us() {
    echo "Ús: $0 estat | activa [--aplica] | desactiva [--aplica]" >&2
    exit 2
}

refusa() {
    echo "warp-restauracio: $1. No s'ha tocat res." >&2
    exit 1
}

case "$ORDRE" in
    estat) [[ -z "$OPCIO" ]] || us ;;
    activa) NOU=true ;;
    desactiva) NOU=false ;;
    *) us ;;
esac
if [[ "$ORDRE" != estat ]]; then
    [[ -z "$OPCIO" || "$OPCIO" == --aplica ]] || us
fi

[[ -f "$FITXER" ]] || refusa "no hi ha $FITXER"
# `mv` substituiria l'enllaç, no el fitxer.
[[ ! -L "$FITXER" ]] || refusa "$FITXER és un enllaç"

# Warp l'escriu en calent. Tot es decideix sobre una sola lectura, i abans d'escriure es mira que el fitxer continuï igual.
TEMPORAL="${TMPDIR:-/tmp}"
LLEGIT="$(mktemp "$TEMPORAL/warp-settings-copia.XXXXXX")"
CANDIDAT="$(mktemp "$TEMPORAL/warp-settings-candidat.XXXXXX")"
PROVISIONAL=""
trap 'rm -f "$CANDIDAT" ${LLEGIT:+"$LLEGIT"} ${PROVISIONAL:+"$PROVISIONAL"}' EXIT
cp -p "$FITXER" "$LLEGIT"

# Sense salt de línia final, awk n'hi afegiria un: canviaria alguna cosa més que el valor.
[[ -z "$(tail -c 1 "$LLEGIT")" ]] || refusa "$FITXER no acaba amb un salt de línia"

# Només una aparició a tot el fitxer, i que sigui una línia de la taula [general], amb un valor true o false.
APARICIONS="$(grep -c 'restore_session' "$LLEGIT" || true)"
[[ "$APARICIONS" == 1 ]] || refusa "«restore_session» hi surt $APARICIONS vegades, i n'hi hauria d'haver 1"
TROBADA="$(awk '
    /^[[:space:]]*\[/ { taula = $0; gsub(/[[:space:]]/, "", taula); next }
    taula == "[general]" && /^[[:space:]]*restore_session[[:space:]]*=/ {
        valor = $0
        sub(/^[^=]*=[[:space:]]*/, "", valor)
        sub(/[[:space:]]*(#.*)?$/, "", valor)
        print NR, valor
    }
' "$LLEGIT")"
[[ -n "$TROBADA" ]] || refusa "«restore_session» no és una línia de la taula [general]"
LINIA="${TROBADA%% *}"
ACTUAL="${TROBADA#* }"
[[ "$ACTUAL" == true || "$ACTUAL" == false ]] || refusa "el valor de «restore_session» no és true ni false"

if [[ "$ORDRE" == estat ]]; then
    if [[ "$ACTUAL" == true ]]; then
        echo "restore_session = true (línia $LINIA): Warp desa les finestres i les restaura en obrir-se."
    else
        echo "restore_session = false (línia $LINIA): Warp no desa les finestres."
    fi
    exit 0
fi

if [[ "$ACTUAL" == "$NOU" ]]; then
    echo "restore_session ja és $NOU (línia $LINIA): no cal canviar res."
    exit 0
fi

awk -v n="$LINIA" -v nou="$NOU" 'NR == n { sub(/true|false/, nou) } { print }' "$LLEGIT" > "$CANDIDAT"
# Una línia fora i una de dins, i prou: la de `restore_session`.
CANVIS="$(diff "$LLEGIT" "$CANDIDAT" | grep '^[<>]' || true)"
[[ "$(grep -c '' <<<"$CANVIS")" == 2 && "$(grep -c 'restore_session' <<<"$CANVIS")" == 2 ]] \
    || refusa "el canvi tocaria alguna cosa més que la línia de «restore_session»"

if [[ "$OPCIO" != --aplica ]]; then
    echo "Mode de prova: canviaria la línia $LINIA de $FITXER: restore_session = $ACTUAL → $NOU."
    echo "No s'ha escrit res. Per fer-ho, afegeix --aplica."
    exit 0
fi

# Fora de la carpeta de Warp, perquè no hi quedi res si el procés mor, i al mateix volum, perquè `mv` sigui atòmic.
[[ "$(stat -f %d "$TEMPORAL")" == "$(stat -f %d "$(dirname "$FITXER")")" ]] \
    || refusa "$TEMPORAL no és al mateix volum que $FITXER"
PROVISIONAL="$(mktemp "$TEMPORAL/warp-settings-nou.XXXXXX")"
# Els permisos de l'original.
cp -p "$LLEGIT" "$PROVISIONAL"
cat "$CANDIDAT" > "$PROVISIONAL"
cmp -s "$FITXER" "$LLEGIT" || refusa "$FITXER acaba de canviar"
mv -f "$PROVISIONAL" "$FITXER"
PROVISIONAL=""
COPIA="$LLEGIT"
LLEGIT=""

echo "Fet: línia $LINIA de $FITXER, restore_session = $ACTUAL → $NOU. Còpia d'abans: $COPIA"
echo "Comprova-ho amb «$0 estat» passat 1 s: si Warp escrivia ara mateix, podria tornar a posar el valor d'abans."
if [[ "$NOU" == true ]]; then
    echo "Mentre sigui activada, si Warp es tanca restaurarà les seves finestres. Settings Sync ho porta a les altres"
    echo "instal·lacions de Warp. Quan acabis: $0 desactiva --aplica"
fi
