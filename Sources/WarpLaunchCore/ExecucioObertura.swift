import Foundation

/// Els passos d'obrir una finestra a Warp un cop confirmat (el botó del full a l'app, o `warp-launch obre --obre`, D17).
/// L'app (`Obertura`) i el CLI (`OrdreCLI`) fan servir aquest mateix camí (docs/disseny.md, secció 7, «Flux»):
///
/// 1. Desa el llançament, pendent, a `estat.json`: si el procés s'atura a mig camí, l'app esborrarà el fitxer en arrencar.
/// 2. Escriu el fitxer temporal (i `entorn-claude.sh`, si cal) i el fa obrir a Warp.
/// 3. Llegeix Warp cada 0,5 s, fins a 30 s: esborra el fitxer en quant veu res de nou (Warp ja l'ha llegit), i continua
///    fins que ha vist la finestra i el Claude de cada pestanya.
/// 4. Desa el llançament i el pane de cada pestanya que ha vist, i torna el text del resultat.
///
/// Tot el que toca fora arriba per `Entorn`: les proves hi posen un obridor fals i una carpeta temporal.
public enum ExecucioObertura {
    public struct Entorn {
        /// Una lectura de Warp; `nil` si no s'ha pogut llegir (es torna a provar a la volta següent).
        public var llegeix: @MainActor () async -> LecturaWarp?
        /// Demana a Warp que obri el fitxer (`ObreWarp.obre`).
        public var obre: @MainActor (URLLlancament) async throws -> Void
        public var fitxers: FitxersLaunchWarp
        public var inici: String
        public var rellotge: () -> Date
        public var espera: @MainActor (Duration) async -> Void
        /// Desa el llançament (nou o posat al dia) a `estat.json`. Torna l'error, si no s'ha pogut.
        public var desaLlancament: @MainActor (Llancament) -> String?
        /// Desa el pane de cada pestanya que s'ha vist a la finestra nova.
        public var lligaPanes: @MainActor ([UUID: String]) -> Void
        /// Escriu `entorn-claude.sh` al costat de la configuració (només si el pla el fa servir).
        public var desaEntornClaude: @MainActor () throws -> Void
        /// Cada lectura de Warp, mentre s'espera la finestra.
        public var enLlegir: @MainActor (LecturaWarp) -> Void
        /// Cada canvi de fase.
        public var enFase: @MainActor (Fase) -> Void
        /// El llançament amb el fitxer escrit, i el que se n'ha vist fins ara; `nil, nil` en acabar. L'app el fa servir si
        /// surt a mig obrir, i el CLI si es prem Ctrl-C. La primera crida, `(llançament, nil)`, és just abans d'obrir.
        public var enCurs: @MainActor (Llancament?, Confirmacio?) -> Void
        /// El fitxer temporal no s'ha pogut esborrar, i per què (per al registre).
        public var enErrorEsborrant: @MainActor (Llancament, String) -> Void
        /// «Obre-ho tot»: els terminals sense marca que ja s'han pres altres finestres que s'obren alhora (no compten
        /// per a aquesta), i on es diu els que pren aquesta. Amb una sola finestra, cap.
        public var presosPerAltres: @MainActor () -> Set<Int32>
        public var pren: @MainActor (Set<Int32>) -> Void

