import Foundation

// Model de la lectura (fase 1): què hi ha obert a Warp i quina sessió de Claude corre a cada pestanya.
// És una fotografia: no es desa enlloc i no és encara la configuració de l'app (fase 2).

/// Estat de Warp i de les sessions de Claude en el moment de la lectura.
public struct LecturaWarp: Codable, Sendable, Equatable {
    public var finestres: [FinestraLlegida]
    /// Sessions interactives de Claude vives que no s'han pogut lligar amb cap pestanya de Warp:
    /// corren fora de Warp, o la seva pestanya encara no és (o ja no és) a la base de Warp.
    public var sessionsSensePestanya: [SessioClaude]
    public var avisos: [String]
    /// Sessions de Claude vives que no són interactives (`bg`, `daemon-worker`…). No es lliguen a cap pane: hereten
    /// l'UUID del pane on es va engegar el dimoni. La seva conversa no es pot reprendre en una pestanya (R9).
    public var sessionsNoInteractives: [SessioViva] = []
    /// Si l'app de Warp és oberta (`FontProcessos.warpObert`). Si no ho és, les finestres són les que Warp restaurarà
    /// en obrir-se. `nil`: no s'ha mirat.
    public var warpObert: Bool? = nil
    /// Els terminals vius de Warp (`FontProcessos.terminalsDeWarp`): el que hi ha obert ara, llegit dels processos.
    public var terminals: [TerminalViu] = []
    /// Si Warp desa les finestres a `warp.sqlite` (`LectorAjustosWarp`). `false`: la restauració de sessió és desactivada,
    /// i `finestres` és buit, perquè el que hi ha a la base no diu què hi ha obert. `nil`: no s'ha mirat.
    public var warpDesaFinestres: Bool? = nil
    /// Si `finestres` és una foto que pot no ser el que hi ha obert (`RefrescWarp`), per què.
    public var avisFoto: String? = nil
    /// Per què no es pot obrir res a Warp Stable (`InstallacioWarp.preview`): no hi ha cap Warp (0.31.1), només hi ha Warp
    /// Preview, o Warp Preview és obert i Warp Stable no (D-P12, 0.29.2). `nil`: no hi ha res a dir, o no s'ha mirat.
    public var warpPreview: WarpPreview? = nil
    /// Warp Stable hi és, però la seva base (`warp.sqlite`) no: Warp encara no hi ha desat res, com en un usuari de macOS on
    /// no s'ha obert mai (`Lector.llegeixDeLApp`). Llavors `finestres` és buit i `warpDesaFinestres` és `false`: el que hi ha
    /// obert ho diuen els processos, com amb la configuració de debò. `nil`: la base hi és, no s'ha mirat o no hi ha cap Warp
    /// Stable (ho diu `warpPreview`).
    public var warpSenseBase: Bool? = nil

    /// Per què no es pot importar ni lligar res amb la restauració de sessió desactivada.
    public static let senseFinestres = "Warp no desa les finestres mentre la restauració de sessió està desactivada "
        + "(«general.restore_session»): l'app no pot saber quines pestanyes hi ha ni com es diuen."

    /// Per què no es pot importar ni lligar res sense la base de Warp (`warpSenseBase`). L'app i el CLI (`llegeix`, `importa`
    /// i `obre`) diuen el mateix. No parla de la restauració de sessió: de sèrie és activada, i qui no ha obert mai Warp no
    /// l'ha desactivada. Amb Warp obert, potser encara arrenca (no s'ha vist quan crea la base); amb Warp tancat, que s'obri.
    public static func senseBase(warpObert: Bool) -> String {
        "Warp encara no ha desat cap finestra en aquest usuari: "
            + (warpObert ? "torna-ho a provar d'aquí a uns segons." : "obre'l un cop i torna-ho a provar.")
    }

    /// Les sessions interactives de Claude vives, lligades o no a una pestanya de Warp.
    public var sessionsInteractives: [SessioClaude] {
        finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude) + sessionsSensePestanya
    }

    /// La conversa de cada Claude obert per l'app que encara no ha escrit la seva sessió (acaba d'arrencar, o s'ha aturat a
    /// preguntar si confies en la carpeta), amb la pestanya. Si ja l'ha escrita, mana la sessió: després d'un `/clear`, els
    /// arguments del procés continuen dient la conversa d'abans.
    public var conversesArrencant: [String: UUID] {
        let ambSessio = Set(sessionsInteractives.compactMap(\.marca))
        var converses: [String: UUID] = [:]
        for terminal in terminals {
            if let conversa = terminal.conversa, let marca = terminal.marca, !ambSessio.contains(marca) {
                converses[conversa] = marca
            }
        }
        return converses
    }

    /// Les converses amb un Claude viu, en una pestanya, fora de Warp o en segon pla (R9).
    public var conversesVives: Set<String> {
        Set(sessionsInteractives.map(\.sessionId)).union(sessionsNoInteractives.map(\.sessionId)).union(conversesArrencant.keys)
    }
}

