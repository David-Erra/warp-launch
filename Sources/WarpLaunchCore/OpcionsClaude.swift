import Foundation

/// Opcions d'arrencada de Claude Code que interessen a Warp Launch, extretes de l'`argv` d'un procés.
///
/// `analitza` llegeix l'`argv` com `parseOptions` de commander a Claude Code, amb la taula de `TaulaOpcionsClaude`:
/// sap quin argument és el valor d'una opció i quin és el primer missatge (`prompt`), i entén `-cw` (`-c -w`),
/// `-nBotiga` (`-n Botiga`) i `--opcio=valor`. Les opcions que l'app no fa servir van a `altres`, en ordre i amb els
/// seus valors, perquè no es perdin.
public struct OpcionsClaude: Codable, Sendable, Equatable {
    public var model: String?
    /// Esforç tal com s'ha escrit. `ultracode` és un àlies: esforç `xhigh` més ultracode.
    public var esforc: String?
    /// Ultracode actiu: per `--effort ultracode` o per `"ultracode": true` a `--settings`.
    public var ultracode: Bool
    /// Valor de `--settings`, sense interpretar (JSON o ruta). Si es repeteix, Claude només fa servir l'últim.
    public var settings: String?
    /// `-n` / `--name`.
    public var nom: String?
    /// `-r` / `--resume`. Buit (`""`) vol dir sense valor: obre el selector de converses.
    public var repren: String?
    /// `-c` / `--continue`.
    public var continua: Bool
    /// `--dangerously-skip-permissions`.
    public var saltaPermisos: Bool
    /// `--permission-mode`.
    public var modePermisos: String?
    /// `--remote-control` o `--rc`. Buit (`""`) vol dir sense nom.
    public var controlRemot: String?
    /// `--session-id`.
    public var idSessio: String?
    /// Les opcions que l'app no fa servir, amb els seus valors, en ordre i tal com s'han escrit. D'una combinació de
    /// curtes com `-cw`, aquí només hi va la part que no fa servir l'app (`-w`).
    public var altres: [String]
    /// El primer missatge: els arguments que no són de cap opció i tot el que va després de `--`. És de la sessió:
    /// no es desa a la pestanya, perquè s'enviaria de nou a cada obertura.
    public var prompt: [String]
    /// Opcions que no són a la taula de Claude Code (`TaulaOpcionsClaude.versio`). Són a `altres` amb els arguments
    /// que les segueixen, perquè no se sap si en són el valor.
    public var desconegudes: [String]

    public init(model: String? = nil, esforc: String? = nil, ultracode: Bool = false, settings: String? = nil,
                nom: String? = nil, repren: String? = nil, continua: Bool = false, saltaPermisos: Bool = false,
                modePermisos: String? = nil, controlRemot: String? = nil, idSessio: String? = nil,
                altres: [String] = [], prompt: [String] = [], desconegudes: [String] = []) {
        self.model = model
        self.esforc = esforc
        self.ultracode = ultracode
        self.settings = settings
        self.nom = nom
        self.repren = repren
        self.continua = continua
        self.saltaPermisos = saltaPermisos
        self.modePermisos = modePermisos
        self.controlRemot = controlRemot
        self.idSessio = idSessio
        self.altres = altres
        self.prompt = prompt
        self.desconegudes = desconegudes
    }

    /// Les opcions que tenen camp propi aquí (i a `ClaudePestanya`, llevat de `-r` i `--session-id`).
    static let nomsPropis: Set<String> = [
        "--model", "--effort", "--settings", "-n", "--name", "-r", "--resume", "-c", "--continue",
        "--dangerously-skip-permissions", "--permission-mode", "--remote-control", "--rc", "--session-id",
    ]

    /// Analitza l'`argv` complet d'un procés `claude` (el primer element és l'executable), com `parseOptions` de
    /// commander a Claude Code 2.1.318. Si una opció es repeteix, mana l'última, com a commander.
    public static func analitza(_ argv: [String]) -> OpcionsClaude {
        analitzaAmbNoms(argv).opcions
    }

    /// El que diu `analitza`, i a més:
    /// - `noms`: el nom llarg de cada opció de la taula que hi surt, en ordre (`-cw` dona `--continue` i `--worktree`);
    /// - `textosDesconeguts`: els textos que van després d'una opció desconeguda i que no són de cap opció coneguda.
    ///   Commander els posa amb les desconegudes, però si l'opció no en pren cap valor, són el primer missatge.
    struct Analisi {
        var opcions: OpcionsClaude
        var noms: [String]
        var textosDesconeguts: [String]
    }

