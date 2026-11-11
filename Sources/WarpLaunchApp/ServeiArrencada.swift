import AppKit
import ServiceManagement
import WarpLaunchUI

/// Els ítems d'inici de macOS (D3, regla 3). L'únic lloc amb `SMAppService`, i només l'app principal (`mainApp`): cap
/// agent ni dimoni. Només es fa servir amb la configuració de debò, i només registra quan en David activa l'interruptor de
/// la Configuració (`ArrencadaSessio.posa`). Desactivar-lo no tanca l'app.
@MainActor
enum ServeiArrencada {
    static let entorn = ArrencadaSessio.Entorn(
        estat: {
            switch SMAppService.mainApp.status {
            case .enabled: .activada
            case .requiresApproval: .perAprovar
            default: .desactivada
            }
        },
        activa: { try SMAppService.mainApp.register() },
        desactiva: { try SMAppService.mainApp.unregister() },
        obreAjustos: { SMAppService.openSystemSettingsLoginItems() })

    /// Els ítems d'inici apunten al fitxer de l'app: des de `build/` o `.build/`, una compilació nova el canviaria.
    static var motiuNoDisponible: String? {
        Bundle.main.bundlePath.hasPrefix("/Applications/") ? nil : ArrencadaSessio.motiuForaDAplicacions(Bundle.main.bundlePath)
    }

    /// macOS diu que l'ha obert com a element d'inici. Es llegeix a `applicationDidFinishLaunching`, amb l'esdeveniment
    /// d'obertura encara viu (abans, `currentAppleEvent` és nil).
    static var obertaComElementDInici: Bool {
        guard let esdeveniment = NSAppleEventManager.shared().currentAppleEvent,
              esdeveniment.eventID == kAEOpenApplication else { return false }
        return esdeveniment.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
