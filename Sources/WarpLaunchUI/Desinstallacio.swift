import Foundation
import Observation
import WarpLaunchCore

/// «Deixa de fer servir Warp Launch» (0.31.0, decisió 3 d'en David, 07/11/2026), al final de Configuració › General: qui
/// deixa de fer servir l'app torna a deixar Warp com era abans que l'app hi toqués, amb un botó i una confirmació. En
/// confirmar, si `preferencies.json` encara diu el que ha mostrat la confirmació (si no, no fa res i ho diu), en aquest ordre:
/// 1. treu l'app dels ítems d'inici de sessió, si hi és (`ArrencadaSessio.treuDelsItemsDInici`, que va a
///    `ServeiArrencada`, l'únic que toca els ítems d'inici de macOS). Si no es pot, no fa res més; es pot tornar a activar
///    amb l'interruptor.
/// 2. torna `restore_session` com era i retira el permís (`ConsentimentRestauracio.retira`): el refresc queda retirat, i
///    ni el de cada minut ni sortir no tornen a desactivar l'ajust. Si no es pot, no ha canviat res.
/// 3. surt de l'app.
///
/// Només amb la configuració de debò i el permís acceptat o migrat (D19, regla 7): si no, el botó és desactivat, i el peu
/// diu per què. La configuració (`configuracio.json`, `estat.json`) no s'esborra: el README diu com fer-ho.
@MainActor
@Observable
public final class Desinstallacio {
    /// Què se'n farà de l'ajust, o per què no es pot. Es torna a mirar en mostrar la Configuració i abans de confirmar.
    public private(set) var retirada: ConsentimentRestauracio.Retirada
    /// La confirmació és a la vista.
    public var confirmant = false
    /// L'últim intent no s'ha pogut acabar: es diu a la secció.
    public private(set) var error: String?

    @ObservationIgnored private let consentiment: ConsentimentRestauracio
    @ObservationIgnored private let arrencada: ArrencadaSessio
    @ObservationIgnored private let surt: () -> Void

    /// - Parameter surt: l'app hi fa sortir el procés (aquí no es toca `NSApp`).
    public init(consentiment: ConsentimentRestauracio, arrencada: ArrencadaSessio, surt: @escaping () -> Void) {
        self.consentiment = consentiment
        self.arrencada = arrencada
        self.surt = surt
        retirada = consentiment.retirada()
    }

    /// El nom de l'ajust a la configuració de Warp, com el diu la pantalla del permís.
    static let nomAjust = "«Restore windows, tabs, and panes on startup»"

    public var disponible: Bool {
        if case .disponible = retirada { true } else { false }
    }

    /// Torna a mirar què es pot fer (`preferencies.json` i el permís poden haver canviat).
    public func actualitza() {
        retirada = consentiment.retirada()
    }

    /// El botó de la secció: la confirmació, si es pot.
    public func demana() {
        error = nil
        actualitza()
        // El missatge diu si la treurà dels ítems d'inici: es pot haver canviat a Configuració del Sistema.
        arrencada.actualitza()
        confirmant = disponible
    }

    /// El botó de la confirmació: fa els tres passos, i si un no es pot fer, ho diu i no fa els següents.
    public func confirma() {
        confirmant = false
        guard case let .disponible(retorn) = retirada else { return }
        // Abans de cap pas, tampoc els ítems d'inici: el que ha dit la confirmació encara ha de ser el que es farà (revisió de
        // la 0.31.0). `ConsentimentRestauracio.retira` ho torna a mirar.
        guard consentiment.retirada() == retirada else {
            error = ConsentimentRestauracio.ErrorRetirada.haCanviat.description
            actualitza()
            return
        }
        arrencada.actualitza()
        let eraALInici = arrencada.activada
        if let motiu = arrencada.treuDelsItemsDInici() {
            error = motiu
            return
        }
        do {
            try consentiment.retira(retorn)
        } catch {
            // Els ítems d'inici, en canvi, ja s'han tret: l'interruptor de dalt ho mostra.
            self.error = error.description + (eraALInici
                ? " Warp Launch ja no s'obre en iniciar sessió: si vols, torna a activar l'interruptor de dalt." : "")
            actualitza()
            return
        }
        Registre.consentiment.notice("deixa de fer servir l'app: surt")
        surt()
    }

    /// Què se'n farà de l'ajust de Warp; `nil` si no es pot.
    public var textAjust: String? {
        guard case let .disponible(retorn) = retirada else { return nil }
        return switch retorn {
        case .original(true): "L'ajust de Warp \(Self.nomAjust) tornarà a estar activat, com el tenies abans de Warp Launch."
        case .original(false): "L'ajust de Warp \(Self.nomAjust) es quedarà desactivat, com el tenies abans de Warp Launch."
        case .deSerie: "No se sap com tenies l'ajust de Warp \(Self.nomAjust) abans de Warp Launch, perquè ja la feies "
            + "servir abans que demanés permís: quedarà activat, com ve de sèrie a Warp."
        case .senseCanvis: "Warp Launch no ha canviat mai l'ajust de Warp \(Self.nomAjust): es queda com és."
        }
    }

    /// El peu de la secció: què fa el botó o, si no es pot, per què.
    public var peu: String {
        switch retirada {
        case let .noDisponible(motiu): motiu
        case .disponible: "Torna l'ajust de Warp com era, retira el permís de Warp Launch, la treu dels ítems d'inici de "
            + "sessió si hi és, i surt. La configuració no s'esborra. Per desinstal·lar-la del tot, després arrossega-la a la "
            + "Paperera."
        }
    }

    public static let titolConfirmacio = "Vols deixar de fer servir Warp Launch?"

    /// El missatge de la confirmació: què passarà, abans que passi.
    public var missatgeConfirmacio: String {
        guard case let .disponible(retorn) = retirada, let textAjust else { return peu }
        let restaura = retorn.valor == true
            ? " En arrencar, Warp tornarà a obrir les pestanyes de l'última vegada, sense Claude." : ""
        let inici = arrencada.activada ? ", sortirà dels ítems d'inici de sessió" : ""
        return "\(textAjust)\(restaura) Warp Launch deixarà de tenir permís per tocar l'ajust\(inici) i es tancarà. La "
            + "configuració no s'esborra. Si la tornes a obrir, et tornarà a demanar permís."
    }
}
