import Foundation
import Testing
@testable import WarpLaunchCore

// Docs/disseny.md, secció 11, 2.2 i 2.4. Tot dades inventades: cap actualitzador ni cap fitxer.

private typealias P = PoliticaActualitzacions

private let modelsTranquils = SituacioApp.Models(
    errorEnDesar: false, nomAMigEscriure: false, obrint: false, fullObert: false, conversesEnCurs: false, refrescant: false,
    ajustPerDesactivar: false, finestraVisible: false, canvisSenseDesar: false, potDesfer: false, segonsDesDelDarrerCanvi: nil)
private let tranquil = SituacioApp(models: modelsTranquils, segonsEnMarxa: 1000, segonsInactiu: 1000, installacioFallida: false)

/// La situació on només hi ha aquest motiu.
private func nomes(_ motiu: P.Motiu) -> SituacioApp {
    var s = tranquil
    switch motiu {
    case .errorEnDesar: s.models.errorEnDesar = true
    case .nomAMigEscriure: s.models.nomAMigEscriure = true
    case .obrint: s.models.obrint = true
    case .fullObert: s.models.fullObert = true
    case .conversesEnCurs: s.models.conversesEnCurs = true
    case .refrescant: s.models.refrescant = true
    case .ajustPerDesactivar: s.models.ajustPerDesactivar = true
    case .finestraVisible: s.models.finestraVisible = true
    case .canvisSenseDesar: s.models.canvisSenseDesar = true
    case .desfesRecent:
        s.models.potDesfer = true
        s.models.segonsDesDelDarrerCanvi = 10
    case .acabaDArrencar: s.segonsEnMarxa = 10
    case .macEnUs: s.segonsInactiu = 10
    case .installacioFallida: s.installacioFallida = true
    }
    return s
}

private let paquetBo = P.Paquet(arguments: .normals, ruta: "/Applications/Warp Launch.app", identificador: "cat.exemple.prova", teFeed: true,
                                potEscriure: true, esDeLUsuari: true, actualitzadorCompatible: true)

@Suite struct PoliticaActualitzacionsTests {
    @Test func senseCapMotiuEsPot() {
        #expect(P.motiuEspera(tranquil, demanat: false) == nil)
        #expect(P.motiuEspera(tranquil, demanat: true) == nil)
    }

    @Test(arguments: P.Motiu.allCases)
    func cadaMotiuAutomaticIDemanat(motiu: PoliticaActualitzacions.Motiu) {
        #expect(P.motiuEspera(nomes(motiu), demanat: false) == motiu)
        #expect(P.motiuEspera(nomes(motiu), demanat: true) == (motiu.valTambeDemanat ? motiu : nil))
    }

    @Test func elsQueAturenTambeElBotoSonElsDeLaTaula() {
        let demanats = P.Motiu.allCases.filter(\.valTambeDemanat)
        #expect(demanats == [.errorEnDesar, .nomAMigEscriure, .obrint, .fullObert, .conversesEnCurs, .refrescant, .ajustPerDesactivar])
    }

    /// Amb tots els motius alhora, surt cadascun quan es treuen els d'abans: l'ordre és el de la taula.
    @Test func ordre() {
        let ordre: [P.Motiu] = [.errorEnDesar, .nomAMigEscriure, .obrint, .fullObert, .conversesEnCurs, .refrescant, .ajustPerDesactivar,
                                .finestraVisible, .canvisSenseDesar, .desfesRecent, .acabaDArrencar, .macEnUs, .installacioFallida]
        #expect(P.Motiu.allCases == ordre)
        var s = SituacioApp(models: SituacioApp.Models(
            errorEnDesar: true, nomAMigEscriure: true, obrint: true, fullObert: true, conversesEnCurs: true, refrescant: true,
            ajustPerDesactivar: true, finestraVisible: true, canvisSenseDesar: true, potDesfer: true, segonsDesDelDarrerCanvi: 1),
            segonsEnMarxa: 1, segonsInactiu: 1, installacioFallida: true)
        #expect(P.motiuEspera(s, demanat: false) == .errorEnDesar)
        s.models.errorEnDesar = false
        #expect(P.motiuEspera(s, demanat: false) == .nomAMigEscriure)
        s.models.nomAMigEscriure = false
        s.models.obrint = false
        #expect(P.motiuEspera(s, demanat: false) == .fullObert)
        s.models.fullObert = false
        s.models.conversesEnCurs = false
        s.models.refrescant = false
        s.models.ajustPerDesactivar = false
        #expect(P.motiuEspera(s, demanat: true) == nil, "la resta no atura el botó")
        #expect(P.motiuEspera(s, demanat: false) == .finestraVisible)
        s.models.finestraVisible = false
        s.models.canvisSenseDesar = false
        #expect(P.motiuEspera(s, demanat: false) == .desfesRecent)
        s.models.potDesfer = false
        #expect(P.motiuEspera(s, demanat: false) == .acabaDArrencar)
        s.segonsEnMarxa = 1000
        #expect(P.motiuEspera(s, demanat: false) == .macEnUs)
        s.segonsInactiu = 1000
        #expect(P.motiuEspera(s, demanat: false) == .installacioFallida)
    }

