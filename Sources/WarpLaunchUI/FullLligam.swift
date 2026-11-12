import SwiftUI
import WarpLaunchCore

/// El full de «Lliga amb Warp…»: quina pestanya de Warp correspon a cada pestanya de la configuració, amb xifres, i les
/// que s'han de comprovar (no coincideixen el títol i la carpeta), que es poden desmarcar. Només desa amb «Lliga».
struct FullLligam: View {
    let lligam: Lligam
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
    }

    // MARK: - Contingut

    @ViewBuilder
    private var contingut: some View {
        switch lligam.estat {
        case .cap:
            EmptyView()
        case .llegint:
            Section(t("Lliga amb Warp")) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("Llegint Warp i les sessions de Claude…"))
                }
            }
        case let .error(motiu):
            Section(t("No es pot lligar amb Warp")) {
                Label(motiu, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
                Text(t("No s'ha desat res."))
                    .foregroundStyle(.secondary)
            }
        case let .fet(n, error):
            Section(t("Lliga amb Warp")) {
                if let error {
                    // L'error ja diu «no s'ha pogut desar «estat.json»: …».
                    Label(error.prefix(1).uppercased() + error.dropFirst(), systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .textSelection(.enabled)
                } else {
                    Label(t("S'han lligat \(n) pestanyes amb Warp."), systemImage: "checkmark.circle")
                    Text(t("«Obre a Warp…» ja no tornarà a obrir les que són obertes, i l'app en recordarà la conversa de Claude."))
                        .foregroundStyle(.secondary)
                }
            }
        case let .llest(proposta):
            seccions(proposta)
        }
    }

    @ViewBuilder
    private func seccions(_ p: LligamWarp.Proposta) -> some View {
        let perComprovar = p.parelles.filter { !$0.criteri.segur }
        let segures = p.parelles.filter(\.criteri.segur)
        Section(t("Lliga amb Warp")) {
            Text(t("""
                Per a cada pestanya de la configuració, la pestanya de Warp on ja és oberta. Les lligades no es tornaran a \
                obrir mentre siguin obertes, i l'app en recordarà la conversa de Claude. No canvia la configuració, ni obre o \
                tanca res de Warp.
                """))
                .foregroundStyle(.secondary)
            if let avis = lligam.avisLectura {
                Label(avis, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            if p.parelles.isEmpty {
                Label(p.senseParella.isEmpty ? t("Totes les pestanyes ja estan lligades amb Warp")
                                             : t("Cap pestanya sense lligam no té parella a Warp"),
                      systemImage: p.senseParella.isEmpty ? "checkmark.circle" : "info.circle")
            }
            ForEach(xifres(p), id: \.self) { Text($0) }
        }
        if !p.parelles.isEmpty {
            Section(t("Per finestra")) {
                ForEach(p.finestres) { f in
                    LabeledContent(f.nom) {
                        Text(Self.lligades(f.lligades(excepte: lligam.desmarcades), de: f.pestanyes, warp: f.numerosWarp))
                    }
                }
            }
        }
        if !perComprovar.isEmpty {
            Section {
                ForEach(perComprovar) { parella in
                    Toggle(isOn: Binding(get: { !lligam.desmarcades.contains(parella.id) },
                                         set: { marcada in
                                             if marcada { lligam.desmarcades.remove(parella.id) }
                                             else { lligam.desmarcades.insert(parella.id) }
                                         })) {
                        Text(t("\(parella.finestra) › \(parella.pestanya.titol)"))
                        Text(detall(parella))
                    }
                }
            } header: {
                Text(t("Comprova-les (\(perComprovar.count))"))
            } footer: {
                Text(t("Desmarca les que no siguin la mateixa pestanya: quedaran sense lligar, i s'obriran si n'obres la finestra."))
                    .foregroundStyle(.secondary)
            }
        }
        if !p.senseParella.isEmpty {
            Section(t("Sense parella (\(p.senseParella.count)): s'obriran si n'obres la finestra")) {
                ForEach(p.senseParella) { s in
                    LabeledContent(t("\(s.finestra) › \(s.pestanya.titol)"),
                                   value: Rutes.abreujada(s.pestanya.carpeta, inici: inici))
                }
            }
        }
        if !segures.isEmpty {
            Section {
                DisclosureGroup(t("Les altres (\(segures.count))")) {
                    ForEach(segures) { parella in
                        LabeledContent(t("\(parella.finestra) › \(parella.pestanya.titol)"), value: detall(parella))
                    }
                }
            }
        }
    }

    /// Les xifres, una per línia.
    private func xifres(_ p: LligamWarp.Proposta) -> [String] {
        guard !p.parelles.isEmpty || !p.senseParella.isEmpty else {
            return p.jaLligades > 0 ? [t("Ja lligades: \(p.jaLligades)")] : []
        }
        let pendents = p.parelles.count + p.senseParella.count
        var linies = [p.senseParella.isEmpty
            ? t("\(pendents) pestanyes sense lligam: \(p.parelles.count) amb parella a Warp")
            : t("\(pendents) pestanyes sense lligam: \(p.parelles.count) amb parella a Warp, \(p.senseParella.count) sense")]
        let criteris: [(LligamWarp.Criteri, (Int) -> String)] = [
            (.conversa, { t("\($0) per la conversa de Claude") }), (.titolICarpeta, { t("\($0) pel títol i la carpeta") }),
            (.titol, { t("\($0) només pel títol") }), (.carpeta, { t("\($0) només per la carpeta") }),
        ]
        let parts = criteris.compactMap { criteri, text in p.compta(criteri) > 0 ? text(p.compta(criteri)) : nil }
        if !parts.isEmpty { linies.append(parts.joined(separator: " · ")) }
        let ambClaude = p.parelles.filter { $0.claude != nil && !lligam.desmarcades.contains($0.id) }.count
        if ambClaude > 0 {
            linies.append(t("\(ambClaude) amb Claude obert: se'n recordarà la conversa"))
        }
        if p.jaLligades > 0 { linies.append(t("Ja lligades: \(p.jaLligades) (no canvien)")) }
        if p.sobrants > 0 {
            linies.append(t("\(p.sobrants) pestanyes de Warp no són de cap pestanya de la configuració"))
        }
        return linies
    }

    /// «2 de 3 · finestra 4 de Warp», «2 de 3 · finestres 1, 2 i 4 de Warp» o, sense cap finestra de Warp, «2 de 3». Els
    /// números de les finestres, com a text, i la conjunció, la de la llengua (`Idioma.llista`).
    private static func lligades(_ lligades: Int, de pestanyes: Int, warp numeros: [Int]) -> String {
        guard let darrer = numeros.last else { return t("\(lligades) de \(pestanyes)") }
        if numeros.count == 1 { return t("\(lligades) de \(pestanyes) · finestra \(String(darrer)) de Warp") }
        return t("\(lligades) de \(pestanyes) · finestres \(Idioma.llista(numeros.map(String.init))) de Warp")
    }

    private func detall(_ parella: LligamWarp.Parella) -> String {
        let carpeta = Rutes.abreujada(parella.carpetaWarp, inici: inici)
        return switch parella.criteri {
        case .conversa: t("\(parella.lloc): hi corre la seva conversa de Claude")
        case .titolICarpeta: parella.lloc
        case .titol: t("\(parella.lloc), a \(carpeta): el títol coincideix, la carpeta no")
        case .carpeta: t("\(parella.lloc), a \(carpeta): la carpeta coincideix, el títol no")
        }
    }

    // MARK: - Botons

    @ViewBuilder
    private var botons: some View {
        switch lligam.estat {
        case let .llest(proposta) where !proposta.parelles.isEmpty:
            let n = proposta.parelles.filter { !lligam.desmarcades.contains($0.id) }.count
            Button(t("Cancel·la"), role: .cancel) { lligam.cancela() }
                .keyboardShortcut(.cancelAction)
            // Lligar no obre res: només desa a `estat.json`. Retorn hi va bé.
            Button(t("Lliga \(n) pestanyes")) { lligam.confirma() }
                .keyboardShortcut(.defaultAction)
                .disabled(n == 0)
                .help(t("Desa els lligams a «estat.json». No canvia la configuració ni toca Warp"))
        case .llegint:
            Button(t("Cancel·la"), role: .cancel) { lligam.cancela() }
                .keyboardShortcut(.cancelAction)
        default:
            Button(t("D'acord")) { lligam.cancela() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
