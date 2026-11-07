import Foundation
import Testing
@testable import WarpLaunchCore

@Suite struct ResumTests {
    @Test func plurals() {
        #expect(Plural.compta(0, "pestanya", "pestanyes") == "0 pestanyes")
        #expect(Plural.compta(1, "pestanya", "pestanyes") == "1 pestanya")
        #expect(Plural.compta(23, "pestanya", "pestanyes") == "23 pestanyes")
    }

    @Test func resumDeWarp() {
        #expect(ResumWarp(finestres: 7, pestanyes: 64, sessionsClaude: 14).descripcio
            == "Warp: 7 finestres · 64 pestanyes · 14 sessions de Claude")
        #expect(ResumWarp(finestres: 1, pestanyes: 1, sessionsClaude: 1).descripcio
            == "Warp: 1 finestra · 1 pestanya · 1 sessió de Claude")
    }

    @Test func resumDUnaFinestra() {
        let ambClaude = ClaudePestanya.habituals, sense = ClaudePestanya.nomesTerminal
        let finestra = Finestra(id: UUID(), nom: "feina", pestanyes: [
            Pestanya(id: UUID(), titol: "a", carpeta: "/a", claude: ambClaude),
            Pestanya(id: UUID(), titol: "b", carpeta: "/b", claude: sense),
            Pestanya(id: UUID(), titol: "c", carpeta: "/c", claude: ambClaude),
        ])
        #expect(finestra.ambClaude == 2)
        #expect(finestra.resum == "3 pestanyes · 2 amb Claude")
        #expect(Finestra(id: UUID(), nom: "buida").resum == "0 pestanyes · 0 amb Claude")
    }

    // MARK: Arguments de l'app

    private let real = Rutes.carpetaConfiguracio(inici: "/Users/prova")

    private func arguments(_ arguments: [String]) -> ArgumentsApp {
        ArgumentsApp(["/Applications/Warp Launch.app/Contents/MacOS/WarpLaunch"] + arguments, inici: "/Users/prova")
    }

    /// La ruta, si és de prova.
    private func prova(_ arguments: String...) -> String? {
        if case let .prova(url) = self.arguments(arguments).carpeta { url.path } else { nil }
    }

    @Test func senseArgumentsEsLaCarpetaDeD8() {
        let a = arguments([])
        #expect(a.carpeta == .real(real))
        #expect(a.carpetaConfiguracio == real)
        #expect(!a.deProva)
    }

    @Test func ambConfigEsUnaCarpetaDeProva() {
        let a = arguments(["--config", "/tmp/prova/../wl"])
        #expect(a.carpetaConfiguracio?.path == "/tmp/wl")
        #expect(a.deProva)
        #expect(prova("--config=/tmp/wl") == "/tmp/wl")
        #expect(prova("--config", "~/proves/wl") == "/Users/prova/proves/wl")
    }

    @Test func elsArgumentsDeMacOSSIgnoren() {
        #expect(prova("-NSDocumentRevisionsDebugMode", "YES", "--config", "/tmp/wl") == "/tmp/wl")
        #expect(arguments(["-psn_0_12345"]).carpeta == .real(real))
        #expect(arguments(["-AppleLanguages", "(ca)"]).carpeta == .real(real))
    }

    /// Un `--config` mal escrit no ha de fer servir mai la configuració real: la prova 1 hi escriuria.
    @Test(arguments: [
        ["--config"], ["--config", ""], ["--config="], ["--config", "prova"], ["--config", "./prova"],
        ["--config", "~altri/prova"], ["--confg", "/tmp/wl"], ["-config", "/tmp/wl"], ["/tmp/wl"],
        ["--config", "/tmp/a", "--config", "/tmp/b"],
    ])
    func unArgumentMalEscritNoFaServirCapCarpeta(arguments: [String]) {
        let a = self.arguments(arguments)
        guard case let .incorrecta(motiu) = a.carpeta else {
            Issue.record("\(arguments) → \(a.carpeta)")
            return
        }
        #expect(!motiu.isEmpty)
        #expect(a.carpetaConfiguracio == nil)
        #expect(!a.deProva)
    }

    @Test func laCarpetaRealPerConfigNoEsDeProva() {
        #expect(arguments(["--config", real.path]).carpeta == .real(real))
        // «~/» i els dos darrers components (sense escriure la ruta: la prova de guarda no ho deixa).
        #expect(arguments(["--config", "~/" + real.pathComponents.suffix(2).joined(separator: "/") + "/"]).carpeta == .real(real))
    }
}

