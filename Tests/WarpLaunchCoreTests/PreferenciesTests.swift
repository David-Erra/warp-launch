import Foundation
import Testing
@testable import WarpLaunchCore

// `preferencies.json` (D-P4, 0.29.0): el consentiment de la restauració de Warp i el valor original de `restore_session`.
// Sempre en una carpeta temporal.

private let t0 = Date(timeIntervalSince1970: 1_793_750_400)

private func carpeta(_ tmp: CarpetaTemporal) -> URL { URL(filePath: tmp.ruta, directoryHint: .isDirectory) }

private func noms(_ tmp: CarpetaTemporal) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: tmp.ruta).sorted()
}

@Suite struct PreferenciesTests {
    /// Una carpeta nova: sense triar, sense valor original, i llegir-la no crea res.
    @Test func perDefecteSenseTriar() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        let preferencies = try magatzem.carrega()
        #expect(preferencies == Preferencies())
        #expect(preferencies.versio == 1 && preferencies.restauracio == .senseTriar && preferencies.restauracioOriginal == nil)
        #expect(!preferencies.restauracio.esAcceptat)
        #expect(try noms(tmp).isEmpty)
    }

    /// Migració: amb `configuracio.json` o `estat.json` i sense `preferencies.json`, l'app ja es feia servir (D19), i el
    /// consentiment compta com a acceptat sense preguntar. No s'escriu res.
    @Test(arguments: [MagatzemConfiguracio.nomFitxer, EstatApp.nomFitxer])
    func ambLaCarpetaJaFetaComptaComAcceptat(_ nom: String) throws {
        let tmp = try CarpetaTemporal()
        try Data("{}".utf8).write(to: tmp.url(nom))
        let preferencies = try MagatzemPreferencies(carpeta: carpeta(tmp)).carrega()
        #expect(preferencies.restauracio == .migrat && preferencies.restauracio.esAcceptat)
        #expect(try noms(tmp) == [nom])
    }

    /// Un enllaç (encara que sigui trencat) també compta: el fitxer hi és.
    @Test func unEnllacALaConfiguracioTambeCompta() throws {
        let tmp = try CarpetaTemporal()
        try FileManager.default.createSymbolicLink(atPath: tmp.url(MagatzemConfiguracio.nomFitxer).path,
                                                   withDestinationPath: tmp.url("no-hi-es.json").path)
        #expect(try MagatzemPreferencies(carpeta: carpeta(tmp)).carrega().restauracio == .migrat)
    }

    /// Si ja hi ha `preferencies.json`, mana el fitxer: no es torna a migrar.
    @Test func elFitxerManaSobreLaMigracio() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try magatzem.desa(Preferencies(restauracio: .senseTriar))
        try Data("{}".utf8).write(to: tmp.url(MagatzemConfiguracio.nomFitxer))
        #expect(try magatzem.carrega().restauracio == .senseTriar)
    }

    /// «Accepta» desa el consentiment amb la data, a segons sencers, i es torna a llegir igual.
    @Test func acceptaDesaLaData() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        let desades = try magatzem.accepta(ara: t0 + 0.75)
        #expect(desades.restauracio == .acceptat(t0))
        #expect(try magatzem.carrega() == desades)
        let text = try String(contentsOf: magatzem.fitxer, encoding: .utf8)
        #expect(text.contains(#""consentiment" : "acceptat""#), "\(text)")
        #expect(text.contains(#""acceptatEl" : "2026-11-04T00:00:00Z""#), "\(text)")
        #expect(text.contains(#""versio" : 1"#))
        #expect(text.contains(#""generador" : "Warp Launch \#(WarpLaunch.versio)""#))
        #expect(!text.contains("valorOriginal"), "encara no s'ha canviat res de Warp")
        #expect(try noms(tmp) == [Preferencies.nomFitxer], "cap fitxer temporal")
    }

    /// El valor original de `restore_session` es desa el primer cop, i després ja no canvia.
    @Test func elValorOriginalNomesEsDesaUnCop() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try magatzem.accepta(ara: t0)
        #expect(try magatzem.recordaRestauracioOriginal(true))
        #expect(try !magatzem.recordaRestauracioOriginal(false))
        let preferencies = try magatzem.carrega()
        #expect(preferencies.restauracioOriginal == true)
        #expect(preferencies.restauracio == .acceptat(t0), "el consentiment no es toca")
    }

    /// L'ajust de Warp passa per `posaRestauracio`: abans del primer canvi, el valor que hi havia; després, ja no. Amb una
    /// carpeta migrada, el fitxer es crea amb el consentiment `migrat`.
    @Test func posarLAjustDesaElValorDAbansDelPrimerCanvi() throws {
        let tmp = try CarpetaTemporal()
        try Data("{}".utf8).write(to: tmp.url(EstatApp.nomFitxer))
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        var ajust = true
        var posats: [Bool] = []
        func posa(_ nou: Bool) throws {
            try magatzem.posaRestauracio(nou, valor: { ajust }, posa: { posats.append($0); ajust = $0; return .escrit })
        }

        try posa(true)
        #expect(!FileManager.default.fileExists(atPath: magatzem.fitxer.path), "no ha canviat res: no es desa")
        try posa(false)
        #expect(try magatzem.carrega() == Preferencies(restauracio: .migrat, restauracioOriginal: true))
        try posa(true)
        try posa(false)
        #expect(try magatzem.carrega().restauracioOriginal == true)
        #expect(posats == [true, false, true, false] && !ajust)
    }

    /// Si no es pot desar el valor original, l'ajust es canvia igualment: que quedi desactivat és més important.
    @Test func siNoEsPotDesarLAjustEsCanviaIgualment() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try Data(#"{"versio": 9}"#.utf8).write(to: magatzem.fitxer)
        var ajust = true
        try magatzem.posaRestauracio(false, valor: { ajust }, posa: { ajust = $0; return .escrit })
        #expect(!ajust)
        #expect(try String(contentsOf: magatzem.fitxer, encoding: .utf8) == #"{"versio": 9}"#)
    }

    /// Si no es pot llegir el valor actual, no es canvia res, i l'error arriba a qui ho demana.
    @Test func siNoEsPotLlegirLAjustNoEsToca() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        struct NoEsPot: Error {}
        var posats = 0
        #expect(throws: NoEsPot.self) {
            try magatzem.posaRestauracio(false, valor: { throw NoEsPot() }, posa: { _ in posats += 1; return .escrit })
        }
        #expect(posats == 0)
        #expect(try noms(tmp).isEmpty)
    }

    /// Si `settings.toml` acaba de canviar (0.31.3), el valor llegit podria ser el d'un fitxer buit o a mitges: no es desa
    /// com el d'abans ni es canvia l'ajust, i no és cap error. Quan es torna a provar, sí.
    @Test func siLAjustAcabaDeCanviarNoEsDesaNiEsToca() throws {
        let tmp = try CarpetaTemporal()
        try Data("{}".utf8).write(to: tmp.url(EstatApp.nomFitxer))
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        var valor: Bool? = nil
        var posats: [Bool] = []
        #expect(try magatzem.posaRestauracio(false, valor: { valor }, posa: { posats.append($0); return .escrit }) == .mesTard)
        #expect(posats.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: magatzem.fitxer.path))
        valor = false
        #expect(try magatzem.posaRestauracio(true, valor: { valor }, posa: { posats.append($0); return .escrit }) == .escrit)
        #expect(posats == [true])
        #expect(try magatzem.carrega() == Preferencies(restauracio: .migrat, restauracioOriginal: false))
    }

    /// Un fitxer d'una versió més nova no es trepitja.
    @Test func unaVersioMesNovaNoEsTrepitja() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        let text = #"{"versio": 2, "restauracio": {"consentiment": "acceptat", "acceptatEl": "2026-11-07T10:00:00Z"}}"#
        try Data(text.utf8).write(to: magatzem.fitxer)
        #expect(throws: Preferencies.ErrorPreferencies.versioMesNova(2)) { try magatzem.carrega() }
        #expect(throws: Preferencies.ErrorPreferencies.versioMesNova(2)) { try magatzem.accepta(ara: t0) }
        #expect(throws: Preferencies.ErrorPreferencies.versioMesNova(2)) { try magatzem.recordaRestauracioOriginal(true) }
        #expect(try String(contentsOf: magatzem.fitxer, encoding: .utf8) == text)
    }

    /// Un fitxer mal fet és un error, no «sense triar»: no es preguntaria ni es desaria al damunt sense saber-ho.
    @Test(arguments: [
        "no és JSON",
        #"{"restauracio": {"consentiment": "senseTriar"}}"#,
        #"{"versio": 1}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "potser"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "acceptat"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "migrat", "acceptatEl": "2026-11-07T10:00:00Z"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "senseTriar", "valorOriginal": "sí"}}"#,
        // 0.31.0: `retirat` sempre amb la data, i cap data on no toca.
        #"{"versio": 1, "restauracio": {"consentiment": "retirat"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "retirat", "acceptatEl": "2026-11-07T10:00:00Z"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "senseTriar", "retiratEl": "2026-11-07T10:00:00Z"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "migrat", "retiratEl": "2026-11-07T10:00:00Z"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "acceptat", "acceptatEl": "2026-11-07T10:00:00Z", "retiratEl": "2026-11-08T10:00:00Z"}}"#,
        #"{"versio": 1, "restauracio": {"consentiment": "retirat", "acceptatEl": "2026-11-07T10:00:00Z", "retiratEl": "2026-11-08T10:00:00Z"}}"#,
    ])
    func unFitxerMalFetEsUnError(_ text: String) throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try Data(text.utf8).write(to: magatzem.fitxer)
        #expect(throws: Preferencies.ErrorPreferencies.self) { try magatzem.carrega() }
        #expect(throws: Preferencies.ErrorPreferencies.self) { try magatzem.accepta(ara: t0) }
        #expect(try String(contentsOf: magatzem.fitxer, encoding: .utf8) == text)
    }

    /// Un enllaç trencat a `preferencies.json` no és «no n'hi ha»: es desaria al damunt.
    @Test func unEnllacTrencatEsUnError() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try FileManager.default.createSymbolicLink(atPath: magatzem.fitxer.path, withDestinationPath: tmp.url("enlloc.json").path)
        #expect(throws: Preferencies.ErrorPreferencies.self) { try magatzem.carrega() }
    }

    /// Les mateixes preferències donen sempre els mateixos bytes, i es tornen a llegir igual.
    @Test(arguments: [
        Preferencies(),
        Preferencies(restauracio: .acceptat(t0), restauracioOriginal: false),
        Preferencies(restauracio: .migrat, restauracioOriginal: true),
        Preferencies(restauracio: .retirat(t0)),
    ])
    func elJSONEsTornaALlegirIgual(_ preferencies: Preferencies) throws {
        let dades = try preferencies.json(generador: "prova")
        #expect(try preferencies.json(generador: "prova") == dades)
        #expect(try Preferencies.llegeix(dades) == preferencies)
    }

    // MARK: - Deixar de fer servir Warp Launch (0.31.0, decisió 3)

    /// Què se'n fa de l'ajust: el valor d'abans de l'app si se sap; amb `migrat`, el de sèrie de Warp (activat), sigui quin
    /// sigui el valor desat; si l'app no l'ha canviat mai, res. Sense el consentiment, no hi ha res per tornar.
    @Test(arguments: [
        (Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true), Preferencies.Retorn.original(true)),
        (Preferencies(restauracio: .acceptat(t0), restauracioOriginal: false), .original(false)),
        (Preferencies(restauracio: .acceptat(t0)), .senseCanvis),
        (Preferencies(restauracio: .migrat), .deSerie),
        (Preferencies(restauracio: .migrat, restauracioOriginal: false), .deSerie),
        (Preferencies(restauracio: .migrat, restauracioOriginal: true), .deSerie),
    ])
    func queEsFaAmbLAjustEnRetirar(_ preferencies: Preferencies, _ retorn: Preferencies.Retorn) {
        #expect(preferencies.retornEnRetirar == retorn)
    }

    @Test func senseConsentimentNoHiHaResPerTornar() {
        #expect(Preferencies().retornEnRetirar == nil)
        #expect(Preferencies(restauracio: .retirat(t0), restauracioOriginal: true).retornEnRetirar == nil)
        #expect(Preferencies.Retorn.original(false).valor == false && Preferencies.Retorn.original(true).valor == true)
        #expect(Preferencies.Retorn.deSerie.valor == true && Preferencies.restauracioDeSerie)
        #expect(Preferencies.Retorn.senseCanvis.valor == nil)
    }

    /// Retirar desa `retirat` amb la data, sense el valor original. Amb `configuracio.json` i `estat.json` a la carpeta, no
    /// compta com a migrat: el fitxer mana, i l'app torna a preguntar.
    @Test func retirarNoEsConfonAmbLaMigracio() throws {
        let tmp = try CarpetaTemporal()
        try Data("{}".utf8).write(to: tmp.url(MagatzemConfiguracio.nomFitxer))
        try Data("{}".utf8).write(to: tmp.url(EstatApp.nomFitxer))
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try magatzem.accepta(ara: t0)
        try magatzem.recordaRestauracioOriginal(true)

        let retirades = try magatzem.retira(ara: t0 + 3600.5)
        #expect(retirades == Preferencies(restauracio: .retirat(t0 + 3600)))
        let llegides = try magatzem.carrega()
        #expect(llegides == retirades)
        #expect(!llegides.restauracio.esAcceptat && llegides.restauracio != .migrat && llegides.retornEnRetirar == nil)
        #expect(llegides.restauracio.retiratEl == t0 + 3600 && llegides.restauracio.acceptatEl == nil)
        let text = try String(contentsOf: magatzem.fitxer, encoding: .utf8)
        #expect(text.contains(#""consentiment" : "retirat""#), "\(text)")
        #expect(text.contains(#""retiratEl" : "2026-11-04T01:00:00Z""#), "\(text)")
        #expect(!text.contains("acceptatEl") && !text.contains("valorOriginal"), "\(text)")
        #expect(try noms(tmp) == [MagatzemConfiguracio.nomFitxer, EstatApp.nomFitxer, Preferencies.nomFitxer].sorted())
    }

    /// Una carpeta migrada que encara no tenia `preferencies.json` (l'app no havia canviat mai l'ajust): retirar el crea, i
    /// a partir d'aquí ja no compta com a acceptada.
    @Test func retirarUnaCarpetaMigradaSenseFitxerElCrea() throws {
        let tmp = try CarpetaTemporal()
        try Data("{}".utf8).write(to: tmp.url(MagatzemConfiguracio.nomFitxer))
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        #expect(try magatzem.carrega().restauracio == .migrat)
        try magatzem.retira(ara: t0)
        #expect(FileManager.default.fileExists(atPath: magatzem.fitxer.path))
        #expect(try magatzem.carrega().restauracio == .retirat(t0))
    }

    /// Després de retirar, l'app no desa cap valor original (no toca l'ajust) fins que es torna a acceptar; llavors, el del
    /// primer canvi d'aquesta vegada. Sense triar, tampoc.
    @Test func senseConsentimentNoEsDesaCapValorOriginal() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        #expect(try !magatzem.recordaRestauracioOriginal(true))
        #expect(try noms(tmp).isEmpty, "sense triar: no es crea res")

        try magatzem.accepta(ara: t0)
        try magatzem.recordaRestauracioOriginal(true)
        try magatzem.retira(ara: t0 + 60)
        #expect(try !magatzem.recordaRestauracioOriginal(false))
        var ajust = false
        try magatzem.posaRestauracio(true, valor: { ajust }, posa: { ajust = $0; return .escrit })
        #expect(try magatzem.carrega() == Preferencies(restauracio: .retirat(t0 + 60)))

        try magatzem.accepta(ara: t0 + 120)
        #expect(try magatzem.recordaRestauracioOriginal(false))
        #expect(try magatzem.carrega() == Preferencies(restauracio: .acceptat(t0 + 120), restauracioOriginal: false))
    }

    /// Un fitxer que no es pot llegir no es trepitja tampoc en retirar.
    @Test func retirarNoTrepitjaUnFitxerQueNoEsPotLlegir() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemPreferencies(carpeta: carpeta(tmp))
        try Data(#"{"versio": 9}"#.utf8).write(to: magatzem.fitxer)
        #expect(throws: Preferencies.ErrorPreferencies.versioMesNova(9)) { try magatzem.retira(ara: t0) }
        #expect(try String(contentsOf: magatzem.fitxer, encoding: .utf8) == #"{"versio": 9}"#)
    }
}
