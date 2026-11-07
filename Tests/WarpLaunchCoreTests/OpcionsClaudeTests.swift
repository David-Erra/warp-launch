import Testing
@testable import WarpLaunchCore

@Suite("Opcions de Claude a partir de l'argv")
struct OpcionsClaudeTests {
    @Test func laComandaHabitualDenDavid() {
        let o = OpcionsClaude.analitza(["claude", "--dangerously-skip-permissions", "--effort", "ultracode"])
        #expect(o == OpcionsClaude(esforc: "ultracode", ultracode: true, saltaPermisos: true))
    }

    @Test func ultracodeIndependentDeLEsforcAmbSettings() {
        let o = OpcionsClaude.analitza(["claude", "--effort", "high", "--settings", #"{"ultracode":true}"#])
        #expect(o.esforc == "high")
        #expect(o.ultracode)
        #expect(o.settings == #"{"ultracode":true}"#)
    }

    @Test func settingsSenseUltracodeORutaNoLActiven() {
        #expect(!OpcionsClaude.analitza(["claude", "--settings", #"{"ultracode":false}"#]).ultracode)
        #expect(!OpcionsClaude.analitza(["claude", "--settings", "/tmp/settings.json"]).ultracode)
        #expect(!OpcionsClaude.analitza(["claude", "--settings", "{trencat"]).ultracode)
    }

    @Test func formaAmbIgual() {
        let o = OpcionsClaude.analitza(["claude", "--model=opus", "--effort=max", "--name=agent-x", "--resume=abc"])
        #expect(o == OpcionsClaude(model: "opus", esforc: "max", nom: "agent-x", repren: "abc"))
    }

    @Test func nomCurtIContinuar() {
        let o = OpcionsClaude.analitza(["claude", "-c", "-n", "warp-launch-prova", "--model", "fable"])
        #expect(o == OpcionsClaude(model: "fable", nom: "warp-launch-prova", continua: true))
    }

    @Test func reprendreAmbISenseValor() {
        #expect(OpcionsClaude.analitza(["claude", "--resume", "1234-abcd"]).repren == "1234-abcd")
        #expect(OpcionsClaude.analitza(["claude", "-r", "nom-fix"]).repren == "nom-fix")
        // Sense valor obre el selector: es desa buit, i l'opció següent no es confon amb el valor.
        let o = OpcionsClaude.analitza(["claude", "--resume", "--effort", "high"])
        #expect(o.repren == "")
        #expect(o.esforc == "high")
    }

    @Test func controlRemotAmbNomAmbEspais() {
        let o = OpcionsClaude.analitza(["claude", "--dangerously-skip-permissions", "--remote-control", "Agent web"])
        #expect(o.controlRemot == "Agent web")
        #expect(o.saltaPermisos)
        #expect(OpcionsClaude.analitza(["claude", "--remote-control"]).controlRemot == "")
    }

    @Test func opcionsDesconegudesNoEsPerden() {
        let o = OpcionsClaude.analitza(["claude", "--add-dir", "/tmp/a", "--verbose", "--permission-mode", "plan",
                                        "--session-id", "0000-1111"])
        #expect(o.altres == ["--add-dir", "/tmp/a", "--verbose"])
        #expect(o.modePermisos == "plan")
        #expect(o.idSessio == "0000-1111")
    }

    @Test func opcioSenseValorAlFinal() {
        let o = OpcionsClaude.analitza(["claude", "--model"])
        #expect(o.model == nil)
        #expect(o.altres.isEmpty)
    }

    // MARK: Com commander (Claude Code 2.1.318)

    @Test func elPrimerMissatgeNoEsCapOpcio() {
        let o = OpcionsClaude.analitza(["claude", "--dangerously-skip-permissions", "--continue", "fes el pas 5"])
        #expect(o == OpcionsClaude(continua: true, saltaPermisos: true, prompt: ["fes el pas 5"]))
        // Després de `--`, tot és el missatge, també el que sembla una opció.
        let d = OpcionsClaude.analitza(["claude", "-c", "--", "--model", "x", "-n"])
        #expect(d == OpcionsClaude(continua: true, prompt: ["--model", "x", "-n"]))
        // «-» sol no és cap opció.
        #expect(OpcionsClaude.analitza(["claude", "-"]).prompt == ["-"])
    }

    @Test func unaVariadicaSEmpassaElQueNoComencaPerGuio() {
        // `--add-dir <directories...>`: «revisa» és una carpeta, no el missatge.
        let o = OpcionsClaude.analitza(["claude", "--add-dir", "../lib", "revisa", "--verbose", "hola"])
        #expect(o.altres == ["--add-dir", "../lib", "revisa", "--verbose"])
        #expect(o.prompt == ["hola"])
        // Amb «=», no: el següent ja és el missatge.
        let igual = OpcionsClaude.analitza(["claude", "--add-dir=../lib", "revisa"])
        #expect(igual.altres == ["--add-dir=../lib"])
        #expect(igual.prompt == ["revisa"])
    }

    @Test func unValorOpcionalNoEsPrenSiComencaPerGuio() {
        // `-w, --worktree [name]` i `-d, --debug [filter]`.
        #expect(OpcionsClaude.analitza(["claude", "-w", "branca", "x"]).altres == ["-w", "branca"])
        let o = OpcionsClaude.analitza(["claude", "--debug", "--effort", "high", "revisa"])
        #expect(o.altres == ["--debug"])
        #expect(o.esforc == "high")
        #expect(o.prompt == ["revisa"])
        // Un valor obligatori es pren sempre, encara que comenci per «-».
        #expect(OpcionsClaude.analitza(["claude", "--model", "-raro"]).model == "-raro")
        #expect(OpcionsClaude.analitza(["claude", "--system-prompt", "-x"]).altres == ["--system-prompt", "-x"])
    }

    @Test func curtesCombinades() {
        #expect(OpcionsClaude.analitza(["claude", "-cw"]) == OpcionsClaude(continua: true, altres: ["-w"]))
        #expect(OpcionsClaude.analitza(["claude", "-nBotiga"]).nom == "Botiga")
        #expect(OpcionsClaude.analitza(["claude", "-cnBotiga"]) == OpcionsClaude(nom: "Botiga", continua: true))
        #expect(OpcionsClaude.analitza(["claude", "-rabc"]).repren == "abc")
        #expect(OpcionsClaude.analitza(["claude", "-wnom"]).altres == ["-wnom"])
        // `-d2e` és una opció sencera (`--debug-to-stderr`), no `-d` amb el valor «2e».
        #expect(OpcionsClaude.analitza(["claude", "-d2e"]).altres == ["-d2e"])
    }

    @Test func formaAmbIgualNomesPerOpcionsAmbValor() {
        // `--continue` no té valor: «--continue=sí» és desconeguda, i Claude s'aturaria.
        let o = OpcionsClaude.analitza(["claude", "--continue=sí", "hola"])
        #expect(!o.continua)
        #expect(o.desconegudes == ["--continue=sí"])
        #expect(o.altres == ["--continue=sí", "hola"])
        #expect(o.prompt.isEmpty)
        #expect(OpcionsClaude.analitza(["claude", "--remote-control=Agent"]).controlRemot == "Agent")
        #expect(OpcionsClaude.analitza(["claude", "--rc"]).controlRemot == "")
    }

    @Test func unaOpcioDesconegudaNoEsConfonAmbElMissatge() {
        // Pot ser d'una versió de Claude més nova: no se sap si «valor» n'és el valor.
        let o = OpcionsClaude.analitza(["claude", "--nova", "valor", "--effort", "max", "més"])
        #expect(o.desconegudes == ["--nova"])
        #expect(o.altres == ["--nova", "valor", "més"])
        #expect(o.esforc == "max")
        #expect(o.prompt.isEmpty)
    }

    @Test func manaLUltimSettings() {
        // Claude només fa servir l'últim `--settings`.
        let o = OpcionsClaude.analitza(["claude", "--settings", #"{"ultracode":true}"#, "--settings", #"{"a":1}"#])
        #expect(o.settings == #"{"a":1}"#)
        #expect(!o.ultracode)
        #expect(OpcionsClaude.analitza(["claude", "--settings", "/s.json", "--settings", #"{"ultracode":true}"#]).ultracode)
    }

    @Test(arguments: [
        (#"{"ultracode":true}"#, true),
        ("  {\"ultracode\": true}\n", true),
        (#"{"ultracode":1}"#, false),          // Claude només en fa cas si és un booleà
        (#"{"ultracode":"true"}"#, false),
        (#"{"ultracode":false,"ultracode":true}"#, false),  // claus repetides: no se sap
        (#"[{"ultracode":true}]"#, false),     // no acaba per «}»: és un fitxer
        (#"{"ultracode":true}x"#, false),
    ])
    func ultracodeNomesSiEsUnBoolea(settings: String, actiu: Bool) {
        #expect(OpcionsClaude.analitza(["claude", "--settings", settings]).ultracode == actiu)
    }

    @Test func settingsJSONComClaude() {
        #expect(SettingsClaude.esJSON(#" {"a":1} "#))
        #expect(SettingsClaude.esJSON("{malmès}"))
        #expect(!SettingsClaude.esJSON("{malmès"))
        #expect(!SettingsClaude.esJSON("[1, 2]"))
        #expect(!SettingsClaude.esJSON("~/s.json"))
        #expect(SettingsClaude.objecte("{malmès}") == nil)
    }
}

@Suite("Taula d'opcions de Claude Code")
struct TaulaOpcionsClaudeTests {
    @Test func totesLesDefinicionsDelBinari() {
        #expect(TaulaOpcionsClaude.definicions.count == 132)
        let noms = TaulaOpcionsClaude.opcions.flatMap(\.noms)
        #expect(Set(noms).count == noms.count, "noms repetits")
        #expect(noms.allSatisfy { $0.hasPrefix("-") && !$0.contains(" ") })
    }

    @Test(arguments: [
        ("-c", TaulaOpcionsClaude.Valor.cap, false),
        ("--continue", .cap, false),
        ("--dangerously-skip-permissions", .cap, false),
        ("--effort", .obligatori, false),
        ("--resume-session-at", .obligatori, false),
        ("-r", .opcional, false),
        ("--remote-control", .opcional, false),
        ("--rc", .opcional, false),
        ("--add-dir", .obligatori, true),
        ("--allowedTools", .obligatori, true),
        ("--allowed-tools", .obligatori, true),
        ("--bg", .cap, false),
        ("--background", .cap, false),
        ("-d2e", .cap, false),
        ("-v", .cap, false),
    ])
    func aritats(nom: String, valor: TaulaOpcionsClaude.Valor, variadica: Bool) throws {
        let opcio = try #require(TaulaOpcionsClaude.troba(nom))
        #expect(opcio.valor == valor)
        #expect(opcio.variadica == variadica)
    }

    @Test func lAjudaNoHiEs() {
        #expect(TaulaOpcionsClaude.troba("-h") == nil)
        #expect(TaulaOpcionsClaude.troba("--help") == nil)
    }
}
