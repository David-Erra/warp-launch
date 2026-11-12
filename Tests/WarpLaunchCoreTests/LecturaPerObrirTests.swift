import Foundation
import Testing
@testable import WarpLaunchCore

// El que l'app ha de llegir abans d'obrir una finestra (fase 3.1, pas 0.16.0): la marca de cada Claude, les sessions en
// segon pla, si Warp és obert, on és cada transcripció i la confiança de cada carpeta. Sempre amb dades fictícies en
// carpetes temporals.

private let marca = UUID(uuidString: "9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62")!

@Suite struct MarcaISegonPlaTests {
    /// La marca surt de l'entorn del procés; en majúscules o minúscules, però ha de ser un UUID.
    @Test func laMarcaDeCadaSessio() throws {
        let e = try LectorTests.Escenari { processos, sessions in
            processos.processos[106]?.info.entorn[OrdreClaude.variableMarca] = marca.uuidString
            processos.processos[103]?.info.entorn[OrdreClaude.variableMarca] = marca.uuidString.lowercased()
            try escriuSessio(a: sessions, pid: 201, sessionId: "s-201", cwd: "/tmp")
            processos.claude(201, argv: ["claude"], uuid: uuidDeProva("b"), entorn: [OrdreClaude.variableMarca: "pestanya-1"])
        }
        let lectura = try e.lector.llegeix()
        let totes = lectura.sessionsSensePestanya
            + lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude)
        let perPid = Dictionary(uniqueKeysWithValues: totes.map { ($0.pid, $0.marca) })
        #expect(perPid == [101: nil, 103: marca, 106: marca, 201: nil])

        // `llegeix --json` la torna igual.
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        let descodificador = JSONDecoder()
        descodificador.dateDecodingStrategy = .iso8601
        #expect(try descodificador.decode(LecturaWarp.self, from: codificador.encode(lectura)) == lectura)
        #expect(Informe.text(lectura, inici: e.inici).contains("pestanya 9f4b2c7e"))
    }

    /// Les sessions en segon pla es llegeixen, però no es lliguen a cap pane (hereten el del dimoni) ni avisen.
    @Test func lesSessionsEnSegonPla() throws {
        let e = try LectorTests.Escenari { processos, sessions in
            // Un dimoni que ja ha acabat, i un fitxer `bg` amb el pid d'un altre programa: no compten.
            try escriuSessio(a: sessions, pid: 301, sessionId: "s-301", cwd: "/tmp", kind: "daemon-worker")
            try escriuSessio(a: sessions, pid: 302, sessionId: "s-302", cwd: "/tmp", kind: "bg")
            processos.processos[302] = (InfoProces(executable: "/usr/bin/python3", argv: ["python3"]), 1)
            try escriuSessio(a: sessions, pid: 303, sessionId: "s-303", cwd: "/tmp", kind: "daemon-worker")
            processos.claude(303, argv: ["claude", "daemon"], uuid: nil, dinsDeWarp: false)
        }
        let lectura = try e.lector.llegeix()
        #expect(lectura.sessionsNoInteractives == [
            SessioViva(pid: 102, sessionId: "s-102", tipus: "bg", carpeta: e.projecteB),
            SessioViva(pid: 303, sessionId: "s-303", tipus: "daemon-worker", carpeta: Rutes.canonica("/tmp")),
        ])
        #expect(lectura.finestres[0].pestanyes[0].panes[0].claude?.pid == 101)
        #expect(lectura.avisos.count == 3, "\(lectura.avisos)")
        #expect(Informe.text(lectura, inici: e.inici).contains("Sessions de Claude en segon pla: 2 (bg i daemon-worker)."))
    }
}

@Suite struct WarpObertTests {
    /// Amb l'app de Warp i el seu `terminal-server` (`ProcessosFalsos.ambWarp`): obert.
    @Test func ambLAppEsObert() throws {
        #expect(ProcessosFalsos.ambWarp().warpObert(executable: ProcessosFalsos.executableWarp))
        let e = try LectorTests.Escenari()
        let lectura = try e.lector.llegeix()
        #expect(lectura.warpObert == true)
        #expect(Informe.text(lectura, inici: e.inici).contains("Warp és obert."))
    }

