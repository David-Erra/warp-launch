import Foundation
import Observation
import WarpLaunchCore

/// L'estat de l'editor: la configuració, la selecció, els avisos, el Desfés i el desat automàtic.
///
/// Viu tant com l'app: tancar la finestra de l'editor només l'amaga, i el Desfés no es perd (docs/disseny.md,
/// «Dock i activació»). No obre ni llegeix Warp: només el magatzem que se li passa.
///
/// Cada ordre és un sol pas de Desfés, amb el seu nom, que torna la configuració i la selecció d'abans. Els canvis
/// es desen junts 1 s després de l'últim (`retardDesat`), i a l'instant en amagar l'editor o sortir.
@MainActor
@Observable
public final class Editor {
    public enum Estat: Equatable {
        case carregant
        /// No hi ha `configuracio.json`. No s'escriu res fins que en David tria «Comença en blanc» o importa.
        case senseConfiguracio
        case oberta
        /// No s'ha pogut llegir (malmès, d'una versió més nova, sense permisos…). No s'hi pot escriure.
        case error(String)
    }

    public private(set) var estat: Estat = .carregant
    public private(set) var configuracio = Configuracio()
    /// El que s'ha corregit en llegir un fitxer editat a mà (`AvisFormat`). Surt en un bàner fins que en David el
    /// tanca o es torna a carregar.
    public private(set) var avisosFormat: [AvisFormat] = []
    /// Els avisos de cada finestra i pestanya (`Validacio`), al dia amb la configuració.
    public private(set) var avisos = AvisosConfiguracio()
    public var finestraSeleccionada: Finestra.ID? {
        didSet {
            // A «Per revisar», la finestra només es recorda: canviar-la no toca la llista que es veu.
            if finestraSeleccionada != oldValue, !perRevisar { pestanyesSeleccionades = [] }
            if finestraSeleccionada != oldValue { clauAgrupada = nil }
        }
    }
    /// La llista mostra «Per revisar» (les pestanyes amb avisos de totes les finestres) en lloc d'una finestra.
    /// `finestraSeleccionada` es manté, per tornar-hi.
    public var perRevisar = false {
        didSet {
            if perRevisar != oldValue {
                pestanyesSeleccionades = []
                clauAgrupada = nil
            }
        }
    }
    /// Pestanyes seleccionades de la llista que es veu. Canviar-les (o la finestra, o «Per revisar») tanca l'agrupació
    /// de canvis de text.
    public var pestanyesSeleccionades: Set<Pestanya.ID> = [] {
        didSet {
            if pestanyesSeleccionades != oldValue { clauAgrupada = nil }
        }
    }
    /// L'últim desat ha fallat. L'editor ho diu amb un bàner, i el menú de la icona també.
    public private(set) var errorDesat: ErrorMagatzem?
    public private(set) var canvisSenseDesar = false
    /// La fila on s'està escrivint el nom (Retorn, «Canvia el nom», o una finestra nova), i el que s'hi ha escrit.
    /// El text és aquí i no a la vista perquè no es perdi si l'editor s'amaga, se surt de l'app o es comença a
    /// escriure el nom d'una altra fila: en tots aquests casos es desa (`acabaNom`).
    public private(set) var nomEnEdicio: ElementNom?
    public var textDelNom = ""
    /// El full d'importació és obert (estat buit, o Fitxer › «Torna a importar-ho tot…»).
    public var demanaImportacio = false
    /// El diàleg de carpetes de «Nova pestanya…» és obert (⌘T, «+», el menú contextual o l'estat buit).
    public var demanaNovaPestanya = false
    /// L'inspector és a la vista (⌥⌘I, o el botó de la barra d'eines). Viu tant com l'app, com la selecció.
    public var mostraInspector = true
    /// Canvia cada cop que una finestra s'obre arrossegant (`obreArrossegant`). La vista el posa a la llista de
    /// pestanyes amb `.id`: la llista de la finestra oberta és una altra, i no la d'on ha sortit l'arrossegament, que
    /// en deixar-les anar faria servir les posicions de l'altra finestra (docs/fets-verificats.md, «Arrossegar a una
    /// `List`»). Un clic a la barra lateral no el canvia: la llista es queda, com a la 0.12.0.
    public private(set) var generacioLlista = 0
    /// S'arrossega una fila de la barra lateral (una finestra), no pestanyes. La barra lateral i la llista són totes
    /// dues `List` (`NSOutlineView`) amb `onMove`: si SwiftUI passés a l'una les posicions de l'altra, es mourien
    /// finestres o pestanyes que en David no ha tocat. `reordenaFinestres` només actua amb aquesta marca, i
    /// `reordena` (pestanyes) i obrir una finestra arrossegant, sense. La posa el `.itemProvider` de la fila d'una
    /// finestra, i la treu el d'una pestanya i el moviment mateix.
    private(set) var arrossegantFinestres = false
    /// Les pestanyes de l'última pulsació en una fila de pestanya: les files per a les quals SwiftUI demana el proveïdor
    /// (`comencaArrossegament`). En una mateixa pulsació, AppKit el demana per a la fila premuda i, si s'arrossega, per
    /// a cada fila arrossegada, després de canviar la selecció (⇧, ⌘), tot en pocs mil·lisegons (binari de macOS 27.2).
    /// No es fa servir la selecció: SwiftUI encara no l'ha actualitzada.
    @ObservationIgnored private(set) var pestanyesArrossegades: Set<Pestanya.ID> = []
    @ObservationIgnored private var darreraCridaDelProveidor = Date.distantPast
    /// Les de `pestanyesArrossegades`, fixades mentre l'arrossegament passa per la fila d'una finestra, quan encara no
    /// es pot fer cap clic. La fila no sempre rep les dades: la càrrega es cancel·la (NSItemProvider -1000, Cocoa
    /// 3072; prova 7b) i l'acció arriba ~0,3 s després amb 0 pestanyes. Llavors es mouen aquestes, si l'arrossegament
    /// és d'aquesta app i en porta les mateixes (`deixaAnar(_:a:local:elements:)`). Es buiden en deixar anar.
    @ObservationIgnored private(set) var pestanyesFixades: Set<Pestanya.ID> = []
    /// Puja quan unes pestanyes arriben a la llista que es veu (la de la finestra oberta arrossegant): la llista és nova
    /// (`generacioLlista`) i no té el focus, i sense això ↓, ⌘C o ⌫ no hi actuen fins a fer-hi clic.
    public private(set) var demanaFocusLlista = 0
    /// La selecció d'abans d'obrir una finestra arrossegant. Mentre hi és, la llista que es veu no és la d'on ha
    /// sortit l'arrossegament: `reordena` no fa res, la fila de la finestra que es veu accepta les pestanyes, i
    /// deixar-les anar torna aquí amb ⌘Z. Es treu en començar un altre arrossegament (`.itemProvider` →
    /// `comencaArrossegament`), en deixar-les anar (a la fila o a la llista, encara que no canviï res), amb qualsevol
    /// canvi, amb Desfés i Refés, i en carregar.
    private(set) var abansDObrir: Seleccio?

    /// El valor d'un camp a les pestanyes seleccionades: el mateix a totes, «Valors diversos», o cap pestanya.
    public enum Comu<Valor: Equatable>: Equatable {
        case cap
        case un(Valor)
        case diversos
    }

    /// Una fila de la barra lateral.
    public enum ElementLateral: Hashable, Sendable {
        case perRevisar
        case finestra(Finestra.ID)
    }

    /// Una fila on es pot escriure el nom.
    public enum ElementNom: Hashable, Sendable {
        case finestra(Finestra.ID)
        case pestanya(Pestanya.ID)
    }

