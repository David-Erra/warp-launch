import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// docs/disseny.md, secció 11, 2.1 a 2.3. Amb un entorn fals: ni actualitzador, ni xarxa, ni rellotge de debò.

private typealias P = PoliticaActualitzacions
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
/// Segons des que el Mac és despert, lluny de l'arrencada: `acabaDArrencar` no compta.
private let t = TimeInterval(100_000)

private let tranquils = SituacioApp.Models(
    errorEnDesar: false, nomAMigEscriure: false, obrint: false, fullObert: false, conversesEnCurs: false, refrescant: false,
    ajustPerDesactivar: false, finestraVisible: false, canvisSenseDesar: false, potDesfer: false, segonsDesDelDarrerCanvi: nil)

@MainActor
private final class Banc {
    var potComprovar = true
    var auto = true
    var inactiu: TimeInterval = 1000
    var darrera: Date?
    var models = tranquils
    var ara = t0
    var crides: [String] = []
    let carpeta: URL
    let magatzem: MagatzemIntent
    /// Quantes vegades s'ha cridat el bloc, i l'intent que hi havia al disc cada vegada.
    var blocs: [IntentActualitzacio.Lectura] = []

    var entorn: Actualitzacions.Entorn {
        Actualitzacions.Entorn(
            comprovaIBaixa: { [unowned self] in crides.append("comprovaIBaixa") },
            nomesMira: { [unowned self] in crides.append("nomesMira") },
            actualitzaAra: { [unowned self] in crides.append("actualitzaAra") },
            potComprovar: { [unowned self] in potComprovar },
            automatiques: { [unowned self] in auto },
            posaAutomatiques: { [unowned self] in auto = $0 },
            segonsInactiu: { [unowned self] in inactiu },
            darreraComprovacio: { [unowned self] in darrera },
            models: { [unowned self] in models },
            rellotge: { [unowned self] in ara })
    }

    init() throws {
        carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-act-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        magatzem = MagatzemIntent(carpeta: carpeta)
    }

    deinit { try? FileManager.default.removeItem(at: carpeta) }

    /// L'app en marxa fa molta estona.
    func model(intent: IntentActualitzacio = IntentActualitzacio(), versio: String = "0.32.0", inici: TimeInterval = 0) -> Actualitzacions {
        Actualitzacions(entorn: entorn, magatzem: magatzem, intent: intent, ara: inici, versioActual: versio)
    }

    var aplica: @MainActor () -> Void {
        { [unowned self] in blocs.append(magatzem.carrega()) }
    }

    /// Fa que escriure l'intent falli (la carpeta passa a ser un fitxer).
    func trencaLaCarpeta() throws {
        try FileManager.default.removeItem(at: carpeta)
        try Data().write(to: carpeta)
    }
}

/// Un model amb la versió a punt.
@MainActor
private func aPunt(_ b: Banc, intent: IntentActualitzacio = IntentActualitzacio(), versio: String = "0.32.1") -> Actualitzacions {
    let m = b.model(intent: intent)
    m.rep(.aPunt(versio, aplica: b.aplica), ara: t)
    return m
}

@MainActor
@Suite struct ActualitzacionsTests {
    // MARK: - El menú

    @Test func elMenuComprovaOReinicia() throws {
        let b = try Banc()
        let m = b.model()
        #expect(m.textMenu == "Comprova si hi ha actualitzacions…" && m.accioMenu == .mostraIComprova)
        m.rep(.aPunt("0.32.1", aplica: b.aplica), ara: t)
        #expect(m.textMenu == "Reinicia i actualitza a la 0.32.1" && m.accioMenu == .reinicia)
    }

    /// Decisió 5 de Sparkle: passats 7 dies a punt, el menú ho diu. Abans, no. No fa res més.
    @Test func elMenuDiuElsDiesAPartirDeSet() throws {
        let b = try Banc()
        b.inactiu = 0
        let m = aPunt(b)
        b.ara = t0.addingTimeInterval(6 * 86_400 + 3000)
        m.vigila(ara: t)
        #expect(m.textMenu == "Reinicia i actualitza a la 0.32.1")
        b.ara = t0.addingTimeInterval(7 * 86_400)
        m.vigila(ara: t + 60)
        #expect(m.textMenu == "Reinicia i actualitza a la 0.32.1 (fa 7 dies)")
        #expect(b.blocs.isEmpty, "només l'avís: no aplica res")
        b.ara = t0.addingTimeInterval(9 * 86_400 + 100)
        m.vigila(ara: t + 120)
        #expect(m.textMenu == "Reinicia i actualitza a la 0.32.1 (fa 9 dies)")
    }

