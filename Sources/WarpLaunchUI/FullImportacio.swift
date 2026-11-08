import Foundation
import Observation
import WarpLaunchCore

/// El full d'importació (docs/disseny.md, «Importació (R2)»). Llegeix Warp, diu amb xifres què en sortiria i, només
/// amb «Crea» o «Substitueix», ho passa a l'editor. Fins llavors no escriu res. No obre res de Warp ni de Claude.
@MainActor
@Observable
public final class FullImportacio {
    public enum Mode: Equatable {
        /// Encara no hi ha configuració: «Crea» la desa de seguida.
        case crea
        /// «Torna a importar-ho tot…»: substitueix les finestres, amb còpia i Desfés.
        case substitueix
    }

    public enum Estat: Equatable {
        case llegint
        case error(String)
        /// La lectura ha anat bé, però Warp no desa les finestres (`LecturaWarp.senseFinestres`): no hi ha res per importar.
        case senseFinestres(String)
        case llest(Importacio)
    }

    public let mode: Mode
    public private(set) var estat: Estat = .llegint
    /// Avisos de la lectura de Warp (per exemple, que no s'han pogut llegir les sessions de Claude): expliquen xifres
    /// que, si no, semblarien equivocades.
    public private(set) var avisosLectura: [String] = []
    /// La plantilla amb què s'ha previsualitzat. Si després canvia a la Configuració (o s'hi desfà), les pestanyes de
    /// la previsualització la porten vella: «Substitueix» queda desactivat fins a tornar a llegir.
    public private(set) var plantillaPrevista: ClaudePestanya?
    @ObservationIgnored private let editor: Editor
    @ObservationIgnored private let warp: EstatWarp

    /// `nil` si l'editor no pot importar (la configuració no es pot llegir, o encara s'està carregant).
    public init?(editor: Editor, warp: EstatWarp) {
        switch editor.estat {
        case .senseConfiguracio: mode = .crea
        case .oberta: mode = .substitueix
        case .carregant, .error: return nil
        }
        self.editor = editor
        self.warp = warp
    }

    /// Torna a llegir Warp (en obrir el full i amb «Torna a llegir»).
    public func llegeix() async {
        estat = .llegint
        avisosLectura = []
        switch await warp.llegeixAmbFinestres() {
        case let .success(lectura) where lectura.warpDesaFinestres == false:
            // Importar substituiria la configuració per res.
            estat = .senseFinestres(LecturaWarp.senseFinestres + queFerSenseFinestres)
        case let .success(lectura):
            avisosLectura = lectura.avisos
            plantillaPrevista = editor.plantillaPerImportar.normalitzada()
            estat = .llest(editor.previsualitza(lectura))
        case let .failure(error):
            estat = .error(error.description)
        }
    }

    /// Què fer quan Warp no desa les finestres. Sense refresc (D19), l'app no ha pogut demanar a Warp que les desi: és una
    /// carpeta de prova (`--config`), on l'app no toca l'ajust, i no és que Warp no tingui res. Sense el consentiment
    /// tampoc no n'hi ha, però llavors el full no es pot obrir (D-P4). Amb el refresc, la foto sempre hi és
    /// (`BaseWarp.sempre`): el text de sempre, per si de cas.
    private var queFerSenseFinestres: String {
        guard warp.refresc == nil else {
            return mode == .crea
                ? " No hi ha res per importar: tria «Comença en blanc» i afegeix-hi les pestanyes."
                : " No hi ha res per importar, i la configuració no canvia."
        }
        return " Amb una configuració de prova (--config), l'app no toca aquest ajust i no pot demanar a Warp que les "
            + "desi. Amb la configuració de debò, sí: l'activa uns segons perquè Warp les desi, i el torna a desactivar."
            + (mode == .crea ? " Aquí, tria «Comença en blanc» i afegeix-hi les pestanyes." : " La configuració no canvia.")
    }

    public var importacio: Importacio? {
        if case let .llest(importacio) = estat { importacio } else { nil }
    }

    /// La plantilla ha canviat des de la previsualització.
    public var plantillaHaCanviat: Bool {
        importacio != nil && plantillaPrevista != editor.plantillaPerImportar.normalitzada()
    }

    /// Hi ha una importació llesta, i l'editor (i la plantilla) encara són com quan s'ha llegit.
    public var potConfirmar: Bool {
        guard importacio != nil, !plantillaHaCanviat else { return false }
        return switch mode {
        case .crea: editor.estat == .senseConfiguracio
        // Una lectura sense cap finestra de terminal deixaria la configuració buida, i Retorn prem «Substitueix».
        case .substitueix: editor.potEditar && importacio?.configuracio.finestres.isEmpty == false
        }
    }

    /// «Crea» o «Substitueix».
    /// - Returns: `false` si no s'ha fet res.
    @discardableResult
    public func confirma() -> Bool {
        guard potConfirmar, let importacio else { return false }
        switch mode {
        case .crea: editor.crea(amb: importacio)
        case .substitueix: editor.substitueix(amb: importacio)
        }
        return true
    }

    // MARK: - Textos del full

    public var titol: String {
        mode == .crea ? "Importa de Warp" : "Torna a importar-ho tot de Warp"
    }