    /// La selecció: la finestra (es recorda també a «Per revisar»), si es veu «Per revisar», i les pestanyes triades.
    struct Seleccio: Equatable {
        var finestra: Finestra.ID?
        var perRevisar: Bool
        var pestanyes: Set<Pestanya.ID>
    }

    private var seleccio: Seleccio {
        Seleccio(finestra: finestraSeleccionada, perRevisar: perRevisar, pestanyes: pestanyesSeleccionades)
    }

    /// Les pestanyes amb avisos d'una finestra, per a «Per revisar».
    public struct GrupPerRevisar: Identifiable, Equatable {
        public var finestra: Finestra
        public var pestanyes: [Pestanya]
        public var id: Finestra.ID { finestra.id }
    }

    /// El Desfés. L'app hi posa el de la finestra de l'editor (`usaUndoManager`), que és el que fan servir
    /// Edició › Desfés (⌘Z) i els camps de text; no es perd en amagar l'editor, perquè la finestra només s'amaga.
    /// Fins llavors (i a les proves) és un de propi.
    @ObservationIgnored public private(set) var undoManager: UndoManager
    /// La conversa que reprendria cada pestanya, per a l'ordre que es mostra i es copia (D15). L'app hi posa la
    /// d'`EstatSessions`; sense, cap (l'ordre en comença una de nova).
    @ObservationIgnored public var conversaDe: @MainActor (Pestanya) -> String? = { _ in nil }
    /// Després de crear la configuració o tornar a importar: l'app hi desa els lligams de les pestanyes (`estat.json`).
    @ObservationIgnored public var enImportar: @MainActor (Importacio) -> Void = { _ in }
    /// Obrir una finestra a Warp (fase 3.1). L'app l'hi posa; sense (a les proves de l'editor, o sense carpeta), les
    /// ordres «Obre…» queden desactivades.
    @ObservationIgnored public var obertura: Obertura?
    /// «Lliga amb Warp…» (fase 3.1). L'app l'hi posa; sense, l'ordre queda desactivada.
    @ObservationIgnored public var lligam: Lligam?
    /// `nil` si l'app s'ha obert amb arguments incorrectes: llavors no es llegeix ni s'escriu res.
    @ObservationIgnored private let magatzem: MagatzemConfiguracio?
    @ObservationIgnored private let motiuSenseCarpeta: String?
    @ObservationIgnored let inici: String
    @ObservationIgnored let carpetaExisteix: (String) -> Bool
    @ObservationIgnored private let nouId: () -> UUID
    @ObservationIgnored private var empremta: Data?
    @ObservationIgnored private var copiaDeSessioFeta = false
    /// Les finestres amb pestanyes del fitxer tal com és al disc: si en desar en falta alguna, abans es fa còpia.
    @ObservationIgnored private var finestresDesades: Set<Finestra.ID> = []
    /// Les finestres de l'última importació («Torna a importar») encara sense desar: si en desar hi són, la còpia
    /// és `importacio`.
    @ObservationIgnored private var finestresImportades: Set<Finestra.ID> = []
    @ObservationIgnored private let retardDesat: Duration?
    @ObservationIgnored private var desatProgramat: Task<Void, Never>?
    /// L'últim canvi agrupable (escriure en un camp): els següents amb la mateixa clau no fan un pas de Desfés nou.
    @ObservationIgnored private var clauAgrupada: String?
    /// Les finestres d'abans del pas agrupat obert: si un camp hi torna, el pas ja no canvia res i es treu.
    @ObservationIgnored private var finestresEnObrirGrup: [Finestra]?
    /// El Desfés de la plantilla: el de la finestra de Configuració (`usaDesferPlantilla`). Fins llavors (i a les
    /// proves), un de propi. És un altre que el de l'editor: el de l'editor només desfà finestres, i aquest, només la
    /// plantilla. Si fossin el mateix, ⌘Z a l'editor tornaria a posar una plantilla vella sense que es vegi.
    @ObservationIgnored public private(set) var desferPlantilla: UndoManager
    /// Quantes vegades s'ha escrit el fitxer. Per a les proves.
    @ObservationIgnored private(set) var escriptures = 0

    /// - Parameters:
    ///   - retardDesat: quant s'espera després de l'últim canvi per desar. `nil` vol dir que no es desa sol (les
    ///     proves criden `desaSiCal()`).
    ///   - carpetaExisteix: per als avisos; l'app mira el disc, i les proves, una llista.
    ///   - nouId: els id de les finestres i pestanyes noves.
    public convenience init(magatzem: MagatzemConfiguracio, retardDesat: Duration? = .seconds(1),
                            carpetaExisteix: @escaping (String) -> Bool = Validacio.carpetaExisteixAlDisc,
                            nouId: @escaping () -> UUID = { UUID() }) {
        self.init(magatzem: magatzem, motiuSenseCarpeta: nil, retardDesat: retardDesat,
                  carpetaExisteix: carpetaExisteix, nouId: nouId)
    }

    /// Sense cap carpeta (arguments incorrectes): l'editor mostra el motiu i no toca cap fitxer.
    public convenience init(senseCarpeta motiu: String) {
        self.init(magatzem: nil, motiuSenseCarpeta: motiu, retardDesat: nil, carpetaExisteix: { _ in false },
                  nouId: { UUID() })
    }

    private init(magatzem: MagatzemConfiguracio?, motiuSenseCarpeta: String?, retardDesat: Duration?,
                 carpetaExisteix: @escaping (String) -> Bool, nouId: @escaping () -> UUID) {
        self.magatzem = magatzem
        self.motiuSenseCarpeta = motiuSenseCarpeta
        self.retardDesat = retardDesat
        self.carpetaExisteix = carpetaExisteix
        self.nouId = nouId
        inici = magatzem.map { Rutes.canonica($0.inici) } ?? ""
        undoManager = UndoManager()
        desferPlantilla = UndoManager()
        // El propi, sense finestra: cada canvi és un grup explícit i no depèn del bucle d'esdeveniments. El de la
        // finestra no es toca mai (un `TextEditor` hi registra sense obrir cap grup i, amb `false`, l'app petaria).
        undoManager.groupsByEvent = false
        desferPlantilla.groupsByEvent = false
    }

    public var potEditar: Bool { estat == .oberta }

    /// On es desa la configuració, abreujat amb `~` (per al full d'importació).
    public var rutaFitxer: String? {
        magatzem.map { Rutes.abreujada($0.fitxer.path, inici: $0.inici) }
    }

    /// El fitxer de la configuració, sense abreujar; `nil` sense carpeta.
    public var fitxerConfiguracio: URL? { magatzem?.fitxer }

    /// Passa a fer servir el Desfés de la finestra de l'editor, sense tocar-ne `groupsByEvent`. AppKit el crea
    /// abans que l'app pugui posar el seu delegat a la finestra, i després ja no en demana cap altre
    /// (docs/fets-verificats.md, «SwiftUI i AppKit»): per això és l'editor qui fa servir el de la finestra.
    public func usaUndoManager(_ nou: UndoManager) {
        guard nou !== undoManager, nou !== desferPlantilla else { return }
        undoManager.removeAllActions()
        undoManager = nou
        clauAgrupada = nil
    }

    /// Passa a fer servir el Desfés de la finestra de Configuració per a la plantilla. Mai el de l'editor: es
    /// barrejarien.
    public func usaDesferPlantilla(_ nou: UndoManager) {
        guard nou !== desferPlantilla, nou !== undoManager else { return }
        desferPlantilla.removeAllActions()
        desferPlantilla = nou
    }

