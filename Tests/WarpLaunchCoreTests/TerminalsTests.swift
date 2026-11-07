import Foundation
import Testing
@testable import WarpLaunchCore

// Saber què hi ha obert a Warp sense la seva base: l'ajust de la restauració de sessió i els terminals vius (0.22.0). Tot amb
// processos inventats i carpetes temporals.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

@Suite struct LectorAjustosWarpTests {
    @Test(arguments: [
        ("[general]\nrestore_session = false\n", false),
        ("[general]\nrestore_session = true\n", true),
        ("[general]\nlogin_item = false\n", true),
        ("", true),
        ("[altra]\nrestore_session = false\n", true),
        ("restore_session = false\n", true),
        ("# [general]\n# restore_session = false\n", true),
        ("[general]\n  restore_session=false  # un comentari\n", false),
        ("general.restore_session = false\n", false),
        ("[appearance.tema]\nx = 1\n\n[general]\nrestore_session = false\n[terminal]\ny = 2\n", false),
        ("[general]\nrestore_session = false\n[terminal]\nrestore_session = true\n", false),
    ])
    func llegeixLaClau(toml: String, desa: Bool) {
        #expect(LectorAjustosWarp.desaFinestres(toml: toml) == desa)
    }

    @Test func senseFitxerEsElValorPerDefecteDeWarp() throws {
        let tmp = try CarpetaTemporal()
        #expect(LectorAjustosWarp(ruta: tmp.url("no-hi-es.toml")).desaFinestres())
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        #expect(!LectorAjustosWarp(ruta: tmp.url("settings.toml")).desaFinestres())
    }
}

@Suite struct TerminalsDeWarpTests {
    /// La forma real (05/11/2026, `ps` i `KERN_PROCARGS2`): els shells pengen del `terminal-server`, sense entorn, i el pane i
    /// la marca surten dels seus fills.
    @Test func elsFillsDelTerminalServer() {
        var p = ProcessosFalsos.ambWarp()
        p.claude(101, argv: ["claude", "--resume", "x"], uuid: uuidDeProva("A"),
                 entorn: [OrdreClaude.variableMarca: id(1).uuidString])
        p.carpetes[1101] = "/x/t1"
        // Un shell sense fills: se'n sap la carpeta, i prou.
        p.processos[200] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 50)
        p.carpetes[200] = "/x/t2"
        // Un shell amb un altre programa, que porta el pane.
        p.processos[300] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 50)
        p.processos[301] = (InfoProces(executable: "/usr/bin/vim", argv: ["vim"],
                                       entorn: ["WARP_TERMINAL_SESSION_UUID": uuidDeProva("b")]), 300)
        // Un Claude de Terminal, i un net del shell amb una marca: no són de Warp, o no diuen res d'aquest terminal.
        p.claude(102, argv: ["claude"], uuid: nil, dinsDeWarp: false, entorn: [OrdreClaude.variableMarca: id(2).uuidString])
        p.processos[302] = (InfoProces(executable: "/bin/sh", argv: ["sh"], entorn: [OrdreClaude.variableMarca: id(3).uuidString]), 301)

        #expect(p.terminalsDeWarp(executable: ProcessosFalsos.executableWarp) == [
            TerminalViu(pid: 200, carpeta: "/x/t2"),
            TerminalViu(pid: 300, pane: uuidDeProva("b")),
            TerminalViu(pid: 1101, carpeta: "/x/t1", pane: uuidDeProva("a"), marca: id(1), claude: true, conversa: "x"),
        ])
    }

    /// Sense Warp no n'hi ha cap; ni són de Warp els d'un altre programa que es digui igual.
    @Test func nomesElsDelTerminalServerDeWarp() {
        #expect(ProcessosFalsos().terminalsDeWarp(executable: ProcessosFalsos.executableWarp).isEmpty)
        var p = ProcessosFalsos()
        p.processos[50] = (InfoProces(executable: "/tmp/stable", argv: ["/tmp/stable", "terminal-server"]), 1)
        p.processos[51] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 50)
        #expect(p.terminalsDeWarp(executable: ProcessosFalsos.executableWarp).isEmpty)
        // L'app de Warp no és el seu `terminal-server`: un procés que pengi de l'app no és cap terminal.
        var q = ProcessosFalsos.ambWarp()
        q.processos[41] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 40)
        #expect(q.terminalsDeWarp(executable: ProcessosFalsos.executableWarp).isEmpty)
    }

    /// Una marca que no és un UUID no és cap marca.
    @Test func unaMarcaEstranyaNoCompta() {
        var p = ProcessosFalsos.ambWarp()
        p.claude(101, argv: ["claude"], uuid: nil, entorn: [OrdreClaude.variableMarca: "no-es-un-uuid"])
        #expect(p.terminalsDeWarp(executable: ProcessosFalsos.executableWarp) == [TerminalViu(pid: 1101, claude: true)])
    }
}

