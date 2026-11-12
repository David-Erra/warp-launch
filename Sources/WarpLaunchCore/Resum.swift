import Foundation

// Xifres per al menú de la icona i per al subtítol de l'editor.

public enum Plural {
    /// «1 pestanya», «0 pestanyes», «12 pestanyes».
    public static func compta(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}

/// Què hi ha obert a Warp, en xifres.
public struct ResumWarp: Sendable, Equatable {
    public var finestres: Int
    public var pestanyes: Int
    /// Sessions de Claude que corren en alguna pestanya de Warp.
    public var sessionsClaude: Int
    /// Els terminals vius, si Warp no desa les finestres (llavors no se'n saben les finestres ni les pestanyes).
    public var terminals: Int?

    public init(finestres: Int, pestanyes: Int, sessionsClaude: Int, terminals: Int? = nil) {
        self.finestres = finestres
        self.pestanyes = pestanyes
        self.sessionsClaude = sessionsClaude
        self.terminals = terminals
    }

    public init(_ lectura: LecturaWarp) {
        if lectura.warpDesaFinestres == false {
            self.init(finestres: 0, pestanyes: 0, sessionsClaude: lectura.sessionsSensePestanya.filter(\.dinsDeWarp).count,
                      terminals: lectura.terminals.count)
            return
        }
        let pestanyes = lectura.finestres.flatMap(\.pestanyes)
        self.init(finestres: lectura.finestres.count, pestanyes: pestanyes.count,
                  sessionsClaude: pestanyes.flatMap(\.panes).filter { $0.claude != nil }.count)
    }

    /// «Warp: 4 finestres · 30 pestanyes · 6 sessions de Claude», o «Warp: 6 terminals · 6 sessions de Claude».
    public var descripcio: String {
        if let terminals {
            return t("Warp: \(terminals) terminals · \(sessionsClaude) sessions de Claude")
        }
        return t("Warp: \(finestres) finestres · \(pestanyes) pestanyes · \(sessionsClaude) sessions de Claude")
    }
}

extension Finestra {
    /// Pestanyes que obriran Claude.
    public var ambClaude: Int { pestanyes.filter(\.claude.activat).count }

    /// «12 pestanyes · 8 amb Claude».
    public var resum: String {
        t("\(pestanyes.count) pestanyes · \(ambClaude) amb Claude")
    }
}

/// Arguments de l'app (`WarpLaunch`). Només n'hi ha un: `--config <carpeta>` (o `--config=<carpeta>`), per provar-la
/// amb una configuració que no sigui la d'en David.
///
/// Un argument mal escrit no torna mai a la configuració real: l'app s'obre sense cap configuració i diu per què.
/// Així, una prova amb `--config` mal posat no pot escriure a `~/.config/warp-launch/`. Només s'ignoren els
/// arguments que hi pot posar macOS: `-psn_…` i els de les preferències (`-NSDocumentRevisionsDebugMode YES`).
public struct ArgumentsApp: Sendable, Equatable {
    public enum Carpeta: Sendable, Equatable {
        /// Sense `--config`: la d'en David (D8).
        case real(URL)
        /// `--config <carpeta>`: el menú de la icona i l'editor ho diuen, perquè no es confongui amb la real.
        case prova(URL)
        /// Arguments que no s'entenen: no es fa servir cap carpeta.
        case incorrecta(String)
    }

    public var carpeta: Carpeta

    public init(_ arguments: [String], inici: String) {
        carpeta = Self.interpreta(arguments.dropFirst(), inici: inici)
    }

    /// La carpeta que es farà servir; `nil` si els arguments són incorrectes.
    public var carpetaConfiguracio: URL? {
        switch carpeta {
        case let .real(url), let .prova(url): url
        case .incorrecta: nil
        }
    }

    public var deProva: Bool {
        if case .prova = carpeta { true } else { false }
    }

