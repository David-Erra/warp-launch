import Foundation

/// El que el CLI agafa de fora. `main.swift` hi posa els valors reals; les proves, fixtures.
public struct EntornCLI: Sendable {
    public var lector: Lector
    public var inici: String
    /// La configuració d'en David (D8): `configuracio valida` la llegeix si no es diu `--config`, `importa` en pren
    /// la plantilla, i `importa --desa` no hi escriu mai.
    public var carpetaReal: URL
    public var nouId: @Sendable () -> UUID
    public var carpetaExisteix: @Sendable (String) -> Bool
    /// `obre`: on són les transcripcions de Claude i qui diu en quines carpetes confia. Sense valor per defecte: les
    /// proves no han de llegir mai els de debò.
    public var transcripcions: LectorTranscripcions
    public var confianca: LectorConfianca
    public var ara: @Sendable () -> Date
    /// `diagnostica`: la versió de macOS que diu l'informe.
    public var sistema: String

    public init(lector: Lector, inici: String, carpetaReal: URL, transcripcions: LectorTranscripcions,
                confianca: LectorConfianca, nouId: @escaping @Sendable () -> UUID = { UUID() },
                carpetaExisteix: @escaping @Sendable (String) -> Bool = Validacio.carpetaExisteixAlDisc,
                ara: @escaping @Sendable () -> Date = { Date() },
                sistema: String = ProcessInfo.processInfo.operatingSystemVersionString) {
        self.sistema = sistema
        self.lector = lector
        self.inici = inici
        self.carpetaReal = carpetaReal
        self.transcripcions = transcripcions
        self.confianca = confianca
        self.nouId = nouId
        self.carpetaExisteix = carpetaExisteix
        self.ara = ara
    }
}

/// El que fa obrir alguna cosa a Warp des del CLI (`warp-launch obre --obre`, D17). `main.swift` hi posa `ObreWarp`; les
/// proves, un obridor fals i una carpeta temporal.
public struct ObridorCLI {
    /// Demana a Warp que obri el fitxer (`ObreWarp.obre`).
    public var obre: @MainActor (URLLlancament) async throws -> Void
    /// Obre Warp, si és tancat (`ObreWarp.engega`).
    public var engega: @MainActor () async throws -> Void
    public var fitxers: FitxersLaunchWarp
    /// L'app és oberta: llavors el CLI no obre res.
    public var appOberta: () -> Bool
    public var espera: @MainActor (Duration) async -> Void
    /// Mostra ara un text (el pla, l'espera de Warp), abans d'una espera llarga: la resta surt en acabar.
    public var avisa: @MainActor (String) -> Void
    /// Què cal fer si es prem Ctrl-C (esborrar el fitxer temporal i desar el llançament), mentre n'hi ha cap d'escrit; `nil`
    /// quan ja no cal.
    public var enInterrupcio: @MainActor ((@MainActor () -> Void)?) -> Void

    public init(obre: @escaping @MainActor (URLLlancament) async throws -> Void,
                engega: @escaping @MainActor () async throws -> Void, fitxers: FitxersLaunchWarp,
                appOberta: @escaping () -> Bool,
                espera: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                avisa: @escaping @MainActor (String) -> Void = { _ in },
                enInterrupcio: @escaping @MainActor ((@MainActor () -> Void)?) -> Void = { _ in }) {
        self.obre = obre
        self.avisa = avisa
        self.enInterrupcio = enInterrupcio
        self.engega = engega
        self.fitxers = fitxers
        self.appOberta = appOberta
        self.espera = espera
    }
}

/// El text de sortida i el d'error.
public struct Sortida: Sendable, Equatable {
    public var text = ""
    public var errors = ""

    public init() {}

    mutating func escriu(_ linia: String) { text += linia + "\n" }
}

/// La comanda `warp-launch` (docs/disseny.md, «Arquitectura»). Llegeix Warp i Claude, i només escriu amb
/// `importa --desa --config <carpeta>`, que no pot ser la configuració real. `obre` només mostra el pla (mode de prova,
/// D17); amb `--obre`, obre la finestra (`executa(_:entorn:obridor:sortida:)`, 0.24.0). No tanca mai res.
public enum OrdreCLI {
    public enum Codi {
        public static let correcte: Int32 = 0
        /// No s'ha pogut llegir Warp o la configuració, o desar-la.
        public static let fallida: Int32 = 1
        /// La configuració té errors: alguna pestanya no s'obriria com diu (o, amb `obre`, no s'obriria).
        public static let configuracioAmbErrors: Int32 = 2
        /// `EX_USAGE`.
        public static let us: Int32 = 64
    }

