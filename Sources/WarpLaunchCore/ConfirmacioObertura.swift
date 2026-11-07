import Foundation

/// El que s'ha vist a Warp després d'obrir: la finestra nova, els terminals nous i les sessions de Claude que ja porten
/// la marca.
public struct Confirmacio: Sendable, Equatable {
    /// El número de la finestra nova de Warp, si s'ha trobat. Amb la restauració de sessió desactivada, mai: Warp no desa
    /// les finestres, i la prova són els terminals.
    public var finestra: Int?
    /// Les pestanyes que ja tenen el seu terminal viu: per la marca o, si encara no en té, per la carpeta.
    public var terminals: Set<UUID>
    /// El pane de cada pestanya oberta: de la finestra nova (per ordre) o de la marca, que mana.
    public var panes: [UUID: String]
    /// La conversa de cada pestanya que ja té el seu Claude en marxa.
    public var sessions: [UUID: String]
    /// Les pestanyes amb el terminal reconegut per la marca: segur que són d'aquest fitxer.
    public var marcats: Set<UUID>
    /// El terminal sense marca que s'ha pres per a cada pestanya, només per la carpeta. Amb diverses finestres alhora
    /// («Obre-ho tot»), podria ser d'una altra: no el pot prendre ningú més.
    public var perCarpeta: [UUID: Int32]

    public init(finestra: Int?, panes: [UUID: String], sessions: [UUID: String], terminals: Set<UUID> = [],
                marcats: Set<UUID> = [], perCarpeta: [UUID: Int32] = [:]) {
        self.finestra = finestra
        self.terminals = terminals
        self.panes = panes
        self.sessions = sessions
        self.marcats = marcats
        self.perCarpeta = perCarpeta
    }

    /// Hi ha un senyal que és d'aquest fitxer, i no d'una altra finestra que s'obre alhora: la finestra nova, una sessió o
    /// un terminal amb la marca. Un terminal reconegut només per la carpeta no ho és.
    public var segura: Bool { finestra != nil || !sessions.isEmpty || !marcats.isEmpty }

    /// Hi afegeix el que s'ha vist en una lectura posterior: la finestra, si se n'ha trobat (amb els seus panes), i les
    /// marques. El que es veu més tard mana.
    public mutating func afegeix(_ nova: Confirmacio) {
        if let numero = nova.finestra { finestra = numero }
        terminals.formUnion(nova.terminals)
        panes.merge(nova.panes) { _, nou in nou }
        sessions.merge(nova.sessions) { _, nova in nova }
        marcats.formUnion(nova.marcats)
        perCarpeta.merge(nova.perCarpeta) { _, nou in nou }
    }

    /// S'ha vist que Warp ha obert aquestes pestanyes: la finestra nova, o un terminal nou per a cadascuna.
    public func vista(_ pestanyes: [UUID]) -> Bool {
        finestra != nil || (!pestanyes.isEmpty && pestanyes.allSatisfy(terminals.contains))
    }

    /// Ja s'ha vist tot: la finestra (o els terminals) i el Claude de cada pestanya que n'ha de tenir.
    public func completa(_ obertes: [PestanyaAObrir]) -> Bool {
        vista(obertes.map(\.pestanya.id)) && obertes.allSatisfy { $0.argv == nil || sessions[$0.pestanya.id] != nil }
    }

    /// Les pestanyes amb Claude del fitxer que encara no s'han vist.
    public func senseClaude(_ obertes: [PestanyaAObrir]) -> [PestanyaAObrir] {
        obertes.filter { $0.argv != nil && sessions[$0.pestanya.id] == nil }
    }
}

/// Com se sap que Warp ha obert la finestra (docs/disseny.md, secció 7, «Flux», 8): l'app llegeix Warp cada 0,5 s fins a
/// 30 s i hi busca tres coses:
/// - **Les sessions amb la marca** d'una pestanya del fitxer, començades després d'obrir (amb 5 s de marge). Donen la
///   conversa i el pane d'aquella pestanya amb certesa.
/// - **La finestra nova:** una finestra de Warp amb tots els panes nous (no hi eren abans d'obrir), un per pestanya, i el
///   mateix nombre de pestanyes que el fitxer. Si conté el pane d'una marca a la seva posició, és la nostra. Si no,
///   ha de ser l'única que encaixa amb els títols i les carpetes, en ordre: un títol que Warp no ha desat o una carpeta
///   que encara és la d'inici (la shell no l'ha dit) no la descarten, però cal almenys un títol o una carpeta que
///   coincideixi (una finestra nova feta a mà, sense títol i a l'inici, no compta).
/// - **Els terminals nous** (no hi eren abans d'obrir), només amb la restauració de sessió desactivada, on són l'única prova:
///   amb la restauració activada mana la base, i un shell restaurat tard semblaria nou. El que porta la marca d'una
///   pestanya és el seu, encara que Claude s'hagi aturat a preguntar i no hagi escrit la sessió. Els altres compten per la
///   carpeta, un per pestanya. Si l'app acaba d'engegar Warp, la carpeta d'inici no compta: hi és la finestra buida.
/// Pura: no llegeix res.
public enum ConfirmacioObertura {
    /// Marge per al rellotge de la sessió: `startedAt` el posa Claude, i pot anar una mica per darrere.
    public static let marge: TimeInterval = 5

