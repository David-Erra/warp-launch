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

/// `text` sense la taula `[general]`.
private let senseGeneral = text.replacingOccurrences(of: "[general]\nlogin_item = true\nrestore_session = false\n\n", with: "")

@Suite struct AjustRestauracioTests {
    private struct Banc {
        let tmp: CarpetaTemporal
        var ajust: AjustRestauracio
        var fitxer: URL { ajust.ruta }

        /// Amb `nil`, la carpeta sense el fitxer.
        init(_ contingut: String? = text) throws {
            tmp = try CarpetaTemporal()
            let temporal = try tmp.carpeta("tmp")
            ajust = AjustRestauracio(ruta: tmp.url("settings.toml"), carpetaTemporal: URL(filePath: temporal))
            if let contingut { try Data(contingut.utf8).write(to: tmp.url("settings.toml")) }
        }

        /// Byte a byte: `String(contentsOf:encoding:)` trauria la marca d'ordre de bytes (BOM).
        var contingut: String { (try? Data(contentsOf: fitxer)).flatMap { String(validating: $0, as: UTF8.self) } ?? "" }
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
        "[general]\nx = 1\r\n[altra]\nrestore_session = false\n", // Un CRLF amagaria la taula.
    ])
    func unaFormaInesperadaNoEsToca(contingut: String) throws {
        let b = try Banc(contingut)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(true) }
        #expect(b.contingut == contingut)
        #expect(b.temporals.isEmpty)
    }

    @Test func unaRedireccioNoEsToca() throws {
        let b = try Banc(nil)
        let altre = b.tmp.url("altre.toml")
        try Data(text.utf8).write(to: altre)
        try FileManager.default.createSymbolicLink(at: b.fitxer, withDestinationURL: altre)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.valor() }
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(true) }
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(false) }
        #expect(try String(contentsOf: altre, encoding: .utf8) == text)
        // Un enllaç trencat, igual: no es crea res a l'altra banda.
        try FileManager.default.removeItem(at: altre)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(false) }
        #expect(!FileManager.default.fileExists(atPath: altre.path))
    }

    // MARK: - Sense la línia (0.31.2, decisió A)

    /// Sense cap aparició, el valor és el de sèrie de Warp, i activar-lo no escriu res, tampoc si no s'hi podria afegir.
    @Test(arguments: ["[general]\nlogin_item = true\n", "", "a = 1\n", "[general]\nx = 1\r\n", "[general]\n[general]\n"])
    func senseLiniaElValorEsElDeSerie(contingut: String) throws {
        let b = try Banc(contingut)
        let abans = try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int
        #expect(try b.ajust.valor() == true)
        #expect(try !b.ajust.posa(true))
        #expect(b.contingut == contingut)
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int == abans)
        #expect(b.temporals.isEmpty)
    }

    /// Desactivar-lo hi afegeix la línia: just després de `[general]`, la taula abans de la primera subtaula, o al final.
    /// Després, `analitza` la troba, i es pot tornar a activar canviant-ne només el valor.
    @Test(arguments: [
        ("[general]\nlogin_item = true\n", "[general]\nrestore_session = false\nlogin_item = true\n"),
        ("  [ general ]\t\nx = 1\n", "  [ general ]\t\nrestore_session = false\nx = 1\n"),
        ("a = 1\n\n[general]\nx = 1\n\n[terminal]\ny = 2\n", "a = 1\n\n[general]\nrestore_session = false\nx = 1\n\n[terminal]\ny = 2\n"),
        ("[general]\nx = 1\n\n[general.sub]\ny = 2\n", "[general]\nrestore_session = false\nx = 1\n\n[general.sub]\ny = 2\n"),
        ("[general.sub]\ny = 2\n[general]\nx = 1\n", "[general.sub]\ny = 2\n[general]\nrestore_session = false\nx = 1\n"),
        // Sense `[general]`: al final, amb una línia en blanc abans.
        (senseGeneral, senseGeneral + "\n[general]\nrestore_session = false\n"),
        ("\n", "\n\n[general]\nrestore_session = false\n"),
        ("[generalitat]\nx = 1\n[[llista]]\ny = 1\n", "[generalitat]\nx = 1\n[[llista]]\ny = 1\n\n[general]\nrestore_session = false\n"),
        // Una clau `general` dins d'una taula en línia, i un comentari, no són la taula.
        ("[a]\nb = { general = 1 }\n# [general]\n", "[a]\nb = { general = 1 }\n# [general]\n\n[general]\nrestore_session = false\n"),
        // Només subtaules: la taula, just abans de la primera (vàlid a qualsevol versió de TOML).
        ("a = 1\n\n[general.sub]\ny = 2\n", "a = 1\n\n[general]\nrestore_session = false\n\n[general.sub]\ny = 2\n"),
        ("[appearance]\nx = 1\n[ general . a ] # comentari\ny = 1\n[general.b]\nz = 1\n",
         "[appearance]\nx = 1\n[general]\nrestore_session = false\n\n[ general . a ] # comentari\ny = 1\n[general.b]\nz = 1\n"),
        // Un fitxer buit: només la taula i la línia.
        ("", "[general]\nrestore_session = false\n"),
    ])
    func desactivarSenseLiniaLAfegeix(contingut: String, esperat: String) throws {
        let b = try Banc(contingut)
        #expect(try b.ajust.posa(false))
        #expect(b.contingut == esperat)
        #expect(try b.ajust.valor() == false)
        #expect(try !b.ajust.posa(false))
        #expect(try b.ajust.posa(true))
        #expect(b.contingut == esperat.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
        #expect(b.temporals.isEmpty)
    }

    /// Una marca d'ordre de bytes (BOM) al començament no es perd en canviar la línia: només canvia el valor.
    @Test func conservaLaMarcaDOrdreDeBytes() throws {
        let contingut = "\u{FEFF}a = 1\n[general]\nrestore_session = false\n"
        let b = try Banc(contingut)
        #expect(try b.ajust.posa(true))
        #expect(try Data(contentsOf: b.fitxer) == Data(contingut.replacingOccurrences(of: "false", with: "true").utf8))
    }

    /// En afegir la línia, el fitxer conserva els permisos i els atributs estesos, com en canviar-la.
    @Test func afegirLaLiniaConservaPermisosIAtributs() throws {
        let b = try Banc("[general]\nx = 1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: b.fitxer.path)
        #expect(setxattr(b.fitxer.path, "cat.davide.prova", "x", 1, 0, 0) == 0)
        #expect(try b.ajust.posa(false))
        #expect(b.contingut == "[general]\nrestore_session = false\nx = 1\n")
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.posixPermissions] as? Int == 0o640)
        #expect(getxattr(b.fitxer.path, "cat.davide.prova", nil, 0, 0, 0) == 1)
    }

    /// Si el fitxer podria definir `general` d'una manera que no se sap llegir, no hi afegeix res: una segona taula
    /// `[general]` el faria invàlid. El valor continua sent el de sèrie, i activar-lo no escriu res.
    @Test(arguments: [
        "[general]\nx = 1\n[general]\ny = 2\n", // Dues capçaleres.
        "general = { x = 1 }\n", // Una taula en línia.
        "general.x = 1\n", // Una clau amb punts.
        "general . x = 1\n", // També amb espais.
        "\"general\" = { x = 1 }\n", // Entre cometes.
        "'general'.x = 1\n",
        "[\"general\"]\nx = 1\n",
        "['general']\nx = 1\n",
        "[general.\"x\"]\ny = 1\n",
        "[\"gen\\u0065ral\"]\nx = 1\n", // Amb una seqüència d'escapament, no se sap quina clau és.
        "\"gen\\u0065ral\" = { x = 1 }\n",
        "[[general]]\nx = 1\n", // Una llista de taules.
        "[[general.x]]\ny = 1\n",
        "[general] # els generals\nx = 1\n", // `analitza` no la veuria com a `[general]`.
        "[altra]\ngeneral = 1\n", // A qualsevol taula: no sempre se sap on comença una taula.
        "x = [\n  \"general = 1\",\n]\n",
        "[general]\nx = 1\r\n", // CRLF.
        "[altra]\r\n[general]\nx = 1\n",
        "a = 1", // Sense salt de línia final.
        "\u{FEFF}[general]\nx = 1\n", // Una marca d'ordre de bytes.
        "a = \"\"\"\n[general]\n\"\"\"\n", // Textos de diverses línies.
        "a = '''\nx\n'''\n",
    ])
    func unaFormaAmbiguaSenseLiniaNoEsToca(contingut: String) throws {
        let b = try Banc(contingut)
        #expect(throws: AjustRestauracio.Refusat.self) { try b.ajust.posa(false) }
        #expect(b.contingut == contingut)
        #expect(b.temporals.isEmpty)
        #expect(try b.ajust.valor() == true)
        #expect(try !b.ajust.posa(true))
        guard case let .senseLinia(.failure(motiu)) = try AjustRestauracio.analitza(contingut).lloc else {
            Issue.record("s'hi afegiria la línia: \(contingut)")
            return
        }
        #expect(motiu.description.hasPrefix("«restore_session» no hi és, i no s'hi pot afegir: "), "\(motiu)")
    }

    /// Sense el fitxer (la carpeta de Warp hi és): el valor és el de sèrie; activar-lo no crea res, i desactivar-lo el crea
    /// només amb la línia, amb 0644.
    @Test func senseFitxerElCreaNomesAmbLaLinia() throws {
        let b = try Banc(nil)
        #expect(try b.ajust.valor() == true)
        #expect(try !b.ajust.posa(true))
        #expect(!FileManager.default.fileExists(atPath: b.fitxer.path))
        #expect(try b.ajust.posa(false))
        #expect(b.contingut == "[general]\nrestore_session = false\n")
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.posixPermissions] as? Int == 0o644)
        #expect(try b.ajust.valor() == false)
        #expect(b.temporals.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: b.tmp.ruta).sorted() == ["settings.toml", "tmp"])
    }

    /// Sense la carpeta de Warp, Warp no s'ha obert mai en aquest usuari: el valor és el de sèrie, activar-lo no fa res, i
    /// desactivar-lo es refusa sense crear la carpeta.
    @Test func senseLaCarpetaDeWarpNoLaCrea() throws {
        let tmp = try CarpetaTemporal()
        let temporal = try tmp.carpeta("tmp")
        let ajust = AjustRestauracio(ruta: tmp.url("warp/settings.toml"), carpetaTemporal: URL(filePath: temporal))
        #expect(try ajust.valor() == true)
        #expect(try !ajust.posa(true))
        #expect(throws: AjustRestauracio.Refusat(description: "Warp encara no s'ha obert mai en aquest usuari: no hi ha la "
            + "carpeta «\(tmp.url("warp").path)», i Warp Launch no la crea", warpMaiObert: true)) { try ajust.posa(false) }
        #expect(!FileManager.default.fileExists(atPath: tmp.url("warp").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporal).isEmpty)
    }

    /// Si la carpeta del fitxer és un fitxer, no es pot saber res.
    @Test func siLaCarpetaEsUnFitxerNoEsToca() throws {
        let tmp = try CarpetaTemporal()
        try Data("x".utf8).write(to: tmp.url("warp"))
        let ajust = AjustRestauracio(ruta: tmp.url("warp/settings.toml"), carpetaTemporal: URL(filePath: try tmp.carpeta("tmp")))
        #expect(throws: AjustRestauracio.Refusat.self) { try ajust.valor() }
        #expect(throws: AjustRestauracio.Refusat.self) { try ajust.posa(false) }
        #expect(try String(contentsOf: tmp.url("warp"), encoding: .utf8) == "x")
    }

    /// Si Warp escriu el fitxer entre la lectura i l'escriptura, no es trepitja: ni en canviar la línia, ni en afegir-la.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false)])
    func unFitxerQueCanviaMentrestantNoEsTrepitja(contingut: String, nou: Bool) throws {
        var b = try Banc(contingut)
        let deWarp = contingut + "de_warp = 1\n"
        let fitxer = b.fitxer
        b.ajust.ganxoDeProva = { try? Data(deWarp.utf8).write(to: fitxer) }
        #expect(throws: AjustRestauracio.Refusat(description: "«\(fitxer.path)» acaba de canviar")) { try b.ajust.posa(nou) }
        #expect(b.contingut == deWarp)
        #expect(b.temporals.isEmpty)
    }

    /// Si Warp crea el fitxer entre la lectura i l'escriptura, no es trepitja (`RENAME_EXCL`).
    @Test func unFitxerQueApareixMentrestantNoEsTrepitja() throws {
        var b = try Banc(nil)
        let fitxer = b.fitxer
        b.ajust.ganxoDeProva = { try? Data("de_warp = 1\n".utf8).write(to: fitxer) }
        #expect(throws: AjustRestauracio.Refusat(description: "«\(fitxer.path)» acaba d'aparèixer")) { try b.ajust.posa(false) }
        #expect(b.contingut == "de_warp = 1\n")
        #expect(b.temporals.isEmpty)
    }

    /// Crear el fitxer tampoc no es fa des d'un altre volum: no seria d'un sol cop. L'error ha de ser el del volum: a
    /// `/dev` tampoc no s'hi pot preparar res, i sense la comprovació la prova passaria igualment.
    @Test func crearloDesDUnAltreVolumNoEsFa() throws {
        let b = try Banc(nil)
        let ajust = AjustRestauracio(ruta: b.fitxer, carpetaTemporal: URL(filePath: "/dev"))
        #expect(throws: AjustRestauracio.Refusat(description: "la carpeta temporal no és al mateix volum que "
            + "«\(b.fitxer.path)»")) { try ajust.posa(false) }
        #expect(!FileManager.default.fileExists(atPath: b.fitxer.path))
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

    /// Ni en canviar la línia ni en afegir-la. L'error ha de ser el del volum, com en crear el fitxer.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false)])
    func enUnAltreVolumNoEscriu(contingut: String, nou: Bool) throws {
        let b = try Banc(contingut)
        let ajust = AjustRestauracio(ruta: b.fitxer, carpetaTemporal: URL(filePath: "/dev"))
        #expect(throws: AjustRestauracio.Refusat(description: "la carpeta temporal no és al mateix volum que "
            + "«\(b.fitxer.path)»")) { try ajust.posa(nou) }
        #expect(b.contingut == contingut)
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
