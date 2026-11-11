import Foundation

/// Configuració de Warp Launch: les finestres de Warp que l'app ha de saber tornar a obrir, amb les seves pestanyes.
/// Es desa a `~/.config/warp-launch/configuracio.json`, que és d'en David (format a `docs/disseny.md`).
public struct Configuracio: Sendable, Equatable {
    /// Versió del format que escriu aquesta app. Tot canvi de format la puja i porta una migració (regla 11).
    public static let versioActual = 1

    /// Opcions de Claude que reben les pestanyes noves (es copien; no s'hi fa referència).
    public var plantilla: ClaudePestanya
    public var finestres: [Finestra]
    /// Qui va escriure el fitxer per última vegada, per exemple «Warp Launch 0.3.0». Només informatiu.
    public var generador: String?

    public init(plantilla: ClaudePestanya = .perOmissio, finestres: [Finestra] = [], generador: String? = nil) {
        self.plantilla = plantilla
        self.finestres = finestres
        self.generador = generador
    }
}

/// Una finestra de Warp, que per a en David és un grup de sessions.
public struct Finestra: Sendable, Equatable, Identifiable {
    /// Id propi: els de Warp canvien cada vegada que Warp desa.
    public var id: UUID
    public var nom: String
    public var pestanyes: [Pestanya]

    public init(id: UUID, nom: String, pestanyes: [Pestanya] = []) {
        self.id = id
        self.nom = nom
        self.pestanyes = pestanyes
    }
}

public struct Pestanya: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var titol: String
    /// Ruta absoluta.
    public var carpeta: String
    public var claude: ClaudePestanya

    public init(id: UUID, titol: String, carpeta: String, claude: ClaudePestanya) {
        self.id = id
        self.titol = titol
        self.carpeta = carpeta
        self.claude = claude
    }
}

/// Com s'obre Claude Code en una pestanya. Només hi ha el que és de la pestanya: la conversa que es reprèn
/// (`--resume <id>`, D7) la posa qui llança.
public struct ClaudePestanya: Sendable, Equatable {
    /// `false`: la pestanya només és un terminal.
    public var activat: Bool
    public var model: String?
    /// `low`, `medium`, `high`, `xhigh` o `max`. L'àlies `ultracode` es desa com a `xhigh` més `ultracode`.
    public var esforc: String?
    public var ultracode: Bool
    /// Reprendre la conversa de la pestanya en lloc d'obrir-ne una de nova (R4: activat per defecte). Si no se sap
    /// quina és, se'n comença una de nova (D7).
    public var continua: Bool
    /// Nom fix de la sessió (`-n`).
    public var nom: String?
    /// `--dangerously-skip-permissions`. **Mai `true` si no s'ha dit explícitament.**
    public var saltaPermisos: Bool
    public var modePermisos: String?
    /// Valor de `--settings`, sense interpretar (JSON o ruta).
    public var settings: String?
    /// `--remote-control`. Buit (`""`) vol dir sense nom.
    public var controlRemot: String?
    /// Opcions que l'app no entén, en ordre i literals.
    public var altres: [String]

    public init(activat: Bool = true, model: String? = nil, esforc: String? = nil, ultracode: Bool = false,
                continua: Bool = true, nom: String? = nil, saltaPermisos: Bool = false, modePermisos: String? = nil,
                settings: String? = nil, controlRemot: String? = nil, altres: [String] = []) {
        self.activat = activat
        self.model = model
        self.esforc = esforc
        self.ultracode = ultracode
        self.continua = continua
        self.nom = nom
        self.saltaPermisos = saltaPermisos
        self.modePermisos = modePermisos
        self.settings = settings
        self.controlRemot = controlRemot
        self.altres = altres
    }

    /// Valors segurs quan el fitxer no diu res: Claude activat, continuar, i res més. També és la plantilla d'una
    /// configuració nova, importada de Warp o en blanc (D11, revisada per en David el 07/11/2026).
    public static let perOmissio = ClaudePestanya()

