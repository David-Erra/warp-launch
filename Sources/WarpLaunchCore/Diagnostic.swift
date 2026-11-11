import Foundation

// Diagnòstic (pla A4, 0.30.0): quan Warp o Claude Code canvien un format intern, que l'usuari (i les issues) ho vegin en
// lloc d'una fallada en silenci. Unes comprovacions de només lectura, cadascuna amb el seu resultat (bé, avís o error) i el
// detall. No bloqueja res: en David no ha acceptat aturar «Obre-ho tot». El text de l'informe és en anglès, perquè va a les
// issues de GitHub; la resta (codi, comentaris, interfície), en català.

/// Les versions de Warp i de Claude Code amb prova real (docs/fets-verificats.md). Fora d'aquí, el diagnòstic avisa que no
/// s'han provat, però no és cap error. És una constant de Swift (no un recurs de SwiftPM): va dins del binari.
public enum VersionsProvades {
    /// Warp Stable 0.2026.10.21 (qualsevol compilació: `0.2026.10.21.08.25.02`, a la prova L1).
    public static let warp = [RangVersions("0.2026.10.21")]
    /// Claude Code de la 2.1.317 a la 2.1.318.
    public static let claude = [RangVersions(desDe: "2.1.317", finsA: "2.1.318")]

    /// Si `versio` és dins d'algun dels rangs.
    public static func provada(_ versio: String, _ rangs: [RangVersions]) -> Bool {
        rangs.contains { $0.conte(versio) }
    }
}

/// Un rang de versions, amb els extrems inclosos. Es compara xifra a xifra, i només fins on arriben els extrems: amb
/// `0.2026.10.21`, `0.2026.10.21.08.25.02` hi és.
public struct RangVersions: Sendable, Equatable, CustomStringConvertible {
    public var desDe: String
    public var finsA: String

    public init(desDe: String, finsA: String) {
        self.desDe = desDe
        self.finsA = finsA
    }

    /// Una sola versió.
    public init(_ versio: String) {
        self.init(desDe: versio, finsA: versio)
    }

    public var description: String { desDe == finsA ? desDe : "\(desDe)–\(finsA)" }

    public func conte(_ versio: String) -> Bool {
        guard let minim = Self.xifres(desDe), let maxim = Self.xifres(finsA), minim.count == maxim.count,
              let totes = Self.xifres(versio, fins: minim.count), totes.count == minim.count
        else { return false }
        return !totes.lexicographicallyPrecedes(minim) && !maxim.lexicographicallyPrecedes(totes)
    }

    /// Les xifres de la versió (`2.1.317` → `[2, 1, 317]`), fins a `fins` components. `nil` si n'hi ha cap que no ho sigui.
    static func xifres(_ versio: String, fins: Int = .max) -> [Int]? {
        let components = versio.split(separator: ".", omittingEmptySubsequences: false).prefix(fins)
        let xifres = components.compactMap { c in c.allSatisfy(\.isASCII) ? Int(c) : nil }
        return xifres.count == components.count && !xifres.isEmpty ? xifres : nil
    }
}

/// El que llegeix el diagnòstic. L'app i `main.swift` hi posen el seu `Lector` i les carpetes de debò; les proves,
/// fixtures. Tot és de només lectura: el diagnòstic no executa res, ni obre ni escriu res.
public struct EntornDiagnostic: Sendable {
    public var processos: any FontProcessos
    public var warp: @Sendable () -> InstallacioWarp
    public var rutaWarp: URL
    /// `settings.toml` de Warp. `nil`: no es mira.
    public var rutaAjustos: URL?
    public var carpetaSessions: URL
    public var transcripcions: LectorTranscripcions
    public var confianca: LectorConfianca
    /// On és `preferencies.json` (la carpeta de la configuració). `nil`: l'app no en té.
    public var carpetaConfiguracio: URL?
    /// La carpeta és de prova (`--config`): l'app no hi toca mai `restore_session`, perquè D19 només val per a la de debò.
    /// El CLI sempre llegeix la de debò.
    public var configuracioDeProva: Bool
    public var inici: String
    /// El nom d'usuari, que l'informe anonimitzat no porta. Per defecte, l'últim component de la carpeta d'inici.
    public var usuari: String
    /// La versió de macOS, per a l'informe.
    public var sistema: String
    /// Com està l'actualització automàtica. `nil`: no aplica (el CLI).
    public var actualitzacions: (@Sendable () -> String)?

    public init(lector: Lector, carpetaConfiguracio: URL?, configuracioDeProva: Bool = false,
                transcripcions: LectorTranscripcions, confianca: LectorConfianca, usuari: String? = nil,
                sistema: String = ProcessInfo.processInfo.operatingSystemVersionString) {
        processos = lector.processos
        // El Warp que compta, com a la lectura: el que corre, si n'hi ha un (decisió 4, 0.31.1).
        warp = { lector.installacio() }
        rutaWarp = lector.rutaWarp
        rutaAjustos = lector.rutaAjustos
        carpetaSessions = lector.carpetaSessions
        self.transcripcions = transcripcions
        self.confianca = confianca
        self.carpetaConfiguracio = carpetaConfiguracio
        self.configuracioDeProva = configuracioDeProva
        inici = lector.inici
        self.usuari = usuari ?? (lector.inici as NSString).lastPathComponent
        self.sistema = sistema
    }
}

/// Una comprovació del diagnòstic i el que n'ha sortit.
public struct Comprovacio: Sendable, Equatable {
    public enum Id: String, Sendable, CaseIterable {
        /// a) Warp és obert i corre Claude als seus terminals, però no se'n reconeix cap.
        case terminalsWarp = "warp-terminals"
        /// b) Processos `claude` sense fitxer de sessió vàlid, o amb un `kind` desconegut.
        case sessionsClaude = "claude-sessions"
        /// c) Cap transcripció enlloc, o les de les sessions vives no són on s'esperen.
        case transcripcions = "claude-transcripts"
        /// d) `~/.claude.json` no es pot llegir o no té `projects`.
        case configuracioClaude = "claude-json"
        /// e) A `warp.sqlite` hi falta alguna taula o columna de les que es llegeixen.
        case baseWarp = "warp-database"
        /// f) La versió de Warp, comparada amb `VersionsProvades`.
        case versioWarp = "warp-version"
        /// f) La versió de Claude Code, dels fitxers de sessió.
        case versioClaude = "claude-version"
        /// g) L'ajust `restore_session` de Warp i el consentiment (D-P4).
        case restauracio = "warp-restore"