@Suite("La lectura amb la restauració de sessió desactivada")
struct LecturaSenseFinestresTests {
    private struct Escenari {
        let tmp: CarpetaTemporal
        let lector: Lector
        let sessions: URL

        init(ajustos: String?, base: Bool = true) throws {
            tmp = try CarpetaTemporal()
            let inici = try tmp.carpeta("inici")
            let a = try tmp.carpeta("inici/a")
            if base {
                let warp = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
                try warp.finestra(1)
                try warp.pestanya(1, finestra: 1, titol: "D'abans")
                try warp.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("c"), cwd: a)
            }
            if let ajustos { try Data(ajustos.utf8).write(to: tmp.url("settings.toml")) }
            sessions = tmp.url("sessions")
            var processos = ProcessosFalsos.ambWarp()
            try escriuSessio(a: sessions, pid: 101, sessionId: "s-101", cwd: a)
            processos.claude(101, argv: ["claude"], uuid: uuidDeProva("c"), entorn: [OrdreClaude.variableMarca: id(1).uuidString])
            processos.carpetes[1101] = a
            lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"), carpetaSessions: sessions,
                            processos: processos, warp: { .perOmissio }, inici: inici)
        }
    }

    /// El que hi ha a la base és d'abans: no surt, encara que un pane coincideixi, i les sessions queden sense pestanya.
    @Test func noEsFiaDeLaBase() throws {
        let e = try Escenari(ajustos: "[general]\nrestore_session = false\n")
        let lectura = try e.lector.llegeix()
        #expect(lectura.warpDesaFinestres == false)
        #expect(lectura.finestres.isEmpty)
        #expect(lectura.sessionsSensePestanya.map(\.sessionId) == ["s-101"])
        #expect(lectura.terminals.map(\.pane) == [uuidDeProva("c")])
        #expect(lectura.terminals.map(\.marca) == [id(1)])
        #expect(ResumWarp(lectura).descripcio == "Warp: 1 terminal · 1 sessió de Claude")
    }

    /// D19: `.sempre` llegeix la foto encara que l'ajust digui que no desa, i `.mai` no se'n fia encara que digui que sí.
    @Test func elModeDeLaBaseManaSobreLAjust() throws {
        let desactivat = try Escenari(ajustos: "[general]\nrestore_session = false\n")
        let foto = try desactivat.lector.llegeix(base: .sempre)
        #expect(foto.warpDesaFinestres == true)
        #expect(foto.finestres.count == 1)

        let activat = try Escenari(ajustos: "[general]\nrestore_session = true\n")
        let enRefresc = try activat.lector.llegeix(base: .mai)
        #expect(enRefresc.warpDesaFinestres == false)
        #expect(enRefresc.finestres.isEmpty)
    }

    /// Ni tan sols la fa servir: sense la base (o sense permís per llegir-la), es pot llegir igualment.
    @Test func noNecessitaLaBase() throws {
        let e = try Escenari(ajustos: "[general]\nrestore_session = false\n", base: false)
        #expect(try e.lector.llegeix().terminals.count == 1)
    }

    /// Amb la restauració activada, o sense ajust, tot és com abans, i també hi ha els terminals.
    @Test(arguments: ["[general]\nrestore_session = true\n", nil] as [String?])
    func ambLaRestauracioActivadaEsLlegeixLaBase(ajustos: String?) throws {
        let e = try Escenari(ajustos: ajustos)
        let lectura = try e.lector.llegeix()
        #expect(lectura.warpDesaFinestres == true)
        #expect(lectura.finestres.count == 1)
        #expect(lectura.sessionsSensePestanya.isEmpty)
        #expect(lectura.terminals.count == 1)
        #expect(ResumWarp(lectura).descripcio == "Warp: 1 finestra · 1 pestanya · 1 sessió de Claude")
    }

    /// `warp-launch llegeix` ho explica, i llista els terminals.
    @Test func lInformeHoDiu() throws {
        let e = try Escenari(ajustos: "[general]\nrestore_session = false\n")
        let text = Informe.text(try e.lector.llegeix(), inici: e.tmp.url("inici").path)
        #expect(text.contains("Warp: 1 terminal viu, 1 amb Claude."))
        #expect(text.contains("Warp no desa les finestres"))
        #expect(text.contains("Terminals:"))
        #expect(!text.contains("base de Warp"), "no ha de dir que la pestanya no és a la base")
    }
}
