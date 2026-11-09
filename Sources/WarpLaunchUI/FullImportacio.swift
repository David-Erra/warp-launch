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
        /// La lectura ha anat bé, però no en surten finestres (`MotiuSenseFinestres`): no hi ha res per importar.
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

    /// Si el full pot llegir Warp: la lectura activa uns segons la restauració (D19), i no es pot fer mentre s'obre res a Warp
    /// ni mentre s'aplica una actualització (`Obertura.impedeixRefresc`). Els botons del full es desactiven.
    public var potLlegir: Bool { editor.obertura?.impedeixRefresc != true }

    /// Per què el full no ha pogut llegir Warp en obrir-se (`potLlegir`).
    static let motiuNoEsPotLlegir = "ara mateix s'està obrint alguna finestra a Warp, o Warp Launch s'està actualitzant. "
        + "Torna-ho a provar quan acabi."

    /// Torna a llegir Warp (en obrir el full, amb «Actualitza l'estat de Warp» i amb «Torna-ho a provar»). Si ara no es pot
    /// (`potLlegir`), el que el full ja mostra es queda; només en obrir-se, sense res per mostrar, diu per què.
    public func llegeix() async {
        guard potLlegir else {
            if estat == .llegint { estat = .error(Self.motiuNoEsPotLlegir) }
            return
        }
        estat = .llegint
        avisosLectura = []
        switch await warp.llegeixAmbFinestres() {
        case let .success(lectura):
            if let motiu = MotiuSenseFinestres(lectura, ambRefresc: warp.refresc != nil) {
                // Importar substituiria la configuració per res.
                estat = .senseFinestres(motiu.text + queFer(motiu))
                return
            }
            avisosLectura = lectura.avisos
            plantillaPrevista = editor.plantillaPerImportar.normalitzada()
            estat = .llest(editor.previsualitza(lectura))
        case let .failure(error):
            estat = .error(error.description)
        }
    }

    /// Què fer quan no hi ha finestres per importar, després del motiu (`MotiuSenseFinestres`, el mateix que «Lliga amb
    /// Warp…»). Amb una carpeta de prova, el motiu ja diu per què aquí no se'n poden llegir.
    private func queFer(_ motiu: MotiuSenseFinestres) -> String {
        switch (motiu, mode) {
        case (.deProva, .crea): " Aquí, tria «Comença en blanc» i afegeix-hi les pestanyes."
        case (.deProva, .substitueix): " La configuració no canvia."
        // El motiu ja diu què fer per poder importar (amb Warp Preview obert, obrir Warp Stable): aquí, l'altra opció.
        case (.senseBase, .crea), (.senseWarp(.obert), .crea): " Si no, tria «Comença en blanc» i afegeix-hi les pestanyes."
        case (.senseBase, .substitueix), (.senseWarp(.obert), .substitueix): " La configuració no canvia."
        case (_, .crea): " No hi ha res per importar: tria «Comença en blanc» i afegeix-hi les pestanyes."
        case (_, .substitueix): " No hi ha res per importar, i la configuració no canvia."
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

    /// Les xifres, una per línia: finestres i pestanyes, amb Claude, sense, i quantes salten els permisos. Les pestanyes
    /// que no tenien Claude obert queden només terminal (D-P5a; també en tornar a importar, 09/11/2026).
    public var xifres: [String] {
        guard let importacio else { return [] }
        let resum = importacio.resum
        let ambClaude = resum.ambSessio
        var linies = [
            "\(Plural.compta(resum.finestres, "finestra", "finestres")) · \(Plural.compta(resum.pestanyes, "pestanya", "pestanyes"))",
        ]
        linies.append(ambClaude == 0 ? "0 amb Claude" : "\(ambClaude) amb Claude, amb l'ordre de la seva sessió")
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

    /// L'ordre que tindran les pestanyes que no tenien Claude obert si s'hi activa Claude (`notaSenseClaudeObert`), o `nil`
    /// si no n'hi ha cap: la de la plantilla.
    public var ordrePlantilla: String? {
        guard let importacio,
              var claude = importacio.configuracio.finestres.flatMap(\.pestanyes)
                  .first(where: { importacio.origens[$0.id] == .nomesTerminal })?.claude
        else { return nil }
        claude.activat = true
        return (try? OrdreClaude.argv(claude, repren: nil)).map(OrdreClaude.text)
    }

    /// Què passa amb les pestanyes que no tenien Claude obert (D-P5a), o `nil` si no n'hi ha cap.
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
        let ambAvis = avisos.pestanyes.filter { $0.value.contains { $0.gravetat >= .avis } }.keys
        // Les carpetes de Warp i Claude que no coincideixen: l'avís surt en importar (`Validacio.avisCarpetaDeClaude`).
        return Set(ambAvis).union(importacio.vincles.filter { $0.value.carpetaWarp != nil }.keys).count
    }

    /// Què passarà en confirmar.
    public var explicacio: String {
        switch mode {
        case .crea:
            "Es desarà la configuració\(editor.rutaFitxer.map { " a \($0)" } ?? ""). No s'obre res de Warp ni de Claude."
        case .substitueix:
            "Substitueix el que hi ha ara (\(Plural.compta(editor.configuracio.finestres.count, "finestra", "finestres"))"
                + " i \(Plural.compta(editor.configuracio.finestres.flatMap(\.pestanyes).count, "pestanya", "pestanyes"))). "
                + perdenClaude + "Abans de desar se'n fa una còpia, i es pot desfer amb ⌘Z. La plantilla no canvia."
        }
    }

    /// Quantes pestanyes es queden sense Claude en substituir (decisió d'en David del 09/11/2026), o res si no se'n perd cap.
    private var perdenClaude: String {
        guard let importacio else { return "" }
        let ara = editor.configuracio.finestres.flatMap(\.pestanyes).filter(\.claude.activat).count
        let despres = importacio.configuracio.finestres.flatMap(\.pestanyes).filter(\.claude.activat).count
        guard despres < ara else { return "" }
        return "Ara hi ha \(Plural.compta(ara, "pestanya", "pestanyes")) amb Claude i en "
            + (despres == 1 ? "quedarà 1" : "quedaran \(despres)") + ": les altres seran només terminal. "
    }

    /// «a», «a i b», «a, b i c».
    private static func enumera(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " i " + parts.last!
    }
}
