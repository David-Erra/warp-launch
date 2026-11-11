import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WarpLaunchCore

/// L'inspector (docs/disseny.md, «Disposició»): la pestanya triada (nom, carpeta, Claude Code i l'ordre), el bloc de
/// Claude de diverses pestanyes amb «Valors diversos», o la finestra si no hi ha cap pestanya triada. Cada canvi es
/// desa sol i es desfà amb ⌘Z. No obre res de Warp ni de Claude.
struct VistaInspector: View {
    @Bindable var editor: Editor
    let inici: String

    var body: some View {
        let contingut = editor.contingutInspector
        Group {
            switch contingut {
            case let .res(text):
                ContentUnavailableView(text, systemImage: "sidebar.trailing")
            case let .finestra(finestra):
                InspectorFinestra(editor: editor, finestra: finestra)
            case let .pestanya(pestanya):
                InspectorPestanya(editor: editor, pestanya: pestanya, inici: inici)
            case let .pestanyes(pestanyes):
                Form {
                    Section {
                        BlocClaude(editor: editor, unaSola: nil)
                    } header: {
                        Text(t("Claude Code a \(pestanyes.count) pestanyes"))
                    } footer: {
                        Text(t("Cada canvi s'aplica a totes."))
                            .foregroundStyle(.secondary)
                    }
                    if !editor.ordresSeleccionades.isEmpty {
                        Section {
                            BotoCopia(text: editor.ordresSeleccionades, titol: t("Copia les ordres"))
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        // Una altra selecció és un altre inspector: els camps de text no s'enduen el que s'hi escrivia.
        .id(Identitat(contingut))
        .disabled(!editor.potEditar)
    }

    /// Què identifica el contingut (no els valors, que canvien a cada tecla).
    private enum Identitat: Hashable {
        case res, finestra(Finestra.ID), pestanyes([Pestanya.ID])

        init(_ contingut: Editor.ContingutInspector) {
            switch contingut {
            case .res: self = .res
            case let .finestra(finestra): self = .finestra(finestra.id)
            case let .pestanya(pestanya): self = .pestanyes([pestanya.id])
            case let .pestanyes(pestanyes): self = .pestanyes(pestanyes.map(\.id))
            }
        }
    }
}

// MARK: - Finestra

private struct InspectorFinestra: View {
    let editor: Editor
    let finestra: Finestra

    var body: some View {
        Form {
            Section(t("Finestra")) {
                CampText(t("Nom"), valor: finestra.nom, indicacio: nil, buitTornaAlDAbans: true) { nom in
                    editor.reanomenaFinestra(finestra.id, a: nom, agrupa: "nom")
                } acaba: {
                    editor.acabaAgrupacio()
                }
                LabeledContent(t("Pestanyes"), value: finestra.resum)
                ForEach(Array((editor.avisos.finestres[finestra.id] ?? []).enumerated()), id: \.offset) { _, avis in
                    FilaAvis(avis: avis)
                }
            }
            Section {
                // Sense drecera ni botó per defecte: abans d'obrir res, el full diu què s'obrirà i demana confirmació.
                Button(t("Obre a Warp…")) { editor.demanaObertura(finestra.id) }
                    .disabled(!editor.potObrir(finestra.id))
                    .help(t("Mostra quines pestanyes s'obririen a Warp, i amb quina conversa; no obre res fins que ho confirmis"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Una pestanya

private struct InspectorPestanya: View {
    let editor: Editor
    let pestanya: Pestanya
    let inici: String
    private var triaCarpeta = State(initialValue: false)

    init(editor: Editor, pestanya: Pestanya, inici: String) {
        self.editor = editor
        self.pestanya = pestanya
        self.inici = inici
    }

    var body: some View {
        let avisos = editor.avisosInspector(pestanya.id)
        let id = pestanya.id
        Form {
            Section(t("Pestanya")) {
                CampText(t("Nom"), valor: pestanya.titol, indicacio: (pestanya.carpeta as NSString).lastPathComponent) { nom in
                    editor.reanomenaPestanya(id, a: nom, agrupa: "nom")
                } acaba: {
                    editor.acabaAgrupacio()
                }
                HStack(spacing: 8) {
                    CampText(t("Carpeta"), valor: Rutes.abreujada(pestanya.carpeta, inici: inici), indicacio: "~/GitHub/…",
                             normalitza: { Rutes.abreujada(Rutes.desabreujada($0, inici: inici), inici: inici) }) { text in
                        editor.canviaCarpeta([id], a: Rutes.desabreujada(text, inici: inici), agrupa: "carpeta")
                    } acaba: {
                        editor.acabaAgrupacio()
                    }
                    Button(t("Tria…")) { triaCarpeta.wrappedValue = true }
                        .help(t("Tria la carpeta al Finder"))
                }
                ForEach(Array(avisos.carpeta.enumerated()), id: \.offset) { _, avis in
                    FilaAvis(avis: avis)
                }
            }
            // Un nom propi: no es tradueix.
            Section {
                BlocClaude(editor: editor, unaSola: pestanya)
                ForEach(Array(avisos.claude.enumerated()), id: \.offset) { _, avis in
                    FilaAvis(avis: avis)
                }
            } header: {
                Text(verbatim: "Claude Code")
            }
            let nomesLectura = pestanya.claude.opcionsNomesLectura
            if !nomesLectura.isEmpty {
                Section {
                    ForEach(nomesLectura, id: \.nom) { opcio in
                        LabeledContent(opcio.nom) {
                            Text(opcio.valor)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text(t("Altres opcions"))
                } footer: {
                    Text(t("L'editor no les canvia: es conserven tal com són."))
                        .foregroundStyle(.secondary)
                }
            }
            Section(t("Ordre")) {
                BlocOrdre(claude: pestanya.claude, repren: editor.conversaDe(pestanya))
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: triaCarpeta.projectedValue, allowedContentTypes: [.folder]) { resultat in
            if case let .success(url) = resultat { editor.canviaCarpeta([id], a: url.path) }
        }
        // A la carpeta pare, o a la més propera que existeixi: amb una que no existeix, el diàleg s'obriria on vol el
        // sistema.
        .fileDialogDefaultDirectory(URL(filePath: editor.carpetaPerTriar(pestanya), directoryHint: .isDirectory))
        .fileDialogMessage(t("Tria la carpeta de la pestanya"))
        .fileDialogConfirmationLabel(t("Tria"))
    }
}

// MARK: - Claude Code

/// Els camps de Claude d'una pestanya (`unaSola`) o de les triades (`nil`, sense el nom fix: dues sessions amb el
/// mateix nom es confondrien). Amb Claude apagat a totes, la resta queda desactivada.
private struct BlocClaude: View {
    let editor: Editor
    let unaSola: Pestanya?

    var body: some View {
        Toggle(unaSola == nil ? t("Obre Claude Code") : t("Obre Claude Code en aquesta pestanya"),
               sources: fonts(.activat), isOn: \.self)
            // Caselles i no interruptors: només una casella mostra el guió de «Valors diversos» (NSSwitch no en té).
            .toggleStyle(.checkbox)
        Group {
            tria(.model, t("Model"))
            tria(.esforc, t("Esforç"))
            Toggle(ClaudePestanya.nomUltracode, sources: fonts(.ultracode), isOn: \.self)
                .toggleStyle(.checkbox)
                .help(t("Orquestració amb dynamic workflows. Amb l'esforç «Molt alt», l'ordre fa servir --effort ultracode"))
            Toggle(t("Continua la conversa"), sources: fonts(.continua), isOn: \.self)
                .toggleStyle(.checkbox)
                .help(t("En obrir-la, la pestanya reprèn la conversa més recent de la seva carpeta en lloc de començar-ne una de nova"))
            if let pestanya = unaSola, pestanya.claude.activat, pestanya.claude.continua {
                LabeledContent(t("Conversa"), value: Self.conversa(editor.conversaDe(pestanya)))
                    .help(t("La conversa més recent de la seva carpeta. Si no n'hi ha cap, se'n començarà una de nova"))
            }
            if let pestanya = unaSola {
                CampText(t("Nom de la sessió"), valor: pestanya.claude.nom ?? "", indicacio: t("Cap"),
                         normalitza: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : $0 }) { nom in
                    editor.canviaNomSessio(pestanya.id, a: nom, agrupa: "nom de la sessió")
                } acaba: {
                    editor.acabaAgrupacio()
                }
                .help(t("Nom fix de la sessió (-n): surt al selector de /resume i al títol del terminal"))
            }
            Toggle(t("Salta els permisos"), sources: fonts(.saltaPermisos), isOn: \.self)
                .toggleStyle(.checkbox)
                .help(t("--dangerously-skip-permissions: Claude no demana permís per a res, ni les feines noves que engegui directament amb claude --bg"))
            tria(.modePermisos, t("Mode de permisos"))
                .disabled(editor.modeSenseEfecte)
                .help(editor.modeSenseEfecte ? Text(t("Amb «Salta els permisos», Claude no fa cas del mode"))
                                             : Text(verbatim: "--permission-mode"))
            if editor.modeSenseEfecte, editor.tria(.modePermisos) != .perDefecte {
                Button(t("Treu el mode de permisos")) { editor.tria(.modePermisos, a: .perDefecte) }
            }
        }
        .disabled(editor.claudeApagatATotes)
    }

    /// «reprèn 1b2c3d4e» (els 8 primers caràcters de l'id) o «nova».
    static func conversa(_ sessio: String?) -> String {
        sessio.map { t("reprèn \(String($0.prefix(8)))") } ?? t("nova")
    }

    private func tria(_ camp: Editor.CampTria, _ titol: String) -> some View {
        Picker(titol, selection: Binding { editor.tria(camp) } set: { editor.tria(camp, a: $0) }) {
            ForEach(editor.opcions(camp)) { opcio in
                Text(opcio.text).tag(opcio.tria)
            }
        }
    }

    /// Un interruptor per pestanya triada: amb valors diferents, el control es mostra mixt.
    private func fonts(_ camp: Editor.CampSiNo) -> [Binding<Bool>] {
        editor.pestanyes.map { pestanya in
            Binding { pestanya.claude[keyPath: camp.cami] } set: { editor.posa(camp, $0) }
        }
    }
}

/// L'ordre que s'escriurà a la pestanya, seleccionable, amb «Copia l'ordre». També a la Configuració (la plantilla).
struct BlocOrdre: View {
    let claude: ClaudePestanya
    /// La conversa que reprendria (D7), si se sap; si no, l'ordre en comença una de nova.
    var repren: String? = nil

    var body: some View {
        switch OrdreClaude.text(de: claude, repren: repren) {
        case .success(nil):
            Text(t("Només terminal: no s'hi obre Claude."))
                .foregroundStyle(.secondary)
        case let .success(ordre?):
            Text(ordre)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            BotoCopia(text: ordre, titol: t("Copia l'ordre"))
        case let .failure(error):
            FilaAvis(avis: Avis(.ordreImpossible(error)))
        }
    }
}

struct BotoCopia: View {
    let text: String
    let titol: String

    var body: some View {
        Button(titol) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        .disabled(text.isEmpty)
    }
}

// MARK: - Peces

/// Un avís: sempre icona i text, mai només color.
struct FilaAvis: View {
    let avis: Avis

    var body: some View {
        Label {
            Text(avis.description)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icona)
                .symbolRenderingMode(.multicolor)
        }
        .foregroundStyle(avis.gravetat == .info ? .secondary : .primary)
    }

    private var icona: String {
        switch avis.gravetat {
        case .info: "info.circle"
        case .avis: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

/// Camp de text de l'inspector. Cada tecla canvia la configuració (un sol pas de Desfés per camp, amb `agrupa`), i
/// sortir del camp, prémer Retorn o que el camp desaparegui (una altra selecció, amagar l'inspector) tanca el pas.
/// Mentre s'hi escriu, es veu el que s'escriu; si la configuració canvia per una altra via (⌘Z), el camp la torna a
/// mostrar.
private struct CampText: View {
    let titol: String
    let valor: String
    let indicacio: String?
    /// Per al nom de la finestra, que no pot quedar buit: si se surt del camp buit, torna al nom d'abans d'entrar-hi
    /// (si no, es quedaria amb la primera lletra, l'última que s'ha desat en esborrar).
    let buitTornaAlDAbans: Bool
    /// Com es mostraria `valor` després de desar un text: la carpeta es mostra abreujada, i el nom de la sessió buit
    /// no es desa. Si coincideix amb `valor`, el canvi del camp no canvia res.
    let normalitza: (String) -> String
    let canvia: (String) -> Void
    let acaba: () -> Void
    private var esborrany: State<String>
    /// El valor en entrar al camp.
    private var enEntrar: State<String?>
    @FocusState private var enfocat: Bool

    init(_ titol: String, valor: String, indicacio: String?, buitTornaAlDAbans: Bool = false,
         normalitza: @escaping (String) -> String = { $0 },
         canvia: @escaping (String) -> Void, acaba: @escaping () -> Void) {
        self.titol = titol
        self.valor = valor
        self.indicacio = indicacio
        self.buitTornaAlDAbans = buitTornaAlDAbans
        enEntrar = State(initialValue: nil)
        self.normalitza = normalitza
        self.canvia = canvia
        self.acaba = acaba
        esborrany = State(initialValue: valor)
    }

    var body: some View {
        TextField(titol, text: esborrany.projectedValue, prompt: indicacio.map { Text($0) })
            .focused($enfocat)
            .onChange(of: esborrany.wrappedValue) { _, text in
                // Quan el camp només torna a mostrar la configuració, no hi ha res a desar.
                if enfocat, normalitza(text) != valor { canvia(text) }
            }
            .onChange(of: valor) { _, nou in
                if !enfocat || normalitza(esborrany.wrappedValue) != nou { esborrany.wrappedValue = nou }
            }
            .onChange(of: enfocat) { _, ara in
                if ara { enEntrar.wrappedValue = valor } else { tanca() }
            }
            .onSubmit(tanca)
            .onDisappear(perform: tanca)
    }

    private func tanca() {
        if buitTornaAlDAbans, esborrany.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let abans = enEntrar.wrappedValue, abans != valor {
            // Amb la mateixa agrupació: el pas torna a com era, i l'editor el treu.
            canvia(abans)
        }
        acaba()
        enEntrar.wrappedValue = nil
        esborrany.wrappedValue = valor
    }
}
