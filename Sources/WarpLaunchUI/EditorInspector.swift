import Foundation
import WarpLaunchCore

// L'inspector (docs/disseny.md, «Disposició», i pas 9): què mostra i com canvia els camps de Claude d'una o de
// diverses pestanyes. La vista només hi posa els controls.

extension Editor {
    /// Què mostra l'inspector.
    public enum ContingutInspector: Equatable {
        /// Res a editar: el text que es mostra.
        case res(String)
        /// Cap pestanya triada: la finestra.
        case finestra(Finestra)
        case pestanya(Pestanya)
        /// Diverses pestanyes: només el bloc de Claude, amb «Valors diversos».
        case pestanyes([Pestanya])
    }

    public var contingutInspector: ContingutInspector {
        let triades = pestanyes
        if triades.count == 1 { return .pestanya(triades[0]) }
        if triades.count > 1 { return .pestanyes(triades) }
        if perRevisar {
            return .res(perRevisarPerFinestra.isEmpty ? "Res per revisar" : "Tria una pestanya per revisar-la")
        }
        if let finestra { return .finestra(finestra) }
        return .res(configuracio.finestres.isEmpty ? "Cap finestra" : "Tria una finestra")
    }

    // MARK: - Camps amb opcions (model, esforç, mode de permisos)

    /// El valor d'un camp amb opcions a les pestanyes triades.
    public enum Tria: Hashable, Sendable {
        /// Sense valor: Claude fa servir el seu.
        case perDefecte
        case valor(String)
        /// Les pestanyes triades no hi coincideixen.
        case diversos
    }

    public struct Opcio: Hashable, Sendable, Identifiable {
        public let tria: Tria
        public let text: String
        public var id: Tria { tria }
    }

    public enum CampTria: Sendable, CaseIterable {
        case model, esforc, modePermisos

        var cami: WritableKeyPath<ClaudePestanya, String?> {
            switch self {
            case .model: \.model
            case .esforc: \.esforc
            case .modePermisos: \.modePermisos
            }
        }

        /// El nom del pas de Desfés.
        public var accio: String {
            switch self {
            case .model: "Canvia el model"
            case .esforc: "Canvia l'esforç"
            case .modePermisos: "Canvia el mode de permisos"
            }
        }

        var coneguts: [String] {
            switch self {
            case .model: ClaudePestanya.modelsConeguts
            case .esforc: ClaudePestanya.esforcosConeguts
            case .modePermisos: ClaudePestanya.modesPermisos
            }
        }

        /// El valor tal com el tracta l'inspector: un àlies de model amb majúscules («Opus») és l'àlies, perquè no
        /// surti dues vegades al desplegable. La resta, tal com està escrita (els modes distingeixen majúscules).
        func canonic(_ valor: String) -> String {
            guard self == .model, coneguts.contains(valor.lowercased()) else { return valor }
            return valor.lowercased()
        }

        /// Un valor que Claude no coneix es mostra tal com està escrit, amb «(desconegut)»; un model que no és un
        /// àlies (un id complet), tal com està escrit.
        func text(_ valor: String) -> String {
            switch self {
            case .model: return ClaudePestanya.nomModel(valor)
            case .esforc:
                return coneguts.contains(valor) ? ClaudePestanya.nomEsforc(valor) : "\(valor) (desconegut)"
            case .modePermisos:
                return coneguts.contains(valor) ? ClaudePestanya.nomMode(valor) : "\(valor) (desconegut)"
            }
        }
    }

    public func tria(_ camp: CampTria) -> Tria {
        Self.tria(camp, de: pestanyes.map(\.claude))
    }

    /// «Per defecte», els valors coneguts i els que tenen les pestanyes triades (encara que Claude no els conegui:
    /// si no, el control no els podria mostrar). Amb valors diferents, primer «Valors diversos».
    public func opcions(_ camp: CampTria) -> [Opcio] {
        Self.opcions(camp, de: pestanyes.map(\.claude))
    }

    /// El valor d'un camp a unes opcions de Claude (les pestanyes triades, o la plantilla).
    static func tria(_ camp: CampTria, de claudes: [ClaudePestanya]) -> Tria {
        let valors = claudes.map { $0[keyPath: camp.cami].map(camp.canonic) }
        guard let primer = valors.first else { return .perDefecte }
        guard valors.allSatisfy({ $0 == primer }) else { return .diversos }
        return primer.map { .valor($0) } ?? .perDefecte
    }

    static func opcions(_ camp: CampTria, de claudes: [ClaudePestanya]) -> [Opcio] {
        var valors = camp.coneguts
        for claude in claudes {
            if let valor = claude[keyPath: camp.cami].map(camp.canonic), !valors.contains(valor) { valors.append(valor) }
        }
        var opcions = [Opcio(tria: .perDefecte, text: "Per defecte")]
            + valors.map { Opcio(tria: .valor($0), text: camp.text($0)) }
        if tria(camp, de: claudes) == .diversos { opcions.insert(Opcio(tria: .diversos, text: "Valors diversos"), at: 0) }
        return opcions
    }