    public var finestra: Finestra? {
        finestraSeleccionada.flatMap(configuracio.finestra)
    }

    /// La selecció de la barra lateral.
    public var lateral: ElementLateral? {
        get { perRevisar ? .perRevisar : finestraSeleccionada.map { .finestra($0) } }
        set {
            switch newValue {
            case .perRevisar:
                perRevisar = true
            case let .finestra(id):
                perRevisar = false
                finestraSeleccionada = id
            case nil:
                // Un clic al buit de la barra lateral: es queda la selecció que hi havia.
                break
            }
        }
    }

    /// Les pestanyes de la llista: les de la finestra, o les de «Per revisar».
    public var pestanyesVisibles: [Pestanya] {
        perRevisar ? perRevisarPerFinestra.flatMap(\.pestanyes) : finestra?.pestanyes ?? []
    }

    /// Les pestanyes seleccionades que es veuen, en l'ordre de la llista.
    public var pestanyes: [Pestanya] {
        pestanyesVisibles.filter { pestanyesSeleccionades.contains($0.id) }
    }

    /// Els id seleccionats que es veuen: les ordres només actuen sobre el que es veu.
    private var seleccioVisible: Set<Pestanya.ID> {
        Set(pestanyes.map(\.id))
    }

    // MARK: - Avisos

    /// L'avís que surt a la fila d'una pestanya: el primer error o, si no n'hi ha, el primer avís. Els d'informació
    /// només surten a l'inspector.
    public func avisPrincipal(_ pestanya: Pestanya.ID) -> Avis? {
        Self.principal(avisos.pestanyes[pestanya] ?? [])
    }

    /// L'avís de la fila d'una finestra (un nom repetit).
    public func avisPrincipal(finestra: Finestra.ID) -> Avis? {
        Self.principal(avisos.finestres[finestra] ?? [])
    }

    private static func principal(_ avisos: [Avis]) -> Avis? {
        avisos.first { $0.gravetat == .error } ?? avisos.first { $0.gravetat == .avis }
    }

    /// Les pestanyes amb algun avís a la fila, per finestres, en l'ordre de la configuració. Una pestanya
    /// seleccionada s'hi queda encara que ja no en tingui (s'ha arreglat des de l'inspector), fins que se'n tria una
    /// altra: si no, desapareixeria mentre s'edita.
    public var perRevisarPerFinestra: [GrupPerRevisar] {
        configuracio.finestres.compactMap { finestra in
            let amb = finestra.pestanyes.filter { avisPrincipal($0.id) != nil || pestanyesSeleccionades.contains($0.id) }
            return amb.isEmpty ? nil : GrupPerRevisar(finestra: finestra, pestanyes: amb)
        }
    }

    /// Quantes pestanyes hi ha a «Per revisar».
    public var nombrePerRevisar: Int {
        configuracio.finestres.reduce(0) { $0 + $1.pestanyes.filter { avisPrincipal($0.id) != nil }.count }
    }

    /// Els avisos d'una altra configuració (la d'una importació), amb la mateixa carpeta d'inici.
    public func avisos(de altra: Configuracio) -> AvisosConfiguracio {
        Validacio.avisos(altra, inici: inici, carpetaExisteix: carpetaExisteix)
    }

    /// El títol de la finestra de l'editor: la finestra de Warp seleccionada, o «Per revisar».
    public var titol: String {
        perRevisar ? "Per revisar" : finestra?.nom ?? WarpLaunch.nom
    }

    /// «12 pestanyes · 8 amb Claude · 2 avisos». Si no s'ha pogut desar, ho diu.
    public var subtitol: String {
        if let errorDesat {
            return errorDesat == .modificadaFora ? "El fitxer ha canviat fora de l'app" : "No s'ha pogut desar"
        }
        if perRevisar {
            let n = nombrePerRevisar
            return n == 0 ? "Res per revisar" : "\(Plural.compta(n, "pestanya", "pestanyes")) per revisar"
        }
        guard let finestra else { return "" }
        let n = finestra.pestanyes.filter { avisPrincipal($0.id) != nil }.count
            + (avisPrincipal(finestra: finestra.id) == nil ? 0 : 1)
        return finestra.resum + (n == 0 ? "" : " · \(Plural.compta(n, "avís", "avisos"))")
    }

    /// On s'obre el diàleg de «Nova pestanya…»: la carpeta que conté la de l'última pestanya seleccionada (o la de
    /// l'última de la finestra), per triar-ne una del costat. Si no n'hi ha cap, o és a `~`, la d'inici.
    public var carpetaSuggerida: String {
        let referencia = pestanyes.last ?? finestra?.pestanyes.last
        guard let carpeta = referencia.map({ ($0.carpeta as NSString).standardizingPath }), carpeta.hasPrefix("/"),
              carpeta != (inici as NSString).standardizingPath
        else { return inici }
        return (carpeta as NSString).deletingLastPathComponent
    }

    // MARK: - Carregar

    /// Llegeix la configuració del disc i descarta els canvis sense desar i el Desfés.
    public func carrega() {
        desatProgramat?.cancel()
        undoManager.removeAllActions()
        desferPlantilla.removeAllActions()
        canvisSenseDesar = false
        errorDesat = nil
        nomEnEdicio = nil
        abansDObrir = nil
        finestresImportades = []
        finestresDesades = []
        clauAgrupada = nil
        avisosFormat = []
        empremta = nil
        configuracio = Configuracio()
        if let magatzem {
            do {
                if let carregada = try magatzem.carrega() {
                    configuracio = carregada.configuracio
                    avisosFormat = carregada.avisos
                    empremta = carregada.empremta
                    estat = .oberta
                    recordaDesades()
                } else {
                    estat = .senseConfiguracio
                }
            } catch {
                estat = .error(error.description)
            }
        } else {
            estat = .error(motiuSenseCarpeta ?? "no hi ha cap carpeta de configuració")
        }
        actualitzaAvisos()
        ajustaSeleccio()
    }

    /// Quan l'editor passa al davant: torna a mirar les carpetes (els avisos) i si el fitxer ha canviat fora.
    public func enMostrar() {
        comprovaCanviExtern()
        if estat == .oberta {
            actualitzaAvisos()
            ajustaSeleccio()
        }
    }

    /// Mira si el fitxer ha canviat fora de l'app. Si no hi ha canvis sense desar, el torna a carregar; si n'hi ha, no
    /// toca res i ho diu (`modificadaFora`), com faria el desat. Si el fitxer torna a ser com era, el bàner se'n va.
    public func comprovaCanviExtern() {
        guard let magatzem, estat != .carregant else { return }
        let actual: Data?
        do {
            actual = try magatzem.bytesActuals()
        } catch {
            if !canvisSenseDesar { carrega() }
            return
        }
        guard actual != empremta else {
            if errorDesat == .modificadaFora { errorDesat = nil }
            return
        }
        if canvisSenseDesar {
            errorDesat = .modificadaFora
        } else {
            carrega()
        }
    }

    /// Crea una configuració buida. La plantilla és la segura (sense saltar permisos), la mateixa que en importar, fins
    /// que es canviï a la Configuració.
    public func comencaEnBlanc() {
        guard estat == .senseConfiguracio else { return }
        configuracio = Configuracio(plantilla: .perOmissio)
        estat = .oberta
        actualitzaAvisos()
        canvisSenseDesar = true
        desaSiCal()
    }

    // MARK: - Importar

