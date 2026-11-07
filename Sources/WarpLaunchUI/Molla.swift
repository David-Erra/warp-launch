import AppKit
import SwiftUI
import WarpLaunchCore

/// Obrir la finestra d'una fila de la barra lateral en aturar-s'hi arrossegant pestanyes, com les carpetes del Finder
/// (docs/disseny.md, «Arrossegar»). La `List` de SwiftUI no ho fa: no fa servir `springLoadingBehavior`, i l'`NSOutlineView`
/// només ho fa per desplegar files (docs/fets-verificats.md). Cada fila avisa amb `onDropSessionUpdated`, i un rellotge
/// mira, quan ha passat el retard, si el cursor encara és a la fila i el botó encara és premut.
///
/// Esc a mig arrossegament (pas 11): SwiftUI no avisa la fila (no hi ha `.exiting`), i el cursor hi continua. La molla
/// no obre mentre la fila ha deixat de ser la destinació d'AppKit després d'haver-ho estat, i s'atura si arriba un Esc a
/// l'app. Si no arriba cap dels dos senyals, fa el mateix que abans. Cada canvi va al registre (`.notice`) per a la
/// prova 8.
@MainActor
final class Molla {
    /// El retard per defecte de macOS (Accessibilitat › Control del punter, «Retard de l'obertura per molla»): 0,5 s. No es
    /// llegeix la preferència: l'app no fa servir les preferències del sistema (prova de guarda).
    static let retard: TimeInterval = 0.5
    /// Cada quant es mira on és el cursor mentre hi ha una fila en compte.
    static let interval: TimeInterval = 0.05

    /// Per què s'atura, per al registre.
    enum Motiu: String {
        case sortida = "el cursor ha sortit de la fila"
        case noEsPotObrir = "és la finestra que es veu"
        case deixades = "s'han deixat anar"
        case acabat = "l'arrossegament s'ha acabat"
        case esc = "Esc"
        case desapareguda = "la barra lateral ja no hi és"
    }

    private var estat = EstatMolla()
    private var rellotge: Timer?
    private var obre: ((Finestra.ID) -> Void)?
    private var vistes: [Finestra.ID: VistaFeble] = [:]
    /// Esc mentre hi ha rellotge (`NSEvent.addLocalMonitorForEvents`).
    private var monitorEsc: Any?
    /// L'últim `dropConfiguration` d'una fila: només per al registre.
    private var ultimBatec: Date?

    /// Per a `onDropSessionUpdated` de la fila d'una finestra. `obre` mostra la finestra; només es fa servir si
    /// `potObrir` (una altra finestra que la que es veu).
    func actualitza(_ sessio: DropSession, fila: Finestra.ID, potObrir: Bool, obre: @escaping (Finestra.ID) -> Void) {
        switch sessio.phase {
        case .entering, .active:
            guard potObrir else {
                surt(fila, .noEsPotObrir)
                return
            }
            // Si no es troba la fila a la pantalla, la mida i la posició de la sessió (coordenades de la fila, y cap avall).
            let ratoli = NSEvent.mouseLocation
            let rect = CGRect(x: ratoli.x - sessio.location.x, y: ratoli.y + sessio.location.y - sessio.size.height,
                              width: sessio.size.width, height: sessio.size.height)
            if estat.fila != fila {
                Registre.arrossegar.notice("molla: compta la fila \(Registre.curt(fila), privacy: .public)")
            }
            estat.entra(fila, ara: .now, rectDeLaSessio: rect)
            self.obre = obre
            programa()
        case .exiting:
            surt(fila, .sortida)
        case .ended, .dataTransferCompleted:
            atura(.acabat)
        @unknown default:
            atura(.acabat)
        }
    }

    /// `dropConfiguration` d'una fila: no decideix res, només es registra quant fa de l'últim quan la molla s'atura.
    func batec(_ fila: Finestra.ID) {
        ultimBatec = .now
    }

    /// Deixa de comptar (s'han deixat anar, la fila ja no hi és, Esc…).
    func atura(_ motiu: Motiu) {
        if rellotge != nil { registraAtura(motiu.rawValue) }
        aturaSenseRegistre()
    }

    /// `.exiting` d'una fila, o una fila que no es pot obrir: s'atura només si era la que es comptava (o no se'n
    /// comptava cap). Es registra abans d'oblidar la fila (la 0.14.0 hi deia «fila cap»).
    private func surt(_ fila: Finestra.ID, _ motiu: Motiu) {
        guard estat.fila == nil || estat.fila == fila else { return }
        atura(motiu)
    }

