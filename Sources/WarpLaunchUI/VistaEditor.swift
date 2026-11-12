import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WarpLaunchCore

/// La finestra de l'editor (docs/disseny.md, «Disposició»): barra lateral amb «Per revisar» i les finestres, la llista
/// de pestanyes, l'inspector, els estats buits i el full d'importació.
public struct VistaEditor: View {
    @Bindable var editor: Editor
    let warp: EstatWarp
    let inici: String
    /// Si l'app s'ha obert amb `--config`: es diu a l'estat buit i a la barra lateral.
    let carpetaDeProva: String?

    /// Les amplades de la finestra i de les columnes (docs/disseny.md, «Disposició»). La prova de les amplades (F6,
    /// `AmpladesTests`) hi mesura els textos de la barra lateral, l'inspector i la llista.
    ///
    /// F6 (0.35.0): l'inspector no es pot fer més estret de 320 pt (abans, 280), la seva amplada ideal. A 280, ni en català no
    /// hi cabien «Obre Claude Code en aquesta pestanya» (es partia) ni l'etiqueta «Mode de permisos» al costat del desplegable.
    /// La finestra, de 640 a 680 pt, perquè la llista conservi el mínim d'abans (180 pt) amb la barra lateral i l'inspector.
    static let ampladaMinima: CGFloat = 680
    /// La de la finestra quan s'obre per primer cop (l'escena de l'app, `defaultSize`).
    public static let ampladaPerDefecte: CGFloat = 900
    static let barraLateralMinima: CGFloat = 180
    static let barraLateralIdeal: CGFloat = 220
    static let barraLateralMaxima: CGFloat = 320
    static let inspectorMinim: CGFloat = 320
    static let inspectorIdeal: CGFloat = 320
    static let inspectorMaxim: CGFloat = 460

    /// El primer ús (0.36.0): l'enllaç de l'estat buit a Configuració › General. Sense, no hi és.
    let primerUs: PrimerUs?

    public init(editor: Editor, warp: EstatWarp, inici: String, carpetaDeProva: String? = nil, primerUs: PrimerUs? = nil) {
        self.editor = editor
        self.warp = warp
        self.inici = inici
        self.carpetaDeProva = carpetaDeProva
        self.primerUs = primerUs
    }

    public var body: some View {
        Group {
            switch editor.estat {
            case .carregant:
                ProgressView()
            case .senseConfiguracio:
                SenseConfiguracio(editor: editor, carpetaDeProva: carpetaDeProva, primerUs: primerUs)
            case let .error(missatge):
                ContentUnavailableView {
                    Label(t("No es pot obrir la configuració"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(t("\(missatge). No s'hi escriurà res fins que es pugui llegir."))
                } actions: {
                    Button(t("Torna a carregar")) { editor.carrega() }
                }
            case .oberta:
                Disposicio(editor: editor, inici: inici, carpetaDeProva: carpetaDeProva)
            }
        }
        .frame(minWidth: Self.ampladaMinima, minHeight: 360)
        .focusedSceneValue(\.editor, editor)
        .sheet(isPresented: $editor.demanaImportacio) {
            if let full = FullImportacio(editor: editor, warp: warp) {
                VistaImportacio(full: full)
            }
        }
    }
}

/// El primer ús (0.36.0, `PrimerUs`): què fa l'app, en tres passos, i els botons de sempre. Sense finestres noves: un
/// `ContentUnavailableView`, com la resta d'estats buits (mac-design, «Pàgina buida»).
struct SenseConfiguracio: View {
    let editor: Editor
    let carpetaDeProva: String?
    let primerUs: PrimerUs?
    @Environment(\.openSettings) private var openSettings

    /// L'amplada dels passos, alineats a l'esquerra: a la finestra més estreta (`VistaEditor.ampladaMinima`) hi caben, i cada pas
    /// fa com a molt dues línies en les 10 llengües (`AmpladesTests`).
    static let ampladaPassos: CGFloat = 440

    var body: some View {
        ContentUnavailableView {
            Label(t("Encara no hi ha cap configuració"), systemImage: "macwindow.on.rectangle")
        } description: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(PrimerUs.passos.enumerated()), id: \.offset) { posicio, pas in
                    Label(pas, systemImage: "\(posicio + 1).circle")
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: Self.ampladaPassos, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Text(t("Fins que no triïs, no s'escriu res."))
            if let carpetaDeProva {
                Label(t("Configuració de prova: \(carpetaDeProva)"), systemImage: "testtube.2")
            }
        } actions: {
            Button(t("Importa de Warp…")) { editor.demanaImportar() }
                .buttonStyle(.borderedProminent)
                .help(t("Llegeix Warp i mostra què se n'importaria, abans de crear res"))
                .disabled(!editor.potImportar)
            Button(t("Comença en blanc")) { editor.comencaEnBlanc() }
            // Només hi porta: l'interruptor de la Configuració l'activa l'usuari (D3, regla 3).
            if let primerUs, primerUs.mostraEnllacInici {
                Button(t("Fes que s'obri sola en iniciar sessió…")) {
                    primerUs.mostraGeneral()
                    openSettings()
                }
                .buttonStyle(.link)
                .help(t("Mostra Configuració › General, on pots activar «Obre Warp Launch en iniciar sessió»"))
            }
        }
    }
}

private struct Disposicio: View {
    @Bindable var editor: Editor
    let inici: String
    let carpetaDeProva: String?