    public static var ajuda: String {
        """
        \(WarpLaunch.nom) \(WarpLaunch.versio)

        Ús:
          warp-launch llegeix [--json] [--warp <warp.sqlite>] [--sessions <carpeta>]
              Finestres i pestanyes obertes a Warp, i la sessió de Claude de cada pestanya.
          warp-launch importa [--json] [--warp <warp.sqlite>] [--sessions <carpeta>] [--desa --config <carpeta>]
              La configuració que sortiria de Warp ara, amb els avisos. Sense --desa no escriu res.
              Les pestanyes on no corre Claude prenen la plantilla de ~/.config/warp-launch. Si no hi ha
              configuració, o encara no té cap pestanya, queden només terminal, com a l'app.
              --desa la desa a <carpeta>, que no pot tenir cap configuració ni ser ~/.config/warp-launch:
              la configuració real només es crea des de l'app.
          warp-launch configuracio valida [--config <carpeta>]
              Errors i avisos de la configuració (per defecte, la de ~/.config/warp-launch).
          warp-launch obre <nom o número de finestra> [--json] [--config <carpeta>] [--warp <warp.sqlite>]
                  [--sessions <carpeta>]
              Mode de prova: què passaria si s'obrís la finestra a Warp (quines pestanyes ja són obertes, quines
              s'obririen i com, i el fitxer i l'URL exactes). No escriu ni obre res, tampoc estat.json.
          warp-launch obre <nom o número de finestra> --obre [--config <carpeta>]
              Obre la finestra a Warp, com el botó «Obre» de l'app: les pestanyes que no són obertes, cadascuna
              amb el seu Claude. Si Warp és tancat, primer l'obre. No fa res si l'app és oberta.
          warp-launch diagnostica [--json] [--anonimitza]
              Comprova si Warp i Claude Code encara tenen la forma que l'app llegeix: els terminals de Warp, els
              fitxers de sessió i les transcripcions de Claude, ~/.claude.json, les taules de warp.sqlite, les
              versions (comparades amb les provades) i la restauració de sessió de Warp amb el consentiment. Cada
              comprovació diu bé, avís o error. L'informe és en anglès, per enganxar-lo en una issue de GitHub.
              --anonimitza treu el nom d'usuari, la carpeta d'inici i els noms de carpeta (en deixa la forma).
          warp-launch --versio

        Només llegeix Warp (warp.sqlite en només lectura), ~/.claude/sessions i, amb obre i diagnostica, el nom de
        les transcripcions de ~/.claude/projects i les carpetes de confiança de ~/.claude.json. Amb diagnostica,
        també l'esquema de warp.sqlite, l'Info.plist de Warp, ~/.warp/settings.toml i preferencies.json. No obre ni tanca res,
        excepte obre --obre, que obre la finestra i escriu estat.json i el fitxer temporal de Warp (i l'esborra).
        Codis de sortida: 0 correcte; 1 no s'ha pogut llegir, desar o obrir (o, amb --obre, no s'ha vist tot
        obert; amb obre, també si no hi ha cap Warp o Warp Preview no deixa obrir res; amb diagnostica, alguna
        comprovació ha donat error); 2 la configuració (llegida o importada) té errors, o alguna pestanya no
        s'obriria; 64 ús incorrecte.
        """
    }

    public static func executa(_ args: [String], entorn: EntornCLI, sortida: inout Sortida) -> Int32 {
        do throws(ErrorCLI) {
            var resta = ArraySlice(args)
            switch resta.popFirst() {
            case nil, "--ajuda", "--help", "-h":
                sortida.escriu(ajuda)
                return Codi.correcte
            case "--versio", "--version", "-V":
                sortida.escriu("\(WarpLaunch.nom) \(WarpLaunch.versio)")
                return Codi.correcte
            case "llegeix":
                return try llegeix(resta, entorn: entorn, sortida: &sortida)
            case "importa":
                return try importa(resta, entorn: entorn, sortida: &sortida)
            case "configuracio":
                guard resta.popFirst() == "valida" else { throw .us("ordre: «configuracio valida»") }
                return try valida(resta, entorn: entorn, sortida: &sortida)
            case "obre":
                return try obre(resta, entorn: entorn, sortida: &sortida)
            case "diagnostica":
                return try diagnostica(resta, entorn: entorn, sortida: &sortida)
            case let desconegut?:
                throw .us("ordre desconeguda «\(desconegut)»")
            }
        } catch {
            switch error {
            case let .us(missatge):
                sortida.errors += "warp-launch: \(missatge)\n\n\(ajuda)\n"
                return Codi.us
            case let .fallida(missatge):
                sortida.errors += "warp-launch: \(missatge)\n"
                return Codi.fallida
            }
        }
    }

    enum ErrorCLI: Error {
        case us(String)
        case fallida(String)
    }

    // MARK: - Ordres

    private struct Opcions {
        var json = false
        var desa = false
        var anonimitza = false
        var config: URL?
    }

    /// Llegeix les opcions d'una ordre. `admeses` diu quines accepta.
    private static func opcions(_ args: ArraySlice<String>, ordre: String, admeses: Set<String>,
                                lector: inout Lector, inici: String) throws(ErrorCLI) -> Opcions {
        var o = Opcions()
        var resta = args
        while let arg = resta.popFirst() {
            let nom = arg.hasPrefix("--config=") ? "--config" : arg
            guard admeses.contains(nom) else { throw .us("opció desconeguda per a \(ordre): «\(arg)»") }
            switch nom {
            case "--json": o.json = true
            case "--desa": o.desa = true
            case "--anonimitza": o.anonimitza = true
            case "--warp":
                guard let ruta = resta.popFirst() else { throw .us("falta la ruta després de --warp") }
                lector.rutaWarp = URL(filePath: ruta)
                // Una base triada a mà es llegeix sigui quin sigui l'ajust de Warp.
                lector.rutaAjustos = nil
            case "--sessions":
                guard let ruta = resta.popFirst() else { throw .us("falta la carpeta després de --sessions") }
                lector.carpetaSessions = URL(filePath: ruta)
            default:  // --config
                guard o.config == nil else { throw .us("«--config» hi és més d'un cop") }
                let valor = arg == "--config" ? resta.popFirst() ?? "" : String(arg.dropFirst("--config=".count))
                o.config = try carpeta(valor, inici: inici)
            }
        }
        return o
    }

