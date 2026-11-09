import Foundation
import Observation
import WarpLaunchCore

/// Obrir una finestra de la configuració a Warp (fase 3.1, R12; docs/disseny.md, secció 7, «Flux»). Una sola alhora:
///
/// 1. `demana` desa la configuració, llegeix Warp i les sessions, i calcula el pla (`PlaObertura`).
/// 2. El full de confirmació el mostra, i diu si Warp és tancat. **Només `confirmaIObre` (el botó del full) obre res,
///    també Warp.**
/// 3. `confirmaIObre` torna a llegir i a calcular: si el que s'obriria ha canviat, torna al full («Warp ha canviat»).
///    Si Warp és tancat, l'obre, n'espera l'arrencada i torna a comprovar-ho (si Warp restaura la sessió, pot haver
///    canviat). Després desa el llançament a `estat.json`, escriu el fitxer temporal i el fa obrir a Warp. Llavors llegeix
///    Warp cada 0,5 s, fins a 30 s: esborra el fitxer en quant veu la finestra nova, un terminal nou o un Claude amb la
///    marca (Warp ja l'ha llegit), i continua fins que ho ha vist tot i el Claude de cada pestanya, per lligar-les totes.
///    Ho diu en un bàner.
///
/// Tot el que toca fora (Warp, el disc, el rellotge) arriba per `Entorn`: les proves hi posen un obridor fals i una
/// carpeta temporal.
@MainActor
@Observable
public final class Obertura {
    /// Tot el que fa servir de fora.
    public struct Entorn {
        public var llegeix: @MainActor () async -> Result<LecturaWarp, EstatWarp.ErrorLectura>
        /// Demana a Warp que obri el fitxer (`ObreWarp.obre`).
        public var obre: @MainActor (URLLlancament) async throws -> Void
        /// Obre Warp, si és tancat (`ObreWarp.engega`).
        public var engegaWarp: @MainActor () async throws -> Void
        public var fitxers: FitxersLaunchWarp
        public var transcripcions: LectorTranscripcions
        public var confianca: LectorConfianca
        public var versioWarp: () -> String?
        /// Carpeta d'inici (es fa canònica).
        public var inici: String
        public var carpetaExisteix: (String) -> Bool
        public var nouId: () -> UUID
        public var rellotge: () -> Date
        public var espera: @MainActor (Duration) async -> Void

        public init(llegeix: @escaping @MainActor () async -> Result<LecturaWarp, EstatWarp.ErrorLectura>,
                    obre: @escaping @MainActor (URLLlancament) async throws -> Void,
                    engegaWarp: @escaping @MainActor () async throws -> Void, fitxers: FitxersLaunchWarp,
                    transcripcions: LectorTranscripcions, confianca: LectorConfianca,
                    versioWarp: @escaping () -> String?, inici: String,
                    carpetaExisteix: @escaping (String) -> Bool = Validacio.carpetaExisteixAlDisc,
                    nouId: @escaping () -> UUID = { UUID() }, rellotge: @escaping () -> Date = { Date() },
                    espera: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
            self.llegeix = llegeix
            self.obre = obre
            self.engegaWarp = engegaWarp
            self.fitxers = fitxers
            self.transcripcions = transcripcions
            self.confianca = confianca
            self.versioWarp = versioWarp
            self.inici = inici
            self.carpetaExisteix = carpetaExisteix
            self.nouId = nouId
            self.rellotge = rellotge
            self.espera = espera
        }
    }

