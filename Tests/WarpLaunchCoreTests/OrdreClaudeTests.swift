import Foundation
import Testing
@testable import WarpLaunchCore

// L'ordre de Claude (docs/disseny.md, pas 5): de la configuració a l'argv i al text. Llegir l'ordre generada ha de
// tornar la mateixa configuració. No s'executa mai `claude`: només zsh i sh, per veure com parteixen el text.

/// La configuració que es llegeix d'una ordre, com faria la importació.
private func llegida(_ argv: [String]) -> ClaudePestanya {
    ClaudePestanya(OpcionsClaude.analitza(argv))
}

/// La configuració que ha de tornar l'ordre: sense conversa per reprendre, l'ordre no diu que es continua (D7).
private func esperada(_ c: ClaudePestanya, repren: String?) -> ClaudePestanya {
    var c = c.normalitzada()
    if repren == nil { c.continua = false }
    return c
}

private func objecteJSON(_ text: String) -> NSDictionary? {
    guard let dades = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: dades)) as? NSDictionary
}

/// Iguals, amb el JSON de `--settings` comparat pel contingut i no per la forma (pot sortir amb les claus ordenades).
private func mateixa(_ a: ClaudePestanya, _ b: ClaudePestanya) -> Bool {
    var a = a, b = b
    if let sa = a.settings.flatMap(objecteJSON), let sb = b.settings.flatMap(objecteJSON), sa == sb {
        a.settings = nil
        b.settings = nil
    }
    return a == b
}

/// Què és cada valor de `--settings` de les proves per a Claude Code, escrit a mà (no calculat amb el codi que es
/// prova): JSON si, sense espais als extrems, comença per `{` i acaba per `}`; si no, un fitxer.
private enum Settings { case cap, json, jsonQueActivaUltracode, fitxer, malmes, ultracodeNoBoolea }

