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
/// canvia, i dos botons. «Surt de Warp Launch» no desa res, i la propera vegada es torna a preguntar. Retorn prem
/// «Accepta», que és el botó per defecte (decisió d'en David del 07/11/2026). Escapada no fa res (vegeu `botons`).
///
/// Després de «Deixa de fer servir Warp Launch» (0.31.0), l'app surt; si la sortida es cancel·la, aquesta pantalla diu que
/// ja no toca Warp, i només deixa sortir (`retirat`).
struct VistaConsentiment: View {
    let consentiment: ConsentimentRestauracio
    let carpetaDeProva: String?
    let surt: () -> Void

    var body: some View {
        if consentiment.estat == .retirat {
            retirat
        } else {
            permis
        }
    }

    private var retirat: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Has deixat de fer servir Warp Launch")
                    .font(.title2.bold())
            }
            Text(consentiment.textSortir)
            HStack {
                Spacer()
                Button("Surt de Warp Launch", action: surt)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 560)
    }

    private var permis: some View {
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
                        A Warp, l'ajust «Restore windows, tabs, and panes on startup» queda desactivat (Warp Launch el desa \
                        al fitxer d'ajustos de Warp, encara que no l'hagis canviat mai). Si tens Settings Sync, també als \
                        teus altres Macs.
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

            // Amb un `preferencies.json` que no es pot llegir, l'error i on és el fitxer: la propera vegada no es pregunta.
            if case .error = consentiment.estat {
                Label(consentiment.textSortir, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
            } else {
                Text(consentiment.textSortir)
                    .foregroundStyle(.secondary)
            }

            if let carpetaDeProva {
                Label("Configuració de prova (\(carpetaDeProva)): l'app no tocarà aquest ajust.", systemImage: "testtube.2")
                    .foregroundStyle(.secondary)
            }
            if let error = consentiment.errorDesat {
                Label("No s'ha pogut desar el permís: \(error).", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
            }

            botons
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 560)
    }

    /// «Accepta» és el botó per defecte: Retorn el prem, si es pot acceptar (amb un `preferencies.json` que no es pot
    /// llegir, no). «Surt de Warp Launch» no respon a Escapada, i cap botó no ho fa: a macOS, Escapada és «Cancel·la»,
    /// que torna on eres sense fer res (`NSAlert` només la dona a un botó «Cancel·la»), i aquí no hi ha on tornar: el botó
    /// tanca l'app sencera, i una Escapada per costum la tancaria. Per sortir hi ha les maneres de sempre: ⌘Q i tancar la
    /// finestra.
    private var botons: some View {
        HStack {
            Spacer()
            Button("Surt de Warp Launch", action: surt)
            Button("Accepta") { consentiment.accepta() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!consentiment.potAcceptar)
        }
    }

    private func apartat(_ titol: String, @ViewBuilder _ cos: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titol).font(.headline)
            cos()
        }
    }
}
