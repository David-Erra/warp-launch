import Foundation

/// L'app de Warp que obre el fitxer temporal (fase 3.1): la d'Aplicacions, i només si el paquet és el de Warp. Només
/// llegeix l'`Info.plist`: no obre res.
public struct AppWarp: Sendable {
    public static let identificador = "dev.warp.Warp-Stable"
    public static let real = AppWarp(url: URL(filePath: "/Applications/Warp.app", directoryHint: .isDirectory))

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private var info: [String: Any]? {
        guard let dades = try? Data(contentsOf: url.appending(path: "Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: dades, format: nil) as? [String: Any]
    }

    /// Si és Warp: l'`Info.plist` diu `dev.warp.Warp-Stable`.
    public var esWarp: Bool { info?["CFBundleIdentifier"] as? String == Self.identificador }

    /// La versió (`CFBundleShortVersionString`), per al full de confirmació i les proves reals.
    public var versio: String? { info?["CFBundleShortVersionString"] as? String }
}