private let settingsDeProva: [(text: String?, tipus: Settings)] = [
    (nil, .cap),
    (" ", .cap),
    (#"{"model":"x"}"#, .json),
    (#"{ "env": {"A": "1"}, "permissions": {"allow": ["Bash(git:*)"]} }"#, .json),
    (#"{"ultracode":true}"#, .jsonQueActivaUltracode),
    (#"{"ultracode":true,"a":[1]}"#, .jsonQueActivaUltracode),
    (#"{"ultracode":false,"a":1}"#, .json),
    (#"{"ultracode":"sí"}"#, .ultracodeNoBoolea),
    (#"{"ultracode":1}"#, .ultracodeNoBoolea),
    ("/Users/prova/.claude/s.json", .fitxer),
    ("~/s.json", .fitxer),
    ("-raro.json", .fitxer),
    ("{malmès", .fitxer),
    ("[1]", .fitxer),
    ("{malmès}", .malmes),
    (#"{"a":1,"a":2}"#, .malmes),
]

/// Les altres opcions de les proves, amb l'error que han de donar, escrit a mà.
private let altresDeProva: [(altres: [String], error: OrdreClaude.ErrorOrdre?)] = [
    ([], nil),
    (["--verbose"], nil),
    (["--add-dir", "/a b", "/c"], nil),
    (["-w"], nil),
    (["--nova-opcio", "valor"], nil),  // desconeguda: es deixa com és
    (["hola"], .promptAAltres("hola")),
    (["--verbose", "--", "x"], .promptAAltres("--")),
    (["--model", "x"], .opcioPropiaAAltres("--model")),
    (["--effort=max"], .opcioPropiaAAltres("--effort=max")),
    (["-cw"], .opcioPropiaAAltres("-cw")),
]

/// L'error que s'espera. Ordre: les altres opcions, `--settings` i la sessió.
private func errorEsperat(esforc: String?, ultracode: Bool, settings: Settings, continua: Bool,
                          represa: String?, altres: OrdreClaude.ErrorOrdre?) -> OrdreClaude.ErrorOrdre? {
    if let altres { return altres }
    let esforcNet = esforc?.lowercased()
    let ambUltracode = ultracode || esforcNet == "ultracode" || settings == .jsonQueActivaUltracode
    let molAlt = esforcNet == "xhigh" || esforcNet == "ultracode"
    if ambUltracode, !molAlt {
        switch settings {
        case .fitxer: return .ultracodeAmbSettingsDeFitxer
        case .malmes: return .settingsNoEsJSON
        case .ultracodeNoBoolea: return .ultracodeEstranyASettings
        case .cap, .json, .jsonQueActivaUltracode: break
        }
    }
    if continua, let s = represa, s.trimmingCharacters(in: .whitespaces).isEmpty { return .sessioBuida }
    return nil
}

@Suite struct OrdreClaudeTests {
    // MARK: La comanda habitual

    @Test func laComandaHabitual() throws {
        // Unes sessions porten `--continue` i altres no (03/11/2026). Es llegeix igual, però l'app no
        // el torna a escriure (D7): reprèn la conversa de la pestanya, o en comença una de nova.
        let ambContinua = ["claude", "--dangerously-skip-permissions", "--effort", "ultracode", "--continue"]
        #expect(llegida(ambContinua) == .habituals)
        let nova = Array(ambContinua.dropLast())
        #expect(try OrdreClaude.argv(.habituals, repren: nil) == nova)
        #expect(OrdreClaude.text(try #require(try OrdreClaude.argv(.habituals, repren: nil)))
            == "claude --dangerously-skip-permissions --effort ultracode")
        let id = "1f0c2d3e-0000-4000-8000-000000000001"
        #expect(try OrdreClaude.argv(.habituals, repren: id) == nova + ["--resume", id])
        #expect(llegida(nova + ["--resume", id]) == .habituals)

        var sense = ClaudePestanya.habituals
        sense.continua = false
        #expect(llegida(nova) == sense)
        #expect(try OrdreClaude.argv(sense, repren: id) == nova, "sense continuar, la conversa no compta")
    }

    /// D7 i D15: cap combinació dona `--continue` ni `-c`, ni amb conversa ni sense.
    @Test func maiContinue() throws {
        for c in [ClaudePestanya.habituals, .perOmissio, ClaudePestanya(continua: true, altres: ["--verbose"])] {
            for repren in [nil, "id-1"] as [String?] {
                let argv = try #require(try OrdreClaude.argv(c, repren: repren))
                #expect(!argv.contains("--continue") && !argv.contains("-c"), "\(argv)")
            }
        }
    }

    @Test func nomesTerminalNoTeOrdre() throws {
        #expect(try OrdreClaude.argv(.nomesTerminal, repren: nil) == nil)
        #expect(try OrdreClaude.argv(ClaudePestanya(activat: false, ultracode: true, settings: "/x.json"), repren: nil) == nil)
    }

    @Test func perOmissioNoSaltaPermisos() throws {
        #expect(try OrdreClaude.argv(.perOmissio, repren: nil) == ["claude"])
    }

    // MARK: Esforç, ultracode i settings

    @Test func ultracodeAmbUnAltreEsforcVaDinsDeSettings() throws {
        #expect(try OrdreClaude.argv(ClaudePestanya(esforc: "high", ultracode: true, continua: false), repren: nil)
            == ["claude", "--effort", "high", "--settings", #"{"ultracode":true}"#])
        #expect(try OrdreClaude.argv(ClaudePestanya(ultracode: true, continua: false), repren: nil)
            == ["claude", "--settings", #"{"ultracode":true}"#])
        // S'afegeix al JSON que ja hi havia.
        #expect(try OrdreClaude.argv(ClaudePestanya(esforc: "max", ultracode: true, continua: false,
                                                    settings: #"{"env": {"A": "1"}}"#), repren: nil)
            == ["claude", "--effort", "max", "--settings", #"{"env":{"A":"1"},"ultracode":true}"#])
        // Amb «Molt alt», l'àlies, i el fitxer de settings es deixa com és.
        #expect(try OrdreClaude.argv(ClaudePestanya(esforc: "xhigh", ultracode: true, continua: false,
                                                    settings: "/Users/prova/s.json"), repren: nil)
            == ["claude", "--effort", "ultracode", "--settings", "/Users/prova/s.json"])
    }

    @Test func ultracodeAmbUnFitxerDeSettingsNoEsPotGenerar() {
        #expect(throws: OrdreClaude.ErrorOrdre.ultracodeAmbSettingsDeFitxer) {
            try OrdreClaude.argv(ClaudePestanya(esforc: "high", ultracode: true, settings: "~/s.json"), repren: nil)
        }
        // Per a Claude, «{malmès» i «[1, 2]» són rutes de fitxer: només és JSON el que va de «{» a «}».
        #expect(throws: OrdreClaude.ErrorOrdre.ultracodeAmbSettingsDeFitxer) {
            try OrdreClaude.argv(ClaudePestanya(esforc: "high", ultracode: true, settings: "{malmès"), repren: nil)
        }
        #expect(throws: OrdreClaude.ErrorOrdre.ultracodeAmbSettingsDeFitxer) {
            try OrdreClaude.argv(ClaudePestanya(ultracode: true, settings: "[1, 2]"), repren: nil)
        }
        #expect(throws: OrdreClaude.ErrorOrdre.settingsNoEsJSON) {
            try OrdreClaude.argv(ClaudePestanya(esforc: "high", ultracode: true, settings: "{malmès}"), repren: nil)
        }
        #expect(throws: OrdreClaude.ErrorOrdre.settingsNoEsJSON) {
            try OrdreClaude.argv(ClaudePestanya(ultracode: true, settings: #"{"a":1,"a":2}"#), repren: nil)
        }
        #expect(throws: OrdreClaude.ErrorOrdre.ultracodeEstranyASettings) {
            try OrdreClaude.argv(ClaudePestanya(ultracode: true, settings: #"{"ultracode":"sí"}"#), repren: nil)
        }
    }

    @Test func unUltracodeFalsExplicitArribaAClaude() throws {
        // Apaga l'ultracode de la configuració de Claude de l'usuari: l'ordre l'ha de mantenir.
        let original = ["claude", "--effort", "high", "--settings", #"{"ultracode":false}"#]
        #expect(try OrdreClaude.argv(llegida(original), repren: nil) == original)
    }

    /// Cada combinació d'esforç, ultracode, `--settings` i manera de continuar: o l'ordre es llegeix i torna la
    /// mateixa configuració, o dona l'error que toca.
    @Test func totesLesCombinacionsEsLlegeixenIgual() throws {
        let esforcos: [String?] = [nil, "low", "medium", "high", "xhigh", "max", "ultracode", "XHigh", "turbo"]
        let represes: [String?] = [nil, "1f0c2d3e-0000-4000-8000-000000000001", "-nom raro", "", " "]
        var casos = 0, errors = 0
        for esforc in esforcos {
            for (s, tipus) in settingsDeProva {
                for ultracode in [false, true] {
                    for continua in [false, true] {
                        for represa in represes {
                            let c = ClaudePestanya(esforc: esforc, ultracode: ultracode, continua: continua,
                                                   saltaPermisos: true, settings: s)
                            casos += 1
                            if let esperat = errorEsperat(esforc: esforc, ultracode: ultracode, settings: tipus,
                                                          continua: continua, represa: represa, altres: nil) {
                                errors += 1
                                #expect(throws: esperat, "\(c) \(String(describing: represa))") {
                                    try OrdreClaude.argv(c, repren: represa)
                                }
                                continue
                            }
                            let argv = try #require(try OrdreClaude.argv(c, repren: represa))
                            #expect(!argv.contains("--continue") && !argv.contains("-c"), "\(argv)")
                            let tornada = llegida(argv)
                            #expect(mateixa(tornada, esperada(c, repren: represa)), "\(c) → \(argv) → \(tornada)")
                        }
                    }
                }
            }
        }
        #expect(casos == 9 * 16 * 2 * 2 * 5)
        #expect(errors > 0 && errors < casos / 2)
    }

    // MARK: La resta d'opcions

    @Test func continuarAmbUnaSessioConcreta() throws {
        let c = ClaudePestanya(esforc: "high")
        #expect(try OrdreClaude.argv(c, repren: "1f0c2d3e") == ["claude", "--effort", "high", "--resume", "1f0c2d3e"])
        // Un valor que comença per «-» es llegiria com una opció.
        #expect(try OrdreClaude.argv(c, repren: "-x") == ["claude", "--effort", "high", "--resume=-x"])
        // Sense conversa coneguda, una de nova.
        #expect(try OrdreClaude.argv(c, repren: nil) == ["claude", "--effort", "high"])
        // Si la pestanya no continua, la sessió no hi és.
        var nova = c
        nova.continua = false
        #expect(try OrdreClaude.argv(nova, repren: "1f0c2d3e") == ["claude", "--effort", "high"])
    }

    @Test func controlRemotSenseNomVaAlFinal() throws {
        // Amb `--remote-control` abans d'un altre argument, Claude prendria aquest argument pel nom.
        let c = ClaudePestanya(continua: false, controlRemot: "", altres: ["--add-dir", "/x"])
        let argv = try #require(try OrdreClaude.argv(c, repren: nil))
        #expect(argv == ["claude", "--add-dir", "/x", "--remote-control"])
        #expect(llegida(argv) == c.normalitzada())
    }

    @Test(arguments: [
        ClaudePestanya(model: "opus", continua: false),
        ClaudePestanya(model: "claude-opus-5-5", nom: "Gestor de sessions", modePermisos: "plan"),
        ClaudePestanya(nom: "l'agent «Gestió»", controlRemot: "Agent web"),
        ClaudePestanya(model: "-raro", nom: "-guió", modePermisos: "-x", controlRemot: "-y"),
        ClaudePestanya(saltaPermisos: true, controlRemot: "", altres: ["--verbose", "--add-dir", "/a b"]),
        ClaudePestanya(esforc: "XHIGH", ultracode: false, settings: " "),
        ClaudePestanya(saltaPermisos: true, altres: ["-w", "--add-dir", "/a", "/b", "--debug"]),
        ClaudePestanya(controlRemot: "", altres: ["--nova-opcio", "valor"]),
    ])
    func laRestaDOpcionsEsLlegeixIgual(c: ClaudePestanya) throws {
        // Amb una conversa per reprendre: així l'ordre també diu si la pestanya continua.
        let argv = try #require(try OrdreClaude.argv(c, repren: "1f0c2d3e"))
        #expect(llegida(argv) == c.normalitzada(), "\(argv)")
    }

    /// Moltes configuracions a l'atzar (amb llavor fixa): les opcions no s'interfereixen.
    @Test func configuracionsALAtzar() throws {
        var llavor: UInt64 = 0x5EED_2026_1104
        func tria<T>(_ opcions: [T]) -> T {
            llavor = llavor &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return opcions[Int((llavor >> 33) % UInt64(opcions.count))]
        }
        var generades = 0, errors = 0
        for _ in 0..<5000 {
            let (s, tipus) = tria(settingsDeProva)
            let (altres, errorAltres) = tria(altresDeProva)
            let c = ClaudePestanya(
                activat: tria([true, true, true, false]),
                model: tria([nil, "opus", "fable", "-m", " "]),
                esforc: tria([nil, "low", "xhigh", "max", "ultracode"]),
                ultracode: tria([false, true]),
                continua: tria([false, true]),
                nom: tria([nil, "", " ", "Botiga", "l'agent", "-n"]),
                saltaPermisos: tria([false, true]),
                modePermisos: tria([nil, "plan", "acceptEdits"]),
                settings: s,
                controlRemot: tria([nil, "", "Agent web", "-r"]),
                altres: altres)
            let represa = tria([nil, "id-1", "-id", ""] as [String?])
            let esperat = c.activat ? errorEsperat(esforc: c.esforc, ultracode: c.ultracode, settings: tipus,
                                                   continua: c.continua, represa: represa, altres: errorAltres) : nil
            if let esperat {
                errors += 1
                #expect(throws: esperat, "\(c) \(String(describing: represa))") { try OrdreClaude.argv(c, repren: represa) }
            } else if let argv = try OrdreClaude.argv(c, repren: represa) {
                generades += 1
                #expect(!argv.contains("--continue"), "\(argv)")
                #expect(mateixa(llegida(argv), esperada(c, repren: represa)), "\(c) → \(argv)")
            } else {
                #expect(!c.activat)
            }
        }
        #expect(generades > 1000 && errors > 300, "\(generades) generades, \(errors) errors")
    }

    // MARK: Permisos i altres opcions

    @Test func ambSaltaPermisosElModeNoFaRes() throws {
        // Claude 2.1.318 no fa cas de `--permission-mode` si hi ha `--dangerously-skip-permissions`. L'ordre porta
        // el que diu la configuració, i ho ha d'avisar la validació (pas 6).
        var c = ClaudePestanya.habituals
        c.modePermisos = "plan"
        #expect(try OrdreClaude.argv(c, repren: nil)
            == ["claude", "--dangerously-skip-permissions", "--effort", "ultracode", "--permission-mode", "plan"])
    }

    @Test func elPrimerMissatgeNoEsDesa() throws {
        // Una sessió oberta amb un missatge: la pestanya no el guarda, i l'ordre no el torna a enviar.
        let original = ["claude", "--dangerously-skip-permissions", "--effort", "ultracode", "--continue", "fes el pas 5"]
        #expect(llegida(original) == .habituals)
        #expect(try OrdreClaude.argv(llegida(original), repren: nil) == Array(original.dropLast(2)))
        // Tampoc el que va després de `--`.
        #expect(llegida(["claude", "-c", "--", "--model", "x"]) == ClaudePestanya(continua: true))
    }

    @Test func lesAltresNomesPodenSerOpcionsSenceres() {
        for (altres, error) in altresDeProva {
            let c = ClaudePestanya(altres: altres)
            if let error {
                #expect(throws: error, "\(altres)") { try OrdreClaude.argv(c, repren: nil) }
            } else {
                #expect(throws: Never.self, "\(altres)") { try OrdreClaude.argv(c, repren: nil) }
            }
        }
    }

    // MARK: El text per a la línia d'ordres

    @Test func elTextEsLlegeixIgualAZshIASh() throws {
        // Tot el que una shell podria interpretar: cometes, variables, ordres, comodins, expansions de zsh.
        let argv = ["claude", "--name", "l'agent \"Gestió\"", "--settings", #"{"a":"$HOME `true` $(true)"}"#,
                    "--model", "=ls", "--add-dir", "~/x", "*", "?", "[a]", "{a,b}", "!!", "#x", "^x", "%1",
                    "a b\tc\nd", "\\", "", "=", "a=b", "--opcio=~/y", "àèìòù·ç", "-"]
        let text = OrdreClaude.text(argv)
        for shell in ["/bin/zsh", "/bin/sh"] {
            #expect(try argvSegons(shell, text) == argv, "\(shell): \(text)")
        }
    }

    @Test func elTextDeLaComandaHabitual() throws {
        let argv = try #require(try OrdreClaude.argv(ClaudePestanya(esforc: "high", ultracode: true, nom: "Botiga"), repren: nil))
        #expect(OrdreClaude.text(argv) == #"claude --effort high --settings '{"ultracode":true}' --name Botiga"#)
        #expect(try argvSegons("/bin/zsh", OrdreClaude.text(argv)) == argv)
    }
}

@Suite struct TextOrdreTests {
    /// El que mostra l'inspector: l'ordre, «només terminal» (`nil`) o per què no es pot generar.
    @Test func elTextDeLOrdre() {
        #expect(OrdreClaude.text(de: .habituals, repren: nil) == .success("claude --dangerously-skip-permissions --effort ultracode"))
        #expect(OrdreClaude.text(de: .habituals, repren: "1f0c2d3e")
            == .success("claude --dangerously-skip-permissions --effort ultracode --resume 1f0c2d3e"))
        #expect(OrdreClaude.text(de: .nomesTerminal, repren: "1f0c2d3e") == .success(nil))
        let fitxer = ClaudePestanya(esforc: "high", ultracode: true, settings: "/Users/prova/settings.json")
        #expect(OrdreClaude.text(de: fitxer, repren: nil) == .failure(.ultracodeAmbSettingsDeFitxer))
    }
}
