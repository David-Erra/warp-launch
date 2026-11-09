import AppKit
import SwiftUI
import WarpLaunchCore
import WarpLaunchObridor
import WarpLaunchUI

/// App de barra de menú (docs/disseny.md): l'editor, el menú de la icona i la Configuració. Llegeix Warp (en segon pla)
/// i la configuració, i només escriu de Warp l'ajust de la restauració (D19), i només amb el consentiment de l'usuari
/// (D-P4): fins llavors, totes les finestres mostren la pantalla de consentiment. **Només obre res de Warp des del full de
/// confirmació** (fase 3.1, `Obertura`): una finestra cada vegada, amb Warp ja obert.
@main
struct WarpLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegat

    var body: some Scene {
        let aplicacio = delegat.aplicacio

        Window(WarpLaunch.nom, id: Aplicacio.idEditor) {
            // D-P4: fins que no s'accepta, la pantalla de consentiment.
            PortaConsentiment(consentiment: aplicacio.consentiment, carpetaDeProva: aplicacio.carpetaDeProva,
                              surt: { NSApp.terminate(nil) }) {
                VistaEditor(editor: aplicacio.editor, warp: aplicacio.warp, inici: aplicacio.inici,
                            carpetaDeProva: aplicacio.carpetaDeProva)
            }
            .background(AccesFinestra { aplicacio.activacio.adopta($0) })
        }
        .defaultSize(width: 900, height: 560)
        .restorationBehavior(.disabled)
        .commands {
            OrdresEditor()
            SidebarCommands()
        }

        Settings {
            PortaConsentiment(consentiment: aplicacio.consentiment, carpetaDeProva: aplicacio.carpetaDeProva,
                              surt: { NSApp.terminate(nil) }) {
                VistaConfiguracio(editor: aplicacio.editor, carpeta: aplicacio.carpetaDescrita,
                                  deProva: aplicacio.arguments.deProva, arrencada: aplicacio.arrencada,
                                  diagnostic: aplicacio.copiaDiagnostic, desinstallacio: aplicacio.desinstallacio)
            }
            .background(AccesFinestra { aplicacio.activacio.adoptaConfiguracio($0) })
        }
        // La mida de la pestanya que es veu: tan alta com el contingut, fins a 640 pt (`VistaConfiguracio.formulari`).
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuIcona(aplicacio: aplicacio)
        } label: {
            Label(WarpLaunch.nom, systemImage: "macwindow.on.rectangle")
        }
    }
}

/// Tot el que viu tant com l'app.
@MainActor
final class Aplicacio {
    static let idEditor = "editor"

    let inici: String
    let arguments: ArgumentsApp
    let editor: Editor
    let warp: EstatWarp
    /// D-P4: el permís per gestionar la restauració de Warp (`preferencies.json`). Fins que no s'accepta, l'app no toca Warp.
    let consentiment: ConsentimentRestauracio
    /// La restauració de sessió de Warp, sempre desactivada, i la foto de les finestres (D19). `nil` amb una carpeta de prova
    /// o sense el consentiment: només el crea `ConsentimentRestauracio`, i l'app no en guarda cap altre.
    var refresc: RefrescWarp? { consentiment.refresc }
    /// Els lligams de cada pestanya (`estat.json`, a la mateixa carpeta que la configuració).
    let sessions: EstatSessions
    /// Obrir una finestra a Warp (fase 3.1). `nil` sense carpeta.
    let obertura: Obertura?
    let activacio: Activacio
    /// «Obre Warp Launch en iniciar sessió» (D3): l'interruptor de la Configuració.
    let arrencada: ArrencadaSessio
    /// Pla A4: «Copia el diagnòstic», a la Configuració, amb el mateix Warp i Claude que llegeix l'app. Només llegeix.
    let copiaDiagnostic: CopiaDiagnostic
    /// Decisió 3 (0.31.0): «Deixa de fer servir Warp Launch», a la Configuració. Només es pot amb la configuració de debò i el
    /// permís (sense el refresc, el botó és desactivat).
    let desinstallacio: Desinstallacio
    /// Aquesta arrencada és la de l'inici de sessió (es decideix a `applicationDidFinishLaunching`).
    var enIniciarSessio = false
    /// Cada quant es torna a llegir Warp mentre l'app és en marxa (D18).
    static let lecturaPeriodica: Duration = .seconds(60)