/// El resum de Claude de cada fila de la llista (pas 8).
@Suite struct ResumClaudeTests {
    @Test func elResumDeLaFila() {
        #expect(ClaudePestanya.habituals.resum == "Molt alt · Ultracode")
        #expect(ClaudePestanya.perOmissio.resum == "Claude")
        #expect(ClaudePestanya.nomesTerminal.resum == "Només terminal")
        #expect(ClaudePestanya(model: "opus", esforc: "xhigh", ultracode: true).resum == "Opus · Molt alt · Ultracode")
        // L'àlies `ultracode` i les majúscules es normalitzen; un model que no és àlies, tal com està escrit.
        #expect(ClaudePestanya(model: "claude-opus-5-5", esforc: "ULTRACODE").resum == "claude-opus-5-5 · Molt alt · Ultracode")
        #expect(ClaudePestanya(model: "  ", esforc: "extrem").resum == "extrem")
        var apagada = ClaudePestanya.habituals
        apagada.activat = false
        #expect(apagada.resum == "Només terminal")
    }

    @Test func elsNomsDelsEsforcos() {
        #expect(ClaudePestanya.esforcosConeguts.map(ClaudePestanya.nomEsforc) == ["Baix", "Mitjà", "Alt", "Molt alt", "Màxim"])
        #expect(ClaudePestanya.nomModel("Sonnet") == "Sonnet")
        #expect(ClaudePestanya.nomModel("haiku") == "Haiku")
    }

    @Test func elsNomsDelsModesIElsModels() {
        #expect(ClaudePestanya.modesPermisos.map(ClaudePestanya.nomMode) == [
            "Accepta les edicions (acceptEdits)", "Automàtic (auto)", "Sense cap permís (bypassPermissions)",
            "Manual (manual)", "No preguntis (dontAsk)", "Planifica (plan)",
        ])
        #expect(ClaudePestanya.nomMode("yolo") == "yolo")
        #expect(ClaudePestanya.modelsConeguts.map(ClaudePestanya.nomModel) == ["Fable", "Opus", "Sonnet", "Haiku"])
    }

    @Test func lesOpcionsQueLInspectorNoEdita() {
        #expect(ClaudePestanya.habituals.opcionsNomesLectura.isEmpty)
        let c = ClaudePestanya(settings: #"{"a":1}"#, controlRemot: "", altres: ["--add-dir", "/tmp/x"])
        #expect(c.opcionsNomesLectura.map(\.nom) == ["--settings", "--remote-control", "Altres"])
        #expect(c.opcionsNomesLectura.map(\.valor) == [#"{"a":1}"#, "sense nom", "--add-dir /tmp/x"])
        #expect(ClaudePestanya(controlRemot: "mac").opcionsNomesLectura.map(\.valor) == ["mac"])
        // Normalitzades, com a l'ordre: un `"ultracode": false` amb l'ultracode activat no hi va.
        #expect(ClaudePestanya(esforc: "xhigh", ultracode: true, settings: #"{"ultracode":false}"#).opcionsNomesLectura.isEmpty)
        #expect(ClaudePestanya(settings: #"{"ultracode":false,"a":1}"#).opcionsNomesLectura.map(\.valor)
            == [#"{"ultracode":false,"a":1}"#])
    }
}