    /// Pestanya que només és un terminal.
    public static let nomesTerminal = ClaudePestanya(activat: false)

    /// Si Claude hi corre sense demanar permisos, sigui amb un paràmetre o amb l'altre: les dues ordres donen el mateix mode.
    public var enBypass: Bool { saltaPermisos || modePermisos == "bypassPermissions" }

    /// Esforços que Claude Code accepta (`claude --help`, 03/11/2026).
    public static let esforcosConeguts = ["low", "medium", "high", "xhigh", "max"]

    /// Modes de permisos que Claude Code accepta (`claude --help` de la 2.1.318, 04/11/2026). Amb un altre, Claude
    /// s'atura amb un error: `--permission-mode` té `choices`.
    public static let modesPermisos = ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"]

    /// Forma canònica del format v1, la que s'escriu i la que es llegeix:
    /// - esforç en minúscules, i l'àlies `ultracode` com a `xhigh` més `ultracode`;
    /// - si `settings` és un JSON amb `"ultracode": true`, la clau en surt i activa `ultracode`. Amb `false`, en surt
    ///   només si la pestanya ja té ultracode (llavors no fa res a Claude); si no, s'hi queda, perquè apaga l'ultracode
    ///   que pugui venir de la configuració de Claude de l'usuari o del projecte;
    /// - sense textos buits ni fets només d'espais, excepte `controlRemot` (`""` vol dir `--remote-control` sense nom).
    public func normalitzada() -> ClaudePestanya {
        var c = self
        let (esforc, alies) = Configuracio.normalitza(esforc: esforc)
        c.esforc = esforc
        c.ultracode = ultracode || alies
        c.model = model.flatMap(Self.senseBuits)
        c.nom = nom.flatMap(Self.senseBuits)
        c.modePermisos = modePermisos.flatMap(Self.senseBuits)
        c.settings = nil
        if let settings = settings.flatMap(Self.senseBuits) {
            let (resta, valor) = Self.separaUltracode(de: settings)
            switch valor {
            case true?:
                c.settings = resta
                c.ultracode = true
            case false? where c.ultracode: c.settings = resta
            default: c.settings = settings
            }
        }
        return c
    }

    /// El valor de `"ultracode"` d'un `--settings` en JSON, si és booleà, i el JSON sense la clau (`nil` si queda buit).
    /// Una ruta de fitxer, un JSON sense la clau o amb claus repetides (`SettingsClaude.objecte`) no canvia.
    static func separaUltracode(de settings: String) -> (settings: String?, ultracode: Bool?) {
        guard var json = SettingsClaude.objecte(settings), let valor = SettingsClaude.ultracode(json) else {
            return (settings, nil)
        }
        json.removeValue(forKey: "ultracode")
        if json.isEmpty { return (nil, valor) }
        guard let net = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return (settings, nil) }
        return (String(decoding: net, as: UTF8.self), valor)
    }

    /// `nil` si el text és buit o només té espais.
    private static func senseBuits(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}

// MARK: - Errors i avisos

public enum ErrorConfiguracio: Error, Equatable, Sendable, CustomStringConvertible {
    /// El fitxer no és JSON vàlid. `linia` i `columna` comencen per 1.
    case jsonMalmes(linia: Int?, columna: Int?)
    /// El JSON és vàlid però no té la forma de la configuració. `cami` diu on, per exemple `finestres[0].nom`.
    case formaIncorrecta(cami: String, detall: String)
    case senseVersio
    /// Escrit per una versió més nova de Warp Launch: no es pot llegir sense perdre dades.
    case versioMesNova(Int)
    case versioDesconeguda(Int)