    /// Una carpeta de `--config`: absoluta, o `~/…`.
    private static func carpeta(_ valor: String, inici: String) throws(ErrorCLI) -> URL {
        guard !valor.isEmpty else { throw .us("falta la carpeta després de «--config»") }
        let ruta: String
        if valor.hasPrefix("/") {
            ruta = valor
        } else if valor == "~" || valor.hasPrefix("~/") {
            ruta = inici + valor.dropFirst()
        } else {
            throw .us("la carpeta de «--config» ha de ser una ruta absoluta (que comenci per / o ~/): «\(valor)»")
        }
        // Sense `standardizedFileURL`, que canviaria `/private/var/…` per `/var/…`: la ruta es mostra tal com s'ha escrit.
        return URL(filePath: ruta, directoryHint: .isDirectory)
    }

    private static func llegeix(_ args: ArraySlice<String>, entorn: EntornCLI,
                                sortida: inout Sortida) throws(ErrorCLI) -> Int32 {
        var lector = entorn.lector
        let o = try opcions(args, ordre: "llegeix", admeses: ["--json", "--warp", "--sessions"], lector: &lector,
                            inici: entorn.inici)
        let lectura = try llegeixWarp(lector)
        if o.json {
            let codificador = JSONEncoder()
            codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            codificador.dateEncodingStrategy = .iso8601
            guard let dades = try? codificador.encode(lectura) else { throw .fallida("no s'ha pogut generar el JSON") }
            sortida.escriu(String(decoding: dades, as: UTF8.self))
        } else {
            sortida.escriu(Informe.text(lectura, inici: lector.inici))
        }
        return Codi.correcte
    }

    private static func importa(_ args: ArraySlice<String>, entorn: EntornCLI,
                                sortida: inout Sortida) throws(ErrorCLI) -> Int32 {
        var lector = entorn.lector
        let o = try opcions(args, ordre: "importa", admeses: ["--json", "--warp", "--sessions", "--desa", "--config"],
                            lector: &lector, inici: entorn.inici)
        if o.desa, o.config == nil {
            throw .us("«--desa» necessita «--config <carpeta>»: la configuració real només es crea des de l'app")
        }
        if o.config != nil, !o.desa { throw .us("«--config» només serveix amb «--desa»") }
        if let config = o.config, esLaReal(config, real: entorn.carpetaReal) {
            throw .us("«--config» no pot ser la configuració real (\(entorn.carpetaReal.path)), ni ser-hi a dins, ni "
                + "passar per «..» o un enllaç trencat: la configuració real només es crea des de l'app")
        }

        let lectura = try llegeixWarp(lector)
        // El CLI no toca mai l'ajust (D19 només és de l'app): no és que Warp no tingui res obert.
        if lectura.warpDesaFinestres == false {
            throw .fallida(LecturaWarp.senseFinestres + " «warp-launch importa» no toca aquest ajust i no pot demanar a Warp "
                + "que les desi. L'app, amb la configuració de debò, sí: l'activa uns segons perquè Warp les desi, i el "
                + "torna a desactivar.")
        }
        let inici = Rutes.canonica(entorn.inici)
        let plantilla = plantillaPerImportar(entorn, inici: inici)
        let importacio = Importador.importa(lectura, inici: inici, plantilla: plantilla.valor,
                                            senseSessio: plantilla.senseSessio, nouId: entorn.nouId)
        var configuracio = importacio.configuracio
        configuracio.generador = "\(WarpLaunch.nom) \(WarpLaunch.versio)"

        var desada: URL?
        if let carpeta = o.config {
            let magatzem = MagatzemConfiguracio(carpeta: carpeta, inici: inici)
            let existeix: Bool
            do { existeix = try magatzem.carrega() != nil } catch { existeix = true }
            if existeix || FileManager.default.fileExists(atPath: magatzem.fitxer.path) {
                throw .fallida("ja hi ha una configuració a \(magatzem.fitxer.path); tria una carpeta buida")
            }
            do {
                try magatzem.desa(configuracio, sobre: nil)
            } catch {
                throw .fallida(error.description)
            }
            desada = magatzem.fitxer
        }

        let avisos = Validacio.avisos(configuracio, inici: inici, carpetaExisteix: entorn.carpetaExisteix)
        let codi = avisos.compta(.error) == 0 ? Codi.correcte : Codi.configuracioAmbErrors
        if o.json {
            guard let dades = try? configuracio.normalitzada(inici: inici).json() else {
                throw .fallida("no s'ha pogut generar el JSON")
            }
            sortida.text += String(decoding: dades, as: UTF8.self)
            return codi
        }
        sortida.escriu(desada.map { "Importació de Warp, desada a \($0.path)" }
            ?? "Importació de Warp (vista prèvia: no s'ha desat res)")
        sortida.escriu(importacio.resum.descripcio)
        sortida.escriu("\(Plural.compta(importacio.resum.saltenPermisos, "pestanya salta", "pestanyes salten")) els permisos (--dangerously-skip-permissions).")
        sortida.escriu(plantilla.origen)
        if let motiu = plantilla.nomesTerminal {
            sortida.escriu("Les pestanyes que no tenien Claude obert queden només terminal (\(motiu)).")
        }
        sortida.text += InformeConfiguracio.text(configuracio, avisos: avisos, origens: importacio.origens, inici: inici)
        if !importacio.notes.isEmpty {
            sortida.escriu("")
            sortida.escriu("Notes de la importació:")
            for nota in importacio.notes { sortida.escriu("  · \(nota)") }
        }
        if !lectura.avisos.isEmpty {
            sortida.escriu("")
            sortida.escriu("Avisos de la lectura:")
            for avis in lectura.avisos { sortida.escriu("  · \(avis)") }
        }
        let ambErrors = avisos.pestanyes.values.filter { $0.contains { $0.gravetat == .error } }.count
        if ambErrors > 0 {
            sortida.escriu("")
            sortida.escriu("\(Plural.compta(ambErrors, "pestanya no s'obriria", "pestanyes no s'obririen")) com diu la configuració (✗).")
        }
        return codi
    }

