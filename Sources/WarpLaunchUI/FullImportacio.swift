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
            estat = .senseFinestres(LecturaWarp.senseFinestres + (mode == .crea
                ? " No hi ha res per importar: tria «Comença en blanc» i afegeix-hi les pestanyes."
                : " No hi ha res per importar, i la configuració no canvia."))
        case let .success(lectura):
            avisosLectura = lectura.avisos
            plantillaPrevista = editor.plantillaPerImportar.normalitzada()
            estat = .llest(editor.previsualitza(lectura))
        case let .failure(error):
            estat = .error(error.description)
        }
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

    /// Les xifres, una per línia: finestres i pestanyes, amb Claude, sense, i quantes salten els permisos.
    public var xifres: [String] {
        guard let importacio else { return [] }
        let resum = importacio.resum
        var linies = [
            "\(Plural.compta(resum.finestres, "finestra", "finestres")) · \(Plural.compta(resum.pestanyes, "pestanya", "pestanyes"))",
            "\(resum.ambSessio + resum.ambPlantilla) amb Claude: \(resum.ambSessio) amb l'ordre de la seva sessió i "
                + "\(resum.ambPlantilla) amb la plantilla",
        ]
        if resum.senseClaude > 0 {
            let aInici = importacio.compta(.carpetaInici)
            let perdudes = importacio.compta(.carpetaNoExisteix)
            let altres = resum.senseClaude - aInici - perdudes
            var motius: [String] = []
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

    /// L'ordre de les pestanyes que no tenien Claude obert (la plantilla), o `nil` si no n'hi ha cap.
    public var ordrePlantilla: String? {
        guard let importacio, importacio.resum.ambPlantilla > 0 else { return nil }
        let plantilla = importacio.configuracio.finestres.flatMap(\.pestanyes)
            .first { importacio.origens[$0.id] == .plantilla }?.claude
        return plantilla.flatMap { try? OrdreClaude.argv($0, repren: nil) }.map(OrdreClaude.text)
    }

    /// «16 pestanyes sortiran a «Per revisar»», o `nil` si no n'hi ha cap.
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
