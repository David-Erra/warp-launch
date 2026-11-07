import Foundation
import Testing
@testable import WarpLaunchCore

// `estat.json` (fase 3.1, 0.17.0): el format, el magatzem i les regles que posen al dia el pane i la conversa de cada
// pestanya. Sempre en carpetes temporals i amb lectures fictícies.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)  // 04/11/2026 00:00:00Z
private let dia: TimeInterval = 24 * 3600

private func pane(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }

/// La configuració de les proves: T1, T2 i T3 en una finestra.
private let configuracio = Configuracio(plantilla: .habituals, finestres: [
    Finestra(id: id(100), nom: "a", pestanyes: [1, 2, 3].map {
        Pestanya(id: id($0), titol: "T\($0)", carpeta: "/x/t\($0)", claude: .habituals)
    }),
])

/// T1 al pane «a» amb la conversa s1; T2 al pane «b» sense conversa; T3 sense lligam.
private let estatInicial = EstatApp(pestanyes: [
    id(1): VincleEstat(pane: pane("a"), sessio: "s1", carpetaSessio: "/x/t1", origen: .importacio, vista: t0),
    id(2): VincleEstat(pane: pane("b"), origen: .importacio, vista: t0),
])

/// Una sessió interactiva viva.
private func sessio(_ sessionId: String, pane: String?, marca: UUID? = nil, dinsDeWarp: Bool = true,
                    carpeta: String = "/x/t1", iniciada: Date = t0) -> SessioClaude {
    SessioClaude(pid: Int32.random(in: 1000...9999), sessionId: sessionId, carpeta: carpeta, iniciada: iniciada,
                 ordre: ["claude"], opcions: OpcionsClaude(), paneUUID: pane, dinsDeWarp: dinsDeWarp, marca: marca)
}

/// Una lectura on les sessions no són a cap pestanya de la base (com just després d'obrir): les regles no en depenen.
private func lectura(_ sessions: [SessioClaude]) -> LecturaWarp {
    LecturaWarp(finestres: [], sessionsSensePestanya: sessions, avisos: [])
}

@Suite struct EstatAppTests {
    // MARK: El fitxer