    /// La plantilla amb què s'importa: la de la configuració, o, si encara no n'hi ha, la segura, com «Comença en
    /// blanc»: sense saltar els permisos ni ultracode (D11, revisada per en David el 07/11/2026). Les opcions es trien
    /// després, a la Configuració o a cada pestanya.
    public var plantillaPerImportar: ClaudePestanya {
        estat == .oberta ? configuracio.plantilla : .perOmissio
    }

    /// Què reben les pestanyes que no tenien Claude obert: en una configuració nova, només terminal (D-P5a, en David,
    /// 07/11/2026), i també en una que encara no té cap pestanya, com després de «Comença en blanc» (08/11/2026); en
    /// tornar a importar sobre alguna pestanya, Claude amb la plantilla, com fins ara (D11).
    public var senseSessioPerImportar: Importador.SenseSessio {
        .per(estat == .oberta ? configuracio : nil)
    }

    /// El que sortiria d'importar una lectura de Warp, per al full de previsualització. No canvia res.
    public func previsualitza(_ lectura: LecturaWarp) -> Importacio {
        Importador.importa(lectura, inici: inici, plantilla: plantillaPerImportar, senseSessio: senseSessioPerImportar,
                           nouId: nouId)
    }

    /// «Crea» del full d'importació, quan encara no hi ha configuració: la desa de seguida.
    public func crea(amb importacio: Importacio) {
        guard estat == .senseConfiguracio, magatzem != nil else { return }
        configuracio = importacio.configuracio
        estat = .oberta
        actualitzaAvisos()
        ajustaSeleccio()
        canvisSenseDesar = true
        // Sense la configuració al disc, `estat.json` no s'escriu.
        if desaSiCal() { enImportar(importacio) }
    }

    /// «Torna a importar-ho tot…»: substitueix les finestres, amb còpia abans de desar i Desfés. La plantilla no
    /// canvia. Si ha canviat després de previsualitzar, les pestanyes importades la porten vella: el full no deixa
    /// substituir fins a tornar a llegir (`FullImportacio.plantillaHaCanviat`).
    public func substitueix(amb importacio: Importacio) {
        guard potEditar else { return }
        let abans = configuracio
        canvia("Torna a importar") { $0.finestres = importacio.configuracio.finestres }
        // Si no ha canviat res (la mateixa importació dues vegades), no cal cap còpia.
        if configuracio != abans {
            finestresImportades = Set(importacio.configuracio.finestres.map(\.id))
            enImportar(importacio)
        }
        ajustaSeleccio()
    }

    // MARK: - Finestres

    /// Afegeix una finestra buida després de la seleccionada (o al final), la selecciona i n'obre el nom per escriure'l.
    public func afegeixFinestra() {
        guard potEditar else { return }
        let nomPendent = prenNomPendent()
        let nova = nouId()
        canvia("Nova finestra") {
            nomPendent?(&$0)
            // El nom, després del pendent: si aquell deixa lliure «Finestra nova», la nova el pot fer servir.
            $0.afegeix(Finestra(id: nova, nom: $0.nomUnic("Finestra nova"), pestanyes: []), despresDe: finestraSeleccionada)
        }
        lateral = .finestra(nova)
        comencaNom(.finestra(nova))
    }

    // MARK: - Canviar el nom a la fila

    /// Obre el camp del nom d'una fila. Si se n'estava escrivint un altre, abans el desa.
    public func comencaNom(_ element: ElementNom) {
        guard potEditar else { return }
        acabaNom(desant: true)
        guard let actual = nom(de: element) else { return }
        textDelNom = actual
        nomEnEdicio = element
    }

    /// Tanca el camp del nom. Amb `desant`, hi posa el text (un pas de Desfés, «Canvia el nom»; una finestra no pot
    /// quedar sense nom). Amb `element`, només si és el que s'està editant: un camp que ja no és l'actiu no tanca el
    /// d'una altra fila.
    public func acabaNom(_ element: ElementNom? = nil, desant: Bool) {
        guard let actual = nomEnEdicio, element == nil || element == actual else { return }
        nomEnEdicio = nil
        guard desant, let abans = nom(de: actual), textDelNom != abans else { return }
        switch actual {
        case let .finestra(id): reanomenaFinestra(id, a: textDelNom)
        case let .pestanya(id): reanomenaPestanya(id, a: textDelNom)
        }
    }

    /// Tanca el camp del nom i en torna el canvi, perquè l'ordre que el tanca el posi dins del seu pas de Desfés.
    /// Amb el Desfés de la finestra (`groupsByEvent`), dos passos del mateix esdeveniment (el nom i, per exemple, el
    /// moviment de «Mou a ▸» amb el camp obert) es desfarien junts igualment: així les proves i l'app fan el mateix.
    private func prenNomPendent() -> ((inout Configuracio) -> Void)? {
        guard let actual = nomEnEdicio else { return nil }
        nomEnEdicio = nil
        guard let abans = nom(de: actual), textDelNom != abans else { return nil }
        let text = textDelNom
        switch actual {
        case let .finestra(id): return { $0.reanomenaFinestra(id, a: text) }
        case let .pestanya(id): return { $0.canviaPestanyes([id]) { $0.titol = text } }
        }
    }

    private func nom(de element: ElementNom) -> String? {
        switch element {
        case let .finestra(id): configuracio.finestra(id)?.nom
        case let .pestanya(id): configuracio.pestanya(id)?.titol
        }
    }

    /// - Parameter agrupa: per al camp de text de l'inspector (vegeu `canviaClaude`).
    public func reanomenaFinestra(_ id: Finestra.ID, a nom: String, agrupa: String? = nil) {
        guard potEditar else { return }
        canvia("Canvia el nom", agrupa: Self.clau(agrupa, [id])) { $0.reanomenaFinestra(id, a: nom) }
    }

    /// Elimina una finestra, sense confirmació (es desfà amb ⌘Z; si tenia pestanyes, abans de desar es fa còpia).
    /// Queda seleccionada la següent, o l'anterior.
    public func eliminaFinestra(_ id: Finestra.ID) {
        guard potEditar else { return }
        var index: Int?
        canvia("Elimina la finestra") { index = $0.eliminaFinestra(id) }
        if let index, finestraSeleccionada == id {
            let finestres = configuracio.finestres
            finestraSeleccionada = finestres.isEmpty ? nil : finestres[min(index, finestres.count - 1)].id
        }
        ajustaSeleccio()
    }

    public func duplicaFinestra(_ id: Finestra.ID) {
        guard potEditar else { return }
        var copia: Finestra.ID?
        // Un nom a mig escriure (⌘D amb el camp obert) va al mateix pas.
        let nomPendent = prenNomPendent()
        canvia("Duplica la finestra") {
            nomPendent?(&$0)
            copia = $0.duplicaFinestra(id, nouId: nouId)
        }
        if let copia { lateral = .finestra(copia) }
    }

    // MARK: - Pestanyes

    /// Es pot afegir una pestanya: hi ha una finestra a la llista (no «Per revisar»).
    public var potAfegirPestanya: Bool { potEditar && !perRevisar && finestra != nil }

    /// «Nova pestanya…»: a la finestra seleccionada, després de l'última pestanya seleccionada (o al final), amb la
    /// plantilla. Queda seleccionada.
    public func afegeixPestanya(carpeta: String) {
        guard potAfegirPestanya, let finestra else { return }
        let nova = Pestanya.nova(id: nouId(), carpeta: carpeta, plantilla: configuracio.plantilla, inici: inici)
        let despres = finestra.pestanyes.lastIndex { pestanyesSeleccionades.contains($0.id) }
        canvia("Nova pestanya") { $0.afegeix(nova, a: finestra.id, index: despres.map { $0 + 1 }) }
        pestanyesSeleccionades = [nova.id]
    }