    init() {
        inici = FileManager.default.homeDirectoryForCurrentUser.path
        arguments = ArgumentsApp(CommandLine.arguments, inici: inici)
        let editor: Editor, sessions: EstatSessions, preferencies: MagatzemPreferencies?, carpeta: URL?
        switch arguments.carpeta {
        case let .real(c), let .prova(c):
            carpeta = c
            editor = Editor(magatzem: MagatzemConfiguracio(carpeta: c, inici: inici))
            sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: c))
            preferencies = MagatzemPreferencies(carpeta: c)
        case let .incorrecta(motiu):
            carpeta = nil
            editor = Editor(senseCarpeta: motiu)
            sessions = EstatSessions(magatzem: nil)
            preferencies = nil
        }
        self.editor = editor
        self.sessions = sessions
        let processos = ProcessosDelSistema()
        // Warp i Claude de debò (només lectura): el lector no té res per defecte.
        let lector = Lector(rutaWarp: LectorWarp.rutaPerDefecte, rutaAjustos: LectorAjustosWarp.rutaPerDefecte,
                            carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,
                            inici: inici)
        // Les transcripcions i la confiança de Claude de debò (només lectura): els lectors no tenen cap ruta per defecte.
        let transcripcions = LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte)
        let confianca = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte)
        let entornDiagnostic = EntornDiagnostic(lector: lector, carpetaConfiguracio: carpeta,
                                                configuracioDeProva: arguments.deProva,
                                                transcripcions: transcripcions, confianca: confianca)
        copiaDiagnostic = CopiaDiagnostic(diagnostic: { Diagnostic.executa(entornDiagnostic, anonimitza: $0) })
        // D19: només amb la configuració de debò. Una carpeta de prova no toca res de Warp. L'única connexió amb l'ajust de debò.
        // D-P4: `ConsentimentRestauracio` només crida `creaEntornRefresc` (i només llavors es crea l'ajust) amb el
        // consentiment acceptat.
        var creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?
        if case .real = arguments.carpeta, let preferencies {
            creaEntornRefresc = {
                // Sense `settings.toml`, només el crea amb Warp obert i amb algun terminal (ronda 5).
                let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, potCrearElFitxer: { lector.warpHaAcabatDArrencar() })
                return RefrescWarp.Entorn(ajust: { try ajust.valor() },
                                          // El primer canvi de l'app desa a `preferencies.json` el valor que hi havia.
                                          posa: { nou in
                                              try preferencies.posaRestauracio(nou, valor: { try ajust.valor() },
                                                                               posa: { try ajust.posa($0) })
                                          },
                                          warpObert: { lector.warpObert() },
                                          llegeixBase: { try lector.llegeixDeLApp(base: .sempre) })
            }
        }
        let consentiment = ConsentimentRestauracio(magatzem: preferencies, creaEntornRefresc: creaEntornRefresc)
        self.consentiment = consentiment
        // Amb l'ajust gestionat per l'app (la configuració de debò), la base només és la foto: les lectures de cada minut, i
        // obrir, van pels processos, també durant un refresc o si l'ajust ha quedat activat. Sense el consentiment, l'app no
        // llegeix Warp.
        let base: BaseWarp = creaEntornRefresc == nil ? .segonsAjust : .mai
        // Sense cap Warp ni la seva base, també amb una carpeta de prova: que no hi ha Warp, com amb la de debò.
        let warp = EstatWarp(lector: { try lector.llegeixDeLApp(base: base) })
        self.warp = warp
        if case .incorrecta = arguments.carpeta {
            obertura = nil
        } else {
            // L'única connexió amb l'obridor (`ObreWarp`) i amb la carpeta de Warp de debò.
            obertura = Obertura(editor: editor, sessions: sessions, consentiment: consentiment, entorn: Obertura.Entorn(
                llegeix: { await warp.llegeix() },
                obre: { try await ObreWarp.obre($0, warp: lector.installacio()) },
                // Amb l'ajust activat, Warp restauraria les seves finestres en arrencar.
                engegaWarp: { await consentiment.refresc?.tancaEsperant(); try await ObreWarp.engega(warp: lector.installacio()) },
                fitxers: FitxersLaunchWarp.real,
                transcripcions: transcripcions,
                confianca: confianca,
                versioWarp: { lector.installacio().app.versio },
                inici: inici))
        }
        editor.obertura = obertura
        editor.lligam = obertura == nil ? nil
            : Lligam(editor: editor, sessions: sessions, inici: inici, llegeix: { await warp.llegeixAmbFinestres() },
                     ambRefresc: { warp.refresc != nil })
        // Els ítems d'inici de macOS, només amb la configuració de debò: una de prova no s'obre mai sola.
        let arrencada: ArrencadaSessio
        if case .real = arguments.carpeta {
            arrencada = ArrencadaSessio(entorn: ServeiArrencada.entorn, motiuNoDisponible: ServeiArrencada.motiuNoDisponible)
        } else {
            arrencada = ArrencadaSessio(entorn: nil, motiuNoDisponible: "Amb una configuració de prova, l'app no s'obre sola.")
        }
        self.arrencada = arrencada
        let desinstallacio = Desinstallacio(consentiment: consentiment, arrencada: arrencada, surt: { NSApp.terminate(nil) })
        self.desinstallacio = desinstallacio
        editor.conversaDe = { sessions.conversaAReprendre($0, transcripcions: transcripcions) }
        editor.enImportar = { sessions.vincula($0.vincles) }
        editor.avisCarpetaDeClaude = { sessions.avisCarpeta($0, inici: $1, carpetaExisteix: $2) }
        sessions.enCanviar = { editor.refrescaAvisos() }
        // Sense configuració, `estat.json` no s'escriu.
        warp.enLlegir = { [obertura] lectura in
            if editor.estat == .oberta { sessions.actualitza(amb: lectura, configuracio: editor.configuracio) }
            obertura?.enLlegir(lectura)
        }
        activacio = Activacio(enAdoptarDesfer: { editor.usaUndoManager($0) },
                              enAdoptarDesferConfiguracio: { editor.usaDesferPlantilla($0) },
                              // El fitxer pot haver canviat fora mentre la Configuració era amagada.
                              enMostrarConfiguracio: {
                                  editor.comprovaCanviExtern()
                                  // Es pot haver canviat a Configuració del Sistema.
                                  arrencada.actualitza()
                                  desinstallacio.actualitza()
                              },
                              enTancarConfiguracio: {
                                  // D-P4: tancar la pantalla de consentiment és no acceptar-lo, com tancar l'editor.
                                  guard consentiment.continuaEnTancarFinestra(surt: { NSApp.terminate(nil) }) else { return }
                                  editor.desaSiCal()
                              },
                              enAmagar: {
                                  // D-P4: tancar la pantalla de consentiment és no acceptar-lo. No hi ha res per desar.
                                  guard consentiment.continuaEnTancarFinestra(surt: { NSApp.terminate(nil) }) else { return }
                                  // Un nom a mig escriure es desa: amb l'editor amagat, el camp no es veuria.
                                  editor.acabaNom(desant: true)
                                  // Un camp de l'inspector pot tenir el cursor: el que s'hi escrigui després és un
                                  // altre pas de Desfés.
                                  editor.acabaAgrupacio()
                                  editor.desaSiCal()
                              },
                              enMostrar: { editor.enMostrar() })
        editor.carrega()
        sessions.carrega()
        // Ara mateix si ja s'havia acceptat (o no cal); si no, en acceptar.
        consentiment.enContinuar { [obertura] in
            warp.refresc = consentiment.refresc
            // Els fitxers temporals que hagin quedat d'una obertura a mig fer (només els propis, amb la marca).
            obertura?.netejaEnArrencar()
        }
    }

    /// Llegeix Warp en arrencar i, després, cada minut (D18). No obre ni toca res de Warp ni de Claude, llevat de tornar a
    /// desactivar l'ajust de la restauració si és activat (D19).
    func llegeixPeriodicament() async {
        while !Task.isCancelled {
            refresc?.vigila()
            await warp.llegeix()
            try? await Task.sleep(for: Self.lecturaPeriodica)
        }
    }

    /// Per a l'editor: la carpeta, si és de prova.
    var carpetaDeProva: String? {
        if case let .prova(carpeta) = arguments.carpeta { Rutes.abreujada(carpeta.path, inici: inici) } else { nil }
    }

    /// Per a la Configuració: la carpeta, o per què no n'hi ha cap.
    var carpetaDescrita: String {
        switch arguments.carpeta {
        case let .real(carpeta), let .prova(carpeta): Rutes.abreujada(carpeta.path, inici: inici)
        case let .incorrecta(motiu): "Cap: \(motiu)"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let aplicacio = Aplicacio()

    func applicationWillFinishLaunching(_ notification: Notification) {
        aplicacio.activacio.enArrencar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Aquí, i no a WillFinish: l'esdeveniment d'obertura (kAEOpenApplication) només és viu mentre AppKit el despatxa, i
        // aquesta crida en surt. El temps compta també les estones en repòs (`CLOCK_MONOTONIC`, no `systemUptime`).
        aplicacio.enIniciarSessio = InicDeSessio.es(
            comElementDInici: ServeiArrencada.obertaComElementDInici,
            segonsEncesa: TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000,
            registrada: aplicacio.arrencada.obreSola)
        let aplicacio = aplicacio
        // D-P4: sense el consentiment, primer la pantalla de consentiment (també en iniciar sessió). L'app no llegeix ni toca
        // Warp, ni proposa res, fins que s'accepta.
        let ambConsentiment = aplicacio.consentiment.potContinuar
        if aplicacio.enIniciarSessio, !ambConsentiment { aplicacio.activacio.mostraEditor(obre: {}) }
        aplicacio.consentiment.enContinuar {
            Task { await aplicacio.llegeixPeriodicament() }
            // D3: el full de «Obre-ho tot», quan Warp és a punt. Si no falta cap finestra, l'editor s'amaga; però no just
            // després d'haver acceptat el consentiment.
            guard aplicacio.enIniciarSessio, let obertura = aplicacio.obertura else { return }
            Task {
                switch await obertura.enIniciarSessio() {
                case .mostra: aplicacio.activacio.mostraEditor(obre: {})
                case .amaga: if ambConsentiment { aplicacio.activacio.amagaEditorSiNoSHaFetServir() }
                case .res: break
                }
            }
        }
    }

    /// Tancar l'editor no tanca l'app: la icona de la barra de menú continua.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Obrir l'app des d'Aplicacions o del Finder quan ja és oberta mostra l'editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        aplicacio.activacio.mostraEditor(obre: {})
        return false
    }

    /// Desa abans de sortir. Si no es pot, és l'únic cas en què es demana confirmació. A mig obrir una finestra a Warp,
    /// esborra el fitxer temporal abans de sortir (`Obertura.enSortir`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        aplicacio.editor.acabaNom(desant: true)
        // Sempre, també si després es cancel·la. Durant l'alerta, cap refresc: l'app podria sortir amb l'ajust activat.
        aplicacio.refresc?.atura()
        if aplicacio.editor.desaSiCal() {
            aplicacio.obertura?.enSortir()
            return surtAmbLAjustDesactivat()
        }
        aplicacio.activacio.posaAlDavant()
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        alerta.messageText = "No s'han pogut desar els canvis"
        alerta.informativeText = "\(aplicacio.editor.errorDesat?.description ?? ""). Si surts ara, es perdran."
        alerta.addButton(withTitle: "Cancel·la")
        let surt = alerta.addButton(withTitle: "Surt sense desar")
        surt.hasDestructiveAction = true
        guard alerta.runModal() == .alertSecondButtonReturn else {
            aplicacio.refresc?.repren()
            return .terminateCancel
        }
        aplicacio.obertura?.enSortir()
        return surtAmbLAjustDesactivat()
    }

    /// Si `settings.toml` acabava de canviar quan `atura` ha volgut desactivar l'ajust (`RefrescWarp.Pendent.acabaDeCanviar`),
    /// l'app no surt fins que l'ha pogut desactivar, com a molt uns segons (`RefrescWarp.acabaDeDesactivar`): si sortís, la
    /// restauració de Warp podria quedar activada, i ningú no la tornaria a desactivar.
    private func surtAmbLAjustDesactivat() -> NSApplication.TerminateReply {
        guard let refresc = aplicacio.refresc, refresc.pendent == .acabaDeCanviar else { return .terminateNow }
        Task { @MainActor in
            await refresc.acabaDeDesactivar()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Menú de la icona de la barra de menú (docs/disseny.md, «Menú de la icona»).
private struct MenuIcona: View {
    let aplicacio: Aplicacio
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    // Cada bloc en una `Section` sense títol, sense `Divider` solts: una `Section` amb títol seguida d'un `Divider` feia
    // dos separadors seguits (revisió del pas 11).
    var body: some View {
        if aplicacio.consentiment.potContinuar {
            menu
        } else {
            // D-P4: fins que no s'accepta, només la pantalla de consentiment i sortir.
            Section {
                Button("Mostra Warp Launch") { mostraEditor() }
            }
            Section {
                Button("Surt de \(WarpLaunch.nom)") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        let editor = aplicacio.editor

        Section {
            Button("Mostra l'editor") { mostraEditor() }
        }

        if editor.estat == .oberta, !editor.configuracio.finestres.isEmpty {
            Section("Finestres") {
                // El full de confirmació surt a l'editor: no obre res fins que s'hi confirma.
                Button("Obre-ho tot a Warp…") {
                    mostraEditor()
                    editor.demanaObreTot()
                }
                .disabled(!editor.potObrirTot)
                ForEach(editor.configuracio.finestres) { finestra in
                    Menu("\(finestra.nom) — \(finestra.resum)") {
                        Button("Mostra a l'editor") {
                            editor.lateral = .finestra(finestra.id)
                            mostraEditor()
                        }
                        // El full de confirmació surt a l'editor: no obre res fins que s'hi confirma.
                        Button("Obre a Warp…") {
                            editor.lateral = .finestra(finestra.id)
                            mostraEditor()
                            editor.demanaObertura(finestra.id)
                        }
                        .disabled(!editor.potObrir(finestra.id))
                    }
                }
            }
        }

        Section {
            Text(aplicacio.warp.descripcio)
            Button("Torna a llegir Warp") { Task { await aplicacio.warp.llegeixAmbFinestres() } }
            if let avis = aplicacio.warp.avisFoto {
                Label(avis, systemImage: "exclamationmark.triangle")
            }
            if let avis = aplicacio.refresc?.avis {
                Label(avis, systemImage: "exclamationmark.triangle")
            }
            // No és cap error, i no porta el triangle: Warp encara no té `settings.toml`, i l'app el crearà quan Warp sigui obert
            // (ronda 5), o Warp no s'ha obert mai en aquest usuari i no té res per restaurar (decisió 5).
            if let nota = aplicacio.refresc?.nota {
                Label(nota, systemImage: "info.circle")
            }
        }

        let avisos = editor.avisosMenu
        if !avisos.isEmpty || aplicacio.arguments.carpeta != .real(Rutes.carpetaConfiguracio(inici: aplicacio.inici)) {
            Section {
                // Un clic obre l'editor, que diu què passa i com arreglar-ho.
                ForEach(avisos, id: \.self) { avis in
                    Button { mostraEditor() } label: {
                        Label(avis.text, systemImage: "exclamationmark.triangle")
                    }
                }
                switch aplicacio.arguments.carpeta {
                case .real:
                    EmptyView()
                case let .prova(carpeta):
                    Label("Configuració de prova: \(carpeta.path)", systemImage: "testtube.2")
                case let .incorrecta(motiu):
                    Label("Sense configuració: \(motiu)", systemImage: "exclamationmark.triangle")
                }
            }
        }

        Section {
            Button("Configuració…") {
                aplicacio.activacio.posaAlDavant()
                openSettings()
            }
            .keyboardShortcut(",")
            Button("Quant a \(WarpLaunch.nom)") {
                aplicacio.activacio.posaAlDavant()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Button("Surt de \(WarpLaunch.nom)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func mostraEditor() {
        aplicacio.activacio.mostraEditor { openWindow(id: Aplicacio.idEditor) }
    }
}
