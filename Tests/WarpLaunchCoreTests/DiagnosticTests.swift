import Foundation
import Testing
@testable import WarpLaunchCore

// El diagnòstic (pla A4, 0.30.0), amb un Mac inventat a una carpeta temporal: Warp i Claude falsos, la base de Warp de
// prova, i els fitxers de Claude i de l'app amb noms que no són els de debò. Cada comprovació, amb el fixture bo i un de
// trencat; l'anonimització; i `warp-launch diagnostica`.

private struct MacDeProva {
    let tmp: CarpetaTemporal
    /// La carpeta d'inici: l'usuari és `maria.prova`.
    let inici: String
    let projecte: String
    let sessions: URL
    let projectes: URL
    let claudeJSON: URL
    let ajustos: URL
    let configuracio: URL
    let appWarp: URL
    var lector: Lector
    let sessio = "0b2c4e6f-1a3b-4c5d-8e7f-9a0b1c2d3e4f"

    /// Tot com s'espera: Warp 0.2026.10.21 obert, amb un `claude` 2.1.317 al seu terminal i la transcripció al projecte de
    /// la seva carpeta, la restauració desactivada i el consentiment donat.
    init() throws {
        tmp = try CarpetaTemporal()
        inici = try tmp.carpeta("Users/maria.prova")
        projecte = try tmp.carpeta("Users/maria.prova/Feina/ClientSecret")
        sessions = URL(filePath: inici).appending(path: ".claude/sessions")
        projectes = URL(filePath: inici).appending(path: "claude-projectes")
        claudeJSON = URL(filePath: inici).appending(path: "claude-config.json")
        ajustos = URL(filePath: inici).appending(path: "ajustos-warp/settings.toml")
        configuracio = URL(filePath: inici).appending(path: "config-warp-launch")
        appWarp = tmp.url("Applications/Warp.app")

        let base = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
        try base.finestra(1)
        try base.pestanya(1, finestra: 1, titol: "A")
        try base.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("a"), cwd: projecte)

        var processos = ProcessosFalsos.ambWarp()
        processos.claude(101, argv: ["claude", "--dangerously-skip-permissions"], uuid: uuidDeProva("a"))
        try escriuSessio(a: sessions, pid: 101, sessionId: sessio, cwd: projecte)
        let app = appWarp
        lector = Lector(rutaWarp: base.url, rutaAjustos: ajustos, carpetaSessions: sessions, processos: processos,
                        warp: { InstallacioWarp(app: AppWarp(url: app), executable: ProcessosFalsos.executableWarp,
                                                hiHaStable: true) },
                        inici: inici)

        let transcripcio = projectes.appending(path: try #require(LectorTranscripcions.projecte(projecte)))
        try FileManager.default.createDirectory(at: transcripcio, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: transcripcio.appending(path: "\(sessio).jsonl"))

        try escriu(#"{"projects": {"\#(projecte)": {"hasTrustDialogAccepted": true}, "/tmp": {"hasTrustDialogAccepted": false}}}"#,
                   a: claudeJSON)
        try escriu("[general]\nrestore_session = false\n", a: ajustos)
        try FileManager.default.createDirectory(at: configuracio, withIntermediateDirectories: true)
        try MagatzemPreferencies(carpeta: configuracio).accepta(ara: Date(timeIntervalSince1970: 1_793_750_400))
        try appDeWarp(versio: "0.2026.10.21.08.25.02")
    }

    var processos: ProcessosFalsos {
        get { lector.processos as! ProcessosFalsos }
        set { lector.processos = newValue }
    }

    var entorn: EntornDiagnostic {
        EntornDiagnostic(lector: lector, carpetaConfiguracio: configuracio,
                         transcripcions: LectorTranscripcions(carpeta: projectes), confianca: LectorConfianca(ruta: claudeJSON),
                         sistema: "macOS de prova")
    }

    func diagnostic(anonimitza: Bool = false) -> InformeDiagnostic { Diagnostic.executa(entorn, anonimitza: anonimitza) }