    /// La plantilla d'`importa`, com a l'app (`Editor.plantillaPerImportar` i `senseSessioPerImportar`): la de la
    /// configuració real, si n'hi ha, i les pestanyes que no tenien Claude obert la prenen. Si no n'hi ha, la segura, que
    /// no salta els permisos ni porta ultracode (D11, revisada per en David el 07/11/2026), i aquestes pestanyes queden
    /// només terminal (D-P5a); també si la configuració encara no té cap pestanya, amb la seva plantilla (decisió d'en
    /// David del 08/11/2026). Una configuració que no es pot llegir no atura la vista prèvia: es fa servir la segura,
    /// com si es tornés a importar, i `origen` diu per què. `nomesTerminal` diu per què queden només terminal, si és el
    /// cas. Només llegeix.
    private static func plantillaPerImportar(_ entorn: EntornCLI, inici: String)
        -> (valor: ClaudePestanya, senseSessio: Importador.SenseSessio, origen: String, nomesTerminal: String?) {
        let magatzem = MagatzemConfiguracio(carpeta: entorn.carpetaReal, inici: inici)
        let segura = "Plantilla: la segura, sense saltar els permisos"
        do {
            guard let carregada = try magatzem.carrega() else {
                return (.perOmissio, .nomesTerminal, segura + " (encara no hi ha cap configuració).", "configuració nova")
            }
            let senseSessio = Importador.SenseSessio.per(carregada.configuracio)
            return (carregada.configuracio.plantilla, senseSessio, "Plantilla: la de \(magatzem.fitxer.path).",
                    senseSessio == .nomesTerminal ? "la configuració encara no té cap pestanya" : nil)
        } catch {
            return (.perOmissio, .plantilla, segura + " (no s'ha pogut llegir \(magatzem.fitxer.path): \(error)).", nil)
        }
    }

    private static func valida(_ args: ArraySlice<String>, entorn: EntornCLI,
                               sortida: inout Sortida) throws(ErrorCLI) -> Int32 {
        var lector = entorn.lector
        let o = try opcions(args, ordre: "configuracio valida", admeses: ["--config"], lector: &lector,
                            inici: entorn.inici)
        let inici = Rutes.canonica(entorn.inici)
        let magatzem = MagatzemConfiguracio(carpeta: o.config ?? entorn.carpetaReal, inici: inici)
        let llegida: ConfiguracioCarregada?
        do {
            llegida = try magatzem.carrega()
        } catch {
            throw .fallida("\(magatzem.fitxer.path): \(error)")
        }
        guard let carregada = llegida else { throw .fallida("no hi ha cap configuració a \(magatzem.fitxer.path)") }

        let configuracio = carregada.configuracio
        let avisos = Validacio.avisos(configuracio, inici: inici, carpetaExisteix: entorn.carpetaExisteix)
        let pestanyes = configuracio.finestres.flatMap(\.pestanyes)
        let ambClaude = pestanyes.filter(\.claude.activat).count
        sortida.escriu("Configuració: \(magatzem.fitxer.path)")
        sortida.escriu("\(Plural.compta(configuracio.finestres.count, "finestra", "finestres")) · "
            + "\(Plural.compta(pestanyes.count, "pestanya", "pestanyes")) · \(ambClaude) amb Claude · "
            + "\(pestanyes.count - ambClaude) només terminal")
        if !carregada.avisos.isEmpty {
            sortida.escriu("")
            sortida.escriu("Avisos del fitxer:")
            for avis in carregada.avisos { sortida.escriu("  · \(avis)") }
        }
        sortida.text += InformeConfiguracio.text(configuracio, avisos: avisos, origens: nil, inici: inici)
        let errors = avisos.compta(.error)
        sortida.escriu("")
        sortida.escriu("Resultat: \(Plural.compta(errors, "error", "errors")), "
            + "\(Plural.compta(avisos.compta(.avis), "avís", "avisos")).")
        return errors == 0 ? Codi.correcte : Codi.configuracioAmbErrors
    }