    /// Posa el valor a totes les pestanyes triades, en un sol pas de Desfés. «Valors diversos» no fa res.
    public func tria(_ camp: CampTria, a tria: Tria) {
        let valor: String?
        switch tria {
        case .diversos: return
        case .perDefecte: valor = nil
        case let .valor(text): valor = text
        }
        canviaClaude(Set(pestanyes.map(\.id)), nom: camp.accio) { $0[keyPath: camp.cami] = valor }
    }

    // MARK: - Camps sí o no

    public enum CampSiNo: Sendable, CaseIterable {
        case activat, ultracode, continua, saltaPermisos

        var cami: WritableKeyPath<ClaudePestanya, Bool> {
            switch self {
            case .activat: \.activat
            case .ultracode: \.ultracode
            case .continua: \.continua
            case .saltaPermisos: \.saltaPermisos
            }
        }

        /// El nom del pas de Desfés.
        public func accio(_ valor: Bool) -> String {
            switch self {
            case .activat: valor ? "Activa Claude" : "Desactiva Claude"
            case .ultracode: valor ? "Activa l'ultracode" : "Desactiva l'ultracode"
            case .continua: valor ? "Continua la conversa" : "No continuïs la conversa"
            case .saltaPermisos: valor ? "Salta els permisos" : "No saltis els permisos"
            }
        }
    }

    public func siNo(_ camp: CampSiNo) -> Comu<Bool> {
        comu { $0.claude[keyPath: camp.cami] }
    }

    /// Posa el valor a totes les pestanyes triades, en un sol pas de Desfés.
    ///
    /// Un interruptor amb «Valors diversos» (`Toggle(sources:)`) crida això un cop per pestanya: la primera crida les
    /// canvia totes, i les altres ja no canvien res ni registren cap pas.
    public func posa(_ camp: CampSiNo, _ valor: Bool) {
        canviaClaude(Set(pestanyes.map(\.id)), nom: camp.accio(valor)) { $0[keyPath: camp.cami] = valor }
    }

    /// Claude és apagat a totes les pestanyes triades: la resta del bloc queda desactivada.
    public var claudeApagatATotes: Bool { siNo(.activat) == .un(false) }

    /// «Salta els permisos» és activat a totes les triades: Claude no fa cas del mode (2.1.318), i el control queda
    /// desactivat. Si en tenen un, l'avís ofereix treure'l.
    public var modeSenseEfecte: Bool { siNo(.saltaPermisos) == .un(true) }

    // MARK: - Camps de text

    /// El nom fix de la sessió (`-n`). Un text buit o fet d'espais el treu.
    public func canviaNomSessio(_ id: Pestanya.ID, a nom: String, agrupa: String? = nil) {
        let net = nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nom
        canviaClaude([id], nom: "Canvia el nom de la sessió", agrupa: agrupa) { $0.nom = net }
    }

    // MARK: - Carpeta

    /// On s'obre el diàleg «Tria…» de la carpeta: a la carpeta pare, per veure'n les germanes, o a la més propera que
    /// existeixi si ja no hi és (l'avís «La carpeta no existeix»). Si no n'hi ha cap, o la pestanya és a `~`, a la
    /// d'inici.
    public func carpetaPerTriar(_ pestanya: Pestanya) -> String {
        let carpeta = (pestanya.carpeta as NSString).standardizingPath
        guard carpeta.hasPrefix("/"), carpeta != inici else { return inici }
        var ruta = (carpeta as NSString).deletingLastPathComponent
        while ruta != "/", !ruta.isEmpty {
            if carpetaExisteix(ruta) { return ruta }
            ruta = (ruta as NSString).deletingLastPathComponent
        }
        return inici
    }

    // MARK: - Avisos

    /// Els avisos d'una pestanya, repartits per on surten a l'inspector: sota la carpeta, o al bloc de Claude.
    /// «Claude és apagat» no hi surt (ho diu l'interruptor), ni el de l'ordre (ho diu el bloc de l'ordre).
    public func avisosInspector(_ id: Pestanya.ID) -> (carpeta: [Avis], claude: [Avis]) {
        var carpeta: [Avis] = []
        var claude: [Avis] = []
        for avis in avisos.pestanyes[id] ?? [] {
            switch avis.tipus {
            case .carpetaNoAbsoluta, .carpetaInici, .carpetaNoExisteix: carpeta.append(avis)
            case .claudeApagat, .ordreImpossible: break
            default: claude.append(avis)
            }
        }
        return (carpeta, claude)
    }
}