    @Test func elsLimitsDeTemps() {
        var s = tranquil
        s.segonsEnMarxa = P.minimEnMarxa - 1
        #expect(P.motiuEspera(s, demanat: false) == .acabaDArrencar)
        s.segonsEnMarxa = P.minimEnMarxa
        s.segonsInactiu = P.inactivitatMinima - 1
        #expect(P.motiuEspera(s, demanat: false) == .macEnUs)
        s.segonsInactiu = P.inactivitatMinima
        #expect(P.motiuEspera(s, demanat: false) == nil)
    }

    /// Un rellotge que ha anat molt enrere no pot aturar el reinici fins que torni a arribar a aquella hora.
    @Test func desfesRecentAmbElRellotgeEnrere() {
        var s = tranquil
        s.models.potDesfer = true
        s.models.segonsDesDelDarrerCanvi = -60
        #expect(P.motiuEspera(s, demanat: false) == .desfesRecent, "pocs segons: encara és recent")
        s.models.segonsDesDelDarrerCanvi = -P.limitDesfes
        #expect(P.motiuEspera(s, demanat: false) == nil)
        s.models.segonsDesDelDarrerCanvi = -30 * 86_400
        #expect(P.motiuEspera(s, demanat: false) == nil)
    }

    @Test func desfesRecentNomesAmbPasIUltimCanviDeFaMenysDUnaHora() {
        var s = tranquil
        s.models.potDesfer = true
        #expect(P.motiuEspera(s, demanat: false) == nil, "sense cap canvi en aquesta sessió")
        s.models.segonsDesDelDarrerCanvi = P.limitDesfes - 1
        #expect(P.motiuEspera(s, demanat: false) == .desfesRecent)
        s.models.segonsDesDelDarrerCanvi = P.limitDesfes
        #expect(P.motiuEspera(s, demanat: false) == nil)
        s.models.potDesfer = false
        s.models.segonsDesDelDarrerCanvi = 1
        #expect(P.motiuEspera(s, demanat: false) == nil, "sense res per desfer")
    }

    @Test func lesConstantsDelDisseny() {
        #expect(P.quietud == 60 && P.inactivitatMinima == 120 && P.minimEnMarxa == 300 && P.tempsAplicant == 60)
        #expect(P.pausaEntreIntents == 3600 && P.maximIntents == 3 && P.limitDesfes == 3600 && P.margeReobertura == 300)
        #expect(P.diesAvis == 7 && P.tempsComprovant == 180 && P.carpetaAplicacions == "/Applications/")
    }

    // MARK: - Quan no s'actualitza mai

    @Test func unaAppInstalladaIPublicadaEsPotActualitzar() {
        #expect(P.motiuNoDisponible(paquetBo) == nil)
    }

    @Test func cadaCasDeNoDisponible() {
        var p = paquetBo
        p.arguments = .deProva
        #expect(P.motiuNoDisponible(p) == .configuracioDeProva)
        p.arguments = .incorrectes
        #expect(P.motiuNoDisponible(p) == .senseConfiguracio)

        p = paquetBo
        p.ruta = "/x/.build/debug/WarpLaunch"
        #expect(P.motiuNoDisponible(p) == .foraDeLPaquet)
        p = paquetBo
        p.identificador = nil
        #expect(P.motiuNoDisponible(p) == .foraDeLPaquet)

        p = paquetBo
        p.ruta = "/x/build/Warp Launch.app"
        #expect(P.motiuNoDisponible(p) == .foraDAplicacions("/x/build/Warp Launch.app"))
        p.ruta = "/private/var/folders/ab/AppTranslocation/C1/d/Warp Launch.app"
        #expect(P.motiuNoDisponible(p) == .foraDAplicacions(p.ruta), "traslladada per macOS")

        p = paquetBo
        p.teFeed = false
        #expect(P.motiuNoDisponible(p) == .senseFeed)

        p = paquetBo
        p.potEscriure = false
        #expect(P.motiuNoDisponible(p) == .dUnAltreUsuari)
        p = paquetBo
        p.esDeLUsuari = false
        #expect(P.motiuNoDisponible(p) == .dUnAltreUsuari)

        p = paquetBo
        p.actualitzadorCompatible = false
        #expect(P.motiuNoDisponible(p) == .incompatible)
    }