    /// Pla A4 (0.30.0): les comprovacions de `Diagnostic`, amb el Warp, el Claude i la carpeta de l'entorn. Només llegeix;
    /// l'informe és en anglès (va a les issues de GitHub). Surt amb 1 si alguna comprovació dona error.
    private static func diagnostica(_ args: ArraySlice<String>, entorn: EntornCLI,
                                    sortida: inout Sortida) throws(ErrorCLI) -> Int32 {
        var lector = entorn.lector
        let o = try opcions(args, ordre: "diagnostica", admeses: ["--json", "--anonimitza"], lector: &lector,
                            inici: entorn.inici)
        let informe = Diagnostic.executa(EntornDiagnostic(lector: lector, carpetaConfiguracio: entorn.carpetaReal,
                                                          transcripcions: entorn.transcripcions,
                                                          confianca: entorn.confianca, sistema: entorn.sistema),
                                         anonimitza: o.anonimitza)
        if o.json {
            guard let dades = try? informe.json() else { throw .fallida("no s'ha pogut generar el JSON") }
            sortida.escriu(String(decoding: dades, as: UTF8.self))
        } else {
            sortida.text += informe.text
        }
        return informe.compta(.error) == 0 ? Codi.correcte : Codi.fallida
    }

    /// El pla d'obrir una finestra, com el calcularia l'app ara mateix, i el que cal per obrir-la. No escriu res.
    private struct PlaCLI {
        var o: Opcions
        var numero: Int
        var configuracio: Configuracio
        var carpeta: URL
        var fitxerConfiguracio: URL
        var lector: Lector
        var inici: String
        var lectura: LecturaWarp
        /// L'estat del disc, amb els lligams posats al dia amb la lectura (només en memòria).
        var estat: EstatApp
        var pla: Pla
    }

    /// Llegeix la configuració, `estat.json` i Warp, i calcula el pla de la finestra.
    private static func planifica(_ args: ArraySlice<String>, entorn: EntornCLI, finestra id: Finestra.ID? = nil,
                                  admeses: Set<String> = ["--json", "--config", "--warp", "--sessions"])
        throws(ErrorCLI) -> PlaCLI {
        var resta = args
        guard let nom = resta.popFirst(), !nom.hasPrefix("-") else {
            throw .us("falta la finestra: «warp-launch obre <nom o número de finestra>»")
        }
        var lector = entorn.lector
        let o = try opcions(resta, ordre: admeses.contains("--json") ? "obre" : "obre --obre", admeses: admeses,
                            lector: &lector, inici: entorn.inici)
        let inici = Rutes.canonica(entorn.inici)
        let carpeta = o.config ?? entorn.carpetaReal
        let magatzem = MagatzemConfiguracio(carpeta: carpeta, inici: inici)
        let llegida: ConfiguracioCarregada?
        do {
            llegida = try magatzem.carrega()
        } catch {
            throw .fallida("\(magatzem.fitxer.path): \(error)")
        }
        guard let configuracio = llegida?.configuracio else {
            throw .fallida("no hi ha cap configuració a \(magatzem.fitxer.path)")
        }
        let (numero, finestra) = try triaFinestra(nom, de: configuracio)
        // En tornar a calcular, ha de ser la mateixa finestra.
        if let id, finestra.id != id { throw .fallida("la configuració ha canviat mentre s'obria Warp: torna-ho a provar") }

        let fitxerEstat = carpeta.appending(path: EstatApp.nomFitxer)
        let desat: EstatApp
        do {
            desat = try EstatApp.llegeix(fitxer: fitxerEstat)
        } catch {
            throw .fallida("\(fitxerEstat.path): \(error); l'app no obriria res")
        }
        let lectura = try llegeixWarp(lector)
        let ara = entorn.ara()
        // Com l'app: primer posa al dia els lligams amb la lectura, i després calcula.
        let estat = ActualitzaEstat.amb(lectura, configuracio: configuracio, estat: desat, ara: ara)
        let transcripcions = entorn.transcripcions
        let entrada = EntradaObertura(lectura: lectura, estat: estat, inici: inici, ara: ara,
                                      carpetaExisteix: entorn.carpetaExisteix,
                                      transcripcio: { transcripcions.on(sessio: $0, carpeta: $1) },
                                      conversesRecents: { transcripcions.recents(carpeta: $0) },
                                      confianca: entorn.confianca.llegeix(inici: inici),
                                      entornClaude: EntornClaude.ruta(carpeta: magatzem.carpeta))
        return PlaCLI(o: o, numero: numero, configuracio: configuracio, carpeta: magatzem.carpeta,
                      fitxerConfiguracio: magatzem.fitxer, lector: lector, inici: inici, lectura: lectura, estat: estat,
                      pla: PlaObertura.calcula(finestra, entrada))
    }

