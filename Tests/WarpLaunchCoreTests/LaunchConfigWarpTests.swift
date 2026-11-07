import Foundation
import Testing
@testable import WarpLaunchCore

// El fitxer temporal que fa obrir una finestra a Warp (fase 3.1, D5), i la línia que Warp escriu a cada pestanya.
// Només es genera text: no s'escriu cap fitxer ni s'obre res. zsh només llegeix la línia, amb `claude` canviat per una
// funció que l'escriu.

private let llancament = UUID(uuidString: "3F2A9C1E-0B7D-4E8F-9A6B-5C4D3E2F1A0B")!
private let pestanya = UUID(uuidString: "9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62")!
private let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"

/// Llegeix un escalar entre cometes dobles com un lector de YAML, només amb `\\` i `\"` (escrit a mà, no amb el codi
/// que es prova). `nil` si no és un escalar així.
private func llegeixEscalar(_ text: some StringProtocol) -> String? {
    guard text.count >= 2, text.first == "\"", text.last == "\"" else { return nil }
    var resultat = "", escapat = false
    for c in text.dropFirst().dropLast() {
        if escapat {
            guard c == "\\" || c == "\"" else { return nil }
            resultat.append(c)
            escapat = false
        } else if c == "\\" {
            escapat = true
        } else if c == "\"" {
            return nil  // una cometa sense escapar acabaria l'escalar abans d'hora
        } else {
            resultat.append(c)
        }
    }
    return escapat ? nil : resultat
}

/// El valor de cada línia `clau: "…"` del fitxer, en ordre.
private func valors(_ clau: String, _ fitxer: FitxerLaunch) -> [String?] {
    fitxer.text.split(separator: "\n").compactMap { linia in
        let net = linia.drop { $0 == " " || $0 == "-" }.drop { $0 == " " }
        guard net.hasPrefix("\(clau): ") else { return nil }
        return llegeixEscalar(net.dropFirst(clau.count + 2))
    }
}

@Suite struct LaunchConfigWarpTests {
    // MARK: El fitxer

