import Foundation
import SQLite3
import Testing
@testable import WarpLaunchCore

@Suite("Lectura de warp.sqlite")
struct LectorWarpTests {
    /// Dues finestres. La primera té una pestanya normal, una de Settings i una dividida en dos panes.
    static func baseHabitual(a url: URL, wal: Bool = false) throws -> BaseWarpDeProva {
        let base = try BaseWarpDeProva(a: url, wal: wal)
        try base.finestra(1, pestanyaActiva: 2)
        try base.finestra(2)
        try base.pestanya(1, finestra: 1, titol: "Agent A", color: "---\nColor: blue\n")
        try base.pestanya(2, finestra: 1)
        try base.pestanya(3, finestra: 1, titol: "Dividida")
        try base.pestanya(4, finestra: 2)
        try base.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("a"), cwd: "/tmp/a")
        try base.paneSettings(20, pestanya: 2)
        try base.nodeArrel(30, pestanya: 3)
        try base.paneTerminal(31, pestanya: 3, uuid: uuidDeProva("b"), cwd: "/tmp/b", pare: 30)
        try base.paneTerminal(32, pestanya: 3, uuid: uuidDeProva("c"), cwd: "/tmp/c", pare: 30)
        try base.paneTerminal(40, pestanya: 4, uuid: uuidDeProva("d"), cwd: nil)
        return base
    }

    @Test func finestresPestanyesIPanesEnOrdre() throws {
        let tmp = try CarpetaTemporal()
        let base = try Self.baseHabitual(a: tmp.url("warp.sqlite"))
        let finestres = try LectorWarp(ruta: base.url).llegeix()

        #expect(finestres.map(\.numero) == [1, 2])
        #expect(finestres[0].pestanyaActiva == 2)
        // La pestanya de Settings no hi és, però compta per a les posicions.
        #expect(finestres[0].pestanyes.map(\.posicio) == [0, 2])
        #expect(finestres[0].pestanyes[0].titol == "Agent A")
        #expect(finestres[0].pestanyes[0].color == "---\nColor: blue\n")
        #expect(finestres[0].pestanyes[0].panes == [PaneWarp(uuid: uuidDeProva("a"), cwd: "/tmp/a", darrerPwd: nil)])
        #expect(finestres[0].pestanyes[1].panes.map(\.uuid) == [uuidDeProva("b"), uuidDeProva("c")])
        #expect(finestres[1].pestanyes.count == 1)
        #expect(finestres[1].pestanyes[0].titol == nil)
        #expect(finestres[1].pestanyes[0].panes[0].cwd == nil)
    }

    @Test func lUUIDSurtEnHexadecimalMinuscula() throws {
        let tmp = try CarpetaTemporal()
        let base = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
        try base.finestra(1)
        try base.pestanya(1, finestra: 1)
        try base.paneTerminal(10, pestanya: 1, uuid: "D63AF59EBD1B4FF992C6396504D4C593", cwd: "/tmp")
        let uuid = try LectorWarp(ruta: base.url).llegeix()[0].pestanyes[0].panes[0].uuid
        #expect(uuid == "d63af59ebd1b4ff992c6396504d4c593")
    }

    @Test func darreraCarpetaDeLHistorial() throws {
        let tmp = try CarpetaTemporal()
        let base = try Self.baseHabitual(a: tmp.url("warp.sqlite"))
        try base.bloc(uuid: uuidDeProva("d"), pwd: "/tmp/antiga", hora: "2026-10-30 09:00:00.000000")
        try base.bloc(uuid: uuidDeProva("d"), pwd: "/tmp/recent", hora: "2026-11-02 18:00:00.000000")
        try base.bloc(uuid: uuidDeProva("d"), pwd: "", hora: "2026-11-03 08:00:00.000000")
        let pane = try LectorWarp(ruta: base.url).llegeix()[1].pestanyes[0].panes[0]
        #expect(pane.darrerPwd == "/tmp/recent")
    }

    @Test func llegeixMentreUnAltreEscriuEnModeWAL() throws {
        let tmp = try CarpetaTemporal()
        // La connexió d'escriptura queda oberta durant la lectura, com fa Warp.
        let base = try Self.baseHabitual(a: tmp.url("warp.sqlite"), wal: true)
        #expect(try LectorWarp(ruta: base.url).llegeix().count == 2)
        try base.finestra(3)
        #expect(try LectorWarp(ruta: base.url).llegeix().count == 3)
    }

    @Test func llegeixUnaBaseWALAmbWarpTancat() throws {
        let tmp = try CarpetaTemporal()
        // L'SQLite de macOS conserva -wal i -shm en tancar l'última connexió (WAL persistent).
        do { _ = try Self.baseHabitual(a: tmp.url("warp.sqlite"), wal: true) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.ruta).sorted()
                == ["warp.sqlite", "warp.sqlite-shm", "warp.sqlite-wal"])
        #expect(try LectorWarp(ruta: tmp.url("warp.sqlite")).llegeix().count == 2)
    }

    @Test func llegeixUnaBaseWALSenseFitxersAuxiliars() throws {
        let tmp = try CarpetaTemporal()
        do { _ = try Self.baseHabitual(a: tmp.url("warp.sqlite"), wal: true) }
        try FileManager.default.removeItem(at: tmp.url("warp.sqlite-wal"))
        try FileManager.default.removeItem(at: tmp.url("warp.sqlite-shm"))
        #expect(try LectorWarp(ruta: tmp.url("warp.sqlite")).llegeix().count == 2)
        // Ni torna a crear els fitxers auxiliars.
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.ruta) == ["warp.sqlite"])
    }

    @Test func llegeixUnaRutaAmbEspais() throws {
        // La ruta real és a «Group Containers/…/Application Support/»: amb espais.
        let tmp = try CarpetaTemporal()
        let carpeta = try tmp.carpeta("Group Containers/Application Support")
        do { _ = try Self.baseHabitual(a: URL(filePath: carpeta + "/warp.sqlite"), wal: true) }
        try FileManager.default.removeItem(atPath: carpeta + "/warp.sqlite-shm")
        #expect(try LectorWarp(ruta: URL(filePath: carpeta + "/warp.sqlite")).llegeix().count == 2)
    }

    @Test func noModificaLaBase() throws {
        let tmp = try CarpetaTemporal()
        let base = try Self.baseHabitual(a: tmp.url("warp.sqlite"))
        let abans = try FileManager.default.attributesOfItem(atPath: base.url.path)
        _ = try LectorWarp(ruta: base.url).llegeix()
        let despres = try FileManager.default.attributesOfItem(atPath: base.url.path)
        #expect(abans[.modificationDate] as? Date == despres[.modificationDate] as? Date)
        #expect(abans[.size] as? Int == despres[.size] as? Int)
        // Ni crea fitxers de diari al costat.
        let fitxers = try FileManager.default.contentsOfDirectory(atPath: tmp.ruta)
        #expect(fitxers == ["warp.sqlite"])
    }

    @Test func senseBaseDonaUnErrorClar() throws {
        let tmp = try CarpetaTemporal()
        #expect(throws: ErrorLectura.noHiHaBase(tmp.url("no-hi-es.sqlite").path)) {
            try LectorWarp(ruta: tmp.url("no-hi-es.sqlite")).llegeix()
        }
    }

    @Test func siMacOSNoDeixaLlegirHoDiu() {
        // A la prova 1, macOS 27 va bloquejar l'app sense preguntar: `open()` → EPERM → SQLITE_AUTH (23),
        // «authorization denied». L'error ha de dir què cal fer.
        let error = ErrorLectura.de(codi: SQLITE_AUTH, missatge: "authorization denied")
        #expect(error == .macOSNoDeixaLlegir)
        #expect(error.description.contains("Privacitat i seguretat"))
        #expect(ErrorLectura.de(codi: SQLITE_CANTOPEN, missatge: "unable to open database file")
            == .sqlite("unable to open database file"))
        #expect(ErrorLectura.de(codi: SQLITE_BUSY, missatge: "database is locked") == .sqlite("database is locked"))
    }

    @Test func senseTaulaDHistorialTambeLlegeix() throws {
        let tmp = try CarpetaTemporal()
        let base = try Self.baseHabitual(a: tmp.url("warp.sqlite"))
        try base.executa("DROP TABLE blocks")
        let finestres = try LectorWarp(ruta: base.url).llegeix()
        #expect(finestres[1].pestanyes[0].panes[0].darrerPwd == nil)
    }
}
