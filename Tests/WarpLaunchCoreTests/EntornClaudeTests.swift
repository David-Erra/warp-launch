import Foundation
import Testing
@testable import WarpLaunchCore

// La funció `claude` de `EntornClaude`, executada de debò a zsh i a bash, amb un `claude` fals que només escriu els seus
// arguments. El PATH de la prova només té el fals: no es pot arribar mai al Claude de debò.

private let shells = ["/bin/zsh", "/bin/bash"]

private let mode = ["--permission-mode", "bypassPermissions"]
private let idFeina = "4d7e2a91-3b6c-4f08-a5d2-8e1c9b0f7a63"
private let altreId = "b8e05f3c-72a4-4d19-9c6e-1f3a5d7b2e40"

/// El text sense els espais dels extrems, com el llegeix Claude.
private var textNet: String { EntornClaude.text.trimmingCharacters(in: .whitespacesAndNewlines) }

private func carpetaTemporal() throws -> URL {
    let carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-entorn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    return carpeta
}

/// El que surt d'executar `ordre` amb el fitxer enganxat al davant, tal com ho fa Claude: `<anterior> && <text>\n: && <ordre>`
/// (binari 2.1.318, `Qe.push(`${Et}\n:`)`). A la carpeta temporal hi ha el `claude` fals, una ordre `entorn` que escriu el valor
/// de la variable, i la carpeta de Claude amb les feines que li diguis.
private func executa(_ shell: String, _ ordre: String, feines: [String] = [], abans: String = "true",
                     carpetaClaude: String = "CLAUDE_CONFIG_DIR") throws -> [String] {
    let carpeta = try carpetaTemporal()
    defer { try? FileManager.default.removeItem(at: carpeta) }
    func executable(_ nom: String, _ text: String) throws {
        let fitxer = carpeta.appending(path: nom)
        try Data(("#!/bin/sh\n" + text).utf8).write(to: fitxer)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fitxer.path)
    }
    try executable("claude", "for a; do printf '%s\\0' \"$a\"; done\nexit ${CODI:-0}\n")
    try executable("entorn", "printf '%s\\0' \"${CLAUDE_ENV_FILE-cap}\"\n")
    let config = carpetaClaude == "HOME" ? carpeta.appending(path: ".claude") : carpeta.appending(path: "config")
    for feina in feines {
        let lloc = config.appending(path: "jobs").appending(path: feina)
        try FileManager.default.createDirectory(at: lloc, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: lloc.appending(path: "state.json"))
    }
    let valor = carpetaClaude == "HOME" ? carpeta.path : config.path
    let script = "PATH=\(Informe.cometes(carpeta.path)); unset CLAUDE_CONFIG_DIR; export \(carpetaClaude)=\(Informe.cometes(valor)); "
        + "\(abans) && \(textNet)\n: && " + ordre
    return try sortidaDe(shell, script)
}

@Suite struct EntornClaudeTests {
    /// Una feina nova: l'ordre porta el paràmetre, just després de `--bg`, i el text no es toca.
    @Test(arguments: shells) func unaFeinaNovaPortaElParametre(shell: String) throws {
        #expect(try executa(shell, "claude --bg 'text amb  espais'") == ["--bg"] + mode + ["text amb  espais"])
        #expect(try executa(shell, "claude --background x") == ["--background"] + mode + ["x"])
        #expect(try executa(shell, "claude --bg") == ["--bg"] + mode)
        #expect(try executa(shell, "claude --bg -n nom 'a b'") == ["--bg"] + mode + ["-n", "nom", "a b"])
    }