        public init(llegeix: @escaping @MainActor () async -> LecturaWarp?,
                    obre: @escaping @MainActor (URLLlancament) async throws -> Void, fitxers: FitxersLaunchWarp,
                    inici: String, rellotge: @escaping () -> Date, espera: @escaping @MainActor (Duration) async -> Void,
                    desaLlancament: @escaping @MainActor (Llancament) -> String?,
                    lligaPanes: @escaping @MainActor ([UUID: String]) -> Void,
                    desaEntornClaude: @escaping @MainActor () throws -> Void,
                    enLlegir: @escaping @MainActor (LecturaWarp) -> Void = { _ in },
                    enFase: @escaping @MainActor (Fase) -> Void = { _ in },
                    enCurs: @escaping @MainActor (Llancament?, Confirmacio?) -> Void = { _, _ in },
                    enErrorEsborrant: @escaping @MainActor (Llancament, String) -> Void = { _, _ in },
                    presosPerAltres: @escaping @MainActor () -> Set<Int32> = { [] },
                    pren: @escaping @MainActor (Set<Int32>) -> Void = { _ in }) {
            self.llegeix = llegeix
            self.obre = obre
            self.fitxers = fitxers
            self.inici = inici
            self.rellotge = rellotge
            self.espera = espera
            self.desaLlancament = desaLlancament
            self.lligaPanes = lligaPanes
            self.desaEntornClaude = desaEntornClaude
            self.enLlegir = enLlegir
            self.enFase = enFase
            self.enCurs = enCurs
            self.enErrorEsborrant = enErrorEsborrant
            self.presosPerAltres = presosPerAltres
            self.pren = pren
        }
    }

    public enum Fase: Sendable, Equatable {
        /// Escriu el fitxer i el passa a Warp.
        case obrint
        /// Espera la finestra nova.
        case esperant
        /// La finestra ja hi és: espera que arrenqui el Claude de cada pestanya.
        case esperantClaude
    }

    /// El que s'ha de fer: el pla confirmat, el seu fitxer, i què hi havia a Warp abans.
    public struct Peticio: Sendable, Equatable {
        public var pla: Pla
        public var fitxer: FitxerLaunch
        /// Els panes de Warp abans d'obrir: la finestra nova és la que només en té de nous.
        public var panesAbans: Set<String>
        /// Els terminals vius abans d'obrir: els de la finestra nova són els que no hi eren.
        public var terminalsAbans: Set<Int32>
        /// Warp s'acaba d'obrir per a aquesta finestra.
        public var warpEngegat: Bool
        /// `false`: la restauració de sessió és desactivada (si Warp s'acaba d'obrir, n'ha obert una de buida).
        public var warpDesaFinestres: Bool
        /// S'obren altres finestres alhora («Obre-ho tot»): un terminal reconegut només per la carpeta podria ser d'una
        /// altra, i no fa esborrar el fitxer (`Confirmacio.segura`).
        public var ambAltres: Bool

        public init(pla: Pla, fitxer: FitxerLaunch, panesAbans: Set<String>, terminalsAbans: Set<Int32>,
                    warpEngegat: Bool = false, warpDesaFinestres: Bool = true, ambAltres: Bool = false) {
            self.ambAltres = ambAltres
            self.pla = pla
            self.fitxer = fitxer
            self.panesAbans = panesAbans
            self.terminalsAbans = terminalsAbans
            self.warpEngegat = warpEngegat
            self.warpDesaFinestres = warpDesaFinestres
        }
    }

    public enum Resultat: Sendable, Equatable {
        /// No s'ha escrit ni obert res.
        case noEsPot(String)
        case acabat(Acabat)
    }

    public struct Acabat: Sendable, Equatable {
        /// S'ha vist la finestra, i el Claude de cada pestanya.
        public var correcte: Bool
        public var text: String
        public var llancament: Llancament
        public var vist: Confirmacio?
        /// S'ha vist la finestra nova (totes les pestanyes).
        public var finestra: Bool
        /// Les pestanyes amb Claude on encara no s'ha vist.
        public var senseClaude: [PestanyaAObrir]
        /// Quan s'ha començat a obrir (el marge de les marques compta des d'aquí).
        public var desDe: Date
    }

    public static let finestraBuida = "En arrencar, Warp ha obert també una finestra buida: la pots tancar."
    public static let interval: Duration = .milliseconds(500)
    public static let tempsMaxim: TimeInterval = 30
    /// Quant s'espera que Warp arrenqui, i el marge perquè acabi de restaurar la sessió, si la restaura.
    public static let tempsMaximWarp: TimeInterval = 30
    public static let margeArrencada: Duration = .seconds(2)

