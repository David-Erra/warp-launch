import Foundation

/// Multidioma (docs/disseny.md, secció 12). És l'únic lloc que coneix el bundle dels textos.
///
/// Els textos són a `Sources/WarpLaunchCore/Textos/<llengua>.lproj/` (`Localizable.strings` i, els plurals,
/// `Localizable.stringsdict`), i SwiftPM els copia al bundle `WarpLaunch_WarpLaunchCore.bundle`. La clau de cada text és el
/// text en català, i `ca.lproj` els té tots (clau = valor).
///
/// La llengua, per ordre: la de prova (`deProva`, només a les proves), la de la variable d'entorn `WARP_LAUNCH_IDIOMA`
/// (`scripts/test.sh` hi posa `ca`) i les preferides del Mac (`Locale.preferredLanguages`). De la llista, la primera que té
/// textos, amb les equivalències de macOS (pt-PT → pt-BR, zh-CN → zh-Hans, es-MX → es); si no n'hi ha cap, l'anglès.
///
/// L'accessor que genera SwiftPM (`module`) no es fa servir: si no troba el bundle, atura el programa, i un binari copiat sol
/// no el porta. Sense el bundle, `t(_:)` torna la clau, en català (`nomesIdiomaConeixElBundleDelsTextos`).
public enum Idioma {
    /// La variable d'entorn que tria la llengua per sobre del Mac. Les proves s'executen en català (`scripts/test.sh`).
    public static let variable = "WARP_LAUNCH_IDIOMA"
    /// La llengua de reserva, si cap de les preferides no té textos (decisió de l'autor).
    public static let reserva = "en"
    /// La llengua de les claus: la que surt sense el bundle.
    public static let original = "ca"
    /// El bundle de recursos de `WarpLaunchCore` (paquet `WarpLaunch`, target `WarpLaunchCore`), com el diu SwiftPM.
    public static let nomDelBundle = "WarpLaunch_WarpLaunchCore.bundle"

    /// Només per a les proves: la llengua dins d'un bloc, per sobre de la variable i del Mac.
    /// `Idioma.$deProva.withValue("en") { t("Obre a Warp…") }` dona «Open in Warp…».
    @TaskLocal public static var deProva: String?

    /// La llengua dels textos, entre les que en tenen (`ca`, `en`, `pt-BR`…).
    public static var efectiva: String {
        if let deProva { return tria(disponibles: disponibles, preferencies: [deProva]) }
        return delProces
    }

    /// El `locale` de la llengua dels textos: els plurals i les xifres la segueixen a ella, no la regió del Mac.
    public static var locale: Locale { Locale(identifier: efectiva) }

    /// Una enumeració, amb la conjunció i les comes de la llengua dels textos: «A i B», «A, B i C» (en anglès, «A, B, and C»).
    public static func llista(_ elements: [String]) -> String {
        let formatador = ListFormatter()
        formatador.locale = locale
        return formatador.string(from: elements) ?? elements.joined(separator: ", ")
    }

    /// Els textos del paquet, o res si el bundle no es troba (un binari copiat sol).
    static let textos: Textos? = Textos.delPrimer(candidats(principal: .main, codi: Bundle(for: Marca.self)))

    /// Les llengües amb textos. Sense el bundle, només la de les claus.
    static var disponibles: [String] { textos?.llengues ?? [original] }

    /// La llengua del procés: no canvia mentre corre, com la dels menús de macOS.
    private static let delProces = tria(disponibles: disponibles,
                                        preferencies: preferencies(entorn: ProcessInfo.processInfo.environment,
                                                                   delMac: Locale.preferredLanguages))

    /// Les llengües preferides: la de la variable, si n'hi ha, i si no, les del Mac.
    static func preferencies(entorn: [String: String], delMac: [String]) -> [String] {
        if let llengua = entorn[variable]?.trimmingCharacters(in: .whitespaces), !llengua.isEmpty { return [llengua] }
        return delMac
    }

