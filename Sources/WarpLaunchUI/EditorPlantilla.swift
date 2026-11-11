import Foundation
import WarpLaunchCore

// La plantilla a la finestra de Configuració (docs/disseny.md, pas 11): les opcions de Claude de les pestanyes noves i
// de les importades sense sessió. Els mateixos camps que l'inspector, sobre un sol valor, i amb el seu Desfés
// (`canviaPlantilla`, `desferPlantilla`). La vista només hi posa els controls.

extension Editor {
    /// La plantilla es pot canviar: hi ha una configuració oberta.
    public var potCanviarPlantilla: Bool { potEditar }

    /// La plantilla que es mostra: la de la configuració, o, si encara no n'hi ha, la que tindrà la nova (la mateixa si
    /// s'importa de Warp que si es comença en blanc). `nil` si no se sap (carregant, o el fitxer no es pot llegir):
    /// mostrar-ne una altra faria creure que és la del fitxer (revisió del pas 11).
    public var plantillaVisible: ClaudePestanya? {
        switch estat {
        case .oberta: configuracio.plantilla
        case .senseConfiguracio: plantillaPerImportar
        case .carregant, .error: nil
        }
    }

    /// El que rebrà de debò una pestanya nova: sense el nom fix de sessió (`perAPestanyaNova`). D'aquí surten l'ordre
    /// i els avisos de la Configuració.
    public var plantillaPerAPestanyaNova: ClaudePestanya? {
        plantillaVisible?.perAPestanyaNova()
    }

    /// Els valors que es llegeixen als controls quan no n'hi ha cap per mostrar (la vista no els mostra).
    private var plantillaDelsControls: ClaudePestanya { plantillaVisible ?? .perOmissio }

    public func triaPlantilla(_ camp: CampTria) -> Tria {
        Self.tria(camp, de: [plantillaDelsControls])
    }

    /// «Per defecte», els valors coneguts i el que ja hi ha, encara que Claude no el conegui.
    public func opcionsPlantilla(_ camp: CampTria) -> [Opcio] {
        Self.opcions(camp, de: [plantillaDelsControls])
    }

    public func triaPlantilla(_ camp: CampTria, a tria: Tria) {
        let valor: String?
        switch tria {
        case .diversos: return
        case .perDefecte: valor = nil
        case let .valor(text): valor = text
        }
        canviaPlantilla(nom: camp.accio) { $0[keyPath: camp.cami] = valor }
    }

    public func siNoPlantilla(_ camp: CampSiNo) -> Bool {
        plantillaDelsControls[keyPath: camp.cami]
    }

    public func posaPlantilla(_ camp: CampSiNo, _ valor: Bool) {
        canviaPlantilla(nom: camp.accio(valor)) { $0[keyPath: camp.cami] = valor }
    }

    /// Amb «Salta els permisos», Claude no fa cas del mode: el control queda desactivat.
    public var modeSenseEfectePlantilla: Bool { plantillaDelsControls.saltaPermisos }

    /// Els avisos de la plantilla, sense el de l'ordre (ho diu el bloc de l'ordre).
    public var avisosPlantilla: [Avis] {
        guard estat == .oberta, let plantilla = plantillaPerAPestanyaNova else { return [] }
        return Validacio.avisos(plantilla: plantilla).filter {
            if case .ordreImpossible = $0.tipus { false } else { true }
        }
    }

    /// Les opcions que la Configuració no edita, en només lectura (`--settings`, `--remote-control` i les altres). El
    /// nom fix de sessió no s'aplica mai a les pestanyes noves (decisió d'en David, 04/11/2026): surt a part.
    public var opcionsNomesLecturaPlantilla: [(nom: String, valor: String)] {
        plantillaVisible?.opcionsNomesLectura ?? []
    }

    /// Un nom fix de sessió escrit a mà a la plantilla del fitxer: es mostra, però no es copia a cap pestanya.
    public var nomSessioPlantilla: String? {
        plantillaVisible?.normalitzada().nom
    }

    /// Per què no es pot canviar la plantilla, o `nil` si es pot.
    public var motiuPlantillaNoEditable: String? {
        switch estat {
        case .oberta: return nil
        case .carregant: return t("Es llegeix la configuració…")
        case .senseConfiguracio:
            // En importar, les pestanyes que no tenien Claude obert queden només terminal (D-P5a): no s'hi obre aquesta.
            return t("""
                Encara no hi ha cap configuració. Si importes de Warp, les pestanyes que no tenien Claude obert queden només \
                terminal. Les pestanyes que afegeixis, i aquestes si hi actives Claude, s'obriran amb \
                «\(Self.textOrdre(plantillaPerImportar))».
                """)
        case let .error(motiu):
            return t("No es pot canviar: \(motiu)")
        }
    }

    private static func textOrdre(_ claude: ClaudePestanya) -> String {
        (try? OrdreClaude.text(de: claude, repren: nil).get()).flatMap { $0 } ?? "claude"
    }
}
