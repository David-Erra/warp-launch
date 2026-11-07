import SwiftUI
import WarpLaunchCore

/// Mostra `contingut` només quan l'app pot continuar (D-P4); si no, la pantalla de consentiment. L'app la posa a l'editor
/// i a la Configuració: fins que no s'accepta, cap finestra de l'app no fa res més.
public struct PortaConsentiment<Contingut: View>: View {
    let consentiment: ConsentimentRestauracio
    let carpetaDeProva: String?
    let surt: () -> Void
    let contingut: () -> Contingut

    /// - Parameter surt: «Surt de Warp Launch». L'app hi fa sortir el procés (aquí no es toca `NSApp`).
    public init(consentiment: ConsentimentRestauracio, carpetaDeProva: String? = nil, surt: @escaping () -> Void,
                @ViewBuilder contingut: @escaping () -> Contingut) {
        self.consentiment = consentiment
        self.carpetaDeProva = carpetaDeProva
        self.surt = surt
        self.contingut = contingut
    }

    public var body: some View {
        if consentiment.potContinuar {
            contingut()
        } else {
            VistaConsentiment(consentiment: consentiment, carpetaDeProva: carpetaDeProva, surt: surt)
        }
    }
}

/// La pantalla de consentiment (D-P4, en David, 07/11/2026): per què l'app ha de desactivar la restauració de Warp, què
/// canvia, i dos botons. «Surt de Warp Launch» no desa res, i la propera vegada es torna a preguntar. Cap dels dos no té
/// drecera: s'ha de triar a consciència.
struct VistaConsentiment: View {
    let consentiment: ConsentimentRestauracio
    let carpetaDeProva: String?
    let surt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warp Launch ha de desactivar un ajust de Warp")
                        .font(.title2.bold())
                    Text("Abans de començar, necessita el teu permís.")
                        .foregroundStyle(.secondary)
                }
            }

            apartat("Per què cal") {
                Text("""
                    Quan Warp arrenca, pot tornar a obrir les pestanyes de l'última vegada, però sense Claude. Warp Launch no \
                    les reconeixeria com a seves i, en obrir les teves finestres, les pestanyes quedarien repetides.
                    """)
            }

            apartat("Què canvia") {
                Label {
                    Text("""
                        A Warp, l'ajust «Restore windows, tabs, and panes on startup» queda desactivat. Si tens Settings \
                        Sync, també als teus altres Macs.
                        """)
                } icon: {
                    Image(systemName: "switch.2")
                }
                Label {
                    Text("""
                        Només quan li demanes que llegeixi les finestres de Warp (per exemple, en importar-les), Warp Launch \
                        l'activa uns segons perquè Warp les desi, i el torna a desactivar.
                        """)
                } icon: {
                    Image(systemName: "clock")
                }
            }

            Text("""
                Sense aquest permís, Warp Launch no es pot fer servir. Si surts, no es desa res, i t'ho tornarà a preguntar \
                la propera vegada.
                """)
                .foregroundStyle(.secondary)

            if let carpetaDeProva {
                Label("Configuració de prova (\(carpetaDeProva)): l'app no tocarà aquest ajust.", systemImage: "testtube.2")
                    .foregroundStyle(.secondary)
            }
            if case let .error(motiu) = consentiment.estat {
                Label("\(motiu). Arregla'l o esborra'l, i torna a obrir Warp Launch.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
            }
            if let error = consentiment.errorDesat {
                Label("No s'ha pogut desar el permís: \(error).", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Surt de Warp Launch", action: surt)
                Button("Accepta") { consentiment.accepta() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!consentiment.potAcceptar)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 560)
    }

    private func apartat(_ titol: String, @ViewBuilder _ cos: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titol).font(.headline)
            cos()
        }
    }
}
