import Foundation
import Testing
@testable import WarpLaunchCore

// Format v1 de la configuració (docs/disseny.md, apartat 2). Tot amb dades fictícies; cap prova toca el disc.

/// UUID fix per a les proves: `uuid(7)` és `00000000-0000-0000-0000-000000000007`.
func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

/// Generador determinista d'id, a partir de 900. Amb un pany, perquè el CLI el vol `@Sendable`.
final class IdsDeProva: @unchecked Sendable {
    private let pany = NSLock()
    private var comptador = 900
    var seguent: Int { pany.withLock { comptador } }
    func nou() -> UUID {
        pany.withLock {
            defer { comptador += 1 }
            return uuid(comptador)
        }
    }
}

private let inici = "/Users/prova"

private func llegeix(_ json: String, ids: IdsDeProva = IdsDeProva()) throws(ErrorConfiguracio) -> ConfiguracioLlegida {
    try Configuracio.llegeix(Data(json.utf8), inici: inici, nouId: ids.nou)
}

private func error(_ json: String) -> ErrorConfiguracio? {
    do {
        _ = try llegeix(json)
        return nil
    } catch {
        return error
    }
}

/// Configuració fixa que fa servir la prova «golden».
private let configuracioDeMostra = Configuracio(
    plantilla: .habituals,
    finestres: [
        Finestra(id: uuid(1), nom: "feina", pestanyes: [
            Pestanya(id: uuid(2), titol: "Botiga", carpeta: "/Users/prova/GitHub/empresa/botiga", claude: .habituals),
            Pestanya(id: uuid(3), titol: "Suport", carpeta: "/Users/prova/GitHub/empresa/suport",
                     claude: ClaudePestanya(model: "opus", esforc: "high", ultracode: true, continua: false, nom: "suport",
                                            modePermisos: "plan", settings: #"{"outputStyle":"concise"}"#,
                                            controlRemot: "Agent web", altres: ["--verbose"])),
            Pestanya(id: uuid(4), titol: "Web Host", carpeta: "/Users/prova",
                     claude: ClaudePestanya(activat: false, esforc: "xhigh", ultracode: true, saltaPermisos: true)),
        ]),
        Finestra(id: uuid(5), nom: "buida"),
    ],
    generador: "Warp Launch 0.3.0")

private let jsonDeMostra = #"""
{
  "finestres" : [
    {
      "id" : "00000000-0000-0000-0000-000000000001",
      "nom" : "feina",
      "pestanyes" : [
        {
          "carpeta" : "/Users/prova/GitHub/empresa/botiga",
          "claude" : {
            "activat" : true,
            "continua" : true,
            "esforc" : "xhigh",
            "saltaPermisos" : true,
            "ultracode" : true
          },
          "id" : "00000000-0000-0000-0000-000000000002",
          "titol" : "Botiga"
        },
        {
          "carpeta" : "/Users/prova/GitHub/empresa/suport",
          "claude" : {
            "activat" : true,
            "altres" : [
              "--verbose"
            ],
            "continua" : false,
            "controlRemot" : "Agent web",
            "esforc" : "high",
            "modePermisos" : "plan",
            "model" : "opus",
            "nom" : "suport",
            "saltaPermisos" : false,
            "settings" : "{\"outputStyle\":\"concise\"}",
            "ultracode" : true
          },
          "id" : "00000000-0000-0000-0000-000000000003",
          "titol" : "Suport"
        },
        {
          "carpeta" : "/Users/prova",
          "claude" : {
            "activat" : false,
            "continua" : true,
            "esforc" : "xhigh",
            "saltaPermisos" : true,
            "ultracode" : true
          },
          "id" : "00000000-0000-0000-0000-000000000004",
          "titol" : "Web Host"
        }
      ]
    },
    {
      "id" : "00000000-0000-0000-0000-000000000005",
      "nom" : "buida",
      "pestanyes" : [

      ]
    }
  ],
  "generador" : "Warp Launch 0.3.0",
  "plantilla" : {
    "activat" : true,
    "continua" : true,
    "esforc" : "xhigh",
    "saltaPermisos" : true,
    "ultracode" : true
  },
  "versio" : 1
}