    @Test func elMenuNoDeixaFerResAMigAplicarOAmbUnMotiu() throws {
        let b = try Banc()
        let m = aPunt(b)
        b.models.obrint = true
        m.vigila(ara: t)
        #expect(m.accioMenu == .cap, "a mig obrir, no es pot reiniciar")
        b.models.obrint = false
        m.vigila(ara: t + 60)
        m.reinicia(ara: t + 120)
        #expect(m.aplicant && m.textMenu == "S'està actualitzant…" && m.accioMenu == .cap)
    }

    /// El menú porta a la pestanya d'actualitzacions, on es veu el resultat.
    @Test func elMenuPortaALaPestanyaGeneralIComprova() throws {
        let b = try Banc()
        let m = b.model()
        m.pestanyaConfiguracio = .pestanyesNoves
        m.mostraIComprova(ara: t)
        #expect(m.pestanyaConfiguracio == .actualitzacions && m.estat == .comprovant && b.crides == ["comprovaIBaixa"])
    }

    @Test func aquestaCopiaNoSActualitzaIHoDiu() throws {
        let m = Actualitzacions(noDisponible: .senseFeed)
        #expect(!m.disponible)
        #expect(m.textPeu == "Aquesta còpia no és una versió publicada i no s'actualitza sola.")
        #expect(m.boto == .comprovaAra(actiu: false))
        #expect(m.accioMenu == .mostraIComprova, "el menú porta a on es veu per què")
    }

    // MARK: - El que necessita el servei

    @Test func elMotiuDeReiniciarDemanatEsElDelsModels() throws {
        let b = try Banc()
        let m = b.model()
        #expect(m.motiuReiniciDemanat(ara: t) == nil)
        b.models.obrint = true
        #expect(m.motiuReiniciDemanat(ara: t) == .obrint)
        b.models.obrint = false
        b.models.finestraVisible = true
        #expect(m.motiuReiniciDemanat(ara: t) == nil, "una finestra no atura un reinici demanat")
    }

    /// La finestra de l'actualitzador reinicia sense passar per `aplica`: l'intent l'escriu el servei, com a demanat.
    @Test func elReiniciDeLaFinestraEscriuLIntent() throws {
        let b = try Banc()
        let m = b.model()
        m.reiniciaDesDeLaFinestra(versio: "0.32.1")
        guard case let .llegit(intent) = b.magatzem.carrega() else { Issue.record("sense intent"); return }
        #expect(intent.pendent == IntentActualitzacio.Pendent(objectiu: "0.32.1", tipus: .demanada, hora: t0))
    }

