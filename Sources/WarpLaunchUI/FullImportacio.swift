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
    static var motiuNoEsPotLlegir: String {
        t("ara mateix s'està obrint alguna finestra a Warp, o Warp Launch s'està actualitzant. Torna-ho a provar quan acabi.")
    }

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
                estat = .senseFinestres(motiu.text + " " + queFer(motiu))
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
        case (.deProva, .crea): t("Aquí, tria «Comença en blanc» i afegeix-hi les pestanyes.")
        case (.deProva, .substitueix): t("La configuració no canvia.")
        // El motiu ja diu què fer per poder importar (amb Warp Preview obert, obrir Warp Stable): aquí, l'altra opció.
        case (.senseBase, .crea), (.senseWarp(.obert), .crea): t("Si no, tria «Comença en blanc» i afegeix-hi les pestanyes.")
        case (.senseBase, .substitueix), (.senseWarp(.obert), .substitueix): t("La configuració no canvia.")
        case (_, .crea): t("No hi ha res per importar: tria «Comença en blanc» i afegeix-hi les pestanyes.")
        case (_, .substitueix): t("No hi ha res per importar, i la configuració no canvia.")
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
        mode == .crea ? t("Importa de Warp") : t("Torna a importar-ho tot de Warp")
    }

    public var boto: String {
        mode == .crea ? t("Crea") : t("Substitueix")
    }

    /// Les xifres, una per línia: finestres i pestanyes, amb Claude, sense, i quantes salten els permisos. Les pestanyes
    /// que no tenien Claude obert queden només terminal (D-P5a; també en tornar a importar, 09/11/2026).
    public var xifres: [String] {
        guard let importacio else { return [] }
        let resum = importacio.resum
        let ambClaude = resum.ambSessio
        var linies = [t("\(resum.finestres) finestres · \(resum.pestanyes) pestanyes")]
        linies.append(ambClaude == 0 ? t("0 amb Claude") : t("\(ambClaude) amb Claude, amb l'ordre de la seva sessió"))
        if resum.senseClaude > 0 {
            let aInici = importacio.compta(.carpetaInici)
            let perdudes = importacio.compta(.carpetaNoExisteix)
            let altres = resum.senseClaude - resum.senseClaudeObert - aInici - perdudes
            var motius: [String] = []
            if resum.senseClaudeObert > 0 { motius.append(t("\(resum.senseClaudeObert) sense Claude obert")) }
            if aInici > 0 { motius.append(t("\(aInici) a la carpeta d'inici")) }
            if perdudes > 0 { motius.append(t("\(perdudes) amb una carpeta que ja no existeix")) }
            if altres > 0, !motius.isEmpty { motius.append(t("\(altres) més")) }
            linies.append(motius.isEmpty ? t("\(resum.senseClaude) només terminal")
                : t("\(resum.senseClaude) només terminal: \(Idioma.llista(motius))"))
        }
        if resum.saltenPermisos > 0 {
            linies.append(t("\(resum.saltenPermisos) salten els permisos (--dangerously-skip-permissions)"))
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
        // El nombre no surt al text: dues frases senceres.
        return n == 1
            ? t("Queda només terminal. Per obrir-hi Claude, marca «Obre Claude Code en aquesta pestanya» a l'inspector: s'hi obrirà amb aquesta ordre.")
            : t("Queden només terminal. Per obrir-hi Claude, marca «Obre Claude Code en aquesta pestanya» a l'inspector: s'hi obrirà amb aquesta ordre.")
    }

    /// «6 pestanyes sortiran a «Per revisar»», o `nil` si no n'hi ha cap.
    public var textPerRevisar: String? {
        let n = perRevisar
        return n == 0 ? nil : t("\(n) pestanyes sortiran a «Per revisar»")
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
            editor.rutaFitxer.map { t("Es desarà la configuració a \($0). No s'obre res de Warp ni de Claude.") }
                ?? t("Es desarà la configuració. No s'obre res de Warp ni de Claude.")
        case .substitueix:
            textSubstitueix
        }
    }

    /// «Substitueix el que hi ha ara (2 finestres i 4 pestanyes). …», i quantes pestanyes es queden sense Claude en substituir
    /// (decisió d'en David del 09/11/2026), si se'n perd cap: dues frases senceres, amb els plurals.
    private var textSubstitueix: String {
        let finestres = editor.configuracio.finestres.count
        let pestanyes = editor.configuracio.finestres.flatMap(\.pestanyes).count
        let ara = editor.configuracio.finestres.flatMap(\.pestanyes).filter(\.claude.activat).count
        let despres = importacio?.configuracio.finestres.flatMap(\.pestanyes).filter(\.claude.activat).count ?? ara
        guard despres < ara else {
            return t("""
                Substitueix el que hi ha ara (\(finestres) finestres i \(pestanyes) pestanyes). Abans de desar se'n fa una \
                còpia, i es pot desfer amb ⌘Z. La plantilla no canvia.
                """)
        }
        return t("""
            Substitueix el que hi ha ara (\(finestres) finestres i \(pestanyes) pestanyes). Ara hi ha \(ara) pestanyes amb \
            Claude i en quedaran \(despres): les altres seran només terminal. Abans de desar se'n fa una còpia, i es pot \
            desfer amb ⌘Z. La plantilla no canvia.
            """)
    }
}