    /// Duplica les pestanyes seleccionades (sense nom fix de sessió) i selecciona les còpies.
    public func duplicaPestanyes() {
        let seleccionades = seleccioVisible
        guard potEditar, !seleccionades.isEmpty else { return }
        var noves: [Pestanya.ID] = []
        let nomPendent = prenNomPendent()
        canvia(seleccionades.count == 1 ? "Duplica la pestanya" : "Duplica les pestanyes") {
            nomPendent?(&$0)
            noves = $0.duplicaPestanyes(seleccionades, nouId: nouId)
        }
        pestanyesSeleccionades = Set(noves)
    }

    /// Elimina les pestanyes seleccionades, sense confirmació. Queda seleccionada la que venia després a la llista.
    public func eliminaPestanyes() {
        elimina(accio: seleccioVisible.count == 1 ? "Elimina la pestanya" : "Elimina les pestanyes")
    }

    private func elimina(accio: String) {
        let seleccionades = seleccioVisible
        guard potEditar, !seleccionades.isEmpty else { return }
        let llista = pestanyesVisibles
        let restants = llista.filter { !seleccionades.contains($0.id) }
        let primera = llista.firstIndex { seleccionades.contains($0.id) } ?? 0
        let seguent = llista[primera...].first { !seleccionades.contains($0.id) } ?? restants.last
        canvia(accio) { $0.eliminaPestanyes(seleccionades) }
        pestanyesSeleccionades = seguent.map { [$0.id] } ?? []
    }

    // MARK: - Porta-retalls (⌘C, ⌘X, ⌘V)

    /// Les pestanyes triades que es veuen, per al porta-retalls (`PortaRetalls`). `nil` si no n'hi ha cap.
    public func copiaPestanyes() -> Data? {
        let triades = pestanyes
        guard !triades.isEmpty else { return nil }
        return try? PortaRetalls.dades(triades)
    }

    /// ⌘X: les copia i les elimina, en un sol pas de Desfés.
    public func retallaPestanyes() -> Data? {
        guard potEditar, let dades = copiaPestanyes() else { return nil }
        elimina(accio: pestanyes.count == 1 ? "Retalla la pestanya" : "Retalla les pestanyes")
        return dades
    }

    /// Es pot enganxar a la finestra que es veu (a «Per revisar», no: no hi ha cap finestra on posar-les).
    public var potEnganxar: Bool { potAfegirPestanya }

    /// ⌘V: les pestanyes del porta-retalls, a la finestra que es veu, després de l'última triada (o al final). Les
    /// copiades entren com a còpies; les retallades, tal com eren (`Configuracio.enganxa`). Queden triades.
    /// - Returns: `false` si no s'ha enganxat res (no es pot, o les dades no són pestanyes).
    @discardableResult
    public func enganxa(_ dades: Data) -> Bool {
        guard potEnganxar, let finestra, let noves = PortaRetalls.pestanyes(de: dades, inici: inici) else { return false }
        let despresDe = finestra.pestanyes.last { pestanyesSeleccionades.contains($0.id) }?.id
        var ids: [Pestanya.ID] = []
        canvia(noves.count == 1 ? "Enganxa la pestanya" : "Enganxa les pestanyes") {
            ids = $0.enganxa(noves, a: finestra.id, despresDe: despresDe, nouId: nouId)
        }
        pestanyesSeleccionades = Set(ids)
        return !ids.isEmpty
    }

    public func reanomenaPestanya(_ id: Pestanya.ID, a titol: String, agrupa: String? = nil) {
        guard potEditar else { return }
        canvia("Canvia el nom", agrupa: Self.clau(agrupa, [id])) { $0.canviaPestanyes([id]) { $0.titol = titol } }
    }

    /// Mou pestanyes a una finestra (reordenar, arrossegar o «Mou a ▸»). `index`: la posició de la llista de destinació
    /// on es deixen anar, abans de treure'n les que es mouen; `nil`, al final. Si canvien de finestra, la selecció les
    /// segueix. El nom que s'estigués escrivint es desa en el mateix pas de Desfés.
    public func mouPestanyes(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID, index: Int? = nil) {
        mou(ids, a: desti, index: index, seleccioAbans: nil)
    }

    /// - Parameter seleccioAbans: la selecció a què torna ⌘Z, i la que decideix si l'editor segueix les pestanyes. Per
    ///   defecte, la d'ara; després d'obrir una finestra arrossegant, la d'abans d'obrir-la (`abansDObrir`).
    private func mou(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID, index: Int?, seleccioAbans: Seleccio?) {
        // El nom del pas compta les que existeixen: un id vell no fa dir «les pestanyes» movent-ne una.
        let mogudes = configuracio.finestres.reduce(0) { $0 + $1.pestanyes.filter { ids.contains($0.id) }.count }
        guard potEditar, mogudes > 0, configuracio.finestra(desti) != nil else { return }
        let nomPendent = prenNomPendent()
        let abans = seleccioAbans ?? seleccio
        // A «Per revisar» les pestanyes no desapareixen de la llista en canviar de finestra: no cal seguir-les.
        let seguir = !abans.perRevisar && abans.finestra != desti && !abans.pestanyes.isEmpty
            && abans.pestanyes.isSubset(of: ids)
        canvia(mogudes == 1 ? "Mou la pestanya" : "Mou les pestanyes", seleccioAbans: abans) {
            nomPendent?(&$0)
            $0.mouPestanyes(ids, a: desti, index: index)
        }
        if seguir {
            // Tota la selecció ha canviat de finestra: la segueix.
            finestraSeleccionada = desti
            pestanyesSeleccionades = ids
        } else {
            // Les que han marxat ja no es veuen: deixen d'estar seleccionades.
            ajustaSeleccio()
        }
    }

    // MARK: - Arrossegar i «Mou a ▸» (pas 10)

    /// Es pot reordenar arrossegant: a la llista d'una finestra. A «Per revisar» no: cada secció és una part de la
    /// finestra, i la posició on es deixen anar no seria la de la finestra.
    public var potReordenar: Bool { potEditar && !perRevisar && finestra != nil }

    /// `onMove` de la llista d'una finestra. `origens` i `desti` són posicions de `finestra.pestanyes` (`desti`, abans
    /// de treure'n les que es mouen, com `move(fromOffsets:toOffset:)`). Un sol pas de Desfés; les mogudes queden
    /// triades (mac-design 74).
    ///
    /// Després d'obrir una finestra arrossegant (`abansDObrir`), no fa res: les posicions podrien ser les de la llista
    /// d'on ha sortit l'arrossegament, i mourien pestanyes que en David no ha tocat. A la llista nova, les pestanyes
    /// arriben per `deixaAnar(_:a:index:)`, pels id.
    public func reordena(_ origens: IndexSet, a desti: Int) {
        guard potReordenar, abansDObrir == nil, !arrossegantFinestres, let finestra else { return }
        let ids = Set(origens.filter(finestra.pestanyes.indices.contains).map { finestra.pestanyes[$0].id })
        guard !ids.isEmpty else { return }
        mouPestanyes(ids, a: finestra.id, index: desti)
        pestanyesSeleccionades = ids
    }

    /// Moure-hi aquestes pestanyes canviaria alguna cosa: la finestra existeix i n'hi falta alguna.
    public func potMoure(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID) -> Bool {
        guard potEditar, let finestra = configuracio.finestra(desti) else { return false }
        let existents = configuracio.finestres.flatMap(\.pestanyes).map(\.id).filter(ids.contains)
        return !Set(existents).isSubset(of: finestra.pestanyes.map(\.id))
    }

