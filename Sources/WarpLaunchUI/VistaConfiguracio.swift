import SwiftUI
import WarpLaunchCore

/// La finestra de Configuració (⌘,; docs/disseny.md, pas 11): la plantilla de les pestanyes noves, l'ordre que en
/// surt i el fitxer. Un sol panell, d'amplada fixa i alçada del contingut (settings.md de mac-design). Els canvis de
/// la plantilla van al Desfés d'aquesta finestra (`Editor.desferPlantilla`), no al de l'editor.
public struct VistaConfiguracio: View {
    @Bindable var editor: Editor
    let carpeta: String
    let deProva: Bool
    let arrencada: ArrencadaSessio

    public init(editor: Editor, carpeta: String, deProva: Bool, arrencada: ArrencadaSessio) {
        self.editor = editor
        self.carpeta = carpeta
        self.deProva = deProva
        self.arrencada = arrencada
    }

    public var body: some View {
        Form {
            if let plantilla = editor.plantillaVisible {
                seccionsPlantilla(plantilla)
            } else {
                // Carregant, o el fitxer no es pot llegir: cap valor, perquè no se sap quina és la plantilla.
                Section("Pestanyes noves") {
                    Text(editor.motiuPlantillaNoEditable ?? "")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            seccioArrencada
            seccioFitxer
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func seccionsPlantilla(_ plantilla: ClaudePestanya) -> some View {
        Section {
            interruptor(.activat, "Obre Claude Code a les pestanyes noves")
            Group {
                tria(.model, "Model")
                tria(.esforc, "Esforç")
                interruptor(.ultracode, "Ultracode")
                    .help("Orquestració amb dynamic workflows. Amb l'esforç «Molt alt», l'ordre fa servir --effort ultracode")
                interruptor(.continua, "Continua la conversa")
                    .help("En obrir-les, les pestanyes reprenen la seva conversa en lloc de començar-ne una de nova")
                interruptor(.saltaPermisos, "Salta els permisos")
                    .help("--dangerously-skip-permissions: Claude no demana permís per a res, ni les feines noves que engegui directament amb claude --bg")
                tria(.modePermisos, "Mode de permisos")
                    .disabled(editor.modeSenseEfectePlantilla)
                    .help(editor.modeSenseEfectePlantilla
                        ? "Amb «Salta els permisos», Claude no fa cas del mode" : "--permission-mode")
                if editor.modeSenseEfectePlantilla, editor.triaPlantilla(.modePermisos) != .perDefecte {
                    Button("Treu el mode de permisos") { editor.triaPlantilla(.modePermisos, a: .perDefecte) }
                }
            }
            .disabled(!plantilla.activat)
            if let nom = editor.nomSessioPlantilla {
                LabeledContent("Nom de la sessió") {
                    Text("\(nom) (no s'aplica)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .help("Escrit al fitxer: les pestanyes noves no el copien mai, perquè totes tindrien el mateix nom")
            }
        } header: {
            Text("Pestanyes noves")
        } footer: {
            Text(editor.motiuPlantillaNoEditable ?? "S'aplica a les pestanyes noves i a les que s'importen sense "
                + "sessió de Claude. Les que ja hi són no canvien.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!editor.potCanviarPlantilla)

        Section("Ordre") {
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
                Text("Altres opcions")
            } footer: {
                Text("La Configuració no les canvia: es conserven tal com són.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// D3: en iniciar sessió, l'app s'obre sola i mostra el full de «Obre-ho tot»; no obre res sense el clic.
    private var seccioArrencada: some View {
        Section {
            Toggle("Obre Warp Launch en iniciar sessió", isOn: Binding { arrencada.activada } set: { arrencada.posa($0) })
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!arrencada.editable)
            if arrencada.estat == .perAprovar {
                HStack {
                    Label("macOS no l'obrirà sola fins que la permetis a Ítems d’inici de sessió",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                    Button("Mostra Ítems d’inici de sessió…") { arrencada.obreAjustos() }
                }
            }
            if let error = arrencada.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
        } header: {
            Text("En iniciar sessió")
        } footer: {
            Text(arrencada.activada || arrencada.motiuNoDisponible == nil
                ? "Quan Warp és a punt, mostra «Obre-ho tot a Warp…» amb les finestres que falten. No obre res fins que hi "
                    + "fas clic. També es desactiva a Configuració del Sistema › General › Ítems d’inici de sessió."
                : arrencada.motiuNoDisponible ?? "")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seccioFitxer: some View {
        Section("Fitxer") {
            LabeledContent("Carpeta de la configuració") {
                Text(carpeta)
                    .textSelection(.enabled)
            }
            if let fitxer = editor.fitxerPerMostrar {
                Button("Mostra al Finder") { Finder.mostra(fitxer) }
            }
            if deProva {
                Label("Configuració de prova (--config)", systemImage: "testtube.2")
            }
            if let error = editor.errorDesat {
                HStack {
                    Label(error == .modificadaFora ? "El fitxer ha canviat fora de l'app"
                            : "No s'ha pogut desar: \(error.description)",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                    if error == .modificadaFora {
                        Button("Torna a carregar") { editor.carrega() }
                    } else {
                        Button("Torna-ho a provar") { editor.desaSiCal() }
                    }
                }
            }
            LabeledContent("Versió", value: WarpLaunch.versio)
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