"""#

@Suite struct ConfiguracioTests {
    @Test func escriuExactamentElFormatV1() throws {
        let json = String(decoding: try configuracioDeMostra.json(), as: UTF8.self)
        #expect(json == jsonDeMostra)
    }

    @Test func llegirElQueEscriuDonaElMateixModelSenseAvisos() throws {
        let llegida = try Configuracio.llegeix(try configuracioDeMostra.json(), inici: inici)
        #expect(llegida.configuracio == configuracioDeMostra)
        #expect(llegida.avisos.isEmpty)
    }

    @Test func elsValorsAbsentsNoSEscriuen() throws {
        let json = String(decoding: try configuracioDeMostra.json(), as: UTF8.self)
        // La pestanya Botiga no té model, nom, mode de permisos, settings, control remot ni altres opcions.
        let botiga = try #require(json.range(of: #""titol" : "Botiga""#))
        let blocBotiga = json[json.range(of: #""carpeta" : "/Users/prova/GitHub/empresa/botiga""#)!.lowerBound ..< botiga.lowerBound]
        for clau in ["model", "nom", "modePermisos", "settings", "controlRemot", "altres"] {
            #expect(!blocBotiga.contains("\"\(clau)\""), "\(clau) no s'hauria d'escriure")
        }
    }

    @Test func lesOpcionsHabitualsSonLesDenDavid() {
        // --dangerously-skip-permissions --effort ultracode, continuant la conversa (decisió D11, 03/11/2026).
        let h = ClaudePestanya.habituals
        #expect(h.activat && h.continua && h.saltaPermisos && h.ultracode)
        #expect(h.esforc == "xhigh")
        #expect(h.model == nil && h.nom == nil && h.altres.isEmpty)
    }

    // MARK: Valors per defecte d'un fitxer escrit a mà

    @Test func unaPestanyaSenseBlocClaudeEsNomesTerminalIAvisa() throws {
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {"saltaPermisos": true},
             "finestres": [{"id": "\(uuid(1))", "nom": "a",
                            "pestanyes": [{"id": "\(uuid(2))", "titol": "t", "carpeta": "/x"}]}]}
            """)
        let pestanya = llegida.configuracio.finestres[0].pestanyes[0]
        #expect(pestanya.claude == .nomesTerminal)
        #expect(llegida.avisos == [.claudeSenseConfigurar(cami: "finestres[0].pestanyes[0]")])
    }

    @Test func unBlocClaudeParcialFaServirValorsSegurs() throws {
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {},
             "finestres": [{"id": "\(uuid(1))", "nom": "a",
                            "pestanyes": [{"id": "\(uuid(2))", "titol": "t", "carpeta": "/x",
                                           "claude": {"model": "opus"}}]}]}
            """)
        let claude = llegida.configuracio.finestres[0].pestanyes[0].claude
        #expect(claude == ClaudePestanya(activat: true, model: "opus", continua: true, saltaPermisos: false))
        #expect(llegida.configuracio.plantilla == .perOmissio)
        #expect(llegida.avisos.isEmpty)
    }

    @Test(arguments: [
        #"{"versio": 1}"#,
        #"{"versio": 1, "plantilla": {}}"#,
        #"{"versio": 1, "plantilla": {"activat": true, "esforc": "ultracode"}}"#,
        #"{"versio": 1, "finestres": [{"pestanyes": [{"carpeta": "/x"}]}]}"#,
        #"{"versio": 1, "finestres": [{"pestanyes": [{"claude": {}}]}]}"#,
        #"{"versio": 1, "finestres": [{"pestanyes": [{"claude": {"activat": true, "continua": true}}]}]}"#,
        #"{"versio": 1, "finestres": [{"pestanyes": [{"claude": {"saltaPermisos": null}}]}]}"#,
    ])
    func saltarPermisosNoSActivaMaiPerOmissio(json: String) throws {
        let c = try llegeix(json).configuracio
        #expect(!c.plantilla.saltaPermisos)
        #expect(c.finestres.flatMap(\.pestanyes).allSatisfy { !$0.claude.saltaPermisos })
    }

    @Test func senseLaPlantillaAvisaIFaServirValorsSegurs() throws {
        let llegida = try llegeix(#"{"versio": 1, "finestres": []}"#)
        #expect(llegida.configuracio.plantilla == .perOmissio)
        #expect(llegida.avisos == [.sensePlantilla])
    }

    @Test(arguments: [("ultracode", "xhigh", true), (" XHigh ", "xhigh", false), ("max", "max", false),
                      ("Ultracode", "xhigh", true), ("", nil, false)] as [(String, String?, Bool)])
    func normalitzaLEsforc(escrit: String, esforc: String?, ultracode: Bool) throws {
        let c = try llegeix(#"{"versio": 1, "plantilla": {"esforc": "\#(escrit)"}}"#).configuracio
        #expect(c.plantilla.esforc == esforc)
        #expect(c.plantilla.ultracode == ultracode)
    }

    @Test func unEsforcUltracodeAmbUltracodeFalsSegueixActivantUltracode() throws {
        let c = try llegeix(#"{"versio": 1, "plantilla": {"esforc": "ultracode", "ultracode": false}}"#).configuracio
        #expect(c.plantilla.esforc == "xhigh" && c.plantilla.ultracode)
    }

    @Test func expandeixLesCarpetesEscritesAmbTitlla() throws {
        let c = try llegeix("""
            {"versio": 1, "plantilla": {}, "finestres": [{"id": "\(uuid(1))", "nom": "a", "pestanyes": [
              {"id": "\(uuid(2))", "carpeta": "~", "claude": {}},
              {"id": "\(uuid(3))", "carpeta": "~/GitHub/x", "claude": {}},
              {"id": "\(uuid(4))", "carpeta": "/absoluta", "claude": {}},
              {"id": "\(uuid(5))", "carpeta": "~altri/x", "claude": {}}]}]}
            """).configuracio
        #expect(c.finestres[0].pestanyes.map(\.carpeta) == ["/Users/prova", "/Users/prova/GitHub/x", "/absoluta", "~altri/x"])
    }

    @Test func elsTextosBuitsEsLlegeixenComAbsents() throws {
        let c = try llegeix(#"{"versio": 1, "plantilla": {"model": "", "nom": "", "settings": "", "modePermisos": ""}}"#)
            .configuracio
        #expect(c.plantilla == .perOmissio)
    }

    @Test func elsTextosBuitsNoSEscriuen() throws {
        let c = Configuracio(plantilla: ClaudePestanya(model: "", nom: "", modePermisos: "", settings: ""))
        let json = String(decoding: try c.json(), as: UTF8.self)
        for clau in ["model", "nom", "modePermisos", "settings"] {
            #expect(!json.contains("\"\(clau)\""), "\(clau) no s'hauria d'escriure")
        }
    }

    @Test func controlRemotSenseNomEsConserva() throws {
        // "" vol dir --remote-control sense nom: no és un text buit qualsevol.
        let c = Configuracio(plantilla: ClaudePestanya(controlRemot: ""))
        #expect(String(decoding: try c.json(), as: UTF8.self).contains(#""controlRemot" : """#))
        #expect(try Configuracio.llegeix(try c.json(), inici: inici).configuracio == c)
        #expect(try llegeix(#"{"versio": 1, "plantilla": {"controlRemot": ""}}"#).configuracio.plantilla.controlRemot == "")
    }

    @Test func laPlantillaNoOmpleUnBlocParcial() throws {
        // La plantilla d'en David salta els permisos; una pestanya escrita a mà amb un bloc parcial no l'hereta.
        let llegida = try llegeix("""
            {"versio": 1,
             "plantilla": {"saltaPermisos": true, "ultracode": true, "esforc": "xhigh", "continua": false, "model": "opus"},
             "finestres": [{"id": "\(uuid(1))", "nom": "a",
                            "pestanyes": [{"id": "\(uuid(2))", "titol": "t", "carpeta": "/x", "claude": {"nom": "x"}}]}]}
            """)
        #expect(llegida.configuracio.finestres[0].pestanyes[0].claude == ClaudePestanya(nom: "x"))
        #expect(llegida.configuracio.plantilla.saltaPermisos)
    }

    // MARK: Forma canònica

    @Test func lAliesUltracodeEsDesaComXhighMesUltracode() throws {
        let json = String(decoding: try Configuracio(plantilla: ClaudePestanya(esforc: "ultracode")).json(), as: UTF8.self)
        #expect(json.contains(#""esforc" : "xhigh""#))
        #expect(json.contains(#""ultracode" : true"#))
        #expect(!json.contains(#""esforc" : "ultracode""#))
    }

    @Test func unModelNoCanonicSEscriuCanonicIEsEstable() throws {
        let c = Configuracio(plantilla: ClaudePestanya(model: "", esforc: " ULTRACODE", ultracode: false, nom: "",
                                                       settings: #"{"ultracode":true,"b":1,"a":2}"#))
        let primer = try c.json()
        let llegida = try Configuracio.llegeix(primer, inici: inici).configuracio
        #expect(llegida.plantilla == c.plantilla.normalitzada())
        #expect(llegida.plantilla == ClaudePestanya(esforc: "xhigh", ultracode: true, settings: #"{"a":2,"b":1}"#))
        #expect(try llegida.json() == primer)
    }

    @Test func ultracodeDeSettingsPassaAlSeuCamp() throws {
        let c = try llegeix(#"""
            {"versio": 1, "plantilla": {"esforc": "high", "ultracode": false, "settings": "{\"ultracode\":true}"}}
            """#).configuracio
        #expect(c.plantilla.ultracode)
        #expect(c.plantilla.settings == nil)
        #expect(c.plantilla.esforc == "high")
    }

    @Test(arguments: [
        (#"{"ultracode": false, "x": 1}"#, #"{"x":1}"#, false),
        (#"{"ultracode": true}"#, nil, true),
        (#"{"outputStyle": "concise"}"#, #"{"outputStyle": "concise"}"#, nil),
        (#"{"ultracode": "sí"}"#, #"{"ultracode": "sí"}"#, nil),
        (#"{"ultracode": 1}"#, #"{"ultracode": 1}"#, nil),
        (#"{"ultracode": true, "ultracode": false}"#, #"{"ultracode": true, "ultracode": false}"#, nil),
        ("/Users/prova/.claude/settings-prova.json", "/Users/prova/.claude/settings-prova.json", nil),
    ] as [(String, String?, Bool?)])
    func separaUltracodeDeSettings(settings: String, resta: String?, ultracode: Bool?) {
        let resultat = ClaudePestanya.separaUltracode(de: settings)
        #expect(resultat.settings == resta)
        #expect(resultat.ultracode == ultracode)
    }

    @Test func unUltracodeFalsExplicitEsQueda() {
        // Apaga l'ultracode que pugui venir de la configuració de Claude de l'usuari: no es pot perdre.
        let sense = ClaudePestanya(esforc: "high", settings: #"{"ultracode":false}"#).normalitzada()
        #expect(sense.settings == #"{"ultracode":false}"#)
        #expect(!sense.ultracode)
        // Si la pestanya ja té ultracode, el `false` no fa res a Claude, i en surt.
        let amb = ClaudePestanya(esforc: "high", ultracode: true, settings: #"{"ultracode":false,"a":1}"#).normalitzada()
        #expect(amb.settings == #"{"a":1}"#)
        #expect(amb.ultracode)
        #expect(ClaudePestanya(esforc: "ultracode", settings: #"{"ultracode":false}"#).normalitzada().settings == nil)
    }

    @Test func elsTextosNomesDEspaisNoHiSon() {
        let c = ClaudePestanya(model: " ", nom: "\t", modePermisos: " \n", settings: " ").normalitzada()
        #expect(c.model == nil && c.nom == nil && c.modePermisos == nil && c.settings == nil)
        // Els espais d'un valor de debò es queden.
        #expect(ClaudePestanya(nom: " Botiga ").normalitzada().nom == " Botiga ")
    }

    // MARK: Carpetes

    @Test func unaCarpetaQueNoEsAbsolutaAvisa() throws {
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {}, "finestres": [{"id": "\(uuid(1))", "nom": "a", "pestanyes": [
              {"id": "\(uuid(2))", "carpeta": "GitHub/x", "claude": {}},
              {"id": "\(uuid(3))", "claude": {}},
              {"id": "\(uuid(4))", "carpeta": "~altri/x", "claude": {}},
              {"id": "\(uuid(5))", "carpeta": "~/bé", "claude": {}}]}]}
            """)
        #expect(llegida.avisos == [
            .carpetaNoAbsoluta(cami: "finestres[0].pestanyes[0]"),
            .carpetaNoAbsoluta(cami: "finestres[0].pestanyes[1]"),
            .carpetaNoAbsoluta(cami: "finestres[0].pestanyes[2]"),
        ])
    }

    // MARK: Claus repetides

    @Test(arguments: [
        (#"{"versio": 1, "plantilla": {"saltaPermisos": true, "saltaPermisos": false}}"#, "plantilla", "saltaPermisos"),
        (#"{"versio": 1, "versio": 1}"#, "", "versio"),
        (#"{"versio": 1, "finestres": [{"nom": "a", "pestanyes": [{"carpeta": "/a", "claude": {"saltaPermisos": true}, "claude": {"activat": false}}]}]}"#,
         "finestres[0].pestanyes[0]", "claude"),
        (#"{"versio": 1, "finestres": [{"nom": "a", "pestanyes": []}, {"nom": "b", "pestanyes": [], "pestanyes": [{"carpeta": "/b"}]}]}"#,
         "finestres[1]", "pestanyes"),
        (#"{"versio": 1, "plantilla": {"activat": true, "activat": false}}"#, "plantilla", "activat"),
        (#"{"versio": 1, "plantilla": {"altres": ["--a"], "model": "x\"y", "altres": []}}"#, "plantilla", "altres"),
    ] as [(String, String, String)])
    func unaClauRepetidaEsUnError(json: String, cami: String, clau: String) {
        #expect(error(json) == .formaIncorrecta(cami: cami, detall: "clau «\(clau)» repetida"))
    }

    @Test func laMateixaClauEnObjectesDiferentsNoEsRepetida() throws {
        // A més, cadenes amb cometes i claus escapades no confonen l'escàner.
        let llegida = try llegeix(#"""
            {"versio": 1, "plantilla": {"settings": "{\"a\":1,\"a\":2}", "nom": "x\\"},
             "finestres": [{"nom": "a", "pestanyes": [{"carpeta": "/a"}, {"carpeta": "/b"}]}, {"nom": "b"}]}
            """#)
        #expect(llegida.configuracio.finestres.count == 2)
        #expect(llegida.configuracio.plantilla.nom == #"x\"#)
    }

    // MARK: Id

    @Test func posaIdNousALesQueFaltenOSonIncorrectesORepetides() throws {
        let ids = IdsDeProva()
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {}, "finestres": [
              {"nom": "sense id", "pestanyes": [
                 {"id": "\(uuid(1))", "carpeta": "/a", "claude": {}},
                 {"id": "no-és-un-uuid", "carpeta": "/b", "claude": {}},
                 {"id": "\(uuid(1))", "carpeta": "/c", "claude": {}}]},
              {"id": "\(uuid(1))", "nom": "repetida", "pestanyes": []}]}
            """, ids: ids)
        let c = llegida.configuracio
        #expect(c.finestres[0].id == uuid(900))
        #expect(c.finestres[0].pestanyes.map(\.id) == [uuid(1), uuid(901), uuid(902)])
        #expect(c.finestres[1].id == uuid(903))
        #expect(llegida.avisos == [
            .idNou(cami: "finestres[0]", motiu: .absent),
            .idNou(cami: "finestres[0].pestanyes[1]", motiu: .invalid),
            .idNou(cami: "finestres[0].pestanyes[2]", motiu: .repetit),
            .idNou(cami: "finestres[1]", motiu: .repetit),
        ])
    }

    @Test func unIdNouNoRepeteixUnIdQueSurtMesAvall() throws {
        // El generador proposa uuid(900), que el fitxer fa servir més avall: l'id del fitxer guanya.
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {}, "finestres": [
              {"nom": "sense id", "pestanyes": []},
              {"id": "\(uuid(900))", "nom": "b", "pestanyes": []}]}
            """)
        #expect(llegida.configuracio.finestres.map(\.id) == [uuid(901), uuid(900)])
        #expect(llegida.avisos == [.idNou(cami: "finestres[0]", motiu: .absent)])
    }

    @Test func unIdNouNoRepeteixUnIdQueJaHiEs() throws {
        // El generador proposa primer uuid(900), que ja és al fitxer.
        let llegida = try llegeix("""
            {"versio": 1, "plantilla": {}, "finestres": [{"id": "\(uuid(900))", "nom": "a", "pestanyes": [{"carpeta": "/a", "claude": {}}]}]}
            """)
        let c = llegida.configuracio
        #expect(c.finestres[0].id == uuid(900))
        #expect(c.finestres[0].pestanyes[0].id == uuid(901))
        #expect(llegida.avisos == [.idNou(cami: "finestres[0].pestanyes[0]", motiu: .absent)])
    }

    // MARK: Claus desconegudes

    @Test func lesClausDesconegudesAvisenPeroNoImpedeixenLlegir() throws {
        let llegida = try llegeix("""
            {"versio": 1, "extra": 1, "plantilla": {"colour": "red"},
             "finestres": [{"id": "\(uuid(1))", "nom": "a", "x": true,
                            "pestanyes": [{"id": "\(uuid(2))", "carpeta": "/a", "color": "blue", "claude": {"efort": "high"}}]}]}
            """)
        #expect(llegida.avisos == [
            .clauDesconeguda(cami: "extra"),
            .clauDesconeguda(cami: "plantilla.colour"),
            .clauDesconeguda(cami: "finestres[0].x"),
            .clauDesconeguda(cami: "finestres[0].pestanyes[0].color"),
            .clauDesconeguda(cami: "finestres[0].pestanyes[0].claude.efort"),
        ])
        #expect(llegida.configuracio.finestres[0].pestanyes[0].claude.esforc == nil)
    }

    // MARK: Errors

    @Test func unaVersioMesNovaNoEsLlegeix() {
        #expect(error(#"{"versio": 2, "finestres": []}"#) == .versioMesNova(2))
    }

    @Test(arguments: [
        (#"{"finestres": []}"#, ErrorConfiguracio.senseVersio),
        (#"{"versio": 0}"#, .versioDesconeguda(0)),
        (#"{"versio": "1"}"#, .formaIncorrecta(cami: "versio", detall: "ha de ser un nombre enter")),
        (#"{"versio": true}"#, .formaIncorrecta(cami: "versio", detall: "ha de ser un nombre enter")),
        (#"{"versio": 1.5}"#, .formaIncorrecta(cami: "versio", detall: "ha de ser un nombre enter")),
        (#"[1, 2]"#, .formaIncorrecta(cami: "", detall: "ha de ser un objecte JSON")),
        ("null", .formaIncorrecta(cami: "", detall: "ha de ser un objecte JSON")),
        ("1", .formaIncorrecta(cami: "", detall: "ha de ser un objecte JSON")),
        (#""x""#, .formaIncorrecta(cami: "", detall: "ha de ser un objecte JSON")),
        (#"{"versio": 9223372036854775807}"#, .versioMesNova(Int.max)),
        (#"{"versio": 99999999999999999999}"#, .versioMesNova(Int.max)),
        (#"{"versio": 9007199254740993}"#, .versioMesNova(9_007_199_254_740_993)),
        (#"{"versio": -99999999999999999999}"#, .versioDesconeguda(Int.min)),
    ] as [(String, ErrorConfiguracio)])
    func versioIFormaGeneral(json: String, esperat: ErrorConfiguracio) {
        #expect(error(json) == esperat)
    }

    @Test(arguments: [
        ("{\n  \"versio\": 1,\n  \"finestres\": [,]\n}", 3, 17),
        ("{\r\n  \"versio\": 1,\r\n  \"finestres\": [,]\r\n}", 3, 17),
        ("{\r  \"versio\": 1,\r  \"finestres\": [,]\r}", 3, 17),
        ("\u{FEFF}{\n  \"versio\": 1,\n  \"finestres\": [,]\n}", 3, 17),
        ("{\n  \"versio\": 1, \"generador\": \"Producció\", \"finestres\": [,]\n}", 2, 56),
    ] as [(String, Int, Int)])
    func unJSONMalmesDiuLaLiniaILaColumna(json: String, linia: Int, columna: Int) {
        #expect(error(json) == .jsonMalmes(linia: linia, columna: columna))
    }

    @Test func unFitxerAmbBOMEsLlegeix() throws {
        let llegida = try llegeix("\u{FEFF}" + #"{"versio": 1, "plantilla": {}}"#)
        #expect(llegida.configuracio.finestres.isEmpty)
    }

    @Test func unFitxerQueNoEsUTF8NoEsLlegeix() throws {
        let utf16 = try #require(#"{"versio": 1, "plantilla": {}}"#.data(using: .utf16))
        #expect(throws: ErrorConfiguracio.formaIncorrecta(cami: "", detall: "el fitxer ha de ser text UTF-8")) {
            try Configuracio.llegeix(utf16, inici: inici)
        }
        #expect(throws: ErrorConfiguracio.formaIncorrecta(cami: "", detall: "el fitxer ha de ser text UTF-8")) {
            try Configuracio.llegeix(Data([0x7B, 0xFF, 0x7D]), inici: inici)
        }
    }

    @Test func unTipusIncorrecteDiuOnEs() {
        let e = error(#"{"versio": 1, "finestres": [{"nom": "a", "pestanyes": [{"claude": {"saltaPermisos": "sí"}}]}]}"#)
        guard case let .formaIncorrecta(cami, _) = e else {
            Issue.record("s'esperava formaIncorrecta, i ha donat \(String(describing: e))")
            return
        }
        #expect(cami == "finestres[0].pestanyes[0].claude.saltaPermisos")
    }

    @Test func elsMissatgesDErrorSonEnCatala() {
        #expect(ErrorConfiguracio.versioMesNova(2).description.contains("versió més nova de Warp Launch"))
        #expect(ErrorConfiguracio.jsonMalmes(linia: 3, columna: 14).description == "el fitxer no és JSON vàlid (línia 3, columna 14)")
    }
}
