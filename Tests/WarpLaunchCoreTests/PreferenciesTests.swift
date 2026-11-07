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
            try magatzem.posaRestauracio(nou, valor: { ajust }, posa: { posats.append($0); ajust = $0 })
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
        try magatzem.posaRestauracio(false, valor: { ajust }, posa: { ajust = $0 })
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
            try magatzem.posaRestauracio(false, valor: { throw NoEsPot() }, posa: { _ in posats += 1 })
        }
        #expect(posats == 0)
        #expect(try noms(tmp).isEmpty)
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
    ])
    func elJSONEsTornaALlegirIgual(_ preferencies: Preferencies) throws {
        let dades = try preferencies.json(generador: "prova")
        #expect(try preferencies.json(generador: "prova") == dades)
        #expect(try Preferencies.llegeix(dades) == preferencies)
    }
}
