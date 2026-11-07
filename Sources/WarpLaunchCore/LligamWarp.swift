import Foundation

/// «Lliga amb Warp…» (docs/disseny.md, secció 7, «Lligar amb Warp»): per a cada pestanya de la configuració sense
/// lligam, la pestanya de Warp on ja és oberta. Serveix per a una configuració que no s'ha creat important de Warp, o que
/// es va crear abans de la 0.17.0 (sense `estat.json`). Sense lligam, l'app no sap que la pestanya ja és oberta (D13), i
/// la tornaria a obrir; ni quina conversa de Claude hi corre. Pura: del disc només mira la ruta canònica de les carpetes.
///
/// - **Ja lligada:** el seu pane és a Warp, o un Claude viu porta la seva marca. No es toca, i la seva pestanya de Warp no
///   s'ofereix a cap altra.
/// - **Criteris, de més segur a menys:** la conversa (el Claude viu d'un pane té la que recorda la pestanya); el títol i
///   la carpeta; només el títol; només la carpeta, que no pot ser la d'inici (el 03/11, 34 de 64 panes hi eren).
/// - **Com es veu una pestanya de Warp:** com a la importació (`Importador`): sense títol, el nom de la carpeta; amb el
///   pane a la carpeta d'inici, la del seu Claude.
/// - **On es busca:** per a cada criteri, de més segur a menys, primer a la finestra de Warp que correspon a cada
///   finestra de la configuració (la que en té més pestanyes amb el mateix títol) i després a totes. La carpeta sola no
///   lliga fora de la seva finestra, i un criteri feble no pren una pestanya que una altra finestra de la configuració
///   podria voler.
/// - **Només si és inequívoc:** si N pestanyes de la configuració i N de Warp comparteixen la clau, s'aparellen per
///   ordre; si no en són tantes com tantes, cap.
public enum LligamWarp {
    public enum Criteri: Int, Sendable, Comparable, CaseIterable {
        /// El Claude viu del pane té la conversa que recorda la pestanya.
        case conversa
        /// El mateix títol i la mateixa carpeta.
        case titolICarpeta
        /// El mateix títol; la carpeta és una altra (a Warp, sovint la d'inici, o la d'abans d'un canvi a mà).
        case titol
        /// La mateixa carpeta, a la finestra de Warp que correspon a la de la configuració; el títol és un altre.
        case carpeta

        public static func < (a: Criteri, b: Criteri) -> Bool { a.rawValue < b.rawValue }

        /// Prou segur per lligar-la sense que en David la miri: les altres surten al full per comprovar-les.
        public var segur: Bool { self <= .titolICarpeta }
    }

    /// Una pestanya de la configuració i la de Warp on és oberta.
    public struct Parella: Sendable, Equatable, Identifiable {
        public var finestra: String
        public var pestanya: Pestanya
        public var criteri: Criteri
        public var numeroWarp: Int
        /// «finestra 3 › Botiga».
        public var lloc: String
        public var titolWarp: String?
        public var carpetaWarp: String
        public var pane: String
        /// El Claude viu del pane: en dona la conversa.
        public var claude: SessioClaude?

        public var id: UUID { pestanya.id }
    }

    /// Una pestanya de la configuració que no té parella a Warp: si s'obre la seva finestra, s'obrirà.
    public struct SenseParella: Sendable, Equatable, Identifiable {
        public var finestra: String
        public var pestanya: Pestanya

        public var id: UUID { pestanya.id }
    }

    /// Una finestra de la configuració.
    public struct ResumFinestra: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var nom: String
        public var pestanyes: Int
        public var jaLligades: Int
        public var parelles: [UUID]
        /// Les finestres de Warp on són les pestanyes lligades (les d'abans i les noves), en ordre.
        public var numerosWarp: [Int]