    static func analitzaAmbNoms(_ argv: [String]) -> Analisi {
        var o = OpcionsClaude()
        var noms: [String] = []
        var textos: [String] = []
        // Pila: l'últim element és el següent argument, i `append` el torna a posar al davant (`unshift`).
        var pila = Array(argv.dropFirst().reversed())
        var variadica = false
        // Després d'una opció desconeguda, commander envia els arguments que no són opcions a les desconegudes.
        var desconegut = false

        while let arg = pila.popLast() {
            if arg == "--" {
                let resta = Array(pila.reversed())
                if desconegut { o.altres += [arg] + resta } else { o.prompt += resta }
                break
            }
            if variadica, !esOpcio(arg) {
                o.altres.append(arg)
                continue
            }
            variadica = false

            if esOpcio(arg), let opcio = TaulaOpcionsClaude.troba(arg) {
                var escrit = [arg]
                var valor: String?
                switch opcio.valor {
                case .cap: break
                case .obligatori: valor = pila.popLast()  // si no n'hi ha, Claude s'atura amb un error
                case .opcional: if let seguent = pila.last, !esOpcio(seguent) { valor = pila.popLast() }
                }
                if let valor { escrit.append(valor) }
                o.aplica(opcio, escrit: escrit, valor: valor)
                noms.append(opcio.noms.last ?? arg)
                variadica = opcio.variadica
                continue
            }

            // `-abc`: una curta seguida del seu valor (`-nBotiga`) o d'altres curtes (`-cw`).
            let escalars = Array(arg.unicodeScalars)
            if arg.utf16.count > 2, escalars[0] == "-", escalars[1] != "-",
               let opcio = TaulaOpcionsClaude.troba("-" + String(escalars[1])) {
                var resta = String.UnicodeScalarView()
                resta.append(contentsOf: escalars.dropFirst(2))
                if opcio.valor == .cap {
                    o.aplica(opcio, escrit: ["-" + String(escalars[1])], valor: nil)
                    pila.append("-" + String(resta))
                } else {
                    o.aplica(opcio, escrit: [arg], valor: String(resta))
                }
                noms.append(opcio.noms.last ?? arg)
                continue
            }

            // `--opcio=valor`, només si l'opció té valor. No activa una variàdica.
            if arg.hasPrefix("--"), let igual = arg.unicodeScalars.firstIndex(of: "="),
               arg.unicodeScalars.distance(from: arg.unicodeScalars.startIndex, to: igual) > 2 {
                let nom = String(arg.unicodeScalars[..<igual])
                if let opcio = TaulaOpcionsClaude.troba(nom), opcio.valor != .cap {
                    o.aplica(opcio, escrit: [arg], valor: String(arg.unicodeScalars[arg.unicodeScalars.index(after: igual)...]))
                    noms.append(opcio.noms.last ?? nom)
                    continue
                }
            }

            if esOpcio(arg) {
                desconegut = true
                o.desconegudes.append(arg)
                o.altres.append(arg)
            } else if desconegut {
                o.altres.append(arg)
                textos.append(arg)
            } else {
                o.prompt.append(arg)
            }
        }

        if o.esforc == "ultracode" { o.ultracode = true }
        if let s = o.settings, SettingsClaude.objecte(s).flatMap(SettingsClaude.ultracode) == true { o.ultracode = true }
        return Analisi(opcions: o, noms: noms, textosDesconeguts: textos)
    }

    /// Com `maybeOption` de commander: més d'un caràcter (en UTF-16, com JavaScript) i comença per «-».
    private static func esOpcio(_ arg: String) -> Bool {
        arg.utf16.count > 1 && arg.hasPrefix("-")
    }

    private mutating func aplica(_ opcio: TaulaOpcionsClaude.Opcio, escrit: [String], valor: String?) {
        switch opcio.noms.last {
        case "--model": model = valor
        case "--effort": esforc = valor
        case "--settings": settings = valor
        case "--name": nom = valor
        case "--resume": repren = valor ?? ""
        case "--continue": continua = true
        case "--dangerously-skip-permissions": saltaPermisos = true
        case "--permission-mode": modePermisos = valor
        case "--remote-control", "--rc": controlRemot = valor ?? ""
        case "--session-id": idSessio = valor
        default: altres += escrit
        }
    }
}

/// Com llegeix Claude Code el valor de `--settings` (2.1.318, `loadSettingsFromFlag` i l'esquema de settings).
enum SettingsClaude {
    /// Els espais que treu `String.prototype.trim` de JavaScript.
    private static let espaisJS = CharacterSet.whitespaces
        .union(CharacterSet(charactersIn: "\n\r\u{0B}\u{0C}\u{FEFF}\u{2028}\u{2029}"))

    /// Sense espais als extrems, comença per `{` i acaba per `}`: és JSON. Si no, és la ruta d'un fitxer (també `[1]`).
    static func esJSON(_ settings: String) -> Bool {
        let net = settings.trimmingCharacters(in: espaisJS)
        return net.hasPrefix("{") && net.hasSuffix("}")
    }

    /// JSON vàlid tal com el llegeix Claude (`JSON.parse` del text sense espais als extrems), amb la gramàtica
    /// estricta: les claus repetides no són cap error, i una coma final sí.
    static func esValid(_ settings: String) -> Bool {
        JSONEstricte.esValid(Array(settings.trimmingCharacters(in: espaisJS).utf8))
    }

    /// L'objecte, o `nil` si no és JSON vàlid per a Claude, té claus repetides (Claude es queda amb l'última i
    /// `JSONSerialization` amb la primera) o té valors que `JSONSerialization` no llegeix (`1e400`, `"\ud800"`):
    /// llavors no se'n pot saber el contingut amb seguretat.
    static func objecte(_ settings: String) -> [String: Any]? {
        guard esJSON(settings) else { return nil }
        let bytes = Array(settings.trimmingCharacters(in: espaisJS).utf8)
        guard JSONEstricte.esValid(bytes), ClausRepetides.primera(bytes) == nil else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any]
    }

    /// `"ultracode"` si és un booleà de debò. Claude no fa cas d'un altre valor (`1`, `"sí"`): és com si no hi fos.
    static func ultracode(_ json: [String: Any]) -> Bool? {
        guard let valor = json["ultracode"] as? NSNumber, CFGetTypeID(valor) == CFBooleanGetTypeID() else { return nil }
        return valor.boolValue
    }
}