    private func aturaSenseRegistre() {
        rellotge?.invalidate()
        rellotge = nil
        if let monitorEsc { NSEvent.removeMonitor(monitorEsc) }
        monitorEsc = nil
        obre = nil
        estat.surt()
    }

    private func registraAtura(_ motiu: String) {
        let fila = estat.fila.map(Registre.curt) ?? "cap"
        let batec = ultimBatec.map { String(Int(Date.now.timeIntervalSince($0) * 1000)) } ?? "cap"
        Registre.arrossegar.notice("""
            molla: s'atura (\(motiu, privacy: .public)), fila \(fila, privacy: .public), \
            destinació vista \(self.estat.destiVist), últim batec fa \(batec, privacy: .public) ms
            """)
    }

    /// La vista de la fila, per saber on és a la pantalla (`AncoraFila`). La `List` reaprofita les cel·les: una vista
    /// només és d'una fila, l'última que l'ha registrat.
    func registra(_ vista: NSView, fila: Finestra.ID) {
        vistes = vistes.filter { $0.key != fila && $0.value.vista != nil && $0.value.vista !== vista }
        vistes[fila] = VistaFeble(vista)
    }

    /// Un `Timer`, i no una `Task`: durant un arrossegament el bucle d'execució corre en `.eventTracking`, on una `Task`
    /// del `MainActor` només es desperta si aquest mode és als comuns (docs/fets-verificats.md).
    private func programa() {
        guard rellotge == nil else { return }
        // Esc: es torna tal com és (la sessió d'arrossegar el pot fer servir per cancel·lar). En un arrossegament
        // asíncron potser no arriba a l'app; per això també hi ha el senyal de la fila.
        monitorEsc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.atura(.esc) }
            }
            return event
        }
        let rellotge = Timer(timeInterval: Self.interval, repeats: true) { [weak self] rellotge in
            // Si la barra lateral ja no hi és, el rellotge s'atura sol.
            guard self != nil else { return rellotge.invalidate() }
            MainActor.assumeIsolated { self?.comprova() }
        }
        RunLoop.main.add(rellotge, forMode: .common)
        RunLoop.main.add(rellotge, forMode: .eventTracking)
        self.rellotge = rellotge
    }

    private func comprova() {
        let ratoli = NSEvent.mouseLocation
        let aLaPantalla = estat.fila.flatMap(filaALaPantalla)
        let rect = aLaPantalla?.rect ?? estat.rectDeLaSessio
        // `pressedMouseButtons` és l'estat del ratolí ara mateix (NSEvent.h): si s'ha amollat, l'arrossegament s'acaba.
        let premut = NSEvent.pressedMouseButtons & 1 != 0
        let abans = (vist: estat.destiVist, perdut: estat.perdutDesDe != nil)
        let decisio = estat.decideix(ara: .now, cursorALaFila: rect?.contains(ratoli) ?? false, botoPremut: premut,
                                     filaEsDesti: aLaPantalla?.desti, retard: Self.retard)
        if let fila = estat.fila.map(Registre.curt) {
            if !abans.vist, estat.destiVist {
                Registre.arrossegar.notice("molla: la fila \(fila, privacy: .public) és la destinació")
            }
            if !abans.perdut, estat.perdutDesDe != nil {
                Registre.arrossegar.notice("molla: la fila \(fila, privacy: .public) ja no és la destinació: no s'obre")
            }
            if abans.perdut, estat.perdutDesDe == nil {
                Registre.arrossegar.notice("molla: la fila \(fila, privacy: .public) torna a ser la destinació")
            }
        }
        switch decisio {
        case .espera:
            break
        case let .atura(motiu):
            registraAtura(motiu.rawValue)
            aturaSenseRegistre()
        case let .obre(fila):
            Registre.arrossegar.notice("""
                molla: obre la fila \(Registre.curt(fila), privacy: .public), destinació vista \(self.estat.destiVist)
                """)
            let obre = self.obre
            aturaSenseRegistre()
            obre?(fila)
        }
    }

    /// La fila a la pantalla: la `NSTableRowView` que conté la vista (la `List` de macOS és un `NSOutlineView`, i les
    /// files, `ListTableRowView`), o la vista mateixa si no n'hi ha cap. `nil` si la vista ja no és a cap finestra.
    /// `desti` és `isTargetForDropOperation` de la fila (AppKit el treu quan l'arrossegament en surt, també amb Esc), o
    /// `nil` si no s'ha trobat la `NSTableRowView`.
    private func filaALaPantalla(_ fila: Finestra.ID) -> (rect: CGRect, desti: Bool?)? {
        guard let vista = vistes[fila]?.vista, let finestra = vista.window else { return nil }
        var actual: NSView? = vista
        while let v = actual, !(v is NSTableRowView) { actual = v.superview }
        let filaVista = actual ?? vista
        let rect = finestra.convertToScreen(filaVista.convert(filaVista.bounds, to: nil))
        return (rect, (actual as? NSTableRowView)?.isTargetForDropOperation)
    }
}

