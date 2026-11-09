import AppKit
@preconcurrency import Sparkle

/// L'únic fitxer que coneix l'actualitzador (docs/disseny.md, secció 11). La lògica és a `PoliticaActualitzacions` i a
/// `Actualitzacions`, sense l'actualitzador i amb proves. Aquí encara només es crea el controlador, sense engegar-lo.
@MainActor
final class ServeiActualitzacions: NSObject {
    private let controlador: SPUStandardUpdaterController

    override init() {
        controlador = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }
}
