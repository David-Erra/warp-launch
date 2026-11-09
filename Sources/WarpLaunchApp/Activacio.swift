import AppKit
import SwiftUI

/// Dock i activació (docs/disseny.md, «Dock i activació»). L'app és `LSUIElement`: només surt al Dock i a ⌘⇥
/// mentre hi ha una finestra a la vista (l'editor, la Configuració o «Sobre l’app»).
@MainActor
final class Activacio {
    private(set) weak var finestraEditor: NSWindow?
    private(set) weak var finestraConfiguracio: NSWindow?
    private let delegat = DelegatEditor()
    private var observadors: [any NSObjectProtocol] = []
    private let enAdoptarDesfer: @MainActor (UndoManager) -> Void
    private let enAdoptarDesferConfiguracio: @MainActor (UndoManager) -> Void

    /// - Parameters:
    ///   - enAdoptarDesfer: rep el Desfés de la finestra de l'editor, que l'editor ha de fer servir.
    ///   - enAmagar: es crida quan es tanca (s'amaga) l'editor: hi desa.
    ///   - enMostrar: es crida cada vegada que l'editor passa al davant: hi mira si el fitxer ha canviat fora i torna a
    ///     mirar les carpetes dels avisos.
    ///   - enAdoptarDesferConfiguracio: rep el Desfés de la finestra de Configuració, que fa servir la plantilla.
    ///   - enMostrarConfiguracio: cada vegada que la Configuració passa al davant.
    ///   - enTancarConfiguracio: quan es tanca la Configuració: hi desa (amb la pantalla del permís, fa sortir de l'app).
    init(enAdoptarDesfer: @escaping @MainActor (UndoManager) -> Void,
         enAdoptarDesferConfiguracio: @escaping @MainActor (UndoManager) -> Void,
         enMostrarConfiguracio: @escaping @MainActor () -> Void,
         enTancarConfiguracio: @escaping @MainActor () -> Void,
         enAmagar: @escaping @MainActor () -> Void,
         enMostrar: @escaping @MainActor () -> Void) {
        self.enAdoptarDesfer = enAdoptarDesfer
        self.enAdoptarDesferConfiguracio = enAdoptarDesferConfiguracio
        delegat.enAmagar = { [weak self] in
            enAmagar()
            self?.actualitzaPolitica()
        }
        let centre = NotificationCenter.default
        observadors.append(centre.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                              queue: .main) { [weak self] nota in
            let id = (nota.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                if let configuracio = self?.finestraConfiguracio, ObjectIdentifier(configuracio) == id {
                    enTancarConfiguracio()
                }
                self?.actualitzaPolitica(excepte: id)
            }
        })
        // Xarxa de seguretat: una finestra amb títol que passa al davant sense haver passat per `posaAlDavant`.
        observadors.append(centre.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                              queue: .main) { [weak self] nota in
            let id = (nota.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                let titulada = NSApp.windows.contains { ObjectIdentifier($0) == id && $0.styleMask.contains(.titled) }
                if titulada, NSApp.activationPolicy() != .regular { self?.posaAlDavant() }
                if let editor = self?.finestraEditor, ObjectIdentifier(editor) == id { enMostrar() }
                // Tant si SwiftUI reaprofita la finestra de Configuració com si en fa una de nova, el Desfés de la
                // plantilla és el de la que es veu.
                if let configuracio = self?.finestraConfiguracio, ObjectIdentifier(configuracio) == id {
                    self?.adoptaDesferConfiguracio(configuracio)
                    enMostrarConfiguracio()
                }
            }
        })
    }

    /// En arrencar, SwiftUI obre l'editor sol (és la primera escena), i `adopta` el rep abans que sigui visible:
    /// l'app ha de ser `.regular` des d'abans que Launch Services l'activi, o es queda sense Dock, sense ⌘⇥ i
    /// sense menú principal (revisió del pas 4). Es crida a `applicationWillFinishLaunching`.
    /// - Parameter silenciosa: l'app es reobre sola després d'actualitzar-se: cap finestra ni Dock.
    func enArrencar(silenciosa: Bool) {
        NSApp.setActivationPolicy(silenciosa ? .accessory : .regular)
    }

    /// La finestra de l'editor (la crea SwiftUI): s'hi posa el delegat que l'amaga en lloc de tancar-la.
    func adopta(_ finestra: NSWindow) {
        if finestra.delegate !== delegat {
            delegat.original = finestra.delegate
            finestra.delegate = delegat
        }
        finestraEditor = finestra
        // El Desfés de l'editor és el de la finestra, i no al revés: quan arriba aquí, AppKit ja n'ha creat un (SwiftUI
        // el demana en preparar la vista) i el torna sense preguntar al delegat. ⌘Z no veia el de l'editor (prova 1).
        if let desfer = finestra.undoManager { enAdoptarDesfer(desfer) }
    }

    /// La finestra de Configuració (la crea SwiftUI): al davant, i el seu Desfés és el de la plantilla.
    func adoptaConfiguracio(_ finestra: NSWindow) {
        posaAlDavant()
        finestraConfiguracio = finestra
        adoptaDesferConfiguracio(finestra)
    }

    private func adoptaDesferConfiguracio(_ finestra: NSWindow) {
        if let desfer = finestra.undoManager { enAdoptarDesferConfiguracio(desfer) }
    }

    /// L'editor, la Configuració, «Sobre l’app» o una finestra de l'actualitzador. Una de minimitzada també compta: continua oberta, i en
    /// reiniciar-se l'app desapareixeria.
    var hiHaFinestraVisible: Bool {
        NSApp.windows.contains { ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled) }
    }

    /// Un full sobre alguna finestra, també si no és dels models de l'app.
    var hiHaFullObert: Bool {
        NSApp.windows.contains { $0.attachedSheet != nil }
    }

    /// Mostra l'editor. `obre` el crea si encara no existeix (`openWindow` de SwiftUI).
    func mostraEditor(obre: () -> Void) {
        posaAlDavant()
        if let finestraEditor {
            adopta(finestraEditor)
            finestraEditor.makeKeyAndOrderFront(nil)
        } else {
            obre()
        }
    }

    /// En iniciar sessió, si no falta cap finestra (D3): l'editor, que SwiftUI obre sol en arrencar, s'amaga com si s'hagués
    /// tancat (desa i surt del Dock). Si mentrestant s'hi ha fet algun canvi, o hi ha un full, es queda.
    func amagaEditorSiNoSHaFetServir() {
        guard let finestraEditor, finestraEditor.isVisible, finestraEditor.attachedSheet == nil,
              finestraEditor.undoManager?.canUndo != true else { return }
        finestraEditor.performClose(nil)
    }

    /// Abans de mostrar una finestra: al Dock, amb el menú principal, i al davant.
    func posaAlDavant() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        // Després d'una reobertura silenciosa l'app és amagada (`NSApp.hide`): si l'activació no la mostrés, la finestra no es veuria.
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
    }

    /// Fora del Dock si no queda cap finestra a la vista.
    func actualitzaPolitica(excepte: ObjectIdentifier? = nil) {
        let visibles = NSApp.windows.contains {
            ObjectIdentifier($0) != excepte && $0.isVisible && $0.styleMask.contains(.titled)
        }
        let politica: NSApplication.ActivationPolicy = visibles ? .regular : .accessory
        if NSApp.activationPolicy() != politica { NSApp.setActivationPolicy(politica) }
    }
}

/// Delegat de la finestra de l'editor. Tancar-la l'amaga (`orderOut`), i tota la resta la reenvia al delegat que
/// hi havia posat SwiftUI. És el patró de BAMA: tancar i tornar a obrir una `Window` de SwiftUI i després canviar
/// l'estat bloquejava AppKit. A la prova 1, 20 cicles d'amagar i tornar a mostrar no s'han bloquejat.
final class DelegatEditor: NSObject, NSWindowDelegate {
    nonisolated(unsafe) weak var original: (any NSWindowDelegate)?
    @MainActor var enAmagar: (@MainActor () -> Void)?

    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        enAmagar?()
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : super.forwardingTarget(for: aSelector)
    }
}

/// Dona la `NSWindow` on és una vista de SwiftUI.
struct AccesFinestra: NSViewRepresentable {
    let enTrobar: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> Vista { Vista(enTrobar: enTrobar) }
    func updateNSView(_ vista: Vista, context: Context) {}

    final class Vista: NSView {
        let enTrobar: @MainActor (NSWindow) -> Void

        init(enTrobar: @escaping @MainActor (NSWindow) -> Void) {
            self.enTrobar = enTrobar
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("no es fa servir") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { enTrobar(window) }
        }
    }
}