    /// Les finestres de «Mou a ▸»: des d'una finestra, totes les altres; a «Per revisar», les que no les tenen ja
    /// totes. Buit (el submenú no surt) si no n'hi ha cap.
    public func finestresPerMoure(_ ids: Set<Pestanya.ID>) -> [Finestra] {
        configuracio.finestres.filter { potMoure(ids, a: $0.id) }
    }

    /// El text d'una finestra a «Mou a ▸»: el nom i, si una altra es diu igual, el resum, per distingir-les.
    public func etiquetaPerMoure(_ finestra: Finestra) -> String {
        let repetit = avisos.finestres[finestra.id]?.contains {
            if case .nomRepetit = $0.tipus { true } else { false }
        } ?? false
        return repetit ? "\(finestra.nom) — \(finestra.resum)" : finestra.nom
    }

    /// Mou pestanyes al final d'una finestra (fila de la barra lateral o «Mou a ▸»). Les que ja hi són es queden on
    /// són: a «Per revisar» la selecció pot tenir pestanyes de la finestra de destinació, i allà no es reordena.
    public func mouA(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID) {
        mouA(ids, a: desti, seleccioAbans: nil)
    }

    private func mouA(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID, seleccioAbans: Seleccio?) {
        guard potMoure(ids, a: desti), let finestra = configuracio.finestra(desti) else { return }
        mou(ids.subtracting(finestra.pestanyes.map(\.id)), a: desti, index: nil, seleccioAbans: seleccioAbans)
    }

    /// La fila d'una finestra de la barra lateral accepta pestanyes arrossegades: totes menys la de la llista que es
    /// veu, on ja són (a «Per revisar», totes). Si la finestra que es veu s'ha obert arrossegant, la seva fila també:
    /// les pestanyes vénen d'una altra.
    public func acceptaPestanyes(_ desti: Finestra.ID) -> Bool {
        potEditar && configuracio.finestra(desti) != nil
            && (perRevisar || finestraSeleccionada != desti || abansDObrir != nil)
    }

    /// Pestanyes deixades anar sobre la fila d'una finestra: van al final, en un sol pas de Desfés. Només les
    /// arrossegades en aquesta execució de l'app (`PestanyaArrossegada.aquestProces`).
    /// - Returns: si se n'ha mogut alguna.
    /// - Parameters:
    ///   - local: l'arrossegament surt d'aquesta app (`DropSession.localSession`).
    ///   - elements: quants elements porta (`DropSession.itemsCount`).
    @discardableResult
    public func deixaAnar(_ arrossegades: [PestanyaArrossegada], a desti: Finestra.ID, local: Bool = false,
                          elements: Int = 0) -> Bool {
        let fixades = pestanyesFixades
        pestanyesFixades = []
        let ids: Set<Pestanya.ID>
        if arrossegades.isEmpty {
            // Les dades no han arribat: les fixades, només si no hi ha cap dubte que són les arrossegades.
            ids = local && !arrossegantFinestres && elements == fixades.count ? fixades : []
            Registre.arrossegar.notice("""
                fila \(Registre.curt(desti), privacy: .public): sense dades, local \(local), \(elements) elements, \
                \(fixades.count) fixades
                """)
        } else {
            ids = Self.dAquestaExecucio(arrossegades)
        }
        let accepta = acceptaPestanyes(desti), potMoure = potMoure(ids, a: desti)
        Registre.arrossegar.notice("""
            fila \(Registre.curt(desti), privacy: .public): \(arrossegades.count) arrossegades, \(ids.count) per moure, \
            accepta \(accepta), potMoure \(potMoure), oberta \(self.abansDObrir != nil)
            """)
        guard accepta, potMoure else { return false }
        let abans = abansDObrir
        abansDObrir = nil
        mouA(ids, a: desti, seleccioAbans: abans)
        // La fila de la finestra oberta arrossegant: com a la seva llista (`deixaAnar(_:a:index:)`), les que hi han
        // arribat queden triades, encara que no fossin les triades d'abans d'obrir-la.
        if abans != nil, !perRevisar, finestraSeleccionada == desti, let finestra {
            pestanyesSeleccionades = ids.intersection(finestra.pestanyes.map(\.id))
            demanaFocusLlista += 1
        }
        return true
    }

    /// Només les d'aquesta execució de l'app: una altra pot tenir els mateixos id.
    private static func dAquestaExecucio(_ arrossegades: [PestanyaArrossegada]) -> Set<Pestanya.ID> {
        Set(arrossegades.filter { $0.origen == PestanyaArrossegada.aquestProces }.map(\.id))
    }

    /// L'arrossegament passa per la fila d'una finestra (`onDropSessionUpdated`): fixa les pestanyes de l'última
    /// pulsació, abans que un clic les pugui canviar.
    public func fixaPestanyesArrossegades() {
        pestanyesFixades = pestanyesArrossegades
    }

    // MARK: - Obrir una finestra arrossegant (pas 10b)

    /// La fila d'una finestra s'obre si s'hi atura el cursor arrossegant pestanyes, com les carpetes del Finder: una
    /// altra finestra amb pestanyes. La que es veu no (ja hi és), ni «Per revisar» (no s'hi pot deixar res), ni una de
    /// buida: només hi ha un lloc on posar-les, i obrir-la treu de la pantalla la llista d'on surten (sense cap llista
    /// que la substitueixi, no s'accepta res enlloc: prova 7). S'hi deixen a la seva fila, que no l'obre.
    public func potObrirArrossegant(_ id: Finestra.ID) -> Bool {
        guard potEditar, !arrossegantFinestres, let finestra = configuracio.finestra(id), !finestra.pestanyes.isEmpty
        else { return false }
        return perRevisar || finestraSeleccionada != id
    }

    /// Mostra una finestra a mig arrossegament, com un clic a la seva fila (un nom a mig escriure es desa en el seu pas).
    /// No és cap pas de Desfés. Recorda la selecció d'abans (la primera, si se n'obren diverses en el mateix
    /// arrossegament) i canvia la llista (`generacioLlista`).
    public func obreArrossegant(_ id: Finestra.ID) {
        guard potObrirArrossegant(id) else { return }
        acabaNom(desant: true)
        let abans = abansDObrir ?? seleccio
        lateral = .finestra(id)
        abansDObrir = abans
        generacioLlista += 1
    }

    /// SwiftUI demana el proveïdor d'una fila de pestanya (el seu `.itemProvider`): en prémer-la, o un camp de la
    /// fila, i en començar a arrossegar, un cop per cada fila arrossegada. Les posicions tornen a ser les d'aquesta
    /// llista, i es desa la fila (`pestanyesArrossegades`): les crides de menys de 50 ms de diferència són de la
    /// mateixa pulsació. No canvia res que es vegi.
    public func comencaArrossegament(_ pestanya: Pestanya.ID, ara: Date = Date()) {
        if abansDObrir != nil { abansDObrir = nil }
        if arrossegantFinestres { arrossegantFinestres = false }
        if ara.timeIntervalSince(darreraCridaDelProveidor) > 0.05 { pestanyesArrossegades = [] }
        pestanyesArrossegades.insert(pestanya)
        darreraCridaDelProveidor = ara
    }

    // MARK: - Reordenar finestres

    /// Comença a arrossegar la fila d'una finestra (el `.itemProvider` de la fila, que SwiftUI també crida en prémer-la).
    public func comencaArrossegamentDeFinestra() {
        if abansDObrir != nil { abansDObrir = nil }
        if !arrossegantFinestres { arrossegantFinestres = true }
        pestanyesArrossegades = []
        darreraCridaDelProveidor = .distantPast
    }