    /// El que mostra el full de confirmació.
    public struct Proposta: Equatable, Sendable {
        public var pla: Pla
        /// L'id del llançament: el fitxer que es mostra és exactament el que s'escriurà.
        public var llancament: UUID
        /// El fitxer, si n'hi ha cap pestanya per obrir; o per què no es pot generar.
        public var fitxer: Result<FitxerLaunch, LaunchConfigWarp.ErrorLaunch>?
        public var versioWarp: String?
        /// Warp ha canviat entre el full i «Obre»: el pla és el nou, i s'ha de tornar a confirmar.
        public var haCanviat = false
        /// Warp és tancat: «Obre» primer l'obrirà.
        public var warpTancat = false
        /// `false`: la restauració de sessió és desactivada. Warp no desa les finestres, i en arrencar n'obre una de buida.
        /// `true` també si Warp no té `settings.toml` i és tancat (ronda 5, `warpRestauraEnArrencar`).
        public var warpDesaFinestres = true
        /// Els panes de Warp abans d'obrir: la finestra nova és la que només en té de nous.
        var panesAbans: Set<String>
        /// Els terminals vius abans d'obrir: els de la finestra nova són els que no hi eren.
        var terminalsAbans: Set<Int32> = []
    }

    public enum Fase: Equatable, Sendable {
        /// Torna a llegir Warp per comprovar que el pla és el mateix.
        case comprovant
        /// Warp era tancat: l'obre i n'espera l'arrencada.
        case engegant
        /// Escriu el fitxer i el passa a Warp.
        case obrint
        /// Espera la finestra nova.
        case esperant
        /// La finestra ja hi és: espera que arrenqui el Claude de cada pestanya.
        case esperantClaude
    }

    public enum Estat: Equatable {
        case cap
        /// Llegint Warp per fer el pla de la finestra (el nom, i l'id del llançament: és el de la petició).
        case preparant(String, UUID)
        case confirmant(Proposta)
        case obrint(Proposta, Fase)
        /// No es pot obrir (encara no s'ha escrit res): el full ho diu, amb «D'acord».
        case noEsPot(String)
        /// «Obre-ho tot» (fase 3.2): llegint Warp per fer el pla de cada finestra (l'id de la petició).
        case preparantTot(UUID)
        case confirmantTot(PropostaTot)
        case obrintTot(PropostaTot, Fase)
    }

    /// El bàner de l'editor, després d'obrir.
    public struct Resultat: Equatable {
        public var correcte: Bool
        public var text: String
    }

    public static let interval = ExecucioObertura.interval
    public static let tempsMaxim = ExecucioObertura.tempsMaxim
    /// Quant s'espera que Warp arrenqui, i el marge perquè acabi de restaurar la sessió, si la restaura.
    public static let tempsMaximWarp = ExecucioObertura.tempsMaximWarp
    public static let margeArrencada = ExecucioObertura.margeArrencada

    public internal(set) var estat: Estat = .cap
    public internal(set) var resultat: Resultat?
    @ObservationIgnored let editor: Editor
    @ObservationIgnored let sessions: EstatSessions
    /// D-P4: sense el consentiment de la restauració, no es proposa obrir res, ni es toca la carpeta de Warp.
    @ObservationIgnored let consentiment: ConsentimentRestauracio
    @ObservationIgnored let entorn: Entorn
    /// Cada llançament amb el fitxer escrit, i el que se n'ha vist fins ara (per a `enSortir`). Amb «Obre-ho tot», n'hi pot
    /// haver més d'un alhora.
    private struct EnCurs {
        var llancament: Llancament
        var vist: Confirmacio?
    }
    @ObservationIgnored private var enCurs: [UUID: EnCurs] = [:]
    /// «Obre-ho tot»: els terminals sense marca que s'ha pres cada llançament, perquè cap altre no els compti. Duren fins que
    /// acaben totes les finestres.
    @ObservationIgnored var presos: [UUID: Set<Int32>] = [:]
    /// «Obre-ho tot»: la lectura del full, per tornar a calcular els plans quan es marca o es desmarca una finestra.
    @ObservationIgnored var lecturaTot: LecturaWarp?
    /// Per què no s'ha pogut obrir Warp, si no s'ha pogut.
    @ObservationIgnored private var errorEngegant: String?
    /// Una conversa que reprèn una pestanya d'una finestra que s'ha vist obrir, però on encara no s'ha vist Claude.
    private struct ConversaEnCurs {
        var pestanya: UUID
        var desDe: Date
    }
    /// Per conversa (`EntradaObertura.conversesEnCurs`). Se n'esborra quan es veu el Claude, o als 10 min.
    @ObservationIgnored private var conversesEnCurs: [String: ConversaEnCurs] = [:]
    /// Una actualització s'ha començat a aplicar: l'app sortirà, i ja no se li torna a preguntar (`Actualitzacions`). Mentrestant,
    /// no es pot començar a obrir res. L'assigna l'app.
    @ObservationIgnored public var aplicantActualitzacio: @MainActor () -> Bool = { false }