        /// El títol, en anglès.
        public var titol: String {
            switch self {
            case .terminalsWarp: "Warp terminals"
            case .sessionsClaude: "Claude Code session files"
            case .transcripcions: "Claude Code transcripts"
            case .configuracioClaude: "Claude Code settings (~/.claude.json)"
            case .baseWarp: "Warp database"
            case .versioWarp: "Warp version"
            case .versioClaude: "Claude Code version"
            case .restauracio: "Warp session restoration"
            }
        }
    }

    public enum Resultat: String, Sendable {
        case be = "ok"
        case avis = "warning"
        case error = "error"
    }

    public var id: Id
    public var resultat: Resultat
    /// En anglès.
    public var detall: String

    public init(_ id: Id, _ resultat: Resultat, _ detall: String) {
        self.id = id
        self.resultat = resultat
        self.detall = detall
    }
}

/// El resultat del diagnòstic: les comprovacions, i l'informe en text o en JSON.
public struct InformeDiagnostic: Sendable, Equatable {
    public var versio: String
    public var sistema: String
    public var anonimitzat: Bool
    public var comprovacions: [Comprovacio]
    /// Si l'app s'actualitza, i com està. `nil`: no aplica (el CLI).
    public var actualitzacions: String?

    public init(versio: String, sistema: String, anonimitzat: Bool, comprovacions: [Comprovacio], actualitzacions: String? = nil) {
        self.actualitzacions = actualitzacions
        self.versio = versio
        self.sistema = sistema
        self.anonimitzat = anonimitzat
        self.comprovacions = comprovacions
    }

    public func compta(_ resultat: Comprovacio.Resultat) -> Int {
        comprovacions.filter { $0.resultat == resultat }.count
    }

    public func comprovacio(_ id: Comprovacio.Id) -> Comprovacio? { comprovacions.first { $0.id == id } }

    /// L'informe per enganxar en una issue de GitHub, en anglès.
    public var text: String {
        var linies = ["\(versio) diagnostic", "macOS: \(sistema)"]
        linies.append(anonimitzat
            ? "Anonymized: no user name, home paths or folder names (only their shape)."
            : "Not anonymized: it includes the user name, paths and folder names.")
        linies.append("Updates: \(actualitzacions ?? "not applicable (command line)")")
        linies.append("")
        for c in comprovacions {
            let marca = "[\(c.resultat.rawValue)]"
            linies.append(marca.padding(toLength: 10, withPad: " ", startingAt: 0) + "\(c.id.titol): \(c.detall)")
        }
        linies.append("")
        linies.append("Summary: \(compta(.be)) ok, \(Plural.compta(compta(.avis), "warning", "warnings")), "
            + "\(Plural.compta(compta(.error), "error", "errors")).")
        return linies.map { $0 + "\n" }.joined()
    }

    /// El mateix, en JSON (claus en anglès, ordenades).
    public func json() throws -> Data {
        struct Informe: Encodable {
            struct Check: Encodable {
                var id: String
                var title: String
                var status: String
                var detail: String
            }

            struct Summary: Encodable {
                var ok: Int
                var warnings: Int
                var errors: Int
            }

            var app: String
            var macOS: String
            var anonymized: Bool
            var updates: String?
            var checks: [Check]
            var summary: Summary
        }
        let informe = Informe(app: versio, macOS: sistema, anonymized: anonimitzat, updates: actualitzacions,
                              checks: comprovacions.map {
                                  .init(id: $0.id.rawValue, title: $0.id.titol, status: $0.resultat.rawValue, detail: $0.detall)
                              },
                              summary: .init(ok: compta(.be), warnings: compta(.avis), errors: compta(.error)))
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try codificador.encode(informe)
    }
}

/// Les comprovacions (`executa`). Només llegeix: processos (`sysctl`), fitxers i l'esquema de `warp.sqlite` (en només
/// lectura). No executa cap programa, ni Warp ni `claude`.
public enum Diagnostic {
    /// La variable que Warp posa a l'entorn de cada shell (docs/fets-verificats.md, «Identitat de pane»).
    static let variablePane = "WARP_TERMINAL_SESSION_UUID"
    /// La llengua de l'informe, sigui quina sigui la de l'app: és el que es comparteix a les incidències de GitHub.
    static let llengua = "en"

    /// L'informe, en anglès: també els motius que pren del Core (els errors de `preferencies.json` i de `settings.toml`), que
    /// es componen dins del bloc amb la llengua fixada (`Idioma.fixada`).
    public static func executa(_ entorn: EntornDiagnostic, anonimitza: Bool) -> InformeDiagnostic {
        Idioma.$fixada.withValue(llengua) { compon(entorn, anonimitza: anonimitza) }
    }

    private static func compon(_ entorn: EntornDiagnostic, anonimitza: Bool) -> InformeDiagnostic {
        let anon = Anonimitzador(inici: entorn.inici, usuari: entorn.usuari, actiu: anonimitza)
        let installacio = entorn.warp()
        let claude = processosClaude(entorn.processos)
        let sessions = llegeixSessions(entorn.carpetaSessions, processos: entorn.processos)
        let consentiment = llegeixConsentiment(entorn.carpetaConfiguracio)
        var comprovacions = [
            terminals(entorn, installacio, claude, anon),
            fitxersSessio(entorn, claude, sessions, anon),
            transcripcions(entorn, anon),
            configuracioClaude(entorn, anon),
            base(entorn, consentiment: consentiment, anon),
            versioWarp(installacio, anon),
            versioClaude(sessions, anon),
            restauracio(entorn, consentiment: consentiment, anon),
        ]
        // L'última xarxa: cap text (tampoc el d'un error) no hi deixa la carpeta d'inici ni el nom d'usuari.
        for i in comprovacions.indices { comprovacions[i].detall = anon.text(comprovacions[i].detall) }
        return InformeDiagnostic(versio: "\(WarpLaunch.nom) \(WarpLaunch.versio)", sistema: entorn.sistema,
                                 anonimitzat: anonimitza, comprovacions: comprovacions,
                                 actualitzacions: entorn.actualitzacions.map { anon.text($0()) })
    }

    // MARK: - Lectures

    struct ProcesClaude {
        var pid: Int32
        var info: InfoProces
        var pare: Int32?
    }