    /// Només el `terminal-server`, el CLI (amb arguments) o una còpia que no és la d'Aplicacions: tancat.
    @Test func senseLAppEsTancat() throws {
        var nomesServidor = ProcessosFalsos.ambWarp()
        nomesServidor.processos[40] = nil
        let executable = ProcessosFalsos.executableWarp
        var cli = nomesServidor
        cli.processos[70] = (InfoProces(executable: executable, argv: [executable, "--help"]), 60)
        cli.processos[71] = (InfoProces(executable: executable, argv: [executable, "agent", "list"]), 60)
        var copia = nomesServidor
        copia.processos[72] = (InfoProces(executable: "/Users/prova/Downloads/Warp.app/Contents/MacOS/stable",
                                          argv: ["/Users/prova/Downloads/Warp.app/Contents/MacOS/stable"]), 1)
        for processos in [nomesServidor, cli, copia, ProcessosFalsos()] {
            #expect(!processos.warpObert(executable: ProcessosFalsos.executableWarp))
        }
        let e = try LectorTests.Escenari { processos, _ in processos.processos[40] = nil }
        let lectura = try e.lector.llegeix()
        #expect(lectura.warpObert == false)
        #expect(Informe.text(lectura, inici: e.inici).contains("Warp és tancat: són les finestres que restaurarà"))
    }

    /// Una lectura feta sense mirar-ho no ho diu.
    @Test func senseMirarNoDiuRes() {
        let lectura = LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: [])
        #expect(lectura.warpObert == nil)
        #expect(!Informe.text(lectura, inici: "/Users/prova").contains("Warp és"))
    }
}

@Suite struct LectorTranscripcionsTests {
    private let id1 = "11111111-1111-4111-8111-111111111111"
    private let id2 = "22222222-2222-4222-8222-222222222222"
    private let id3 = "33333333-3333-4333-8333-333333333333"
    private let id4 = "44444444-4444-4444-8444-444444444444"

    /// `projects/` amb un projecte real, un enllaç a un projecte d'abans (com quan s'ha mogut la carpeta dels repos), una
    /// conversa en un altre projecte (també vista per un enllaç), i una altra en dos projectes.
    private func escenari() throws -> (CarpetaTemporal, LectorTranscripcions) {
        let tmp = try CarpetaTemporal()
        let projectes = try tmp.carpeta("projects")
        func transcripcio(_ projecte: String, _ id: String) throws {
            try tmp.carpeta("projects/\(projecte)")
            try Data("{}\n".utf8).write(to: tmp.url("projects/\(projecte)/\(id).jsonl"))
        }
        try transcripcio("-x-repo-a", id1)
        try transcripcio("-x-vell-b", id2)
        try FileManager.default.createSymbolicLink(atPath: projectes + "/-x-repo-b", withDestinationPath: "-x-vell-b")
        try transcripcio("-x-altre", id3)
        try FileManager.default.createSymbolicLink(atPath: projectes + "/-x-enllac", withDestinationPath: "-x-altre")
        try transcripcio("-x-altre2", id4)
        try transcripcio("-x-altre3", id4)
        // Un fitxer amb nom de projecte: no és un projecte.
        try Data().write(to: tmp.url("projects/-x-fitxer"))
        return (tmp, LectorTranscripcions(carpeta: URL(filePath: projectes)))
    }

    @Test func onEsLaConversa() throws {
        let (_, lector) = try escenari()
        #expect(lector.on(sessio: id1, carpeta: "/x/repo-a") == .aLaCarpeta)
        // Pel projecte que és un enllaç, com Claude.
        #expect(lector.on(sessio: id2, carpeta: "/x/repo-b") == .aLaCarpeta)
        // En un altre projecte: l'enllaç no hi compta dues vegades.
        #expect(lector.on(sessio: id3, carpeta: "/x/repo-a") == .altres(["-x-altre"]))
        #expect(lector.on(sessio: id4, carpeta: "/x/repo-a") == .altres(["-x-altre2", "-x-altre3"]))
        #expect(lector.on(sessio: "55555555-5555-4555-8555-555555555555", carpeta: "/x/repo-a") == .enlloc)
    }

    // MARK: Les converses recents d'una carpeta (D7)