    /// Obre la finestra. Només s'hi arriba després de la confirmació.
    @MainActor
    public static func executa(_ peticio: Peticio, entorn: Entorn) async -> Resultat {
        let fitxer = peticio.fitxer
        let pla = peticio.pla
        let nom = pla.finestra.nom
        let x = pla.xifres

        // 1. El llançament, pendent, a `estat.json`.
        var llancament = Llancament(id: fitxer.llancament, fitxer: fitxer.nomFitxer, mida: fitxer.mida,
                                    creat: entorn.rellotge(), finestra: pla.finestra.id,
                                    pestanyes: pla.aObrir.map(\.pestanya.id), estat: .pendent)
        if let error = entorn.desaLlancament(llancament) {
            return .noEsPot("No s'ha pogut desar el llançament a «estat.json»: \(error)")
        }

        func esborra(_ llancament: Llancament) -> Bool {
            guard let error = ExecucioObertura.error(esborrant: llancament, entorn.fitxers) else { return true }
            entorn.enErrorEsborrant(llancament, error)
            return false
        }

        func acaba(_ text: String) -> Resultat {
            .acabat(Acabat(correcte: false, text: text, llancament: llancament, vist: nil, finestra: false,
                           senseClaude: pla.aObrir.filter { $0.argv != nil }, desDe: entorn.rellotge()))
        }

        // 2. El fitxer, i Warp.
        entorn.enFase(.obrint)
        do {
            if pla.necessitaEntornClaude { try entorn.desaEntornClaude() }
            _ = try entorn.fitxers.escriu(fitxer)
        } catch {
            llancament.estat = .error
            _ = entorn.desaLlancament(llancament)
            return acaba("No s'ha pogut obrir «\(nom)» a Warp: \(error)")
        }
        entorn.enCurs(llancament, nil)
        defer { entorn.enCurs(nil, nil) }
        // El marge de les marques compta des d'abans d'obrir; els 30 s, des que Warp ha rebut l'URL.
        let desDe = entorn.rellotge()
        do {
            try await entorn.obre(fitxer.url)
        } catch {
            llancament.estat = .error
            llancament.esborrat = esborra(llancament)
            _ = entorn.desaLlancament(llancament)
            return acaba("No s'ha pogut obrir «\(nom)» a Warp: \(error)")
        }

        // 3. La finestra nova i el Claude de cada pestanya, cada 0,5 s fins a 30 s (com a mínim, una lectura).
        entorn.enFase(.esperant)
        let aObrir = pla.aObrir
        let fins = entorn.rellotge().addingTimeInterval(tempsMaxim)
        let ids = aObrir.map(\.pestanya.id)
        let inici = Rutes.canonica(entorn.inici)
        var vist: Confirmacio?
        var segons: Double?
        repeat {
            await entorn.espera(interval)
            guard let lectura = await entorn.llegeix() else { continue }
            entorn.enLlegir(lectura)
            // Els terminals que ja s'han pres altres finestres no compten; els que ja s'ha pres aquesta, sí.
            let presos = entorn.presosPerAltres().subtracting(vist.map { Set($0.perCarpeta.values) } ?? [])
            guard let nova = ConfirmacioObertura.busca(lectura, obertes: aObrir, panesAbans: peticio.panesAbans,
                                                       terminalsAbans: peticio.terminalsAbans.union(presos), desDe: desDe,
                                                       inici: inici, warpAcabatDEngegar: peticio.warpEngegat)
            else { continue }
            if vist == nil { vist = nova } else { vist?.afegeix(nova) }
            if let vist { entorn.pren(Set(vist.perCarpeta.values)) }
            if !llancament.esborrat, !peticio.ambAltres || vist?.segura == true {
                llancament.esborrat = esborra(llancament)
            }
            entorn.enCurs(llancament, vist)
            if segons == nil, vist?.vista(ids) == true {
                segons = (entorn.rellotge().timeIntervalSince(desDe) * 10).rounded() / 10
                entorn.enFase(.esperantClaude)
            }
        } while vist?.completa(aObrir) != true && entorn.rellotge() < fins

        // 4. Ho desa tot: el llançament, i el pane de cada pestanya que s'ha vist.
        let finestra = vist?.vista(ids) == true
        llancament.estat = finestra ? .confirmat : .senseConfirmar
        if !llancament.esborrat { llancament.esborrat = esborra(llancament) }
        llancament.segons = segons ?? (entorn.rellotge().timeIntervalSince(desDe) * 10).rounded() / 10
        _ = entorn.desaLlancament(llancament)
        if let panes = vist?.panes, !panes.isEmpty { entorn.lligaPanes(panes) }

        let senseClaude = vist?.senseClaude(aObrir) ?? aObrir.filter { $0.argv != nil }
        let ambClaude = x.ambClaude
        var text: String
        if finestra {
            text = "S'ha obert «\(nom)» a Warp: \(Plural.compta(x.pestanyes, "pestanya", "pestanyes")), \(ambClaude) amb Claude."
            if !senseClaude.isEmpty {
                text += " Claude encara no ha arrencat a \(llista(senseClaude)): mira-ho a Warp."
            }
        } else if vist != nil {
            text = "No s'ha pogut reconèixer la finestra nova de «\(nom)» (s'ha vist Claude a "
                + "\(ambClaude - senseClaude.count) de \(ambClaude) pestanyes): mira-la a Warp abans de tornar-la a obrir."
        } else {
            text = "No s'ha pogut confirmar que s'hagi obert «\(nom)»: mira si hi ha una finestra nova a Warp."
        }
        if peticio.warpEngegat, !peticio.warpDesaFinestres { text += " " + finestraBuida }
        if !llancament.esborrat {
            text += " El fitxer temporal no s'ha pogut esborrar: es tornarà a provar en obrir l'app."
        }
        return .acabat(Acabat(correcte: finestra && senseClaude.isEmpty, text: text, llancament: llancament, vist: vist,
                              finestra: finestra, senseClaude: senseClaude, desDe: desDe))
    }