    /// Una feina que ja existeix es desperta sola, amb les seves opcions: amb el paràmetre, Claude en faria una còpia.
    @Test(arguments: shells) func unaFeinaQueJaExisteixNoElPorta(shell: String) throws {
        let feines = [String(idFeina.prefix(8))]
        #expect(try executa(shell, "claude --bg --resume \(idFeina) 'a b'", feines: feines) == ["--bg", "--resume", idFeina, "a b"])
        #expect(try executa(shell, "claude --bg -r \(idFeina)", feines: feines) == ["--bg", "-r", idFeina])
        #expect(try executa(shell, "claude --bg --resume \(idFeina)", feines: feines, carpetaClaude: "HOME")
            == ["--bg", "--resume", idFeina], "la carpeta per defecte de Claude")
    }

    /// Reprendre una conversa que encara no és una feina: conserva l'id, i sense el paràmetre aniria en `auto` (el cas del 03/11).
    /// Un id curt sempre fa una còpia: millor que vagi en bypass.
    @Test(arguments: shells) func unaConversaSenseFeinaElPorta(shell: String) throws {
        let feines = [String(idFeina.prefix(8))]
        #expect(try executa(shell, "claude --bg --resume \(altreId) x", feines: feines) == ["--bg"] + mode + ["--resume", altreId, "x"])
        #expect(try executa(shell, "claude --bg --resume \(idFeina.prefix(8)) x", feines: feines)
            == ["--bg"] + mode + ["--resume", String(idFeina.prefix(8)), "x"])
    }

    /// La ruta no passa al que engega la shell: si no, arribaria al servei de feines i a totes les feines, també a les que no
    /// van en bypass. La funció continua definida.
    @Test(arguments: shells) func laVariableNoPassaAlsFills(shell: String) throws {
        #expect(try executa(shell, "entorn", abans: "export CLAUDE_ENV_FILE=/x") == ["cap"])
        #expect(try executa(shell, "claude --bg x", abans: "export CLAUDE_ENV_FILE=/x") == ["--bg"] + mode + ["x"])
    }

    /// El codi de sortida de Claude arriba a l'agent, pels dos camins de la funció.
    @Test(arguments: shells) func elCodiDeSortidaArriba(shell: String) throws {
        let feines = [String(idFeina.prefix(8))]
        #expect(try executa(shell, "export CODI=7; claude --bg; printf '%s\\0' \"codi $?\"").last == "codi 7")
        #expect(try executa(shell, "export CODI=7; claude --bg --resume \(idFeina); printf '%s\\0' \"codi $?\"", feines: feines).last == "codi 7")
        #expect(try executa(shell, "export CODI=7; claude --version; printf '%s\\0' \"codi $?\"").last == "codi 7")
    }

    /// Formes d'ordre vistes en feines reals (05/11/2026): la majoria van amb `cd … &&`.
    @Test(arguments: shells) func lesFormesReals(shell: String) throws {
        let esperat = ["--bg"] + mode + ["x"]
        #expect(try executa(shell, "cd / && claude --bg x") == esperat)
        #expect(try executa(shell, "(claude --bg x)") == esperat)
        #expect(try executa(shell, "claude --bg x 2>/dev/null") == esperat)
    }

    /// Si l'agent tria un mode, el seu va després i és el que mana.
    @Test(arguments: shells) func elModeDeLAgentVaDespres(shell: String) throws {
        #expect(try executa(shell, "claude --bg --permission-mode plan x") == ["--bg"] + mode + ["--permission-mode", "plan", "x"])
    }

    /// El que no és una feina no canvia, encara que el text digui `--bg`.
    @Test(arguments: shells) func laRestaNoCanvia(shell: String) throws {
        #expect(try executa(shell, "claude --version") == ["--version"])
        #expect(try executa(shell, "claude --resume id") == ["--resume", "id"])
        #expect(try executa(shell, "claude -p 'hola --bg'") == ["-p", "hola --bg"])
        #expect(try executa(shell, "claude '--bg text'") == ["--bg text"])
        #expect(try executa(shell, "claude") == [])
    }

    /// Un àlies `claude` d'un fitxer d'inici (`.zshenv`) ja existeix quan zsh llegeix la línia: amb `claude()`, tota la línia
    /// fallaria, i també totes les ordres de Bash de la pestanya. La segona part comprova que la prova ho distingeix.
    @Test func unAliesNoTrencaLaLinia() throws {
        let carpeta = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: carpeta) }
        try Data("alias claude=/usr/bin/true\n".utf8).write(to: carpeta.appending(path: ".zshenv"))
        let bona = try zshAmbInici("true && \(textNet)\n: && printf seguent", zdotdir: carpeta)
        #expect(bona.codi == 0 && bona.sortida == "seguent", "\(bona.sortida)")
        #expect(textNet.contains("function claude {"))
        let dolenta = textNet.replacing("function claude {", with: "claude() {")
        #expect(try zshAmbInici("true && \(dolenta)\n: && printf seguent", zdotdir: carpeta).codi != 0)
    }

    /// Enganxat al davant de cada ordre: només ASCII i sense apòstrofs, que obririen unes cometes en una altra shell.
    @Test func elTextEsSegur() {
        #expect(EntornClaude.text.utf8.count == EntornClaude.text.unicodeScalars.count, "només ASCII")
        #expect(!EntornClaude.text.contains("'"))
        #expect(EntornClaude.text.hasPrefix("# Warp Launch"), "la marca pròpia (regla 7)")
    }

    @Test func desaEscriuElFitxerINomesSiCanvia() throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-entorn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        try EntornClaude.desa(carpeta: carpeta)
        let fitxer = carpeta.appending(path: EntornClaude.nomFitxer)
        #expect(try Data(contentsOf: fitxer) == Data(EntornClaude.text.utf8))
        let abans = try #require(FileManager.default.attributesOfItem(atPath: fitxer.path)[.modificationDate] as? Date)
        try EntornClaude.desa(carpeta: carpeta)
        #expect(FileManager.default.fileExists(atPath: fitxer.path))
        let despres = try FileManager.default.attributesOfItem(atPath: fitxer.path)[.modificationDate] as? Date
        #expect(despres == abans)
        try Data("una altra cosa".utf8).write(to: fitxer)
        try EntornClaude.desa(carpeta: carpeta)
        #expect(try Data(contentsOf: fitxer) == Data(EntornClaude.text.utf8))
    }

    @Test func laRutaEsAbsoluta() {
        #expect(EntornClaude.ruta(carpeta: URL(filePath: "/tmp/a b")) == "/tmp/a b/entorn-claude.sh")
        #expect(EntornClaude.ruta(carpeta: URL(filePath: "relativa")).hasPrefix("/"))
    }

    /// La línia: el mateix `argv` per a la shell, i la variable només si se'n passa una.
    @Test func laLiniaPortaLaVariable() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #expect(OrdreClaude.liniaExec(["claude"], pestanya: id)
            == " WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000001 claude")
        let linia = OrdreClaude.liniaExec(["claude", "--effort", "high"], pestanya: id, entorn: "/tmp/a b/entorn-claude.sh")
        #expect(linia == " WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000001 "
            + "CLAUDE_ENV_FILE='/tmp/a b/entorn-claude.sh' claude --effort high")
        // Una assignació davant d'una ordre: la shell la passa a aquesta ordre, i no a la resta de la pestanya.
        let entorn = try sortidaDe("/bin/zsh", "printf() { builtin printf '%s\\0' \"$CLAUDE_ENV_FILE\" \"$@\"; }; "
            + "claude() { builtin printf '%s\\0' \"$CLAUDE_ENV_FILE\" \"$@\"; }; " + linia)
        #expect(entorn == ["/tmp/a b/entorn-claude.sh", "--effort", "high"])
    }

    /// Al pla: només les pestanyes amb Claude en bypass, i només si l'entrada en diu la ruta (la lectura no escriu res).
    @Test func alPlaNomesLesPestanyesEnBypass() {
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
        let finestra = Finestra(id: id(100), nom: "W", pestanyes: [
            Pestanya(id: id(1), titol: "a", carpeta: "/x/a", claude: ClaudePestanya(saltaPermisos: true)),
            Pestanya(id: id(2), titol: "b", carpeta: "/x/b", claude: ClaudePestanya(modePermisos: "bypassPermissions")),
            Pestanya(id: id(3), titol: "c", carpeta: "/x/c", claude: ClaudePestanya(modePermisos: "auto")),
            Pestanya(id: id(4), titol: "d", carpeta: "/x/d", claude: ClaudePestanya(activat: false)),
        ])
        func pla(entorn: String?) -> Pla {
            PlaObertura.calcula(finestra, EntradaObertura(
                lectura: LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []), estat: EstatApp(), inici: "/Users/prova",
                ara: Date(timeIntervalSince1970: 1_793_750_400), carpetaExisteix: { _ in true },
                transcripcio: { _, _ in .enlloc }, confianca: nil, entornClaude: entorn))
        }
        let amb = pla(entorn: "/c/entorn-claude.sh")
        #expect(amb.aObrir.map { $0.yaml.exec?.contains("CLAUDE_ENV_FILE=/c/entorn-claude.sh ") } == [true, true, false, nil])
        #expect(amb.necessitaEntornClaude)
        #expect(pla(entorn: nil).aObrir.allSatisfy { $0.yaml.exec?.contains("CLAUDE_ENV_FILE") != true })
        let sense = Finestra(id: id(100), nom: "W", pestanyes: [finestra.pestanyes[2], finestra.pestanyes[3]])
        #expect(!PlaObertura.calcula(sense, EntradaObertura(
            lectura: LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []), estat: EstatApp(), inici: "/Users/prova",
            ara: Date(timeIntervalSince1970: 1_793_750_400), carpetaExisteix: { _ in true },
            transcripcio: { _, _ in .enlloc }, confianca: nil, entornClaude: "/c/e")).necessitaEntornClaude)
    }

    @Test func enBypass() {
        #expect(ClaudePestanya(saltaPermisos: true).enBypass)
        #expect(ClaudePestanya(modePermisos: "bypassPermissions").enBypass)
        #expect(!ClaudePestanya(modePermisos: "auto").enBypass)
        #expect(!ClaudePestanya().enBypass)
    }
}