    public init(editor: Editor, sessions: EstatSessions, consentiment: ConsentimentRestauracio, entorn: Entorn) {
        self.editor = editor
        self.sessions = sessions
        self.consentiment = consentiment
        self.entorn = entorn
    }

    /// El full de confirmació és a la vista.
    public var mostraFull: Bool { estat != .cap }

    /// Si es pot començar a obrir aquesta finestra: s'ha acceptat el consentiment (D-P4), la configuració és oberta, la
    /// finestra té pestanyes, no hi ha cap altra obertura en curs i `estat.json` es pot fer servir.
    public func potObrir(_ finestra: Finestra.ID?) -> Bool {
        guard estat == .cap, !aplicantActualitzacio(), consentiment.potContinuar, editor.estat == .oberta,
              sessions.motiuNoEsPotObrir == nil, let finestra else { return false }
        return editor.configuracio.finestres.first { $0.id == finestra }?.pestanyes.isEmpty == false
    }

    // MARK: - Els passos

    /// Prepara el full de confirmació. No escriu res de Warp (només desa la configuració, si calia).
    public func demana(_ finestra: Finestra.ID) async {
        guard potObrir(finestra), let nom = editor.configuracio.finestres.first(where: { $0.id == finestra })?.nom else {
            return
        }
        resultat = nil
        let llancament = entorn.nouId()
        estat = .preparant(nom, llancament)
        Registre.obertura.notice("demana \(Registre.curt(finestra), privacy: .public)")
        let preparada = await prepara(finestra, llancament: llancament)
        // Cancel·lat mentre es llegia Warp (potser per demanar-ne una altra).
        guard estat == .preparant(nom, llancament) else { return }
        switch preparada {
        case let .success(proposta):
            estat = .confirmant(proposta)
            let x = proposta.pla.xifres
            Registre.obertura.notice("""
                pla \(x.pestanyes) a obrir (\(x.ambClaude) amb Claude, \(x.reprenen) reprenen), \(x.jaObertes) ja obertes, \
                \(x.excloses) excloses, \(proposta.pla.avisos.count) avisos
                """)
        case let .failure(motiu):
            estat = .noEsPot(motiu.text)
            Registre.obertura.notice("no es pot: \(motiu.text)")
        }
    }

    /// Tanca el full sense obrir res. Mentre obre, no fa res: s'ha d'acabar.
    public func cancela() {
        switch estat {
        case .obrint, .obrintTot: return
        default: estat = .cap
        }
    }

    public func descartaResultat() { resultat = nil }