    /// Tots els processos de Claude Code de l'usuari. No n'hi ha prou amb el nom (`p_comm`): el del binari de Claude Code
    /// és la seva versió (`2.1.319`, 07/11/2026, `ps -o ucomm`). Es miren tots, com `InfoProces.esClaude`, però només
    /// compten els que corren com a Claude Code (`esClaudeCode`).
    static func processosClaude(_ processos: any FontProcessos) -> [ProcesClaude] {
        let arbre = processos.fills()
        let pids = Set(arbre.keys).union(arbre.values.joined())
        return pids.sorted().compactMap { pid in
            guard pid > 1, let info = processos.proces(pid), esClaudeCode(info) else { return nil }
            return ProcesClaude(pid: pid, info: info, pare: processos.pare(pid))
        }
    }

    /// El binari de Claude Code corre com a Claude Code (`argv[0]` és `claude`, o el binari mateix), i no com una de les
    /// eines que porta a dins. El 07/11/2026 (`ps`, 2.1.319), el mateix binari corria com a `ugrep -G --ignore-files …`
    /// quan Claude cerca: fill del shell de l'eina Bash de Claude, amb el pane de la pestanya a l'entorn i sense fitxer de
    /// sessió. No és cap sessió.
    static func esClaudeCode(_ info: InfoProces) -> Bool {
        guard info.esClaude, let primer = info.argv.first else { return false }
        let nom = (primer as NSString).lastPathComponent
        return nom == "claude" || nom == (info.executable as NSString).lastPathComponent
    }

    struct LecturaSessions {
        var llegible = true
        /// Pel pid de dins del fitxer.
        var valids: [Int32: LectorSessions.FitxerSessio] = [:]
        /// El nom dels fitxers `.json` que no són de sessió.
        var invalids: [String] = []
        /// El procés de cada fitxer vàlid que encara corre. Els altres són d'un procés que ja ha acabat.
        var vius: [Int32: InfoProces] = [:]

        /// Els fitxers dels processos vius que `LectorSessions` llegeix com a Claude (`InfoProces.esClaude`).
        var deClaude: [LectorSessions.FitxerSessio] {
            valids.filter { vius[$0.key]?.esClaude == true }.sorted { $0.key < $1.key }.map(\.value)
        }
    }

