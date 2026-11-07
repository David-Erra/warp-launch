import Foundation
import Testing
@testable import WarpLaunchCore

@Suite("Lectura completa: Warp més sessions de Claude")
struct LectorTests {
    /// Escenari: Warp amb dues finestres i quatre panes, i set fitxers de sessió de tota mena.
    struct Escenari {
        let tmp: CarpetaTemporal
        let inici: String
        let projecteA: String
        let projecteB: String
        let lector: Lector

        init(modifica: (inout ProcessosFalsos, URL) throws -> Void = { _, _ in }) throws {
            tmp = try CarpetaTemporal()
            inici = try tmp.carpeta("inici")
            projecteA = try tmp.carpeta("inici/GitHub/projecte-a")
            projecteB = try tmp.carpeta("inici/GitHub/projecte-b")
            let historial = try tmp.carpeta("inici/GitHub/historial")

            let base = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
            try base.finestra(1)
            try base.finestra(2)
            try base.pestanya(1, finestra: 1, titol: "Projecte A")
            try base.pestanya(2, finestra: 1, titol: "Projecte B")
            try base.pestanya(3, finestra: 2, titol: "Restaurada")
            try base.pestanya(4, finestra: 2)
            // Warp desa la ruta tal com es va escriure: amb barres repetides i sense canonicalitzar.
            try base.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("a"), cwd: projecteA.replacingOccurrences(of: "/GitHub/", with: "//GitHub/"))
            try base.paneTerminal(20, pestanya: 2, uuid: uuidDeProva("b"), cwd: projecteB)
            try base.paneTerminal(30, pestanya: 3, uuid: uuidDeProva("c"), cwd: inici)
            try base.paneTerminal(40, pestanya: 4, uuid: uuidDeProva("d"), cwd: inici)
            try base.bloc(uuid: uuidDeProva("c"), pwd: historial, hora: "2026-11-02 18:00:00.000000")

            let sessions = tmp.url("sessions")
            var processos = ProcessosFalsos.ambWarp()
            // 101: sessió habitual a la pestanya A (l'UUID de l'entorn ve en majúscula).
            try escriuSessio(a: sessions, pid: 101, sessionId: "s-101", cwd: projecteA, nom: "projecte-a")
            processos.claude(101, argv: ["claude", "--dangerously-skip-permissions", "--effort", "ultracode"],
                             uuid: uuidDeProva("A"))
            // 102: dimoni en segon pla amb el mateix UUID: s'ignora.
            try escriuSessio(a: sessions, pid: 102, sessionId: "s-102", cwd: projecteB, kind: "bg")
            processos.claude(102, argv: ["claude", "bg-spare"], uuid: uuidDeProva("a"))
            // 103: sessió interactiva fora de Warp (Terminal).
            try escriuSessio(a: sessions, pid: 103, sessionId: "s-103", cwd: projecteB)
            processos.claude(103, argv: ["claude"], uuid: nil, dinsDeWarp: false)
            // 104: el procés ja no existeix.
            try escriuSessio(a: sessions, pid: 104, sessionId: "s-104", cwd: projecteB)
            // 105: el pid ara és un altre programa.
            try escriuSessio(a: sessions, pid: 105, sessionId: "s-105", cwd: projecteB)
            processos.processos[105] = (InfoProces(executable: "/usr/bin/python3", argv: ["python3"]), 1)
            // 106: dins de Warp, però la seva pestanya no és a la base (encara no s'ha desat o s'acaba de tancar).
            try escriuSessio(a: sessions, pid: 106, sessionId: "s-106", cwd: projecteB)
            processos.claude(106, argv: ["claude", "-c"], uuid: uuidDeProva("e"))
            // Un fitxer trencat.
            try Data("{no és json".utf8).write(to: sessions.appending(path: "107.json"))

