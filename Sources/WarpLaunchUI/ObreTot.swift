import Foundation
import WarpLaunchCore

/// «Obre-ho tot» (fase 3.2): un sol full per tornar a obrir totes les finestres que falten, per exemple després de reiniciar.
///
/// - **Decisions d'en David (05/11/2026):** totes de cop (D4), sense esperar que s'hagi vist l'anterior; si una no s'obre o no
///   es reconeix, les altres continuen, i el resultat ho diu al final; al full, una casella per finestra, totes marcades.
/// - Llegeix Warp un sol cop i calcula el pla de cada finestra en ordre. Les converses que reprèn una finestra ja no les
///   reprèn cap altra (`EntradaObertura.jaRepreses`, R9).
/// - **Només `confirmaIObreTot` (el botó del full) obre res.** Torna a llegir i a calcular: si alguna finestra triada ha
///   canviat, torna al full. Si Warp és tancat, l'obre un cop. Després fa els passos d'`ExecucioObertura` per a cada
///   finestra alhora, amb una lectura de Warp compartida.
/// - **Les pestanyes sense marca** (només de terminal, o abans que arrenqui Claude) es reconeixen per la carpeta. Amb
///   diverses finestres alhora, un terminal que n'ha pres una ja no compta per a cap altra, i un terminal reconegut només
///   per la carpeta no fa esborrar el fitxer (`Confirmacio.segura`; si no hi ha res més, s'esborra als 30 s). Si dues
///   finestres en tenen a la mateixa carpeta, l'app encara pot lligar-ne una a la finestra de l'altra (cap Claude no queda
///   repetit).
extension Obertura {
    /// El que mostra el full de «Obre-ho tot».
    public struct PropostaTot: Equatable, Sendable {
        /// Cada finestra amb pestanyes, en l'ordre de la configuració.
        public var finestres: [Proposta]
        /// Les marcades al full. Per defecte, totes les que es poden obrir.
        public var triades: Set<Finestra.ID>
        /// Warp ha canviat entre el full i «Obre»: el pla és el nou, i s'ha de tornar a confirmar.
        public var haCanviat = false
        public var warpTancat: Bool
        public var warpDesaFinestres: Bool
        public var versioWarp: String?
        /// Terminals oberts a Warp que l'app no reconeix com a pestanyes de la configuració: sense marca de Warp Launch i que
        /// cap finestra no compta com a oberta. Per exemple, les que Warp ha restaurat sola, sense Claude (06/11/2026). Si
        /// s'obre, quedaran repetides: el full ho diu, però deixa obrir (en David, 06/11/2026).
        public var terminalsDesconeguts = 0

        /// Té alguna pestanya per obrir, no ha d'esperar i el fitxer es pot generar.
        public static func esPotObrir(_ p: Proposta) -> Bool {
            guard !p.pla.aObrir.isEmpty, p.pla.motiuEspera == nil, case .success? = p.fitxer else { return false }
            return true
        }

        /// L'id del llançament de cada finestra: es manté en tornar a calcular.
        public var llancaments: [Finestra.ID: UUID] {
            Dictionary(uniqueKeysWithValues: finestres.map { ($0.pla.finestra.id, $0.llancament) })
        }

        /// Les finestres que s'obriran: les marcades que es poden obrir.
        public var aObrir: [Proposta] {
            finestres.filter { triades.contains($0.pla.finestra.id) && Self.esPotObrir($0) }
        }

        /// «S'obriran 3 finestres noves de Warp amb 16 pestanyes: 10 amb Claude (8 reprenen la seva conversa) i 6 només
        /// terminal · unes 5 GB».
        public var text: String {
            let finestres = aObrir
            guard !finestres.isEmpty else { return "No s'obrirà res." }
            let x = finestres.map(\.pla.xifres)
            let pestanyes = x.map(\.pestanyes).reduce(0, +)
            let ambClaude = x.map(\.ambClaude).reduce(0, +)
            let reprenen = x.map(\.reprenen).reduce(0, +)
            let terminal = x.map(\.terminal).reduce(0, +)
            var text = "S'obriran \(Plural.compta(finestres.count, "finestra nova", "finestres noves")) de Warp amb "
                + "\(Plural.compta(pestanyes, "pestanya", "pestanyes"))"
            var parts: [String] = []
            if ambClaude > 0 { parts.append("\(ambClaude) amb Claude (\(reprenen) reprenen la seva conversa)") }
            if terminal > 0 { parts.append("\(terminal) només terminal") }
            if !parts.isEmpty { text += ": " + parts.joined(separator: " i ") }
            if ambClaude > 0 {
                text += " · unes \(Int((Double(ambClaude) * PlaObertura.memoriaPerSessioGB).rounded())) GB"
            }
            if ambClaude > 10 { text += " · tots els Claude s'engegaran alhora" }
            return text
        }
    }

