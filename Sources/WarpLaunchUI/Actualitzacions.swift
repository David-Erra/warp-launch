import Foundation
import Observation
import WarpLaunchCore

/// L'actualització automàtica de l'app, sense l'actualitzador (docs/disseny.md, secció 11, 2.1 a 2.3): els estats, quan es reinicia
/// sola, els intents i els textos. Tot el que toca fora arriba per `Entorn`, que omple el servei de l'app. `ara`, a totes les
/// funcions: els segons del Mac despert (`systemUptime`), perquè el Mac adormit no compti.
@MainActor
@Observable
public final class Actualitzacions {
    public struct Entorn {
        /// Mira si hi ha versió, i si n'hi ha la baixa i la deixa a punt.
        public var comprovaIBaixa: @MainActor () -> Void
        /// Només mira si n'hi ha, sense baixar res.
        public var nomesMira: @MainActor () -> Void
        /// Mostra la finestra de l'actualitzador.
        public var actualitzaAra: @MainActor () -> Void
        public var potComprovar: @MainActor () -> Bool
        public var automatiques: @MainActor () -> Bool
        public var posaAutomatiques: @MainActor (Bool) -> Void
        public var segonsInactiu: @MainActor () -> TimeInterval
        /// Quan es va mirar per última vegada, si mai.
        public var darreraComprovacio: @MainActor () -> Date?
        /// Què diuen els models de l'app.
        public var models: @MainActor () -> SituacioApp.Models
        /// L'hora del rellotge, per a l'intent i per als textos.
        public var rellotge: @MainActor () -> Date

        public init(comprovaIBaixa: @escaping @MainActor () -> Void, nomesMira: @escaping @MainActor () -> Void,
                    actualitzaAra: @escaping @MainActor () -> Void, potComprovar: @escaping @MainActor () -> Bool,
                    automatiques: @escaping @MainActor () -> Bool, posaAutomatiques: @escaping @MainActor (Bool) -> Void,
                    segonsInactiu: @escaping @MainActor () -> TimeInterval, darreraComprovacio: @escaping @MainActor () -> Date?,
                    models: @escaping @MainActor () -> SituacioApp.Models, rellotge: @escaping @MainActor () -> Date) {
            self.comprovaIBaixa = comprovaIBaixa
            self.nomesMira = nomesMira
            self.actualitzaAra = actualitzaAra
            self.potComprovar = potComprovar
            self.automatiques = automatiques
            self.posaAutomatiques = posaAutomatiques
            self.segonsInactiu = segonsInactiu
            self.darreraComprovacio = darreraComprovacio
            self.models = models
            self.rellotge = rellotge
        }
    }

    /// El que explica el servei que ha passat.
    public enum Esdeveniment {
        case trobada(String), alDia, baixant(String), cicleAcabat
        /// A punt per instal·lar. `aplica` instal·la i reobre l'app.
        case aPunt(String, aplica: @MainActor () -> Void)
        /// Reinici demanat des de la finestra de l'actualitzador, ajornat per un motiu, i la versió. Es fa una sola vegada.
        case postposada(String, aplica: @MainActor () -> Void)
        case error(String, demanat: Bool)
    }

    public enum Estat: Equatable {
        /// Sense cap comprovació en aquesta sessió: no afirma res.
        case inicial(Date?)
        case comprovant
        /// Només després d'una comprovació d'aquesta sessió que ha dit que no hi ha res de nou.
        case alDia(Date)
        case trobada(String)
        case baixant(String)
        case aPunt(String)
        case aplicant(String)
        case error(String, Date)
        /// El motiu, que surt al peu de la secció.
        case noDisponible(String)
    }

    /// El botó de la fila.
    public enum Boto: Equatable {
        case cap
        case comprovaAra(actiu: Bool)
        case actualitzaAra
        case reinicia(actiu: Bool)
    }

    private typealias P = PoliticaActualitzacions