            try modifica(&processos, sessions)
            lector = Lector(rutaWarp: base.url, rutaAjustos: tmp.url("settings.toml"), carpetaSessions: sessions,
                            processos: processos, warp: { .perOmissio }, inici: inici)
        }
    }

    @Test func lligaLaSessioAmbLaSevaPestanya() throws {
        let e = try Escenari()
        let lectura = try e.lector.llegeix()
        let pane = lectura.finestres[0].pestanyes[0].panes[0]
        #expect(pane.carpeta == e.projecteA)
        #expect(pane.origenCarpeta == .pane)
        let claude = try #require(pane.claude)
        #expect(claude.pid == 101)
        #expect(claude.nom == "projecte-a")
        #expect(claude.carpeta == e.projecteA)
        #expect(claude.paneUUID == uuidDeProva("a"))
        #expect(claude.dinsDeWarp)
        #expect(claude.opcions == OpcionsClaude(esforc: "ultracode", ultracode: true, saltaPermisos: true))
        #expect(lectura.finestres[0].pestanyes[1].panes[0].claude == nil)
    }

    @Test func carpetaDeLHistorialQuanElPaneEsALInici() throws {
        let e = try Escenari()
        let lectura = try e.lector.llegeix()
        let restaurada = lectura.finestres[1].pestanyes[0].panes[0]
        #expect(restaurada.carpeta == e.tmp.ruta + "/inici/GitHub/historial")
        #expect(restaurada.origenCarpeta == .historial)
        // Sense historial, es queda a l'inici.
        let senseHistorial = lectura.finestres[1].pestanyes[1].panes[0]
        #expect(senseHistorial.carpeta == e.inici)
        #expect(senseHistorial.origenCarpeta == .pane)
    }

    @Test func sessionsSensePestanyaIAvisos() throws {
        let lectura = try Escenari().lector.llegeix()
        #expect(lectura.sessionsSensePestanya.map(\.pid) == [103, 106])
        #expect(lectura.sessionsSensePestanya.map(\.dinsDeWarp) == [false, true])
        #expect(lectura.avisos.count == 3)
        #expect(lectura.avisos.contains { $0.contains("104") && $0.contains("ja no existeix") })
        #expect(lectura.avisos.contains { $0.contains("105") && $0.contains("python3") })
        #expect(lectura.avisos.contains { $0.contains("107.json") })
    }

    @Test func duesSessionsAlMateixPaneEsQuedaLaMesRecent() throws {
        let e = try Escenari { processos, sessions in
            try escriuSessio(a: sessions, pid: 201, sessionId: "s-201", cwd: "/tmp", iniciadaMs: 1_793_700_000_000)
            processos.claude(201, argv: ["claude"], uuid: uuidDeProva("b"))
            try escriuSessio(a: sessions, pid: 202, sessionId: "s-202", cwd: "/tmp", iniciadaMs: 1_793_700_500_000)
            processos.claude(202, argv: ["claude", "--resume", "x"], uuid: uuidDeProva("b"))
        }
        let lectura = try e.lector.llegeix()
        #expect(lectura.finestres[0].pestanyes[1].panes[0].claude?.pid == 202)
        #expect(lectura.avisos.contains { $0.contains("dues sessions") && $0.contains("202") })
        // La que no es mostra no queda amagada: surt entre les sessions sense pestanya.
        #expect(lectura.sessionsSensePestanya.map(\.pid).contains(201))
    }

    @Test func senseCarpetaDeSessionsLlegeixWarpIAvisa() throws {
        let e = try Escenari()
        var lector = e.lector
        lector.carpetaSessions = e.tmp.url("no-hi-es")
        let lectura = try lector.llegeix()
        #expect(lectura.finestres.flatMap(\.pestanyes).count == 4)
        #expect(lectura.avisos.count == 1)
    }

    @Test func carpetaQueJaNoExisteix() throws {
        // L'historial apunta a un repo que s'ha mogut: la ruta es manté, però es marca.
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        let base = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
        try base.finestra(1)
        try base.pestanya(1, finestra: 1, titol: "Web")
        try base.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("a"), cwd: inici)
        try base.bloc(uuid: uuidDeProva("a"), pwd: inici + "/GitHub/web-moguda", hora: "2026-11-01 10:00:00.000000")
        let lector = Lector(rutaWarp: base.url, rutaAjustos: tmp.url("settings.toml"), carpetaSessions: tmp.url("sessions"),
                            processos: ProcessosFalsos(), warp: { .perOmissio }, inici: inici)
        let lectura = try lector.llegeix()
        let pane = lectura.finestres[0].pestanyes[0].panes[0]
        #expect(pane.carpeta == inici + "/GitHub/web-moguda")
        #expect(pane.origenCarpeta == .historial)
        #expect(!pane.carpetaExisteix)
        let text = Informe.text(lectura, inici: inici)
        #expect(text.contains("Web · ~/GitHub/web-moguda (historial, no existeix)"))
        #expect(text.contains("Carpetes: 1 recuperades de l'historial, 1 que ja no existeixen, 0 a la carpeta d'inici"))
    }

    @Test func lesCarpetesQueExisteixenNoEsMarquen() throws {
        let lectura = try Escenari().lector.llegeix()
        let panes = lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes)
        #expect(panes.allSatisfy { $0.carpetaExisteix })
    }

    @Test func informeLlegible() throws {
        let e = try Escenari()
        let text = Informe.text(try e.lector.llegeix(), inici: e.inici)
        #expect(text.contains("Warp: 2 finestres, 4 pestanyes de terminal, 1 amb Claude"))
        #expect(text.contains("Projecte A · ~/GitHub/projecte-a"))
        #expect(text.contains("claude --dangerously-skip-permissions --effort ultracode  [projecte-a · pid 101 · idle]"))
        #expect(text.contains("Restaurada · ~/GitHub/historial (historial)"))
        #expect(text.contains("fora de Warp"))
    }

    @Test func cometesNomesOnCalen() {
        #expect(Informe.ordre(["/opt/bin/claude", "--remote-control", "Agent web", "--settings", #"{"ultracode":true}"#])
                == #"claude --remote-control 'Agent web' --settings '{"ultracode":true}'"#)
        #expect(Informe.ordre(["claude", "-n", "l'agent"]) == #"claude -n 'l'\''agent'"#)
    }
}