    var body: some View {
        NavigationSplitView {
            BarraLateral(editor: editor, carpetaDeProva: carpetaDeProva)
                .navigationSplitViewColumnWidth(min: VistaEditor.barraLateralMinima, ideal: VistaEditor.barraLateralIdeal,
                                                max: VistaEditor.barraLateralMaxima)
                // El full de «Lliga amb Warp…»: aquí, perquè la llista ja porta el d'obrir i `VistaEditor`, el d'importar.
                .sheet(isPresented: Binding(get: { editor.lligam?.mostraFull == true },
                                            set: { if !$0 { editor.lligam?.cancela() } })) {
                    if let lligam = editor.lligam {
                        FullLligam(lligam: lligam, inici: inici)
                    }
                }
        } detail: {
            LlistaPestanyes(editor: editor, inici: inici, novaPestanya: { editor.demanaPestanyaNova() })
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if let obertura = editor.obertura, let resultat = obertura.resultat {
                            BanerObertura(resultat: resultat) { obertura.descartaResultat() }
                        }
                        if let error = editor.errorDesat {
                            BanerDesat(error: error, editor: editor)
                        }
                        if !editor.avisosFormat.isEmpty {
                            BanerFormat(editor: editor)
                        }
                    }
                }
                // Cada botó sobre la columna on actua (mac-design, «Toolbar that follows the columns»): «+» sobre la
                // llista, i el de l'inspector, a la barra de l'inspector.
                .toolbar {
                    // L'acció principal de l'app, sobre la llista de la finestra que obriria. Només demana el full.
                    ToolbarItem(placement: .primaryAction) {
                        Button(t("Obre a Warp…"), systemImage: "arrow.up.forward.app") {
                            if let id = editor.finestra?.id { editor.demanaObertura(id) }
                        }
                            .help(t("Obre aquesta finestra a Warp: abans, el full diu què s'obrirà i demana confirmació"))
                            .disabled(!editor.potObrir(editor.finestra?.id))
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem(placement: .primaryAction) {
                        Button { editor.demanaPestanyaNova() } label: {
                            Label(t("Nova pestanya…"), systemImage: "plus")
                        }
                        .help(t("Nova pestanya: en tries la carpeta (⌘T)"))
                        .disabled(!editor.potNovaPestanya)
                    }
                }
                // A la llista, i no a tota la finestra: els `fileDialog…` no han d'arribar al «Tria…» de l'inspector.
                .fileImporter(isPresented: $editor.demanaNovaPestanya, allowedContentTypes: [.folder]) { resultat in
                    if case let .success(url) = resultat { editor.afegeixPestanya(carpeta: url.path) }
                }
                .fileDialogDefaultDirectory(URL(filePath: editor.carpetaSuggerida, directoryHint: .isDirectory))
                .fileDialogMessage(t("Tria la carpeta de la pestanya nova"))
                .fileDialogConfirmationLabel(t("Afegeix"))
        }
        .navigationTitle(editor.titol)
        .navigationSubtitle(editor.subtitol)
        // El full d'obrir a Warp (fase 3.1). Aquí i no a `VistaEditor`, que ja porta el d'importar.
        .sheet(isPresented: Binding(get: { editor.obertura?.mostraFull == true },
                                    set: { if !$0 { editor.obertura?.cancela() } })) {
            if let obertura = editor.obertura {
                FullObertura(obertura: obertura, inici: inici)
            }
        }
        .inspector(isPresented: $editor.mostraInspector) {
            VistaInspector(editor: editor, inici: inici)
                .inspectorColumnWidth(min: VistaEditor.inspectorMinim, ideal: VistaEditor.inspectorIdeal, max: VistaEditor.inspectorMaxim)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem(placement: .primaryAction) {
                        Button { editor.mostraInspector.toggle() } label: {
                            Label(editor.mostraInspector ? t("Amaga l'inspector") : t("Mostra l'inspector"),
                                  systemImage: "sidebar.trailing")
                        }
                        .help(t("Mostra o amaga l'inspector (⌥⌘I)"))
                    }
                }
        }
    }
}

