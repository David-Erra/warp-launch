import Foundation
import Testing
@testable import WarpLaunchCore

// L'ajust de la restauració de sessió que l'app escriu (D19). Les mateixes garanties que `ScriptRestauracioTests`, sempre
// sobre un fitxer temporal.

private let text = """
    is_settings_sync_enabled = true

    [agents.warp_agent.other]
    restored = 'text que no s\\'ha de tocar: true false'

    [general]
    login_item = true
    restore_session = false

    [appearance]
    theme = "true"

    """

@Suite struct AjustRestauracioTests {
    private struct Banc {
        let tmp: CarpetaTemporal
        let ajust: AjustRestauracio
        var fitxer: URL { ajust.ruta }

        init(_ contingut: String = text) throws {
            tmp = try CarpetaTemporal()
            let temporal = try tmp.carpeta("tmp")
            ajust = AjustRestauracio(ruta: tmp.url("settings.toml"), carpetaTemporal: URL(filePath: temporal))
            try Data(contingut.utf8).write(to: tmp.url("settings.toml"))
        }

        var contingut: String { (try? String(contentsOf: fitxer, encoding: .utf8)) ?? "" }
        var temporals: [String] { (try? FileManager.default.contentsOfDirectory(atPath: ajust.carpetaTemporal.path)) ?? [] }
    }

    @Test func nomesCanviaElValorDeLaLinia() throws {
        let b = try Banc()
        #expect(try b.ajust.valor() == false)
        #expect(try b.ajust.posa(true))
        #expect(b.contingut == text.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
        #expect(try b.ajust.valor() == true)
        #expect(try b.ajust.posa(false))
        #expect(b.contingut == text)
        #expect(b.temporals.isEmpty)
    }

    @Test func siJaTeElValorNoEscriu() throws {
        let b = try Banc()
        let abans = try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int
        #expect(try !b.ajust.posa(false))
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int == abans)
    }

    @Test func conservaElsPermisosIElComentari() throws {
        let b = try Banc("[general]\nrestore_session = false # true o false\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: b.fitxer.path)
        #expect(try b.ajust.posa(true))
        #expect(b.contingut == "[general]\nrestore_session = true # true o false\n")
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.posixPermissions] as? Int == 0o640)
    }

    @Test(arguments: [
        "[altra]\nrestore_session = false\n", // En una altra taula.
        "general.restore_session = false\n", // Fora de la taula.
        "restore_session = false\n[general]\nx = 1\n", // Abans de la taula.
        "[general]\nrestore_session = false\nrestore_session = true\n", // Dues vegades.
        "[general]\nrestore_session = false\n[a]\nb = 'restore_session'\n", // També en un text.
        "[general]\n# restore_session = false\n", // Comentada.
        "[general]\nrestore_session = \"false\"\n", // No és un booleà.
        "[general]\nrestore_session = false", // Sense salt de línia final.
        "[general]\nrestore_session = false\r\n", // Amb CRLF.
        "[general]\nx = 1\n", // No hi és.
        "[general]\nx = 1\r\n[altra]\nrestore_session = false\n", // Un CRLF amagaria la taula.
    ])
    func unaFormaInesperadaNoEsToca(contingut: String) throws {
        let b = try Banc(contingut)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(true) }
        #expect(b.contingut == contingut)
        #expect(b.temporals.isEmpty)
    }

    @Test func senseFitxerORedireccioNoEsToca() throws {
        let b = try Banc()
        let altre = b.tmp.url("altre.toml")
        try Data(text.utf8).write(to: altre)
        try FileManager.default.removeItem(at: b.fitxer)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.valor() }
        try FileManager.default.createSymbolicLink(at: b.fitxer, withDestinationURL: altre)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(true) }
        #expect(try String(contentsOf: altre, encoding: .utf8) == text)
    }

    @Test func unFitxerDeNomesLecturaNoEsToca() throws {
        let b = try Banc()
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: b.fitxer.path)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(true) }
        #expect(b.contingut == text)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: b.fitxer.path)
    }

    @Test func conservaElsAtributsEstesos() throws {
        let b = try Banc()
        #expect(setxattr(b.fitxer.path, "cat.davide.prova", "x", 1, 0, 0) == 0)
        #expect(try b.ajust.posa(true))
        #expect(getxattr(b.fitxer.path, "cat.davide.prova", nil, 0, 0, 0) == 1)
    }

    @Test func enUnAltreVolumNoEscriu() throws {
        let b = try Banc()
        let ajust = AjustRestauracio(ruta: b.fitxer, carpetaTemporal: URL(filePath: "/dev"))
        #expect(throws: AjustRestauracio.Refusat.self) { try ajust.posa(true) }
        #expect(b.contingut == text)
    }
}

@Suite struct FotoFinestresTests {
    private func lectura(panes: [String], terminals: [String?], titol: String = "T") -> LecturaWarp {
        var l = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: panes.enumerated().map { i, p in
            PestanyaLlegida(posicio: i, titol: titol, color: nil, panes: [
                PaneLlegit(uuid: p, carpeta: "/x", origenCarpeta: .pane, carpetaExisteix: true),
            ])
        })], sessionsSensePestanya: [], avisos: [])
        l.terminals = terminals.enumerated().map { TerminalViu(pid: Int32($0), carpeta: nil, pane: $1) }
        return l
    }

    @Test func quadraSiElsPanesSonElsMateixos() {
        #expect(lectura(panes: ["aa", "bb"], terminals: ["aa", "bb"]).finestresQuadrenAmbTerminals)
        // Un shell sense cap fill no diu el seu pane.
        #expect(lectura(panes: ["aa", "bb"], terminals: ["aa", nil]).finestresQuadrenAmbTerminals)
        // Warp no fa servir guions a la base, i potser sí a l'entorn.
        #expect(lectura(panes: ["aabb"], terminals: ["AA-BB"]).finestresQuadrenAmbTerminals)
    }

    @Test func noQuadraSiLaBaseEsAntiga() {
        #expect(!lectura(panes: ["aa"], terminals: ["aa", "bb"]).finestresQuadrenAmbTerminals)
        #expect(!lectura(panes: ["aa", "bb"], terminals: ["aa"]).finestresQuadrenAmbTerminals)
        #expect(!lectura(panes: ["aa", "cc"], terminals: ["aa", "bb"]).finestresQuadrenAmbTerminals)
        #expect(lectura(panes: ["aa"], terminals: ["aa", "bb"]).avisFinestresAntigues.contains("1 pestanya desades i 2 terminals vius"))
    }

    @Test func laFotoNoteLesSessionsPeroSiElsTitols() {
        #expect(lectura(panes: ["aa"], terminals: []).fotoFinestres != lectura(panes: ["aa"], terminals: [], titol: "U").fotoFinestres)
    }
}