        /// Les lligades si es confirma, sense les parelles `excepte`.
        public func lligades(excepte: Set<UUID> = []) -> Int {
            jaLligades + parelles.filter { !excepte.contains($0) }.count
        }
    }

    public struct Proposta: Sendable, Equatable {
        /// En l'ordre de la configuració.
        public var parelles: [Parella]
        public var senseParella: [SenseParella]
        public var jaLligades: Int
        /// Pestanyes de Warp que no serien de cap pestanya de la configuració.
        public var sobrants: Int
        public var finestres: [ResumFinestra]

        public func compta(_ criteri: Criteri) -> Int { parelles.filter { $0.criteri == criteri }.count }

        /// Els lligams per desar (`ActualitzaEstat.lliga`), sense les parelles `excepte` (les que s'han desmarcat).
        public func vincles(excepte: Set<UUID> = []) -> [UUID: VincleImportat] {
            Dictionary(uniqueKeysWithValues: parelles.filter { !excepte.contains($0.id) }.map {
                ($0.id, VincleImportat(pane: $0.pane, sessio: $0.claude?.sessionId, carpetaSessio: $0.claude?.carpeta))
            })
        }
    }

    // MARK: - El càlcul

    /// Una pestanya de Warp, com la veu la importació: el pane del Claude o, si no n'hi ha, el primer; la carpeta del
    /// Claude si el pane és a la d'inici; i, sense títol, el nom de la carpeta (`Importador.titol`).
    private struct DeWarp {
        var numero: Int
        var titol: String?
        var principal: PaneLlegit
        var carpeta: String
        /// El títol per comparar (`clauTitol`).
        var clau: String?
        var lloc: String
    }

    /// El que es lligaria: la pestanya de Warp, el pane (el principal o, per la conversa, el seu) i per què.
    private struct Triada {
        var warp: Int
        var pane: PaneLlegit
        var criteri: Criteri
    }

    /// Una pestanya de la configuració per lligar.
    private struct Pendent {
        var finestra: Int
        var pestanya: Pestanya
        var titol: String?
        var carpeta: String
    }

    /// - Parameter inici: la carpeta d'inici, canònica.
    public static func proposa(_ configuracio: Configuracio, lectura: LecturaWarp, estat: EstatApp,
                               inici: String) -> Proposta {
        var warp: [DeWarp] = []
        var perPane: [String: Int] = [:]
        for f in lectura.finestres {
            for p in f.pestanyes {
                guard let principal = p.panes.first(where: { $0.claude != nil }) ?? p.panes.first else { continue }
                let titol = p.titol.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                let carpeta = principal.carpeta == inici ? principal.claude?.carpeta ?? inici : principal.carpeta
                let darrer = (carpeta as NSString).lastPathComponent
                let perDefecte = carpeta == inici || darrer.isEmpty || darrer == "/" ? nil : darrer
                for pane in p.panes { perPane[pane.uuid] = warp.count }
                warp.append(DeWarp(numero: f.numero, titol: titol, principal: principal, carpeta: carpeta,
                                   clau: (titol ?? perDefecte).map { $0.trimmingCharacters(in: .whitespaces).lowercased() },
                                   lloc: "finestra \(f.numero) › \(titol ?? (principal.carpeta as NSString).lastPathComponent)"))
            }
        }
        let interactives = lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude)
            + lectura.sessionsSensePestanya
        let perMarca = Dictionary(interactives.compactMap { s in s.marca.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })

        // Les ja lligades, i les pestanyes de Warp que ocupen.
        var ocupades = Set<Int>()
        var jaLligades: [UUID: Int?] = [:]
        var pendents: [Pendent] = []
        for (f, finestra) in configuracio.finestres.enumerated() {
            for pestanya in finestra.pestanyes {
                if let sessio = perMarca[pestanya.id] {
                    let i = sessio.dinsDeWarp ? sessio.paneUUID.flatMap { perPane[$0] } : nil
                    if let i { ocupades.insert(i) }
                    jaLligades.updateValue(i, forKey: pestanya.id)
                } else if let pane = estat.pestanyes[pestanya.id]?.pane, let i = perPane[pane] {
                    ocupades.insert(i)
                    jaLligades.updateValue(i, forKey: pestanya.id)
                } else {
                    pendents.append(Pendent(finestra: f, pestanya: pestanya, titol: clauTitol(pestanya),
                                            carpeta: Rutes.canonica(pestanya.carpeta)))
                }
            }
        }

        var triades: [UUID: Triada] = [:]
        var lliures: Set<Int> { Set(warp.indices).subtracting(ocupades).subtracting(triades.values.map(\.warp)) }
        func sense() -> [Pendent] { pendents.filter { triades[$0.pestanya.id] == nil } }

        // 1. La conversa que recorda la pestanya, viva en un pane de Warp: es lliga aquell pane (en una pestanya
        //    dividida, potser no és el principal).
        var perSessio: [String: (Int, PaneLlegit)] = [:]
        for f in lectura.finestres {
            for p in f.pestanyes {
                for pane in p.panes {
                    if let sessio = pane.claude, let i = perPane[pane.uuid] { perSessio[sessio.sessionId] = (i, pane) }
                }
            }
        }
        // Dues pestanyes que recorden la mateixa conversa: cap (no se sap quina és).
        let recordades = pendents.compactMap { p in estat.pestanyes[p.pestanya.id]?.sessio.map { (p, $0) } }
        let vegades = Dictionary(grouping: recordades, by: \.1).mapValues(\.count)
        for (p, sessio) in recordades where vegades[sessio] == 1 {
            if let (i, pane) = perSessio[sessio], lliures.contains(i) {
                triades[p.pestanya.id] = Triada(warp: i, pane: pane, criteri: .conversa)
            }
        }

        // 2. La finestra de Warp de cada finestra de la configuració: la que en té més pestanyes pel títol (comptant
        //    les ja lligades); si n'hi ha dues d'iguals, la carpeta desempata; si encara, cap.
        let numeros = Array(Set(warp.map(\.numero))).sorted()
        var parellaDe: [Int: Int] = [:]
        for f in configuracio.finestres.indices {
            let ids = Set(configuracio.finestres[f].pestanyes.map(\.id))
            let seves = sense().filter { $0.finestra == f }
            let lliuresAra = lliures
            var puntuacions: [(numero: Int, forta: Int, feble: Int)] = []
            for numero in numeros {
                let aquesta = lliuresAra.filter { warp[$0].numero == numero }
                let lligades = jaLligades.filter { ids.contains($0.key) && $0.value.map { warp[$0].numero } == numero }.count
                    + triades.filter { ids.contains($0.key) && warp[$0.value.warp].numero == numero }.count
                let perTitol = seves.filter { p in p.titol != nil && aquesta.contains { warp[$0].clau == p.titol } }.count
                let perCarpeta = seves.filter { p in
                    p.carpeta != inici && aquesta.contains { warp[$0].carpeta == p.carpeta }
                }.count
                puntuacions.append((numero, lligades + perTitol, perCarpeta))
            }
            let millor = puntuacions.max { ($0.forta, $0.feble) < ($1.forta, $1.feble) }
            if let millor, millor.forta + millor.feble > 0,
               puntuacions.filter({ ($0.forta, $0.feble) == (millor.forta, millor.feble) }).count == 1 {
                parellaDe[f] = millor.numero
            }
        }

        /// Aparella les pendents i les de Warp que comparteixen la clau del criteri, si en són tantes com tantes. Amb
        /// `arreu`, a més, cap altra pendent de fora d'aquestes pot tenir la mateixa clau (un criteri feble a la finestra
        /// no ha de prendre la pestanya d'una altra finestra de la configuració).
        func emparella(_ pendents: [Pendent], _ deWarp: [Int], _ criteri: Criteri, arreu: [Pendent]? = nil) {
            func clauPendent(_ p: Pendent) -> String? {
                switch criteri {
                case .titolICarpeta: p.titol.map { $0 + "\u{0}" + p.carpeta }
                case .titol: p.titol
                case .carpeta: p.carpeta == inici ? nil : p.carpeta
                case .conversa: nil
                }
            }
            func clauWarp(_ i: Int) -> String? {
                let w = warp[i]
                return switch criteri {
                case .titolICarpeta: w.clau.map { $0 + "\u{0}" + w.carpeta }
                case .titol: w.clau
                case .carpeta: w.carpeta == inici ? nil : w.carpeta
                case .conversa: nil
                }
            }
            let deWarpPerClau = Dictionary(grouping: deWarp.filter { clauWarp($0) != nil }, by: { clauWarp($0)! })
            var vistes = Set<String>()
            for p in pendents {
                guard let k = clauPendent(p), vistes.insert(k).inserted, let candidates = deWarpPerClau[k] else { continue }
                let mateixa = pendents.filter { clauPendent($0) == k }
                guard mateixa.count == candidates.count,
                      arreu.map({ $0.filter { clauPendent($0) == k }.count == mateixa.count }) ?? true
                else { continue }
                for (pendent, i) in zip(mateixa, candidates) {
                    triades[pendent.pestanya.id] = Triada(warp: i, pane: warp[i].principal, criteri: criteri)
                }
            }
        }

        // 3. De més segur a menys; per a cada criteri, primer a la finestra de Warp de cada finestra de la configuració
        //    i després a totes. La carpeta sola, només a la seva finestra.
        for criteri in [Criteri.titolICarpeta, .titol, .carpeta] {
            for numero in Set(parellaDe.values).sorted() {
                let seves = sense().filter { parellaDe[$0.finestra] == numero }
                emparella(seves, lliures.filter { warp[$0].numero == numero }.sorted(), criteri,
                          arreu: criteri.segur ? nil : sense())
            }
            if criteri != .carpeta { emparella(sense(), lliures.sorted(), criteri) }
        }

        // El resultat, en l'ordre de la configuració.
        var parelles: [Parella] = []
        var senseParella: [SenseParella] = []
        var finestres: [ResumFinestra] = []
        for (f, finestra) in configuracio.finestres.enumerated() {
            var noves: [UUID] = []
            var numerosWarp = Set<Int>()
            var ja = 0
            for pestanya in finestra.pestanyes {
                if let i = jaLligades[pestanya.id] {
                    ja += 1
                    if let i { numerosWarp.insert(warp[i].numero) }
                } else if let triada = triades[pestanya.id] {
                    let w = warp[triada.warp]
                    parelles.append(Parella(finestra: finestra.nom, pestanya: pestanya, criteri: triada.criteri,
                                            numeroWarp: w.numero, lloc: w.lloc, titolWarp: w.titol,
                                            carpetaWarp: w.carpeta, pane: triada.pane.uuid, claude: triada.pane.claude))
                    noves.append(pestanya.id)
                    numerosWarp.insert(w.numero)
                } else if pendents.contains(where: { $0.pestanya.id == pestanya.id && $0.finestra == f }) {
                    senseParella.append(SenseParella(finestra: finestra.nom, pestanya: pestanya))
                }
            }
            finestres.append(ResumFinestra(id: finestra.id, nom: finestra.nom, pestanyes: finestra.pestanyes.count,
                                           jaLligades: ja, parelles: noves, numerosWarp: numerosWarp.sorted()))
        }
        return Proposta(parelles: parelles, senseParella: senseParella, jaLligades: jaLligades.count,
                        sobrants: lliures.count, finestres: finestres)
    }

    /// El títol per comparar: sense espais als extrems i en minúscules. A la configuració, si és buit, el nom de la
    /// carpeta (el que l'app posa al fitxer de Warp, `PestanyaYAML.titolAWarp`).
    private static func clauTitol(_ pestanya: Pestanya) -> String? {
        let titol = pestanya.titol.trimmingCharacters(in: .whitespaces)
        let valor = titol.isEmpty ? URL(filePath: pestanya.carpeta).lastPathComponent : titol
        return valor.isEmpty ? nil : valor.lowercased()
    }
}