// MARK: - Barra lateral

private struct BarraLateral: View {
    @Bindable var editor: Editor
    let carpetaDeProva: String?
    /// Obre la finestra d'una fila quan s'hi atura el cursor arrossegant pestanyes. Una per a tota la barra lateral.
    private var molla = State(initialValue: Molla())

    init(editor: Editor, carpetaDeProva: String?) {
        self.editor = editor
        self.carpetaDeProva = carpetaDeProva
    }

    /// Sempre hi ha una fila triada: amb una selecció opcional, un clic al buit desmarcava la fila, però la finestra
    /// continuava seleccionada (i ⌫ l'hauria eliminat sense que es veiés). Sense finestres no es marca res.
    private var seleccio: Binding<Editor.ElementLateral> {
        Binding { editor.lateral ?? .perRevisar } set: { editor.lateral = $0 }
    }

    var body: some View {
        List(selection: seleccio) {
            // Es queda mentre està seleccionada, encara que ja no hi hagi res per revisar («Res per revisar»).
            if editor.nombrePerRevisar > 0 || editor.perRevisar {
                Label(t("Per revisar"), systemImage: "exclamationmark.triangle")
                    .badge(editor.nombrePerRevisar)
                    .help(t("Pestanyes amb avisos de totes les finestres"))
                    .tag(Editor.ElementLateral.perRevisar)
            }
            Section(t("Finestres")) {
                ForEach(editor.configuracio.finestres) { finestra in
                    FilaFinestra(editor: editor, finestra: finestra)
                        .modifier(DestiPestanyes(editor: editor, finestra: finestra.id, molla: molla.wrappedValue))
                        // Arrossegar la fila per reordenar les finestres: la marca que diu que és una finestra, i no
                        // pestanyes (`Editor.arrossegantFinestres`). El proveïdor és buit: no porta cap dada enlloc.
                        .itemProvider(editor.potEditar ? {
                            editor.comencaArrossegamentDeFinestra()
                            return NSItemProvider()
                        } : nil)
                        .tag(Editor.ElementLateral.finestra(finestra.id))
                }
                // Les posicions són de `configuracio.finestres`, les dades del ForEach.
                .onMove(perform: editor.potEditar ? { origens, desti in editor.reordenaFinestres(origens, a: desti) } : nil)
            }
        }
        .contextMenu(forSelectionType: Editor.ElementLateral.self) { seleccio in
            if seleccio.isEmpty {
                Button(t("Nova finestra")) { editor.afegeixFinestra() }
            } else if seleccio.count == 1, case let .finestra(id)? = seleccio.first {
                Button(t("Canvia el nom")) {
                    editor.lateral = .finestra(id)
                    editor.comencaNom(.finestra(id))
                }
                // Només demana el full de confirmació.
                if editor.potObrir(id) {
                    Button(t("Obre a Warp…")) { editor.demanaObertura(id) }
                    Divider()
                }
                Button(t("Duplica")) { editor.duplicaFinestra(id) }
                if editor.potMoureFinestra(id, amunt: true) {
                    Button(t("Mou amunt")) { editor.mouFinestra(id, amunt: true) }
                }
                if editor.potMoureFinestra(id, amunt: false) {
                    Button(t("Mou avall")) { editor.mouFinestra(id, amunt: false) }
                }
                if editor.potEditar, PortaRetallsSistema.hiHaPestanyes {
                    Button(t("Enganxa les pestanyes")) {
                        editor.lateral = .finestra(id)
                        PortaRetallsSistema.enganxa(a: editor)
                    }
                }
                Divider()
                Button(t("Elimina"), role: .destructive) { editor.eliminaFinestra(id) }
            }
        }
        // Edició › Elimina, desactivat si no hi ha cap finestra triada (a «Per revisar» no faria res).
        .onDeleteCommand(perform: editor.potEliminarFinestra ? {
            if case let .finestra(id)? = editor.lateral { editor.eliminaFinestra(id) }
        } : nil)
        .focusedValue(\.columnaEditor, .barraLateral)
        // Copiar pestanyes, triar una altra finestra i ⌘V: el focus és aquí, i van a la finestra triada.
        .modifier(Enganxa(editor: editor))
        .onKeyPress(.return) {
            guard editor.nomEnEdicio == nil, case let .finestra(id)? = editor.lateral else { return .ignored }
            editor.comencaNom(.finestra(id))
            return .handled
        }
        .onDisappear { molla.wrappedValue.atura(.desapareguda) }
        .overlay {
            if editor.configuracio.finestres.isEmpty {
                // L'acció és a la llista, al costat («Nova finestra»): aquí només es diu.
                ContentUnavailableView(t("Cap finestra"), systemImage: "macwindow")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let carpetaDeProva {
                Label(t("Prova: \(carpetaDeProva)"), systemImage: "testtube.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .help(t("Configuració de prova (--config): \(carpetaDeProva)"))
            }
        }
    }
}

private struct FilaFinestra: View {
    let editor: Editor
    let finestra: Finestra

    var body: some View {
        if editor.nomEnEdicio == .finestra(finestra.id) {
            CampNom(editor: editor, element: .finestra(finestra.id))
        } else {
            let avis = editor.avisPrincipal(finestra: finestra.id)
            Label {
                Text(finestra.nom)
            } icon: {
                if avis == nil {
                    Image(systemName: "macwindow")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                }
            }
            .badge(finestra.pestanyes.count)
            .help(avis.map { "\(finestra.resum)\n\($0.description)" } ?? finestra.resum)
        }
    }
}

/// La fila d'una finestra rep les pestanyes arrossegades de la llista: van al final, en un sol pas de Desfés
/// (docs/disseny.md, «Arrossegar»). La de la finestra que es veu no (ja hi són), tret que s'hagi obert arrossegant.
/// Aturar-s'hi arrossegant obre la finestra, com les carpetes del Finder (`Molla`).
private struct DestiPestanyes: ViewModifier {
    let editor: Editor
    let finestra: Finestra.ID
    let molla: Molla

    func body(content: Content) -> some View {
        content
            // On és la fila a la pantalla, quan salta el rellotge de la molla.
            .background { AncoraFila(molla: molla, fila: finestra) }
            // Sense `isEnabled`: la fila d'una finestra triada en crear-la (⌘N) o en obrir l'app no acceptava res
            // després, quan ja no ho era (prova 7). Es decideix en cada arrossegament, a `dropConfiguration`, i
            // `deixaAnar` ho torna a mirar.
            .dropDestination(for: PestanyaArrossegada.self) { arrossegades, sessio in
                molla.atura(.deixades)
                let mogudes = editor.deixaAnar(arrossegades, a: finestra, local: sessio.localSession != nil,
                                               elements: sessio.itemsCount)
                Registre.arrossegar.notice("fila \(Registre.curt(finestra), privacy: .public): mou \(mogudes)")
            }
            // Moure, no copiar: el cursor no porta «+». A la fila de la finestra que es veu no s'hi deixa res
            // (`.forbidden`) i la pestanya torna al seu lloc, però el cursor no canvia: SwiftUI hi demana
            // NSDragOperationNone, i AppKit no hi posa el de prohibit (prova 7b, binari).
            .dropConfiguration { _ in
                let accepta = editor.acceptaPestanyes(finestra)
                molla.batec(finestra)
                Registre.arrossegar.debug("fila \(Registre.curt(finestra), privacy: .public): configuració, accepta \(accepta)")
                return DropConfiguration(operation: accepta ? .move : .forbidden)
            }
            // Per fora de `dropDestination`: avisa de «the closest drop session in the child view hierarchy» (doc).
            .onDropSessionUpdated { sessio in
                // Mentre s'arrossega no es pot fer cap clic: les pestanyes de l'última pulsació són les arrossegades.
                switch sessio.phase {
                case .entering, .active: editor.fixaPestanyesArrossegades()
                default: break
                }
                Registre.arrossegar.debug("""
                    fila \(Registre.curt(finestra), privacy: .public): sessió \(String(describing: sessio.phase), privacy: .public), \
                    \(sessio.itemsCount) elements, nom obert \(editor.nomEnEdicio == .finestra(finestra))
                    """)
                molla.actualitza(sessio, fila: finestra, potObrir: editor.potObrirArrossegant(finestra)) {
                    editor.obreArrossegant($0)
                }
            }
    }
}

// MARK: - Llista de pestanyes

private struct LlistaPestanyes: View {
    @Bindable var editor: Editor
    let inici: String
    let novaPestanya: () -> Void
    /// Després de deixar-hi pestanyes d'una altra finestra: la llista és nova (`.id`), i la d'on han sortit, que tenia
    /// el focus, ja no hi és. Sense això, ⌫, ⌘C o Retorn no hi actuen fins a fer-hi clic.
    @FocusState private var llistaEnfocada: Bool

    var body: some View {
        if editor.perRevisar {
            let grups = editor.perRevisarPerFinestra
            if grups.isEmpty {
                ContentUnavailableView(t("Res per revisar"), systemImage: "checkmark.circle",
                                       description: Text(t("Cap pestanya no té avisos.")))
            } else {
                List(selection: $editor.pestanyesSeleccionades) {
                    ForEach(grups) { grup in
                        Section(grup.finestra.nom) {
                            ForEach(grup.pestanyes) { pestanya in
                                FilaPestanya(editor: editor, pestanya: pestanya, inici: inici)
                            }
                        }
                    }
                }
                .modifier(OrdresLlista(editor: editor, novaPestanya: nil))
            }
        } else if let finestra = editor.finestra {
            if finestra.pestanyes.isEmpty {
                ContentUnavailableView {
                    Label(t("Finestra sense pestanyes"), systemImage: "rectangle.dashed")
                } description: {
                    Text(t("Afegeix-hi una pestanya: en tries la carpeta, i Claude hi tindrà les opcions de la plantilla."))
                } actions: {
                    Button(t("Nova pestanya…"), action: novaPestanya)
                    // Copiar unes pestanyes, crear una finestra i omplir-la: aquí no hi ha cap llista que rebi ⌘V.
                    if editor.potEnganxar, PortaRetallsSistema.hiHaPestanyes {
                        Button(t("Enganxa les pestanyes")) { PortaRetallsSistema.enganxa(a: editor) }
                    }
                }
            } else {
                List(selection: $editor.pestanyesSeleccionades) {
                    ForEach(finestra.pestanyes) { pestanya in
                        FilaPestanya(editor: editor, pestanya: pestanya, inici: inici)
                    }
                    // D'una altra llista (la finestra s'ha obert arrossegant): a la posició on es deixen anar, pels id.
                    // SwiftUI només hi passa si aquesta llista no és la d'on surt l'arrossegament. Abans d'`onMove`:
                    // així el compilador no pot triar el `dropDestination` de `View` (sense posició).
                    .dropDestination(for: PestanyaArrossegada.self) { arrossegades, index in
                        editor.deixaAnar(arrossegades, a: finestra.id, index: index)
                    }
                    // Dins de la mateixa llista: reordenar. Les posicions són de `finestra.pestanyes`, les dades del
                    // ForEach. A «Per revisar» no n'hi ha.
                    .onMove(perform: editor.potReordenar ? { origens, desti in editor.reordena(origens, a: desti) } : nil)
                }
                // Una altra `List` (un altre `NSOutlineView`) cada cop que una finestra s'obre arrossegant: la d'on surt
                // l'arrossegament es queda amb les posicions velles, i en deixar-les anar reordenaria aquesta.
                .id(editor.generacioLlista)
                .focused($llistaEnfocada)
                .onChange(of: editor.demanaFocusLlista) { llistaEnfocada = true }
                .modifier(OrdresLlista(editor: editor, novaPestanya: novaPestanya))
            }
        } else if editor.configuracio.finestres.isEmpty {
            ContentUnavailableView {
                Label(t("Cap finestra"), systemImage: "macwindow")
            } description: {
                Text(t("Una finestra de Warp agrupa pestanyes. Afegeix-ne una per començar."))
            } actions: {
                Button(t("Nova finestra")) { editor.afegeixFinestra() }
            }
        } else {
            ContentUnavailableView(t("Tria una finestra"), systemImage: "sidebar.leading")
        }
    }
}

/// Menú contextual, ⌫ i Retorn de la llista de pestanyes. Al menú contextual, el que no s'aplica no hi surt.
private struct OrdresLlista: ViewModifier {
    let editor: Editor
    /// `nil` a «Per revisar», on no es poden afegir pestanyes.
    let novaPestanya: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: Pestanya.ID.self) { ids in
                if ids.isEmpty {
                    if let novaPestanya, editor.potAfegirPestanya {
                        Button(t("Nova pestanya…"), action: novaPestanya)
                    }
                    if editor.potEnganxar, PortaRetallsSistema.hiHaPestanyes {
                        Button(t("Enganxa")) { PortaRetallsSistema.enganxa(a: editor) }
                    }
                } else {
                    menu(ids)
                }
            }
            .onDeleteCommand(perform: editor.potEliminarPestanyes ? { editor.eliminaPestanyes() } : nil)
            .focusedValue(\.columnaEditor, .llista)
            // Arrossegar: dins de l'app, moure; cap a una altra app, res (si SwiftUI ho aplica a la `List`).
            .dragConfiguration(PestanyaArrossegada.configuracio)
            // ⌘C, ⌘X i ⌘V: pestanyes, amb el tipus propi (mai text). Sense res a fer, Edició les mostra desactivades.
            .onCopyCommand(perform: editor.pestanyes.isEmpty ? nil : {
                PortaRetallsSistema.proveidors(editor.copiaPestanyes())
            })
            .onCutCommand(perform: editor.pestanyes.isEmpty || !editor.potEditar ? nil : {
                PortaRetallsSistema.proveidors(editor.retallaPestanyes())
            })
            .modifier(Enganxa(editor: editor))
            .onKeyPress(.return) {
                guard editor.nomEnEdicio == nil, editor.pestanyes.count == 1, let id = editor.pestanyes.first?.id
                else { return .ignored }
                editor.comencaNom(.pestanya(id))
                return .handled
            }
    }