    private static let usuari = #"{"type":"user","entrypoint":"cli","message":{"role":"user","content":"hola"}}"#
    private static let resposta = #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}"#
    private static let conversa = usuari + "\n" + resposta + "\n"

    /// Una conversa amb l'últim missatge del dia `data`. Amb `feina`, com les línies d'una feina en segon pla.
    private static func conversa(a data: String, feina: Bool = false) -> String {
        let tipus = feina ? #""sessionKind":"bg","# : ""
        return #"{"type":"user","entrypoint":"cli","# + tipus + #""timestamp":"\#(data)T08:00:00.000Z","message":{}}"# + "\n"
            + #"{"message":{"model":"claude-opus-5-5"},"# + tipus + #""type":"assistant","timestamp":"\#(data)T09:00:00.000Z"}"# + "\n"
    }

    private static func dia(_ data: String) throws -> Date {
        try Date(data + "T09:00:00.000Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private func primera(_ tmp: CarpetaTemporal) -> LectorTranscripcions.Recent? {
        LectorTranscripcions(carpeta: tmp.url("projects")).recents(carpeta: "/x/repo").first
    }

    /// Escriu una transcripció a `/x/repo`, amb la data de fa `fa` segons.
    private func transcripcio(_ tmp: CarpetaTemporal, _ id: String, _ text: String, fa: TimeInterval, projecte: String = "-x-repo") throws {
        try tmp.carpeta("projects/\(projecte)")
        let fitxer = tmp.url("projects/\(projecte)/\(id).jsonl")
        try Data(text.utf8).write(to: fitxer)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_793_750_400 - fa)], ofItemAtPath: fitxer.path)
    }

    private func recents(_ tmp: CarpetaTemporal, carpeta: String = "/x/repo", maxim: Int = 8) -> [String] {
        LectorTranscripcions(carpeta: tmp.url("projects")).recents(carpeta: carpeta, maxim: maxim).map(\.id)
    }

    /// De la més recent a la més antiga, amb la data de l'últim canvi; `maxim` les limita.
    @Test func recentsPerOrdre() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, Self.conversa, fa: 300)
        try transcripcio(tmp, id2, Self.conversa, fa: 100)
        try transcripcio(tmp, id3, Self.conversa, fa: 200)
        #expect(recents(tmp) == [id2, id3, id1])
        #expect(recents(tmp, maxim: 2) == [id2, id3])
        let primera = LectorTranscripcions(carpeta: tmp.url("projects")).recents(carpeta: "/x/repo").first
        #expect(primera == LectorTranscripcions.Recent(id: id2, darrerMissatge: Date(timeIntervalSince1970: 1_793_750_400 - 100)))
        #expect(recents(tmp, carpeta: "/x/altra").isEmpty, "només les de la carpeta")
    }

    /// El cas real (05/11/2026): una bona part de les transcripcions eren de `claude -p`, que no són converses del terminal.
    @Test func recentsNomesLesDelTerminal() throws {
        let tmp = try CarpetaTemporal()
        let meta = #"{"type":"user","isMeta":true,"entrypoint":"cli","message":{"content":"<local-command>"}}"#
        try transcripcio(tmp, id1, Self.conversa, fa: 500)
        // Més recents, però cap no compta: `claude -p`, Claude Desktop, sense missatges, i només amb un missatge del sistema.
        try transcripcio(tmp, id2, #"{"type":"user","entrypoint":"sdk-cli","message":{}}"# + "\n", fa: 400)
        try transcripcio(tmp, id3, #"{"type":"user","entrypoint":"claude-desktop","message":{}}"# + "\n", fa: 300)
        try transcripcio(tmp, id4, #"{"type":"summary","summary":"x"}"# + "\n", fa: 200)
        try transcripcio(tmp, "55555555-5555-4555-8555-555555555555", meta + "\n", fa: 100)
        // Un missatge dins d'un text no és un missatge: les cometes hi van escapades.
        try transcripcio(tmp, "66666666-6666-4666-8666-666666666666",
                         #"{"type":"assistant","text":"{\"type\":\"user\"}"}"# + "\n", fa: 50)
        // Un nom que no és un UUID (l'`agent-…` de versions antigues), i un fitxer d'un altre tipus.
        try transcripcio(tmp, "agent-abc", Self.conversa, fa: 10)
        try Data(Self.usuari.utf8).write(to: tmp.url("projects/-x-repo/\(id2).txt"))
        #expect(recents(tmp) == [id1])
    }

    /// Sense `entrypoint` (versions antigues) compta, i sense salt de línia final també. El missatge pot ser lluny del
    /// principi: el 05/11/2026, el més tardà era als 894 KB.
    @Test func recentsAmbElMissatgeLluny() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, #"{"type":"user","message":{}}"# + "\n" + Self.resposta, fa: 100)
        let llarga = #"{"type":"attachment","text":""# + String(repeating: "x", count: 900 * 1024) + "\"}\n"
        try transcripcio(tmp, id2, llarga + Self.conversa, fa: 50)
        #expect(recents(tmp) == [id2, id1])
    }

    /// Sense cap resposta de Claude no és una conversa. El cas real: en una pestanya, un sol missatge, «cd ..», guanyava la
    /// conversa de debò. La resposta que escriu Claude Code sense preguntar al model (un error de l'API) no compta.
    @Test func recentsNomesAmbResposta() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, Self.conversa, fa: 300)
        try transcripcio(tmp, id2, Self.usuari + "\n", fa: 100)
        try transcripcio(tmp, id3, Self.usuari + "\n" + #"{"type":"assistant","message":{"model":"<synthetic>"}}"# + "\n", fa: 50)
        #expect(recents(tmp) == [id1])
    }

    /// Si la resposta queda més enllà del que es llegeix, compta: no es pot dir que no n'hi hagi.
    @Test func recentsAmbLaRespostaMoltLluny() throws {
        let tmp = try CarpetaTemporal()
        let llarga = #"{"type":"attachment","text":""# + String(repeating: "x", count: LectorTranscripcions.maximLectura) + "\"}\n"
        try transcripcio(tmp, id1, Self.usuari + "\n" + llarga + Self.resposta + "\n", fa: 100)
        #expect(recents(tmp) == [id1])
    }

    /// Compta l'últim missatge, no la data del fitxer, que Claude també escriu en tancar-se. El cas real: una pestanya deia
    /// «fa 4 dies», i l'últim missatge era de mesos abans. Amb `maxim` també: el fitxer més nou pot no ser la conversa més recent.
    @Test func recentsPerLUltimMissatge() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, Self.conversa(a: "2026-08-01") + #"{"type":"cost-state","cost":1}"# + "\n", fa: 10)
        try transcripcio(tmp, id2, Self.conversa(a: "2026-10-24"), fa: 100)
        #expect(recents(tmp) == [id2, id1])
        #expect(recents(tmp, maxim: 1) == [id2])
        #expect(try primera(tmp)?.darrerMissatge == Self.dia("2026-10-24"))
    }

    /// Les línies d'una feina en segon pla no compten. El cas real: en una pestanya, una feina posterior hauria passat davant de la
    /// conversa de la pestanya. Una feina de principi a fi no és cap conversa del terminal.
    @Test func lesLiniesDUnaFeinaNoCompten() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, Self.conversa(a: "2026-10-12") + Self.conversa(a: "2026-10-28", feina: true), fa: 50)
        try transcripcio(tmp, id2, Self.conversa(a: "2026-10-24"), fa: 100)
        try transcripcio(tmp, id3, Self.conversa(a: "2026-11-01", feina: true), fa: 10)
        #expect(recents(tmp) == [id2, id1])
        #expect(try LectorTranscripcions(carpeta: tmp.url("projects")).recents(carpeta: "/x/repo").last?.darrerMissatge == Self.dia("2026-10-12"))
    }

    /// Una feina més llarga del que es llegeix no semblaria d'ara mateix. El cas real: una de viva, de 10 MB: en
    /// aturar-se hauria guanyat la conversa de la pestanya. També si la conversa va començar al terminal.
    @Test func unaFeinaLlargaNoSemblaRecent() throws {
        let tmp = try CarpetaTemporal()
        let linia = #"{"type":"assistant","sessionKind":"bg","timestamp":"2026-11-01T00:00:00.000Z","text":""#
            + String(repeating: "x", count: 1024 * 1024) + "\"}\n"
        let feina = String(repeating: linia, count: 5)
        try transcripcio(tmp, id1, Self.conversa(a: "2026-10-12") + feina, fa: 10)
        try transcripcio(tmp, id2, Self.conversa(a: "2026-10-24"), fa: 100)
        try transcripcio(tmp, id3, Self.conversa(a: "2026-11-01", feina: true) + feina, fa: 5)
        #expect(recents(tmp) == [id2, id1])
    }

    /// L'últim missatge es busca des del final: per sobre de línies grans, que no caben en un sol tros, i encara que ell mateix
    /// sigui gran o no tingui salt de línia. Els del sistema (`isMeta`) no compten.
    @Test func elDarrerMissatgeDesDelFinal() throws {
        let tmp = try CarpetaTemporal()
        let meta = #"{"type":"user","isMeta":true,"timestamp":"2026-11-01T00:00:00.000Z","message":{}}"# + "\n"
        let gran = #"{"type":"attachment","text":""# + String(repeating: "x", count: 900 * 1024) + "\"}\n"
        try transcripcio(tmp, id1, Self.conversa(a: "2026-10-01") + meta + gran, fa: 10)
        #expect(try primera(tmp)?.darrerMissatge == Self.dia("2026-10-01"))

        let missatgeGran = #"{"type":"assistant","message":{"text":""# + String(repeating: "x", count: 200 * 1024)
            + #""},"timestamp":"2026-10-02T09:00:00.000Z"}"#
        try transcripcio(tmp, id1, Self.usuari + "\n" + missatgeGran, fa: 10)
        #expect(try primera(tmp)?.darrerMissatge == Self.dia("2026-10-02"))
    }

    /// Si no se sap (el missatge és més lluny del que es llegeix, o la seva data no s'entén), la del fitxer.
    @Test func siNoEsSapLaDataDelFitxer() throws {
        let tmp = try CarpetaTemporal()
        let dataFitxer = Date(timeIntervalSince1970: 1_793_750_400 - 10)
        let llarga = #"{"type":"attachment","text":""# + String(repeating: "x", count: LectorTranscripcions.maximLectura) + "\"}\n"
        try transcripcio(tmp, id1, Self.conversa(a: "2026-10-01") + llarga, fa: 10)
        #expect(primera(tmp)?.darrerMissatge == dataFitxer)

        try transcripcio(tmp, id1, Self.usuari + "\n" + #"{"type":"assistant","timestamp":"ahir"}"# + "\n", fa: 10)
        #expect(primera(tmp)?.darrerMissatge == dataFitxer)
    }

    /// El projecte pot ser un enllaç, com a `on` (passa quan s'ha mogut la carpeta dels repos).
    @Test func recentsPelProjecteQueEsUnEnllac() throws {
        let tmp = try CarpetaTemporal()
        try transcripcio(tmp, id1, Self.conversa, fa: 100, projecte: "-x-vell")
        try FileManager.default.createSymbolicLink(atPath: tmp.url("projects/-x-repo").path, withDestinationPath: "-x-vell")
        #expect(recents(tmp) == [id1])
    }

    /// Un id que no és un UUID no es busca: no pot sortir de la carpeta ni trobar res que no sigui una transcripció.
    @Test(arguments: ["", "s-101", "../-x-repo-a/11111111-1111-4111-8111-111111111111", "*", "11111111-1111-4111-8111-111111111111.jsonl"])
    func unIdQueNoEsUUIDNoEsBusca(id: String) throws {
        let (_, lector) = try escenari()
        #expect(lector.on(sessio: id, carpeta: "/x/repo-a") == .enlloc)
    }

    @Test func senseCarpetaDeProjectesEnlloc() throws {
        let tmp = try CarpetaTemporal()
        #expect(LectorTranscripcions(carpeta: tmp.url("no-hi-es")).on(sessio: id1, carpeta: "/x") == .enlloc)
    }

    @Test func elNomDelProjecte() {
        #expect(LectorTranscripcions.projecte("/Users/nom.cognom/GitHub/empresa/botiga") == "-Users-nom-cognom-GitHub-empresa-botiga")
        #expect(LectorTranscripcions.projecte("/a_b.c d/è") == "-a-b-c-d--")
        // Claude compta en UTF-16: un emoji són dues unitats, i dos guions.
        #expect(LectorTranscripcions.projecte("/🙂") == "---")
        #expect(LectorTranscripcions.projecte("/" + String(repeating: "a", count: 199))?.count == 200)
        #expect(LectorTranscripcions.projecte("/" + String(repeating: "a", count: 200)) == nil)
    }

    /// Amb una carpeta massa llarga, el nom del projecte no es pot calcular: es busca a tots.
    @Test func ambUnaCarpetaMassaLlargaEsBuscaATots() throws {
        let (_, lector) = try escenari()
        let llarga = "/" + String(repeating: "a", count: 250)
        #expect(lector.on(sessio: id1, carpeta: llarga) == .altres(["-x-repo-a"]))
    }
}