    /// Una còpia de prova no continua mirant res més: `--config` mana sobre tota la resta.
    @Test func laConfiguracioDeProvaManaSobreLaResta() {
        let p = P.Paquet(arguments: .deProva, ruta: "/x/WarpLaunch", identificador: nil, teFeed: false, potEscriure: false, esDeLUsuari: false,
                         actualitzadorCompatible: false)
        #expect(P.motiuNoDisponible(p) == .configuracioDeProva)
    }

    @Test func elsTextos() {
        #expect(P.NoDisponible.foraDAplicacions("/x/y.app").text
            == "Per actualitzar-se sola, l'app ha de ser a Aplicacions. Ara és a /x/y.app.")
        #expect(P.NoDisponible.senseFeed.text == "Aquesta còpia no és una versió publicada i no s'actualitza sola.")
        #expect(P.Motiu.allCases.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: - La URL del fitxer

    private static let feed = "https://github.com/exemple/warp-launch/releases/latest/download/appcast.xml"
    private static let local = "http://127.0.0.1:48917/appcast.xml"

    @Test(arguments: [
        (feed, "https://github.com/exemple/warp-launch/releases/download/v0.32.0/WarpLaunch-0.32.0.zip"),
        (local, "http://127.0.0.1:48917/WarpLaunch-0.31.91.zip"),
    ])
    func enclosureDeLaCarpetaDelFeed(feed: String, enclosure: String) {
        #expect(P.enclosureValid(feed: feed, enclosure: enclosure))
    }

    @Test(arguments: [
        "https://exemple.net/warp-launch/releases/download/v0.32.0/WarpLaunch-0.32.0.zip",          // altre domini
        "https://github.com/altre/warp-launch/releases/download/v0.32.0/WarpLaunch-0.32.0.zip",     // altre compte
        "https://github.com/exemple/warp-launch-falsa/releases/download/v0.32.0/WarpLaunch.zip",    // repo amb el mateix principi
        "https://github.com/exemple/warp-launch/archive/v0.32.0.zip",                                // altra ruta
        "https://github.com/exemple/warp-launch/releases/latest/download/WarpLaunch.zip",            // sense canviar «latest»
        "http://github.com/exemple/warp-launch/releases/download/v0.32.0/WarpLaunch.zip",            // sense https
        "https://github.com/exemple/warp-launch/releases/download/../../../altre/repo/WarpLaunch.zip", // surt de la carpeta
        "https://github.com/exemple/warp-launch/releases/download/v0.32.0/%2e%2e/WarpLaunch.zip",    // surt, codificat
        "https://github.com/exemple/warp-launch/releases/download/v0.32.0//WarpLaunch.zip",          // tros buit
        "https://github.com/exemple/warp-launch/releases/download/x.zip?u=https://exemple.net",      // amb consulta
        "https://github.com/exemple/warp-launch/releases/download/x.zip#a",
        "https://github.com/exemple/warp-launch/releases/download/",                                 // la carpeta sola
        "",
    ])
    func enclosureRefusada(enclosure: String) {
        #expect(!P.enclosureValid(feed: Self.feed, enclosure: enclosure))
    }

    @Test func enclosureAmbUnFeedSenseFitxerOSenseEsquema() {
        #expect(!P.enclosureValid(feed: "https://exemple.net/", enclosure: "https://exemple.net/x.zip"))
        #expect(!P.enclosureValid(feed: "x/y.xml", enclosure: "x/z.zip"))
        #expect(!P.enclosureValid(feed: "", enclosure: ""))
    }

    @Test func enclosureLocalNoServeixPerAUnAltrePort() {
        #expect(!P.enclosureValid(feed: Self.local, enclosure: "http://127.0.0.1:48918/x.zip"))
    }

    // MARK: - Errors i versions

    @Test(arguments: [(1001, false), (4007, false), (1, true), (2001, true), (4008, true), (0, true)])
    func errorsVisibles(codi: Int, visible: Bool) {
        #expect(P.esErrorVisible(codi: codi) == visible)
    }

    private func v(_ text: String) throws -> P.Versio { try #require(P.Versio(text), "«\(text)»") }

    @Test func compararVersions() throws {
        #expect(try v("0.31.9") < v("0.31.10"))
        #expect(try v("0.31.4") < v("1.0.0"))
        #expect(try v("0.31.4") < v("0.32.0"))
        #expect(try v("0.31.4") == v("0.31.4"))
        #expect(try !(v("0.31.10") < v("0.31.9")))
        #expect(try v("0.32.0") > v("0.31.99"))
    }

    @Test(arguments: ["", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "1..3", "-1.2.3", "+1.2.3", " 1.2.3", "1.2.3-beta", "99999999999999999999.0.0", "٣.1.2"])
    func versionsNoValides(text: String) {
        #expect(P.Versio(text) == nil)
    }
}
