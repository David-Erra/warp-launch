import Foundation
import Testing
@testable import WarpLaunchCore

// Avisos (docs/disseny.md, «Avisos»). Les carpetes que existeixen les diu una llista: cap prova mira el disc.

private let inici = "/Users/prova"
private let existents: Set<String> = ["/Users/prova/GitHub/botiga"]

private func avisos(_ claude: ClaudePestanya, carpeta: String = "/Users/prova/GitHub/botiga") -> [Avis.Tipus] {
    Validacio.avisos(Pestanya(id: uuid(1), titol: "Botiga", carpeta: carpeta, claude: claude), inici: inici,
                     carpetaExisteix: existents.contains).map(\.tipus)
}

@Suite struct ValidacioTests {
    @Test func laComandaHabitualNomesPortaLAvisDUltracode() {
        #expect(avisos(.habituals) == [.ultracode])
        #expect(Avis(.ultracode).gravetat == .info)
        #expect(avisos(.perOmissio) == [])
    }

    /// La plantilla: els mateixos avisos de Claude que una pestanya a una carpeta bona; amb Claude apagat, cap.
    @Test func laPlantilla() {
        let casos: [ClaudePestanya] = [
            .habituals, .perOmissio, ClaudePestanya(modePermisos: "yolo"),
            ClaudePestanya(saltaPermisos: true, modePermisos: "plan"), ClaudePestanya(esforc: "extrem"),
            ClaudePestanya(settings: "{malmès"), ClaudePestanya(altres: ["--worktree"]),
            ClaudePestanya(esforc: "high", ultracode: true, settings: "/Users/prova/s.json"),
        ]
        for claude in casos {
            #expect(Validacio.avisos(plantilla: claude).map(\.tipus) == avisos(claude), "\(claude)")
        }
        #expect(Validacio.avisos(plantilla: .habituals).map(\.tipus) == [.ultracode])
        var apagada = ClaudePestanya(modePermisos: "yolo")
        apagada.activat = false
        #expect(Validacio.avisos(plantilla: apagada).isEmpty)
    }

    @Test func laCarpeta() {
        #expect(avisos(.perOmissio, carpeta: "GitHub/botiga") == [.carpetaNoAbsoluta])
        #expect(avisos(.perOmissio, carpeta: inici) == [.carpetaInici])
        #expect(avisos(.perOmissio, carpeta: inici + "/") == [.carpetaInici])
        #expect(avisos(.perOmissio, carpeta: "/Users/prova/GitHub/perduda") == [.carpetaNoExisteix])
        // Una pestanya sense Claude també s'obre en una carpeta.
        #expect(avisos(.nomesTerminal, carpeta: inici) == [.carpetaInici])
        #expect(Avis(.carpetaInici).description == "Carpeta d'inici: probablement Warp l'ha perduda")
    }

    @Test func activaClaudeNomesQuanLaCarpetaJaEsBona() {
        #expect(avisos(.nomesTerminal) == [.claudeApagat])
        #expect(Avis(.claudeApagat).gravetat == .info)
        #expect(avisos(.nomesTerminal, carpeta: "/Users/prova/GitHub/perduda") == [.carpetaNoExisteix])
        // Amb Claude apagat, la resta d'opcions no es revisa: no s'obrirà.
        var apagada = ClaudePestanya.habituals
        apagada.activat = false
        apagada.modePermisos = "yolo"
        #expect(avisos(apagada) == [.claudeApagat])
    }