    /// Si es pot demanar el full de «Obre-ho tot»: s'ha acceptat el consentiment (D-P4), la configuració és oberta, té alguna
    /// finestra amb pestanyes, no hi ha cap altra obertura en curs i `estat.json` es pot fer servir.
    public var potObrirTot: Bool {
        estat == .cap && consentiment.potContinuar && editor.estat == .oberta && sessions.motiuNoEsPotObrir == nil
            && editor.configuracio.finestres.contains { !$0.pestanyes.isEmpty }
    }

    /// Prepara el full de «Obre-ho tot». No escriu res de Warp (només desa la configuració, si calia).
    public func demanaTot() async {
        guard potObrirTot else { return }
        resultat = nil
        let peticio = entorn.nouId()
        estat = .preparantTot(peticio)
        Registre.obertura.notice("demana-ho tot")
        let preparada = await preparaTot(llancaments: [:])
        guard estat == .preparantTot(peticio) else { return }
        switch preparada {
        case let .success(proposta):
            estat = .confirmantTot(proposta)
            Registre.obertura.notice("pla de tot: \(proposta.aObrir.count) finestres de \(proposta.finestres.count)")
        case let .failure(motiu):
            estat = .noEsPot(motiu.text)
            Registre.obertura.notice("no es pot obrir-ho tot: \(motiu.text)")
        }
    }

    /// Marca o desmarca una finestra al full, i torna a calcular els plans amb la mateixa lectura: les converses d'una
    /// finestra desmarcada queden lliures per a les altres.
    public func tria(_ finestra: Finestra.ID, _ triada: Bool) {
        guard case let .confirmantTot(proposta) = estat, let lectura = lecturaTot else { return }
        var triades = proposta.triades
        if triada { triades.insert(finestra) } else { triades.remove(finestra) }
        guard case var .success(nova) = planificaTot(lectura, llancaments: proposta.llancaments, triades: triades) else { return }
        nova.haCanviat = proposta.haCanviat
        estat = .confirmantTot(nova)
    }