    public var description: String {
        switch self {
        case let .jsonMalmes(linia?, columna?): t("el fitxer no és JSON vàlid (línia \(String(linia)), columna \(String(columna)))")
        case .jsonMalmes: t("el fitxer no és JSON vàlid")
        case let .formaIncorrecta(cami, detall): cami.isEmpty ? t("el fitxer: \(detall)") : t("\(cami): \(detall)")
        case .senseVersio: t("falta el camp «versio»")
        case let .versioMesNova(n):
            t("el fitxer és de la versió \(String(n)) del format, i aquesta app només entén fins a la \(String(Configuracio.versioActual)): cal una versió més nova de Warp Launch")
        case let .versioDesconeguda(n): t("versió del format desconeguda: \(String(n))")
        }
    }
}

/// Coses que s'han corregit en llegir un fitxer escrit a mà. No impedeixen obrir-lo.
public enum AvisFormat: Equatable, Sendable, CustomStringConvertible {
    case clauDesconeguda(cami: String)
    /// La pestanya no té bloc `claude`: s'ha llegit com a només terminal.
    case claudeSenseConfigurar(cami: String)
    case idNou(cami: String, motiu: MotiuIdNou)
    case sensePlantilla
    /// La carpeta no és una ruta absoluta (ni `~/…`), o falta.
    case carpetaNoAbsoluta(cami: String)

    public enum MotiuIdNou: String, Sendable { case absent, invalid, repetit }

    public var description: String {
        switch self {
        case let .clauDesconeguda(cami): t("\(cami): clau desconeguda; es perdrà en desar (la còpia la conserva)")
        case let .claudeSenseConfigurar(cami): t("\(cami): sense bloc «claude»; queda com a només terminal")
        case let .idNou(cami, .absent): t("\(cami): id absent; se n'ha posat un de nou")
        case let .idNou(cami, .invalid): t("\(cami): id invalid; se n'ha posat un de nou")
        case let .idNou(cami, .repetit): t("\(cami): id repetit; se n'ha posat un de nou")
        case .sensePlantilla: t("falta la plantilla; es fan servir valors segurs (sense saltar permisos)")
        case let .carpetaNoAbsoluta(cami): t("\(cami): la carpeta ha de ser una ruta absoluta (que comenci per / o ~/)")
        }
    }
}

public struct ConfiguracioLlegida: Sendable, Equatable {
    public var configuracio: Configuracio
    public var avisos: [AvisFormat]
}

// MARK: - Lectura