    public var boto: String {
        mode == .crea ? "Crea" : "Substitueix"
    }

    /// Les xifres, una per línia: finestres i pestanyes, amb Claude, sense, i quantes salten els permisos. En una
    /// configuració nova, les pestanyes que no tenien Claude obert queden només terminal (D-P5a): la plantilla no hi surt.
    public var xifres: [String] {
        guard let importacio else { return [] }
        let resum = importacio.resum
        let ambClaude = resum.ambSessio + resum.ambPlantilla
        var linies = [
            "\(Plural.compta(resum.finestres, "finestra", "finestres")) · \(Plural.compta(resum.pestanyes, "pestanya", "pestanyes"))",
        ]
        if resum.senseClaudeObert > 0, resum.ambPlantilla == 0 {
            linies.append(ambClaude == 0 ? "0 amb Claude" : "\(ambClaude) amb Claude, amb l'ordre de la seva sessió")
        } else {
            linies.append("\(ambClaude) amb Claude: \(resum.ambSessio) amb l'ordre de la seva sessió i "
                + "\(resum.ambPlantilla) amb la plantilla")
        }
        if resum.senseClaude > 0 {
            let aInici = importacio.compta(.carpetaInici)
            let perdudes = importacio.compta(.carpetaNoExisteix)
            let altres = resum.senseClaude - resum.senseClaudeObert - aInici - perdudes
            var motius: [String] = []
            if resum.senseClaudeObert > 0 { motius.append("\(resum.senseClaudeObert) sense Claude obert") }
            if aInici > 0 { motius.append("\(aInici) a la carpeta d'inici") }
            if perdudes > 0 { motius.append("\(perdudes) amb una carpeta que ja no existeix") }
            if altres > 0, !motius.isEmpty { motius.append("\(altres) més") }
            linies.append("\(resum.senseClaude) només terminal" + (motius.isEmpty ? "" : ": " + Self.enumera(motius)))
        }
        if resum.saltenPermisos > 0 {
            linies.append(Plural.compta(resum.saltenPermisos, "salta", "salten") + " els permisos (--dangerously-skip-permissions)")
        }
        return linies
    }

    /// L'ordre de les pestanyes que no tenien Claude obert (la plantilla), o `nil` si no n'hi ha cap. En tornar a
    /// importar, s'hi obrirà; en una configuració nova, queden només terminal i és la que hi tindran si s'hi activa
    /// Claude (`notaSenseClaudeObert`).
    public var ordrePlantilla: String? {
        guard let importacio else { return nil }
        let pestanyes = importacio.configuracio.finestres.flatMap(\.pestanyes)
        var claude: ClaudePestanya
        if importacio.resum.ambPlantilla > 0,
           let dePlantilla = pestanyes.first(where: { importacio.origens[$0.id] == .plantilla }) {
            claude = dePlantilla.claude
        } else if let terminal = pestanyes.first(where: { importacio.origens[$0.id] == .nomesTerminal }) {
            claude = terminal.claude
            claude.activat = true
        } else {
            return nil
        }
        return (try? OrdreClaude.argv(claude, repren: nil)).map(OrdreClaude.text)
    }

    /// En una configuració nova, què passa amb les pestanyes que no tenien Claude obert (D-P5a), o `nil` si no n'hi ha
    /// cap.
    public var notaSenseClaudeObert: String? {
        guard let importacio, importacio.resum.senseClaudeObert > 0 else { return nil }
        let n = importacio.resum.senseClaudeObert
        return (n == 1 ? "Queda" : "Queden") + " només terminal. Per obrir-hi Claude, marca «Obre Claude Code en "
            + "aquesta pestanya» a l'inspector: s'hi obrirà amb aquesta ordre."
    }

    /// «6 pestanyes sortiran a «Per revisar»», o `nil` si no n'hi ha cap.
    public var textPerRevisar: String? {
        let n = perRevisar
        return n == 0 ? nil : Plural.compta(n, "pestanya sortirà", "pestanyes sortiran") + " a «Per revisar»"
    }

    /// Pestanyes que sortiran a «Per revisar».
    public var perRevisar: Int {
        guard let importacio else { return 0 }
        let avisos = editor.avisos(de: importacio.configuracio)
        return avisos.pestanyes.values.filter { llista in llista.contains { $0.gravetat >= .avis } }.count
    }

    /// Què passarà en confirmar.
    public var explicacio: String {
        switch mode {
        case .crea:
            "Es desarà la configuració\(editor.rutaFitxer.map { " a \($0)" } ?? ""). No s'obre res de Warp ni de Claude."
        case .substitueix:
            "Substitueix el que hi ha ara (\(Plural.compta(editor.configuracio.finestres.count, "finestra", "finestres"))"
                + " i \(Plural.compta(editor.configuracio.finestres.flatMap(\.pestanyes).count, "pestanya", "pestanyes"))). "
                + "Abans de desar se'n fa una còpia, i es pot desfer amb ⌘Z. La plantilla no canvia."
        }
    }

    /// «a», «a i b», «a, b i c».
    private static func enumera(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " i " + parts.last!
    }
}