    /// `obertes`: les pestanyes del fitxer, en ordre. `panesAbans` i `terminalsAbans`: els de la lectura del pla. `desDe`:
    /// quan s'ha obert. `inici`: la carpeta d'inici canònica. `warpAcabatDEngegar`: l'ha obert l'app per obrir la finestra.
    /// `nil` si encara no hi ha res.
    public static func busca(_ lectura: LecturaWarp, obertes: [PestanyaAObrir], panesAbans: Set<String>,
                             terminalsAbans: Set<Int32>, desDe: Date, inici: String,
                             warpAcabatDEngegar: Bool = false) -> Confirmacio? {
        let posicio = Dictionary(uniqueKeysWithValues: obertes.enumerated().map { ($1.pestanya.id, $0) })

        var sessions: [UUID: String] = [:]
        var panesMarca: [UUID: String] = [:]
        let interactives = lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude)
            + lectura.sessionsSensePestanya
        for sessio in interactives {
            guard let marca = sessio.marca, posicio[marca] != nil, let iniciada = sessio.iniciada,
                  iniciada >= desDe - marge
            else { continue }
            sessions[marca] = sessio.sessionId
            if sessio.dinsDeWarp, let pane = sessio.paneUUID { panesMarca[marca] = pane }
        }

        var terminals = Set<UUID>()
        var marcats = Set<UUID>()
        var perCarpeta: [UUID: Int32] = [:]
        var senseMarca: [TerminalViu] = []
        let vius = lectura.warpDesaFinestres == false ? lectura.terminals : []
        for terminal in vius where !terminalsAbans.contains(terminal.pid) {
            guard let marca = terminal.marca else {
                senseMarca.append(terminal)
                continue
            }
            guard posicio[marca] != nil else { continue }
            terminals.insert(marca)
            marcats.insert(marca)
            if panesMarca[marca] == nil { panesMarca[marca] = terminal.pane }
        }
        for pestanya in obertes where !terminals.contains(pestanya.pestanya.id) {
            let carpeta = Rutes.canonica(pestanya.yaml.carpeta)
            guard !warpAcabatDEngegar || carpeta != inici,
                  let i = senseMarca.firstIndex(where: { $0.carpeta == carpeta })
            else { continue }
            terminals.insert(pestanya.pestanya.id)
            perCarpeta[pestanya.pestanya.id] = senseMarca[i].pid
            senseMarca.remove(at: i)
        }

        // La finestra que conté el pane d'una marca, a la posició de la seva pestanya; si no n'hi ha, la que encaixa.
        let noves = lectura.finestres.filter { nova($0, obertes: obertes, panesAbans: panesAbans) }
        let ancorades = noves.filter { finestra in
            panesMarca.contains { id, pane in
                guard let n = posicio[id], n < finestra.pestanyes.count else { return false }
                return finestra.pestanyes[n].panes.first?.uuid == pane
            }
        }
        let candidates = ancorades.isEmpty ? noves.filter { encaixa($0, obertes: obertes, inici: inici) } : ancorades

        var panes: [UUID: String] = [:]
        var numero: Int?
        if candidates.count == 1, let finestra = candidates.first {
            numero = finestra.numero
            for (pestanya, llegida) in zip(obertes, finestra.pestanyes) {
                panes[pestanya.pestanya.id] = llegida.panes.first?.uuid
            }
        }
        panes.merge(panesMarca) { _, marca in marca }

        guard numero != nil || !sessions.isEmpty || !terminals.isEmpty else { return nil }
        return Confirmacio(finestra: numero, panes: panes, sessions: sessions, terminals: terminals, marcats: marcats,
                           perCarpeta: perCarpeta)
    }

    /// El mateix nombre de pestanyes que el fitxer, cadascuna amb un sol pane, i cap pane d'abans d'obrir.
    private static func nova(_ finestra: FinestraLlegida, obertes: [PestanyaAObrir], panesAbans: Set<String>) -> Bool {
        guard !obertes.isEmpty, finestra.pestanyes.count == obertes.count else { return false }
        return finestra.pestanyes.allSatisfy { llegida in
            llegida.panes.count == 1 && !panesAbans.contains(llegida.panes[0].uuid)
        }
    }

    /// Cap títol ni carpeta diferent del fitxer, i almenys un d'igual.
    private static func encaixa(_ finestra: FinestraLlegida, obertes: [PestanyaAObrir], inici: String) -> Bool {
        var coincideix = false
        for (pestanya, llegida) in zip(obertes, finestra.pestanyes) {
            guard let pane = llegida.panes.first else { return false }
            if let titol = llegida.titol, !titol.isEmpty {
                guard titol == pestanya.yaml.titolAWarp else { return false }
                coincideix = true
            }
            // A l'inici, la carpeta no diu res: potser la shell encara no l'ha dit.
            if pane.carpeta != inici {
                guard pane.carpeta == Rutes.canonica(pestanya.yaml.carpeta) else { return false }
                coincideix = true
            }
        }
        return coincideix
    }
}