    public private(set) var estat: Estat {
        didSet {
            guard estat != oldValue else { return }
            Registre.actualitzacions.notice("estat \(Self.nom(self.estat), privacy: .public)")
        }
    }
    /// Per què no es reinicia sola ara. Es posa al dia a cada `vigila`.
    public private(set) var motiuAra: PoliticaActualitzacions.Motiu?
    /// Per què no es pot reiniciar ni amb el botó.
    public private(set) var motiuDemanatAra: PoliticaActualitzacions.Motiu?
    public private(set) var automatiques: Bool
    /// No s'ha pogut escriure l'intent, i per això no s'ha aplicat.
    public private(set) var errorPreparant: String?
    /// Puja quan canvia alguna cosa de l'actualitzador que no arriba com a esdeveniment (`canviEntorn`): si es pot comprovar, per al botó.
    private var revisio = 0

    @ObservationIgnored private let motiuNoDisponible: PoliticaActualitzacions.NoDisponible?
    @ObservationIgnored private let entorn: Entorn?
    @ObservationIgnored private let magatzem: MagatzemIntent?
    /// `ara` en crear el model: des de quan corre l'app.
    @ObservationIgnored private let arrencada: TimeInterval
    @ObservationIgnored private let versioActual: String
    @ObservationIgnored private var intent: IntentActualitzacio
    @ObservationIgnored private var bloc: (@MainActor () -> Void)?
    @ObservationIgnored private var postposat: (versio: String, aplica: @MainActor () -> Void)?
    @ObservationIgnored private var aPuntDes: Date?
    @ObservationIgnored private var comprovantDes: TimeInterval?
    @ObservationIgnored private var aplicantDes: TimeInterval?
    @ObservationIgnored private var quietDes: TimeInterval?
    @ObservationIgnored private var pausaFins: TimeInterval?
    @ObservationIgnored private var intents = 0

    /// L'app es pot actualitzar: `intent` és el resultat de `IntentActualitzacio.enArrencar`.
    public init(entorn: Entorn, magatzem: MagatzemIntent, intent: IntentActualitzacio, ara: TimeInterval, versioActual: String) {
        self.entorn = entorn
        self.magatzem = magatzem
        self.intent = intent
        arrencada = ara
        self.versioActual = versioActual
        motiuNoDisponible = nil
        estat = .inicial(entorn.darreraComprovacio())
        automatiques = entorn.automatiques()
    }

    /// Aquesta còpia no s'actualitza mai: no hi ha servei, ni es llegeix ni s'escriu res.
    public init(noDisponible motiu: PoliticaActualitzacions.NoDisponible) {
        motiuNoDisponible = motiu
        entorn = nil
        magatzem = nil
        intent = IntentActualitzacio()
        arrencada = 0
        versioActual = ""
        estat = .noDisponible(motiu.text)
        automatiques = false
    }

    /// Entre el bloc i la sortida: no es pot començar a obrir res (`Obertura.aplicantActualitzacio`).
    public var aplicant: Bool {
        if case .aplicant = estat { true } else { false }
    }

    // MARK: - El que demana l'usuari

    /// «Comprova ara». Amb l'interruptor encès, la versió que trobi la baixa (decisió 4 de Sparkle); apagat, només mira.
    public func comprova(ara: TimeInterval) {
        guard let entorn, entorn.potComprovar() else { return }
        switch estat {
        case .inicial, .alDia, .error: break
        default: return
        }
        estat = .comprovant
        comprovantDes = ara
        if entorn.automatiques() {
            entorn.comprovaIBaixa()
        } else {
            entorn.nomesMira()
        }
    }

    /// «Actualitza ara».
    public func actualitzaAra() {
        guard let entorn, case .trobada = estat else { return }
        entorn.actualitzaAra()
    }

    /// «Reinicia i actualitza»: de seguida, si res ho impedeix. Si no, diu per què.
    public func reinicia(ara: TimeInterval) {
        guard let entorn, case let .aPunt(versio) = estat else { return }
        let situacio = situacio(entorn, ara: ara, candidat: versio)
        posaMotius(situacio)
        guard motiuDemanatAra == nil else { return }
        _ = aplica(.demanada, versio: versio, bloc: bloc, entorn: entorn, ara: ara)
    }

