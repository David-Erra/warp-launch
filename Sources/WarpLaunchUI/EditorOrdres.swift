import Foundation
import WarpLaunchCore

// Les ordres de la barra de menús i del menú de la icona (docs/disseny.md, «Ordres» i «Menú de la icona», pas 11):
// quan s'apliquen i què fan. La vista només hi posa els botons.

extension Editor {
    /// El fitxer de la configuració per mostrar-lo al Finder: el fitxer, si existeix; si no, la seva carpeta; `nil`
    /// sense carpeta (arguments incorrectes) o si no hi ha res.
    public var fitxerPerMostrar: URL? {
        guard let fitxer = fitxerConfiguracio else { return nil }
        let gestor = FileManager.default
        if gestor.fileExists(atPath: fitxer.path) { return fitxer }
        let carpeta = fitxer.deletingLastPathComponent()
        return gestor.fileExists(atPath: carpeta.path) ? carpeta : nil
    }
}

/// «Actualitza l'estat de Warp» (`WarpLaunch.ordreActualitzaEstat`): la mateixa ordre al menú Arxiu i al de la icona, amb una
/// sola vista (`ItemActualitzaWarp`). No obre ni canvia res de la configuració, però amb Warp obert activa uns segons la
/// restauració perquè Warp desi les finestres (D19): per això, només amb el permís (D-P4), i mai mentre s'obre res a Warp ni
/// mentre s'aplica una actualització (`Obertura.impedeixRefresc`). Sense el refresc (una carpeta de prova), només llegeix.
@MainActor
public struct OrdreActualitzaWarp {
    private let warp: EstatWarp
    private let consentiment: ConsentimentRestauracio
    private let obertura: Obertura?

    /// - Parameter obertura: la de l'app; `nil` sense carpeta de configuració, on no n'hi ha cap.
    public init(warp: EstatWarp, consentiment: ConsentimentRestauracio, obertura: Obertura?) {
        self.warp = warp
        self.consentiment = consentiment
        self.obertura = obertura
    }

    /// Desactivada sense el permís, mentre ja es llegeix Warp i mentre s'obre res a Warp o s'aplica una actualització. Després
    /// d'una lectura que falla, sí: és quan cal tornar-hi.
    public var potExecutar: Bool { consentiment.potContinuar && !warp.llegint && obertura?.impedeixRefresc != true }

    public func executa() async {
        guard potExecutar else { return }
        await warp.llegeixAmbFinestres()
    }
}

/// La columna de l'editor que té el focus (`FocusedValues.columnaEditor`): Duplica i «Canvia el nom» hi actuen.
public enum ColumnaEditor: Hashable, Sendable {
    case barraLateral, llista
}

extension Editor {
    /// El que fan Duplica i «Canvia el nom» segons la columna amb el focus.
    public enum ObjecteOrdre: Equatable, Sendable {
        case pestanyes(Set<Pestanya.ID>)
        case finestra(Finestra.ID)
    }

    /// Les ordres que canvien la configuració: no amb el full d'importació o el diàleg de carpetes oberts (canviarien
    /// la configuració per sota).
    public var ordresActives: Bool { potEditar && !demanaImportacio && !demanaNovaPestanya }

    /// Importa de Warp…: amb configuració o sense, i sense cap full ni diàleg obert. El full llegeix Warp amb les finestres, que
    /// activa uns segons la restauració (D19): per això, no mentre s'obre res a Warp ni mentre s'aplica una actualització
    /// (`Obertura.impedeixRefresc`). I tampoc amb el full d'obrir a la vista, encara que només esperi el clic: «Obre» començaria
    /// a obrir amb la lectura a mig fer.
    public var potImportar: Bool {
        (estat == .oberta || estat == .senseConfiguracio) && !demanaImportacio && !demanaNovaPestanya
            && obertura?.impedeixRefresc != true && obertura?.mostraFull != true && lligam?.mostraFull != true
    }

    /// «Importa de Warp…» o «Torna a importar-ho tot de Warp…» (l'estat buit i el menú Arxiu): obre el full, que llegeix Warp.
    public func demanaImportar() {
        if potImportar { demanaImportacio = true }
    }

    public var potNovaPestanya: Bool { ordresActives && potAfegirPestanya }