    /// Espera que Warp sigui obert, i el marge perquè acabi d'arrencar. `false` si no ho és al cap de `tempsMaximWarp`, o
    /// si `fallat` diu que no s'ha pogut obrir.
    @MainActor
    public static func esperaWarp(llegeix: @MainActor () async -> LecturaWarp?,
                                  espera: @MainActor (Duration) async -> Void, rellotge: () -> Date,
                                  fallat: @MainActor () -> Bool) async -> Bool {
        let fins = rellotge().addingTimeInterval(tempsMaximWarp)
        repeat {
            await Task.yield()
            guard !fallat() else { return false }
            await espera(interval)
            if let lectura = await llegeix(), lectura.warpObert == true {
                await espera(margeArrencada)
                return true
            }
        } while rellotge() < fins
        return false
    }

    /// Esborra el fitxer del llançament; torna si ja no hi és.
    public static func esborra(_ llancament: Llancament, _ fitxers: FitxersLaunchWarp) -> Bool {
        error(esborrant: llancament, fitxers) == nil
    }

    /// Esborra el fitxer del llançament; torna per què no s'ha pogut, o `nil` si ja no hi és.
    public static func error(esborrant llancament: Llancament, _ fitxers: FitxersLaunchWarp) -> String? {
        do {
            _ = try fitxers.esborra(llancament: llancament.id, mida: llancament.mida)
            return nil
        } catch {
            return error.description
        }
    }

    /// «T1» o «T1, T2 i T3», amb el títol que es veu a Warp.
    static func llista(_ pestanyes: [PestanyaAObrir]) -> String {
        let titols = pestanyes.map { "«\($0.yaml.titolAWarp)»" }
        guard titols.count > 1 else { return titols.first ?? "" }
        return titols.dropLast().joined(separator: ", ") + " i " + titols.last!
    }
}