    /// El botó «Obre» del full: l'únic camí que obre res de Warp.
    public func confirmaIObre() async {
        guard case let .confirmant(vista) = estat, !vista.pla.aObrir.isEmpty, vista.pla.motiuEspera == nil else { return }
        estat = .obrint(vista, .comprovant)

        // 1. Torna a llegir i a calcular, amb el mateix id: si el que s'obriria no és el mateix, es torna a confirmar.
        guard var proposta = await comprova(vista) else { return }

        // Warp s'ha tancat mentre el full era obert, i el full no ho deia: s'ha de tornar a confirmar.
        if proposta.warpTancat, !vista.warpTancat {
            proposta.haCanviat = true
            estat = .confirmant(proposta)
            Registre.obertura.notice("Warp s'ha tancat: es torna a confirmar")
            return
        }

        // Warp és tancat: l'obre i ho torna a comprovar, perquè en arrencar pot haver restaurat alguna pestanya.
        let engegat = proposta.warpTancat
        if engegat {
            estat = .obrint(proposta, .engegant)
            if let motiu = await engegaWarp() {
                estat = .noEsPot(motiu)
                return
            }
            guard var nova = await comprova(vista) else { return }
            guard !nova.warpTancat else {
                estat = .noEsPot("Warp s'ha tancat mentre arrencava: mira'l i torna-ho a provar.")
                return
            }
            // Com ha arrencat Warp: l'app pot haver creat `settings.toml` mentre l'esperava (ronda 5), i ja seria tard.
            nova.warpDesaFinestres = proposta.warpDesaFinestres
            proposta = nova
        }
        guard case let .success(fitxer)? = proposta.fitxer else { return }

        // 2 a 5: el llançament a `estat.json`, el fitxer, Warp, i la finestra nova.
        presos = [:]
        defer { presos = [:] }
        switch await executa(proposta, fitxer: fitxer, engegat: engegat, fase: { [weak self] in
            self?.estat = .obrint(proposta, $0)
        }) {
        case let .noEsPot(motiu): estat = .noEsPot(motiu)
        case let .acabat(fet): acaba(correcte: fet.correcte, fet.text)
        }
    }

    /// Obre Warp i n'espera l'arrencada. Torna per què no s'ha pogut, o `nil`.
    func engegaWarp() async -> String? {
        Registre.obertura.notice("Warp és tancat: l'obre")
        // No s'espera que torni: un diàleg del sistema el podria aturar, i el full quedaria blocat. El límit és a `esperaWarp`.
        errorEngegant = nil
        Task {
            do {
                try await entorn.engegaWarp()
            } catch {
                errorEngegant = "\(error)"
            }
        }
        let arrencat = await esperaWarp()
        if let errorEngegant { return "No s'ha pogut obrir Warp: \(errorEngegant)" }
        guard arrencat else {
            Registre.obertura.notice("Warp no ha arrencat")
            return "Warp no ha arrencat en \(Int(Self.tempsMaximWarp)) s: mira'l i torna-ho a provar."
        }
        return nil
    }

