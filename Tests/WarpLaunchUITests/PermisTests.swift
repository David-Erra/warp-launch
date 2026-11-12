import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

/// Decisió 8 de l'autor (0.36.0): quan macOS no deixa llegir les dades de Warp, «Obre la configuració del sistema» (el menú de
/// la icona i el full d'importar) obre la pàgina del permís. Aquí, per una crida falsa: cap prova no obre Configuració del Sistema
/// (la crida de debò només la connecta l'app, i la guarda no deixa que cap prova hi arribi).
@MainActor
@Suite struct PermisTests {
    private final class Crides {
        var n = 0
    }

    /// Carpeta temporal per a la configuració. S'esborra en acabar.
    private final class Temporal {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-permis-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        var magatzem: MagatzemConfiguracio { MagatzemConfiguracio(carpeta: url.appending(path: "config"), inici: "/Users/prova") }
    }

    nonisolated private static let buida = LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: [])

    /// Una lectura que falla pel permís mentre `falla` és cert.
    private static func warp(_ falla: Bandera) -> EstatWarp {
        EstatWarp(lector: {
            if falla.valor { throw ErrorLectura.macOSNoDeixaLlegir }
            return buida
        })
    }

    /// Es decideix pel cas de l'error del Core, no pel text, que és traduït.
    @Test func lErrorDelPermisEsDiuPelCas() {
        #expect(EstatWarp.ErrorLectura(ErrorLectura.macOSNoDeixaLlegir).calPermis)
        #expect(EstatWarp.ErrorLectura(ErrorLectura.macOSNoDeixaLlegir).description == ErrorLectura.macOSNoDeixaLlegir.description)
        #expect(!EstatWarp.ErrorLectura(ErrorLectura.sqlite("database is locked")).calPermis)
        #expect(!EstatWarp.ErrorLectura(ErrorLectura.noHiHaBase("/tmp/warp.sqlite")).calPermis)
        #expect(!EstatWarp.ErrorLectura(description: "sense permís").calPermis)
        Idioma.$deProva.withValue("en") {
            #expect(EstatWarp.ErrorLectura(ErrorLectura.macOSNoDeixaLlegir).calPermis)
        }
    }

    /// El menú de la icona: el botó, només després d'una lectura que falla pel permís, i fins a la lectura següent. El clic crida
    /// la pàgina una vegada; sense el botó, res.
    @Test func elMenuOfereixLaPaginaNomesSenseElPermis() async {
        let falla = Bandera(true)
        let warp = Self.warp(falla)
        let crides = Crides()
        warp.obrePaginaPermis = { crides.n += 1 }
        #expect(!warp.potObrirPermis)
        warp.obrePermis()
        #expect(crides.n == 0, "abans de llegir")

        await warp.llegeix()
        #expect(warp.calPermis && warp.potObrirPermis)
        warp.obrePermis()
        #expect(crides.n == 1)

        // Donat el permís, la lectura següent el treu.
        falla.valor = false
        await warp.llegeix()
        #expect(!warp.calPermis && !warp.potObrirPermis)
        warp.obrePermis()
        #expect(crides.n == 1)
    }

    /// Un altre error no és el del permís: cap botó.
    @Test func unAltreErrorNoOfereixLaPagina() async {
        let warp = EstatWarp(lector: { throw ErrorLectura.sqlite("database is locked") })
        let crides = Crides()
        warp.obrePaginaPermis = { crides.n += 1 }
        await warp.llegeix()
        #expect(!warp.calPermis && !warp.potObrirPermis)
        warp.obrePermis()
        #expect(crides.n == 0)
    }

    /// Sense la crida (només la hi posa l'app), cap botó, tampoc sense el permís.
    @Test func senseLaCridaCapBoto() async {
        let warp = Self.warp(Bandera(true))
        await warp.llegeix()
        #expect(warp.calPermis && !warp.potObrirPermis)
        warp.obrePermis()
    }

    /// El full d'importar: amb l'error del permís, el botó; amb «Torna-ho a provar», ja amb el permís, se'n va.
    @Test func elFullDImportarOfereixLaPagina() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        let falla = Bandera(true)
        let warp = Self.warp(falla)
        let crides = Crides()
        warp.obrePaginaPermis = { crides.n += 1 }
        let full = try #require(FullImportacio(editor: editor, warp: warp))
        #expect(!full.potObrirPermis)

        await full.llegeix()
        guard case .error = full.estat else {
            Issue.record("havia de fallar: \(full.estat)")
            return
        }
        #expect(full.potObrirPermis)
        full.obrePermis()
        #expect(crides.n == 1)

        falla.valor = false
        await full.llegeix()
        #expect(!full.potObrirPermis)
        full.obrePermis()
        #expect(crides.n == 1)
    }

    /// Un altre error al full: cap botó.
    @Test func elFullDImportarAmbUnAltreErrorNoLOfereix() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        let warp = EstatWarp(lector: { throw ErrorLectura.sqlite("database is locked") })
        let crides = Crides()
        warp.obrePaginaPermis = { crides.n += 1 }
        let full = try #require(FullImportacio(editor: editor, warp: warp))
        await full.llegeix()
        #expect(!full.potObrirPermis)
        full.obrePermis()
        #expect(crides.n == 0)
    }
}