    /// El botó «Obre» del full de «Obre-ho tot»: l'únic camí que n'obre res.
    public func confirmaIObreTot() async {
        guard case let .confirmantTot(vista) = estat, !vista.aObrir.isEmpty else { return }
        estat = .obrintTot(vista, .comprovant)

        // 1. Torna a llegir i a calcular, amb els mateixos ids: si el que s'obriria no és el mateix, es torna a confirmar.
        guard var proposta = await comprovaTot(vista) else { return }
        if proposta.warpTancat, !vista.warpTancat {
            proposta.haCanviat = true
            estat = .confirmantTot(proposta)
            Registre.obertura.notice("Warp s'ha tancat: es torna a confirmar")
            return
        }
        let engegat = proposta.warpTancat
        if engegat {
            estat = .obrintTot(proposta, .engegant)
            if let motiu = await engegaWarp() {
                estat = .noEsPot(motiu)
                return
            }
            guard var nova = await comprovaTot(vista) else { return }
            guard !nova.warpTancat else {
                estat = .noEsPot("Warp s'ha tancat mentre arrencava: mira'l i torna-ho a provar.")
                return
            }
            // Com ha arrencat Warp: l'app pot haver creat `settings.toml` mentre l'esperava (ronda 5), i ja seria tard.
            nova.warpDesaFinestres = proposta.warpDesaFinestres
            proposta = nova
        }

        // 2. Totes alhora (D4), amb una lectura de Warp compartida.
        let finestres = proposta.aObrir
        estat = .obrintTot(proposta, .obrint)
        Registre.obertura.notice("obre-ho tot: \(finestres.count) finestres")
        let compartida = LecturaCompartida(entorn: entorn)
        presos = [:]
        defer { presos = [:] }
        var tasques: [Int: Task<ExecucioObertura.Resultat, Never>] = [:]
        for n in finestres.indices {
            let finestra = finestres[n]
            guard case let .success(fitxer)? = finestra.fitxer else { continue }
            tasques[n] = Task { @MainActor in
                await executa(finestra, fitxer: fitxer, engegat: engegat, llegeix: { await compartida.llegeix() },
                              ambAltres: finestres.count > 1, fase: { [weak self] in self?.avancaTot($0) })
            }
        }
        var resultats: [Int: ExecucioObertura.Resultat] = [:]
        for (n, tasca) in tasques { resultats[n] = await tasca.value }

        // 3. El resum: quantes s'han obert, i què ha passat amb les altres.
        var correctes = 0
        var linies: [String] = []
        for (n, finestra) in finestres.enumerated() {
            switch resultats[n] {
            case let .acabat(fet)? where fet.correcte:
                correctes += 1
            case let .acabat(fet)?:
                // La finestra buida de Warp es diu un sol cop, al final.
                linies.append(fet.text.replacingOccurrences(of: " " + ExecucioObertura.finestraBuida, with: ""))
            case let .noEsPot(motiu)?:
                linies.append("«\(finestra.pla.finestra.nom)»: \(motiu)")
            case nil:
                linies.append("«\(finestra.pla.finestra.nom)»: no s'ha pogut obrir.")
            }
        }
        let pestanyes = finestres.map(\.pla.aObrir.count).reduce(0, +)
        let ambClaude = finestres.map(\.pla.xifres.ambClaude).reduce(0, +)
        var text = correctes == finestres.count
            ? "S'han obert \(Plural.compta(finestres.count, "finestra", "finestres")) a Warp, amb "
                + "\(Plural.compta(pestanyes, "pestanya", "pestanyes")), \(ambClaude) amb Claude."
            : "S'han obert bé \(correctes) de \(Plural.compta(finestres.count, "finestra", "finestres")) a Warp."
        if !linies.isEmpty { text += "\n" + linies.joined(separator: "\n") }
        if engegat, !proposta.warpDesaFinestres {
            text += "\n" + ExecucioObertura.finestraBuida
        }
        Registre.obertura.notice("obre-ho tot: \(correctes) de \(finestres.count) correctes")
        resultat = Resultat(correcte: correctes == finestres.count, text: text)
        estat = .cap
    }

    // MARK: - Detalls

    /// La primera finestra que espera: el full ho diu.
    private func avancaTot(_ fase: Fase) {
        guard fase == .esperant, case let .obrintTot(proposta, .obrint) = estat else { return }
        estat = .obrintTot(proposta, .esperant)
    }

    /// Desa la configuració, llegeix Warp un cop i calcula el pla de cada finestra amb pestanyes (`planificaTot`).
    /// `llancaments` i `triades`: els d'un full d'abans (per comparar-lo); `nil`, totes les que es poden obrir.
    func preparaTot(llancaments: [Finestra.ID: UUID], triades: Set<Finestra.ID>? = nil) async -> Result<PropostaTot, Motiu> {
        let lectura: LecturaWarp
        switch await llegeixPerObrir() {
        case let .success(llegida): lectura = llegida
        case let .failure(motiu): return .failure(motiu)
        }
        lecturaTot = lectura
        return planificaTot(lectura, llancaments: llancaments, triades: triades)
    }