    /// `onMove` de la barra lateral: `origens` i `desti` són posicions de `configuracio.finestres` (`desti`, abans de
    /// treure les que es mouen). Només si l'arrossegament ha sortit d'una fila de finestra (`arrossegantFinestres`).
    public func reordenaFinestres(_ origens: IndexSet, a desti: Int) {
        guard potEditar, arrossegantFinestres else { return }
        arrossegantFinestres = false
        let finestres = configuracio.finestres
        mouFinestres(Set(origens.filter(finestres.indices.contains).map { finestres[$0].id }), a: desti)
    }

    /// Mou finestres a una posició de la barra lateral: un sol pas de Desfés. La finestra que es veu no canvia.
    public func mouFinestres(_ ids: Set<Finestra.ID>, a index: Int) {
        guard potEditar else { return }
        let nomPendent = prenNomPendent()
        canvia(ids.count == 1 ? "Mou la finestra" : "Mou les finestres") {
            nomPendent?(&$0)
            $0.mouFinestres(ids, a: index)
        }
    }

    /// «Mou amunt» i «Mou avall» del menú de la fila: si no és la primera (o l'última).
    public func potMoureFinestra(_ id: Finestra.ID, amunt: Bool) -> Bool {
        guard potEditar, let i = configuracio.finestres.firstIndex(where: { $0.id == id }) else { return false }
        return amunt ? i > 0 : i < configuracio.finestres.count - 1
    }

    public func mouFinestra(_ id: Finestra.ID, amunt: Bool) {
        guard potMoureFinestra(id, amunt: amunt), let i = configuracio.finestres.firstIndex(where: { $0.id == id })
        else { return }
        mouFinestres([id], a: amunt ? i - 1 : i + 2)
    }

    /// Pestanyes deixades anar a la llista de la finestra que es veu, a la posició `index` (la de la llista abans de
    /// treure'n les que es mouen, com `onMove`), o, sense `index`, al final (la finestra buida). Arriben d'una altra
    /// llista (la finestra s'ha obert arrossegant): es mouen pels id, mai per posició. Un sol pas de Desfés, que torna
    /// a la selecció d'abans d'obrir-la. Les mogudes queden triades. Només les d'aquesta execució de l'app.
    /// - Returns: si se n'ha mogut alguna.
    @discardableResult
    public func deixaAnar(_ arrossegades: [PestanyaArrossegada], a desti: Finestra.ID, index: Int?) -> Bool {
        // Sense dades no es mou res: aquí l'acció no diu d'on ve l'arrossegament (la càrrega no s'ha vist fallar mai).
        let ids = Self.dAquestaExecucio(arrossegades)
        Registre.arrossegar.notice("""
            llista \(Registre.curt(desti), privacy: .public): \(arrossegades.count) arrossegades, \(ids.count) per \
            moure, a la posició \(index ?? -1)
            """)
        // Només a la llista que es veu: l'índex és d'aquesta llista.
        guard potEditar, !perRevisar, finestraSeleccionada == desti, configuracio.finestra(desti) != nil else { return false }
        let existents = ids.intersection(configuracio.finestres.flatMap(\.pestanyes).map(\.id))
        guard !existents.isEmpty else { return false }
        let abans = abansDObrir
        abansDObrir = nil
        let configuracioAbans = configuracio
        mou(existents, a: desti, index: index, seleccioAbans: abans)
        guard configuracio != configuracioAbans else { return false }
        pestanyesSeleccionades = existents
        demanaFocusLlista += 1
        return true
    }

    /// Canvia la carpeta de pestanyes. Si Claude estava apagat, no s'activa sol (decisió d'en David): ho fa
    /// «Activa Claude».
    public func canviaCarpeta(_ ids: Set<Pestanya.ID>, a carpeta: String, agrupa: String? = nil) {
        guard potEditar else { return }
        canvia("Canvia la carpeta", agrupa: Self.clau(agrupa, ids)) { $0.canviaPestanyes(ids) { $0.carpeta = carpeta } }
    }

    public func activaClaude(_ ids: Set<Pestanya.ID>, _ activat: Bool) {
        guard potEditar else { return }
        canvia(activat ? "Activa Claude" : "Desactiva Claude") { $0.canviaPestanyes(ids) { $0.claude.activat = activat } }
    }

    /// Canvia les opcions de Claude d'una o de diverses pestanyes (l'inspector).
    /// - Parameter agrupa: per als camps de text. Els canvis seguits amb la mateixa clau fan un sol pas de Desfés,
    ///   fins que n'hi ha un altre, es desfà o es crida `acabaAgrupacio()`.
    public func canviaClaude(_ ids: Set<Pestanya.ID>, nom: String, agrupa: String? = nil,
                             _ canvi: (inout ClaudePestanya) -> Void) {
        guard potEditar else { return }
        // Normalitzada, com al fitxer i a l'ordre: si no, la memòria i el disc dirien coses diferents (per exemple, un
        // `{"ultracode":false}` de `--settings` que se'n va en activar l'ultracode).
        canvia(nom, agrupa: Self.clau(agrupa, ids)) {
            $0.canviaPestanyes(ids) { pestanya in
                canvi(&pestanya.claude)
                pestanya.claude = pestanya.claude.normalitzada()
            }
        }
    }

    /// La clau d'agrupació inclou les files: el mateix camp d'unes altres pestanyes és un altre pas.
    private static func clau(_ agrupa: String?, _ ids: some Sequence<UUID>) -> String? {
        agrupa.map { "\($0)|" + ids.map(\.uuidString).sorted().joined(separator: ",") }
    }

    // MARK: - Inspector

    /// El valor d'un camp a les pestanyes seleccionades que es veuen.
    public func comu<Valor: Equatable>(_ valor: (Pestanya) -> Valor) -> Comu<Valor> {
        let valors = pestanyes.map(valor)
        guard let primer = valors.first else { return .cap }
        return valors.allSatisfy { $0 == primer } ? .un(primer) : .diversos
    }

    /// Les ordres de les pestanyes seleccionades, una per línia, per copiar-les (⌘C a la llista). Les que només són
    /// un terminal, o no tenen ordre (un error), no hi surten. Buit: no hi ha res a copiar, i l'ordre es desactiva.
    public var ordresSeleccionades: String {
        ordres(Set(pestanyes.map(\.id)))
    }

    /// Les ordres d'unes pestanyes de la llista (el menú contextual pot ser d'una fila que no és la triada).
    public func ordres(_ ids: Set<Pestanya.ID>) -> String {
        pestanyesVisibles.filter { ids.contains($0.id) }
            .compactMap { try? OrdreClaude.text(de: $0.claude, repren: conversaDe($0)).get() }
            .joined(separator: "\n")
    }

    /// Canvia la plantilla (Configuració), en un pas del Desfés de la plantilla (`desferPlantilla`), no del de
    /// l'editor. Les pestanyes que ja hi són no canvien. Si no canvia res, no hi ha cap pas.
    public func canviaPlantilla(nom: String, _ canvi: (inout ClaudePestanya) -> Void) {
        guard potEditar else { return }
        let abans = configuracio.plantilla
        var nova = abans
        canvi(&nova)
        nova = nova.normalitzada()
        guard nova != abans.normalitzada() else { return }
        configuracio.plantilla = nova
        desferPlantilla.beginUndoGrouping()
        registraDesferPlantilla(tornaA: abans, nom: nom, a: desferPlantilla)
        desferPlantilla.endUndoGrouping()
        haCanviat()
    }

