import Foundation

/// L'URL que demana a Warp que obri un fitxer temporal (D5). Només el core en pot fer una (`init` intern): la part de
/// l'app que obre no pot rebre cap URL qualsevol.
public struct URLLlancament: Sendable, Equatable, CustomStringConvertible {
    public let url: URL

    /// `nom` és el `name:` del fitxer: només `[a-z0-9-]` (`LaunchConfigWarp.esNom`), i no cal codificar res.
    init(nom: String) {
        precondition(LaunchConfigWarp.esNom(nom), "nom de llançament no vàlid")
        guard let url = URL(string: "warp://launch/" + nom) else { preconditionFailure("URL de llançament no vàlida") }
        self.url = url
    }

    public var description: String { url.absoluteString }
}

/// Una pestanya del fitxer temporal, ja amb el text que hi va.
public struct PestanyaYAML: Sendable, Equatable {
    /// El títol de la pestanya a Warp. Buit: el nom de la carpeta.
    public var titol: String
    /// Ruta absoluta.
    public var carpeta: String
    /// La línia que Warp hi escriurà (`OrdreClaude.liniaExec`), o `nil` si la pestanya només és un terminal.
    public var exec: String?

    public init(titol: String, carpeta: String, exec: String?) {
        self.titol = titol
        self.carpeta = carpeta
        self.exec = exec
    }

    /// El títol que porta el fitxer: el de la pestanya o, si és buit, el nom de la carpeta.
    public var titolAWarp: String {
        titol.trimmingCharacters(in: .whitespaces).isEmpty ? URL(filePath: carpeta).lastPathComponent : titol
    }
}

/// El fitxer temporal, a punt per escriure'l. **No escriu res.**
public struct FitxerLaunch: Sendable, Equatable {
    public let llancament: UUID
    public let text: String

    /// El `name:` del fitxer: `warp-launch-<llançament en minúscules>`.
    public var nom: String { LaunchConfigWarp.prefix + llancament.uuidString.lowercased() }
    public var nomFitxer: String { FitxerLaunch.nomFitxer(llancament) }
    /// Bytes que fa el fitxer (UTF-8): es desa a `estat.json` abans d'escriure'l, i es mira abans d'esborrar-lo.
    public var mida: Int { text.utf8.count }
    public var url: URLLlancament { URLLlancament(nom: nom) }
}

/// El fitxer temporal que fa obrir una finestra a Warp (D5, decisió d'en David del 04/11/2026): una launch
/// configuration amb una marca pròpia, que l'app escriu, fa obrir i esborra. Docs/disseny.md, fase 3.1.
///
/// Només hi van els camps que Warp exigeix i el títol de cada pestanya: sense colors, pestanya activa ni grups.
public enum LaunchConfigWarp {
    public static let prefix = "warp-launch-"

    public enum ErrorPestanya: Error, Equatable, CustomStringConvertible {
        /// Buida, relativa o amb `~`: Warp obriria la pestanya a la seva carpeta per defecte i hi executaria l'ordre.
        case carpetaNoAbsoluta(String)
        case titol(YAMLWarp.ErrorYAML)
        case carpeta(YAMLWarp.ErrorYAML)
        case ordre(YAMLWarp.ErrorYAML)

        public var description: String {
            switch self {
            case let .carpetaNoAbsoluta(carpeta): "la carpeta «\(carpeta)» no és una ruta absoluta"
            case let .titol(error): "al títol, \(error)"
            case let .carpeta(error): "a la carpeta, \(error)"
            case let .ordre(error): "a l'ordre, \(error)"
            }
        }
    }

    public enum ErrorLaunch: Error, Equatable, CustomStringConvertible {
        /// Sense pestanyes, Warp obriria una finestra buida.
        case capPestanya
        /// La pestanya `index` (base 0) no es pot escriure.
        case pestanya(index: Int, ErrorPestanya)

        public var description: String {
            switch self {
            case .capPestanya: "no hi ha cap pestanya per obrir"
            case let .pestanya(index, error): "pestanya \(index + 1): \(error)"
            }
        }
    }

    /// La primera línia del fitxer: diu que és de l'app, i de quin llançament.
    public static func marca(_ llancament: UUID) -> String {
        "# warp-launch: temporal \(llancament.uuidString.lowercased())"
    }

    /// `warp-launch-<uuid en minúscules>`: l'únic nom que l'app fa servir.
    static func esNom(_ nom: String) -> Bool {
        guard nom.hasPrefix(prefix) else { return false }
        let resta = String(nom.dropFirst(prefix.count))
        return UUID(uuidString: resta) != nil && resta == resta.lowercased()
    }

    /// Si el nom del fitxer és el d'un fitxer temporal de l'app (`warp-launch-<uuid en minúscules>.yaml`). No diu
    /// res del contingut: abans d'esborrar-lo, s'ha de mirar la marca.
    public static func esNomPropi(_ nomFitxer: String) -> Bool {
        nomFitxer.hasSuffix(".yaml") && esNom(String(nomFitxer.dropLast(".yaml".count)))
    }

    /// Comprova que una pestanya es pot escriure tal com és. El pla d'obertura ho fa amb cada pestanya, per excloure
    /// les que no (i dir per què) abans de generar el fitxer.
    public static func comprova(_ pestanya: PestanyaYAML) throws(ErrorPestanya) {
        _ = try linies(pestanya)
    }

    /// El fitxer d'una finestra amb aquestes pestanyes, en aquest ordre.
    public static func genera(pestanyes: [PestanyaYAML], llancament: UUID) throws(ErrorLaunch) -> FitxerLaunch {
        guard !pestanyes.isEmpty else { throw .capPestanya }
        let nom = prefix + llancament.uuidString.lowercased()
        var text = [marca(llancament), "name: \"\(nom)\"", "windows:", "  - tabs:"]
        for (index, pestanya) in pestanyes.enumerated() {
            do {
                text += try linies(pestanya)
            } catch {
                throw .pestanya(index: index, error)
            }
        }
        return FitxerLaunch(llancament: llancament, text: text.joined(separator: "\n") + "\n")
    }

    /// Les línies d'una pestanya, dins de `tabs:`.
    private static func linies(_ pestanya: PestanyaYAML) throws(ErrorPestanya) -> [String] {
        let carpeta = pestanya.carpeta
        guard carpeta.hasPrefix("/") else { throw .carpetaNoAbsoluta(carpeta) }
        let titol = pestanya.titolAWarp
        var linies: [String]
        do {
            linies = ["      - title: \(try YAMLWarp.escalar(titol))"]
        } catch {
            throw .titol(error)
        }
        do {
            linies += ["        layout:", "          cwd: \(try YAMLWarp.escalar(carpeta))"]
        } catch {
            throw .carpeta(error)
        }
        if let exec = pestanya.exec {
            do {
                linies += ["          commands:", "            - exec: \(try YAMLWarp.escalar(exec))"]
            } catch {
                throw .ordre(error)
            }
        }
        return linies
    }
}