    @ViewBuilder
    private func menu(_ ids: Set<Pestanya.ID>) -> some View {
        let pestanyes = editor.pestanyesVisibles.filter { ids.contains($0.id) }
        // Un clic dret sobre una fila que no era seleccionada: l'ordre hi actua, i queda seleccionada (no a «Mou a ▸»).
        let selecciona = { editor.pestanyesSeleccionades = ids }
        if ids.count == 1, let id = ids.first {
            Button(t("Canvia el nom")) {
                selecciona()
                editor.comencaNom(.pestanya(id))
            }
        }
        Button(t("Duplica")) {
            selecciona()
            editor.duplicaPestanyes()
        }
        // Amagat si no hi ha cap altra finestra (o, a «Per revisar», si ja hi són totes).
        let destins = editor.finestresPerMoure(ids)
        if !destins.isEmpty {
            Menu(t("Mou a")) {
                // Sense `selecciona()`: com en arrossegar-la, una fila no triada es mou sense canviar de finestra ni de
                // selecció; si és dins de la selecció, l'editor la segueix (pas 7).
                ForEach(destins) { desti in
                    Button(editor.etiquetaPerMoure(desti)) { editor.mouA(ids, a: desti.id) }
                }
            }
        }
        Button(t("Retalla")) {
            selecciona()
            PortaRetallsSistema.escriu(editor.retallaPestanyes())
        }
        Button(t("Copia")) {
            selecciona()
            PortaRetallsSistema.escriu(editor.copiaPestanyes())
        }
        // Només si n'hi ha alguna per copiar: una pestanya amb Claude però sense ordre (un error) no en té.
        let ordres = editor.ordres(ids)
        if !ordres.isEmpty {
            Button(ids.count == 1 ? t("Copia l'ordre") : t("Copia les ordres")) {
                selecciona()
                PortaRetallsSistema.copiaText(ordres)
            }
        }
        Divider()
        if pestanyes.contains(where: { !$0.claude.activat }) {
            Button(t("Activa Claude")) { editor.activaClaude(ids, true) }
        }
        if pestanyes.contains(where: \.claude.activat) {
            Button(t("Desactiva Claude")) { editor.activaClaude(ids, false) }
        }
        Divider()
        Button(t("Elimina"), role: .destructive) {
            selecciona()
            editor.eliminaPestanyes()
        }
    }
}

