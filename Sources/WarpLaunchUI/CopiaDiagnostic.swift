import Foundation
import Observation
import WarpLaunchCore

/// «Copia el diagnòstic», a la Configuració (pla A4, 0.30.0): l'informe de `Diagnostic` (en anglès, per a una issue de
/// GitHub) al porta-retalls. Per defecte, l'anonimitzat; el complet, al menú del botó. El diagnòstic només llegeix, i el
/// porta-retalls només s'escriu amb el clic.
@MainActor
@Observable
public final class CopiaDiagnostic {
    /// Mentre es llegeix: el botó no torna a començar.
    public private(set) var calculant = false
    /// El que s'ha copiat l'última vegada, per dir-ho al costat del botó.
    public private(set) var copiat: String?
    @ObservationIgnored private let diagnostic: @Sendable (_ anonimitza: Bool) -> InformeDiagnostic
    @ObservationIgnored private let escriu: @MainActor (String) -> Void

    /// - Parameters:
    ///   - diagnostic: l'app hi posa `Diagnostic.executa` amb el seu `Lector` i les carpetes de debò; les proves, un de fals.
    ///   - escriu: on es copia l'informe. L'app no en passa cap: el porta-retalls (`PortaRetallsSistema.copiaText`). Les
    ///     proves, un de fals.
    public init(diagnostic: @escaping @Sendable (_ anonimitza: Bool) -> InformeDiagnostic,
                escriu: (@MainActor (String) -> Void)? = nil) {
        self.diagnostic = diagnostic
        self.escriu = escriu ?? { PortaRetallsSistema.copiaText($0) }
    }

    /// Fa el diagnòstic fora del fil principal (llegeix tots els processos i uns quants fitxers) i en copia l'informe.
    public func copia(anonimitzat: Bool) async {
        guard !calculant else { return }
        calculant = true
        let diagnostic = diagnostic
        let informe = await Task.detached { diagnostic(anonimitzat) }.value
        escriu(informe.text)
        copiat = Self.text(informe)
        calculant = false
    }

    /// «Copiat (anonimitzat): 6 bé, 2 avisos, 0 errors.»
    static func text(_ informe: InformeDiagnostic) -> String {
        let (be, avisos, errors) = (informe.compta(.be), informe.compta(.avis), informe.compta(.error))
        return informe.anonimitzat ? t("Copiat (anonimitzat): \(be) bé, \(avisos) avisos, \(errors) errors.")
            : t("Copiat (complet): \(be) bé, \(avisos) avisos, \(errors) errors.")
    }
}