@Suite struct LectorConfiancaTests {
    private func escenari(_ json: String? = nil) throws -> (CarpetaTemporal, String, LectorConfianca) {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        let repo = try tmp.carpeta("inici/repo")
        try tmp.carpeta("inici/no")
        try tmp.carpeta("inici/pare/fill/net")
        try tmp.carpeta("real")
        try FileManager.default.createSymbolicLink(atPath: tmp.ruta + "/enllac", withDestinationPath: tmp.ruta + "/real")
        let text = json ?? """
            {"numStartups": 3, "projects": {
              "\(repo)": {"hasTrustDialogAccepted": true, "allowedTools": []},
              "\(inici)/no": {"hasTrustDialogAccepted": false},
              "\(inici)//pare/": {"hasTrustDialogAccepted": true},
              "\(tmp.ruta)/enllac": {"hasTrustDialogAccepted": true},
              "\(inici)/malmes": "sí"
            }}
            """
        try Data(text.utf8).write(to: tmp.url("claude.json"))
        return (tmp, inici, LectorConfianca(ruta: tmp.url("claude.json")))
    }

    @Test func laCarpetaOUnaDeLesSevesCarpetesPare() throws {
        let (tmp, inici, lector) = try escenari()
        let confianca = try #require(lector.llegeix(inici: inici))
        #expect(confianca.confiada(inici + "/repo"))
        #expect(confianca.confiada(inici + "/repo/sub"))
        #expect(confianca.confiada(inici + "/pare/fill/net"), "de la carpeta pare, escrita amb barres de més")
        #expect(!confianca.confiada(inici + "/no"))
        #expect(!confianca.confiada(tmp.ruta))
        // Claude compara la ruta tal com és: la confiança d'un enllaç no compta per a la carpeta real, ni tampoc si la
        // pestanya apunta a l'enllaç, perquè Claude corre a la carpeta real (el 05/11/2026, la majoria de les pestanyes d'una finestra).
        #expect(!confianca.confiada(tmp.ruta + "/real"))
        #expect(!confianca.confiada(tmp.ruta + "/enllac"))
    }