/// ⌘V a la llista o a la barra lateral: les pestanyes del porta-retalls van a la finestra que es veu. Edició › Enganxa
/// només s'activa si n'hi ha i s'hi poden posar (no a «Per revisar»).
private struct Enganxa: ViewModifier {
    let editor: Editor

    func body(content: Content) -> some View {
        // La validació només mira els tipus (no llegeix el contingut del porta-retalls); el llegeix l'ordre d'enganxar.
        content.onPasteCommand(of: [PortaRetallsSistema.tipus]) { _ in
            editor.potEnganxar && PortaRetallsSistema.hiHaPestanyes ? () : nil
        } perform: {
            PortaRetallsSistema.enganxa(a: editor)
        }
    }
}

/// El porta-retalls de macOS per a les pestanyes (`PortaRetalls`). Només el fan servir ordres d'en David (⌘C, ⌘X,
/// el menú contextual): l'app no hi escriu mai sola.
enum PortaRetallsSistema {
    static let tipus = UTType(exportedAs: PortaRetalls.tipus, conformingTo: .data)
    private static let tipusTauler = NSPasteboard.PasteboardType(PortaRetalls.tipus)

    /// Per a `onCopyCommand` i `onCutCommand`, que hi escriuen el que se'ls torna.
    static func proveidors(_ dades: Data?) -> [NSItemProvider] {
        guard let dades else { return [] }
        let proveidor = NSItemProvider()
        proveidor.registerDataRepresentation(forTypeIdentifier: PortaRetalls.tipus, visibility: .all) { acaba in
            acaba(dades, nil)
            return nil
        }
        return [proveidor]
    }