extension Configuracio {
    /// Llegeix un fitxer de configuració. No toca el disc.
    /// - Parameters:
    ///   - inici: carpeta d'inici, per expandir les carpetes escrites com a `~/…`.
    ///   - nouId: genera els id que falten o es repeteixen (a les proves, de manera determinista).
    public static func llegeix(_ dades: Data, inici: String,
                               nouId: () -> UUID = { UUID() }) throws(ErrorConfiguracio) -> ConfiguracioLlegida {
        // Només UTF-8 (amb BOM o sense): és el que escriu l'app i el que permet dir la línia i la columna d'un error.
        let net = dades.starts(with: [0xEF, 0xBB, 0xBF]) ? dades.dropFirst(3) : dades
        guard !net.contains(0), String(data: net, encoding: .utf8) != nil else {
            throw .formaIncorrecta(cami: "", detall: t("el fitxer ha de ser text UTF-8"))
        }
        let arrel: Any
        do {
            arrel = try JSONSerialization.jsonObject(with: net, options: .fragmentsAllowed)
        } catch {
            let (linia, columna) = posicio(de: error as NSError, a: net)
            throw .jsonMalmes(linia: linia, columna: columna)
        }
        guard let objecte = arrel as? [String: Any] else {
            throw .formaIncorrecta(cami: "", detall: t("ha de ser un objecte JSON"))
        }
        // JSONSerialization i JSONDecoder es queden amb la primera aparició d'una clau repetida, i jq o Python amb
        // l'última: el fitxer és ambigu (per exemple, "saltaPermisos": true i més avall false).
        if let repetida = ClausRepetides.primera(Array(net)) {
            throw .formaIncorrecta(cami: repetida.cami, detall: t("clau «\(repetida.clau)» repetida"))
        }
        guard let valorVersio = objecte["versio"] else { throw .senseVersio }
        guard let versio = enter(valorVersio) else {
            throw .formaIncorrecta(cami: "versio", detall: t("ha de ser un nombre enter"))
        }
        if versio > versioActual { throw .versioMesNova(versio) }
        if versio < 1 { throw .versioDesconeguda(versio) }
        // Aquí aniria la cadena de migracions (versio < versioActual). Encara no n'hi ha cap.

        let fitxer: FitxerV1
        do {
            fitxer = try JSONDecoder().decode(FitxerV1.self, from: Data(net))
        } catch let error as DecodingError {
            throw descriu(error)
        } catch {
            throw .formaIncorrecta(cami: "", detall: "\(error)")
        }

        var avisos = clausDesconegudes(objecte)
        // Els id del fitxer guanyen: un id nou no pot coincidir amb cap que hi aparegui, encara que sigui més avall.
        let delFitxer = Set(((fitxer.finestres ?? []).flatMap { [$0.id] + ($0.pestanyes ?? []).map(\.id) })
            .compactMap { $0.flatMap(UUID.init(uuidString:)) })
        var vistos = Set<UUID>()
        func id(_ text: String?, cami: String) -> UUID {
            let motiu: AvisFormat.MotiuIdNou
            if let text {
                if let uuid = UUID(uuidString: text) {
                    if vistos.insert(uuid).inserted { return uuid }
                    motiu = .repetit
                } else {
                    motiu = .invalid
                }
            } else {
                motiu = .absent
            }
            var nou = nouId()
            while delFitxer.contains(nou) || !vistos.insert(nou).inserted { nou = nouId() }
            avisos.append(.idNou(cami: cami, motiu: motiu))
            return nou
        }

        let plantilla: ClaudePestanya
        if let p = fitxer.plantilla {
            plantilla = p.valor
        } else {
            plantilla = .perOmissio
            avisos.append(.sensePlantilla)
        }
        var finestres: [Finestra] = []
        for (f, finestra) in (fitxer.finestres ?? []).enumerated() {
            let camiFinestra = "finestres[\(f)]"
            let idFinestra = id(finestra.id, cami: camiFinestra)
            var pestanyes: [Pestanya] = []
            for (p, pestanya) in (finestra.pestanyes ?? []).enumerated() {
                let cami = "\(camiFinestra).pestanyes[\(p)]"
                let claude: ClaudePestanya
                if let c = pestanya.claude {
                    claude = c.valor
                } else {
                    claude = .nomesTerminal
                    avisos.append(.claudeSenseConfigurar(cami: cami))
                }
                let carpeta = expandeix(pestanya.carpeta ?? "", inici: inici)
                if !carpeta.hasPrefix("/") { avisos.append(.carpetaNoAbsoluta(cami: cami)) }
                pestanyes.append(Pestanya(id: id(pestanya.id, cami: cami), titol: pestanya.titol ?? "",
                                          carpeta: carpeta, claude: claude))
            }
            finestres.append(Finestra(id: idFinestra, nom: finestra.nom ?? "",
                                      pestanyes: pestanyes))
        }
        let configuracio = Configuracio(plantilla: plantilla, finestres: finestres, generador: fitxer.generador)
        return ConfiguracioLlegida(configuracio: configuracio, avisos: avisos)
    }

    /// `~` i `~/…` escrits a mà passen a ruta absoluta.
    static func expandeix(_ ruta: String, inici: String) -> String {
        if ruta == "~" { return inici }
        if ruta.hasPrefix("~/") { return (inici as NSString).appendingPathComponent(String(ruta.dropFirst(2))) }
        return ruta
    }

    /// Esforç escrit a mà, en minúscules. L'àlies `ultracode` passa a `xhigh` més ultracode.
    static func normalitza(esforc: String?) -> (esforc: String?, ultracode: Bool) {
        guard let net = esforc?.trimmingCharacters(in: .whitespaces).lowercased(), !net.isEmpty else {
            return (nil, false)
        }
        return net == "ultracode" ? ("xhigh", true) : (net, false)
    }

