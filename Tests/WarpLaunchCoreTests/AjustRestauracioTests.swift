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

/// L'hora de l'ajust a les proves (0.31.3): fixa, i un minut després de crear el banc, perquè els fitxers que s'hi escriuen
/// no acabin de canviar. Les proves de l'escriptura prudent la mouen, sense esperar res.
final class RellotgeDeProva: @unchecked Sendable {
    private let pany = NSLock()
    private var valor = Date() + 60

    var ara: Date { get { pany.withLock { valor } } set { pany.withLock { valor = newValue } } }
    var funcio: @Sendable () -> Date { { [self] in ara } }

    /// Posa la data de modificació del fitxer a fa `segons` (negatiu: del futur).
    func modificat(_ fitxer: URL, fa segons: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: ara - segons], ofItemAtPath: fitxer.path)
    }
}

/// Si el Warp de les proves ha acabat d'arrencar (`AjustRestauracio.potCrearElFitxer`, ronda 5): el fals del que l'app mira
/// pels processos (`Lector.warpHaAcabatDArrencar`). Per omissió, sí (Warp obert amb terminals): les proves que no són de la
/// ronda 5 creen el fitxer com abans. `enPreguntar`: el que fa Warp just quan l'ajust ho pregunta. La mateixa a
/// `WarpLaunchUITests/AjudesDeProva.swift`.
final class ArrencadaWarpDeProva: @unchecked Sendable {
    private let pany = NSLock()
    private var estat: (arrencat: Bool, crides: Int, enPreguntar: (@Sendable () -> Void)?) = (true, 0, nil)

    var arrencat: Bool { get { pany.withLock { estat.arrencat } } set { pany.withLock { estat.arrencat = newValue } } }
    /// Quantes vegades l'ajust ho ha preguntat.
    var crides: Int { pany.withLock { estat.crides } }
    var enPreguntar: (@Sendable () -> Void)? {
        get { pany.withLock { estat.enPreguntar } } set { pany.withLock { estat.enPreguntar = newValue } }
    }
    var funcio: @Sendable () -> Bool {
        { [self] in
            let (arrencat, enPreguntar) = pany.withLock { () -> (Bool, (@Sendable () -> Void)?) in
                estat.crides += 1
                return (estat.arrencat, estat.enPreguntar)
            }
            enPreguntar?()
            return arrencat
        }
    }
}

@Suite struct AjustRestauracioTests {
    private struct Banc {
        let tmp: CarpetaTemporal
        let rellotge = RellotgeDeProva()
        let warp = ArrencadaWarpDeProva()
        var ajust: AjustRestauracio
        var fitxer: URL { ajust.ruta }

        /// Amb `nil`, la carpeta sense el fitxer.
        init(_ contingut: String? = text) throws {
            tmp = try CarpetaTemporal()
            let temporal = try tmp.carpeta("tmp")
            ajust = AjustRestauracio(ruta: tmp.url("settings.toml"), carpetaTemporal: URL(filePath: temporal),
                                     rellotge: rellotge.funcio, potCrearElFitxer: warp.funcio)
            if let contingut { try Data(contingut.utf8).write(to: tmp.url("settings.toml")) }
        }

        /// Byte a byte: `String(contentsOf:encoding:)` trauria la marca d'ordre de bytes (BOM).
        var contingut: String { (try? Data(contentsOf: fitxer)).flatMap { String(validating: $0, as: UTF8.self) } ?? "" }
        var temporals: [String] { (try? FileManager.default.contentsOfDirectory(atPath: ajust.carpetaTemporal.path)) ?? [] }
    }

    @Test func nomesCanviaElValorDeLaLinia() throws {
        let b = try Banc()
        #expect(try b.ajust.valor() == false)
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(b.contingut == text.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
        #expect(try b.ajust.valor() == true)
        #expect(try b.ajust.posa(false) == .escrit)
        #expect(b.contingut == text)
        #expect(b.temporals.isEmpty)
    }

    @Test func siJaTeElValorNoEscriu() throws {
        let b = try Banc()
        let abans = try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int
        #expect(try b.ajust.posa(false) == .jaHiEra)
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int == abans)
    }