    private static func interpreta(_ arguments: ArraySlice<String>, inici: String) -> Carpeta {
        let real = Rutes.carpetaConfiguracio(inici: inici)
        var resta = arguments
        var valor: String?
        while let argument = resta.popFirst() {
            let trobat: String
            if argument == "--config" {
                trobat = resta.popFirst() ?? ""
            } else if argument.hasPrefix("--config=") {
                trobat = String(argument.dropFirst("--config=".count))
            } else if argument.hasPrefix("-psn_") {
                continue
            } else if argument.hasPrefix("-NS") || argument.hasPrefix("-Apple") {
                _ = resta.popFirst()
                continue
            } else {
                return .incorrecta(t("argument desconegut «\(argument)»; per provar l'app: --config <carpeta>"))
            }
            if valor != nil { return .incorrecta(t("«--config» hi és més d'un cop")) }
            valor = trobat
        }
        guard let valor else { return .real(real) }
        guard !valor.isEmpty else { return .incorrecta(t("falta la carpeta després de «--config»")) }
        let ruta: String
        if valor.hasPrefix("/") {
            ruta = valor
        } else if valor == "~" || valor.hasPrefix("~/") {
            ruta = inici + valor.dropFirst()
        } else {
            return .incorrecta(t("la carpeta de «--config» ha de ser una ruta absoluta (que comenci per / o ~/): «\(valor)»"))
        }
        let url = URL(filePath: ruta, directoryHint: .isDirectory).standardizedFileURL
        // Si és la real, ho ha de dir: no és cap prova.
        return url.path == real.standardizedFileURL.path ? .real(real) : .prova(url)
    }
}

extension ClaudePestanya {
    /// El nom del mode de Claude (`--effort ultracode`), que no es tradueix: la fila de la llista, l'inspector i la Configuració.
    public static let nomUltracode = "Ultracode"

    /// Per a la fila de la llista (docs/disseny.md, «Disposició»): «Opus · Molt alt · Ultracode», «Claude» si no hi ha
    /// res més a dir, o «Només terminal».
    public var resum: String {
        guard activat else { return t("Només terminal") }
        let net = normalitzada()
        var parts: [String] = []
        if let model = net.model { parts.append(Self.nomModel(model)) }
        if let esforc = net.esforc, !esforc.isEmpty { parts.append(Self.nomEsforc(esforc)) }
        if net.ultracode { parts.append(Self.nomUltracode) }
        return parts.isEmpty ? "Claude" : parts.joined(separator: " · ")
    }

    /// «Baix», «Mitjà», «Alt», «Molt alt», «Màxim»; un esforç desconegut, tal com està escrit.
    public static func nomEsforc(_ esforc: String) -> String {
        switch esforc {
        case "low": t("Baix")
        case "medium": t("Mitjà")
        case "high": t("Alt")
        case "xhigh": t("Molt alt")
        case "max": t("Màxim")
        default: esforc
        }
    }

    /// Àlies de model que ofereix l'inspector, del més capaç al més petit (`--model`, fets-verificats). Un id complet
    /// (`claude-opus-5-5`) també és vàlid: es conserva i es mostra tal com està escrit.
    public static let modelsConeguts = ["fable", "opus", "sonnet", "haiku"]

    /// El nom d'un mode de permisos, amb el de Claude entre parèntesis (és el que es veu a Claude).
    public static func nomMode(_ mode: String) -> String {
        let nom: String? = switch mode {
        case "acceptEdits": t("Accepta les edicions")
        case "auto": t("Automàtic")
        case "bypassPermissions": t("Sense cap permís")
        case "manual": t("Manual")
        case "dontAsk": t("No preguntis")
        case "plan": t("Planifica")
        default: nil
        }
        // Els parèntesis, els de la llengua («（）» en japonès i en xinès).
        return nom.map { t("\($0) (\(mode))") } ?? mode
    }

    /// Les opcions que l'inspector no edita, per mostrar-les en només lectura: `--settings`, `--remote-control` i les
    /// que l'app no entén. Normalitzades, com a l'ordre i al fitxer (un `"ultracode"` de `--settings` és l'interruptor).
    public var opcionsNomesLectura: [(nom: String, valor: String)] {
        let net = normalitzada()
        let (settings, controlRemot, altres) = (net.settings, net.controlRemot, net.altres)
        var opcions: [(nom: String, valor: String)] = []
        if let settings { opcions.append(("--settings", settings)) }
        if let controlRemot { opcions.append(("--remote-control", controlRemot.isEmpty ? t("sense nom") : controlRemot)) }
        if !altres.isEmpty { opcions.append((t("Altres"), altres.joined(separator: " "))) }
        return opcions
    }

    /// Els àlies de model de Claude Code amb majúscula («Opus»); la resta (un id complet), tal com està escrit.
    public static func nomModel(_ model: String) -> String {
        switch model.lowercased() {
        case "opus": "Opus"
        case "sonnet": "Sonnet"
        case "haiku": "Haiku"
        case "fable": "Fable"
        default: model
        }
    }
}

extension Importacio {
    /// Quantes pestanyes tenen aquest origen (per dir, al full, per què n'hi ha sense Claude).
    public func compta(_ origen: OrigenClaude) -> Int {
        configuracio.finestres.flatMap(\.pestanyes).filter { origens[$0.id] == origen }.count
    }
}