    /// La primera llengua de `preferencies` que té textos, amb les equivalències de macOS; si cap no en té, la de reserva
    /// (o, si tampoc no en té, la primera disponible).
    static func tria(disponibles: [String], preferencies: [String]) -> String {
        let reserva = disponibles.contains(Self.reserva) ? Self.reserva : (disponibles.first ?? original)
        // La reserva no va al final de les preferències: macOS triaria l'anglès abans que pt-BR per a pt-PT.
        guard let triada = Bundle.preferredLocalizations(from: disponibles, forPreferences: preferencies).first else {
            return reserva
        }
        // Sense cap coincidència, macOS ja tria l'anglès, però no ho promet: la reserva és nostra.
        let llengua = { (codi: String) in Locale.Language(identifier: codi).languageCode }
        return preferencies.contains { llengua($0) == llengua(triada) } ? triada : reserva
    }

    /// On pot ser el bundle: dins del paquet de l'app (`Contents/Resources`), al costat de l'executable (el CLI, també per un
    /// enllaç), on el busca SwiftPM, i al costat del codi (les proves: el `.xctest` és al costat del bundle).
    static func candidats(principal: Bundle, codi: Bundle) -> [URL] {
        var carpetes: [URL] = []
        if let recursos = principal.resourceURL { carpetes.append(recursos) }
        if let executable = principal.executableURL {
            carpetes.append(executable.deletingLastPathComponent())
            carpetes.append(executable.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        carpetes.append(principal.bundleURL)
        carpetes.append(codi.bundleURL.deletingLastPathComponent())
        return carpetes.map { $0.appending(path: nomDelBundle) }
    }

    /// El text en `llengua`; sense el bundle o sense la llengua, la clau, en català.
    static func text(_ clau: String.LocalizationValue, textos: Textos?, llengua: String) -> String {
        if let text = textos?.text(clau, llengua: llengua) { return text }
        // Una taula que no existeix: la clau, amb els valors posats com en català.
        return String(localized: clau, table: taulaQueNoHiEs, bundle: .main, locale: Locale(identifier: original))
    }

    private static let taulaQueNoHiEs = "WarpLaunchSenseTextos"
}

/// El text en la llengua de l'app. La clau és el text en català, i pot portar valors (`t("\(n) finestres")`, amb la clau
/// «%lld finestres»): els plurals són al `.stringsdict`.
public func t(_ clau: String.LocalizationValue) -> String {
    Idioma.text(clau, textos: Idioma.textos, llengua: Idioma.efectiva)
}

/// Els textos d'un bundle de recursos: una carpeta `.lproj` per llengua.
struct Textos: Sendable {
    /// Les llengües, en ordre alfabètic.
    let llengues: [String]
    /// Cada `.lproj` com a bundle propi: un bundle que no és el principal seguiria la llengua de l'app, i el CLI i les
    /// proves, sense `Info.plist`, sortirien sempre en anglès.
    private let perLlengua: [String: Bundle]

    /// Els textos de la carpeta, o res si no té cap `.lproj`.
    init?(bundle url: URL) {
        guard let bundle = Bundle(url: url), let recursos = bundle.resourceURL,
              let contingut = try? FileManager.default.contentsOfDirectory(at: recursos, includingPropertiesForKeys: nil)
        else { return nil }
        var perLlengua: [String: Bundle] = [:]
        for carpeta in contingut where carpeta.pathExtension == "lproj" {
            let llengua = carpeta.deletingPathExtension().lastPathComponent
            if llengua != "Base", let bundle = Bundle(url: carpeta) { perLlengua[llengua] = bundle }
        }
        guard !perLlengua.isEmpty else { return nil }
        self.perLlengua = perLlengua
        llengues = perLlengua.keys.sorted()
    }

    /// Els del primer candidat que en té.
    static func delPrimer(_ candidats: [URL]) -> Textos? {
        for candidat in candidats {
            if let textos = Textos(bundle: candidat) { return textos }
        }
        return nil
    }

    /// El text en `llengua`, amb el seu `locale`, o res si la llengua no hi és. Si la clau no hi és, la clau.
    func text(_ clau: String.LocalizationValue, llengua: String) -> String? {
        guard let bundle = perLlengua[llengua] else { return nil }
        return String(localized: clau, table: nil, bundle: bundle, locale: Locale(identifier: llengua))
    }
}

/// Per trobar el bundle del codi (`Bundle(for:)`): a les proves, el `.xctest`.
private final class Marca {}