    /// Els passos 2 a 5 d'una finestra (`ExecucioObertura`, com el CLI), i el que se'n recorda: les converses en curs i
    /// el registre. `llegeix`: d'on surten les lectures mentre s'espera (amb «Obre-ho tot», una de compartida).
    func executa(_ proposta: Proposta, fitxer: FitxerLaunch, engegat: Bool,
                 llegeix: (@MainActor () async -> LecturaWarp?)? = nil, ambAltres: Bool = false,
                 fase: @escaping @MainActor (Fase) -> Void) async -> ExecucioObertura.Resultat {
        let peticio = ExecucioObertura.Peticio(pla: proposta.pla, fitxer: fitxer, panesAbans: proposta.panesAbans,
                                               terminalsAbans: proposta.terminalsAbans, warpEngegat: engegat,
                                               warpDesaFinestres: proposta.warpDesaFinestres, ambAltres: ambAltres)
        let sessions = sessions
        let carpeta = sessions.carpeta
        let id = fitxer.llancament
        let execucio = ExecucioObertura.Entorn(
            llegeix: llegeix ?? { [entorn] in try? await entorn.llegeix().get() },
            obre: entorn.obre,
            fitxers: entorn.fitxers,
            // Es mira just abans d'escriure: entre el clic i l'escriptura, el permís es pot haver retirat (regla 7).
            potCrearCarpeta: { [consentiment] in consentiment.potCrearCarpetaDeWarp },
            inici: entorn.inici, rellotge: entorn.rellotge, espera: entorn.espera,
            desaLlancament: { sessions.desa(llancament: $0) },
            lligaPanes: { sessions.lliga(panes: $0) },
            desaEntornClaude: { if let carpeta { try EntornClaude.desa(carpeta: carpeta) } },
            enLlegir: { [weak self] in self?.enLlegir($0) },
            enFase: { nova in
                switch nova {
                case .obrint: fase(.obrint)
                case .esperant: fase(.esperant)
                case .esperantClaude: fase(.esperantClaude)
                }
            },
            enCurs: { [weak self] llancament, vist in
                guard let self else { return }
                guard let llancament else {
                    enCurs[id] = nil
                    return
                }
                if vist == nil, enCurs[id] == nil {
                    Registre.obertura.notice("escrit \(Registre.curt(llancament.id), privacy: .public) (\(llancament.mida) bytes): obre")
                }
                enCurs[id] = EnCurs(llancament: llancament, vist: vist)
            },
            enErrorEsborrant: { llancament, error in
                Registre.obertura.error("no s'ha pogut esborrar \(Registre.curt(llancament.id), privacy: .public): \(error, privacy: .public)")
            },
            presosPerAltres: { [weak self] in
                (self?.presos ?? [:]).filter { $0.key != id }.values.reduce(into: Set<Int32>()) { $0.formUnion($1) }
            },
            pren: { [weak self] in self?.presos[id] = $0 })
        let resultat = await ExecucioObertura.executa(peticio, entorn: execucio)
        switch resultat {
        case let .noEsPot(motiu):
            Registre.obertura.notice("no es pot: \(motiu)")
        case let .acabat(fet) where fet.llancament.estat == .error && fet.llancament.segons == nil:
            // No s'ha pogut escriure el fitxer: Warp no ha rebut res.
            break
        case let .acabat(fet):
            let llancament = fet.llancament
            let vist = fet.vist
            // Les converses represes a la finestra nova on encara no s'ha vist Claude: mentre no es vegi (10 min com a
            // molt), una altra pestanya amb la mateixa conversa compta com a oberta. Si no s'ha vist la finestra, ja ho
            // diu l'avís de l'últim llançament.
            if fet.finestra {
                for pestanya in fet.senseClaude {
                    if let id = pestanya.conversa.repren {
                        conversesEnCurs[id] = ConversaEnCurs(pestanya: pestanya.pestanya.id, desDe: fet.desDe)
                    }
                }
            }
            Registre.obertura.notice("""
                \(llancament.estat.rawValue, privacy: .public) en \(llancament.segons ?? 0, privacy: .public) s, finestra \
                \(vist?.finestra ?? 0), \(vist?.terminals.count ?? 0) terminals, \(vist?.panes.count ?? 0) panes, \
                \(vist?.sessions.count ?? 0) sessions, \
                \(fet.senseClaude.count) Claude sense veure, esborrat \(llancament.esborrat)
                """)
        }
        return resultat
    }

    /// En sortir de l'app a mig obrir: esborra el fitxer temporal, perquè no quedi a Warp (⌃⌘L), i desa el que ja s'ha
    /// vist (si s'ha vist la finestra, els panes de totes les pestanyes).
    public func enSortir() {
        let totes = enCurs.values.sorted { $0.llancament.creat < $1.llancament.creat }
        enCurs = [:]
        for var curs in totes {
            if !curs.llancament.esborrat { curs.llancament.esborrat = esborra(curs.llancament) }
            if curs.llancament.estat == .pendent {
                curs.llancament.estat = curs.vist?.vista(curs.llancament.pestanyes) == true ? .confirmat : .senseConfirmar
            }
            sessions.desa(llancament: curs.llancament)
            if let panes = curs.vist?.panes, !panes.isEmpty { sessions.lliga(panes: panes) }
            Registre.obertura.notice("surt a mig obrir: \(curs.llancament.estat.rawValue, privacy: .public), esborrat \(curs.llancament.esborrat)")
        }
    }