    /// «Nova pestanya…» (⌘T, «+», el menú contextual): obre el diàleg de carpetes.
    public func demanaPestanyaNova() {
        if potNovaPestanya { demanaNovaPestanya = true }
    }

    public func objecte(_ columna: ColumnaEditor?) -> ObjecteOrdre? {
        guard ordresActives, let columna else { return nil }
        switch columna {
        case .llista:
            let ids = Set(pestanyes.map(\.id))
            return ids.isEmpty ? nil : .pestanyes(ids)
        case .barraLateral:
            guard case let .finestra(id)? = lateral, configuracio.finestra(id) != nil else { return nil }
            return .finestra(id)
        }
    }

    public func titolDuplica(_ columna: ColumnaEditor?) -> String {
        switch objecte(columna) {
        case let .pestanyes(ids)?: ids.count == 1 ? t("Duplica la pestanya") : t("Duplica les pestanyes")
        case .finestra?: t("Duplica la finestra")
        case nil: t("Duplica")
        }
    }

    public func duplica(_ columna: ColumnaEditor?) {
        switch objecte(columna) {
        case .pestanyes?: duplicaPestanyes()
        case let .finestra(id)?: duplicaFinestra(id)
        case nil: break
        }
    }

    /// Exactament una pestanya triada, o una finestra.
    public func potCanviarElNom(_ columna: ColumnaEditor?) -> Bool {
        switch objecte(columna) {
        case let .pestanyes(ids)?: ids.count == 1
        case .finestra?: true
        case nil: false
        }
    }

    public func canviaElNom(_ columna: ColumnaEditor?) {
        guard potCanviarElNom(columna) else { return }
        switch objecte(columna) {
        case let .pestanyes(ids)?: if let id = ids.first { comencaNom(.pestanya(id)) }
        case let .finestra(id)?: comencaNom(.finestra(id))
        case nil: break
        }
    }

    /// Pestanya › Mou a ▸: hi ha pestanyes triades.
    public var potMoureTriades: Bool { ordresActives && !pestanyes.isEmpty }

    public var potActivarClaude: Bool { ordresActives && pestanyes.contains { !$0.claude.activat } }
    public var potDesactivarClaude: Bool { ordresActives && pestanyes.contains(where: \.claude.activat) }

    public func activaClaudeTriades(_ activat: Bool) {
        guard activat ? potActivarClaude : potDesactivarClaude else { return }
        activaClaude(Set(pestanyes.map(\.id)), activat)
    }

    /// Edició › Elimina (⌫) a la llista: hi ha pestanyes triades.
    public var potEliminarPestanyes: Bool { potEditar && !pestanyes.isEmpty }

    /// Edició › Elimina (⌫) a la barra lateral: hi ha una finestra triada (no «Per revisar»).
    public var potEliminarFinestra: Bool {
        guard potEditar, case let .finestra(id)? = lateral else { return false }
        return configuracio.finestra(id) != nil
    }
}

// MARK: - Menú de la icona

extension Editor {
    /// Un avís del menú de la icona: una línia que obre l'editor.
    public enum AvisMenu: Equatable, Sendable {
        /// La configuració no es pot llegir (l'editor diu per què).
        case configuracioAmbErrors
        case fitxerCanviatFora
        case noSHaPogutDesar

        public var text: String {
            switch self {
            case .configuracioAmbErrors: t("La configuració té errors")
            case .fitxerCanviatFora: t("El fitxer ha canviat fora de l'app")
            case .noSHaPogutDesar: t("No s'ha pogut desar")
            }
        }
    }

    /// Els avisos del menú de la icona. Sense carpeta (arguments incorrectes) no n'hi ha cap: ja ho diu «Sense
    /// configuració». Els de les pestanyes no hi surten (decisió d'en David, 04/11/2026): són a l'editor.
    public var avisosMenu: [AvisMenu] {
        var avisos: [AvisMenu] = []
        if case .error = estat, fitxerConfiguracio != nil { avisos.append(.configuracioAmbErrors) }
        if let errorDesat { avisos.append(errorDesat == .modificadaFora ? .fitxerCanviatFora : .noSHaPogutDesar) }
        return avisos
    }
}
