import SwiftUI
import WarpLaunchCore

/// Les pestanyes de la Configuració, en aquest ordre (settings.md de mac-design: una per tema, «General» primer). macOS en
/// posa les icones a la barra d'eines, i el títol de la finestra és el de la pestanya que es veu. L'app no desa quina és
/// l'última: el codi de l'app no fa servir les preferències del sistema (prova de guarda; només Sparkle hi desa les seves, i
/// `ServeiIdioma`, la llengua), i la configuració JSON és d'en David.
public enum PestanyaConfiguracio: CaseIterable, Identifiable, Sendable {
    /// «En iniciar sessió», «Idioma», «Fitxer», «Diagnòstic» i, al final, «Deixar de fer servir Warp Launch».
    case general
    /// La plantilla de les pestanyes noves, l'ordre que en surt i les opcions que la Configuració no canvia.
    case pestanyesNoves
    /// La versió, si n'hi ha una de nova, i l'interruptor. A part de «General»: amb aquesta secció, «General» faria 738 pt, més dels 640
    /// pt de la norma (mesurat amb un programa a part, sense finestres, 09/11/2026).
    case actualitzacions

    public var id: Self { self }

    var titol: String {
        switch self {
        case .general: t("General")
        case .pestanyesNoves: t("Pestanyes noves")
        case .actualitzacions: t("Actualitzacions")
        }
    }

    /// SF Symbols de macOS 11, o d'abans.
    var simbol: String {
        switch self {
        case .general: "gearshape"
        case .pestanyesNoves: "plus.rectangle.on.rectangle"
        case .actualitzacions: "arrow.down.circle"
        }
    }
}

/// La finestra de Configuració (⌘,; docs/disseny.md, pas 11), en tres pestanyes (`PestanyaConfiguracio`): «General» (en
/// iniciar sessió, el fitxer, el diagnòstic, pla A4, i deixar de fer servir l'app, 0.31.0) i «Pestanyes noves» (la
/// plantilla i l'ordre que en surt) i «Actualitzacions». Els canvis de la plantilla van al Desfés d'aquesta finestra (`Editor.desferPlantilla`),
/// no al de l'editor.
public struct VistaConfiguracio: View {
    @Bindable var editor: Editor
    let carpeta: String
    let deProva: Bool
    let arrencada: ArrencadaSessio
    /// «Idioma» (F4). Sense, la secció no surt (l'executable sol, sense paquet).
    let idioma: SelectorIdioma?
    /// Pla A4: «Copia el diagnòstic».
    let diagnostic: CopiaDiagnostic
    /// Decisió 3 (0.31.0): «Deixa de fer servir Warp Launch».
    @Bindable var desinstallacio: Desinstallacio
    /// «Actualitzacions», i la pestanya que es veu.
    @Bindable var actualitzacions: Actualitzacions

    public init(editor: Editor, carpeta: String, deProva: Bool, arrencada: ArrencadaSessio, idioma: SelectorIdioma?,
                diagnostic: CopiaDiagnostic, desinstallacio: Desinstallacio, actualitzacions: Actualitzacions) {
        self.actualitzacions = actualitzacions
        self.editor = editor
        self.carpeta = carpeta
        self.deProva = deProva
        self.arrencada = arrencada
        self.idioma = idioma
        self.diagnostic = diagnostic
        self.desinstallacio = desinstallacio
    }

    /// settings.md: cada pestanya, un `Form` agrupat de 520 pt d'amplada; la que faria més de 640 pt d'alçada es desplaça.
    static let amplada: CGFloat = 520
    static let alcadaMaxima: CGFloat = 640

    public var body: some View {
        // Sense cap marc al `TabView`: la mida és la de la pestanya que es veu (`formulari`).
        // La pestanya, al model i no en un `@State` (no compila amb les Command Line Tools): el menú hi ha de poder portar.
        TabView(selection: $actualitzacions.pestanyaConfiguracio) {
            ForEach(PestanyaConfiguracio.allCases) { pestanya in
                Tab(pestanya.titol, systemImage: pestanya.simbol, value: pestanya) {
                    formulari(pestanya)
                }
            }
        }
        // En canviar de pestanya (o quan una pestanya creix, com amb el text de «Copia el diagnòstic»), la finestra canvia
        // d'alçada per baix: la vora de dalt, amb la barra de les pestanyes, no es mou (macOS 26).
        .windowResizeAnchor(.top)
    }

