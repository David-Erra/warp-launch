import Foundation

/// L'ordre que obre Claude Code en una pestanya: de `ClaudePestanya` a l'`argv`, i al text que s'escriu a la línia
/// d'ordres (docs/disseny.md, pas 5). **No executa res.**
///
/// Continuar (D7, decisió d'en David del 05/11/2026): una pestanya amb `continua` reprèn la conversa més recent de la seva
/// carpeta (`--resume <id>`), si no és viva ni d'una altra pestanya, i si no n'hi ha cap, en comença una de nova. **Mai
/// `--continue`**, que no mira cap d'aquestes dues coses (D15: tampoc a l'ordre que es mostra i es copia).
///
/// Llegir l'ordre generada (`OpcionsClaude.analitza`, que llegeix com Claude Code, i `ClaudePestanya(_:)`) torna la
/// mateixa configuració si es reprèn una conversa. L'únic que pot canviar és la forma del JSON de `--settings` (claus
/// ordenades), no el contingut. Sense conversa, l'ordre no diu que es continua.
public enum OrdreClaude {
    public enum ErrorOrdre: Error, Equatable, CustomStringConvertible {
        /// Ultracode amb un esforç que no és «Molt alt» s'activa amb `"ultracode": true` dins de `--settings`, i si
        /// `--settings` és un fitxer, l'ordre no el pot canviar.
        case ultracodeAmbSettingsDeFitxer
        /// `--settings` és JSON (comença per `{` i acaba per `}`) però no és vàlid, té claus repetides o valors que
        /// `JSONSerialization` no llegeix (`1e400`), i s'hi hauria d'afegir ultracode.
        case settingsNoEsJSON
        /// `--settings` ja té `"ultracode"` amb un valor que no és booleà: no se sobreescriu sense dir-ho.
        case ultracodeEstranyASettings
        /// `--resume` sense cap sessió: obriria el selector de converses en lloc de continuar.
        case sessioBuida
        /// `altres` porta una opció que té camp propi (l'ordre i els camps dirien coses diferents).
        case opcioPropiaAAltres(String)
        /// `altres` porta un text que no és de cap opció: Claude el prendria pel primer missatge, i l'enviaria a cada
        /// obertura.
        case promptAAltres(String)

        public var description: String {
            switch self {
            case .ultracodeAmbSettingsDeFitxer:
                "ultracode amb un esforç que no és «Molt alt» necessita «--settings» en JSON, i aquí és un fitxer"
            case .settingsNoEsJSON:
                "«--settings» no és un JSON vàlid, té claus repetides o valors que l'app no sap llegir, i s'hi ha d'afegir ultracode"
            case .ultracodeEstranyASettings: "«--settings» ja té «ultracode» amb un valor que no és true ni false"
            case .sessioBuida: "falta la sessió que s'ha de reprendre"
            case let .opcioPropiaAAltres(opcio): "«\(opcio)» és a les altres opcions, però té camp propi"
            case let .promptAAltres(text):
                "les altres opcions porten «\(text)», que Claude prendria pel primer missatge de cada obertura"
            }
        }
    }

