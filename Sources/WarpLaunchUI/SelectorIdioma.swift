import Foundation
import Observation
import WarpLaunchCore

/// «Idioma», a la Configuració › General (docs/disseny.md, secció 12, F4): la llengua de l'app, o la del sistema. La tria es
/// desa a la preferència `AppleLanguages` del domini de l'app (`[codi]`, o sense la clau per a la del sistema), que macOS llegeix
/// en obrir l'app. L'app no es reinicia sola (prova de guarda): la llengua canvia la propera vegada que s'obre.
///
/// Les opcions surten de les carpetes `.lproj` dels textos (`Idioma.llenguesDisponibles`): una llengua nova no toca el codi.
/// Les preferències de debò, només a `ServeiIdioma` (l'app); les proves, amb un entorn fals.
@MainActor
@Observable
public final class SelectorIdioma {
    /// Una opció del selector: la del sistema, o una llengua amb textos.
    public enum Tria: Hashable, Sendable {
        case sistema
        case llengua(String)
    }

    public struct Opcio: Identifiable, Equatable, Sendable {
        public let tria: Tria
        public let text: String
        public var id: Tria { tria }
    }

    /// L'accés a les preferències de macOS (`ServeiIdioma`, només a l'app).
    public struct Entorn {
        /// Les llengües preferides del Mac (`AppleLanguages` del domini global): les de l'opció del sistema.
        public var delSistema: @MainActor () -> [String]
        /// `AppleLanguages` del domini de l'app, si hi és.
        public var deLApp: @MainActor () -> [String]?
        /// Desa `[codi]` a `AppleLanguages` del domini de l'app; amb `nil`, n'esborra la clau.
        public var desa: @MainActor ([String]?) -> Void

        public init(delSistema: @escaping @MainActor () -> [String], deLApp: @escaping @MainActor () -> [String]?,
                    desa: @escaping @MainActor ([String]?) -> Void) {
            self.delSistema = delSistema
            self.deLApp = deLApp
            self.desa = desa
        }
    }

    /// Les llengües amb textos.
    public let disponibles: [String]
    /// La llengua dels textos ara: no canvia fins que l'app es torna a obrir.
    public let actual: String
    /// L'opció marcada: la llengua de les preferències de l'app, si n'hi ha, i si no, la del sistema.
    public private(set) var tria: Tria
    @ObservationIgnored private let entorn: Entorn

    public init(entorn: Entorn, disponibles: [String] = Idioma.llenguesDisponibles, actual: String = Idioma.efectiva) {
        self.entorn = entorn
        self.disponibles = disponibles
        self.actual = actual
        if let deLApp = entorn.deLApp(), !deLApp.isEmpty {
            tria = .llengua(Idioma.tria(disponibles: disponibles, preferencies: deLApp))
        } else {
            tria = .sistema
        }
    }

    /// La llengua que surt amb la del sistema, entre les que tenen textos.
    public var llenguaDelSistema: String {
        Idioma.tria(disponibles: disponibles, preferencies: entorn.delSistema())
    }

    /// «El del sistema (català)»: el nom, en la llengua de l'app, de la llengua que surt amb aquesta opció.
    public var sistema: Opcio {
        Opcio(tria: .sistema, text: t("El del sistema (\(Idioma.nom(llenguaDelSistema)))"))
    }

    /// Les llengües, cadascuna amb el nom en ella mateixa, per ordre alfabètic del nom.
    public var llengues: [Opcio] {
        disponibles.map { Opcio(tria: .llengua($0), text: Idioma.nomPropi($0)) }
            .sorted { $0.text.compare($1.text, options: .caseInsensitive, locale: Locale(identifier: "en")) == .orderedAscending }
    }

    /// La llengua que sortirà la propera vegada que s'obri l'app.
    public var llenguaTriada: String {
        switch tria {
        case .sistema: llenguaDelSistema
        case let .llengua(codi): codi
        }
    }

    /// La nota de sota el selector, només si la tria canvia la llengua que es veu ara.
    public var nota: String? {
        llenguaTriada == actual ? nil : t("L'idioma canviarà la propera vegada que obris l'app.")
    }

    /// El selector: desa la tria a les preferències de l'app. La llengua no canvia fins que s'obre l'app un altre cop.
    public func posa(_ nova: Tria) {
        guard nova != tria else { return }
        if case let .llengua(codi) = nova, !disponibles.contains(codi) { return }
        switch nova {
        case .sistema: entorn.desa(nil)
        case let .llengua(codi): entorn.desa([codi])
        }
        tria = nova
    }
}