    /// Amb el bloc, l'actualitzador també avisa del reinici: no pot canviar una automàtica per una demanada.
    @Test func elReiniciDelBlocNoTrepitjaLIntent() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.reinicia(ara: t)
        #expect(m.aplicant)
        b.ara = t0.addingTimeInterval(5)
        m.reiniciaDesDeLaFinestra(versio: "0.32.1")
        guard case let .llegit(intent) = b.magatzem.carrega() else { Issue.record("sense intent"); return }
        #expect(intent.pendent?.hora == t0)
    }

    @Test func unaVersioQueNoEsPotLlegirNoEsEscriu() throws {
        let b = try Banc()
        b.model().reiniciaDesDeLaFinestra(versio: "1.0")
        #expect(b.magatzem.carrega() == .absent)
    }

    /// Si canvia si es pot comprovar, o la data de l'última comprovació, sense cap esdeveniment.
    @Test func unCanviDeLActualitzadorEsVeu() throws {
        let b = try Banc()
        let m = b.model()
        #expect(m.estat == .inicial(nil))
        b.darrera = t0
        m.canviEntorn()
        #expect(m.estat == .inicial(t0))
        b.potComprovar = false
        m.canviEntorn()
        #expect(m.boto == .comprovaAra(actiu: false))
        m.rep(.alDia, ara: t)
        let estat = m.estat
        b.darrera = t0.addingTimeInterval(9)
        m.canviEntorn()
        #expect(m.estat == estat, "«al dia» no es torna a «inicial»")
    }

    @Test func elDiagnosticDiuComEsta() throws {
        let b = try Banc()
        let m = b.model(intent: IntentActualitzacio(fallades: 1, versioFallada: "0.32.1"))
        #expect(m.textDiagnostic == "on, state inicial, automatic on, failures 1, failed version 0.32.1")
        b.auto = false
        m.posaAutomatiques(false)
        #expect(m.textDiagnostic.contains("automatic off"))
        let sense = Actualitzacions(noDisponible: .foraDAplicacions("/Users/qui/app.app"))
        #expect(sense.textDiagnostic == "off: not in /Applications (/Users/qui/app.app)")
        #expect(Actualitzacions(noDisponible: .senseFeed).textDiagnostic == "off: not a published build (no feed)")
    }

    // MARK: - Els estats i els textos

    @Test func inicialNoAfirmaRes() throws {
        let b = try Banc()
        let m = b.model()
        #expect(m.estat == .inicial(nil))
        #expect(m.text(avui: t0) == "Encara no s'ha comprovat")
        b.darrera = t0 - 2 * 3600
        let amb = b.model()
        #expect(amb.estat == .inicial(t0 - 2 * 3600))
        #expect(amb.text(avui: t0) == "Última comprovació: fa 2 h")
        #expect(!amb.text(avui: t0).contains("última versió"))
    }

    @Test func comprovaAmbInterruptorEncesBaixaIApagatNomesMira() throws {
        let b = try Banc()
        let m = b.model()
        m.comprova(ara: t)
        #expect(b.crides == ["comprovaIBaixa"])
        #expect(m.estat == .comprovant && m.text(avui: t0) == "Comprovant…" && m.boto == .comprovaAra(actiu: false))

        b.crides = []
        b.auto = false
        let n = b.model()
        n.comprova(ara: t)
        #expect(b.crides == ["nomesMira"])
    }

    @Test func noComprovaSiElServeiNoPot() throws {
        let b = try Banc()
        b.potComprovar = false
        let m = b.model()
        m.comprova(ara: t)
        #expect(b.crides.isEmpty && m.estat == .inicial(nil))
        #expect(m.boto == .comprovaAra(actiu: false))
    }

    @Test func alDiaNomesDespresDeLaResposta() throws {
        let b = try Banc()
        let m = b.model()
        m.comprova(ara: t)
        m.rep(.alDia, ara: t + 2)
        #expect(m.estat == .alDia(t0))
        #expect(m.text(avui: t0).hasPrefix("Tens l'última versió. Comprovat avui a les "))
        #expect(m.boto == .comprovaAra(actiu: true))
        #expect(m.text(avui: t0 + 3 * 86_400).contains("Comprovat el "))
    }

    @Test func unErrorSubstitueixAlDia() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.alDia, ara: t)
        m.rep(.error("no hi ha xarxa", demanat: false), ara: t + 10)
        #expect(m.estat == .error("no hi ha xarxa", t0))
        #expect(m.text(avui: t0) == "No s'ha pogut comprovar: no hi ha xarxa.")
        #expect(!m.text(avui: t0).contains("última versió"))
        #expect(m.boto == .comprovaAra(actiu: true))
    }

    @Test func unErrorSolNoAmagaUnaVersioTrobada() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.trobada("0.32.1"), ara: t)
        m.rep(.error("xarxa", demanat: false), ara: t)
        #expect(m.estat == .trobada("0.32.1"))
        m.rep(.error("xarxa", demanat: true), ara: t)
        #expect(m.estat == .error("xarxa", t0))
    }

    @Test func trobadaIActualitzaAra() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.trobada("0.32.1"), ara: t)
        #expect(m.text(avui: t0) == "Hi ha la 0.32.1." && m.boto == .actualitzaAra)
        m.actualitzaAra()
        #expect(b.crides == ["actualitzaAra"])
    }

    @Test func actualitzaAraNoFaResEnAltresEstats() throws {
        let b = try Banc()
        let m = b.model()
        m.actualitzaAra()
        #expect(b.crides.isEmpty)
    }

    @Test func baixant() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.baixant("0.32.1"), ara: t)
        #expect(m.text(avui: t0) == "Baixant la 0.32.1…" && m.boto == .cap)
        m.rep(.error("sense espai", demanat: false), ara: t)
        #expect(m.estat == .error("sense espai", t0), "una baixada que falla no es queda baixant")
    }

    @Test func baixantNoEsQuedaPerSempreSiElCicleAcaba() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.baixant("0.32.1"), ara: t)
        m.rep(.cicleAcabat, ara: t)
        #expect(m.estat == .inicial(nil))
    }

    @Test func aPuntITextos() throws {
        let b = try Banc()
        let m = aPunt(b)
        #expect(m.estat == .aPunt("0.32.1"))
        #expect(m.text(avui: t0) == "La 0.32.1 és a punt: s'aplicarà sola quan no facis servir l'app.")
        #expect(m.boto == .reinicia(actiu: true))
        #expect(m.textEspera == nil)
    }

    @Test func unaVersioAPuntNoLaTrepitjaRes() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.rep(.trobada("0.32.2"), ara: t)
        m.rep(.alDia, ara: t)
        m.rep(.baixant("0.32.2"), ara: t)
        m.rep(.error("x", demanat: true), ara: t)
        m.rep(.cicleAcabat, ara: t)
        #expect(m.estat == .aPunt("0.32.1"))
    }

    @Test func noDisponibleNoFaRes() throws {
        let m = Actualitzacions(noDisponible: .configuracioDeProva)
        #expect(m.estat == .noDisponible(P.NoDisponible.configuracioDeProva.text))
        #expect(m.boto == .comprovaAra(actiu: false))
        #expect(m.text(avui: t0) == "")
        #expect(m.textPeu == "Amb una configuració de prova, l'app no s'actualitza.")
        m.comprova(ara: t)
        m.vigila(ara: t)
        m.rep(.alDia, ara: t)
        m.reinicia(ara: t)
        m.posaAutomatiques(true)
        #expect(m.estat == .noDisponible(P.NoDisponible.configuracioDeProva.text))
        #expect(!m.automatiques)
    }

    @Test func elPeuAvisaAmbLInterruptorApagatIUnaVersioAPunt() throws {
        let b = try Banc()
        let m = aPunt(b)
        #expect(m.textPeu == Actualitzacions.textPeuBase)
        m.posaAutomatiques(false)
        #expect(b.auto == false && !m.automatiques)
        #expect(m.textPeu.hasSuffix("s'instal·la quan surts de l'app."))
    }

    // MARK: - Límits de temps

    @Test func comprovantCaducaAls180s() throws {
        let b = try Banc()
        b.darrera = t0
        let m = b.model()
        m.comprova(ara: t)
        m.vigila(ara: t + 179)
        #expect(m.estat == .comprovant)
        m.vigila(ara: t + 180)
        #expect(m.estat == .inicial(t0))
    }

    @Test func cicleAcabatTornaAInicial() throws {
        let b = try Banc()
        let m = b.model()
        m.comprova(ara: t)
        b.darrera = t0
        m.rep(.cicleAcabat, ara: t + 1)
        #expect(m.estat == .inicial(t0))
    }

    @Test func cicleAcabatNoTrepitjaElQueJaSeSap() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.alDia, ara: t)
        m.rep(.cicleAcabat, ara: t)
        #expect(m.estat == .alDia(t0))
    }

    @Test func comprovaNoFaResMentreBaixaOAmbUnaVersioTrobada() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.baixant("0.32.1"), ara: t)
        m.comprova(ara: t)
        m.rep(.trobada("0.32.2"), ara: t)
        m.comprova(ara: t)
        #expect(b.crides.isEmpty)
    }

    // MARK: - Quan s'aplica sola

    @Test func vigilaEsperaLaQuietudDe60s() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.vigila(ara: t)
        #expect(b.blocs.isEmpty)
        m.vigila(ara: t + 59)
        #expect(b.blocs.isEmpty)
        m.vigila(ara: t + 60)
        #expect(b.blocs.count == 1 && m.estat == .aplicant("0.32.1"))
        #expect(m.aplicant && m.text(avui: t0) == "S'està actualitzant…" && m.boto == .cap)
    }

    @Test func unMotiuTornaAComencarElCompte() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.vigila(ara: t)
        b.models.finestraVisible = true
        m.vigila(ara: t + 30)
        #expect(m.motiuAra == .finestraVisible && m.textEspera == "Ara no: hi ha una finestra de l'app oberta")
        b.models.finestraVisible = false
        m.vigila(ara: t + 60)
        m.vigila(ara: t + 119)
        #expect(b.blocs.isEmpty, "el compte torna a començar a t + 60")
        m.vigila(ara: t + 120)
        #expect(b.blocs.count == 1)
    }

    @Test func noAplicaAmbLInterruptorApagat() throws {
        let b = try Banc()
        b.auto = false
        let m = aPunt(b)
        m.vigila(ara: t)
        m.vigila(ara: t + 120)
        #expect(b.blocs.isEmpty)
        #expect(m.estat == .aPunt("0.32.1"), "es queda a punt: s'instal·la en sortir")
    }

    /// El que encara no es pot calcular és la inactivitat i el temps en marxa.
    @Test func elsMotiusDeTemps() throws {
        let b = try Banc()
        let m = b.model(inici: t - 10)
        m.rep(.aPunt("0.32.1", aplica: b.aplica), ara: t)
        m.vigila(ara: t)
        #expect(m.motiuAra == .acabaDArrencar)
        b.inactiu = 10
        m.vigila(ara: t + P.minimEnMarxa)
        #expect(m.motiuAra == .macEnUs && b.blocs.isEmpty)
        b.inactiu = P.inactivitatMinima
        m.vigila(ara: t + P.minimEnMarxa + 1)
        #expect(m.motiuAra == nil)
    }

    @Test func demanatSenseQuietud() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.reinicia(ara: t)
        #expect(b.blocs.count == 1 && m.estat == .aplicant("0.32.1"))
        guard case let .llegit(intent) = b.blocs[0] else { Issue.record("\(b.blocs[0])"); return }
        #expect(intent.pendent?.tipus == .demanada && intent.pendent?.objectiu == "0.32.1")
    }

    @Test func demanatEsperaNomesElsMotiusQueHiValen() throws {
        let b = try Banc()
        let m = aPunt(b)
        b.models.obrint = true
        m.reinicia(ara: t)
        #expect(b.blocs.isEmpty && m.motiuDemanatAra == .obrint && m.boto == .reinicia(actiu: false))
        b.models.obrint = false
        b.models.finestraVisible = true
        b.inactiu = 1
        m.reinicia(ara: t)
        #expect(b.blocs.count == 1, "una finestra o el Mac en ús no aturen el botó")
    }

    @Test func tresIntentsAmbUnaHoraEntreMig() throws {
        let b = try Banc()
        let m = aPunt(b)
        var ara = t
        for ronda in 1...P.maximIntents {
            m.vigila(ara: ara)
            m.vigila(ara: ara + 60)
            #expect(b.blocs.count == ronda)
            #expect(m.aplicant)
            ara += 60 + P.tempsAplicant
            m.vigila(ara: ara)
            #expect(m.estat == .aPunt("0.32.1"), "l'app no ha sortit: s'ha cancel·lat")
            if ronda < P.maximIntents {
                m.vigila(ara: ara + P.pausaEntreIntents - 60)
                m.vigila(ara: ara + P.pausaEntreIntents - 1)
                #expect(b.blocs.count == ronda, "la pausa d'1 h")
            }
            ara += P.pausaEntreIntents
        }
        m.vigila(ara: ara)
        m.vigila(ara: ara + 60)
        #expect(b.blocs.count == P.maximIntents, "ja no ho torna a provar sola")
        m.reinicia(ara: ara + 61)
        #expect(b.blocs.count == P.maximIntents + 1, "el botó sí")
    }

    @Test func aplicantCaducaAls60s() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.reinicia(ara: t)
        m.vigila(ara: t + 59)
        #expect(m.aplicant)
        m.vigila(ara: t + 60)
        #expect(m.estat == .aPunt("0.32.1") && !m.aplicant)
    }

    @Test func escriuLIntentAbansDeCadaCridaTambeAlReintent() throws {
        let b = try Banc()
        let m = aPunt(b)
        m.vigila(ara: t)
        m.vigila(ara: t + 60)
        guard case let .llegit(primer) = b.blocs[0] else { Issue.record("\(b.blocs)"); return }
        #expect(primer.pendent == IntentActualitzacio.Pendent(objectiu: "0.32.1", tipus: .automatica, hora: t0))

        // Es cancel·la, i es torna a provar amb el botó: l'hora és la nova, i el tipus, el d'aquesta crida.
        m.vigila(ara: t + 120)
        b.ara = t0 + 600
        m.reinicia(ara: t + 130)
        guard b.blocs.count == 2, case let .llegit(segon) = b.blocs[1] else { Issue.record("\(b.blocs)"); return }
        #expect(segon.pendent == IntentActualitzacio.Pendent(objectiu: "0.32.1", tipus: .demanada, hora: t0 + 600))
    }

    @Test func conservaLesFalladesAnteriorsEnEscriureLIntent() throws {
        let b = try Banc()
        let m = aPunt(b, intent: IntentActualitzacio(fallades: 1, versioFallada: "0.32.0"))
        m.reinicia(ara: t)
        guard case let .llegit(intent) = b.magatzem.carrega() else { Issue.record("sense intent"); return }
        #expect(intent.fallades == 1 && intent.versioFallada == "0.32.0" && intent.pendent != nil)
    }

    @Test func siNoPotEscriureNoCridaElBloc() throws {
        let b = try Banc()
        let m = aPunt(b)
        try b.trencaLaCarpeta()
        m.reinicia(ara: t)
        #expect(b.blocs.isEmpty && m.estat == .aPunt("0.32.1") && m.errorPreparant != nil)
        m.vigila(ara: t)
        m.vigila(ara: t + 60)
        #expect(b.blocs.isEmpty && m.estat == .aPunt("0.32.1"))
        m.vigila(ara: t + 120)
        #expect(b.blocs.isEmpty, "espera la pausa d'1 h, com qualsevol intent")
    }

    /// Una versió que `actualitzacio.json` no podria tornar a llegir: se'n perdrien les fallades.
    @Test func ambUnaVersioNoValidaNoEscriuNiCrida() throws {
        let b = try Banc()
        let m = aPunt(b, versio: "0.32.1-beta")
        m.reinicia(ara: t)
        #expect(b.blocs.isEmpty && m.errorPreparant != nil && m.estat == .aPunt("0.32.1-beta"))
        #expect(b.magatzem.carrega() == .absent)
    }

    @Test func installacioFallidaAturaElReiniciSol() throws {
        let b = try Banc()
        let m = aPunt(b, intent: IntentActualitzacio(fallades: 1, versioFallada: "0.32.1"))
        m.vigila(ara: t)
        m.vigila(ara: t + 60)
        #expect(b.blocs.isEmpty && m.motiuAra == .installacioFallida)
        #expect(m.textEspera == "Ara no: aquesta versió no s'ha pogut instal·lar sola")
        #expect(m.boto == .reinicia(actiu: true), "el botó sempre es pot")
        m.reinicia(ara: t + 61)
        #expect(b.blocs.count == 1)
    }

    @Test func installacioFallidaAmbDuesFalladesAturaQualsevolVersio() throws {
        let b = try Banc()
        let m = aPunt(b, intent: IntentActualitzacio(fallades: 2, versioFallada: "0.32.0"), versio: "0.32.5")
        m.vigila(ara: t)
        m.vigila(ara: t + 60)
        #expect(b.blocs.isEmpty && m.motiuAra == .installacioFallida)
    }

    @Test func elTextDeLaFalladaNomesMentreNoSInstalla() throws {
        let b = try Banc()
        #expect(b.model(intent: IntentActualitzacio(fallades: 1, versioFallada: "0.32.1"), versio: "0.32.0").textFallada
            == "La 0.32.1 no s'ha pogut instal·lar sola. Prova «Reinicia i actualitza», o reinstal·la-la.")
        #expect(b.model(intent: IntentActualitzacio(fallades: 1, versioFallada: "0.32.1"), versio: "0.32.1").textFallada == nil)
        #expect(b.model(versio: "0.32.0").textFallada == nil)
    }

    // MARK: - Postposada

    @Test func postposadaEsperaIEsCridaUnSolCop() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.trobada("0.32.1"), ara: t)
        b.models.fullObert = true
        m.rep(.postposada("0.32.1", aplica: b.aplica), ara: t)
        m.vigila(ara: t)
        #expect(b.blocs.isEmpty)
        b.models.fullObert = false
        m.vigila(ara: t + 60)
        #expect(b.blocs.count == 1 && m.estat == .aplicant("0.32.1"))
        m.vigila(ara: t + 120)
        m.vigila(ara: t + 180)
        #expect(b.blocs.count == 1, "una sola vegada")
        #expect(m.estat == .trobada("0.32.1"), "sense bloc: torna a la versió trobada")
    }

    @Test func postposadaNoLaAturenElsMotiusDelReiniciSol() throws {
        let b = try Banc()
        let m = b.model()
        b.inactiu = 1
        b.models.finestraVisible = true
        m.rep(.postposada("0.32.1", aplica: b.aplica), ara: t)
        m.vigila(ara: t)
        #expect(b.blocs.count == 1)
    }

    /// També al camí de la finestra: si no, una instal·lació que falla després de sortir no es veuria en tornar a obrir l'app.
    @Test func postposadaEscriuLIntentAbansDeLaCrida() throws {
        let b = try Banc()
        let m = b.model()
        m.rep(.postposada("0.32.1", aplica: b.aplica), ara: t)
        m.vigila(ara: t)
        guard b.blocs.count == 1, case let .llegit(intent) = b.blocs[0] else { Issue.record("\(b.blocs)"); return }
        #expect(intent.pendent == IntentActualitzacio.Pendent(objectiu: "0.32.1", tipus: .demanada, hora: t0))
    }

    @Test func postposadaSiNoPotEscriureNoCridaITornaAProvar() throws {
        let b = try Banc()
        let m = b.model()
        try b.trencaLaCarpeta()
        m.rep(.postposada("0.32.1", aplica: b.aplica), ara: t)
        m.vigila(ara: t)
        #expect(b.blocs.isEmpty && m.errorPreparant != nil && !m.aplicant)
        try FileManager.default.removeItem(at: b.carpeta)
        try FileManager.default.createDirectory(at: b.carpeta, withIntermediateDirectories: true)
        m.vigila(ara: t + 60)
        #expect(b.blocs.count == 1 && m.errorPreparant == nil && m.aplicant)
        m.vigila(ara: t + 120)
        #expect(b.blocs.count == 1, "una sola vegada")
    }

    // MARK: - Els dies

    @Test func elMenuAvisaPassats7Dies() throws {
        let b = try Banc()
        let m = aPunt(b)
        #expect(m.diesAPunt(avui: t0 + 6.9 * 86_400) == nil)
        #expect(m.diesAPunt(avui: t0 + 7 * 86_400) == 7)
        #expect(m.diesAPunt(avui: t0 + 8.5 * 86_400) == 8)
        m.reinicia(ara: t)
        #expect(m.diesAPunt(avui: t0 + 8 * 86_400) == nil, "ja no és a punt")
    }

    @Test func tornarAEstarAPuntDeLaMateixaVersioNoReiniciaElsDies() throws {
        let b = try Banc()
        let m = aPunt(b)
        b.ara = t0 + 86_400
        m.rep(.aPunt("0.32.1", aplica: b.aplica), ara: t)
        #expect(m.diesAPunt(avui: t0 + 7 * 86_400) == 7)
        m.rep(.aPunt("0.32.2", aplica: b.aplica), ara: t)
        #expect(m.diesAPunt(avui: t0 + 7 * 86_400) == nil, "una versió nova torna a començar")
    }
}