    /// Mode de prova de D17: el pla d'obrir una finestra, com el calcularia l'app ara mateix. No escriu res (tampoc
    /// `estat.json`, que només llegeix) i no obre res. Amb `--obre`, s'ha de cridar `executa(_:entorn:obridor:sortida:)`.
    private static func obre(_ args: ArraySlice<String>, entorn: EntornCLI,
                             sortida: inout Sortida) throws(ErrorCLI) -> Int32 {
        if args.contains("--obre") {
            throw .us("«--obre» només funciona amb la comanda «warp-launch» de debò")
        }
        let p = try planifica(args, entorn: entorn)
        var fitxer: FitxerLaunch?
        var errorFitxer: String?
        if !p.pla.aObrir.isEmpty {
            do {
                fitxer = try p.pla.fitxer(llancament: entorn.nouId())
            } catch {
                errorFitxer = error.description
            }
        }

        let dades = InformeObertura.Dades(pla: p.pla, numero: p.numero, finestres: p.configuracio.finestres.count,
                                          configuracio: p.fitxerConfiguracio, warpObert: p.lectura.warpObert,
                                          warpPreview: p.lectura.warpPreview, fitxer: fitxer, errorFitxer: errorFitxer,
                                          inici: p.inici)
        if p.o.json {
            guard let json = try? InformeObertura.json(dades) else { throw .fallida("no s'ha pogut generar el JSON") }
            sortida.escriu(String(decoding: json, as: UTF8.self))
        } else {
            sortida.text += InformeObertura.text(dades)
        }
        // Amb `--obre`, no s'obriria res: com si no es pogués obrir.
        if p.lectura.warpPreview != nil { return Codi.fallida }
        return p.pla.excloses.isEmpty && errorFitxer == nil ? Codi.correcte : Codi.configuracioAmbErrors
    }

    // MARK: - obre --obre (D17)

    /// `warp-launch obre <finestra> --obre`: obre la finestra de debò, pel mateix camí que el botó del full de l'app
    /// (`ExecucioObertura`). Les altres ordres, i `obre` sense `--obre`, van com sempre. **Claude no el fa servir mai sense
    /// l'OK d'en David per a cada prova** (regla 1).
    @MainActor
    public static func executa(_ args: [String], entorn: EntornCLI, obridor: ObridorCLI,
                               sortida: inout Sortida) async -> Int32 {
        guard args.first == "obre", args.contains("--obre") else { return executa(args, entorn: entorn, sortida: &sortida) }
        do throws(ErrorCLI) {
            return try await obreDeDebo(ArraySlice(args.dropFirst().filter { $0 != "--obre" }), entorn: entorn,
                                        obridor: obridor, sortida: &sortida)
        } catch {
            switch error {
            case let .us(missatge):
                sortida.errors += "warp-launch: \(missatge)\n\n\(ajuda)\n"
                return Codi.us
            case let .fallida(missatge):
                sortida.errors += "warp-launch: \(missatge)\n"
                return Codi.fallida
            }
        }
    }

