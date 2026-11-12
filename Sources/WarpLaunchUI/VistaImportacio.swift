import SwiftUI
import WarpLaunchCore

/// El full d'importació: llegeix Warp en obrir-se i diu amb xifres què en sortiria. No escriu res fins a «Crea» o
/// «Substitueix». Escapada el tanca.
struct VistaImportacio: View {
    /// Es guarda com a `State` perquè el full no torni a començar cada vegada que l'editor es redibuixa. Sense
    /// `@State`: amb aquest SDK, l'atribut és una macro de SwiftUI que les Command Line Tools no tenen.
    private var estat: State<FullImportacio>
    @Environment(\.dismiss) private var tanca

    /// També per a la prova de les amplades (F6, `AmpladesTests`).
    static let amplada: CGFloat = 560

    init(full: FullImportacio) {
        estat = State(initialValue: full)
    }

    private var full: FullImportacio { estat.wrappedValue }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                contingut
            }
            .formStyle(.grouped)
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if full.importacio != nil {
                    Button(WarpLaunch.ordreActualitzaEstat) { Task { await full.llegeix() } }
                        .help(t("\(WarpLaunch.ordreActualitzaEstat), per si hi has obert o tancat res"))
                        .disabled(!full.potLlegir)
                }
                Spacer()
                Button(t("Cancel·la"), role: .cancel) { tanca() }
                    .keyboardShortcut(.cancelAction)
                Button(full.boto) {
                    if full.confirma() { tanca() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!full.potConfirmar)
            }
            .padding(20)
        }
        .frame(width: Self.amplada)
        .task { await full.llegeix() }
    }

    @ViewBuilder
    private var contingut: some View {
        switch full.estat {
        case .llegint:
            Section(full.titol) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("Llegint Warp…"))
                }
            }
        case let .error(motiu):
            Section(full.titol) {
                Label(t("No s'ha pogut llegir Warp: \(motiu)"), systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
                Button(t("Torna-ho a provar")) { Task { await full.llegeix() } }
                    .disabled(!full.potLlegir)
            }
        case let .senseFinestres(motiu):
            Section(full.titol) {
                Label(motiu, systemImage: "info.circle")
                    .textSelection(.enabled)
            }
        case let .llest(importacio):
            Section(full.titol) {
                ForEach(full.xifres, id: \.self) { linia in
                    Text(linia)
                }
                if let text = full.textPerRevisar {
                    Label(text, systemImage: "exclamationmark.triangle")
                }
                if full.plantillaHaCanviat {
                    Label(t("La plantilla ha canviat a la Configuració: prem «\(WarpLaunch.ordreActualitzaEstat)» per importar amb la nova"),
                          systemImage: "arrow.clockwise")
                }
            }
            if !full.avisosLectura.isEmpty {
                Section(t("Avisos de la lectura")) {
                    ForEach(Array(full.avisosLectura.enumerated()), id: \.offset) { _, avis in
                        Label(avis, systemImage: "exclamationmark.triangle")
                            .textSelection(.enabled)
                    }
                }
            }
            if let ordre = full.ordrePlantilla {
                Section(t("Pestanyes que no tenien Claude obert")) {
                    // Queden només terminal (D-P5a): es diu abans de l'ordre.
                    if let nota = full.notaSenseClaudeObert {
                        Text(nota)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(ordre)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section(t("Finestres")) {
                ForEach(importacio.configuracio.finestres) { finestra in
                    LabeledContent(finestra.nom, value: finestra.resum)
                }
            }
            if !importacio.notes.isEmpty {
                Section(t("Notes")) {
                    ForEach(Array(importacio.notes.enumerated()), id: \.offset) { _, nota in
                        Text(nota.description)
                            .textSelection(.enabled)
                    }
                }
            }
            Section {
                Text(full.explicacio)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
