import Foundation

/// Perquè les feines noves que engega l'agent d'una pestanya vagin en bypass, com ella (en David, 05/11/2026).
///
/// Un `claude --bg` sense paràmetres arrenca en `auto`: no hereta res de la sessió que l'engega. Com que els missatges entre
/// sessions només arriben sols si les dues van en bypass o cap de les dues, els de la feina queden retinguts
/// (`docs/fets-verificats.md`, «Missatges entre sessions de Claude»). L'app no engega aquestes feines; les engega l'agent.
///
/// Per això, la línia de cada pestanya en bypass porta `CLAUDE_ENV_FILE`: Claude llegeix aquest fitxer un cop per sessió i
/// l'enganxa abans de cada ordre de Bash. Hi defineix una funció `claude` que hi afegeix el paràmetre si l'ordre comença amb
/// `--bg` o `--background`. Si l'agent en posa un altre després, mana el seu. Dues coses que no són evidents:
/// - **Una feina que ja existeix no porta el paràmetre** (`--resume <id complet>` amb el seu `state.json`): sense opcions, es
///   desperta amb el mateix id i les opcions desades; amb qualsevol opció, Claude en faria una còpia amb un altre id. Una feina
///   d'abans de la 0.22.3 que tingui `auto` desat continua en `auto`.
/// - **`unset`:** sense, la ruta passaria de l'ordre de Bash al servei de feines, i d'allà a totes les feines, també a les que
///   no van en bypass. Una feina no es pot distingir d'una altra manera: Claude treu `CLAUDE_CODE_SESSION_KIND` a les seves
///   ordres de Bash. Claude ja té la ruta al seu procés: `unset` només afecta el que engega la shell.
///
/// **No arriba** a `nohup claude --bg`, a un script ni a `bash -c`, perquè una funció de la shell no hi passa, ni a
/// `claude -n x --bg`. Tampoc a les feines que engegui una feina. Si el fitxer no hi és, Claude no diu res i la feina va en
/// `auto`, com abans. A zsh, `which claude` escriu el text de la funció; `whence -p claude` en dona la ruta.
public enum EntornClaude {
    public static let variable = "CLAUDE_ENV_FILE"
    public static let nomFitxer = "entorn-claude.sh"

    /// Només ASCII i sense apòstrofs: Claude l'enganxa tal qual dins de l'ordre, i un error de sintaxi trencaria totes les
    /// ordres de Bash de la pestanya. `function` i no `claude()`: zsh no accepta la segona forma si hi ha un àlies `claude`.
    public static let text = #"""
        # Warp Launch: les feines noves engegades amb claude --bg des de la pestanya van en bypass, com ella.
        # Generat per Warp Launch a cada obertura. Claude Code el llegeix abans de les ordres de Bash.
        unset CLAUDE_ENV_FILE
        function claude {
          case "${1:-}" in
            --bg|--background)
              local a= anterior=
              for a in "$@"; do
                if [ "$anterior" = --resume ] || [ "$anterior" = -r ]; then
                  if [ "${#a}" -eq 36 ] && [ -e "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs/${a:0:8}/state.json" ]; then
                    command claude "$@"
                    return
                  fi
                fi
                anterior=$a
              done
              set -- "$1" --permission-mode bypassPermissions "${@:2}" ;;
          esac
          command claude "$@"
        }

        """#

    /// La ruta absoluta del fitxer, que va a la línia de la pestanya: Warp l'executa en una altra carpeta.
    public static func ruta(carpeta: URL) -> String {
        carpeta.appending(path: nomFitxer).absoluteURL.path
    }

    /// Escriu el fitxer a la carpeta de la configuració, si no hi és igual. Les sessions obertes ja l'han llegit.
    public static func desa(carpeta: URL) throws {
        let fitxer = carpeta.appending(path: nomFitxer)
        let dades = Data(text.utf8)
        if (try? Data(contentsOf: fitxer)) == dades { return }
        try EscripturaAtomica.escriu(dades, a: fitxer)
    }
}
