import Foundation

/// Les opcions del programa principal de Claude Code, tal com les defineix amb commander: les 131 de la funció que
/// el construeix, més `-v, --version`. Llegides del binari de la versió 2.1.318 el 04/11/2026 (docs/fets-verificats.md,
/// «Com llegeix Claude Code la línia d'ordres»). `-h, --help` no hi és: commander no la busca entre les opcions.
///
/// Claude Code canvia gairebé cada dia. Una opció que no és a la taula surt com a desconeguda (`OpcionsClaude.desconegudes`),
/// i llavors cal tornar-la a llegir del binari.
enum TaulaOpcionsClaude {
    static let versio = "2.1.318"

    enum Valor: Sendable, Equatable {
        /// Interruptor: `--verbose`.
        case cap
        /// `<valor>`: pren l'argument següent, sigui el que sigui.
        case obligatori
        /// `[valor]`: pren l'argument següent només si no comença per «-».
        case opcional
    }

    struct Opcio: Sendable, Equatable {
        /// Els noms, com `Option.is` de commander: el curt (o el primer llarg) i el llarg.
        let noms: [String]
        let valor: Valor
        /// `<valors...>`: després del primer valor, s'empassa els arguments següents fins al primer que comença per «-».
        let variadica: Bool
        let definicio: String
    }

    /// Les definicions tal com són al binari.
    static let definicions: [String] = [
        "-d, --debug [filter]", "-d2e, --debug-to-stderr", "--debug-file <path>", "--verbose", "-p, --print",
        "--bare", "--safe-mode", "--init", "--init-only", "--maintenance", "--output-format <format>",
        "--json-schema <schema>", "--include-hook-events", "--include-partial-messages", "--forward-subagent-text",
        "--session-mirror", "--await-claim", "--input-format <format>", "--await-initialize",
        "--dangerously-skip-permissions", "--allow-dangerously-skip-permissions", "--thinking <mode>",
        "--thinking-display <display>", "--max-thinking-tokens <tokens>", "--max-turns <turns>",
        "--max-budget-usd <amount>", "--task-budget <tokens>", "--replay-user-messages",
        "--prompt-suggestions [value]", "--enable-auth-status", "--allowedTools, --allowed-tools <tools...>",
        "--tools <tools...>", "--restricted", "--disallowedTools, --disallowed-tools <tools...>",
        "--mcp-config <configs...>", "--permission-prompt-tool <tool>", "--permission-prompts <target>",
        "--system-prompt <prompt>", "--system-prompt-file <file>", "--append-system-prompt <prompt>",
        "--append-system-prompt-file <file>", "--system-prompt-snapshot <on|off>",
        "--append-subagent-system-prompt <prompt>", "--append-subagent-system-prompt-file <file>",
        "--plan-mode-instructions <instructions>", "--exclude-dynamic-system-prompt-sections",
        "--permission-mode <mode>", "--inherit-permission-mode <mode>", "-c, --continue", "-r, --resume [value]",
        "--fork-session", "--watch-artifact <artifact>", "--watch-artifact-no-autoreact <artifact>",
        "--prefill <text>", "--deep-link-origin", "--deep-link-repo <slug>", "--deep-link-last-fetch <ms>",
        "--prefill-b64 <b64>", "--deep-link-cwd-b64 <b64>", "--from-pr [value]", "--no-session-persistence",
        "--resume-session-at <message id>", "--resume-drops-turn <message id>", "--reply-on-resume",
        "--rewind-files <user-message-id>", "--model <model>", "--include-unsupported-models", "--effort <level>",
        "--fast-mode <on|off>", "--agent <agent>", "--betas <betas...>", "--fallback-model <model>",
        "--workload <tag>", "--settings <file-or-json>", "--client-data-url <url>", "--allow-other-models",
        "--managed-settings <json>", "--host-auth-is-org-sign-in", "--add-dir <directories...>",
        "--project-config-root <dir>", "--ide", "--desktop", "--strict-mcp-config", "--session-id <uuid>",
        "-n, --name <name>", "--agents <json-or-file>", "--setting-sources <sources>", "--plugin-dir <path>",
        "--plugin-dir-no-mcp <path>", "--plugin-url <url>", "--disable-slash-commands", "--chrome", "--no-chrome",
        "--file <specs...>", "-w, --worktree [name]", "--tmux", "--advisor <model>", "--autocompact <auto|tokens>",
        "--enable-auto-mode", "--proactivity <level>", "--agents-view-if-allowed", "--bg, --background",
        "--messaging-socket-path <path>", "--brief", "--ax-screen-reader", "--channels <servers...>",
        "--dangerously-load-development-channels <servers...>", "--agent-id <id>", "--agent-name <name>",
        "--team-name <name>", "--agent-color <color>", "--plan-mode-required", "--parent-session-id <id>",
        "--teammate-mode <mode>", "--agent-type <type>", "--sdk-url <url>", "--runner-declares <names>",
        "--session-began-as-copy <value>", "--teleport [session]", "--cloud [description|session_id|url]",
        "--forward-home-settings <true|false>", "--remote [description|session_id|url]",
        "--attach-serve <session_id>", "--environment <environment_id>", "--pool <pool_id>", "--correlation-id <id>",
        "--ref <ref>", "--on-branch <branch>", "--remote-control [name]", "--rc [name]",
        "--remote-control-session-name-prefix <prefix>", "-v, --version",
    ]

    static let opcions: [Opcio] = definicions.map(opcio)

    /// La primera opció amb aquest nom, com `_findOption` de commander.
    static func troba(_ nom: String) -> Opcio? {
        opcions.first { $0.noms.contains(nom) }
    }

    /// Com `splitOptionFlags` i el constructor d'`Option` de commander.
    static func opcio(_ definicio: String) -> Opcio {
        var parts = definicio.split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "," }).map(String.init)
        var curt: String?
        if parts.count > 1, !(parts[1].hasPrefix("[") || parts[1].hasPrefix("<")) { curt = parts.removeFirst() }
        var llarg = parts.isEmpty ? nil : parts.removeFirst()
        if curt == nil, let l = llarg, l.count == 2, l.hasPrefix("-"), l != "--" {
            curt = l
            llarg = nil
        }
        let valor: Valor = definicio.contains("<") ? .obligatori : definicio.contains("[") ? .opcional : .cap
        let variadica = definicio.range(of: #"\w\.\.\.[>\]]$"#, options: .regularExpression) != nil
        return Opcio(noms: [curt, llarg].compactMap { $0 }, valor: valor, variadica: variadica, definicio: definicio)
    }
}