    public func posaAutomatiques(_ valor: Bool) {
        guard let entorn else { return }
        entorn.posaAutomatiques(valor)
        automatiques = entorn.automatiques()
        if !automatiques { quietDes = nil }
    }

    /// El que pregunta el servei: per què no es pot reiniciar ara, ni que ho demani l'usuari.
    public func motiuReiniciDemanat(ara: TimeInterval) -> PoliticaActualitzacions.Motiu? {
        guard let entorn else { return nil }
        return motiu(entorn, ara: ara, candidat: nil, demanat: true)
    }

    /// La finestra de l'actualitzador reinicia l'app: l'intent, per saber en arrencar si ha anat bé. Amb el bloc, ja l'ha escrit `aplica`.
    public func reiniciaDesDeLaFinestra(versio: String) {
        guard let entorn, let magatzem, !aplicant, PoliticaActualitzacions.Versio(versio) != nil else { return }
        var nou = intent
        nou.pendent = IntentActualitzacio.Pendent(objectiu: versio, tipus: .demanada, hora: entorn.rellotge())
        do {
            try magatzem.desa(nou)
            intent = nou
        } catch {
            Registre.actualitzacions.error("no s'ha pogut escriure l'intent: \(error, privacy: .public)")
        }
    }

    /// L'actualitzador ha canviat sense cap esdeveniment: si es pot comprovar, o quan es va comprovar per última vegada.
    public func canviEntorn() {
        guard let entorn else { return }
        revisio &+= 1
        if case .inicial = estat { estat = .inicial(entorn.darreraComprovacio()) }
    }

    // MARK: - El que passa

    /// El que explica el servei.
    public func rep(_ esdeveniment: Esdeveniment, ara: TimeInterval) {
        guard let entorn else { return }
        let ocupat = ocupat
        switch esdeveniment {
        case let .trobada(versio):
            guard !ocupat else { return }
            estat = .trobada(versio)
        case .alDia:
            guard !ocupat, !baixant else { return }
            estat = .alDia(entorn.rellotge())
        case let .baixant(versio):
            guard !ocupat else { return }
            estat = .baixant(versio)
        case .cicleAcabat:
            if estat == .comprovant || baixant { tornaAInicial(entorn) }
        case let .aPunt(versio, aplica):
            if case .aPunt(versio) = estat {} else { aPuntDes = entorn.rellotge() }
            bloc = aplica
            quietDes = nil
            estat = .aPunt(versio)
        case let .postposada(versio, aplica):
            postposat = (versio, aplica)
        case let .error(missatge, demanat):
            guard !ocupat else { return }
            // Una comprovació que falla sola no amaga que ja se sap d'una versió.
            if !demanat, case .trobada = estat { return }
            estat = .error(missatge, entorn.rellotge())
        }
    }

    /// Cada minut (`llegeixPeriodicament`). Comprova els límits de temps i, si ningú no fa servir ni el Mac ni l'app, aplica
    /// la versió que és a punt.
    public func vigila(ara: TimeInterval) {
        guard let entorn else { return }
        caducaEsperes(entorn, ara: ara)

        // Si no es pot escriure l'intent, no es crida: es torna a provar al minut següent.
        if let postposat, motiu(entorn, ara: ara, candidat: nil, demanat: true) == nil,
           aplica(.demanada, versio: postposat.versio, bloc: postposat.aplica, entorn: entorn, ara: ara) {
            self.postposat = nil
        }

        guard case let .aPunt(versio) = estat else {
            motiuAra = nil
            motiuDemanatAra = nil
            quietDes = nil
            return
        }
        automatiques = entorn.automatiques()
        let situacio = situacio(entorn, ara: ara, candidat: versio)
        posaMotius(situacio)
        guard automatiques, intents < P.maximIntents, pausaFins.map({ ara >= $0 }) ?? true, motiuAra == nil else {
            quietDes = nil
            return
        }
        guard let quiet = quietDes else {
            quietDes = ara
            return
        }
        guard ara - quiet >= P.quietud else { return }
        if !aplica(.automatica, versio: versio, bloc: bloc, entorn: entorn, ara: ara) {
            intents += 1
            pausaFins = ara + P.pausaEntreIntents
        }
    }