    /// Cada lectura de Warp (també les de cada 60 s): una conversa en curs deixa de ser-ho en quant es veu el Claude de
    /// la seva pestanya, començat després d'obrir.
    public func enLlegir(_ lectura: LecturaWarp) {
        guard !conversesEnCurs.isEmpty else { return }
        let sessions = lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude)
            + lectura.sessionsSensePestanya
        conversesEnCurs = conversesEnCurs.filter { _, enCurs in
            !sessions.contains { sessio in
                sessio.marca == enCurs.pestanya
                    && (sessio.iniciada.map { $0 >= enCurs.desDe - ConfirmacioObertura.marge } ?? false)
            }
        }
    }

    /// En arrencar l'app: esborra els fitxers temporals que hagin quedat (un llançament a mig fer, o d'una versió
    /// anterior) i ho apunta a `estat.json`.
    public func netejaEnArrencar() {
        guard consentiment.potContinuar else { return }
        // Sense un `estat.json` que es pugui fer servir, no s'hi toca res, però els fitxers propis que hagin quedat
        // (amb la marca i de fa més de 2 min) s'esborren igualment.
        guard sessions.motiuNoEsPotObrir == nil else {
            let resultats = entorn.fitxers.neteja(llancaments: [], ara: entorn.rellotge())
            if !resultats.isEmpty {
                let errors = resultats.values.filter { if case .failure = $0 { true } else { false } }.count
                Registre.obertura.notice("neteja sense estat.json: \(resultats.count) fitxers, \(errors) errors")
            }
            return
        }
        let resultats = entorn.fitxers.neteja(llancaments: sessions.estat.llancaments, ara: entorn.rellotge())
        var esborrats = 0
        for llancament in sessions.estat.llancaments {
            guard case .success? = resultats[llancament.id] else { continue }
            var nou = llancament
            nou.esborrat = true
            if nou.estat == .pendent { nou.estat = .senseConfirmar }
            sessions.desa(llancament: nou)
            esborrats += 1
        }
        let errors = resultats.values.filter { if case .failure = $0 { true } else { false } }.count
        if !resultats.isEmpty {
            Registre.obertura.notice("neteja: \(resultats.count) fitxers, \(esborrats) llançaments al dia, \(errors) errors")
        }
    }

    // MARK: - Detalls

    struct Motiu: Error {
        var text: String
    }

    /// Torna a llegir i a calcular. Si el que s'obriria ha canviat, o ara cal esperar perquè una pestanya s'ha tancat mentre
    /// el full era obert, torna al full; si no es pot, ho diu; en tots dos casos, `nil`.
    private func comprova(_ vista: Proposta) async -> Proposta? {
        switch await prepara(vista.pla.finestra.id, llancament: vista.llancament) {
        case let .failure(motiu):
            estat = .noEsPot(motiu.text)
            Registre.obertura.notice("no es pot en confirmar: \(motiu.text)")
            return nil
        case let .success(nova):
            guard nova.pla.aObrir == vista.pla.aObrir, nova.fitxer == vista.fitxer, nova.pla.motiuEspera == nil else {
                var canviada = nova
                canviada.haCanviat = true
                estat = .confirmant(canviada)
                Registre.obertura.notice("Warp ha canviat: es torna a confirmar")
                return nil
            }
            return nova
        }
    }

    /// Espera que Warp sigui obert, i el marge perquè acabi d'arrencar. `false` si no ho és al cap de `tempsMaximWarp`, o si
    /// no s'ha pogut obrir (`errorEngegant`).
    private func esperaWarp() async -> Bool {
        await ExecucioObertura.esperaWarp(llegeix: { [entorn] in try? await entorn.llegeix().get() }, espera: entorn.espera,
                                          rellotge: entorn.rellotge, fallat: { [weak self] in self?.errorEngegant != nil })
    }

    /// Desa la configuració, llegeix Warp i calcula el pla.
    private func prepara(_ id: Finestra.ID, llancament: UUID) async -> Result<Proposta, Motiu> {
        let lectura: LecturaWarp
        switch await llegeixPerObrir() {
        case let .success(llegida): lectura = llegida
        case let .failure(motiu): return .failure(motiu)
        }
        guard let finestra = editor.configuracio.finestres.first(where: { $0.id == id }), !finestra.pestanyes.isEmpty
        else { return .failure(Motiu(text: "La finestra ja no és a la configuració, o no té pestanyes")) }
        let proposta = planifica(finestra, lectura: lectura, llancament: llancament)
        // Warp és tancat i restaura la sessió: les «obertes» són les que restaurarà, no les d'ara.
        if lectura.warpObert != true, lectura.warpDesaFinestres != false, proposta.pla.aObrir.isEmpty {
            return .failure(Motiu(text: Self.warpRestaurara))
        }
        return .success(proposta)
    }

    static let warpRestaurara = "Warp és tancat, i en obrir-se restaurarà aquestes pestanyes, sense Claude. Obre'l i torna-ho a provar."

    /// Què diuen els fulls d'«Obre a Warp…» i «Obre-ho tot…» amb Warp tancat: si Warp, en arrencar, restaurarà les seves
    /// finestres (`Proposta.warpDesaFinestres`, `warpRestauraEnArrencar`), o si n'obrirà una de buida. Sense `settings.toml`,
    /// diu que les restaurarà, i no demana d'obrir Warp primer, perquè no ho evitaria (decisió 1 d'en David, 08/11/2026).
    static func textWarpTancat(restaura: Bool) -> String {
        "Warp és tancat: l'app l'obrirà abans. "
            + (restaura ? "Warp també restaurarà les finestres d'abans, sense Claude."
                : "En arrencar, Warp obre també una finestra buida, que pots tancar.")
    }

    /// Què poden perdre les feines en segon pla de Claude, als dos fulls (decisió d'en David del 09/11/2026; fet observat una
    /// vegada, per això «pot»). Reobrir una pestanya no reprèn la feina que hi corria.
    static let textFeinesEnSegonPla = "Tancar Warp pot deixar a mitges les feines en segon pla de Claude, i reobrir les "
        + "pestanyes no les fa continuar."

    /// Desa la configuració i llegeix Warp (la lectura posa al dia els lligams, `EstatWarp.enLlegir`). Amb Warp Preview
    /// (`LecturaWarp.warpPreview`, D-P12), o sense cap Warp (0.31.1), no es pot obrir res: ho diu el full.
    func llegeixPerObrir() async -> Result<LecturaWarp, Motiu> {
        editor.acabaNom(desant: true)
        guard editor.desaSiCal() else {
            return .failure(Motiu(text: "No s'ha pogut desar la configuració"
                + (editor.errorDesat.map { ": \($0.description)" } ?? "")))
        }
        if let motiu = sessions.motiuNoEsPotObrir { return .failure(Motiu(text: motiu)) }
        let lectura: LecturaWarp
        switch await entorn.llegeix() {
        case let .success(llegida): lectura = llegida
        case let .failure(error): return .failure(Motiu(text: "No s'ha pogut llegir Warp: \(error)"))
        }
        if let motiu = sessions.motiuNoEsPotObrir { return .failure(Motiu(text: motiu)) }
        enLlegir(lectura)
        // D-P12: amb Warp Preview, o sense cap Warp (0.31.1), ni el full ni obrir res (tampoc Warp Stable, sense dir-ho).
        if let preview = lectura.warpPreview { return .failure(Motiu(text: preview.text)) }
        return .success(lectura)
    }

    /// El pla d'una finestra amb una lectura. `jaRepreses`: converses que ja reprenen pestanyes d'altres finestres que
    /// s'obriran alhora («Obre-ho tot»), perquè dues pestanyes no reprenguin la mateixa.
    func planifica(_ finestra: Finestra, lectura: LecturaWarp, llancament: UUID,
                   jaRepreses: Set<String> = []) -> Proposta {
        let inici = Rutes.canonica(entorn.inici)
        let transcripcions = entorn.transcripcions
        let entrada = EntradaObertura(lectura: lectura, estat: sessions.estat, inici: inici, ara: entorn.rellotge(),
                                      carpetaExisteix: entorn.carpetaExisteix,
                                      transcripcio: { transcripcions.on(sessio: $0, carpeta: $1) },
                                      conversesRecents: { transcripcions.recents(carpeta: $0) },
                                      confianca: entorn.confianca.llegeix(inici: inici),
                                      conversesEnCurs: conversesRecents(),
                                      entornClaude: sessions.carpeta.map(EntornClaude.ruta(carpeta:)))
        var amb = entrada
        amb.jaRepreses = jaRepreses
        let pla = PlaObertura.calcula(finestra, amb)
        let fitxer: Result<FitxerLaunch, LaunchConfigWarp.ErrorLaunch>? = pla.aObrir.isEmpty
            ? nil
            : Result { () throws(LaunchConfigWarp.ErrorLaunch) in try pla.fitxer(llancament: llancament) }
        let panes = Set(lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).map(\.uuid))
        return Proposta(pla: pla, llancament: llancament, fitxer: fitxer, versioWarp: entorn.versioWarp(),
                        warpTancat: lectura.warpObert != true,
                        warpDesaFinestres: warpRestauraEnArrencar(lectura), panesAbans: panes,
                        terminalsAbans: Set(lectura.terminals.map(\.pid)))
    }

    /// Si Warp, en arrencar, restaurarà les seves finestres (`Proposta.warpDesaFinestres`, només per als textos del full i
    /// del resultat): segons la lectura, o perquè Warp no té `settings.toml` i l'app encara no hi ha pogut desactivar la
    /// restauració (ronda 5, `RefrescWarp.warpRestauraEnArrencar`). Llavors no obre cap finestra buida.
    func warpRestauraEnArrencar(_ lectura: LecturaWarp) -> Bool {
        lectura.warpDesaFinestres != false || consentiment.refresc?.warpRestauraEnArrencar == true
    }

    /// Hi ha alguna conversa en curs dels darrers 10 min. Va per la data, com `conversesRecents`: una pestanya on Claude no
    /// arriba mai no pot deixar aquest valor cert per sempre (`enLlegir` només en treu les que veu). En valor absolut: un rellotge
    /// que va molt enrere tampoc.
    public var teConversesEnCurs: Bool {
        let ara = entorn.rellotge()
        return conversesEnCurs.contains { abs(ara.timeIntervalSince($0.value.desDe)) < PlaObertura.tempsDarrerLlancament }
    }

    /// Les converses en curs dels darrers 10 min; les més velles s'obliden.
    private func conversesRecents() -> [String: UUID] {
        let ara = entorn.rellotge()
        conversesEnCurs = conversesEnCurs.filter { ara.timeIntervalSince($0.value.desDe) < PlaObertura.tempsDarrerLlancament }
        return conversesEnCurs.mapValues(\.pestanya)
    }

    /// Esborra el fitxer del llançament; torna si ja no hi és.
    private func esborra(_ llancament: Llancament) -> Bool {
        guard let error = ExecucioObertura.error(esborrant: llancament, entorn.fitxers) else { return true }
        Registre.obertura.error("no s'ha pogut esborrar \(Registre.curt(llancament.id), privacy: .public): \(error, privacy: .public)")
        return false
    }

    private func acaba(correcte: Bool, _ text: String) {
        resultat = Resultat(correcte: correcte, text: text)
        estat = .cap
    }
}