    /// Un nombre enter, també si és molt gran (llavors, `Int.max`: més nou que qualsevol versió coneguda).
    private static func enter(_ valor: Any) -> Int? {
        guard let nombre = valor as? NSNumber, CFGetTypeID(nombre) != CFBooleanGetTypeID() else { return nil }
        let doble = nombre.doubleValue
        guard doble.isFinite, doble == doble.rounded() else { return nil }
        if doble >= 9.2e18 { return Int.max }
        if doble <= -9.2e18 { return Int.min }
        // Per sota de 2^53 el Double és exacte; per sobre, el valor enter de l'NSNumber.
        return abs(doble) < 9_007_199_254_740_992 ? Int(doble) : Int(nombre.int64Value)
    }

    private static func posicio(de error: NSError, a dades: Data.SubSequence) -> (Int?, Int?) {
        guard let index = error.userInfo["NSJSONSerializationErrorIndex"] as? Int, index <= dades.count else {
            return (nil, nil)
        }
        var linia = 1, columna = 1, despresDeCR = false
        for byte in dades.prefix(index) {
            switch byte {
            case UInt8(ascii: "\n"):
                if !despresDeCR { linia += 1 }  // \r\n és un sol salt de línia
                columna = 1
                despresDeCR = false
            case UInt8(ascii: "\r"):
                linia += 1
                columna = 1
                despresDeCR = true
            default:
                despresDeCR = false
                if byte & 0xC0 != 0x80 { columna += 1 }  // no compta els bytes de continuació d'UTF-8
            }
        }
        return (linia, columna)
    }

    private static func descriu(_ error: DecodingError) -> ErrorConfiguracio {
        func cami(_ claus: [any CodingKey]) -> String {
            claus.reduce("") { cami, clau in
                if let index = clau.intValue { return "\(cami)[\(index)]" }
                return cami.isEmpty ? clau.stringValue : "\(cami).\(clau.stringValue)"
            }
        }
        switch error {
        case let .typeMismatch(tipus, context):
            return .formaIncorrecta(cami: cami(context.codingPath), detall: t("tipus incorrecte (s'esperava \(nomDe(tipus)))"))
        case let .valueNotFound(tipus, context):
            return .formaIncorrecta(cami: cami(context.codingPath), detall: t("falta el valor (s'esperava \(nomDe(tipus)))"))
        case let .keyNotFound(clau, context):
            return .formaIncorrecta(cami: cami(context.codingPath + [clau]), detall: t("falta la clau"))
        case let .dataCorrupted(context):
            return .formaIncorrecta(cami: cami(context.codingPath), detall: context.debugDescription)
        @unknown default:
            return .formaIncorrecta(cami: "", detall: "\(error)")
        }
    }

    private static func nomDe(_ tipus: Any.Type) -> String {
        switch tipus {
        case is String.Type: t("text")
        case is Bool.Type: t("true o false")
        case is Int.Type: t("nombre enter")
        case is [Any].Type, is [String].Type: t("una llista")
        default: t("un objecte")
        }
    }

    private static func clausDesconegudes(_ arrel: [String: Any]) -> [AvisFormat] {
        var avisos: [AvisFormat] = []
        func revisa(_ objecte: [String: Any], conegudes: Set<String>, cami: String) {
            for clau in objecte.keys.sorted() where !conegudes.contains(clau) {
                avisos.append(.clauDesconeguda(cami: cami.isEmpty ? clau : "\(cami).\(clau)"))
            }
        }
        revisa(arrel, conegudes: FitxerV1.claus, cami: "")
        if let plantilla = arrel["plantilla"] as? [String: Any] {
            revisa(plantilla, conegudes: ClaudeFitxer.claus, cami: "plantilla")
        }
        for (f, finestra) in ((arrel["finestres"] as? [Any]) ?? []).enumerated() {
            guard let finestra = finestra as? [String: Any] else { continue }
            revisa(finestra, conegudes: FinestraFitxer.claus, cami: "finestres[\(f)]")
            for (p, pestanya) in ((finestra["pestanyes"] as? [Any]) ?? []).enumerated() {
                guard let pestanya = pestanya as? [String: Any] else { continue }
                let cami = "finestres[\(f)].pestanyes[\(p)]"
                revisa(pestanya, conegudes: PestanyaFitxer.claus, cami: cami)
                if let claude = pestanya["claude"] as? [String: Any] {
                    revisa(claude, conegudes: ClaudeFitxer.claus, cami: "\(cami).claude")
                }
            }
        }
        return avisos
    }
}

