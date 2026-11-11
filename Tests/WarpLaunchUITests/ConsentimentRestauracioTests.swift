import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// D-P4 (0.29.0): sense el consentiment, l'app no toca l'ajust de la restauració de Warp. L'ajust és fals, i
// `preferencies.json`, en una carpeta temporal.

private let t0 = Date(timeIntervalSince1970: 1_793_750_400)

/// Una carpeta temporal, que s'esborra en acabar.
private final class Carpeta {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-consentiment-\(UUID().uuidString)",
                                                               directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    var magatzem: MagatzemPreferencies { MagatzemPreferencies(carpeta: url) }
    var noms: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
}

/// L'ajust de Warp, fals: comença activat, com el d'un usuari nou.
private final class AjustFals: @unchecked Sendable {
    private let pany = NSLock()
    private var estat = (valor: true, llegits: 0, posats: [Bool]())

    var valor: Bool { pany.withLock { estat.valor } }
    var llegits: Int { pany.withLock { estat.llegits } }
    var posats: [Bool] { pany.withLock { estat.posats } }

    /// Com el de l'app: el primer canvi desa a `preferencies.json` el valor que hi havia.
    func entorn(_ magatzem: MagatzemPreferencies) -> RefrescWarp.Entorn {
        RefrescWarp.Entorn(
            ajust: { [self] in pany.withLock { estat.llegits += 1; return estat.valor } },
            posa: { [self] nou in
                try magatzem.posaRestauracio(nou, valor: { pany.withLock { estat.valor } }, posa: { nou in
                    pany.withLock {
                        estat.posats.append(nou)
                        estat.valor = nou
                    }
                    return .escrit
                })
            },
            warpObert: { true },
            llegeixBase: { LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) },
            espera: { _ in })
    }
}

/// Quantes vegades s'ha demanat l'entorn de l'ajust.
@MainActor
private final class Comptador {
    var n = 0
}

@MainActor
private func consentiment(_ carpeta: Carpeta, _ ajust: AjustFals, _ demanats: Comptador) -> ConsentimentRestauracio {
    ConsentimentRestauracio(magatzem: carpeta.magatzem, creaEntornRefresc: {
        demanats.n += 1
        return ajust.entorn(carpeta.magatzem)
    }, rellotge: { t0 })
}