    /// Una pestanya amb Claude (ultracode amb un esforç «Alt»: `--settings` amb cometes) i una de terminal.
    @Test func elFitxerDeDuesPestanyes() throws {
        let claude = ClaudePestanya(esforc: "high", ultracode: true, saltaPermisos: true)
        let argv = try #require(try OrdreClaude.argv(claude, repren: conversa))
        let fitxer = try LaunchConfigWarp.genera(pestanyes: [
            PestanyaYAML(titol: "Botiga", carpeta: "/Users/prova/GitHub/botiga",
                         exec: OrdreClaude.liniaExec(argv, pestanya: pestanya)),
            PestanyaYAML(titol: "Web Host", carpeta: "/Users/prova/GitHub/web host", exec: nil),
        ], llancament: llancament)
        #expect(fitxer.text == #"""
            # warp-launch: temporal 3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b
            name: "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b"
            windows:
              - tabs:
                  - title: "Botiga"
                    layout:
                      cwd: "/Users/prova/GitHub/botiga"
                      commands:
                        - exec: " WARP_LAUNCH_PESTANYA=9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62 claude --dangerously-skip-permissions --effort high --settings '{\"ultracode\":true}' --resume 1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
                  - title: "Web Host"
                    layout:
                      cwd: "/Users/prova/GitHub/web host"

            """#)
        #expect(fitxer.nom == "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b")
        #expect(fitxer.nomFitxer == "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b.yaml")
        #expect(fitxer.llancament == llancament)
        #expect(valors("cwd", fitxer) == ["/Users/prova/GitHub/botiga", "/Users/prova/GitHub/web host"])
    }

    /// El nom no té punts ni res a codificar, i l'URL el porta tal com és: Warp el troba sense cap reintent.
    @Test func elNomILURL() throws {
        let fitxer = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "x", carpeta: "/x", exec: nil)],
                                                 llancament: UUID())
        #expect(fitxer.nom.wholeMatch(of: /warp-launch-[0-9a-f-]{36}/) != nil)
        #expect(!fitxer.nom.contains("."))
        #expect(valors("name", fitxer) == [fitxer.nom])
        let url = fitxer.url.url
        #expect(url.scheme == "warp")
        #expect(url.host() == "launch")
        #expect(url.path() == "/" + fitxer.nom)
        #expect(url.query() == nil && url.fragment() == nil)
        #expect(fitxer.url.description == url.absoluteString)
    }

    @Test func laPrimeraLiniaEsLaMarca() throws {
        let fitxer = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "x", carpeta: "/x", exec: nil)],
                                                 llancament: llancament)
        #expect(fitxer.text.split(separator: "\n").first.map(String.init) == LaunchConfigWarp.marca(llancament))
        #expect(LaunchConfigWarp.marca(llancament) == "# warp-launch: temporal 3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b")
        #expect(fitxer.text.hasSuffix("\n"))
    }

    @Test func nomesElsNomsPropis() {
        let propi = "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b.yaml"
        #expect(LaunchConfigWarp.esNomPropi(propi))
        for nom in ["espai-tot.yaml", "warp-launch-x.yaml", "warp-launch-.yaml", "warp-launch-3F2A9C1E-0B7D-4E8F-9A6B-5C4D3E2F1A0B.yaml",
                    "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b", "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b.yml",
                    "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b.YAML", propi + ".bak", "../" + propi, "x" + propi,
                    "warp-launch-3f2a9c1e0b7d4e8f9a6b5c4d3e2f1a0b.yaml"] {
            #expect(!LaunchConfigWarp.esNomPropi(nom), "\(nom)")
        }
    }

    /// Sense títol, el nom de la carpeta (Warp hi posaria el seu títol automàtic, que no és el de l'editor).
    @Test func titolBuitEsElNomDeLaCarpeta() throws {
        for titol in ["", "  "] {
            let fitxer = try LaunchConfigWarp.genera(
                pestanyes: [PestanyaYAML(titol: titol, carpeta: "/Users/prova/web host", exec: nil)], llancament: llancament)
            #expect(valors("title", fitxer) == ["web host"])
        }
    }

    /// Una pestanya de terminal no porta `commands`; cap línia no porta `export` ni `--continue`.
    @Test func nomesTerminalNoPortaOrdres() throws {
        let fitxer = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "x", carpeta: "/x", exec: nil)],
                                                 llancament: llancament)
        #expect(!fitxer.text.contains("commands"))
        #expect(!fitxer.text.contains("exec"))
        let argv = try #require(try OrdreClaude.argv(.habituals, repren: nil))
        let ambClaude = try LaunchConfigWarp.genera(
            pestanyes: [PestanyaYAML(titol: "x", carpeta: "/x", exec: OrdreClaude.liniaExec(argv, pestanya: pestanya))],
            llancament: llancament)
        #expect(!ambClaude.text.contains("export"))
        #expect(!ambClaude.text.contains("--continue"))
        #expect(valors("exec", ambClaude).count == 1)
    }

    // MARK: Errors

    @Test func senseCapPestanyaNoHiHaFitxer() {
        #expect(throws: LaunchConfigWarp.ErrorLaunch.capPestanya) {
            try LaunchConfigWarp.genera(pestanyes: [], llancament: llancament)
        }
    }

    /// Warp obriria la pestanya a la seva carpeta per defecte i hi executaria Claude igualment.
    @Test(arguments: ["", "docs", "~", "~/GitHub", "./x", " /x"])
    func laCarpetaHaDeSerAbsoluta(carpeta: String) {
        let bona = PestanyaYAML(titol: "a", carpeta: "/a", exec: nil)
        let dolenta = PestanyaYAML(titol: "b", carpeta: carpeta, exec: nil)
        #expect(throws: LaunchConfigWarp.ErrorLaunch.pestanya(index: 1, .carpetaNoAbsoluta(carpeta))) {
            try LaunchConfigWarp.genera(pestanyes: [bona, dolenta], llancament: llancament)
        }
        #expect(throws: LaunchConfigWarp.ErrorPestanya.carpetaNoAbsoluta(carpeta)) { try LaunchConfigWarp.comprova(dolenta) }
        #expect(throws: Never.self) { try LaunchConfigWarp.comprova(bona) }
    }

    /// Cada camp diu on és el caràcter que no es pot escriure.
    @Test func elCaracterDiuDeQuinCampEs() {
        let salt = YAMLWarp.ErrorYAML.caracterNoAdmes("\n")
        let casos: [(PestanyaYAML, LaunchConfigWarp.ErrorPestanya)] = [
            (PestanyaYAML(titol: "a\nb", carpeta: "/x", exec: nil), .titol(salt)),
            (PestanyaYAML(titol: "a", carpeta: "/x\ny", exec: nil), .carpeta(salt)),
            (PestanyaYAML(titol: "a", carpeta: "/x", exec: " claude\n"), .ordre(salt)),
        ]
        for (p, error) in casos {
            #expect(throws: error) { try LaunchConfigWarp.comprova(p) }
            #expect(throws: LaunchConfigWarp.ErrorLaunch.pestanya(index: 0, error)) {
                try LaunchConfigWarp.genera(pestanyes: [p], llancament: llancament)
            }
        }
    }

    // MARK: Escalars

    @Test func escapaLaBarraILesCometes() throws {
        #expect(try YAMLWarp.escalar(#"a\b"c"#) == #""a\\b\"c""#)
        #expect(try YAMLWarp.escalar("") == #""""#)
        #expect(try YAMLWarp.escalar(#"\""#) == #""\\\"""#)
    }