    @Test func conservaElsPermisosIElComentari() throws {
        let b = try Banc("[general]\nrestore_session = false # true o false\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: b.fitxer.path)
        #expect(try b.ajust.posa(true) == .escrit)
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
        #expect(try b.ajust.posa(true) == .jaHiEra)
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
        #expect(try b.ajust.posa(false) == .escrit)
        #expect(b.contingut == esperat)
        #expect(try b.ajust.valor() == false)
        #expect(try b.ajust.posa(false) == .jaHiEra)
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(b.contingut == esperat.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
        #expect(b.temporals.isEmpty)
    }

    /// Una marca d'ordre de bytes (BOM) al començament no es perd en canviar la línia: només canvia el valor.
    @Test func conservaLaMarcaDOrdreDeBytes() throws {
        let contingut = "\u{FEFF}a = 1\n[general]\nrestore_session = false\n"
        let b = try Banc(contingut)
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(try Data(contentsOf: b.fitxer) == Data(contingut.replacingOccurrences(of: "false", with: "true").utf8))
    }

    /// En afegir la línia, el fitxer conserva els permisos i els atributs estesos, com en canviar-la.
    @Test func afegirLaLiniaConservaPermisosIAtributs() throws {
        let b = try Banc("[general]\nx = 1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: b.fitxer.path)
        #expect(setxattr(b.fitxer.path, "cat.davide.prova", "x", 1, 0, 0) == 0)
        #expect(try b.ajust.posa(false) == .escrit)
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
        #expect(try b.ajust.posa(true) == .jaHiEra)
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
        #expect(try b.ajust.posa(true) == .jaHiEra)
        #expect(!FileManager.default.fileExists(atPath: b.fitxer.path))
        #expect(try b.ajust.posa(false) == .escrit)
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
        #expect(try ajust.posa(true) == .jaHiEra)
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

    /// Si Warp escriu el fitxer entre la lectura i l'escriptura, no es trepitja: ni en canviar la línia, ni en afegir-la. No
    /// és cap error (0.31.3): es torna a provar més tard.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false)])
    func unFitxerQueCanviaMentrestantNoEsTrepitja(contingut: String, nou: Bool) throws {
        var b = try Banc(contingut)
        let deWarp = contingut + "de_warp = 1\n"
        let fitxer = b.fitxer
        b.ajust.ganxoDeProva = { try? Data(deWarp.utf8).write(to: fitxer) }
        #expect(try b.ajust.posa(nou) == .mesTard)
        #expect(b.contingut == deWarp)
        #expect(b.temporals.isEmpty)
    }

    /// Si Warp crea el fitxer entre la lectura i l'escriptura, no es trepitja (`RENAME_EXCL`), i es torna a provar més tard.
    @Test func unFitxerQueApareixMentrestantNoEsTrepitja() throws {
        var b = try Banc(nil)
        let fitxer = b.fitxer
        b.ajust.ganxoDeProva = { try? Data("de_warp = 1\n".utf8).write(to: fitxer) }
        #expect(try b.ajust.posa(false) == .mesTard)
        #expect(b.contingut == "de_warp = 1\n")
        #expect(b.temporals.isEmpty)
    }

    /// Crear el fitxer tampoc no es fa des d'un altre volum: no seria d'un sol cop. L'error ha de ser el del volum: a
    /// `/dev` tampoc no s'hi pot preparar res, i sense la comprovació la prova passaria igualment. També amb Warp tancat
    /// (ronda 5): l'error es diu abans de preguntar si es pot crear, i no s'ha d'esperar que Warp s'obri per veure'l.
    @Test(arguments: [true, false])
    func crearloDesDUnAltreVolumNoEsFa(warpArrencat: Bool) throws {
        let b = try Banc(nil)
        b.warp.arrencat = warpArrencat
        let ajust = AjustRestauracio(ruta: b.fitxer, carpetaTemporal: URL(filePath: "/dev"), rellotge: b.rellotge.funcio,
                                     potCrearElFitxer: b.warp.funcio)
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
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(getxattr(b.fitxer.path, "cat.davide.prova", nil, 0, 0, 0) == 1)
    }

    /// Ni en canviar la línia ni en afegir-la. L'error ha de ser el del volum, com en crear el fitxer.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false)])
    func enUnAltreVolumNoEscriu(contingut: String, nou: Bool) throws {
        let b = try Banc(contingut)
        let ajust = AjustRestauracio(ruta: b.fitxer, carpetaTemporal: URL(filePath: "/dev"), rellotge: b.rellotge.funcio)
        #expect(throws: AjustRestauracio.Refusat(description: "la carpeta temporal no és al mateix volum que "
            + "«\(b.fitxer.path)»")) { try ajust.posa(nou) }
        #expect(b.contingut == contingut)
    }

    // MARK: - Crear el fitxer, només amb Warp obert (ronda 5)

    /// Sense el fitxer, si qui crida l'ajust diu que ara no es pot crear (Warp tancat, o encara arrencant), no es crea: Warp
    /// encara podria fer la migració d'arrencada, i se la saltaria. No és cap error, no queda res a la carpeta temporal, i
    /// l'ajust no ho recorda: la vegada següent ho torna a preguntar, i quan es pot, el crea.
    @Test func senseElFitxerNomesElCreaSiQuiCridaDiuQueEsPot() throws {
        let b = try Banc(nil)
        b.warp.arrencat = false
        #expect(try b.ajust.valor() == true)
        #expect(try b.ajust.posa(true) == .jaHiEra)
        #expect(b.warp.crides == 0, "activar-lo no crea res: no cal preguntar-ho")
        #expect(try b.ajust.posa(false) == .quanSObriWarp)
        #expect(try b.ajust.posa(false) == .quanSObriWarp)
        #expect(b.warp.crides == 2)
        #expect(!FileManager.default.fileExists(atPath: b.fitxer.path))
        #expect(b.temporals.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: b.tmp.ruta) == ["tmp"])
        b.warp.arrencat = true
        #expect(try b.ajust.posa(false) == .escrit)
        #expect(b.contingut == "[general]\nrestore_session = false\n")
        #expect(b.warp.crides == 3)
        #expect(b.temporals.isEmpty)
    }

    /// Per omissió (sense dir si es pot), l'ajust no crea mai el fitxer.
    @Test func perOmissioNoCreaElFitxer() throws {
        let tmp = try CarpetaTemporal()
        let ajust = AjustRestauracio(ruta: tmp.url("settings.toml"), carpetaTemporal: URL(filePath: try tmp.carpeta("tmp")),
                                     rellotge: { Date() + 3600 })
        #expect(try ajust.posa(false) == .quanSObriWarp)
        #expect(!FileManager.default.fileExists(atPath: tmp.url("settings.toml").path))
    }

    /// Es pregunta després de llegir que el fitxer no hi és, just abans de crear-lo: si Warp el crea just llavors (amb un
    /// ajust seu), no es trepitja, i és `.mesTard`. Si es preguntés abans de llegir, l'ajust veuria el fitxer de Warp i hi
    /// afegiria la taula.
    @Test func esPreguntaJustAbansDeCrearlo() throws {
        let b = try Banc(nil)
        let fitxer = b.fitxer
        b.warp.enPreguntar = { try? Data("x = 1\n".utf8).write(to: fitxer) }
        #expect(try b.ajust.posa(false) == .mesTard)
        #expect(b.contingut == "x = 1\n")
        #expect(b.warp.crides == 1)
        #expect(b.temporals.isEmpty)
    }

    /// Amb el fitxer, afegir-hi la línia o la taula, o canviar-la, no depèn de Warp: també amb Warp tancat, com a la 0.31.2.
    /// Ni s'arriba a preguntar.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false), ("x = 1\n", false), ("", false)])
    func ambElFitxerEscriuAmbWarpTancat(contingut: String, nou: Bool) throws {
        let b = try Banc(contingut)
        b.warp.arrencat = false
        #expect(try b.ajust.posa(nou) == .escrit)
        #expect(try b.ajust.valor() == nou)
        #expect(b.warp.crides == 0)
    }

    /// Sense la carpeta de Warp, refusa com abans, sense preguntar-ho: no és que Warp encara arrenqui, és que no s'ha obert mai.
    @Test func senseLaCarpetaNoHoPregunta() throws {
        let tmp = try CarpetaTemporal()
        let warp = ArrencadaWarpDeProva()
        let ajust = AjustRestauracio(ruta: tmp.url("warp/settings.toml"), carpetaTemporal: URL(filePath: try tmp.carpeta("tmp")),
                                     potCrearElFitxer: warp.funcio)
        #expect(throws: AjustRestauracio.Refusat.self) { try ajust.posa(false) }
        #expect(warp.crides == 0)
        #expect(!FileManager.default.fileExists(atPath: tmp.url("warp").path))
    }

    // MARK: - Escriptura prudent (0.31.3)

    /// Canviar la línia, inserir-la i inserir la taula: amb un fitxer que ha canviat fa 1 s (Warp el podria estar escrivint),
    /// ni se'n diu el valor ni s'hi escriu res, i no és cap error. Quan fa 3 s que ha canviat, sí.
    @Test(arguments: [(text, true), ("[general]\nx = 1\n", false), ("x = 1\n", false)])
    func siHaCanviatFa1sNoEscriuIHoTornaAProvar(contingut: String, nou: Bool) throws {
        let b = try Banc(contingut)
        try b.rellotge.modificat(b.fitxer, fa: 1)
        let abans = try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int
        #expect(try b.ajust.valor() == nil)
        #expect(try b.ajust.posa(nou) == .mesTard)
        #expect(b.contingut == contingut)
        #expect(try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.systemFileNumber] as? Int == abans)
        #expect(b.temporals.isEmpty)
        // Més tard, sense que ningú l'hagi tornat a tocar: fa 3 s.
        b.rellotge.ara += 2
        #expect(try b.ajust.valor() == !nou)
        #expect(try b.ajust.posa(nou) == .escrit)
        #expect(try b.ajust.valor() == nou)
    }

    /// Un fitxer que ha canviat fa 3 s ja no és recent: s'hi escriu.
    @Test func siHaCanviatFa3sEscriu() throws {
        let b = try Banc()
        try b.rellotge.modificat(b.fitxer, fa: 3)
        #expect(try b.ajust.valor() == false)
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(b.contingut == text.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
    }

    /// Un fitxer buit que ha canviat fa poc pot ser Warp a mig escriure: ni el valor ni cap escriptura (tampoc activar-lo,
    /// que no escriuria res). Buit i antic, és buit de debò: s'hi posa la taula.
    @Test func unFitxerBuitRecentNoEsTocaIAnticSi() throws {
        let b = try Banc("")
        try b.rellotge.modificat(b.fitxer, fa: 1)
        #expect(try b.ajust.valor() == nil)
        #expect(try b.ajust.posa(true) == .mesTard)
        #expect(try b.ajust.posa(false) == .mesTard)
        #expect(b.contingut == "")
        #expect(b.temporals.isEmpty)
        try b.rellotge.modificat(b.fitxer, fa: 3)
        #expect(try b.ajust.valor() == true)
        #expect(try b.ajust.posa(false) == .escrit)
        #expect(b.contingut == "[general]\nrestore_session = false\n")
    }

    /// Una data del futur (el rellotge del Mac ha anat enrere) també compta com a recent.
    @Test func unaDataDelFuturCompta() throws {
        let b = try Banc()
        try b.rellotge.modificat(b.fitxer, fa: -10)
        #expect(try b.ajust.valor() == nil)
        #expect(try b.ajust.posa(true) == .mesTard)
        #expect(b.contingut == text)
    }

    /// Just abans del `rename`, el fitxer ha de ser el que s'ha llegit també segons `stat`, encara que el contingut sigui el
    /// mateix: si n'ha canviat la data (Warp l'ha tornat a escriure igual) o l'inode (l'ha substituït per un d'igual, amb la
    /// mateixa data), no s'hi escriu res, i es torna a provar més tard.
    @Test(arguments: [false, true])
    func siStatCanviaAbansDelRenameNoEscriu(substituit: Bool) throws {
        var b = try Banc()
        let fitxer = b.fitxer, copia = b.tmp.url("copia.toml"), ara = b.rellotge.ara
        var info = stat()
        #expect(lstat(fitxer.path, &info) == 0)
        let abans = info
        b.ajust.ganxoDeProva = {
            if substituit {
                // El mateix contingut, la mateixa mida i la mateixa data, fins al nanosegon: només canvia l'inode.
                try? Data(text.utf8).write(to: copia)
                var dates = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), abans.st_mtimespec]
                _ = utimensat(AT_FDCWD, copia.path, &dates, 0)
                _ = rename(copia.path, fitxer.path)
            } else {
                try? FileManager.default.setAttributes([.modificationDate: ara - 30], ofItemAtPath: fitxer.path)
            }
        }
        #expect(try b.ajust.posa(true) == .mesTard)
        var despres = stat()
        #expect(lstat(fitxer.path, &despres) == 0)
        #expect(despres.st_size == abans.st_size)
        if substituit {
            #expect(despres.st_ino != abans.st_ino)
            #expect(despres.st_mtimespec.tv_sec == abans.st_mtimespec.tv_sec)
            #expect(despres.st_mtimespec.tv_nsec == abans.st_mtimespec.tv_nsec)
        } else {
            #expect(despres.st_ino == abans.st_ino)
        }
        #expect(b.contingut == text)
        #expect(b.temporals.isEmpty)
    }

    /// La data recent del fitxer que acaba de posar l'ajust no compta (si no, un refresc no el podria tornar a desactivar fins
    /// passats 2 s), també des d'una còpia de l'ajust, com les de l'app. Si després hi escriu Warp, encara que sigui el mateix
    /// text, ja no és seu.
    @Test(arguments: [text, nil])
    func laDataRecentDelQueHaPosatLAjustNoCompta(contingut: String?) throws {
        let b = try Banc(contingut)
        let copia = b.ajust
        #expect(try b.ajust.posa(false) == (contingut == nil ? .escrit : .jaHiEra))
        #expect(try b.ajust.posa(true) == .escrit)
        let posat = b.contingut
        b.rellotge.ara = try #require(FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.modificationDate] as? Date) + 0.5
        #expect(try copia.valor() == true)
        #expect(try copia.posa(false) == .escrit)
        b.rellotge.ara = try #require(FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.modificationDate] as? Date) + 0.5
        #expect(try b.ajust.posa(true) == .escrit)
        #expect(b.contingut == posat)

        try Data(posat.utf8).write(to: b.fitxer)
        b.rellotge.ara = try #require(FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.modificationDate] as? Date) + 0.5
        #expect(try b.ajust.valor() == nil)
        #expect(try copia.posa(false) == .mesTard)
        #expect(b.contingut == posat)
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
