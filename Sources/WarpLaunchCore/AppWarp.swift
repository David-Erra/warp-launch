import Foundation

/// Un paquet d'app de Warp (fase 3.1): el que obre el fitxer temporal, si és el de Warp Stable. Només llegeix
/// l'`Info.plist`: no obre res.
public struct AppWarp: Sendable, Equatable {
    public static let identificador = "dev.warp.Warp-Stable"
    /// Warp Preview (D-P12, 0.29.2): encara no és compatible. Només es busca per dir-ho.
    public static let identificadorPreview = "dev.warp.Warp-Preview"
    /// On es mira Warp Stable si macOS no en sap res: on era sempre fins a la 0.29.1. Les proves no la fan servir mai.
    public static let rutaPerDefecte = URL(filePath: "/Applications/Warp.app", directoryHint: .isDirectory)

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private var info: [String: Any]? {
        guard let dades = try? Data(contentsOf: url.appending(path: "Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: dades, format: nil) as? [String: Any]
    }

    /// Si és Warp Stable: l'`Info.plist` diu `dev.warp.Warp-Stable`.
    public var esWarp: Bool { info?["CFBundleIdentifier"] as? String == Self.identificador }

    /// Si és Warp Preview: l'`Info.plist` diu `dev.warp.Warp-Preview`.
    public var esPreview: Bool { info?["CFBundleIdentifier"] as? String == Self.identificadorPreview }

    /// La versió (`CFBundleShortVersionString`), per al full de confirmació i les proves reals.
    public var versio: String? { info?["CFBundleShortVersionString"] as? String }

    /// La ruta del binari, de l'`Info.plist` (`Contents/MacOS/` i `CFBundleExecutable`; a Warp Stable, `stable`). El mateix
    /// binari fa d'app, de `terminal-server` i de CLI. `nil` si l'`Info.plist` no ho diu bé.
    public var executable: String? {
        guard let nom = info?["CFBundleExecutable"] as? String, !nom.isEmpty, !nom.contains("/"), nom != "..", nom != "."
        else { return nil }
        return url.appending(path: "Contents/MacOS/\(nom)").path
    }

    /// El Warp Stable d'un binari que corre (decisió 4, 0.31.1): el paquet que el conté (`<paquet>.app/Contents/MacOS/`),
    /// si el seu `Info.plist` diu `dev.warp.Warp-Stable` i que aquell és el seu binari. Una còpia a la Paperera no compta
    /// (0.29.3). Només llegeix l'`Info.plist`. Només el crida `ProcessosDelSistema` (`FontProcessos.warpDelBinari`).
    static func delBinari(_ ruta: String) -> AppWarp? {
        guard ruta.hasPrefix("/") else { return nil }
        let macos = URL(filePath: ruta).deletingLastPathComponent()
        let contents = macos.deletingLastPathComponent()
        let paquet = contents.deletingLastPathComponent()
        guard macos.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents", paquet.pathExtension == "app",
              !InstallacioWarp.esALaPaperera(paquet) else { return nil }
        let app = AppWarp(url: paquet)
        return app.esWarp && app.executable == ruta ? app : nil
    }
}

/// On és Warp en aquest Mac (D-P12, 0.29.2): Warp Stable, en qualsevol carpeta, i Warp Preview, si n'hi ha, per dir que
/// encara no és compatible. Són dades: el que macOS en sap ho pregunta `TrobaWarp` (a l'obridor, on les proves no hi
/// arriben), que crida `troba(aplicacions:cerca:)`; el Warp que corre, `ambLaCopiaOberta` (decisió 4, 0.31.1).
public struct InstallacioWarp: Sendable, Equatable {
    /// L'app de Warp Stable que compta: la que corre (`ambLaCopiaOberta`), o la que diu macOS, o, si no en sap res, la
    /// d'Aplicacions (com fins a la 0.29.1).
    public var app: AppWarp
    /// El binari d'`app`. Només aquest compta com a Warp obert, i el seu `terminal-server`: una altra còpia de Warp que no
    /// corre no és la que s'obriria.
    public var executable: String
    /// Si `app` és Warp Stable de debò. `false`: no n'hi ha cap, i obrir res fallaria.
    public var hiHaStable: Bool
    /// El binari de Warp Preview, si n'hi ha: només per dir que encara no és compatible.
    public var executablePreview: String?

    public init(app: AppWarp, executable: String, hiHaStable: Bool, executablePreview: String? = nil) {
        self.app = app
        self.executable = executable
        self.hiHaStable = hiHaStable
        self.executablePreview = executablePreview
    }

    /// El que es feia fins a la 0.29.1: Warp Stable a Aplicacions, sense Warp Preview. No llegeix res.
    public static let perOmissio = InstallacioWarp(app: AppWarp(url: AppWarp.rutaPerDefecte),
                                                   executable: binariPerOmissio(AppWarp.rutaPerDefecte), hiHaStable: true)

    /// Si és dins d'una Paperera: la de l'usuari (`~/.Trash`) o la d'un altre disc (`.Trashes`).
    static func esALaPaperera(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// El nom del binari de Warp Stable (`CFBundleExecutable`), si el paquet no diu quin és (o no hi és).
    static let nomBinari = "stable"

    /// `Contents/MacOS/stable`: el binari de Warp Stable si el paquet no diu quin és (o no hi és).
    static func binariPerOmissio(_ app: URL) -> String { app.appending(path: "Contents/MacOS/\(nomBinari)").path }

    /// Busca Warp. `cerca` diu on és l'app amb un identificador (a l'app i al CLI, macOS; a les proves, una de falsa), i
    /// `aplicacions`, on es mira Warp Stable si `cerca` no el troba. Només es fa servir una app si el seu `Info.plist`
    /// diu que és la que es busca.
    public static func troba(aplicacions: URL, cerca: (String) -> URL?) -> InstallacioWarp {
        // 0.29.3: una còpia a la Paperera no és cap Warp instal·lat, però macOS la pot donar igualment. No s'hi obre res:
        // com si no en sabés res.
        func installada(_ url: URL?) -> AppWarp? { url.flatMap { esALaPaperera($0) ? nil : AppWarp(url: $0) } }
        let trobada = installada(cerca(AppWarp.identificador)).flatMap { $0.esWarp ? $0 : nil }
        let app = trobada ?? AppWarp(url: aplicacions)
        let hiHaStable = trobada != nil || app.esWarp
        let preview = installada(cerca(AppWarp.identificadorPreview)).flatMap { $0.esPreview ? $0 : nil }
        return InstallacioWarp(app: app, executable: (hiHaStable ? app.executable : nil) ?? binariPerOmissio(app.url),
                               hiHaStable: hiHaStable, executablePreview: preview?.executable)
    }

    /// Decisió 4 (0.31.1): si corre Warp Stable, és aquell el que compta, per a «és obert» i per obrir-hi finestres, encara
    /// que macOS en digui un altre (dues còpies, o un Warp que macOS ha traslladat, «App Translocation»). Si corre el que
    /// diu macOS, o no en corre cap, `self`. Es reconeix pels processos, com `warpObert`: l'app sense arguments, amb el
    /// binari d'un paquet de Warp Stable (`FontProcessos.warpDelBinari`). Amb dues còpies obertes, la que diu macOS, si
    /// n'és una; si no, la de pid més baix. Només llegeix els processos i l'`Info.plist` de cada paquet que corre.
    public func ambLaCopiaOberta(_ processos: any FontProcessos) -> InstallacioWarp {
        if hiHaStable, processos.warpObert(executable: executable) { return self }
        // El nom que en sap el sistema (`p_comm`, tallat a 16 caràcters): el del binari d'`app` i el de sempre.
        let noms = Set([(executable as NSString).lastPathComponent, Self.nomBinari].map { String($0.prefix(16)) })
        for pid in noms.flatMap({ processos.pids(nom: $0) }).sorted() {
            guard let info = processos.proces(pid), info.argv.count <= 1, info.executable != executable,
                  let oberta = processos.warpDelBinari(info.executable) else { continue }
            return InstallacioWarp(app: oberta, executable: info.executable, hiHaStable: true,
                                   executablePreview: executablePreview)
        }
        return self
    }

    /// Per què no es pot obrir res a Warp Stable, amb aquests processos: no hi ha cap Warp (0.31.1), només hi ha Warp
    /// Preview, o Warp Preview és obert i Warp Stable no (l'app obriria un altre Warp sense dir-ho). Amb tots dos oberts,
    /// l'app fa servir el Stable.
    public func preview(_ processos: any FontProcessos, stableObert: Bool) -> WarpPreview? {
        guard hiHaStable else { return executablePreview == nil ? .capWarp : .nomesPreview }
        guard let executablePreview else { return nil }
        return !stableObert && processos.warpObert(executable: executablePreview) ? .obert : nil
    }
}

/// Per què no hi ha cap Warp Stable on obrir res: Warp Preview (D-P12, 0.29.2), que encara no és compatible, o cap Warp
/// (0.31.1). L'app ho diu en lloc d'obrir un altre Warp o de fallar sense explicar per què.
public enum WarpPreview: String, Codable, Sendable, Equatable {
    /// Hi ha Warp Preview, però no Warp Stable.
    case nomesPreview
    /// Warp Preview és obert, i Warp Stable no.
    case obert
    /// No hi ha cap Warp: ni Warp Stable ni Warp Preview (0.31.1). Abans, el full proposava obrir Warp i fallava en
    /// confirmar.
    case capWarp

    public static var noCompatible: String { t("Warp Preview encara no és compatible: cal Warp Stable.") }

    public var text: String {
        switch self {
        case .nomesPreview: Idioma.frases(Self.noCompatible, t("En aquest Mac només hi ha Warp Preview."))
        case .obert: Idioma.frases(Self.noCompatible, t("Ara és obert Warp Preview, i Warp Stable no: obre Warp Stable i torna-ho a provar."))
        case .capWarp: t("No s'ha trobat Warp en aquest Mac: cal Warp Stable.")
        }
    }
}
