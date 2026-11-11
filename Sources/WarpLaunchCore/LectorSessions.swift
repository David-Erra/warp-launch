import Foundation

/// Llegeix les sessions de Claude vives de `~/.claude/sessions/<pid>.json` i, de cada procés, l'`argv` i l'entorn.
/// **Només lectura:** no escriu res a `~/.claude` ni envia senyals als processos.
public struct LectorSessions: Sendable {
    public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/sessions")

    public var carpeta: URL
    public var processos: any FontProcessos

    /// Sense valors per defecte, com `Lector`: una prova que se'ls oblidés llegiria les sessions i els processos de debò.
    public init(carpeta: URL, processos: any FontProcessos) {
        self.carpeta = carpeta
        self.processos = processos
    }

    /// Format de `~/.claude/sessions/<pid>.json` (Claude Code 2.1.317). Només els camps que fem servir.
    struct FitxerSessio: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var name: String?
        var nameSource: String?
        var kind: String?
        var startedAt: Double?
        var status: String?
        /// La versió de Claude Code que l'ha escrit (`2.1.317`): només la fa servir el diagnòstic.
        var version: String?
    }

    /// Els `kind` coneguts: un altre vol dir que Claude Code ha canviat el format (diagnòstic). Són els que accepta Claude
    /// Code de la 2.1.317 a la 2.1.319 en llegir aquests fitxers (`["interactive","bg","daemon","daemon-worker"]`, llegit
    /// als tres binaris sense executar-los, 07/11/2026).
    static let tipusConeguts: Set<String> = ["interactive", "bg", "daemon", "daemon-worker"]

    /// Sessions **interactives** amb el procés viu, ordenades per pid, i els avisos de la lectura.
    /// Les sessions `bg` no hi són: hereten l'UUID del pane on es va engegar el dimoni i no diuen res de la pestanya.
    public func llegeix() -> (sessions: [SessioClaude], avisos: [String]) {
        let lectura = llegeixTotes()
        return (lectura.sessions, lectura.avisos)
    }

    /// Com `llegeix`, i a més les sessions vives que no són interactives (`noInteractives`, ordenades per pid): no
    /// diuen res de cap pestanya, però la seva conversa no es pot reprendre en una altra (R9).
    public func llegeixTotes() -> (sessions: [SessioClaude], noInteractives: [SessioViva], avisos: [String]) {
        let fitxers: [URL]
        do {
            fitxers = try FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return ([], [], [t("no puc llegir la carpeta de sessions de Claude: \(carpeta.path)")])
        }

        var sessions: [SessioClaude] = []
        var noInteractives: [SessioViva] = []
        var avisos: [String] = []
        for fitxer in fitxers {
            guard let dades = try? Data(contentsOf: fitxer),
                  let s = try? JSONDecoder().decode(FitxerSessio.self, from: dades) else {
                avisos.append(t("fitxer de sessió il·legible: \(fitxer.lastPathComponent)"))
                continue
            }
            guard s.kind == "interactive" else {
                // Sense avisos: un dimoni que s'acaba és normal. Si el pid és d'un altre procés, no compta.
                if let proces = processos.proces(s.pid), proces.esClaude {
                    noInteractives.append(SessioViva(pid: s.pid, sessionId: s.sessionId, tipus: s.kind ?? "",
                                                     carpeta: Rutes.canonica(s.cwd)))
                }
                continue
            }
            guard let proces = processos.proces(s.pid) else {
                avisos.append(t("la sessió \(s.sessionId) apunta al pid \(String(s.pid)), que ja no existeix"))
                continue
            }
            guard proces.esClaude else {
                avisos.append(t("el pid \(String(s.pid)) de la sessió \(s.sessionId) ara és un altre procés (\(proces.executable))"))
                continue
            }
            sessions.append(SessioClaude(
                pid: s.pid,
                sessionId: s.sessionId,
                nom: s.name,
                origenNom: s.nameSource,
                carpeta: Rutes.canonica(s.cwd),
                estat: s.status,
                iniciada: s.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                ordre: proces.argv,
                opcions: OpcionsClaude.analitza(proces.argv),
                paneUUID: proces.entorn["WARP_TERMINAL_SESSION_UUID"]?.lowercased(),
                dinsDeWarp: penjaDeWarp(s.pid),
                marca: proces.entorn[OrdreClaude.variableMarca].flatMap(UUID.init(uuidString:))))
        }
        return (sessions.sorted { $0.pid < $1.pid }, noInteractives.sorted { $0.pid < $1.pid }, avisos)
    }

    /// Cerca entre els avantpassats el `stable terminal-server` de Warp, del qual pengen els shells.
    private func penjaDeWarp(_ pid: Int32) -> Bool {
        var actual = processos.pare(pid)
        var passos = 0
        while let p = actual, p > 1, passos < 16 {
            if let info = processos.proces(p), info.argv.contains("terminal-server"), info.executable.contains("Warp") {
                return true
            }
            actual = processos.pare(p)
            passos += 1
        }
        return false
    }
}
