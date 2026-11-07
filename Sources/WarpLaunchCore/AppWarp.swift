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
}

/// On és Warp en aquest Mac (D-P12, 0.29.2): Warp Stable, en qualsevol carpeta, i Warp Preview, si n'hi ha, per dir que
/// encara no és compatible. Són dades: el que macOS en sap ho pregunta `TrobaWarp` (a l'obridor, on les proves no hi
/// arriben), que crida `troba(aplicacions:cerca:)`.
public struct InstallacioWarp: Sendable, Equatable {
    /// L'app de Warp Stable que s'obre: la que diu macOS, o, si no en sap res, la d'Aplicacions (com fins a la 0.29.1).
    public var app: AppWarp
    /// El binari d'`app`. Només aquest compta com a Warp obert, i el seu `terminal-server`: una còpia de Warp en una altra
    /// carpeta no és la que s'obriria.
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

    /// `Contents/MacOS/stable`: el binari de Warp Stable si el paquet no diu quin és (o no hi és).
    static func binariPerOmissio(_ app: URL) -> String { app.appending(path: "Contents/MacOS/stable").path }

    /// Busca Warp. `cerca` diu on és l'app amb un identificador (a l'app i al CLI, macOS; a les proves, una de falsa), i
    /// `aplicacions`, on es mira Warp Stable si `cerca` no el troba. Només es fa servir una app si el seu `Info.plist`
    /// diu que és la que es busca.
    public static func troba(aplicacions: URL, cerca: (String) -> URL?) -> InstallacioWarp {
        let trobada = cerca(AppWarp.identificador).map(AppWarp.init(url:)).flatMap { $0.esWarp ? $0 : nil }
        let app = trobada ?? AppWarp(url: aplicacions)
        let hiHaStable = trobada != nil || app.esWarp
        let preview = cerca(AppWarp.identificadorPreview).map(AppWarp.init(url:)).flatMap { $0.esPreview ? $0 : nil }
        return InstallacioWarp(app: app, executable: (hiHaStable ? app.executable : nil) ?? binariPerOmissio(app.url),
                               hiHaStable: hiHaStable, executablePreview: preview?.executable)
    }

    /// Per què Warp Preview no deixa obrir res, amb aquests processos: no hi ha Warp Stable, o Warp Preview és obert i
    /// Warp Stable no (l'app obriria un altre Warp sense dir-ho). Amb tots dos oberts, l'app fa servir el Stable.
    public func preview(_ processos: any FontProcessos, stableObert: Bool) -> WarpPreview? {
        guard let executablePreview else { return nil }
        if !hiHaStable { return .nomesPreview }
        return !stableObert && processos.warpObert(executable: executablePreview) ? .obert : nil
    }
}

/// Warp Preview (D-P12, 0.29.2): encara no és compatible, i l'app ho diu en lloc d'obrir un altre Warp o de fallar sense
/// explicar per què.
public enum WarpPreview: String, Codable, Sendable, Equatable {
    /// Hi ha Warp Preview, però no Warp Stable.
    case nomesPreview
    /// Warp Preview és obert, i Warp Stable no.
    case obert

    public static let noCompatible = "Warp Preview encara no és compatible: cal Warp Stable."

    public var text: String {
        switch self {
        case .nomesPreview: "\(Self.noCompatible) En aquest Mac només hi ha Warp Preview."
        case .obert: "\(Self.noCompatible) Ara és obert Warp Preview, i Warp Stable no: obre Warp Stable i torna-ho a provar."
        }
    }
}