    /// Desfer i refer només tornen la plantilla, al Desfés que s'ha fet servir en canviar-la.
    private func registraDesferPlantilla(tornaA anterior: ClaudePestanya, nom: String, a desfer: UndoManager) {
        desfer.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                guard editor.potEditar else { return }
                let ara = editor.configuracio.plantilla
                editor.configuracio.plantilla = anterior
                editor.registraDesferPlantilla(tornaA: ara, nom: nom, a: desfer)
                editor.haCanviat()
            }
        }
        desfer.setActionName(nom)
    }

    /// «D'acord» del bàner dels avisos del fitxer.
    public func descartaAvisosFormat() {
        avisosFormat = []
    }

    /// Tanca l'agrupació de canvis de text (en sortir d'un camp).
    public func acabaAgrupacio() {
        clauAgrupada = nil
    }

    // MARK: - Desfés

    /// El que torna un pas de Desfés de l'editor: les finestres i la selecció. La plantilla no: té el seu Desfés.
    private struct Instantania {
        var finestres: [Finestra]
        var seleccio: Seleccio
    }

    private var instantania: Instantania {
        Instantania(finestres: configuracio.finestres, seleccio: seleccio)
    }

    /// Aplica un canvi com un sol pas de Desfés, amb el nom de l'acció, i programa el desat. Si no canvia res, no
    /// registra res.
    /// - Parameter seleccioAbans: la selecció a què torna ⌘Z, si no és la d'ara (vegeu `mou`).
    private func canvia(_ nom: String, agrupa: String? = nil, seleccioAbans: Seleccio? = nil,
                        _ canvi: (inout Configuracio) -> Void) {
        var abans = instantania
        if let seleccioAbans { abans.seleccio = seleccioAbans }
        let plantilla = configuracio.plantilla
        canvi(&configuracio)
        // Els canvis de l'editor no toquen la plantilla: el seu Desfés no la tornaria.
        assert(configuracio.plantilla == plantilla, "un canvi de l'editor ha tocat la plantilla")
        guard configuracio.finestres != abans.finestres else { return }
        // Qualsevol canvi acaba el que quedés d'obrir una finestra arrossegant (un arrossegament cancel·lat).
        if abansDObrir != nil { abansDObrir = nil }
        // S'agrupa només si el pas de dalt de la pila és el de l'últim canvi d'aquest camp: un camp de text de la
        // finestra hi pot haver registrat el seu entremig.
        if agrupa == nil || agrupa != clauAgrupada || !undoManager.canUndo || undoManager.undoActionName != nom {
            undoManager.beginUndoGrouping()
            registraDesfer(tornaA: abans, nom: nom)
            undoManager.endUndoGrouping()
            finestresEnObrirGrup = abans.finestres
        } else if configuracio.finestres == finestresEnObrirGrup, undoManager.groupingLevel == 0 {
            // El camp torna a ser com abans del pas (s'ha esborrat el que s'hi havia escrit): el pas ja no canvia res.
            // Es treu, sense deixar cap Refés; desfer-lo torna la mateixa configuració i avisa la vista. Amb un grup
            // obert (algú altre hi ha registrat alguna cosa en aquest mateix esdeveniment), `undo()` desfaria aquell
            // grup o petaria: llavors el pas es queda.
            undoManager.disableUndoRegistration()
            undoManager.undo()
            undoManager.enableUndoRegistration()
            finestresEnObrirGrup = nil
            return
        }
        clauAgrupada = agrupa
        haCanviat()
    }

    /// Desfer i refer tornen a una instantània sencera (la configuració és petita) i es registren l'un a l'altre.
    private func registraDesfer(tornaA anterior: Instantania, nom: String) {
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                let ara = editor.instantania
                editor.clauAgrupada = nil
                editor.abansDObrir = nil
                editor.configuracio.finestres = anterior.finestres
                editor.nomEnEdicio = nil
                // En aquest ordre: canviar de finestra o de llista buida la selecció de pestanyes.
                editor.finestraSeleccionada = anterior.seleccio.finestra
                editor.perRevisar = anterior.seleccio.perRevisar
                editor.pestanyesSeleccionades = anterior.seleccio.pestanyes
                editor.actualitzaAvisos()
                editor.registraDesfer(tornaA: ara, nom: nom)
                editor.ajustaSeleccio()
                editor.haCanviat()
            }
        }
        undoManager.setActionName(nom)
    }

    /// La finestra seleccionada ha d'existir (si no, la primera), i les pestanyes seleccionades, ser a la llista.
    private func ajustaSeleccio() {
        if finestra == nil { finestraSeleccionada = configuracio.finestres.first?.id }
        let ids = Set(pestanyesVisibles.map(\.id))
        if !pestanyesSeleccionades.isSubset(of: ids) { pestanyesSeleccionades.formIntersection(ids) }
    }

    private func actualitzaAvisos() {
        avisos = estat == .oberta
            ? Validacio.avisos(configuracio, inici: inici, carpetaExisteix: carpetaExisteix)
            : AvisosConfiguracio()
    }

    // MARK: - Desar

    private func haCanviat() {
        actualitzaAvisos()
        // El camp del nom d'una fila que ja no hi és (desfer-ne la creació, tornar a importar…) es tanca.
        if let element = nomEnEdicio, nom(de: element) == nil { nomEnEdicio = nil }
        canvisSenseDesar = true
        guard let retardDesat else { return }
        desatProgramat?.cancel()
        desatProgramat = Task { [weak self] in
            try? await Task.sleep(for: retardDesat)
            guard !Task.isCancelled else { return }
            self?.desaSiCal()
        }
    }

    /// La còpia que cal abans de desar, comparant amb el que hi ha al disc (i no amb cada canvi: el que s'ha desfet
    /// abans de desar no en demana cap):
    /// - `importacio`, si la configuració és la d'una importació que encara no s'ha desat;
    /// - `esborrat`, si hi falta alguna finestra del disc que tenia pestanyes;
    /// - `sessio`, al primer desat de la sessió de l'app.
    private var motiuDeCopia: MotiuCopia? {
        let ara = Set(configuracio.finestres.map(\.id))
        if !finestresImportades.isDisjoint(with: ara) { return .importacio }
        if !finestresDesades.isSubset(of: ara) { return .esborrat }
        return copiaDeSessioFeta ? nil : .sessio
    }

    private func recordaDesades() {
        finestresDesades = Set(configuracio.finestres.filter { !$0.pestanyes.isEmpty }.map(\.id))
    }

    /// Desa ara si hi ha canvis. Es crida sola després de l'últim canvi, en amagar l'editor, en sortir, i amb
    /// «Torna-ho a provar».
    /// - Returns: `false` si hi havia canvis i no s'han pogut desar.
    @discardableResult
    public func desaSiCal() -> Bool {
        desatProgramat?.cancel()
        desatProgramat = nil
        guard canvisSenseDesar, estat == .oberta, let magatzem else { return true }
        do {
            // La primera còpia de cada sessió de l'app; si el fitxer és nou, no hi ha res per copiar. Només compta
            // quan el desat ha escrit: si no canviava res (per exemple, un canvi desfet), el magatzem no copia.
            let noves = try magatzem.desa(configuracio, sobre: empremta, copia: motiuDeCopia)
            if noves != empremta {
                copiaDeSessioFeta = true
                escriptures += 1
            }
            empremta = noves
            finestresImportades = []
            recordaDesades()
            canvisSenseDesar = false
            errorDesat = nil
            return true
        } catch {
            errorDesat = error
            return false
        }
    }
}