    func comprovacio(_ id: Comprovacio.Id, anonimitza: Bool = false) throws -> Comprovacio {
        try #require(diagnostic(anonimitza: anonimitza).comprovacio(id))
    }

    /// El paquet de Warp: només l'`Info.plist`.
    func appDeWarp(versio: String) throws {
        let info: [String: Any] = ["CFBundleIdentifier": AppWarp.identificador, "CFBundleShortVersionString": versio,
                                   "CFBundleExecutable": "stable"]
        let dades = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: appWarp.appending(path: "Contents"), withIntermediateDirectories: true)
        try dades.write(to: appWarp.appending(path: "Contents/Info.plist"))
    }

    func escriu(_ text: String, a url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Canvia el `version` d'un fitxer de sessió.
    func versioDeClaude(_ versio: String, pid: Int32 = 101) throws {
        let fitxer = sessions.appending(path: "\(pid).json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fitxer)) as? [String: Any])
        json["version"] = versio
        try JSONSerialization.data(withJSONObject: json).write(to: fitxer)
    }
}

@Suite struct DiagnosticTests {
    @Test func ambTotComEsperaTotEsBe() throws {
        let mac = try MacDeProva()
        let informe = mac.diagnostic()
        #expect(informe.comprovacions.map(\.id) == Comprovacio.Id.allCases)
        for c in informe.comprovacions {
            #expect(c.resultat == .be, "\(c.id): \(c.detall)")
        }
        #expect(informe.compta(.be) == 8)
        #expect(informe.versio == "Warp Launch \(WarpLaunch.versio)")
        #expect(informe.text.hasPrefix("Warp Launch \(WarpLaunch.versio) diagnostic\nmacOS: macOS de prova\n"))
        #expect(informe.text.contains("[ok]      Warp terminals: Warp is open: 1 terminal of its terminal-server, 1 with "
            + "Claude; 1 claude process runs in Warp terminals"))
        #expect(informe.text.hasSuffix("Summary: 8 ok, 0 warnings, 0 errors.\n"))
        // Sense anonimitzar: les rutes tal com són.
        #expect(informe.text.contains(mac.sessions.path))
    }

    // MARK: - a) Terminals de Warp

    @Test func ambClaudeAWarpISenseCapTerminalReconegutEsUnError() throws {
        var mac = try MacDeProva()
        // Warp ha canviat el nom del seu servidor de terminals: els shells ja no se'n reconeixen.
        mac.processos.processos[50]?.info.argv = [ProcessosFalsos.executableWarp, "pty-host"]
        let c = try mac.comprovacio(.terminalsWarp)
        #expect(c.resultat == .error)
        #expect(c.detall.contains("Warp is open and 1 claude process runs in Warp terminals"))
        #expect(c.detall.contains("no terminal of Warp's terminal-server"))
    }

    @Test func ambClaudeAWarpIWarpTancatEsUnAvis() throws {
        var mac = try MacDeProva()
        // L'app de Warp ja no es veu oberta (un altre binari), però el `claude` porta el pane de Warp.
        mac.processos.processos[40] = nil
        let c = try mac.comprovacio(.terminalsWarp)
        #expect(c.resultat == .avis)
        #expect(c.detall.contains("isn't seen as open"))
    }

    @Test func elDimoniDeClaudeNoComptaComAUnTerminal() throws {
        var mac = try MacDeProva()
        mac.processos.processos[40] = nil
        mac.processos.processos[50] = nil
        mac.processos.processos[1101] = nil
        // El dimoni penja de launchd i la reserva, del dimoni: tots dos hereten el pane (docs/fets-verificats.md).
        let entorn = ["WARP_TERMINAL_SESSION_UUID": uuidDeProva("a")]
        mac.processos.processos[101] = (InfoProces(executable: "/x/claude", argv: ["claude", "daemon", "run"], entorn: entorn), 1)
        mac.processos.processos[102] = (InfoProces(executable: "/x/claude", argv: ["claude", "bg-spare"], entorn: entorn), 101)
        let c = try mac.comprovacio(.terminalsWarp)
        #expect(c.resultat == .be, "\(c.detall)")
        #expect(c.detall == "Warp isn't open, and no claude process runs in a Warp terminal.")
    }

    // MARK: - b) Fitxers de sessió

    @Test func capClaudeAmbFitxerDeSessioEsUnError() throws {
        let mac = try MacDeProva()
        try FileManager.default.removeItem(at: mac.sessions.appending(path: "101.json"))
        let c = try mac.comprovacio(.sessionsClaude)
        #expect(c.resultat == .error)
        #expect(c.detall.contains("None of the 1 claude process has a valid session file"))
        #expect(c.detall.contains("pid 101, options only"))
    }

    @Test func unClaudeSenseFitxerUnFitxerMalmesIUnKindDesconegutSonAvisos() throws {
        var mac = try MacDeProva()
        mac.processos.claude(102, argv: ["claude", "daemon", "run"], uuid: nil)
        mac.processos.claude(103, argv: ["claude", "--resume", "x"], uuid: uuidDeProva("b"))
        try escriuSessio(a: mac.sessions, pid: 103, sessionId: "s-103", cwd: mac.projecte, kind: "supervisor")
        try mac.escriu("{\"pid\": 104}", a: mac.sessions.appending(path: "104.json"))
        let c = try mac.comprovacio(.sessionsClaude)
        #expect(c.resultat == .avis)
        #expect(c.detall.contains("1 process has no valid session file (pid 102, «daemon»)"))
        #expect(c.detall.contains("1 file isn't a session file Warp Launch can read (104.json)"))
        #expect(c.detall.contains("1 session has an unknown kind (pid 103: supervisor; known: bg, daemon-worker, interactive)"))
    }

    @Test func senseCarpetaDeSessionsAmbClaudeEsUnError() throws {
        var mac = try MacDeProva()
        mac.lector.carpetaSessions = mac.tmp.url("no-hi-es")
        #expect(try mac.comprovacio(.sessionsClaude).resultat == .error)
        mac.processos.processos[101] = nil
        #expect(try mac.comprovacio(.sessionsClaude).resultat == .be)
    }

    // MARK: - c) Transcripcions

    @Test func senseCapTranscripcioEsUnAvis() throws {
        let mac = try MacDeProva()
        let projecte = mac.projectes.appending(path: try #require(LectorTranscripcions.projecte(mac.projecte)))
        try FileManager.default.removeItem(at: projecte.appending(path: "\(mac.sessio).jsonl"))
        try mac.escriu("{}", a: projecte.appending(path: "notes.txt"))
        let c = try mac.comprovacio(.transcripcions)
        #expect(c.resultat == .avis)
        #expect(c.detall.contains("No transcript (<id>.jsonl) in any of the 1 project folder of"))
    }

    @Test func lesTranscripcionsNomesEnUnAltreProjecteSonUnAvis() throws {
        let mac = try MacDeProva()
        // Claude anomena els projectes d'una altra manera: la transcripció hi és, però no on la busca l'app.
        let projecte = mac.projectes.appending(path: try #require(LectorTranscripcions.projecte(mac.projecte)))
        try FileManager.default.moveItem(at: projecte, to: mac.projectes.appending(path: "Feina_ClientSecret"))
        let c = try mac.comprovacio(.transcripcions)
        #expect(c.resultat == .avis)
        #expect(c.detall.contains("none of the 1 live session has its transcript in the project folder of its own folder"))
        try FileManager.default.removeItem(at: mac.projectes)
        #expect(try mac.comprovacio(.transcripcions).resultat == .avis)
    }

    // MARK: - d) La configuració de Claude Code

    @Test func unaConfiguracioDeClaudeQueNoEsLlegeixEsUnAvis() throws {
        let mac = try MacDeProva()
        #expect(try mac.comprovacio(.configuracioClaude).detall.hasSuffix(" 1 trusted."))
        for (text, esperat) in [("[]", "isn't a JSON object"), (#"{"projectes": {}}"#, "has no «projects»"),
                                (#"{"projects": {"/a": {"trusted": true}}}"#, "has «hasTrustDialogAccepted»")] {
            try mac.escriu(text, a: mac.claudeJSON)
            let c = try mac.comprovacio(.configuracioClaude)
            #expect(c.resultat == .avis, "\(text)")
            #expect(c.detall.contains(esperat), "\(c.detall)")
        }
        try FileManager.default.removeItem(at: mac.claudeJSON)
        #expect(try mac.comprovacio(.configuracioClaude).detall.contains("can't be read"))
    }

    // MARK: - e) warp.sqlite

    @Test func aLaBaseLiFaltaUnaColumnaOUnaTaula() throws {
        var mac = try MacDeProva()
        let base = try BaseWarpDeProva(a: mac.tmp.url("warp2.sqlite"), crea: false)
        try base.executa("""
            CREATE TABLE windows (id INTEGER PRIMARY KEY, active_tab_index INTEGER);
            CREATE TABLE tabs (id INTEGER PRIMARY KEY, window_id INTEGER, custom_title TEXT);
            CREATE TABLE pane_nodes (id INTEGER PRIMARY KEY, tab_id INTEGER, is_leaf BOOLEAN);
            CREATE TABLE pane_leaves (pane_node_id INTEGER, kind TEXT);
            """)
        mac.lector.rutaWarp = base.url
        let c = try mac.comprovacio(.baseWarp)
        #expect(c.resultat == .error)
        #expect(c.detall.contains("lacks tabs.color, terminal_panes."))
        // Només sense `blocks`: es llegeix, sense l'historial.
        try base.executa("""
            ALTER TABLE tabs ADD COLUMN color TEXT;
            CREATE TABLE terminal_panes (id INTEGER PRIMARY KEY, uuid BLOB, cwd TEXT);
            """)
        let opcional = try mac.comprovacio(.baseWarp)
        #expect(opcional.resultat == .avis)
        #expect(opcional.detall.contains("lacks blocks."))
    }

    @Test func senseBaseEsUnAvisISenseRestauracioNiConsentimentNoEsMira() throws {
        var mac = try MacDeProva()
        mac.lector.rutaWarp = mac.tmp.url("no-hi-es.sqlite")
        #expect(try mac.comprovacio(.baseWarp).resultat == .avis)
        // Warp no desa les finestres i l'app no les gestiona: la base no es mira.
        try FileManager.default.removeItem(at: mac.configuracio.appending(path: Preferencies.nomFitxer))
        let c = try mac.comprovacio(.baseWarp)
        #expect(c.resultat == .be)
        #expect(c.detall.hasPrefix("Not checked"))
    }

    /// L'esquema que mira el diagnòstic és tot el que llegeix `LectorWarp`: una base amb només aquestes columnes es llegeix.
    @Test func lEsquemaEsTotElQueLlegeixLectorWarp() throws {
        let tmp = try CarpetaTemporal()
        let base = try BaseWarpDeProva(a: tmp.url("minima.sqlite"), crea: false)
        for taula in LectorWarp.esquema {
            try base.executa("CREATE TABLE \(taula.nom) (\(taula.columnes.joined(separator: ", ")))")
        }
        try base.executa("""
            INSERT INTO windows VALUES (1, 0);
            INSERT INTO tabs VALUES (1, 1, 'A', NULL);
            INSERT INTO pane_nodes VALUES (10, 1, 1);
            INSERT INTO pane_leaves VALUES (10, 'terminal');
            INSERT INTO terminal_panes VALUES (10, x'\(uuidDeProva("a"))', '/tmp');
            INSERT INTO blocks VALUES (x'\(uuidDeProva("a"))', '/var', '2026-11-07');
            """)
        let finestres = try LectorWarp(ruta: base.url).llegeix()
        #expect(finestres.first?.pestanyes.first?.panes.first?.darrerPwd == "/var")
        let falta = try LectorWarp(ruta: base.url).queFalta()
        #expect(falta.obligatories.isEmpty && falta.opcionals.isEmpty)
    }

    // MARK: - f) Versions

    @Test func lesVersionsNoProvadesSonAvisos() throws {
        let mac = try MacDeProva()
        #expect(try mac.comprovacio(.versioWarp).detall.contains("Warp 0.2026.10.21.08.25.02, at "))
        try mac.appDeWarp(versio: "0.2026.11.04.08.17.01")
        let warp = try mac.comprovacio(.versioWarp)
        #expect(warp.resultat == .avis)
        #expect(warp.detall.contains("hasn't been tested with Warp Launch (tested: 0.2026.10.21)"))

        try mac.versioDeClaude("2.1.319")
        let claude = try mac.comprovacio(.versioClaude)
        #expect(claude.resultat == .avis)
        #expect(claude.detall.contains("Claude Code 2.1.319 (1 session), from the session files. Not tested with Warp "
            + "Launch: 2.1.319 (tested: 2.1.317–2.1.318)"))
        try mac.versioDeClaude("2.1.318")
        #expect(try mac.comprovacio(.versioClaude).resultat == .be)
    }

    @Test func senseWarpStableOSenseVersioDeClaude() throws {
        var mac = try MacDeProva()
        let app = mac.appWarp
        mac.lector.warp = { InstallacioWarp(app: AppWarp(url: app), executable: ProcessosFalsos.executableWarp,
                                            hiHaStable: false) }
        #expect(try mac.comprovacio(.versioWarp).detall == "Warp Stable isn't installed.")
        // Un fitxer de sessió sense `version`: Claude Code ha canviat el format.
        let fitxer = mac.sessions.appending(path: "101.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fitxer)) as? [String: Any])
        json["version"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: fitxer)
        #expect(try mac.comprovacio(.versioClaude).resultat == .avis)
    }

    @Test func elsRangsDeVersions() {
        let warp = RangVersions("0.2026.10.21")
        #expect(warp.conte("0.2026.10.21"))
        #expect(warp.conte("0.2026.10.21.08.25.02"))
        #expect(!warp.conte("0.2026.10.2"))
        #expect(!warp.conte("0.2026.11.04.08.17.01"))
        #expect(!warp.conte("0.2026.10"))
        let claude = RangVersions(desDe: "2.1.317", finsA: "2.1.318")
        #expect(claude.conte("2.1.317") && claude.conte("2.1.318"))
        #expect(!claude.conte("2.1.316") && !claude.conte("2.1.319") && !claude.conte("2.2.0") && !claude.conte("2.1.31x"))
        #expect(claude.description == "2.1.317–2.1.318")
        #expect(VersionsProvades.provada("2.1.317", VersionsProvades.claude))
        #expect(VersionsProvades.provada("0.2026.10.21.08.25.02", VersionsProvades.warp))
    }

    // MARK: - g) Restauració i consentiment

    @Test func laRestauracioActivadaOAmbUnaFormaEstranya() throws {
        let mac = try MacDeProva()
        #expect(try mac.comprovacio(.restauracio).detall.contains("Consent given on 2026-11-04."))
        try mac.escriu("[general]\nrestore_session = true\n", a: mac.ajustos)
        let activada = try mac.comprovacio(.restauracio)
        #expect(activada.resultat == .avis)
        #expect(activada.detall.hasPrefix("restore_session = true: after a restart"))
        // Dues línies: l'app no la tocaria.
        try mac.escriu("[general]\nrestore_session = true\n[altres]\nrestore_session = false\n", a: mac.ajustos)
        let estranya = try mac.comprovacio(.restauracio)
        #expect(estranya.resultat == .error)
        #expect(estranya.detall.contains("doesn't have the form Warp Launch expects"))
        try mac.escriu("[general]\n", a: mac.ajustos)
        #expect(try mac.comprovacio(.restauracio).detall.contains("has no restore_session"))
    }

    @Test func elConsentimentSenseDonarOIlegible() throws {
        let mac = try MacDeProva()
        let preferencies = mac.configuracio.appending(path: Preferencies.nomFitxer)
        try FileManager.default.removeItem(at: preferencies)
        let senseTriar = try mac.comprovacio(.restauracio)
        #expect(senseTriar.resultat == .avis)
        #expect(senseTriar.detall.contains("Consent not given yet"))
        try mac.escriu("{\"versio\": 1, \"restauracio\": {\"consentiment\": \"potser\"}}", a: preferencies)
        let malmes = try mac.comprovacio(.restauracio)
        #expect(malmes.resultat == .error)
        #expect(malmes.detall.contains("preferencies.json can't be read"))
    }

    // MARK: - Anonimització

    /// Cap ruta de casa, ni el nom d'usuari, ni el nom d'una carpeta: ni al text, ni al JSON, ni en un missatge d'error.
    @Test func lInformeAnonimitzatNoPortaResDeLUsuari() throws {
        var mac = try MacDeProva()
        // Un error amb una ruta a dins: `preferencies.json` és un enllaç trencat cap a una carpeta de l'usuari.
        let preferencies = mac.configuracio.appending(path: Preferencies.nomFitxer)
        try FileManager.default.removeItem(at: preferencies)
        try FileManager.default.createSymbolicLink(atPath: preferencies.path,
                                                   withDestinationPath: mac.projecte + "/maria.prova/preferencies.json")
        // Un claude sense fitxer, amb el que se li ha demanat com a primer argument, i Warp a la carpeta d'inici.
        mac.processos.claude(102, argv: ["claude", "Arregla el client de ClientSecret"], uuid: nil)
        let app = URL(filePath: mac.inici).appending(path: "Aplicacions Meves/Warp.app")
        try FileManager.default.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: mac.appWarp, to: app)
        mac.lector.warp = { InstallacioWarp(app: AppWarp(url: app), executable: ProcessosFalsos.executableWarp,
                                            hiHaStable: true) }

        let complet = mac.diagnostic()
        #expect(complet.text.contains(mac.inici) && complet.text.contains("ClientSecret"), "la prova ha de tenir què treure")
        let informe = mac.diagnostic(anonimitza: true)
        let json = String(decoding: try informe.json(), as: UTF8.self)
        for sortida in [informe.text, json] {
            for prohibit in [mac.inici, mac.tmp.ruta, "maria", "Maria", "ClientSecret", "Feina", "Aplicacions Meves",
                             "claude-projectes", "Arregla"] {
                #expect(!sortida.contains(prohibit), "«\(prohibit)» a:\n\(sortida)")
            }
        }
        #expect(informe.anonimitzat && json.contains(#""anonymized" : true"#))
        #expect(informe.text.contains("Anonymized: no user name"))
        // La forma es queda, i els noms que llegeix l'app també.
        #expect(informe.text.contains("~/.claude/sessions"))
        #expect(informe.text.contains("~/Aaaaaaaaaaa Aaaaa/Warp.app"))
        #expect(informe.text.contains("~/aaaaaa-aaaaaaaaa"))
        #expect(informe.text.contains("pid 102, other arguments"))
        let consentiment = try #require(informe.comprovacio(.restauracio)).detall
        #expect(consentiment.contains("«~/Aaaaa/AaaaaaAaaaaa/aaaaa.aaaaa/preferencies.json»"), "\(consentiment)")
    }

    @Test func laFormaDelsNoms() {
        let anon = Anonimitzador(inici: "/Users/joan", usuari: "joan", actiu: true)
        #expect(anon.forma("GitHub-Personal 2") == "AaaAaa-Aaaaaaaa 0")
        // Els altres caràcters ocupen el mateix en UTF-16 que els de debò.
        #expect(anon.forma("Cançó🎵") == "Aaa\u{E9}\u{E9}\u{1F642}")
        #expect(anon.forma("Cançó🎵").utf16.count == "Cançó🎵".utf16.count)
        #expect(anon.ruta("/Users/joan") == "~")
        #expect(anon.ruta("/Users/joan/.claude/sessions") == "~/.claude/sessions")
        #expect(anon.ruta("/Users/joanna/x") == "/Users/aaaaaa/a")
        #expect(anon.ruta("/Applications/Warp.app") == "/Applications/Warp.app")
        #expect(anon.text("a /Users/joan/x b; joan, joanet i Joan") == "a ~/a b; <user>, joanet i Joan")
        // Un punt al final és de la frase, no del nom.
        #expect(anon.text("a /Users/joan/.claude/sessions. B") == "a ~/.claude/sessions. B")
        let inactiu = Anonimitzador(inici: "/Users/joan", usuari: "joan", actiu: false)
        #expect(inactiu.text("/Users/joan/x joan") == "/Users/joan/x joan")
    }

    // MARK: - CLI

    @Test func elCLIAmbJSONIAnonimitzat() throws {
        let mac = try MacDeProva()
        let entorn = EntornCLI(lector: mac.lector, inici: mac.inici, carpetaReal: mac.configuracio,
                               transcripcions: LectorTranscripcions(carpeta: mac.projectes),
                               confianca: LectorConfianca(ruta: mac.claudeJSON), sistema: "macOS de prova")
        func executa(_ args: String...) -> (Int32, Sortida) {
            var sortida = Sortida()
            return (OrdreCLI.executa(args, entorn: entorn, sortida: &sortida), sortida)
        }

        let (codi, sortida) = executa("diagnostica", "--json")
        #expect(codi == 0)
        #expect(sortida.errors.isEmpty)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(sortida.text.utf8)) as? [String: Any])
        #expect(json["app"] as? String == "Warp Launch \(WarpLaunch.versio)")
        #expect(json["macOS"] as? String == "macOS de prova")
        #expect(json["anonymized"] as? Bool == false)
        let checks = try #require(json["checks"] as? [[String: Any]])
        #expect(checks.compactMap { $0["id"] as? String } == Comprovacio.Id.allCases.map(\.rawValue))
        #expect(checks.allSatisfy { $0["status"] as? String == "ok" && ($0["title"] as? String)?.isEmpty == false })
        #expect((json["summary"] as? [String: Int]) == ["ok": 8, "warnings": 0, "errors": 0])
        #expect(sortida.text.contains(mac.inici))

        let (codiAnonim, anonim) = executa("diagnostica", "--anonimitza", "--json")
        #expect(codiAnonim == 0)
        #expect(!anonim.text.contains(mac.inici) && !anonim.text.contains("maria"))
        #expect(anonim.text.contains(#""anonymized" : true"#))

        let (codiText, text) = executa("diagnostica")
        #expect(codiText == 0)
        #expect(text.text.hasPrefix("Warp Launch \(WarpLaunch.versio) diagnostic\n"))
        #expect(text.text.hasSuffix("Summary: 8 ok, 0 warnings, 0 errors.\n"))

        // Amb un error, surt amb 1; amb una opció desconeguda, 64.
        try mac.escriu("[general]\nrestore_session = maybe\n", a: mac.ajustos)
        #expect(executa("diagnostica").0 == OrdreCLI.Codi.fallida)
        let (codiUs, us) = executa("diagnostica", "--desa")
        #expect(codiUs == OrdreCLI.Codi.us)
        #expect(us.errors.contains("opció desconeguda per a diagnostica: «--desa»"))
        #expect(OrdreCLI.ajuda.contains("warp-launch diagnostica [--json] [--anonimitza]"))
    }

    /// El diagnòstic només llegeix: no escriu cap fitxer, tampoc `preferencies.json` (la carpeta queda com era).
    @Test func elDiagnosticNoEscriuRes() throws {
        let mac = try MacDeProva()
        try FileManager.default.removeItem(at: mac.configuracio.appending(path: Preferencies.nomFitxer))
        func contingut() throws -> [String: Data] {
            let enumerador = try #require(FileManager.default.enumerator(atPath: mac.tmp.ruta))
            var fitxers: [String: Data] = [:]
            while let ruta = enumerador.nextObject() as? String {
                let url = mac.tmp.url(ruta)
                var esCarpeta: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta), !esCarpeta.boolValue {
                    fitxers[ruta] = try Data(contentsOf: url)
                }
            }
            return fitxers
        }
        let abans = try contingut()
        _ = mac.diagnostic()
        _ = mac.diagnostic(anonimitza: true)
        #expect(try contingut() == abans)
    }
}