@MainActor
@Suite struct ConsentimentRestauracioTests {
    /// Decisió 7 de Sparkle: la frase que veu qui accepta el permís.
    @Test func laPantallaDiuQueLAppEsConnecta() {
        #expect(ConsentimentRestauracio.textActualitzacions
            == "Un cop al dia, l'app mira a GitHub si hi ha una versió nova i s'hi actualitza sola. Ho pots apagar a la Configuració.")
    }

    /// Multidioma (fase F3): la pantalla del permís, en anglès. Els textos es calculen cada vegada (cap `static let`): el de
    /// les actualitzacions també surt en la llengua del bloc.
    @Test func laPantallaDelPermisEnAngles() throws {
        let carpeta = try Carpeta()
        let c = consentiment(carpeta, AjustFals(), Comptador())
        Idioma.$deProva.withValue("en") {
            #expect(c.textSortir == "Without this permission, Warp Launch can't be used. If you quit, nothing is saved, and it will "
                + "ask you again next time.")
            #expect(ConsentimentRestauracio.textActualitzacions
                == "Once a day, the app checks GitHub for a new version and updates itself. You can turn this off in Settings.")
        }
    }

    /// Sense consentiment, no hi ha refresc, l'entorn de l'ajust ni es demana, i el que l'app fa cada minut, en obrir Warp
    /// i en sortir no crida mai `posa`. No es desa res: la propera vegada es torna a preguntar.
    @Test func senseConsentimentNoEsTocaLAjust() throws {
        let carpeta = try Carpeta()
        let ajust = AjustFals()
        let demanats = Comptador()
        let c = consentiment(carpeta, ajust, demanats)
        #expect(c.estat == .pendent && !c.potContinuar && c.potAcceptar)
        #expect(c.refresc == nil && demanats.n == 0)
        // Cada minut, abans d'engegar Warp i en sortir (`Aplicacio.refresc` és el del consentiment).
        c.refresc?.vigila()
        c.refresc?.tanca()
        c.refresc?.atura()
        #expect(ajust.posats.isEmpty && ajust.llegits == 0 && ajust.valor)
        #expect(carpeta.noms.isEmpty, "no es desa res")
        #expect(c.textSortir.contains("no es desa res, i t'ho tornarà a preguntar la propera vegada"), "\(c.textSortir)")
        #expect(consentiment(carpeta, ajust, demanats).estat == .pendent, "es torna a preguntar")
        #expect(demanats.n == 0)
    }

    /// En acceptar: es desa amb la data, es crea el refresc (un sol cop) i, ara sí, l'ajust queda desactivat; el valor que
    /// tenia es desa. La propera vegada ja no es pregunta.
    @Test func enAcceptarEsDesaIEsCreaElRefresc() throws {
        let carpeta = try Carpeta()
        let ajust = AjustFals()
        let demanats = Comptador()
        let c = consentiment(carpeta, ajust, demanats)
        c.accepta()
        #expect(c.estat == .acceptat && c.potContinuar && !c.potAcceptar && c.errorDesat == nil)
        #expect(demanats.n == 1)
        let refresc = try #require(c.refresc)
        refresc.vigila()
        #expect(ajust.posats == [false] && !ajust.valor)
        #expect(try carpeta.magatzem.carrega() == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true))
        c.accepta()
        #expect(demanats.n == 1 && c.refresc === refresc, "un sol refresc")

        let altra = consentiment(carpeta, ajust, demanats)
        #expect(altra.estat == .acceptat && altra.refresc != nil)
    }

    /// `enContinuar` espera l'acceptació, i llavors s'executa un sol cop, en ordre; si ja es pot continuar, de seguida.
    @Test func enContinuarEsperaLAcceptacio() throws {
        let carpeta = try Carpeta()
        let c = consentiment(carpeta, AjustFals(), Comptador())
        var fets: [String] = []
        c.enContinuar { fets.append("a") }
        c.enContinuar { fets.append("b") }
        #expect(fets.isEmpty)
        c.accepta()
        #expect(fets == ["a", "b"])
        c.accepta()
        c.enContinuar { fets.append("c") }
        #expect(fets == ["a", "b", "c"])
    }

    /// Migració: la carpeta d'abans (amb `configuracio.json`) compta com a acceptada sense preguntar ni desar res, i té
    /// refresc des de l'arrencada.
    @Test func laCarpetaDAbansNoPregunta() throws {
        let carpeta = try Carpeta()
        try Data("{}".utf8).write(to: carpeta.url.appending(path: MagatzemConfiguracio.nomFitxer))
        let demanats = Comptador()
        let c = consentiment(carpeta, AjustFals(), demanats)
        #expect(c.estat == .acceptat && c.refresc != nil && demanats.n == 1)
        var fet = false
        c.enContinuar { fet = true }
        #expect(fet)
        #expect(carpeta.noms == [MagatzemConfiguracio.nomFitxer])
    }

    /// Una carpeta de prova (sense entorn de l'ajust): s'ha d'acceptar igualment, però no hi ha cap refresc.
    @Test func senseEntornNoHiHaRefresc() throws {
        let carpeta = try Carpeta()
        let c = ConsentimentRestauracio(magatzem: carpeta.magatzem, creaEntornRefresc: nil, rellotge: { t0 })
        #expect(c.estat == .pendent)
        c.accepta()
        #expect(c.estat == .acceptat && c.refresc == nil)
    }

    /// Sense carpeta de configuració, no cal: l'app no toca Warp ni té on desar-ho, i tampoc no hi ha refresc.
    @Test func senseCarpetaNoCal() {
        let ajust = AjustFals()
        let c = ConsentimentRestauracio(magatzem: nil, creaEntornRefresc: { ajust.entorn(MagatzemPreferencies(carpeta: URL(filePath: "/no-hi-es"))) })
        #expect(c.estat == .noCal && c.potContinuar && !c.potAcceptar)
        #expect(c.refresc == nil)
        c.accepta()
        #expect(c.refresc == nil && ajust.llegits == 0)
    }

    /// Un `preferencies.json` que no es pot llegir: no se sap si s'ha acceptat, i no es trepitja. Només es pot sortir.
    @Test func unFitxerQueNoEsPotLlegirNomesDeixaSortir() throws {
        let carpeta = try Carpeta()
        let text = #"{"versio": 9}"#
        try Data(text.utf8).write(to: carpeta.magatzem.fitxer)
        let demanats = Comptador()
        let c = consentiment(carpeta, AjustFals(), demanats)
        guard case let .error(motiu) = c.estat else { Issue.record("\(c.estat)"); return }
        #expect(motiu.contains("versió 9"))
        #expect(!c.potContinuar && !c.potAcceptar)
        // Revisió de la 0.29.0: la propera vegada no es pregunta (torna a sortir l'error), i diu on és el fitxer.
        #expect(c.textSortir.hasPrefix(motiu), "\(c.textSortir)")
        #expect(c.textSortir.contains(carpeta.magatzem.fitxer.path), "\(c.textSortir)")
        #expect(!c.textSortir.contains("preguntar"), "\(c.textSortir)")
        c.accepta()
        #expect(c.refresc == nil && demanats.n == 0)
        #expect(try String(contentsOf: carpeta.magatzem.fitxer, encoding: .utf8) == text)
    }

    /// Tancar l'editor o la Configuració amb la pantalla a la vista és no acceptar (la Configuració, decisió d'en David del
    /// 08/11/2026): surt, sense desar res. Amb el consentiment acceptat, o si no cal, la finestra es tanca i l'app continua.
    @Test func tancarUnaFinestraSenseConsentimentSurt() throws {
        let carpeta = try Carpeta()
        let demanats = Comptador()
        let c = consentiment(carpeta, AjustFals(), demanats)
        var sortides = 0
        #expect(!c.continuaEnTancarFinestra { sortides += 1 })
        #expect(sortides == 1 && c.estat == .pendent && carpeta.noms.isEmpty && demanats.n == 0)
        #expect(consentiment(carpeta, AjustFals(), demanats).estat == .pendent, "es torna a preguntar")
        c.accepta()
        #expect(c.continuaEnTancarFinestra { sortides += 1 })
        #expect(sortides == 1)

        // Un `preferencies.json` que no es pot llegir: tampoc no es pot continuar.
        let malmesa = try Carpeta()
        try Data(#"{"versio": 9}"#.utf8).write(to: malmesa.magatzem.fitxer)
        #expect(!consentiment(malmesa, AjustFals(), demanats).continuaEnTancarFinestra { sortides += 1 })
        #expect(sortides == 2)

        let senseCarpeta = ConsentimentRestauracio(magatzem: nil, creaEntornRefresc: nil)
        #expect(senseCarpeta.continuaEnTancarFinestra { sortides += 1 })
        #expect(sortides == 2)
    }

    /// Si «Accepta» no es pot desar, ho diu i no continua ni crea el refresc; es pot tornar a provar.
    @Test func siNoEsPotDesarNoContinua() throws {
        let carpeta = try Carpeta()
        let demanats = Comptador()
        let c = consentiment(carpeta, AjustFals(), demanats)
        var fet = false
        c.enContinuar { fet = true }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: carpeta.url.path)
        c.accepta()
        #expect(c.estat == .pendent && c.errorDesat != nil && c.potAcceptar)
        #expect(c.refresc == nil && demanats.n == 0 && !fet)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: carpeta.url.path)
        c.accepta()
        #expect(c.estat == .acceptat && c.errorDesat == nil && c.refresc != nil && fet)
    }
}
