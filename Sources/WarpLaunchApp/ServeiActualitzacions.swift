import AppKit
@preconcurrency import Sparkle
import WarpLaunchCore
import WarpLaunchUI

/// L'únic fitxer que coneix l'actualitzador (docs/disseny.md, secció 11, 3.3). Decideix `PoliticaActualitzacions`, i els estats són de
/// `Actualitzacions`: aquí només hi ha les crides i els delegats. Una finestra de l'actualitzador només surt si l'usuari prem
/// «Actualitza ara». L'app no fa res abans del permís: `engega` es crida a `consentiment.enContinuar`.
@MainActor
final class ServeiActualitzacions: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controlador: SPUStandardUpdaterController!
    private var model: Actualitzacions?
    private var observacions: [NSKeyValueObservation] = []
    /// La versió que s'instal·la: el reinici des de la finestra no la diu.
    private var versioInstallant: String?
    /// El permís de l'usuari, que es pot retirar amb l'app oberta.
    private let permis: @MainActor () -> Bool
    private let feed: String

    private var updater: SPUUpdater { controlador.updater }
    private var ara: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// - Parameter feed: l'adreça que porta el paquet (`SUFeedURL`).
    private init(feed: String, permis: @escaping @MainActor () -> Bool) {
        self.feed = feed
        self.permis = permis
        super.init()
        // Els delegats són febles: `Aplicacio` guarda el servei.
        controlador = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Crea el model i, si aquesta còpia es pot actualitzar, el servei. Si no, no es crea res més, ni hi ha cap connexió.
    static func crea(arguments: ArgumentsApp, permis: @escaping @MainActor () -> Bool,
                     models: @escaping @MainActor () -> SituacioApp.Models,
                     intent: @MainActor (MagatzemIntent) -> IntentActualitzacio) -> (servei: ServeiActualitzacions?, model: Actualitzacions) {
        let bundle = Bundle.main
        let paquet = paquet(arguments: arguments, bundle: bundle)
        if let motiu = PoliticaActualitzacions.motiuNoDisponible(paquet) {
            return (nil, Actualitzacions(noDisponible: motiu))
        }
        guard case let .real(carpeta) = arguments.carpeta, let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return (nil, Actualitzacions(noDisponible: .senseConfiguracio))
        }
        let servei = ServeiActualitzacions(feed: feed, permis: permis)
        let magatzem = MagatzemIntent(carpeta: carpeta)
        let model = Actualitzacions(entorn: servei.entorn(models: models), magatzem: magatzem, intent: intent(magatzem),
                                    ara: ProcessInfo.processInfo.systemUptime, versioActual: WarpLaunch.versio)
        servei.model = model
        return (servei, model)
    }

    private static func paquet(arguments: ArgumentsApp, bundle: Bundle) -> PoliticaActualitzacions.Paquet {
        let args: PoliticaActualitzacions.Paquet.Arguments = switch arguments.carpeta {
        case .real: .normals
        case .prova: .deProva
        case .incorrecta: .incorrectes
        }
        let ruta = bundle.bundlePath
        let fitxers = FileManager.default
        let propietari = (try? fitxers.attributesOfItem(atPath: ruta))?[.ownerAccountID] as? NSNumber
        return PoliticaActualitzacions.Paquet(
            arguments: args, ruta: ruta, identificador: bundle.bundleIdentifier,
            teFeed: !((bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty,
            potEscriure: fitxers.isWritableFile(atPath: ruta) && fitxers.isWritableFile(atPath: (ruta as NSString).deletingLastPathComponent),
            esDeLUsuari: propietari?.uint32Value == getuid(),
            actualitzadorCompatible: actualitzadorCompatible)
    }

    /// Un mètode opcional mal escrit compila, i l'actualitzador no el cridaria mai: si una versió nova en canvia un, millor no engegar.
    private static var actualitzadorCompatible: Bool {
        let requerits: [Selector] = [
            #selector(SPUUpdaterDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)),
            #selector(SPUUpdaterDelegate.updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)),
            #selector(SPUUpdaterDelegate.updaterWillRelaunchApplication(_:)),
            #selector(SPUUpdaterDelegate.updater(_:mayPerform:)),
            #selector(SPUUpdaterDelegate.updater(_:shouldProceedWithUpdate:updateCheck:)),
            #selector(SPUUpdaterDelegate.updater(_:didAbortWithError:)),
            #selector(SPUStandardUserDriverDelegate.standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)),
        ]
        return requerits.allSatisfy { ServeiActualitzacions.instancesRespond(to: $0) }
            && Int(SUError.noUpdateError.rawValue) == PoliticaActualitzacions.codiSenseNovetats
            && Int(SUError.installationCanceledError.rawValue) == PoliticaActualitzacions.codiInstallacioCancellada
    }

    private func entorn(models: @escaping @MainActor () -> SituacioApp.Models) -> Actualitzacions.Entorn {
        Actualitzacions.Entorn(
            comprovaIBaixa: { [unowned self] in updater.checkForUpdatesInBackground() },
            nomesMira: { [unowned self] in updater.checkForUpdateInformation() },
            actualitzaAra: { [unowned self] in updater.checkForUpdates() },
            potComprovar: { [unowned self] in updater.canCheckForUpdates && !updater.sessionInProgress },
            automatiques: { [unowned self] in updater.automaticallyChecksForUpdates },
            posaAutomatiques: { [unowned self] in updater.automaticallyChecksForUpdates = $0 },
            segonsInactiu: { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) },
            darreraComprovacio: { [unowned self] in updater.lastUpdateCheckDate },
            models: models,
            rellotge: { Date() })
    }

    /// Només després del permís. Si l'actualitzador no es pot engegar, ho diu la secció: cap alerta.
    func engega() {
        do {
            try updater.start()
        } catch {
            model?.rep(.error(Self.missatge(error), demanat: false), ara: ara)
            return
        }
        observa()
    }

    private func observa() {
        let canvia: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.model?.canviEntorn() }
        }
        observacions = [
            updater.observe(\.canCheckForUpdates) { _, _ in canvia() },
            updater.observe(\.sessionInProgress) { _, _ in canvia() },
            updater.observe(\.lastUpdateCheckDate) { _, _ in canvia() },
        ]
    }

    private static func missatge(_ error: any Error) -> String {
        var text = (error as NSError).localizedDescription
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private func comprovant() -> Bool {
        if case .comprovant = model?.estat { true } else { false }
    }

    // MARK: - SPUUpdaterDelegate

    /// Sense el permís, res (val per a tots els camins).
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard permis() else {
            throw NSError(domain: WarpLaunch.identificador, code: 1, userInfo: [NSLocalizedDescriptionKey: "no hi ha permís"])
        }
    }

    /// L'appcast no va signat: tot el que podria obrir una finestra o un enllaç, fora; i el fitxer, només d'on toca.
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        let fitxer = item.fileURL?.absoluteString
        guard !item.isInformationOnlyUpdate, !item.isCriticalUpdate, !item.isMajorUpgrade, let fitxer,
              PoliticaActualitzacions.enclosureValid(feed: feed, enclosure: fitxer) else {
            throw NSError(domain: WarpLaunch.identificador, code: 2, userInfo: [NSLocalizedDescriptionKey: "la versió publicada no té la forma esperada"])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        model?.rep(.trobada(item.displayVersionString), ara: ara)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        model?.rep(.alDia, ara: ara)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        model?.rep(.baixant(item.displayVersionString), ara: ara)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard PoliticaActualitzacions.esErrorVisible(codi: (error as NSError).code) else { return }
        model?.rep(.error(Self.missatge(error), demanat: comprovant()), ara: ara)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        model?.rep(.cicleAcabat, ara: ara)
    }

    /// A punt. El cicle s'atura fins que s'instal·la; el bloc instal·la i reobre, i en tancar l'app s'instal·la igualment.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock bloc: @escaping () -> Void) -> Bool {
        model?.rep(.aPunt(item.displayVersionString, aplica: { bloc() }), ara: ara)
        return true
    }

    /// Només el camí de la finestra. Una sola vegada: `vigila` crida el bloc quan es pugui.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock bloc: @escaping () -> Void) -> Bool {
        versioInstallant = item.displayVersionString
        guard let model, model.motiuReiniciDemanat(ara: ara) != nil else { return false }
        model.rep(.postposada(item.displayVersionString, aplica: { bloc() }), ara: ara)
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        versioInstallant = item.displayVersionString
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        guard let versioInstallant else { return }
        model?.reiniciaDesDeLaFinestra(versio: versioInstallant)
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Mai cap finestra sense demanar-la.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        model?.rep(.trobada(update.displayVersionString), ara: ara)
    }
}