/// Un terminal viu de Warp: un fill del seu `terminal-server`, normalment una pestanya (o un dels panes d'una pestanya).
public struct TerminalViu: Codable, Sendable, Equatable {
    /// El pid del shell.
    public var pid: Int32
    /// La carpeta de treball del shell, canònica.
    public var carpeta: String?
    /// `WARP_TERMINAL_SESSION_UUID`, en minúscula: surt d'un fill del shell, perquè el shell no el mostra. Sense cap
    /// fill, no se sap.
    public var pane: String?
    /// La pestanya de la configuració que el va obrir (`WARP_LAUNCH_PESTANYA` d'un fill), si en té.
    public var marca: UUID?
    /// Hi corre un `claude`, tant si ja ha escrit la seva sessió com si s'ha aturat a preguntar si confies en la carpeta.
    public var claude: Bool
    /// La conversa que li han dit que reprengui (`--resume`, als arguments del `claude`). Pot ser vella: mana la seva sessió,
    /// si l'ha escrit (`LecturaWarp.conversesArrencant`).
    public var conversa: String?

    public init(pid: Int32, carpeta: String? = nil, pane: String? = nil, marca: UUID? = nil, claude: Bool = false,
                conversa: String? = nil) {
        self.pid = pid
        self.carpeta = carpeta
        self.pane = pane
        self.marca = marca
        self.claude = claude
        self.conversa = conversa
    }
}

/// Una sessió de Claude viva que no és interactiva.
public struct SessioViva: Codable, Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    /// `kind` del fitxer de sessió: `bg`, `daemon-worker`…
    public var tipus: String
    /// Carpeta canònica de la sessió.
    public var carpeta: String

    public init(pid: Int32, sessionId: String, tipus: String, carpeta: String) {
        self.pid = pid
        self.sessionId = sessionId
        self.tipus = tipus
        self.carpeta = carpeta
    }
}

public struct FinestraLlegida: Codable, Sendable, Equatable {
    /// Número de la finestra a la base de Warp (1…N). **No és estable:** Warp el renumera cada vegada que desa.
    public var numero: Int
    /// Posició (des de 0) de la pestanya activa, comptant totes les pestanyes de la finestra.
    public var pestanyaActiva: Int
    /// Només les pestanyes de terminal (les de Settings i similars no hi són).
    public var pestanyes: [PestanyaLlegida]
}

public struct PestanyaLlegida: Codable, Sendable, Equatable {
    /// Posició (des de 0) entre totes les pestanyes de la finestra, incloses les que no són de terminal.
    public var posicio: Int
    /// Títol posat a mà a Warp (`tabs.custom_title`).
    public var titol: String?
    /// Color de la pestanya, tal com el desa Warp (text YAML, per exemple `---\nColor: blue\n`).
    public var color: String?
    /// Panes de terminal, en ordre. Si la pestanya no està dividida, n'hi ha un.
    public var panes: [PaneLlegit]
}

/// D'on surt la carpeta d'un pane.
public enum OrigenCarpeta: String, Codable, Sendable {
    /// `terminal_panes.cwd`, la carpeta actual del shell segons Warp.
    case pane
    /// El `cwd` del pane era la carpeta d'inici i s'ha agafat la de l'última comanda de l'historial (`blocks.pwd`).
    case historial
}

public struct PaneLlegit: Codable, Sendable, Equatable {
    /// `WARP_TERMINAL_SESSION_UUID` del shell (32 xifres hexadecimals en minúscula).
    /// Identifica el pane encara que Warp renumeri finestres i pestanyes.
    public var uuid: String
    /// Carpeta canònica (sense symlinks i amb les majúscules del disc).
    public var carpeta: String
    public var origenCarpeta: OrigenCarpeta
    /// La carpeta encara existeix. L'historial pot apuntar a un repo que s'ha mogut.
    public var carpetaExisteix: Bool
    /// Sessió de Claude interactiva que corre en aquest pane, si n'hi ha.
    public var claude: SessioClaude?
}

public struct SessioClaude: Codable, Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    /// Nom de la sessió (`name` del fitxer de sessió).
    public var nom: String?
    /// D'on surt el nom (`nameSource`): `derived` vol dir que l'ha posat Claude.
    public var origenNom: String?
    /// Carpeta canònica de la sessió (`cwd` del fitxer de sessió).
    public var carpeta: String
    /// `idle`, `busy`…, tal com el desa Claude.
    public var estat: String?
    public var iniciada: Date?
    /// Arguments exactes del procés (`argv`), llegits del sistema.
    public var ordre: [String]
    public var opcions: OpcionsClaude
    /// `WARP_TERMINAL_SESSION_UUID` de l'entorn del procés, en minúscula.
    public var paneUUID: String?
    /// El procés penja de `stable terminal-server`, és a dir, d'un shell de Warp.
    public var dinsDeWarp: Bool
    /// La pestanya de la configuració que el va obrir (`WARP_LAUNCH_PESTANYA` de l'entorn del procés, fase 3.1), si
    /// és un UUID. Les sessions que no ha obert l'app no en tenen.
    public var marca: UUID? = nil
}