// MARK: - Escriptura

extension Configuracio {
    /// JSON del fitxer, amb les claus ordenades i un salt de línia final, perquè es pugui llegir i comparar.
    /// Els valors absents i les llistes buides no s'escriuen. La versió és sempre `versioActual`.
    public func json() throws -> Data {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var dades = try codificador.encode(FitxerV1(self))
        dades.append(UInt8(ascii: "\n"))
        return dades
    }
}

// MARK: - Format al disc (versió 1)

/// Tot és opcional en llegir, per poder posar-hi valors per defecte i avisar; en escriure, només hi ha el que cal.
private struct FitxerV1: Codable {
    var versio: Int?
    var generador: String?
    var plantilla: ClaudeFitxer?
    var finestres: [FinestraFitxer]?

    static let claus: Set<String> = ["versio", "generador", "plantilla", "finestres"]

    init(_ c: Configuracio) {
        versio = Configuracio.versioActual
        generador = c.generador
        plantilla = ClaudeFitxer(c.plantilla)
        finestres = c.finestres.map(FinestraFitxer.init)
    }
}

private struct FinestraFitxer: Codable {
    var id: String?
    var nom: String?
    var pestanyes: [PestanyaFitxer]?

    static let claus: Set<String> = ["id", "nom", "pestanyes"]

    init(_ f: Finestra) {
        id = f.id.uuidString
        nom = f.nom
        pestanyes = f.pestanyes.map(PestanyaFitxer.init)
    }
}

private struct PestanyaFitxer: Codable {
    var id: String?
    var titol: String?
    var carpeta: String?
    var claude: ClaudeFitxer?

    static let claus: Set<String> = ["id", "titol", "carpeta", "claude"]

    init(_ p: Pestanya) {
        id = p.id.uuidString
        titol = p.titol
        carpeta = p.carpeta
        claude = ClaudeFitxer(p.claude)
    }
}

private struct ClaudeFitxer: Codable {
    var activat: Bool?
    var model: String?
    var esforc: String?
    var ultracode: Bool?
    var continua: Bool?
    var nom: String?
    var saltaPermisos: Bool?
    var modePermisos: String?
    var settings: String?
    var controlRemot: String?
    var altres: [String]?

    static let claus: Set<String> = ["activat", "model", "esforc", "ultracode", "continua", "nom", "saltaPermisos",
                                     "modePermisos", "settings", "controlRemot", "altres"]

    init(_ pestanya: ClaudePestanya) {
        let c = pestanya.normalitzada()
        activat = c.activat
        model = c.model
        esforc = c.esforc
        ultracode = c.ultracode
        continua = c.continua
        nom = c.nom
        saltaPermisos = c.saltaPermisos
        modePermisos = c.modePermisos
        settings = c.settings
        controlRemot = c.controlRemot
        altres = c.altres.isEmpty ? nil : c.altres
    }

    /// Valors per defecte segurs: el que no hi és, no s'activa (excepte `activat` i `continua`, R4).
    /// La plantilla no omple mai un bloc parcial.
    var valor: ClaudePestanya {
        ClaudePestanya(activat: activat ?? true, model: model, esforc: esforc, ultracode: ultracode ?? false,
                       continua: continua ?? true, nom: nom, saltaPermisos: saltaPermisos ?? false,
                       modePermisos: modePermisos, settings: settings, controlRemot: controlRemot,
                       altres: altres ?? []).normalitzada()
    }
}
