import Foundation
import Observation
import WarpLaunchCore

/// «Obre Warp Launch en iniciar sessió», a la Configuració (D3, fase 3.3). L'app només s'afegeix als ítems d'inici quan en
/// David activa l'interruptor (regla 3); mai sola. Es desfà amb el mateix interruptor, o a Configuració del Sistema ›
/// General › Ítems d’inici de sessió.
@MainActor
@Observable
public final class ArrencadaSessio {
    public enum Estat: Equatable, Sendable {
        case desactivada
        case activada
        /// Registrada, però macOS no l'obrirà sola: falta aprovar-la, o s'ha desactivat, a Configuració del Sistema.
        case perAprovar
    }

    /// L'accés als ítems d'inici de macOS (`ServeiArrencada`, només a l'app). Sense entorn, l'interruptor no fa res.
    public struct Entorn {
        public var estat: @MainActor () -> Estat
        public var activa: @MainActor () throws -> Void
        public var desactiva: @MainActor () throws -> Void
        public var obreAjustos: @MainActor () -> Void

        public init(estat: @escaping @MainActor () -> Estat, activa: @escaping @MainActor () throws -> Void,
                    desactiva: @escaping @MainActor () throws -> Void, obreAjustos: @escaping @MainActor () -> Void) {
            self.estat = estat
            self.activa = activa
            self.desactiva = desactiva
            self.obreAjustos = obreAjustos
        }
    }

    public private(set) var estat: Estat = .desactivada
    public private(set) var error: String?
    /// Per què no es pot activar (configuració de prova, l'app fora d'Aplicacions). Desactivar-la sempre es pot.
    public let motiuNoDisponible: String?
    @ObservationIgnored private let entorn: Entorn?

    public init(entorn: Entorn?, motiuNoDisponible: String?) {
        self.entorn = entorn
        self.motiuNoDisponible = entorn == nil ? (motiuNoDisponible ?? t("No disponible")) : motiuNoDisponible
        actualitza()
    }

    /// Per què no es pot activar amb l'app fora d'Aplicacions (`ServeiArrencada`): els ítems d'inici apunten al fitxer de l'app.
    public static func motiuForaDAplicacions(_ ruta: String) -> String {
        t("Per obrir-se en iniciar sessió, l'app ha de ser a Aplicacions (scripts/instal·la.sh --aplica). Ara és a \(ruta).")
    }

    /// L'interruptor: registrada, encara que macOS no l'hagi aprovada (així es pot treure).
    public var activada: Bool { estat != .desactivada }

    /// macOS l'obrirà en iniciar sessió. Pendent d'aprovar no compta: no s'obrirà sola.
    public var obreSola: Bool { estat == .activada }

    /// L'interruptor: només s'hi pot activar si no hi ha cap motiu en contra.
    public var editable: Bool { entorn != nil && (activada || motiuNoDisponible == nil) }

    /// Torna a mirar l'estat (es pot haver canviat a Configuració del Sistema).
    public func actualitza() {
        guard let entorn else { return }
        estat = entorn.estat()
    }

    /// L'únic camí que afegeix l'app als ítems d'inici: l'interruptor de la Configuració. L'únic altre que la'n treu és
    /// «Restaura Warp i surt…» (`treuDelsItemsDInici`, 0.31.0).
    public func posa(_ activada: Bool) {
        guard let entorn, activada != self.activada else { return }
        if activada, motiuNoDisponible != nil { return }
        do {
            if activada { try entorn.activa() } else { try entorn.desactiva() }
            error = nil
            Registre.obertura.notice("en iniciar sessió: \(activada ? "activada" : "desactivada")")
        } catch {
            self.error = activada ? t("No s'ha pogut activar: \(error.localizedDescription)")
                : t("No s'ha pogut desactivar: \(error.localizedDescription)")
        }
        actualitza()
    }

    public func obreAjustos() { entorn?.obreAjustos() }