    @MainActor
    private static func obreDeDebo(_ args: ArraySlice<String>, entorn: EntornCLI, obridor: ObridorCLI,
                                   sortida: inout Sortida) async throws(ErrorCLI) -> Int32 {
        // Sense `--json`, ni `--warp` ni `--sessions`: el que s'obre surt sempre del Warp i el Claude de debò.
        var p = try planifica(args, entorn: entorn, admeses: ["--config"])
        // L'app escriu `estat.json` cada minut: si tots dos l'escrivissin alhora, se'n podria perdre un canvi (D17).
        if obridor.appOberta() {
            throw .fallida("l'app Warp Launch és oberta: obre la finestra des de l'app, o surt-ne i torna-ho a provar. "
                + "No s'ha obert res.")
        }
        // D-P12: amb Warp Preview, o sense cap Warp (0.31.1), ni s'obre Warp ni s'escriu res.
        if let preview = p.lectura.warpPreview { throw .fallida("\(preview.text) No s'ha obert res.") }
        let id = p.pla.finestra.id
        func dades(_ p: PlaCLI, fitxer: FitxerLaunch?) -> InformeObertura.Dades {
            InformeObertura.Dades(pla: p.pla, numero: p.numero, finestres: p.configuracio.finestres.count,
                                  configuracio: p.fitxerConfiguracio, warpObert: p.lectura.warpObert,
                                  warpPreview: p.lectura.warpPreview, fitxer: fitxer, errorFitxer: nil, inici: p.inici,
                                  capcalera: "S'obre a Warp (--obre).")
        }
        guard p.pla.motiuEspera == nil else {
            sortida.text += InformeObertura.text(dades(p, fitxer: nil))
            throw .fallida("no s'ha obert res: \(p.pla.motiuEspera ?? "")")
        }
        let warpTancat = p.lectura.warpObert != true
        if p.pla.aObrir.isEmpty {
            // Warp és tancat i restaura la sessió: les «obertes» a Warp són les que restaurarà, no les d'ara.
            if warpTancat, p.lectura.warpDesaFinestres != false, p.pla.obertes.contains(where: { $0.on.esAWarp }) {
                throw .fallida("Warp és tancat, i en obrir-se restaurarà aquestes pestanyes, sense Claude. Obre'l i torna-ho "
                    + "a provar. No s'ha obert res.")
            }
            sortida.text += InformeObertura.text(dades(p, fitxer: nil))
            let x = p.pla.xifres
            sortida.escriu(p.pla.excloses.isEmpty
                ? "Totes les pestanyes ja són obertes: no s'ha obert res."
                : "No hi ha cap pestanya per obrir (\(x.jaObertes) ja obertes, \(x.excloses) no s'obriran): no s'ha obert res.")
            return p.pla.excloses.isEmpty ? Codi.correcte : Codi.configuracioAmbErrors
        }
        /// Mostra ara el que hi ha a la sortida, abans d'una espera llarga.
        func mostra() {
            guard !sortida.text.isEmpty else { return }
            obridor.avisa(sortida.text)
            sortida.text = ""
        }
        /// El final dels errors: si s'ha obert Warp, no és cert que no s'hagi obert res.
        func res(_ p: PlaCLI) -> String {
            guard warpTancat else { return "No s'ha obert res." }
            return "S'ha obert Warp, però cap finestra de la configuració."
                + (p.lectura.warpDesaFinestres == false ? " En arrencar, Warp ha obert una finestra buida: la pots tancar." : "")
        }

        // Warp és tancat: l'obre, n'espera l'arrencada i torna a calcular. Si el que s'obriria ha canviat, no obre res.
        let llancament = entorn.nouId()
        if warpTancat {
            sortida.escriu("Warp és tancat: l'obro i n'espero l'arrencada (fins a \(Int(ExecucioObertura.tempsMaximWarp)) s).")
            mostra()
            var errorEngegant: String?
            Task { @MainActor in
                do {
                    try await obridor.engega()
                } catch {
                    errorEngegant = "\(error)"
                }
            }
            let lector = p.lector
            let arrencat = await ExecucioObertura.esperaWarp(llegeix: { try? lector.llegeix() }, espera: obridor.espera,
                                                            rellotge: entorn.ara, fallat: { errorEngegant != nil })
            if let errorEngegant { throw .fallida("no s'ha pogut obrir Warp: \(errorEngegant)") }
            guard arrencat else {
                throw .fallida("Warp no ha arrencat en \(Int(ExecucioObertura.tempsMaximWarp)) s: mira'l i torna-ho a provar.")
            }
            let abans = p.pla.aObrir
            p = try planifica(args, entorn: entorn, finestra: id, admeses: ["--config"])
            guard p.lectura.warpObert == true else {
                throw .fallida("Warp s'ha tancat mentre arrencava: mira'l i torna-ho a provar.")
            }
            guard p.pla.aObrir == abans, p.pla.motiuEspera == nil else {
                sortida.text += InformeObertura.text(dades(p, fitxer: nil))
                throw .fallida("en arrencar, Warp ha canviat el que s'obriria: torna-ho a provar. \(res(p))")
            }
        }
        let fitxer: FitxerLaunch
        do {
            fitxer = try p.pla.fitxer(llancament: llancament)
        } catch {
            sortida.text += InformeObertura.text(dades(p, fitxer: nil))
            throw .fallida("\(error.description). \(res(p))")
        }
        sortida.text += InformeObertura.text(dades(p, fitxer: fitxer))
        mostra()

        // `estat.json`: els lligams posats al dia amb la lectura, i el llançament (com fa l'app).
        let magatzem = MagatzemEstat(carpeta: p.carpeta)
        var estat = p.estat
        let configuracio = p.configuracio
        let ara = entorn.ara
        func desa(_ nou: EstatApp) -> String? {
            do {
                try magatzem.desa(nou)
                estat = nou
                return nil
            } catch {
                return error.description
            }
        }
        let lector = p.lector
        var sortida2: [String] = []
        let execucio = ExecucioObertura.Entorn(
            llegeix: { try? lector.llegeix() },
            obre: obridor.obre, fitxers: obridor.fitxers, inici: entorn.inici, rellotge: ara, espera: obridor.espera,
            desaLlancament: { llancament in
                var nou = estat
                nou.desa(llancament)
                return desa(nou)
            },
            lligaPanes: { _ = desa(ActualitzaEstat.ambPanes($0, estat: estat, ara: ara())) },
            desaEntornClaude: { try EntornClaude.desa(carpeta: p.carpeta) },
            enLlegir: { estat = ActualitzaEstat.amb($0, configuracio: configuracio, estat: estat, ara: ara()) },
            // Ctrl-C a mig obrir: com `Obertura.enSortir` a l'app, esborra el fitxer i desa el llançament.
            enCurs: { [obridor] llancament, _ in
                guard var llancament else { return obridor.enInterrupcio(nil) }
                obridor.enInterrupcio {
                    if !llancament.esborrat { llancament.esborrat = ExecucioObertura.esborra(llancament, obridor.fitxers) }
                    if llancament.estat == .pendent { llancament.estat = .senseConfirmar }
                    var nou = estat
                    nou.desa(llancament)
                    _ = desa(nou)
                }
            },
            enErrorEsborrant: { _, error in sortida2.append("No s'ha pogut esborrar el fitxer temporal: \(error)") })
        let peticio = ExecucioObertura.Peticio(
            pla: p.pla, fitxer: fitxer,
            panesAbans: Set(p.lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).map(\.uuid)),
            terminalsAbans: Set(p.lectura.terminals.map(\.pid)), warpEngegat: warpTancat,
            warpDesaFinestres: p.lectura.warpDesaFinestres != false)
        switch await ExecucioObertura.executa(peticio, entorn: execucio) {
        case let .noEsPot(motiu):
            throw .fallida("\(motiu). \(res(p))")
        case let .acabat(fet):
            sortida.escriu("")
            sortida.escriu(fet.text)
            for linia in sortida2 { sortida.errors += linia + "\n" }
            guard fet.correcte else { return Codi.fallida }
            return p.pla.excloses.isEmpty ? Codi.correcte : Codi.configuracioAmbErrors
        }
    }

    /// La finestra pel número (1…) o pel nom (sense mirar majúscules ni els espais dels extrems).
    static func triaFinestra(_ valor: String, de configuracio: Configuracio) throws(ErrorCLI) -> (Int, Finestra) {
        let finestres = configuracio.finestres
        let llista = finestres.enumerated().map { "  \($0 + 1). \($1.nom)" }.joined(separator: "\n")
        if let n = Int(valor), valor.allSatisfy(\.isASCII) {
            guard finestres.indices.contains(n - 1) else {
                throw .us("no hi ha cap finestra número \(n); n'hi ha \(finestres.count):\n\(llista)")
            }
            return (n, finestres[n - 1])
        }
        let clau = Validacio.clauDeNom(valor)
        let trobades = finestres.enumerated().filter { Validacio.clauDeNom($1.nom) == clau }
        switch trobades.count {
        case 1: return (trobades[0].offset + 1, trobades[0].element)
        case 0: throw .us("no hi ha cap finestra «\(valor)»; n'hi ha \(finestres.count):\n\(llista)")
        default:
            let numeros = trobades.map { String($0.offset + 1) }.joined(separator: ", ")
            throw .us("hi ha més d'una finestra «\(valor)» (\(numeros)): tria-la pel número")
        }
    }

    private static func llegeixWarp(_ lector: Lector) throws(ErrorCLI) -> LecturaWarp {
        do {
            return try lector.llegeix()
        } catch let ErrorLectura.noHiHaBase(ruta) {
            // 0.31.1: on no s'ha instal·lat mai Warp Stable, tampoc no hi ha la base. Es diu per què (cap Warp, o només
            // Warp Preview), com ho diria la lectura, i no només que no es troba la base.
            if let motiu = lector.senseWarpStable() {
                throw .fallida("\(motiu.text) Tampoc no hi ha la base de Warp (\(ruta)).")
            }
            throw .fallida("\(ErrorLectura.noHiHaBase(ruta))")
        } catch {
            throw .fallida("\(error)")
        }
    }

    /// La carpeta és la configuració real, o és a dins, o no se sap: també a través d'enllaços simbòlics, de
    /// `/System/Volumes/Data` o amb altres majúscules (el disc no les distingeix), i encara que la real no existeixi.
    static func esLaReal(_ carpeta: URL, real: URL) -> Bool {
        guard let a = Rutes.canonicaFinsOnExisteix(carpeta.path)?.lowercased(),
              let b = Rutes.canonicaFinsOnExisteix(real.path)?.lowercased()
        else { return true }
        return a == b || a.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }
}