    /// L'`argv` (el primer element és `executable`), o `nil` si la pestanya només és un terminal.
    ///
    /// - Parameter repren: la conversa de la pestanya, si se sap (`estat.json`). Només compta si la pestanya diu
    ///   `continua`; sense, l'ordre comença una conversa nova. És explícit a totes les crides: cap no pot oblidar-lo.
    ///
    /// Ordre de les opcions: el de la comanda d'en David (`--dangerously-skip-permissions --effort ultracode`), després
    /// la resta, les que l'app no entén, i `--remote-control` sense nom al final (el seu valor és opcional i, si no,
    /// s'empassaria l'argument següent).
    ///
    /// Amb `--dangerously-skip-permissions`, Claude no fa cas de `--permission-mode` (2.1.318): l'ordre els porta tots
    /// dos, tal com diu la configuració, i l'avís és cosa de la validació.
    public static func argv(_ claude: ClaudePestanya, repren: String?,
                            executable: String = "claude") throws(ErrorOrdre) -> [String]? {
        let c = claude.normalitzada()
        guard c.activat else { return nil }
        try comprova(altres: c.altres, executable: executable)

        var esforc = c.esforc
        var settings = c.settings
        if c.ultracode {
            if c.esforc == "xhigh" {
                esforc = "ultracode"  // l'àlies: xhigh més ultracode, com ho escriu en David
            } else {
                settings = try ambUltracode(settings)
            }
        }

        var argv = [executable]
        if c.saltaPermisos { argv.append("--dangerously-skip-permissions") }
        argv += opcio("--model", c.model)
        argv += opcio("--effort", esforc)
        argv += opcio("--permission-mode", c.modePermisos)
        argv += opcio("--settings", settings)
        argv += opcio("--name", c.nom)
        if c.continua, let sessio = repren {
            guard !sessio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .sessioBuida }
            argv += opcio("--resume", sessio)
        }
        argv += c.altres
        switch c.controlRemot {
        case nil: break
        case ""?: argv.append("--remote-control")
        case let nom?: argv += opcio("--remote-control", nom)
        }
        return argv
    }

    /// El text per a la línia d'ordres (zsh o sh): cometes simples on calen. Tornat a llegir per la shell, dona
    /// exactament el mateix `argv`.
    public static func text(_ argv: [String]) -> String {
        argv.map(Informe.cometes).joined(separator: " ")
    }

    /// La variable que diu de quina pestanya és cada Claude que obre l'app. L'app la llegeix a l'entorn del procés.
    public static let variableMarca = "WARP_LAUNCH_PESTANYA"

    /// La línia que Warp escriurà a la pestanya, com si l'hagués escrit en David (fase 3.1):
    /// - Comença amb un espai (D16): zsh no la desa a l'historial, perquè Warp l'obre amb `HIST_IGNORE_SPACE`
    ///   (per comprovar a la prova L2).
    /// - `WARP_LAUNCH_PESTANYA=<id de la pestanya>` al davant, només per a aquesta ordre: mai `export`, que quedaria a
    ///   la shell i passaria a tot el que s'hi obrís després.
    /// - `CLAUDE_ENV_FILE=<entorn>`, si se'n passa un (`EntornClaude`), també només per a aquesta ordre. El fitxer la treu de
    ///   tot el que engegui Claude des de Bash.
    public static func liniaExec(_ argv: [String], pestanya: UUID, entorn: String? = nil) -> String {
        let variable = entorn.map { "\(EntornClaude.variable)=\(Informe.cometes($0)) " } ?? ""
        return " \(variableMarca)=\(pestanya.uuidString) \(variable)" + text(argv)
    }

    /// `altres` només pot portar opcions senceres que l'app no fa servir: així, posar-les després dels camps no canvia
    /// com les llegeix Claude. La importació no en genera d'altres; això atura un JSON editat a mà.
    static func comprova(altres: [String], executable: String) throws(ErrorOrdre) {
        guard !altres.isEmpty else { return }
        // Tot el que va després de `--` és el primer missatge, i `--remote-control` també hi aniria a parar.
        if altres.contains("--") { throw .promptAAltres("--") }
        let llegides = OpcionsClaude.analitza([executable] + altres)
        if let text = llegides.prompt.first { throw .promptAAltres(text) }
        let soles = OpcionsClaude(altres: llegides.altres, desconegudes: llegides.desconegudes)
        guard llegides == soles, llegides.altres == altres else {
            let propia = altres.first { arg in
                OpcionsClaude.nomsPropis.contains(arg)
                    || OpcionsClaude.nomsPropis.contains(String(arg.prefix { $0 != "=" }))
            }
            throw .opcioPropiaAAltres(propia ?? altres.first { $0 == "--" } ?? altres[0])
        }
    }

    /// `--opcio valor`, o `--opcio=valor` si el valor comença per `-` (si no, es llegiria com una altra opció).
    private static func opcio(_ nom: String, _ valor: String?) -> [String] {
        guard let valor else { return [] }
        return valor.hasPrefix("-") ? ["\(nom)=\(valor)"] : [nom, valor]
    }

    /// `--settings` amb `"ultracode": true` afegit. Sense settings, només aquesta clau.
    static func ambUltracode(_ settings: String?) throws(ErrorOrdre) -> String {
        var json: [String: Any] = [:]
        if let settings {
            guard SettingsClaude.esJSON(settings) else { throw .ultracodeAmbSettingsDeFitxer }
            guard let objecte = SettingsClaude.objecte(settings) else { throw .settingsNoEsJSON }
            // Els booleans ja els ha tret `normalitzada`; un altre valor no es trepitja.
            guard objecte["ultracode"] == nil else { throw .ultracodeEstranyASettings }
            json = objecte
        }
        json["ultracode"] = true
        guard let dades = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
        else { throw .settingsNoEsJSON }
        return String(decoding: dades, as: UTF8.self)
    }
}

extension ClaudePestanya {
    /// La configuració d'una pestanya a partir de les opcions d'una ordre de Claude, en forma canònica. No hi van
    /// les coses de la sessió: `-c` i `-r` només diuen que es continua, i la sessió de `-r`, `--session-id` i el primer
    /// missatge (`prompt`) no es desen. La importació ho ha de dir (pas 6).
    public init(_ opcions: OpcionsClaude) {
        self.init(activat: true, model: opcions.model, esforc: opcions.esforc, ultracode: opcions.ultracode,
                  continua: opcions.continua || opcions.repren != nil, nom: opcions.nom,
                  saltaPermisos: opcions.saltaPermisos, modePermisos: opcions.modePermisos,
                  settings: opcions.settings, controlRemot: opcions.controlRemot, altres: opcions.altres)
        self = normalitzada()
    }
}

extension OrdreClaude {
    /// L'ordre tal com la mostra l'inspector i com es copia: `nil` si la pestanya només és un terminal.
    public static func text(de claude: ClaudePestanya, repren: String?) -> Result<String?, ErrorOrdre> {
        do {
            return .success(try argv(claude, repren: repren).map(text))
        } catch {
            return .failure(error)
        }
    }
}
