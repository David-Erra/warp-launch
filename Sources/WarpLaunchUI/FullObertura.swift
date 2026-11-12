import SwiftUI
import WarpLaunchCore

/// El full de confirmació d'obrir una finestra a Warp (docs/disseny.md, secció 7, «El full de confirmació»): què
/// s'obrirà, amb xifres, què ja és obert i què no es pot obrir, i per què. **És l'únic lloc des d'on s'obre res:**
/// «Obre N pestanyes» no té drecera ni és el botó per defecte, i Escapada cancel·la.
struct FullObertura: View {
    let obertura: Obertura
    let inici: String

    /// També per a la prova de les amplades (F6, `AmpladesTests`).
    static let amplada: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            Form {
                contingut
            }
            .formStyle(.grouped)
            .frame(maxHeight: 600)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                botons
            }
            .padding(20)
        }
        .frame(width: Self.amplada)
        .interactiveDismissDisabled(obrint)
    }

    private var obrint: Bool {
        switch obertura.estat {
        case .obrint, .obrintTot: true
        default: false
        }
    }

    // MARK: - Contingut

    @ViewBuilder
    private var contingut: some View {
        switch obertura.estat {
        case .cap:
            EmptyView()
        case let .preparant(nom, _):
            Section(t("Obre «\(nom)» a Warp")) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("Llegint Warp i les sessions de Claude…"))
                }
            }
        case let .noEsPot(motiu):
            Section(t("No es pot obrir")) {
                Label(motiu, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
                Text(t("No s'ha obert cap pestanya."))
                    .foregroundStyle(.secondary)
            }
        case let .confirmant(proposta):
            seccions(proposta, fase: nil)
        case let .obrint(proposta, fase):
            seccions(proposta, fase: fase)
        case .preparantTot:
            Section(t("Obre-ho tot a Warp")) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("Llegint Warp i les sessions de Claude…"))
                }
            }
        case let .confirmantTot(proposta):
            seccionsTot(proposta, fase: nil)
        case let .obrintTot(proposta, fase):
            seccionsTot(proposta, fase: fase)
        }
    }

    // MARK: - Obre-ho tot

    @ViewBuilder
    private func seccionsTot(_ p: Obertura.PropostaTot, fase: Obertura.Fase?) -> some View {
        let finestres = p.aObrir
        Section(t("Obre-ho tot a Warp")) {
            if p.haCanviat {
                Label(t("Warp ha canviat mentre el full era obert: revisa-ho abans d'obrir"), systemImage: "arrow.clockwise")
            }
            Text(p.text)
            if p.warpTancat, !finestres.isEmpty {
                Label(Obertura.textWarpTancat(restaura: p.warpDesaFinestres), systemImage: "power")
            }
            if !finestres.isEmpty {
                Label(Obertura.textFeinesEnSegonPla, systemImage: "exclamationmark.triangle")
            }
            if p.terminalsDesconeguts > 0, !finestres.isEmpty {
                Label(t("""
                    Warp ja té \(p.terminalsDesconeguts) pestanyes que l'app no reconeix (potser les ha restaurat Warp, sense \
                    Claude). Si obres, quedaran repetides: tanca-les abans si no les vols.
                    """), systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            let potser = finestres.map(\.pla.potserObertes).reduce(0, +)
            if potser > 0 {
                Label(Self.textPotserObertes(potser), systemImage: "link")
            }
            if let fase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(textTot(fase, finestres: finestres.count))
                }
            }
        }
        Section {
            ForEach(p.finestres, id: \.pla.finestra.id) { proposta in
                filaTot(proposta, triada: p.triades.contains(proposta.pla.finestra.id), bloquejada: fase != nil)
            }
        } header: {
            Text(t("Finestres"))
        } footer: {
            Text(t("Totes les marcades s'obren alhora. Si una no s'obre, les altres continuen, i al final es diu què ha passat."))
                .foregroundStyle(.secondary)
        }
        let avisos = p.finestres.filter { p.triades.contains($0.pla.finestra.id) }
            .flatMap { proposta in proposta.pla.avisos.map { (proposta.pla.finestra.nom, $0) } }
        if !avisos.isEmpty {
            Section {
                DisclosureGroup(t("\(avisos.count) avisos")) {
                    ForEach(Array(avisos.enumerated()), id: \.offset) { _, avis in
                        Label(t("\(avis.0) › \(avis.1.description)"),
                              systemImage: avis.1.esInfo ? "info.circle" : "exclamationmark.triangle")
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func filaTot(_ p: Obertura.Proposta, triada: Bool, bloquejada: Bool) -> some View {
        let pla = p.pla
        let esPot = Obertura.PropostaTot.esPotObrir(p)
        return Toggle(isOn: Binding(get: { triada && esPot },
                                    set: { obertura.tria(pla.finestra.id, $0) })) {
            Text(pla.finestra.nom)
            if pla.aObrir.isEmpty {
                Text(pla.excloses.isEmpty ? t("Totes les pestanyes ja són obertes") : pla.xifres.text)
            } else if let motiu = pla.motiuEspera {
                Text(motiu)
            } else if case let .failure(error)? = p.fitxer {
                Text(t("No es pot generar el fitxer per a Warp: \(error.description)"))
            } else {
                Text(pla.xifres.text)
            }
        }
        .disabled(!esPot || bloquejada)
    }

    private func textTot(_ fase: Obertura.Fase, finestres: Int) -> String {
        switch fase {
        case .comprovant: t("Comprovant que Warp no ha canviat…")
        case .engegant: t("Obrint Warp…")
        case .obrint: t("Obrint \(finestres) finestres a Warp…")
        case .esperant, .esperantClaude: t("Esperant les finestres noves i els seus Claude (fins a 30 s)…")
        }
    }

    @ViewBuilder
    private func seccions(_ p: Obertura.Proposta, fase: Obertura.Fase?) -> some View {
        let pla = p.pla
        Section(t("Obre «\(pla.finestra.nom)» a Warp")) {
            if p.haCanviat {
                Label(t("Warp ha canviat mentre el full era obert: revisa-ho abans d'obrir"), systemImage: "arrow.clockwise")
            }
            if pla.aObrir.isEmpty {
                Label(pla.excloses.isEmpty ? t("Totes les pestanyes ja són obertes") : t("No hi ha cap pestanya per obrir"),
                      systemImage: pla.excloses.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
            }
            Text(pla.xifres.text)
            if p.warpTancat, !pla.aObrir.isEmpty {
                Label(Obertura.textWarpTancat(restaura: p.warpDesaFinestres), systemImage: "power")
            }
            if !pla.aObrir.isEmpty {
                Label(Obertura.textFeinesEnSegonPla, systemImage: "exclamationmark.triangle")
            }
            if pla.potserObertes > 0 {
                Label(Self.textPotserObertes(pla.potserObertes), systemImage: "link")
            }
            if let motiu = pla.motiuEspera {
                Label(motiu, systemImage: "clock")
            }
            if case let .failure(error)? = p.fitxer {
                Label(t("No es pot generar el fitxer per a Warp: \(error.description)"), systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            if let fase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text(fase))
                }
            }
        }
        if !pla.aObrir.isEmpty {
            Section(t("S'obriran (\(pla.aObrir.count))")) {
                ForEach(pla.aObrir, id: \.pestanya.id) { p in
                    fila(p.pestanya, p.conversa.descripcio)
                }
            }
        }
        if !pla.avisos.isEmpty {
            Section(t("Avisos")) {
                ForEach(Array(pla.avisos.enumerated()), id: \.offset) { _, avis in
                    Label(avis.description, systemImage: avis.esInfo ? "info.circle" : "exclamationmark.triangle")
                        .textSelection(.enabled)
                }
            }
        }
        if !pla.obertes.isEmpty {
            Section(t("Ja obertes (\(pla.obertes.count)): no s'obriran")) {
                ForEach(pla.obertes, id: \.pestanya.id) { o in
                    fila(o.pestanya, o.on.description)
                }
            }
        }
        if !pla.excloses.isEmpty {
            Section(t("No es poden obrir (\(pla.excloses.count))")) {
                ForEach(pla.excloses, id: \.pestanya.id) { e in
                    fila(e.pestanya, e.motiu.description, avis: true)
                }
            }
        }
        if case let .success(fitxer)? = p.fitxer {
            Section {
                DisclosureGroup(t("Detalls")) {
                    // Un nom propi: no es tradueix.
                    LabeledContent {
                        Text(p.versioWarp ?? t("versió desconeguda"))
                    } label: {
                        Text(verbatim: "Warp")
                    }
                    LabeledContent(t("Fitxer temporal"), value: fitxer.nomFitxer)
                    Text(fitxer.text)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text(t("""
                    L'app escriu aquest fitxer a la carpeta de launch configurations de Warp, li demana que l'obri, i l'esborra \
                    en quant veu que Warp l'ha obert (o als 30 s).
                    """))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Les pestanyes sense lligam que potser ja són obertes, als dos fulls.
    private static func textPotserObertes(_ n: Int) -> String {
        t("\(n) pestanyes sense lligam potser ja són obertes a Warp: si ho són, cancel·la i fes Arxiu › Lliga amb Warp… abans d'obrir.")
    }

    private func fila(_ pestanya: Pestanya, _ detall: String, avis: Bool = false) -> some View {
        LabeledContent {
            Text(detall)
                .multilineTextAlignment(.trailing)
        } label: {
            if avis {
                Label(pestanya.titol, systemImage: "exclamationmark.triangle")
            } else {
                Text(pestanya.titol)
            }
            Text(Rutes.abreujada(pestanya.carpeta, inici: inici))
        }
    }

    private func text(_ fase: Obertura.Fase) -> String {
        switch fase {
        case .comprovant: t("Comprovant que Warp no ha canviat…")
        case .engegant: t("Obrint Warp…")
        case .obrint: t("Obrint a Warp…")
        case .esperant: t("Esperant la finestra nova (fins a 30 s)…")
        case .esperantClaude: t("Esperant que arrenqui Claude a cada pestanya (fins a 30 s)…")
        }
    }

    // MARK: - Botons

    @ViewBuilder
    private var botons: some View {
        switch obertura.estat {
        case let .confirmant(proposta) where !proposta.pla.aObrir.isEmpty:
            Button(t("Cancel·la"), role: .cancel) { obertura.cancela() }
                .keyboardShortcut(.cancelAction)
            // Sense drecera i sense ser el botó per defecte: Retorn no obre res.
            Button(t("Obre \(proposta.pla.aObrir.count) pestanyes")) {
                Task { await obertura.confirmaIObre() }
            }
            .disabled(proposta.pla.motiuEspera != nil
                || proposta.fitxer.map { if case .success = $0 { false } else { true } } ?? true)
            .help(proposta.warpTancat ? t("Obre Warp, escriu el fitxer temporal i li demana que obri la finestra")
                                      : t("Escriu el fitxer temporal i demana a Warp que obri la finestra"))
        case let .confirmantTot(proposta) where proposta.finestres.contains(where: Obertura.PropostaTot.esPotObrir):
            let finestres = proposta.aObrir
            Button(t("Cancel·la"), role: .cancel) { obertura.cancela() }
                .keyboardShortcut(.cancelAction)
            // Sense drecera i sense ser el botó per defecte: Retorn no obre res.
            Button(t("Obre \(finestres.count) finestres")) {
                Task { await obertura.confirmaIObreTot() }
            }
            .disabled(finestres.isEmpty)
            .help(t("Escriu un fitxer temporal per finestra i demana a Warp que les obri totes alhora"))
        case .obrint, .obrintTot:
            Button(t("Cancel·la"), role: .cancel) {}
                .disabled(true)
        case .preparant, .preparantTot:
            Button(t("Cancel·la"), role: .cancel) { obertura.cancela() }
                .keyboardShortcut(.cancelAction)
        default:
            Button(t("D'acord")) { obertura.cancela() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Després d'obrir: què ha passat, a dalt de la llista, fins que es tanca.
struct BanerObertura: View {
    let resultat: Obertura.Resultat
    let descarta: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(resultat.text, systemImage: resultat.correcte ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .textSelection(.enabled)
            Spacer()
            Button(t("D'acord"), action: descarta)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(resultat.correcte ? Color.green.opacity(0.10) : Color.orange.opacity(0.12))
    }
}