    /// «Deixa de fer servir Warp Launch» (0.31.0, `Desinstallacio`): treu l'app dels ítems d'inici, si hi és (també pendent
    /// d'aprovar), pel mateix entorn que l'interruptor (`ServeiArrencada`). L'única altra manera de treure-la, i mai no
    /// l'afegeix. Torna per què no s'ha pogut; `nil` si ja no hi és.
    public func treuDelsItemsDInici() -> String? {
        actualitza()
        guard let entorn, activada else { return nil }
        do {
            try entorn.desactiva()
        } catch {
            actualitza()
            return t("No s'ha pogut treure Warp Launch dels ítems d'inici de sessió: \(error.localizedDescription). No s'ha canviat res més.")
        }
        actualitza()
        guard !activada else {
            return t("""
                macOS encara té Warp Launch als ítems d'inici de sessió: treu-la a Configuració del Sistema › General › \
                Ítems d’inici de sessió, i torna-ho a provar. No s'ha canviat res més.
                """)
        }
        error = nil
        Registre.obertura.notice("en iniciar sessió: desactivada en deixar de fer servir l'app")
        return nil
    }
}

extension Obertura {
    /// Què ha de fer l'app amb l'editor després de preparar el full d'iniciar sessió (des de la 0.27.2, sense esperar Warp).
    public enum AccioInici: Equatable, Sendable {
        /// Hi ha un full (o un error de la configuració, o la pantalla de consentiment) per veure: l'editor al davant.
        case mostra
        /// No falta cap finestra, o no hi ha res a obrir: l'editor es pot amagar.
        case amaga
        /// En David ja fa servir l'editor (una altra obertura, un altre full): no s'hi toca.
        case res
    }

    /// En iniciar sessió (D3): prepara el full de «Obre-ho tot» de seguida, sense esperar Warp. No obre res: el full espera
    /// el clic. Diu què cal fer amb l'editor, que SwiftUI obre sol en arrencar i és on surt el full.
    ///
    /// No espera Warp (en David, 06/11/2026: «per què he d'esperar dos minuts?»): Warp pot no ser als ítems d'inici, i l'app
    /// no ho pot saber. Amb Warp tancat, el full diu que l'obrirà; si Warp s'obre sol abans del clic, el clic ho torna a
    /// mirar i no l'engega dues vegades (`confirmaIObreTot`).
    public func enIniciarSessio() async -> AccioInici {
        Registre.obertura.notice("en iniciar sessió")
        // D-P4: primer, la pantalla de consentiment (a l'editor). L'app torna a cridar-ho quan s'accepta.
        guard consentiment.potContinuar else {
            Registre.obertura.notice("en iniciar sessió: falta el consentiment")
            return .mostra
        }
        // En David pot haver obert un altre full abans: no es trepitja ni s'amaga.
        guard estat == .cap, !editor.demanaImportacio else {
            Registre.obertura.notice("en iniciar sessió: ja hi ha una altra obertura o el full d'importar")
            return .res
        }
        guard potObrirTot else {
            Registre.obertura.notice("en iniciar sessió: no es pot obrir-ho tot")
            // L'error de la configuració, o el d'`estat.json`, ha de quedar a la vista: si no, no se sabria per què no surt res.
            if case .error = editor.estat { return .mostra }
            if editor.estat == .oberta, let motiu = sessions.motiuNoEsPotObrir {
                estat = .noEsPot(motiu)
                return .mostra
            }
            return .amaga
        }
        await demanaTot()
        switch estat {
        // Totes obertes: res a dir. Una finestra que falta però que no es pot obrir (un avís) sí que surt al full.
        case let .confirmantTot(proposta) where proposta.finestres.allSatisfy({ $0.pla.aObrir.isEmpty }):
            cancela()
            Registre.obertura.notice("en iniciar sessió: no falta cap finestra")
            return .amaga
        case .confirmantTot, .noEsPot:
            return .mostra
        default:
            // Cancel·lat mentre es preparava, o una altra obertura: no s'hi toca.
            return .res
        }
    }
}