    /// Una pestanya: tan alta com el contingut, i com a molt `alcadaMaxima`; el que no hi cap es desplaça dins del `Form`.
    ///
    /// L'ordre dels modificadors compta. Un `Form` agrupat és una vista de desplaçament, i la seva alçada ideal és la de tot
    /// el contingut. `fixedSize` vertical demana l'alçada ideal al marc, i el marc la retalla a `alcadaMaxima` i col·loca el
    /// `Form` amb aquesta alçada: la pestanya fa l'alçada del contingut, fins a 640 pt, sigui quina sigui l'alçada que li
    /// ofereixin. Amb `.windowResizability(.contentSize)` a l'escena, la finestra pren aquesta mida (la mínima i la màxima
    /// del contingut són iguals) i canvia de mida a cada pestanya. Si el contingut és més curt, el `Form` no té res per
    /// desplaçar i macOS no hi posa cap barra; si és més llarg, el `Form` fa 640 pt i s'hi desplaça. Mesurat amb un programa
    /// a part, sense mostrar cap finestra (07/11/2026, macOS 27.2). Fins a la 0.30.1, sense `frame(maxHeight:)`, la finestra
    /// feia l'alçada de tot el contingut, més que la pantalla, i no es podia fer més baixa.
    private func formulari(_ pestanya: PestanyaConfiguracio) -> some View {
        Form {
            switch pestanya {
            case .general:
                seccioArrencada
                seccioIdioma
                seccioFitxer
                seccioDiagnostic
                seccioDesinstallacio
            case .pestanyesNoves:
                seccionsPestanyesNoves
            case .actualitzacions:
                seccioActualitzacions
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.amplada)
        .frame(maxHeight: Self.alcadaMaxima)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var seccionsPestanyesNoves: some View {
        if let plantilla = editor.plantillaVisible {
            seccionsPlantilla(plantilla)
        } else {
            // Carregant, o el fitxer no es pot llegir: cap valor, perquè no se sap quina és la plantilla. Sense títol, com
            // la de la plantilla.
            Section {
                Text(editor.motiuPlantillaNoEditable ?? "")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// La primera secció no té títol: repetiria el de la pestanya (decisió d'en David del 08/11/2026). El peu es queda.
    @ViewBuilder
    private func seccionsPlantilla(_ plantilla: ClaudePestanya) -> some View {
        Section {
            interruptor(.activat, t("Obre Claude Code a les pestanyes noves"))
            Group {
                tria(.model, t("Model"))
                tria(.esforc, t("Esforç"))
                interruptor(.ultracode, ClaudePestanya.nomUltracode)
                    .help(t("Orquestració amb dynamic workflows. Amb l'esforç «Molt alt», l'ordre fa servir --effort ultracode"))
                interruptor(.continua, t("Continua la conversa"))
                    .help(t("En obrir-les, les pestanyes reprenen la seva conversa en lloc de començar-ne una de nova"))
                interruptor(.saltaPermisos, t("Salta els permisos"))
                    .help(t("--dangerously-skip-permissions: Claude no demana permís per a res, ni les feines noves que engegui directament amb claude --bg"))
                tria(.modePermisos, t("Mode de permisos"))
                    .disabled(editor.modeSenseEfectePlantilla)
                    .help(editor.modeSenseEfectePlantilla
                        ? Text(t("Amb «Salta els permisos», Claude no fa cas del mode")) : Text(verbatim: "--permission-mode"))
                if editor.modeSenseEfectePlantilla, editor.triaPlantilla(.modePermisos) != .perDefecte {
                    Button(t("Treu el mode de permisos")) { editor.triaPlantilla(.modePermisos, a: .perDefecte) }
                }
            }
            .disabled(!plantilla.activat)
            if let nom = editor.nomSessioPlantilla {
                LabeledContent(t("Nom de la sessió")) {
                    Text(t("\(nom) (no s'aplica)"))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .help(t("Escrit al fitxer: les pestanyes noves no el copien mai, perquè totes tindrien el mateix nom"))
            }
        } footer: {
            Text(editor.motiuPlantillaNoEditable ?? t("S'aplica a les pestanyes noves i a les que s'importen sense sessió de Claude. Les que ja hi són no canvien."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!editor.potCanviarPlantilla)

        Section(t("Ordre")) {
            // La de les pestanyes noves: sense el nom fix de sessió.
            BlocOrdre(claude: plantilla.perAPestanyaNova())
            ForEach(Array(editor.avisosPlantilla.enumerated()), id: \.offset) { _, avis in
                FilaAvis(avis: avis)
            }
        }

        let nomesLectura = editor.opcionsNomesLecturaPlantilla
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
                Text(t("La Configuració no les canvia: es conserven tal com són."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// D3: en iniciar sessió, l'app s'obre sola i mostra el full de «Obre-ho tot»; no obre res sense el clic.
    private var seccioArrencada: some View {
        Section {
            Toggle(t("Obre Warp Launch en iniciar sessió"), isOn: Binding { arrencada.activada } set: { arrencada.posa($0) })
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!arrencada.editable)
            if arrencada.estat == .perAprovar {
                HStack {
                    Label(t("macOS no l'obrirà sola fins que la permetis a Ítems d’inici de sessió"),
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                    Button(t("Mostra Ítems d’inici de sessió…")) { arrencada.obreAjustos() }
                }
            }
            if let error = arrencada.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
        } header: {
            Text(t("En iniciar sessió"))
        } footer: {
            Text(arrencada.activada || arrencada.motiuNoDisponible == nil
                ? t("""
                    Quan Warp és a punt, mostra «Obre-ho tot a Warp…» amb les finestres que falten. No obre res fins que hi fas \
                    clic. També es desactiva a Configuració del Sistema › General › Ítems d’inici de sessió.
                    """)
                : arrencada.motiuNoDisponible ?? "")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// F4: la llengua de l'app, o la del sistema. Es desa a les preferències de l'app i canvia la propera vegada que s'obre: l'app
    /// no es reinicia sola.
    @ViewBuilder
    private var seccioIdioma: some View {
        if let idioma {
            Section {
                Picker(t("Idioma de l'app"), selection: Binding { idioma.tria } set: { idioma.posa($0) }) {
                    Text(idioma.sistema.text).tag(SelectorIdioma.Tria.sistema)
                    Divider()
                    ForEach(idioma.llengues) { opcio in
                        Text(opcio.text).tag(opcio.tria)
                    }
                }
            } header: {
                Text(t("Idioma"))
            } footer: {
                if let nota = idioma.nota {
                    Text(nota)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var seccioFitxer: some View {
        Section(t("Fitxer")) {
            LabeledContent(t("Carpeta de la configuració")) {
                Text(carpeta)
                    .textSelection(.enabled)
            }
            if let fitxer = editor.fitxerPerMostrar {
                Button(t("Mostra al Finder")) { Finder.mostra(fitxer) }
            }
            if deProva {
                Label(t("Configuració de prova (--config)"), systemImage: "testtube.2")
            }
            if let error = editor.errorDesat {
                HStack {
                    Label(error == .modificadaFora ? t("El fitxer ha canviat fora de l'app")
                            : t("No s'ha pogut desar: \(error.description)"),
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                    if error == .modificadaFora {
                        Button(t("Torna a carregar")) { editor.carrega() }
                    } else {
                        Button(t("Torna-ho a provar")) { editor.desaSiCal() }
                    }
                }
            }
        }
    }

    /// L'actualització automàtica (docs/disseny.md, secció 11, 2.1): cap finestra de l'actualitzador sense demanar-la. Tots els textos i
    /// el botó surten del model, amb proves.
    private var seccioActualitzacions: some View {
        Section {
            LabeledContent(t("Versió"), value: WarpLaunch.versio)
            if actualitzacions.disponible {
                LabeledContent {
                    botoActualitzacions
                } label: {
                    Text(t("Estat"))
                    Text(actualitzacions.text(avui: Date()))
                }
                if let avis = actualitzacions.textAvis {
                    Text(avis)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = actualitzacions.errorPreparant {
                    Label(t("No s'ha pogut preparar l'actualització: \(error)"), systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                Toggle(t("Actualitza automàticament"), isOn: Binding { actualitzacions.automatiques } set: { actualitzacions.posaAutomatiques($0) })
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        } header: {
            Text(t("Actualitzacions"))
        } footer: {
            Text(actualitzacions.textPeu)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var botoActualitzacions: some View {
        switch actualitzacions.boto {
        case .cap:
            EmptyView()
        case let .comprovaAra(actiu):
            Button(t("Comprova ara")) { actualitzacions.comprova(ara: ProcessInfo.processInfo.systemUptime) }
                .disabled(!actiu)
        case .actualitzaAra:
            Button(t("Actualitza ara")) { actualitzacions.actualitzaAra() }
        case let .reinicia(actiu):
            Button(t("Reinicia i actualitza")) { actualitzacions.reinicia(ara: ProcessInfo.processInfo.systemUptime) }
                .disabled(!actiu)
        case .mostraFinestra:
            Button(t("Mostra la finestra")) { actualitzacions.mostraFinestra() }
        }
    }

    /// Pla A4: l'informe per a una issue de GitHub, al porta-retalls (`CopiaDiagnostic`). Per defecte, l'anonimitzat; el
    /// complet, al menú del botó.
    private var seccioDiagnostic: some View {
        Section {
            LabeledContent {
                Menu(t("Copia el diagnòstic")) {
                    Button(t("Copia el diagnòstic complet")) { Task { await diagnostic.copia(anonimitzat: false) } }
                } primaryAction: {
                    Task { await diagnostic.copia(anonimitzat: true) }
                }
                .menuStyle(.button)
                .fixedSize()
                .disabled(diagnostic.calculant)
            } label: {
                Text(t("Informe per a una issue a GitHub"))
                if let copiat = diagnostic.copiat {
                    Text(copiat)
                }
            }
        } header: {
            Text(t("Diagnòstic"))
        } footer: {
            Text(t("""
                Comprova si Warp i Claude Code han canviat el que l'app llegeix, i en copia l'informe (en anglès) al \
                porta-retalls. No obre ni canvia res. No porta el teu nom d'usuari, ni les rutes de casa, ni els noms de les \
                carpetes; el complet, sí.
                """))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Decisió 3 (0.31.0): torna l'ajust de Warp com era, retira el permís, treu l'app dels ítems d'inici i surt. Al final de
    /// «General», amb `role: .destructive` i una confirmació que diu què passarà (settings.md: no es pot desfer, perquè
    /// l'app surt). «Cancel·la» és el botó per defecte: Retorn no la fa sortir.
    private var seccioDesinstallacio: some View {
        Section {
            LabeledContent {
                // La confirmació, al botó i no a la `Section`: en un `Form`, el que es posa a una secció pot anar a cada fila,
                // i amb la fila de l'error hi hauria dues confirmacions per a la mateixa variable (revisió de la 0.31.0).
                Button(t("Restaura Warp i surt…"), role: .destructive) { desinstallacio.demana() }
                    .disabled(!desinstallacio.disponible)
                    .confirmationDialog(Desinstallacio.titolConfirmacio, isPresented: $desinstallacio.confirmant,
                                        titleVisibility: .visible) {
                        Button(t("Restaura Warp i surt"), role: .destructive) { desinstallacio.confirma() }
                        Button(t("Cancel·la"), role: .cancel) {}
                            .keyboardShortcut(.defaultAction)
                    } message: {
                        Text(desinstallacio.missatgeConfirmacio)
                    }
            } label: {
                Text(t("Torna a deixar Warp com era"))
                if let text = desinstallacio.textAjust {
                    Text(text)
                }
            }
            // En tornar a la pestanya, o després d'acceptar el permís en aquesta mateixa finestra.
            .onAppear { desinstallacio.actualitza() }
            if let error = desinstallacio.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
            }
        } header: {
            Text(t("Deixar de fer servir Warp Launch"))
        } footer: {
            Text(desinstallacio.peu)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func interruptor(_ camp: Editor.CampSiNo, _ titol: String) -> some View {
        Toggle(titol, isOn: Binding { editor.siNoPlantilla(camp) } set: { editor.posaPlantilla(camp, $0) })
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    private func tria(_ camp: Editor.CampTria, _ titol: String) -> some View {
        Picker(titol, selection: Binding { editor.triaPlantilla(camp) } set: { editor.triaPlantilla(camp, a: $0) }) {
            ForEach(editor.opcionsPlantilla(camp)) { opcio in
                Text(opcio.text).tag(opcio.tria)
            }
        }
    }
}