    /// Tot el que una shell o un lector de YAML podrien interpretar torna igual.
    @Test(arguments: [
        "", "simple", #"a\b"#, #"a"b"#, #"\\"#, #"""#, #"\""#, "l'agent «Gestió»", "$HOME `true` $(true)", "#x", "a: b",
        "- x", "{a: 1}", "[1]", "&ancora", "*alias", "!etiqueta", "%YAML", "@x", "?x", "|", ">", "àèìòù·ç", "🙂", "\u{A0}",
        #"{"ultracode":true}"#, "~", "null", "true", "0x10", "  espais  ",
    ])
    func elsEscalarsTornenIgual(text: String) throws {
        let escalar = try YAMLWarp.escalar(text)
        #expect(llegeixEscalar(escalar) == text, "\(escalar)")
    }

    /// Els caràcters que s'haurien d'escriure amb un altre escapament (o que un lector podria canviar) són un error.
    @Test(arguments: ["\n", "\t", "\r", "\u{0}", "\u{1B}", "\u{7F}", "\u{80}", "\u{85}", "\u{9F}", "\u{2028}", "\u{2029}",
                      "\u{FEFF}", "\u{FFFE}", "\u{FFFF}"] as [Unicode.Scalar])
    func elsCaractersDeControlSonUnError(c: Unicode.Scalar) {
        #expect(throws: YAMLWarp.ErrorYAML.caracterNoAdmes(c)) { try YAMLWarp.escalar("abans\(Character(c))després") }
    }

    // MARK: La línia de cada pestanya

    @Test func laLiniaComencaAmbUnEspaiILaMarca() {
        let linia = OrdreClaude.liniaExec(["claude", "--effort", "high"], pestanya: pestanya)
        #expect(linia == " WARP_LAUNCH_PESTANYA=9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62 claude --effort high")
        #expect(!linia.contains("export"))
    }

    /// La línia, tal com la llegiria Warp del YAML i l'escriuria a zsh: `claude` rep l'`argv` exacte i la marca, i la
    /// variable no queda a la shell. Aquí `claude` és una funció que escriu el que rep.
    @Test(arguments: [
        ClaudePestanya.habituals,
        ClaudePestanya(esforc: "high", ultracode: true, nom: "l'agent «Gestió»"),
        ClaudePestanya(model: "-raro", settings: #"{"env": {"A": "$HOME `true`"}, "b": "\\ \""}"#),
        ClaudePestanya(saltaPermisos: true, controlRemot: "", altres: ["--add-dir", "/a b", "~/x", "*"]),
    ])
    func zshLlegeixLaLiniaDelFitxer(claude: ClaudePestanya) throws {
        for repren in [nil, conversa, "-x"] as [String?] {
            let argv = try #require(try OrdreClaude.argv(claude, repren: repren))
            let fitxer = try LaunchConfigWarp.genera(
                pestanyes: [PestanyaYAML(titol: "x", carpeta: "/x", exec: OrdreClaude.liniaExec(argv, pestanya: pestanya))],
                llancament: llancament)
            let exec = try #require(valors("exec", fitxer).first ?? nil)
            // Sense la variable: les proves poden córrer dins d'una pestanya oberta per l'app, que la porta a l'entorn.
            let script = #"unset WARP_LAUNCH_PESTANYA; claude() { printf '%s\0' "$WARP_LAUNCH_PESTANYA" "$@"; }; "#
                + exec + #"; printf '%s\0' "${WARP_LAUNCH_PESTANYA-cap}""#
            let sortida = try sortidaDe("/bin/zsh", script)
            #expect(sortida == [pestanya.uuidString] + argv.dropFirst() + ["cap"], "\(exec)")
        }
    }
}