    @Test func anadaITornada() throws {
        var estat = estatInicial
        estat.desa(Llancament(id: id(500), fitxer: "warp-launch-x.yaml", mida: 812, creat: t0 + 0.7, finestra: id(100),
                              pestanyes: [id(1), id(2)], estat: .confirmat, esborrat: true, segons: 0.8))
        let json = try estat.json(generador: "Warp Launch 0.17.0")
        #expect(try EstatApp.llegeix(json) == estat)
        #expect(String(decoding: json, as: UTF8.self) == """
            {
              "generador" : "Warp Launch 0.17.0",
              "llancaments" : [
                {
                  "creat" : "2026-11-04T00:00:00Z",
                  "esborrat" : true,
                  "estat" : "confirmat",
                  "finestra" : "00000000-0000-0000-0000-000000000100",
                  "fitxer" : "warp-launch-x.yaml",
                  "id" : "00000000-0000-0000-0000-000000000500",
                  "mida" : 812,
                  "pestanyes" : [
                    "00000000-0000-0000-0000-000000000001",
                    "00000000-0000-0000-0000-000000000002"
                  ],
                  "segons" : 0.8
                }
              ],
              "pestanyes" : {
                "00000000-0000-0000-0000-000000000001" : {
                  "carpetaSessio" : "/x/t1",
                  "origen" : "importacio",
                  "pane" : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "sessio" : "s1",
                  "vista" : "2026-11-04T00:00:00Z"
                },
                "00000000-0000-0000-0000-000000000002" : {
                  "origen" : "importacio",
                  "pane" : "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "vista" : "2026-11-04T00:00:00Z"
                }
              },
              "versio" : 1
            }

            """)
    }

    /// Les dates es guarden a segons sencers: el JSON no té fraccions, i tornat a llegir ha de donar el mateix.
    @Test func lesDatesSonASegonsSencers() throws {
        let vincle = VincleEstat(origen: .marca, vista: t0 + 0.999, foraDesDe: t0 + 1.5)
        #expect(vincle.vista == t0 && vincle.foraDesDe == t0 + 1)
        let estat = EstatApp(pestanyes: [id(1): vincle])
        #expect(try EstatApp.llegeix(estat.json()) == estat)
    }

    @Test func elsLlancamentsEsGuardenVint() {
        var estat = EstatApp()
        for n in 1...25 {
            estat.desa(Llancament(id: id(n), fitxer: "f", mida: 1, creat: t0, finestra: id(100), pestanyes: [],
                                  estat: .pendent))
        }
        #expect(estat.llancaments.map(\.id) == (6...25).map(id))
        estat.desa(Llancament(id: id(25), fitxer: "f", mida: 1, creat: t0, finestra: id(100), pestanyes: [],
                              estat: .confirmat, esborrat: true))
        #expect(estat.llancaments.count == 20)
        #expect(estat.llancaments.last?.estat == .confirmat)
    }

    // MARK: El magatzem

    @Test func senseFitxerEsBuitINoEsCrea() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemEstat(carpeta: tmp.url("config"))
        #expect(try magatzem.carrega() == EstatApp())
        #expect(!FileManager.default.fileExists(atPath: tmp.url("config").path))
    }

    @Test func desaITornaALlegir() throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemEstat(carpeta: tmp.url("config"))
        try magatzem.desa(estatInicial)
        #expect(try magatzem.carrega() == estatInicial)
        let atributs = try FileManager.default.attributesOfItem(atPath: magatzem.fitxer.path)
        #expect(atributs[.posixPermissions] as? Int == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url("config").path) == ["estat.json"])
    }

    /// Una versió més nova o un fitxer malmès no es trepitgen mai: l'app no hi escriu (ni obrirà res).
    @Test(arguments: [
        (#"{"versio": 2, "pestanyes": {}, "llancaments": [], "nou": true}"#, EstatApp.ErrorEstat.versioMesNova(2)),
        ("{no és json", .format("no és JSON o no té «versio»")),
    ])
    func noEsTrepitja(text: String, error: EstatApp.ErrorEstat) throws {
        let tmp = try CarpetaTemporal()
        let magatzem = MagatzemEstat(carpeta: URL(filePath: tmp.ruta))
        try Data(text.utf8).write(to: magatzem.fitxer)
        #expect(throws: error) { try magatzem.carrega() }
        #expect(throws: error) { try magatzem.desa(estatInicial) }
        #expect(try Data(contentsOf: magatzem.fitxer) == Data(text.utf8))
    }

    @Test func unIdDePestanyaQueNoEsUUIDEsUnError() {
        let json = #"{"versio": 1, "pestanyes": {"x": {"origen": "marca", "vista": "2026-11-04T00:00:00Z"}}, "llancaments": []}"#
        #expect(throws: EstatApp.ErrorEstat.format("«x» no és l'id d'una pestanya")) { try EstatApp.llegeix(Data(json.utf8)) }
    }

    // MARK: Les regles

    /// `/clear` (o `/resume` fet a mà): el mateix pane amb una conversa nova.
    @Test func unClearCanviaLaConversa() {
        let ara = t0 + 3600.4
        let nou = ActualitzaEstat.amb(lectura([sessio("s2", pane: pane("a"))]), configuracio: configuracio,
                                      estat: estatInicial, ara: ara)
        #expect(nou.pestanyes[id(1)] == VincleEstat(pane: pane("a"), sessio: "s2", carpetaSessio: "/x/t1", origen: .pane,
                                                     vista: t0 + 3600))
        #expect(nou.pestanyes[id(2)] == estatInicial.pestanyes[id(2)])
    }

    /// Si Claude surt (o no hi ha cap sessió), la conversa es manté, i no canvia res.
    @Test func siClaudeSurtNoCanviaRes() {
        #expect(ActualitzaEstat.amb(lectura([]), configuracio: configuracio, estat: estatInicial, ara: t0 + 60) == estatInicial)
        // La mateixa sessió una altra vegada: tampoc.
        let un = ActualitzaEstat.amb(lectura([sessio("s1", pane: pane("a"))]), configuracio: configuracio,
                                     estat: estatInicial, ara: t0 + 60)
        #expect(un == estatInicial)
    }

    /// La marca dona a la pestanya la seva sessió i el pane, encara que no en tingués cap.
    @Test func laMarcaDonaElPaneILaConversa() {
        let nou = ActualitzaEstat.amb(lectura([sessio("s3", pane: pane("c"), marca: id(3), carpeta: "/x/t3")]),
                                      configuracio: configuracio, estat: estatInicial, ara: t0 + 10)
        #expect(nou.pestanyes[id(3)] == VincleEstat(pane: pane("c"), sessio: "s3", carpetaSessio: "/x/t3", origen: .marca,
                                                     vista: t0 + 10))
        // Fora de Warp: la conversa sí, el pane no (es manté el que hi havia).
        let fora = ActualitzaEstat.amb(lectura([sessio("s4", pane: pane("z"), marca: id(2), dinsDeWarp: false)]),
                                       configuracio: configuracio, estat: estatInicial, ara: t0 + 10)
        #expect(fora.pestanyes[id(2)]?.pane == pane("b"))
        #expect(fora.pestanyes[id(2)]?.sessio == "s4")
    }

    /// Una marca d'una pestanya que no és d'aquesta configuració, o una sessió fora de Warp sense marca: res.
    @Test func elQueNoEsDeCapPestanyaNoCompta() {
        let sessions = [sessio("s5", pane: pane("z"), marca: id(99)), sessio("s6", pane: pane("a"), dinsDeWarp: false),
                        sessio("s7", pane: pane("q"))]
        #expect(ActualitzaEstat.amb(lectura(sessions), configuracio: configuracio, estat: estatInicial, ara: t0 + 10)
            == estatInicial)
    }

    /// Una marca d'una altra configuració en un pane d'aquesta: la sessió és d'aquell pane.
    @Test func unaMarcaDesconegudaAlPaneDUnaPestanya() {
        let nou = ActualitzaEstat.amb(lectura([sessio("s8", pane: pane("b"), marca: id(99))]), configuracio: configuracio,
                                      estat: estatInicial, ara: t0 + 10)
        #expect(nou.pestanyes[id(2)]?.sessio == "s8")
        #expect(nou.pestanyes[id(99)] == nil)
    }

    /// Dues pestanyes amb el mateix pane: el conserva la que ha canviat més tard.
    @Test func unPaneUnaPestanya() {
        let nou = ActualitzaEstat.amb(lectura([sessio("s9", pane: pane("a"), marca: id(3))]), configuracio: configuracio,
                                      estat: estatInicial, ara: t0 + 10)
        #expect(nou.pestanyes[id(3)]?.pane == pane("a"))
        #expect(nou.pestanyes[id(1)]?.pane == nil)
        #expect(nou.pestanyes[id(1)]?.sessio == "s1", "la conversa no es perd")
    }

    /// Una pestanya esborrada es guarda 30 dies (pel Desfés); si torna, es guarda per sempre.
    @Test func foraDeLaConfiguracio() {
        var sense = configuracio
        sense.finestres[0].pestanyes.removeFirst()  // T1
        let esborrada = ActualitzaEstat.amb(lectura([]), configuracio: sense, estat: estatInicial, ara: t0 + 100)
        #expect(esborrada.pestanyes[id(1)]?.foraDesDe == t0 + 100)
        let encara = ActualitzaEstat.amb(lectura([]), configuracio: sense, estat: esborrada, ara: t0 + 100 + 29 * dia)
        #expect(encara == esborrada)
        let tornada = ActualitzaEstat.amb(lectura([]), configuracio: configuracio, estat: encara, ara: t0 + 100 + 29 * dia)
        #expect(tornada == estatInicial)
        let oblidada = ActualitzaEstat.amb(lectura([]), configuracio: sense, estat: esborrada, ara: t0 + 101 + 30 * dia)
        #expect(oblidada.pestanyes[id(1)] == nil)
        #expect(oblidada.pestanyes[id(2)] == estatInicial.pestanyes[id(2)])
    }

    /// Després de tornar a importar, la pestanya M (oberta per l'app, amb la marca) és N, amb el mateix pane. Un `/clear`
    /// en aquell Claude (la marca de M, una conversa nova) ha d'arribar a N; i M el segueix, pel Desfés (revisió de la
    /// 0.20.0).
    @Test func laMarcaDUnaEntradaDeForaArribaALaPestanyaDelPane() {
        var reimportada = configuracio
        reimportada.finestres[0].pestanyes[0].id = id(21)  // T1 ara és N
        var estat = ActualitzaEstat.vincula([id(21): VincleImportat(pane: pane("a"), sessio: "s1", carpetaSessio: "/x/t1")],
                                            estat: estatInicial, ara: t0 + 5)
        estat = ActualitzaEstat.amb(lectura([]), configuracio: reimportada, estat: estat, ara: t0 + 6)
        #expect(estat.pestanyes[id(1)]?.foraDesDe == t0 + 6)
        let nou = ActualitzaEstat.amb(lectura([sessio("s-clear", pane: pane("a"), marca: id(1))]),
                                      configuracio: reimportada, estat: estat, ara: t0 + 10)
        #expect(nou.pestanyes[id(21)]?.sessio == "s-clear")
        #expect(nou.pestanyes[id(21)]?.pane == pane("a"))
        #expect(nou.pestanyes[id(1)]?.sessio == "s-clear")
    }

    /// Tornar a importar: una pestanya nova sense sessió viva hereta la conversa de l'entrada amb el mateix pane.
    @Test func tornarAImportarHeretaLaConversa() {
        let nou = ActualitzaEstat.vincula([
            id(11): VincleImportat(pane: pane("a")),
            id(12): VincleImportat(pane: pane("x"), sessio: "s12", carpetaSessio: "/x/t12"),
            id(13): VincleImportat(pane: pane("b")),
        ], estat: estatInicial, ara: t0 + 5)
        #expect(nou.pestanyes[id(11)] == VincleEstat(pane: pane("a"), sessio: "s1", carpetaSessio: "/x/t1",
                                                      origen: .importacio, vista: t0 + 5))
        #expect(nou.pestanyes[id(12)]?.sessio == "s12")
        #expect(nou.pestanyes[id(13)]?.sessio == nil)
        // Les entrades velles es queden (el Desfés les pot tornar a fer servir).
        #expect(nou.pestanyes[id(1)] == estatInicial.pestanyes[id(1)])
    }
}