    /// Els fitxers de `~/.claude/sessions`, amb el format que llegeix `LectorSessions`, i el procés de cadascun.
    static func llegeixSessions(_ carpeta: URL, processos: any FontProcessos) -> LecturaSessions {
        guard let fitxers = try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil) else {
            return LecturaSessions(llegible: false)
        }
        var lectura = LecturaSessions()
        for fitxer in fitxers.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let dades = try? Data(contentsOf: fitxer),
               let sessio = try? JSONDecoder().decode(LectorSessions.FitxerSessio.self, from: dades) {
                lectura.valids[sessio.pid] = sessio
                if let info = processos.proces(sessio.pid) { lectura.vius[sessio.pid] = info }
            } else {
                lectura.invalids.append(fitxer.lastPathComponent)
            }
        }
        return lectura
    }

    enum ConsentimentLlegit {
        case senseCarpeta
        case error(String)
        case llegit(Preferencies.Consentiment)

        var acceptat: Bool {
            if case let .llegit(consentiment) = self { consentiment.esAcceptat } else { false }
        }
    }

    /// `preferencies.json`, sense escriure-hi res (`MagatzemPreferencies.carrega`).
    static func llegeixConsentiment(_ carpeta: URL?) -> ConsentimentLlegit {
        guard let carpeta else { return .senseCarpeta }
        do {
            return .llegit(try MagatzemPreferencies(carpeta: carpeta).carrega().restauracio)
        } catch {
            return .error(error.description)
        }
    }

    // MARK: - a) Terminals de Warp

    static func terminals(_ e: EntornDiagnostic, _ warp: InstallacioWarp, _ claude: [ProcesClaude],
                          _ anon: Anonimitzador) -> Comprovacio {
        let obert = e.processos.warpObert(executable: warp.executable)
        let terminals = e.processos.terminalsDeWarp(executable: warp.executable)
        let pidsClaude = Set(claude.map(\.pid))
        // Els d'un terminal de Warp: amb el pane a l'entorn, i que no pengen de launchd ni d'un altre `claude` (el dimoni de
        // Claude i les seves reserves també hereten el pane, docs/fets-verificats.md).
        let enTerminal = claude.filter { c in
            guard c.info.entorn[variablePane] != nil, let pare = c.pare else { return false }
            return pare > 1 && !pidsClaude.contains(pare)
        }
        let shells = Set(terminals.map(\.pid))
        let reconeguts = enTerminal.filter { penja($0.pid, deAlgunDe: shells, e.processos) }.count
        let binari = anon.ruta(warp.executable)
        let enWarp = Plural.compta(enTerminal.count, "claude process runs", "claude processes run")
            + " in Warp terminals (with \(variablePane))"
        let xifres = "\(Plural.compta(terminals.count, "terminal", "terminals")) of its terminal-server, "
            + "\(terminals.filter(\.claude).count) with Claude"

        if obert, terminals.isEmpty, !enTerminal.isEmpty {
            return Comprovacio(.terminalsWarp, .error, "Warp is open and \(enWarp), but no terminal of Warp's "
                + "terminal-server (\(binari)) was recognized. Warp may have changed how it runs its terminals: Warp Launch "
                + "can't see which tabs are open, and would open them again.")
        }
        if !obert, !enTerminal.isEmpty {
            var detall = "\(enWarp), but Warp Stable (\(binari)) isn't seen as open. If Warp is open, it may run from "
                + "another binary, which Warp Launch doesn't see."
            if let preview = warp.executablePreview, e.processos.warpObert(executable: preview) {
                detall += " Warp Preview is open, and it isn't supported yet."
            }
            return Comprovacio(.terminalsWarp, .avis, detall)
        }
        if obert, terminals.isEmpty {
            return Comprovacio(.terminalsWarp, .avis, "Warp is open, but no terminal of its terminal-server (\(binari)) "
                + "was recognized. If Warp has windows open, it may have changed how it runs its terminals.")
        }
        if obert, !enTerminal.isEmpty, reconeguts == 0 {
            return Comprovacio(.terminalsWarp, .avis, "Warp is open (\(xifres)), but none of the "
                + "\(Plural.compta(enTerminal.count, "claude process", "claude processes")) in Warp terminals runs in one of "
                + "them. Warp may have changed how it runs its terminals.")
        }
        if obert {
            return Comprovacio(.terminalsWarp, .be, "Warp is open: \(xifres); \(enWarp).")
        }
        return Comprovacio(.terminalsWarp, .be, "Warp isn't open, and no claude process runs in a Warp terminal.")
    }

    /// Si el procés penja (a qualsevol distància) d'algun dels `pares`.
    private static func penja(_ pid: Int32, deAlgunDe pares: Set<Int32>, _ processos: any FontProcessos) -> Bool {
        var actual = processos.pare(pid)
        var passos = 0
        while let p = actual, p > 1, passos < 16 {
            if pares.contains(p) { return true }
            actual = processos.pare(p)
            passos += 1
        }
        return false
    }

    // MARK: - b) Fitxers de sessió de Claude

    static func fitxersSessio(_ e: EntornDiagnostic, _ claude: [ProcesClaude], _ sessions: LecturaSessions,
                              _ anon: Anonimitzador) -> Comprovacio {
        let carpeta = anon.ruta(e.carpetaSessions.path)
        let efecte = "Warp Launch can't tell which tab runs which conversation."
        let processos = Plural.compta(claude.count, "claude process", "claude processes")
        guard sessions.llegible else {
            if claude.isEmpty {
                return Comprovacio(.sessionsClaude, .be, "No claude process is running, and \(carpeta) doesn't exist.")
            }
            return Comprovacio(.sessionsClaude, .error, "\(processos) running, but \(carpeta) can't be read. Claude Code "
                + "may have moved its session files. \(efecte)")
        }
        // Claude escriu el fitxer després de la pregunta de confiança (docs/fets-verificats.md, 05/11/2026): sense fitxer, en
        // una carpeta on Claude no confia, encara espera la tecla. No vol dir que Claude Code hagi canviat res.
        let confianca = carpetesConfiades(e)
        let esperen = claude.filter { c in
            guard sessions.valids[c.pid] == nil, let confianca, let carpeta = e.processos.carpeta(c.pid) else { return false }
            return !confianca.confiada(carpeta)
        }
        let senseFitxer = claude.filter { c in sessions.valids[c.pid] == nil && !esperen.contains { $0.pid == c.pid } }
        let notaConfianca = esperen.isEmpty ? "" : " \(Plural.compta(esperen.count, "process has", "processes have")) no "
            + "session file yet, in a folder Claude Code doesn't trust: probably waiting for the trust question ("
            + llista(esperen.map { "pid \($0.pid)" }) + ")."
        let fitxers = Plural.compta(sessions.valids.count + sessions.invalids.count, "session file", "session files")
        if !senseFitxer.isEmpty, senseFitxer.count == claude.count - esperen.count {
            return Comprovacio(.sessionsClaude, .error, "None of the "
                + "\(Plural.compta(senseFitxer.count, "claude process", "claude processes")) has a valid session file in "
                + "\(carpeta) (\(fitxers); \(llista(senseFitxer.map { descripcio($0, anon) }))). Claude Code may have "
                + "changed the format or the place of its session files. \(efecte)" + notaConfianca)
        }

        let desconeguts = sessions.valids.values.filter { !LectorSessions.tipusConeguts.contains($0.kind ?? "") }
            .sorted { $0.pid < $1.pid }
        // Un fitxer d'un procés viu que no sembla Claude: `LectorSessions` el descarta («ara és un altre procés»). Si Claude
        // Code canviés la ruta o el nom del binari, l'app no veuria cap sessió.
        let descartats = sessions.vius.filter { !$0.value.esClaude }.sorted { $0.key < $1.key }
        var problemes: [String] = []
        if !senseFitxer.isEmpty {
            problemes.append("\(Plural.compta(senseFitxer.count, "process has", "processes have")) no valid session file ("
                + llista(senseFitxer.map { descripcio($0, anon) }) + ")")
        }
        if !descartats.isEmpty {
            problemes.append("\(Plural.compta(descartats.count, "session file belongs", "session files belong")) to a "
                + "running process Warp Launch doesn't see as claude (" + llista(descartats.map { pid, info in
                    "pid \(pid), «\(anon.ruta(info.executable))»"
                }) + ")")
        }
        if !sessions.invalids.isEmpty {
            let noms = sessions.invalids.map { anon.actiu && !Self.esNomDeSessio($0) ? anon.forma($0) : $0 }
            problemes.append("\(Plural.compta(noms.count, "file isn't", "files aren't")) a session file Warp Launch can "
                + "read (\(llista(noms)))")
        }
        if !desconeguts.isEmpty {
            let tipus = desconeguts.map { "pid \($0.pid): \(codi($0.kind, anon) ?? "no kind")" }
            problemes.append("\(Plural.compta(desconeguts.count, "session has", "sessions have")) an unknown kind ("
                + llista(tipus) + "; known: " + LectorSessions.tipusConeguts.sorted().joined(separator: ", ") + ")")
        }
        guard problemes.isEmpty else {
            return Comprovacio(.sessionsClaude, .avis, "\(processos), \(fitxers) in \(carpeta): "
                + problemes.joined(separator: "; ") + ". Claude Code may have changed its session files; a process that has "
                + "just started may not have written its file yet." + notaConfianca)
        }
        let perTipus = Dictionary(grouping: sessions.deClaude, by: { $0.kind ?? "" }).mapValues(\.count)
            .sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        let ambFitxer = esperen.isEmpty ? "\(processos), each with its session file"
            : "\(Plural.compta(claude.count - esperen.count, "claude process", "claude processes")) with a session file"
        return Comprovacio(.sessionsClaude, .be, "\(ambFitxer) in \(carpeta)"
            + (perTipus.isEmpty ? "." : " (\(perTipus.joined(separator: ", "))).") + notaConfianca)
    }

    /// Les carpetes on Claude Code confia (`~/.claude.json`). Sense el fitxer, Claude no confia en cap; si no s'entén,
    /// `nil`: no se sap.
    private static func carpetesConfiades(_ e: EntornDiagnostic) -> Confianca? {
        e.confianca.llegeix(inici: e.inici)
            ?? (FileManager.default.fileExists(atPath: e.confianca.ruta.path) ? nil
                : Confianca(confiades: [], inici: Rutes.canonica(e.inici)))
    }

    /// `1234.json`: el nom que Claude dona als fitxers de sessió.
    private static func esNomDeSessio(_ nom: String) -> Bool {
        nom.hasSuffix(".json") && !nom.dropLast(5).isEmpty && nom.dropLast(5).allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Un procés sense fitxer: el pid i, si en té, la subordre (`daemon`). Anonimitzat, la subordre només si és una paraula
    /// curta en minúscules: el primer argument pot ser el que s'ha demanat a Claude.
    private static func descripcio(_ proces: ProcesClaude, _ anon: Anonimitzador) -> String {
        guard proces.info.argv.count > 1 else { return "pid \(proces.pid), no arguments" }
        let primer = proces.info.argv[1]
        if primer.hasPrefix("-") { return "pid \(proces.pid), options only" }
        if let paraula = codi(primer, anon) { return "pid \(proces.pid), «\(paraula)»" }
        return "pid \(proces.pid), other arguments"
    }

    /// Un valor curt de Claude (una subordre, un `kind`). Anonimitzat, només si és una paraula curta en minúscules.
    private static func codi(_ valor: String?, _ anon: Anonimitzador) -> String? {
        guard let valor, !valor.isEmpty else { return nil }
        guard anon.actiu else { return String(valor.prefix(40)) }
        let esParaula = valor.count <= 24 && valor.first.map { $0.isASCII && $0.isLowercase } == true
            && valor.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_") }
        return esParaula ? valor : nil
    }

    /// Fins a 8 elements, i quants en queden.
    private static func llista(_ elements: [String]) -> String {
        let primers = elements.prefix(8).joined(separator: "; ")
        return elements.count > 8 ? primers + "; and \(elements.count - 8) more" : primers
    }

    // MARK: - c) Transcripcions

    static func transcripcions(_ e: EntornDiagnostic, _ anon: Anonimitzador) -> Comprovacio {
        let carpeta = e.transcripcions.carpeta
        let mostrada = anon.ruta(carpeta.path)
        guard let projectes = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else {
            return Comprovacio(.transcripcions, .avis, "\(mostrada) can't be read. Claude Code may have moved its "
                + "transcripts: Warp Launch can't resume conversations.")
        }
        var carpetes = 0
        var total = 0
        for projecte in projectes {
            // Com `LectorTranscripcions.on`: els enllaços apunten a un altre projecte, que ja es compta.
            let cami = carpeta.appending(path: projecte).path
            var info = stat()
            guard lstat(cami, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  let fitxers = try? FileManager.default.contentsOfDirectory(atPath: cami) else { continue }
            carpetes += 1
            total += fitxers.filter { $0.hasSuffix(".jsonl") && UUID(uuidString: String($0.dropLast(6))) != nil }.count
        }
        guard total > 0 else {
            return Comprovacio(.transcripcions, .avis, "No transcript (<id>.jsonl) in any of the "
                + "\(Plural.compta(carpetes, "project folder", "project folders")) of \(mostrada). Claude Code may have "
                + "changed where or how it saves conversations: Warp Launch can't resume them.")
        }
        let vives = LectorSessions(carpeta: e.carpetaSessions, processos: e.processos).llegeix().sessions
        var aLaCarpeta = 0
        var altres = 0
        var enlloc = 0
        for sessio in vives {
            switch e.transcripcions.on(sessio: sessio.sessionId, carpeta: sessio.carpeta) {
            case .aLaCarpeta: aLaCarpeta += 1
            case .altres: altres += 1
            case .enlloc: enlloc += 1
            }
        }
        let xifres = "\(Plural.compta(total, "transcript", "transcripts")) in "
            + "\(Plural.compta(carpetes, "project folder", "project folders")) of \(mostrada)"
        if aLaCarpeta == 0, altres > 0 {
            return Comprovacio(.transcripcions, .avis, "\(xifres), but none of the "
                + "\(Plural.compta(vives.count, "live session", "live sessions")) has its transcript in the project folder "
                + "of its own folder (\(altres) in another one). Claude Code may have changed how it names project folders: "
                + "Warp Launch wouldn't resume the most recent conversation of each folder.")
        }
        return Comprovacio(.transcripcions, .be, "\(xifres). Live sessions: \(aLaCarpeta) with the transcript in their "
            + "project folder, \(altres) in another one, \(enlloc) without one yet (a new conversation has none until its "
            + "first message).")
    }

    // MARK: - d) ~/.claude.json

    static func configuracioClaude(_ e: EntornDiagnostic, _ anon: Anonimitzador) -> Comprovacio {
        let ruta = anon.ruta(e.confianca.ruta.path)
        let efecte = "Warp Launch won't warn about the folders where Claude Code will ask whether you trust them (the tab "
            + "waits for a key)."
        guard let dades = try? Data(contentsOf: e.confianca.ruta) else {
            return Comprovacio(.configuracioClaude, .avis, "\(ruta) can't be read. \(efecte)")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: dades)) as? [String: Any] else {
            return Comprovacio(.configuracioClaude, .avis, "\(ruta) isn't a JSON object. \(efecte)")
        }
        guard let projectes = json[LectorConfianca.clauProjectes] as? [String: Any] else {
            return Comprovacio(.configuracioClaude, .avis, "\(ruta) has no «\(LectorConfianca.clauProjectes)». Claude Code "
                + "may have changed its format. \(efecte)")
        }
        let entrades = projectes.values.compactMap { $0 as? [String: Any] }
        let ambClau = entrades.filter { $0[LectorConfianca.clauConfianca] != nil }.count
        let confiades = entrades.filter { $0[LectorConfianca.clauConfianca] as? Bool == true }.count
        if !entrades.isEmpty, ambClau == 0 {
            return Comprovacio(.configuracioClaude, .avis, "None of the "
                + "\(Plural.compta(entrades.count, "project", "projects")) in \(ruta) has «\(LectorConfianca.clauConfianca)». "
                + "Claude Code may have renamed it. \(efecte)")
        }
        return Comprovacio(.configuracioClaude, .be, "\(Plural.compta(projectes.count, "project", "projects")) in \(ruta), "
            + "\(confiades) trusted.")
    }

    // MARK: - e) warp.sqlite

    static func base(_ e: EntornDiagnostic, consentiment: ConsentimentLlegit, _ anon: Anonimitzador) -> Comprovacio {
        // Només si la restauració desa la base: la de Warp, o la de l'app quan fa la foto (D19, amb el consentiment).
        let desaFinestres = e.rutaAjustos.map { LectorAjustosWarp(ruta: $0).desaFinestres() }
        guard desaFinestres != false || consentiment.acceptat else {
            return Comprovacio(.baseWarp, .be, "Not checked: Warp doesn't save its windows (restore_session = false), and "
                + "Warp Launch doesn't manage it yet.")
        }
        let ruta = anon.ruta(e.rutaWarp.path)
        let efecte = "Importing from Warp and linking tabs won't work."
        let falta: (obligatories: [String], opcionals: [String])
        do {
            falta = try LectorWarp(ruta: e.rutaWarp).queFalta()
        } catch ErrorLectura.noHiHaBase {
            return Comprovacio(.baseWarp, .avis, "\(ruta) doesn't exist: Warp hasn't saved its windows there yet, or keeps "
                + "them somewhere else. \(efecte)")
        } catch ErrorLectura.macOSNoDeixaLlegir {
            return Comprovacio(.baseWarp, .error, "macOS doesn't let this process read \(ruta): allow it in System Settings "
                + "› Privacy & Security › Files and Folders (Warp Launch), or Full Disk Access (a terminal). \(efecte)")
        } catch let ErrorLectura.sqlite(missatge) {
            return Comprovacio(.baseWarp, .error, "\(ruta) can't be read (SQLite: \(missatge)). \(efecte)")
        } catch {
            return Comprovacio(.baseWarp, .error, "\(ruta) can't be read (\(error)). \(efecte)")
        }
        if !falta.obligatories.isEmpty {
            return Comprovacio(.baseWarp, .error, "\(ruta) lacks \(falta.obligatories.joined(separator: ", ")). Warp may "
                + "have changed its database. \(efecte)")
        }
        if !falta.opcionals.isEmpty {
            return Comprovacio(.baseWarp, .avis, "\(ruta) lacks \(falta.opcionals.joined(separator: ", ")). Warp Launch can "
                + "still read the windows, but not the folder of each pane's last command.")
        }
        let columnes = LectorWarp.esquema.map(\.columnes.count).reduce(0, +)
        return Comprovacio(.baseWarp, .be, "\(ruta) has the \(LectorWarp.esquema.count) tables and \(columnes) columns "
            + "Warp Launch reads.")
    }

    // MARK: - f) Versions

    static func versioWarp(_ warp: InstallacioWarp, _ anon: Anonimitzador) -> Comprovacio {
        guard warp.hiHaStable else {
            return Comprovacio(.versioWarp, .avis, warp.executablePreview == nil ? "Warp Stable isn't installed."
                : "Warp Stable isn't installed, only Warp Preview, which isn't supported yet.")
        }
        let on = anon.ruta(warp.app.url.path)
        guard let versio = warp.app.versio.map(net) else {
            return Comprovacio(.versioWarp, .avis, "The version of Warp at \(on) is unknown (no CFBundleShortVersionString).")
        }
        if VersionsProvades.provada(versio, VersionsProvades.warp) {
            return Comprovacio(.versioWarp, .be, "Warp \(versio), at \(on): tested with Warp Launch.")
        }
        return Comprovacio(.versioWarp, .avis, "Warp \(versio), at \(on), hasn't been tested with Warp Launch (tested: "
            + VersionsProvades.warp.map(\.description).joined(separator: ", ") + "). It isn't an error: if something fails, "
            + "this may be why.")
    }

    static func versioClaude(_ sessions: LecturaSessions, _ anon: Anonimitzador) -> Comprovacio {
        // Només els dels processos vius: el fitxer d'un Claude que no ha pogut acabar bé pot ser d'una versió d'abans.
        let fitxers = sessions.deClaude
        guard !fitxers.isEmpty else {
            return Comprovacio(.versioClaude, .be, "No Claude Code session is running: the version is unknown.")
        }
        let perVersio = Dictionary(grouping: fitxers.compactMap(\.version).map(net), by: { $0 }).mapValues(\.count)
        guard !perVersio.isEmpty else {
            let quants = Plural.compta(fitxers.count, "session file", "session files")
            return Comprovacio(.versioClaude, .avis, "None of the \(quants) says its version («version»). Claude Code may "
                + "have changed the format of its session files.")
        }
        let ordenades = perVersio.keys.sorted { a, b in
            let (xa, xb) = (RangVersions.xifres(a) ?? [], RangVersions.xifres(b) ?? [])
            return xa == xb ? a < b : xa.lexicographicallyPrecedes(xb)
        }
        let noProvades = Set(ordenades.filter { !VersionsProvades.provada($0, VersionsProvades.claude) })
        // Cada versió, un sol cop, com la de Warp. Si n'hi ha de provades i de no provades, cada no provada ho porta al costat.
        let totes = noProvades.count == ordenades.count
        let text = ordenades.map { versio in
            let sessions = Plural.compta(perVersio[versio] ?? 0, "session", "sessions")
            return totes || !noProvades.contains(versio) ? "\(versio) (\(sessions))"
                : "\(versio) (\(sessions), not tested with Warp Launch)"
        }.joined(separator: ", ")
        guard noProvades.isEmpty else {
            let provades = "(tested: " + VersionsProvades.claude.map(\.description).joined(separator: ", ") + ")"
            let quines = totes
                ? ", \(ordenades.count == 1 ? "hasn't" : "haven't") been tested with Warp Launch \(provades)."
                : " \(provades)."
            return Comprovacio(.versioClaude, .avis, "Claude Code \(text), from the session files\(quines) It isn't an "
                + "error: if something fails, this may be why.")
        }
        return Comprovacio(.versioClaude, .be, "Claude Code \(text), from the session files: tested with Warp Launch.")
    }

    /// Una versió que surt d'un fitxer d'una altra app, sense res que no ho sembli.
    private static func net(_ versio: String) -> String {
        String(versio.prefix(40).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "+") })
    }

    // MARK: - g) Restauració de Warp i consentiment

    static func restauracio(_ e: EntornDiagnostic, consentiment: ConsentimentLlegit, _ anon: Anonimitzador) -> Comprovacio {
        let deConsentiment: (Comprovacio.Resultat, String)
        switch consentiment {
        case .senseCarpeta:
            deConsentiment = (.avis, "Consent: unknown (Warp Launch has no configuration folder).")
        case let .error(motiu):
            deConsentiment = (.error, "\(Preferencies.nomFitxer) can't be read (reason: \(motiu)): Warp "
                + "Launch shows the error instead of the editor.")
        case let .llegit(llegit) where !llegit.esAcceptat:
            // 0.31.0: retirat amb «Deixa de fer servir Warp Launch», que torna l'ajust com era.
            deConsentiment = (.avis, llegit.retiratEl.map {
                // Amb «migrat», el de sèrie de Warp, no el d'abans (revisió de la 0.31.0).
                "Consent withdrawn on \($0.formatted(.iso8601.year().month().day())), when restore_session was put back as "
                    + "it was before Warp Launch (or to Warp's default, on, if that wasn't known): Warp Launch asks for it "
                    + "again the next time it opens, and doesn't touch Warp until then."
            } ?? "Consent not given yet: Warp Launch asks for it the first time it opens, and doesn't touch Warp until then.")
        case let .llegit(llegit):
            deConsentiment = (.be, llegit.acceptatEl.map { "Consent given on \($0.formatted(.iso8601.year().month().day()))." }
                ?? "Consent counted as given (the configuration existed before Warp Launch 0.29.0).")
        }
        guard let ruta = e.rutaAjustos else {
            return Comprovacio(.restauracio, deConsentiment.0, "restore_session: not checked. \(deConsentiment.1)")
        }
        let mostrada = anon.ruta(ruta.path)
        // Sense la línia (0.31.2, decisió A d'en David): Warp fa servir el valor de sèrie, i l'app l'hi escriu quan gestiona
        // l'ajust (`AjustRestauracio`), només amb el permís i la configuració de debò (D19).
        let deSerie = "Warp uses its default, on (after a restart, it restores its own windows, without Claude)."
        let quan = !consentiment.acceptat ? "when it manages the setting (with consent and the real configuration folder)"
            : e.configuracioDeProva ? "only with the real configuration folder, not with a test one (--config)"
            : "within a minute while it's running"
        // Sense el fitxer, només el crea amb Warp obert i amb algun terminal (ronda 5, `Lector.warpHaAcabatDArrencar`): com
        // és Warp ara, pels processos (només lectura), perquè es vegi quin cas és. No diu que Warp restaurarà res: potser és
        // tancat, i potser no té cap finestra desada.
        let ambWarpObert = "but only when Warp is open with a terminal (when Warp starts without settings.toml, it first "
            + "moves its older settings into it, and it wouldn't if the file were already there)"
        func warpAra() -> String {
            let executable = e.warp().executable
            return !e.processos.warpObert(executable: executable) ? "Warp is closed now."
                : e.processos.warpHaAcabatDArrencar(executable: executable) ? "Warp is open now, with a terminal."
                : "Warp is open now, with no terminal yet."
        }
        // Com l'app (`AjustRestauracio.llegeix`, només lectura): un enllaç, una carpeta que no ho és o un text que no és
        // UTF-8, l'app no els pot fer servir, i el diagnòstic no ha de dir que hi afegirà la línia.
        let lectura: AjustRestauracio.Lectura
        do {
            lectura = try AjustRestauracio.llegeix(ruta)
        } catch {
            return Comprovacio(.restauracio, .error, "\(mostrada): Warp Launch can't manage restore_session (reason: "
                + "\(anon.text(error.description))). " + deConsentiment.1)
        }
        let text: String
        switch lectura {
        case .senseFitxer:
            return Comprovacio(.restauracio, pitjor(.avis, deConsentiment.0), "\(mostrada) doesn't exist yet: Warp only "
                + "writes it once a setting is changed, and until then uses its default for restore_session, on. Warp Launch "
                + "creates it with only restore_session = false \(quan), \(ambWarpObert). \(warpAra()) " + deConsentiment.1)
        case .senseCarpeta:
            // Warp Launch no crea la carpeta de Warp (regla 7: només la línia). Sense la carpeta, Warp no ha obert mai cap
            // finestra: no hi ha res per restaurar.
            return Comprovacio(.restauracio, pitjor(.avis, deConsentiment.0),
                               "\(anon.ruta(ruta.deletingLastPathComponent().path)) doesn't exist: Warp hasn't been opened "
                                   + "yet for this user, and has no windows to restore. Warp Launch doesn't create Warp's "
                                   + "folder: once Warp has created it, Warp Launch turns restore_session off \(quan); if "
                                   + "there's no settings.toml yet, it creates one with only restore_session = false, "
                                   + "\(ambWarpObert). \(warpAra()) " + deConsentiment.1)
        case let .fitxer(_, llegit, _):
            text = llegit
        }
        let analisi: AjustRestauracio.Analisi
        do {
            analisi = try AjustRestauracio.analitza(text)
        } catch {
            // El motiu és el que diu l'app, en anglès (`executa`).
            return Comprovacio(.restauracio, .error, "\(mostrada) doesn't have the form Warp Launch expects for "
                + "restore_session (reason: \(error.description)). Warp may have changed its settings file: "
                + "Warp Launch won't change it. " + deConsentiment.1)
        }
        if case let .senseLinia(afegida) = analisi.lloc {
            guard case let .failure(motiu) = afegida else {
                return Comprovacio(.restauracio, pitjor(.avis, deConsentiment.0), "\(mostrada) has no restore_session: "
                    + "\(deSerie) Warp Launch adds restore_session = false to [general] \(quan). " + deConsentiment.1)
            }
            return Comprovacio(.restauracio, .error, "\(mostrada) has no restore_session: \(deSerie) Warp Launch can't add "
                + "it to this file (reason: \(motiu.description)), and won't change it. To let Warp Launch "
                + "manage it, turn «Restore windows, tabs, and panes on startup» off once in Warp's settings. "
                + deConsentiment.1)
        }
        let valor = analisi.valor
        if valor, consentiment.acceptat {
            // D19: només amb la configuració de debò. Amb una de prova, l'app no el desactiva mai.
            let qui = e.configuracioDeProva
                ? "With a test configuration folder (--config), Warp Launch doesn't turn it off. "
                : "Warp Launch turns it off within a minute while it's running. "
            return Comprovacio(.restauracio, .avis, "restore_session = true: after a restart, Warp will restore its own "
                + "windows, without Claude. " + qui + deConsentiment.1)
        }
        let estat = valor ? "restore_session = true (Warp restores its own windows)."
            : "restore_session = false (Warp doesn't restore its own windows)."
        return Comprovacio(.restauracio, deConsentiment.0, "\(estat) \(deConsentiment.1)")
    }

    private static func pitjor(_ a: Comprovacio.Resultat, _ b: Comprovacio.Resultat) -> Comprovacio.Resultat {
        a == .error || b == .error ? .error : a == .avis || b == .avis ? .avis : .be
    }
}