/// La decisió de la molla, sense AppKit ni rellotge: es prova sola.
struct EstatMolla: Equatable {
    enum Motiu: String, Equatable {
        case senseFila = "cap fila"
        case foraDeLaFila = "el cursor és fora de la fila"
        case amollat = "s'ha amollat el botó"
    }

    enum Decisio: Equatable {
        case espera
        case obre(Finestra.ID)
        case atura(Motiu)
    }

    /// Una pèrdua de la destinació més curta (un parpelleig d'AppKit, menys de dos tocs del rellotge) no fa tornar a
    /// començar el compte.
    static let marge: TimeInterval = 0.1

    /// La fila on és el cursor, i des de quan.
    private(set) var fila: Finestra.ID?
    private(set) var desDe: Date?
    /// On és la fila segons l'última actualització de la sessió, per si no es troba la vista.
    private(set) var rectDeLaSessio: CGRect?
    /// La fila ha estat la destinació d'AppKit des que s'hi ha entrat.
    private(set) var destiVist = false
    /// Des de quan ja no ho és, després d'haver-ho estat.
    private(set) var perdutDesDe: Date?

    /// `.entering` o `.active` d'una fila. Si és una altra fila, el compte torna a començar; si és la mateixa, no
    /// (`.active` només arriba quan canvia la zona on es deixarien anar, no amb el cursor quiet).
    mutating func entra(_ fila: Finestra.ID, ara: Date, rectDeLaSessio rect: CGRect?) {
        if self.fila != fila {
            self.fila = fila
            desDe = ara
            destiVist = false
            perdutDesDe = nil
        }
        rectDeLaSessio = rect
    }

    /// `.exiting` d'una fila (només si és la que es compta), o, sense fila, s'acaba tot.
    mutating func surt(_ fila: Finestra.ID? = nil) {
        guard fila == nil || fila == self.fila else { return }
        self.fila = nil
        desDe = nil
        rectDeLaSessio = nil
        destiVist = false
        perdutDesDe = nil
    }

    /// Quan salta el rellotge. El cursor i el botó són els d'ara: si el cursor surt de tota la barra lateral, la `List`
    /// no envia `.exiting` a la fila (docs/fets-verificats.md).
    ///
    /// `filaEsDesti` és si la fila és la destinació d'AppKit ara (`nil` si no se sap). Només compta si ho ha estat
    /// abans: si la fila no ho és mai, la molla fa com abans.
    /// - Mentre no ho és, no s'obre. Després d'Esc, el botó continua premut i el cursor a la fila fins que s'amolla.
    /// - No s'atura: si a la vora de la fila AppKit proposa inserir entre files, en tornar al mig s'ha de poder obrir
    ///   (revisió del pas 11). Si ho torna a ser després d'una pèrdua de més del `marge`, el compte torna a començar.
    mutating func decideix(ara: Date, cursorALaFila: Bool, botoPremut: Bool, filaEsDesti: Bool?,
                           retard: TimeInterval) -> Decisio {
        guard let fila, desDe != nil else { return .atura(.senseFila) }
        guard cursorALaFila else { return .atura(.foraDeLaFila) }
        guard botoPremut else { return .atura(.amollat) }
        switch filaEsDesti {
        case true?:
            if let perdut = perdutDesDe, ara.timeIntervalSince(perdut) >= Self.marge { desDe = ara }
            destiVist = true
            perdutDesDe = nil
        case false? where destiVist:
            if perdutDesDe == nil { perdutDesDe = ara }
            return .espera
        default:
            break
        }
        guard let desDe else { return .espera }
        return ara.timeIntervalSince(desDe) >= retard ? .obre(fila) : .espera
    }
}

private final class VistaFeble {
    weak var vista: NSView?
    init(_ vista: NSView) { self.vista = vista }
}

/// Una vista buida al fons de la fila d'una finestra: diu a la molla on és la fila a la pantalla. No rep clics
/// (`hitTest` és `nil`), ni s'hi pot deixar anar res.
struct AncoraFila: NSViewRepresentable {
    let molla: Molla
    let fila: Finestra.ID

    func makeNSView(context: Context) -> NSView {
        let vista = VistaAncora()
        molla.registra(vista, fila: fila)
        return vista
    }

    func updateNSView(_ vista: NSView, context: Context) {
        molla.registra(vista, fila: fila)
    }

    private final class VistaAncora: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