    /// Text (les ordres de Claude, «Copia l'ordre»): només amb una ordre d'en David.
    static func copiaText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Per al menú contextual.
    static func escriu(_ dades: Data?) {
        guard let dades else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(dades, forType: tipusTauler)
    }

    /// Si hi ha pestanyes al porta-retalls. Només en mira els tipus: llegir-ne el contingut sense que en David hagi
    /// demanat enganxar és un accés que macOS pot fer confirmar (`NSPasteboardAccessBehavior`).
    static var hiHaPestanyes: Bool {
        NSPasteboard.general.availableType(from: [tipusTauler]) != nil
    }

    /// Enganxa (⌘V, «Enganxa»): només aquí es llegeix el contingut.
    @MainActor
    static func enganxa(a editor: Editor) {
        guard let dades = NSPasteboard.general.data(forType: tipusTauler) else { return }
        editor.enganxa(dades)
    }
}

/// Una pestanya: el nom, i a sota la carpeta o l'avís més greu (sempre amb icona i text). A la dreta, el resum de
/// Claude: «Molt alt · Ultracode», o «Només terminal».
private struct FilaPestanya: View {
    let editor: Editor
    let pestanya: Pestanya
    let inici: String

    var body: some View {
        let avis = editor.avisPrincipal(pestanya.id)
        let carpeta = Rutes.abreujada(pestanya.carpeta, inici: inici)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if editor.nomEnEdicio == .pestanya(pestanya.id) {
                    CampNom(editor: editor, element: .pestanya(pestanya.id))
                } else {
                    Text(nom)
                        .lineLimit(1)
                }
                Group {
                    if let avis {
                        Label {
                            Text(avis.description)
                        } icon: {
                            Image(systemName: avis.gravetat == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                        }
                    } else {
                        Text(carpeta)
                            .truncationMode(.middle)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(pestanya.claude.resum)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(avis.map { "\(carpeta)\n\($0.description)" } ?? carpeta)
        // Per deixar-la anar a la fila d'una finestra. Conviu amb `onMove` (reordenar). Sense poder editar, no s'arrossega.
        // SwiftUI el crida en començar a arrossegar: les posicions tornen a ser les d'aquesta llista.
        .itemProvider(editor.potEditar ? {
            editor.comencaArrossegament(pestanya.id)
            return PestanyaArrossegada.proveidor(pestanya)
        } : nil)
    }

    private var nom: String {
        pestanya.titol.isEmpty ? (pestanya.carpeta as NSString).lastPathComponent : pestanya.titol
    }
}

/// El camp on s'escriu el nom d'una fila. El text és a l'editor (`textDelNom`). Retorn, sortir del camp o que el camp
/// desaparegui el desen; Escapada el deixa com era.
private struct CampNom: View {
    @Bindable var editor: Editor
    let element: Editor.ElementNom
    @FocusState private var enfocat: Bool

    var body: some View {
        TextField(t("Nom"), text: $editor.textDelNom)
            .labelsHidden()
            .focused($enfocat)
            .onSubmit { editor.acabaNom(element, desant: true) }
            .onExitCommand { editor.acabaNom(element, desant: false) }
            .onChange(of: enfocat) { _, ara in
                if !ara { editor.acabaNom(element, desant: true) }
            }
            .onDisappear { editor.acabaNom(element, desant: true) }
            .task { enfocat = true }
    }
}

/// Un desat que ha fallat. Sempre amb icona i text, mai només color.
private struct BanerDesat: View {
    let error: ErrorMagatzem
    let editor: Editor

    var body: some View {
        HStack(spacing: 8) {
            Label(titol, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            if error == .modificadaFora {
                Button(t("Torna a carregar")) { editor.carrega() }
                    .help(t("Descarta els canvis d'aquí i llegeix el fitxer tal com és ara"))
            } else {
                Button(t("Torna-ho a provar")) { editor.desaSiCal() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
        .help(error.description)
    }

    private var titol: String {
        error == .modificadaFora ? t("El fitxer ha canviat fora de l'app") : t("No s'ha pogut desar: \(error.description)")
    }
}

/// El fitxer s'ha editat a mà i en llegir-lo s'han corregit coses (docs/disseny.md, «Format v1»). Es diu abans que
/// el primer desat les faci desaparèixer del fitxer (en queda una còpia a `copies/`).
private struct BanerFormat: View {
    let editor: Editor
    private var mostra = State(initialValue: false)

    init(editor: Editor) {
        self.editor = editor
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(t("En llegir el fitxer s'han corregit \(editor.avisosFormat.count) coses. Abans de desar se'n fa una còpia."),
                  systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            Button(t("Mostra-les")) { mostra.wrappedValue = true }
                .popover(isPresented: mostra.projectedValue) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(editor.avisosFormat.enumerated()), id: \.offset) { _, avis in
                            Text(avis.description)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 480, alignment: .leading)
                }
            Button(t("D'acord")) { editor.descartaAvisosFormat() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}