extension ActualitzaEstat {
    /// «Lliga amb Warp…»: el pane de cada pestanya (`origen` `importacio`, com en importar). La conversa és la del Claude
    /// viu del pane; si no n'hi ha, la pestanya conserva la que recordava o, si no en recordava cap, hereta la de
    /// l'entrada que tenia el pane. Un pane, una pestanya: si una altra entrada el tenia, el perd.
    public static func lliga(_ vincles: [UUID: VincleImportat], estat: EstatApp, ara: Date) -> EstatApp {
        let ara = segons(ara)
        var nou = estat
        for (id, vincle) in vincles.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let anterior = nou.pestanyes.filter { $0.key != id && $0.value.pane == vincle.pane }
            let heretada = anterior.values.filter { $0.sessio != nil }.max { $0.vista < $1.vista }
            for altra in anterior.keys {
                nou.pestanyes[altra]?.pane = nil
                nou.pestanyes[altra]?.vista = ara
            }
            let abans = nou.pestanyes[id]
            let (sessio, carpeta): (String?, String?) = if let viva = vincle.sessio {
                (viva, vincle.carpetaSessio)
            } else if let propia = abans?.sessio {
                (propia, abans?.carpetaSessio)
            } else {
                (heretada?.sessio, heretada?.carpetaSessio)
            }
            nou.pestanyes[id] = VincleEstat(pane: vincle.pane, sessio: sessio, carpetaSessio: carpeta,
                                            origen: .importacio, vista: ara)
        }
        return nou
    }
}