// MARK: - Anonimització

/// Treu de l'informe el nom d'usuari, la carpeta d'inici i els noms de carpeta, i en deixa la forma (`--anonimitza`, i el
/// botó «Copia el diagnòstic» de la Configuració): `~/Codi-Prova` → `~/Aaaa-Aaaaa`. Els noms de les carpetes i
/// els fitxers que llegeix l'app (`.claude`, `sessions`, `Warp.app`…) es queden: no són de l'usuari.
struct Anonimitzador: Sendable {
    let actiu: Bool
    /// La carpeta d'inici, tal com és i canònica, sense barra final; la més llarga primer.
    let inicis: [String]
    /// El nom d'usuari, i com surt al nom d'un projecte de Claude (`nom.cognom` → `nom-cognom`).
    let usuaris: [String]

    init(inici: String, usuari: String, actiu: Bool) {
        self.actiu = actiu
        func senseBarra(_ ruta: String) -> String { ruta.count > 1 && ruta.hasSuffix("/") ? String(ruta.dropLast()) : ruta }
        inicis = Array(Set([senseBarra(inici), senseBarra(Rutes.canonica(inici))]))
            .filter { $0.count > 1 }.sorted { $0.count > $1.count }
        usuaris = Array(Set([usuari, LectorTranscripcions.projecte(usuari) ?? usuari]))
            .filter { $0.count >= 2 }.sorted { $0.count > $1.count }
    }