    /// El pla de cada finestra amb pestanyes, en ordre. Les converses que reprèn una finestra marcada que es pot obrir ja
    /// no les reprèn cap altra (R9); les d'una desmarcada queden lliures. Sense `triades`, es marquen totes les que es
    /// poden obrir (i es calcula fins que no canvia, perquè una que en principi no es pot obrir no reservi res).
    func planificaTot(_ lectura: LecturaWarp, llancaments: [Finestra.ID: UUID],
                      triades: Set<Finestra.ID>?) -> Result<PropostaTot, Motiu> {
        var ids = llancaments
        func calcula(_ triades: Set<Finestra.ID>?) -> [Proposta] {
            var represes = Set<String>()
            var finestres: [Proposta] = []
            for finestra in editor.configuracio.finestres where !finestra.pestanyes.isEmpty {
                let id = ids[finestra.id] ?? entorn.nouId()
                ids[finestra.id] = id
                let proposta = planifica(finestra, lectura: lectura, llancament: id, jaRepreses: represes)
                if PropostaTot.esPotObrir(proposta), triades?.contains(finestra.id) ?? true {
                    represes.formUnion(proposta.pla.aObrir.compactMap(\.conversa.repren))
                }
                finestres.append(proposta)
            }
            return finestres
        }
        var finestres = calcula(triades)
        let marcades = triades ?? Set(finestres.filter(PropostaTot.esPotObrir).map(\.pla.finestra.id))
        if triades == nil { finestres = calcula(marcades) }
        guard !finestres.isEmpty else { return .failure(Motiu(text: "Cap finestra de la configuració no té pestanyes")) }
        let warpTancat = lectura.warpObert != true
        // Warp és tancat i restaura la sessió: les «obertes» a Warp són les que restaurarà, no les d'ara.
        if warpTancat, lectura.warpDesaFinestres != false,
           finestres.contains(where: { $0.pla.obertes.contains { $0.on.esAWarp } }) {
            return .failure(Motiu(text: Self.warpRestaurara))
        }
        var proposta = PropostaTot(finestres: finestres,
                                   triades: marcades.intersection(finestres.filter(PropostaTot.esPotObrir).map(\.pla.finestra.id)),
                                   warpTancat: warpTancat, warpDesaFinestres: warpRestauraEnArrencar(lectura),
                                   versioWarp: entorn.versioWarp())
        if !warpTancat {
            // Els reconeguts sense marca (pestanyes de terminal, per la carpeta) ja són a `obertes`.
            let senseMarca = lectura.terminals.filter { $0.marca == nil }.count
            let obertesSenseMarca = finestres.flatMap(\.pla.obertes).filter {
                if case .marca = $0.on { false } else { $0.on.esAWarp }
            }.count
            proposta.terminalsDesconeguts = max(0, senseMarca - obertesSenseMarca)
        }
        return .success(proposta)
    }

    /// Torna a llegir i a calcular. Si alguna finestra triada ha canviat, torna al full; si no es pot, ho diu; en tots
    /// dos casos, `nil`.
    private func comprovaTot(_ vista: PropostaTot) async -> PropostaTot? {
        switch await preparaTot(llancaments: vista.llancaments, triades: vista.triades) {
        case let .failure(motiu):
            estat = .noEsPot(motiu.text)
            Registre.obertura.notice("no es pot obrir-ho tot en confirmar: \(motiu.text)")
            return nil
        case var .success(nova):
            let ara = nova.finestres.filter { vista.triades.contains($0.pla.finestra.id) }
            let iguals = ara.count == vista.aObrir.count && zip(vista.aObrir, ara).allSatisfy { v, n in
                v.pla.finestra.id == n.pla.finestra.id && v.pla.aObrir == n.pla.aObrir && v.fitxer == n.fitxer
                    && n.pla.motiuEspera == nil
            }
            guard iguals else {
                nova.haCanviat = true
                nova.triades = vista.triades.intersection(nova.finestres.filter(PropostaTot.esPotObrir).map(\.pla.finestra.id))
                estat = .confirmantTot(nova)
                Registre.obertura.notice("Warp ha canviat: es torna a confirmar tot")
                return nil
            }
            return nova
        }
    }
}

/// Una lectura de Warp per a totes les finestres que s'obren alhora: si una altra s'ha fet fa menys de 0,4 s, es fa
/// servir aquella.
@MainActor
private final class LecturaCompartida {
    private let entorn: Obertura.Entorn
    private var darrera: (quan: Date, lectura: LecturaWarp)?
    private var enCurs: Task<LecturaWarp?, Never>?

    init(entorn: Obertura.Entorn) {
        self.entorn = entorn
    }

    func llegeix() async -> LecturaWarp? {
        if let darrera, entorn.rellotge().timeIntervalSince(darrera.quan) < 0.4 { return darrera.lectura }
        if let enCurs { return await enCurs.value }
        let entorn = entorn
        let tasca = Task { @MainActor in try? await entorn.llegeix().get() }
        enCurs = tasca
        let lectura = await tasca.value
        enCurs = nil
        if let lectura { darrera = (entorn.rellotge(), lectura) }
        return lectura
    }
}