    @Test func elModeDePermisos() {
        #expect(avisos(ClaudePestanya(modePermisos: "plan")) == [])
        #expect(avisos(ClaudePestanya(modePermisos: "yolo")) == [.modePermisosDesconegut("yolo")])
        #expect(Avis(.modePermisosDesconegut("yolo")).gravetat == .error)
        #expect(avisos(ClaudePestanya(saltaPermisos: true, modePermisos: "plan")) == [.saltaPermisosAmbMode("plan")])
        #expect(Avis(.saltaPermisosAmbMode("plan")).description == "Amb «Salta els permisos», Claude no fa cas del mode «plan»")
        #expect(avisos(ClaudePestanya(saltaPermisos: true, modePermisos: "yolo"))
            == [.modePermisosDesconegut("yolo"), .saltaPermisosAmbMode("yolo")])
    }

    @Test func lEsforc() {
        #expect(avisos(ClaudePestanya(esforc: "max")) == [])
        #expect(avisos(ClaudePestanya(esforc: "HIGH")) == [], "es normalitza a minúscules")
        #expect(avisos(ClaudePestanya(esforc: "extrem")) == [.esforcDesconegut("extrem")])
        #expect(Avis(.esforcDesconegut("extrem")).gravetat == .avis)
    }

    @Test func elsSettings() {
        #expect(avisos(ClaudePestanya(settings: #"{"model": "opus"}"#)) == [])
        #expect(avisos(ClaudePestanya(settings: "/Users/prova/settings.json")) == [])
        #expect(avisos(ClaudePestanya(settings: "{no és json}")) == [.settingsNoJSON])
        #expect(Avis(.settingsNoJSON).gravetat == .error)
        // Amb ultracode, l'error de l'ordre és el mateix: només surt un cop.
        #expect(avisos(ClaudePestanya(esforc: "high", ultracode: true, settings: "{no és json}"))
            == [.settingsNoJSON, .ultracode])
        // Com `JSON.parse`, no com `JSONSerialization`: una coma final atura Claude; `1e400` i `"\ud800"`, no.
        #expect(avisos(ClaudePestanya(settings: #"{"model": "opus",}"#)) == [.settingsNoJSON])
        #expect(avisos(ClaudePestanya(settings: #"{"a": 1e400}"#)) == [])
        #expect(avisos(ClaudePestanya(settings: #"{"a": "\ud800"}"#)) == [])
        // L'app no hi pot afegir ultracode sense canviar-ne el contingut.
        #expect(avisos(ClaudePestanya(esforc: "high", ultracode: true, settings: #"{"a": 1e400}"#))
            == [.ordreImpossible(.settingsNoEsJSON), .ultracode])
        // Claus repetides: Claude les accepta (es queda amb l'última), però no s'hi pot afegir ultracode.
        let repetides = #"{"a": 1, "a": 2}"#
        #expect(avisos(ClaudePestanya(settings: repetides)) == [])
        #expect(avisos(ClaudePestanya(esforc: "high", ultracode: true, settings: repetides))
            == [.ordreImpossible(.settingsNoEsJSON), .ultracode])
        #expect(avisos(ClaudePestanya(esforc: "high", ultracode: true, settings: "/Users/prova/s.json"))
            == [.ordreImpossible(.ultracodeAmbSettingsDeFitxer), .ultracode])
    }

    @Test func lesAltresOpcions() {
        #expect(avisos(ClaudePestanya(altres: ["--add-dir", "/a", "/b", "--verbose"])) == [])
        #expect(avisos(ClaudePestanya(altres: ["--opcio-nova"])) == [.opcionsDesconegudes(["--opcio-nova"], textos: [])])
        #expect(Avis(.opcionsDesconegudes(["--opcio-nova"], textos: [])).description
            == "Claude 2.1.318 no coneix «--opcio-nova»: potser no l'entén (si és d'una versió nova, cal posar al dia la taula d'opcions)")
        // El text que segueix una opció desconeguda pot ser el primer missatge: es diu.
        #expect(avisos(ClaudePestanya(altres: ["--nova", "arregla el bug", "--verbose", "--add-dir", "/a"]))
            == [.opcionsDesconegudes(["--nova"], textos: ["arregla el bug"])])
        #expect(Avis(.opcionsDesconegudes(["--nova"], textos: ["arregla el bug"])).description.hasSuffix(
            ". Si «arregla el bug» no n'és el valor, Claude el prendria pel primer missatge i l'enviaria a cada obertura"))
        #expect(avisos(ClaudePestanya(altres: ["--model", "opus"])) == [.ordreImpossible(.opcioPropiaAAltres("--model"))])
        #expect(avisos(ClaudePestanya(altres: ["--verbose", "fes-ho"])) == [.ordreImpossible(.promptAAltres("fes-ho"))])
        #expect(Avis(.ordreImpossible(.promptAAltres("x"))).gravetat == .error)
    }

    @Test func lesOpcionsDUnSolUs() {
        #expect(avisos(ClaudePestanya(altres: ["-w"])) == [.opcionsDUnSolUs(["--worktree"])])
        #expect(avisos(ClaudePestanya(altres: ["--fork-session", "--from-pr=12"]))
            == [.opcionsDUnSolUs(["--fork-session", "--from-pr"])])
        #expect(avisos(ClaudePestanya(altres: ["--worktree", "nou", "-w"])) == [.opcionsDUnSolUs(["--worktree", "--worktree"])])
        #expect(Avis(.opcionsDUnSolUs(["--worktree", "--worktree"])).description
            == "«--worktree» és d'un sol ús: es tornaria a fer a cada obertura")
        #expect(Avis(.opcionsDUnSolUs([])).gravetat == .avis)
        // Totes les opcions d'un sol ús són a la taula de Claude Code.
        for nom in Validacio.opcionsDUnSolUs { #expect(TaulaOpcionsClaude.troba(nom) != nil, "\(nom)") }
    }

    @Test func elsNomsDeFinestraRepetits() {
        let pestanya = Pestanya(id: uuid(10), titol: "Botiga", carpeta: "/Users/prova/GitHub/botiga", claude: .perOmissio)
        let configuracio = Configuracio(finestres: [
            Finestra(id: uuid(1), nom: "Feina", pestanyes: [pestanya]),
            Finestra(id: uuid(2), nom: "feina ", pestanyes: []),
            Finestra(id: uuid(3), nom: "Planta", pestanyes: []),
            Finestra(id: uuid(4), nom: "", pestanyes: []),
            Finestra(id: uuid(5), nom: " ", pestanyes: []),
        ])
        let resultat = Validacio.avisos(configuracio, inici: inici, carpetaExisteix: existents.contains)
        #expect(resultat.finestres == [uuid(1): [Avis(.nomRepetit("Feina"))], uuid(2): [Avis(.nomRepetit("feina "))]])
        #expect(resultat.pestanyes.isEmpty)
        #expect(resultat.compta(.avis) == 2)
        #expect(resultat.compta(.error) == 0)
    }

    /// Veredictes de `JSON.parse` (node, 04/11/2026).
    @Test(arguments: [
        ("{}", true), (#"{"a":1}"#, true), (#" {"a":1} "#, true), (#"{"a":1,}"#, false), (#"{"a":[1,]}"#, false),
        (#"{"a":[1,2]}"#, true), (#"{"a":01}"#, false), (#"{"a":0}"#, true), (#"{"a":-0.5e-3}"#, true),
        (#"{"a":1E+2}"#, true), (#"{"a":1e400}"#, true), (#"{"a":.5}"#, false), (#"{"a":1.}"#, false),
        (#"{"a":-}"#, false), (#"{"a":+1}"#, false), (#"{"a":NaN}"#, false), (#"{"a":"\ud800"}"#, true),
        (#"{"a":"é"}"#, true), (#"{"a":"\u00"}"#, false), (#"{"a":"\x"}"#, false),
        (#"{"a":"\/\b\f\n\r\t\"\\"}"#, true), (#"{"a":true,"b":false,"c":null}"#, true), (#"{"a":tru}"#, false),
        ("{a:1}", false), (#"{"a":1}x"#, false), (#"{"a":1}{"b":2}"#, false), (#"{"a" 1}"#, false),
        (#"{"a":1 "b":2}"#, false), (#"{"a":[[[]]]}"#, true), (#"{"a":{"b":{"c":{}}}}"#, true), ("{,}", false),
        (#"{"a":1,,"b":2}"#, false), ("{\"a\":\"x\ty\"}", false), ("", false), ("{", false), (#"{"a":"x}"#, false),
    ])
    func jsonEstricteComJSONParse(_ text: String, _ valid: Bool) {
        #expect(JSONEstricte.esValid(Array(text.utf8)) == valid)
    }

    @Test func jsonEstricteNoEsgotaLaPila() {
        let fondo = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(!JSONEstricte.esValid(Array(fondo.utf8)))
        let normal = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        #expect(JSONEstricte.esValid(Array(normal.utf8)))
    }

    @Test func lesGravetatsSOrdenen() {
        #expect(Avis.Gravetat.info < .avis)
        #expect(Avis.Gravetat.avis < .error)
    }
}