    /// Els noms que es deixen: els de les rutes que llegeix l'app i els del sistema.
    static let coneguts: Set<String> = [
        ".claude", "sessions", "projects", ".claude.json", ".warp", "settings.toml", "Library", "Group Containers",
        "2BBY89MBSN.dev.warp", "Application Support", AppWarp.identificador, "warp.sqlite", ".config", "warp-launch",
        Preferencies.nomFitxer, IntentActualitzacio.nomFitxer, "configuracio.json", "estat.json",
        "Applications", "Warp.app", "WarpPreview.app", "Contents", "MacOS", "stable", "preview",
        "Users", "Volumes", "System", "private", "var", "tmp", "usr", "local", "bin", "opt", "homebrew", "share", ".local",
        "claude", "versions",
    ]

    /// La ruta, amb `~` en lloc de la carpeta d'inici i la forma dels noms que no són coneguts.
    func ruta(_ ruta: String) -> String {
        guard actiu else { return ruta }
        let prefix: String
        let resta: Substring
        if ruta == "~" || ruta.hasPrefix("~/") {
            (prefix, resta) = ("~", ruta.dropFirst())
        } else if let inici = inicis.first(where: { ruta == $0 || ruta.hasPrefix($0 + "/") }) {
            (prefix, resta) = ("~", ruta.dropFirst(inici.count))
        } else {
            (prefix, resta) = ("", ruta[...])
        }
        let components = resta.split(separator: "/", omittingEmptySubsequences: false).map { component in
            component.isEmpty || Self.coneguts.contains(String(component)) ? String(component) : forma(String(component))
        }
        return prefix + components.joined(separator: "/")
    }