/// Text d'una configuració per al CLI: cada finestra amb les seves pestanyes, els avisos de cadascuna i, al final, les
/// ordres de Claude que en sortirien, agrupades.
enum InformeConfiguracio {
    static func text(_ configuracio: Configuracio, avisos: AvisosConfiguracio, origens: [UUID: OrigenClaude]?,
                     inici: String) -> String {
        var linies: [String] = []
        var ordres: [String: Int] = [:]
        var senseOrdre = 0

        for finestra in configuracio.finestres {
            linies.append("")
            linies.append("\(finestra.nom) · \(finestra.resum)")
            for avis in avisos.finestres[finestra.id] ?? [] where avis.gravetat != .info {
                linies.append("  \(marca(avis)) \(avis)")
            }
            for (n, pestanya) in finestra.pestanyes.enumerated() {
                let numero = String(n + 1)
                let carpeta = Rutes.abreujada(pestanya.carpeta, inici: inici)
                linies.append(String(repeating: " ", count: max(0, 4 - numero.count)) + numero
                    + "  \(pestanya.titol) · \(carpeta) · \(origen(pestanya, origens?[pestanya.id]))")
                for avis in avisos.pestanyes[pestanya.id] ?? [] where avis.gravetat != .info {
                    linies.append("      \(marca(avis)) \(avis)")
                }
                guard pestanya.claude.activat else { continue }
                if let argv = try? OrdreClaude.argv(pestanya.claude, repren: nil) {
                    ordres[OrdreClaude.text(argv), default: 0] += 1
                } else {
                    senseOrdre += 1
                }
            }
        }

        if !ordres.isEmpty || senseOrdre > 0 {
            linies.append("")
            linies.append("Ordres de Claude:")
            for (ordre, quantes) in ordres.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) }) {
                linies.append(String(repeating: " ", count: max(0, 4 - String(quantes).count)) + "\(quantes)  \(ordre)")
            }
            if senseOrdre > 0 {
                linies.append("  \(Plural.compta(senseOrdre, "pestanya", "pestanyes")) sense ordre (vegeu els errors)")
            }
        }
        return linies.map { $0 + "\n" }.joined()
    }

    private static func marca(_ avis: Avis) -> String { avis.gravetat == .error ? "✗" : "⚠" }

    private static func origen(_ pestanya: Pestanya, _ origen: OrigenClaude?) -> String {
        guard pestanya.claude.activat else { return "sense Claude" }
        switch origen {
        case .sessio?: return "Claude, de la seva ordre"
        case .plantilla?: return "Claude, de la plantilla"
        default: return "Claude"
        }
    }
}