    // MARK: - Detalls

    private var ocupat: Bool {
        switch estat {
        case .aPunt, .aplicant: true
        default: false
        }
    }

    private var baixant: Bool {
        if case .baixant = estat { true } else { false }
    }

    /// Els límits: `.comprovant`, si l'actualitzador no respon mai; `.aplicant`, si l'app no ha sortit: s'ha cancel·lat.
    private func caducaEsperes(_ entorn: Entorn, ara: TimeInterval) {
        switch estat {
        case .comprovant:
            if let comprovantDes, ara - comprovantDes >= P.tempsComprovant { tornaAInicial(entorn) }
        case let .aplicant(versio):
            guard let aplicantDes, ara - aplicantDes >= P.tempsAplicant else { return }
            intents += 1
            pausaFins = ara + P.pausaEntreIntents
            self.aplicantDes = nil
            quietDes = nil
            estat = bloc != nil ? .aPunt(versio) : .trobada(versio)
        default: break
        }
    }

    private func tornaAInicial(_ entorn: Entorn) {
        comprovantDes = nil
        estat = .inicial(entorn.darreraComprovacio())
    }

    private func situacio(_ entorn: Entorn, ara: TimeInterval, candidat: String?) -> SituacioApp {
        SituacioApp(models: entorn.models(), segonsEnMarxa: ara - arrencada, segonsInactiu: entorn.segonsInactiu(),
                    installacioFallida: candidat.map(intent.bloquejaAutomatic) ?? false)
    }

    private func motiu(_ entorn: Entorn, ara: TimeInterval, candidat: String?, demanat: Bool) -> P.Motiu? {
        P.motiuEspera(situacio(entorn, ara: ara, candidat: candidat), demanat: demanat)
    }

    private func posaMotius(_ situacio: SituacioApp) {
        motiuAra = P.motiuEspera(situacio, demanat: false)
        motiuDemanatAra = P.motiuEspera(situacio, demanat: true)
    }

    /// Escriu l'intent i crida el bloc, en aquest ordre i cada vegada: si no es pot escriure, no es crida.
    private func aplica(_ tipus: IntentActualitzacio.Tipus, versio: String, bloc: (@MainActor () -> Void)?, entorn: Entorn,
                        ara: TimeInterval) -> Bool {
        guard let bloc, let magatzem else { return false }
        // `actualitzacio.json` no la podria tornar a llegir: es perdrien les fallades, i ho tornaria a provar sense límit.
        guard P.Versio(versio) != nil else {
            errorPreparant = "la versió «\(versio)» no té la forma que toca"
            Registre.actualitzacions.error("versió no vàlida: \(versio, privacy: .public)")
            return false
        }
        var nou = intent
        nou.pendent = IntentActualitzacio.Pendent(objectiu: versio, tipus: tipus, hora: entorn.rellotge())
        do {
            try magatzem.desa(nou)
        } catch {
            errorPreparant = "\(error)"
            Registre.actualitzacions.error("no s'ha pogut escriure l'intent: \(error, privacy: .public)")
            return false
        }
        errorPreparant = nil
        intent = nou
        aplicantDes = ara
        quietDes = nil
        estat = .aplicant(versio)
        bloc()
        return true
    }

    private static func nom(_ estat: Estat) -> String {
        switch estat {
        case .inicial: "inicial"
        case .comprovant: "comprovant"
        case .alDia: "al dia"
        case let .trobada(versio): "trobada \(versio)"
        case let .baixant(versio): "baixant \(versio)"
        case let .aPunt(versio): "a punt \(versio)"
        case let .aplicant(versio): "aplicant \(versio)"
        case .error: "error"
        case .noDisponible: "no disponible"
        }
    }

    // MARK: - Textos

    /// Per a l'informe del diagnòstic, que és en anglès.
    public var textDiagnostic: String {
        if let motiuNoDisponible { return "off: \(motiuNoDisponible.diagnostic)" }
        return "on, state \(Self.nom(estat)), automatic \(automatiques ? "on" : "off"), failures \(intent.fallades)"
            + (intent.versioFallada.map { ", failed version \($0)" } ?? "")
    }