    /// Claude no desa mai la confiança de la carpeta d'inici, i sempre hi pregunta: encara que el fitxer la portés.
    @Test func aLaCarpetaDIniciSemprePregunta() throws {
        let (_, inici, lector) = try escenari()
        #expect(try #require(lector.llegeix(inici: inici)).confiada(inici) == false)
        let tmp = try CarpetaTemporal()
        let altre = try tmp.carpeta("inici")
        try Data(#"{"projects": {"\#(altre)": {"hasTrustDialogAccepted": true}}}"#.utf8).write(to: tmp.url("claude.json"))
        #expect(try #require(LectorConfianca(ruta: tmp.url("claude.json")).llegeix(inici: altre)).confiada(altre) == false)
    }

    /// Si el fitxer no es pot llegir o no és el que s'espera, no se sap (i el full no avisa).
    @Test(arguments: [nil, "no és json", "[]", #"{"projects": []}"#, #"{"altres": {}}"#] as [String?])
    func senseFitxerNoSeSap(json: String?) throws {
        if let json {
            let (_, inici, lector) = try escenari(json)
            #expect(lector.llegeix(inici: inici) == nil)
        } else {
            let tmp = try CarpetaTemporal()
            #expect(LectorConfianca(ruta: tmp.url("no-hi-es.json")).llegeix(inici: tmp.ruta) == nil)
        }
    }
}