    /// La forma d'un nom: les lletres passen a `a` o `A`, les xifres a `0`, i la resta d'ASCII es queda. Els altres
    /// caràcters ocupen el mateix en UTF-16 (`é`, `🙂`): Claude compta així la llargada del nom d'un projecte.
    func forma(_ nom: String) -> String {
        var resultat = String.UnicodeScalarView()
        for escalar in nom.unicodeScalars {
            switch escalar.value {
            case 0x61...0x7A: resultat.append("a")
            case 0x41...0x5A: resultat.append("A")
            case 0x30...0x39: resultat.append("0")
            case 0x00...0x7F: resultat.append(escalar)
            case 0x80...0xFFFF: resultat.append("\u{E9}")
            default: resultat.append("\u{1F642}")
            }
        }
        return String(resultat)
    }

    /// Un text qualsevol (el detall d'una comprovació, o el missatge d'un error): les rutes entre «» (també les relatives,
    /// com la destinació d'un enllaç: tot el que hi porta una `/`) o que comencen per la carpeta d'inici o per `~/`,
    /// anonimitzades, i el nom d'usuari, fora. Els motius del Core surten en anglès (`Diagnostic.executa`): entre “”.
    func text(_ text: String) -> String {
        guard actiu else { return text }
        var resultat = substitueix(#"«([^»]*/[^»]*)»"#, a: text) { "«" + ruta($0) + "»" }
        resultat = substitueix(#"“([^”]*/[^”]*)”"#, a: resultat) { "“" + ruta($0) + "”" }
        for inici in inicis {
            resultat = substitueix(NSRegularExpression.escapedPattern(for: inici) + #"(?=$|[/\s«»"'“”,;:()])"#, a: resultat) {
                _ in "~"
            }
        }
        // Un punt al final és de la frase: `~/.claude/projects.` no és cap carpeta «projects.».
        resultat = substitueix(#"~/[^\s«»"'“”,;:()]*"#, a: resultat) { trobada in
            let nucli = String(trobada.reversed().drop { $0 == "." }.reversed())
            return ruta(nucli) + trobada.dropFirst(nucli.count)
        }
        for usuari in usuaris {
            resultat = substitueix("(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: usuari) + "(?![A-Za-z0-9])",
                                   a: resultat) { _ in "<user>" }
        }
        return resultat
    }

    /// Substitueix cada aparició de l'expressió pel que en torna `per` (amb el primer grup, si n'hi ha; si no, tota).
    private func substitueix(_ patro: String, a text: String, per: (String) -> String) -> String {
        guard let expressio = try? NSRegularExpression(pattern: patro) else { return text }
        let nsText = text as NSString
        var resultat = text
        for coincidencia in expressio.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            let grup = coincidencia.numberOfRanges > 1 ? coincidencia.range(at: 1) : coincidencia.range
            guard let tot = Range(coincidencia.range, in: resultat) else { continue }
            resultat.replaceSubrange(tot, with: per(nsText.substring(with: grup)))
        }
        return resultat
    }
}