    /// El text de la fila «Estat». `avui`: l'hora de mirar-ho, per als textos.
    public func text(avui: Date) -> String {
        switch estat {
        case let .inicial(ultima):
            ultima.map { "Última comprovació: \(Self.fa($0, avui: avui))" } ?? "Encara no s'ha comprovat"
        case .comprovant: "Comprovant…"
        case let .alDia(quan): "Tens l'última versió. Comprovat \(Self.quan(quan, avui: avui))."
        case let .trobada(versio): "Hi ha la \(versio)."
        case let .baixant(versio): "Baixant la \(versio)…"
        case let .aPunt(versio): "La \(versio) és a punt: s'aplicarà sola quan no facis servir l'app."
        case .aplicant: "S'està actualitzant…"
        case let .error(missatge, _): "No s'ha pogut comprovar: \(missatge)."
        case .noDisponible: ""
        }
    }

    /// El motiu de no reiniciar ara, amb una versió a punt.
    public var textEspera: String? {
        guard case .aPunt = estat, let motiuAra else { return nil }
        return "Ara no: \(motiuAra.text)"
    }

    /// Una versió no s'ha pogut instal·lar sola, i encara no s'ha instal·lat.
    public var textFallada: String? {
        guard let fallada = intent.versioFallada, let actual = P.Versio(versioActual), let versio = P.Versio(fallada), actual < versio else { return nil }
        return "La \(fallada) no s'ha pogut instal·lar sola. Prova «Reinicia i actualitza», o reinstal·la-la."
    }

    public static let textPeuBase = "Un cop al dia, l'app mira a GitHub si hi ha una versió nova i s'hi actualitza sola quan no la fas servir. "
        + "GitHub veu la teva adreça IP i la versió de l'app. Warp i Claude no es tanquen."

    /// El peu de la secció. Sense servei, només el motiu.
    public var textPeu: String {
        if case let .noDisponible(motiu) = estat { return motiu }
        guard case .aPunt = estat, !automatiques else { return Self.textPeuBase }
        return Self.textPeuBase + " Amb l'interruptor apagat, no es reinicia sola: s'instal·la quan surts de l'app."
    }

    public var boto: Boto {
        switch estat {
        case .inicial, .alDia, .error: .comprovaAra(actiu: revisio >= 0 && entorn?.potComprovar() == true)
        case .comprovant, .noDisponible: .comprovaAra(actiu: false)
        case .trobada: .actualitzaAra
        case .aPunt: .reinicia(actiu: motiuDemanatAra == nil)
        case .baixant, .aplicant: .cap
        }
    }

    /// Els dies que fa que la versió és a punt, si en fa com a mínim `diesAvis` (decisió 5 de Sparkle).
    public func diesAPunt(avui: Date) -> Int? {
        guard case .aPunt = estat, let aPuntDes else { return nil }
        let dies = Int(avui.timeIntervalSince(aPuntDes) / 86_400)
        return dies >= P.diesAvis ? dies : nil
    }

    private static func fa(_ quan: Date, avui: Date) -> String {
        let segons = max(0, avui.timeIntervalSince(quan))
        if segons < 60 { return "fa menys d'1 min" }
        if segons < 3600 { return "fa \(Int(segons / 60)) min" }
        if segons < 86_400 { return "fa \(Int(segons / 3600)) h" }
        let dies = Int(segons / 86_400)
        return dies == 1 ? "fa 1 dia" : "fa \(dies) dies"
    }

    private static func quan(_ data: Date, avui: Date) -> String {
        let hora = DateFormatter()
        hora.dateFormat = "HH:mm"
        guard !Calendar.current.isDate(data, inSameDayAs: avui) else { return "avui a les \(hora.string(from: data))" }
        let dia = DateFormatter()
        dia.dateFormat = "dd/MM/yyyy"
        return "el \(dia.string(from: data)) a les \(hora.string(from: data))"
    }
}
