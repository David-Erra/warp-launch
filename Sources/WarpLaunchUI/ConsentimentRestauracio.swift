import Foundation
import Observation
import WarpLaunchCore

/// D-P4 (en David, 07/11/2026): «Com ara, per a tothom. Demanant permís prèviament a l'usuari, de la necessitat de fer
/// això; si no, l'app no pot iniciar-se.»
///
/// L'app gestiona la restauració de sessió de Warp (D19, `RefrescWarp`) només amb el consentiment de `preferencies.json`.
/// Fins llavors no toca Warp: no hi ha refresc (ni tampoc en sortir), no es proposa obrir res (`Obertura`), i totes les
/// finestres de l'app mostren la pantalla de consentiment (`VistaConsentiment`). Si l'usuari no accepta, l'app surt sense
/// desar res, i la propera vegada ho torna a preguntar.
///
/// Una carpeta que ja tenia `configuracio.json` o `estat.json` compta com a acceptada (`MagatzemPreferencies.carrega`).
///
/// **«Deixa de fer servir Warp Launch» (0.31.0, decisió 3 d'en David)** el retira (`retira`, des de `Desinstallacio`): torna
/// l'ajust com era, i la propera vegada l'app torna a preguntar.
@MainActor
@Observable
public final class ConsentimentRestauracio {
    public enum Estat: Equatable, Sendable {
        /// Encara no s'ha acceptat: la pantalla de consentiment.
        case pendent
        case acceptat
        /// `preferencies.json` no es pot llegir: no se sap si s'ha acceptat, i no es trepitja. Només es pot sortir.
        case error(String)
        /// Sense carpeta de configuració: l'app no toca Warp, ni té on desar-ho.
        case noCal
        /// Retirat amb «Deixa de fer servir Warp Launch»: l'ajust de Warp torna a ser com era, i l'app surt tot seguit. Si la
        /// sortida es cancel·la, no toca res i només deixa sortir: el refresc retirat no es torna a crear (la propera
        /// vegada, sí, si s'accepta).
        case retirat
    }

    /// «Deixa de fer servir Warp Launch»: què se'n farà de l'ajust de Warp, o per què no es pot.
    public enum Retirada: Equatable, Sendable {
        case disponible(Preferencies.Retorn)
        case noDisponible(String)
    }

    public struct ErrorRetirada: Error, Equatable, CustomStringConvertible {
        public var description: String

        /// El que ha dit la confirmació ja no és el que es faria (`preferencies.json` ha canviat).
        public static let haCanviat = ErrorRetirada(description: "Mentrestant, «\(Preferencies.nomFitxer)» ha canviat: torna-ho a "
            + "provar.")
    }

    public private(set) var estat: Estat
    /// L'últim «Accepta» no s'ha pogut desar: es diu a la pantalla, i es pot tornar a provar.
    public private(set) var errorDesat: String?
    /// D19: la restauració sempre desactivada, i la foto de les finestres. **Només existeix amb el consentiment acceptat**
    /// i amb `creaEntornRefresc` (que l'app només dona amb la configuració de debò).
    public private(set) var refresc: RefrescWarp?

    @ObservationIgnored private let magatzem: MagatzemPreferencies?
    @ObservationIgnored private let creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?
    @ObservationIgnored private let rellotge: () -> Date
    /// El que espera que l'app pugui continuar (`enContinuar`).
    @ObservationIgnored private var pendents: [@MainActor () -> Void] = []

    /// - Parameters:
    ///   - magatzem: `nil` sense carpeta de configuració (`noCal`).
    ///   - creaEntornRefresc: l'accés a l'ajust de Warp. Només es crida amb el consentiment acceptat, i un sol cop.
    public init(magatzem: MagatzemPreferencies?, creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?,
                rellotge: @escaping () -> Date = { Date() }) {
        self.magatzem = magatzem
        self.creaEntornRefresc = creaEntornRefresc
        self.rellotge = rellotge
        guard let magatzem else {
            estat = .noCal
            return
        }
        do {
            estat = try magatzem.carrega().restauracio.esAcceptat ? .acceptat : .pendent
        } catch {
            estat = .error(error.description)
            Registre.consentiment.error("\(error.description, privacy: .public)")
        }
        if estat == .acceptat { creaRefresc() }
    }

    /// L'app pot fer la seva feina: s'ha acceptat, o no cal.
    public var potContinuar: Bool { estat == .acceptat || estat == .noCal }

    /// Si «Obre» pot crear la carpeta de launch configurations de Warp (regla 7): amb el permís acceptat o migrat i la
    /// configuració de debò, que és quan hi ha refresc. Un cop retirat, ja no, encara que el refresc hi quedi.
    public var potCrearCarpetaDeWarp: Bool { estat == .acceptat && refresc != nil }

    /// Es pot prémer «Accepta».
    public var potAcceptar: Bool { estat == .pendent }

    /// Decisió 7 de Sparkle: qui veu aquesta pantalla sap que l'app es connecta abans d'acceptar.
    public static let textActualitzacions = "Un cop al dia, l'app mira a GitHub si hi ha una versió nova i s'hi actualitza sola. Ho pots apagar a la Configuració."

    /// Què passa si no s'accepta, per a la pantalla. Amb un `preferencies.json` que no es pot llegir, la propera vegada no
    /// es pregunta (torna a sortir l'error): diu on és el fitxer, que s'ha d'arreglar o esborrar (revisió de la 0.29.0).
    public var textSortir: String {
        if estat == .retirat {
            // Amb «migrat», no és el d'abans, sinó el de sèrie de Warp: el que ha dit la confirmació (revisió de la 0.31.0).
            return "Warp Launch ha deixat l'ajust de Warp com t'ha dit en confirmar-ho, i ja no té permís per tocar-lo. Si la "
                + "tornes a obrir, te'l tornarà a demanar."
        }
        guard case let .error(motiu) = estat else {
            return "Sense aquest permís, Warp Launch no es pot fer servir. Si surts, no es desa res, i t'ho tornarà a "
                + "preguntar la propera vegada."
        }
        let on = magatzem.map { " (\($0.fitxer.path))" } ?? ""
        return "\(motiu). Mentre no l'arreglis o l'esborris\(on), Warp Launch no es pot fer servir."
    }

    /// Executa `accio` un sol cop, quan l'app pot continuar: ara mateix si ja es pot, o en acceptar.
    public func enContinuar(_ accio: @escaping @MainActor () -> Void) {
        if potContinuar { accio() } else { pendents.append(accio) }
    }

    /// Tancar una finestra de l'app (l'editor o la Configuració) amb la pantalla de consentiment a la vista és no
    /// acceptar-lo, com «Surt de l’app Warp Launch» (D-P4; la Configuració, decisió d'en David del 08/11/2026): crida `surt` i
    /// torna `false`, sense desar res (no hi ha res per desar). Amb el consentiment acceptat, o si no cal, torna `true`: la
    /// finestra es tanca com sempre i l'app continua.
    /// - Parameter surt: l'app hi fa sortir el procés (aquí no es toca `NSApp`).
    public func continuaEnTancarFinestra(surt: () -> Void) -> Bool {
        guard potContinuar else {
            Registre.consentiment.notice("finestra tancada sense acceptar: surt")
            surt()
            return false
        }
        return true
    }

    /// «Accepta», a la pantalla de consentiment: desa el consentiment, crea el refresc i continua. Si no es pot desar, ho
    /// diu i no continua.
    public func accepta() {
        guard estat == .pendent, let magatzem else { return }
        do {
            try magatzem.accepta(ara: rellotge())
        } catch {
            errorDesat = error.description
            Registre.consentiment.error("no s'ha pogut desar: \(error.description, privacy: .public)")
            return
        }
        errorDesat = nil
        estat = .acceptat
        Registre.consentiment.notice("acceptat")
        creaRefresc()
        let accions = pendents
        pendents = []
        for accio in accions { accio() }
    }

    /// «Deixa de fer servir Warp Launch» (0.31.0): què se'n farà de l'ajust, segons `preferencies.json` (que només llegeix), o
    /// per què no es pot. Només amb el consentiment acceptat (o migrat) i amb el refresc, que vol dir amb la configuració de
    /// debò (D19, regla 7: l'app només pot canviar l'ajust amb la carpeta de debò).
    public func retirada() -> Retirada {
        switch estat {
        case .noCal: return .noDisponible("Sense carpeta de configuració, Warp Launch no ha tocat Warp.")
        case .retirat: return .noDisponible("Ja has deixat de fer servir Warp Launch.")
        case .pendent, .error: return .noDisponible("Sense el teu permís, Warp Launch no ha tocat Warp.")
        case .acceptat: break
        }
        guard let magatzem, refresc != nil else {
            return .noDisponible("Amb una configuració de prova (--config), Warp Launch no toca l'ajust de Warp: no hi ha res "
                + "per tornar com era. Només es pot fer amb la configuració de debò.")
        }
        do {
            guard let retorn = try magatzem.carrega().retornEnRetirar else {
                return .noDisponible("«\(Preferencies.nomFitxer)» ja no diu que hi hagi el teu permís: torna a obrir Warp Launch.")
            }
            return .disponible(retorn)
        } catch {
            return .noDisponible(error.description)
        }
    }

    /// «Deixa de fer servir Warp Launch» (0.31.0, decisió 3 d'en David): torna l'ajust de Warp com era (`retorn`, el que ha
    /// mostrat la confirmació) i retira el permís a `preferencies.json`. A partir d'aquí, l'app no toca Warp (`.retirat`), i
    /// la propera vegada torna a preguntar. Primer l'ajust, que és el que pot fallar més (Warp l'escriu en calent): si no es
    /// pot posar, o si el permís no es pot desar (llavors l'ajust es torna a desactivar; si tampoc no es pot, ho diu), no
    /// ha canviat res, i llança l'error.
    public func retira(_ retorn: Preferencies.Retorn) throws(ErrorRetirada) {
        let ara = retirada()
        if case let .noDisponible(motiu) = ara { throw ErrorRetirada(description: motiu) }
        guard ara == .disponible(retorn), let magatzem, let refresc else { throw .haCanviat }
        do {
            try refresc.retira(posant: retorn.valor)
        } catch {
            Registre.consentiment.error("retirar: l'ajust: \(String(describing: error), privacy: .public)")
            throw ErrorRetirada(description: "No s'ha pogut tornar l'ajust de Warp com era: \(error). L'ajust i el permís no "
                + "han canviat.")
        }
        do {
            try magatzem.retira(ara: rellotge())
        } catch {
            refresc.desfesRetirada()
            Registre.consentiment.error("retirar: \(error.description, privacy: .public)")
            // Desactivar-lo també pot fallar (Warp l'escriu en calent): llavors el refresc té l'avís, i la vigilància de cada
            // minut ho torna a provar (revisió de la 0.31.0). Si `settings.toml` acabava de canviar (0.31.3), potser no hi ha
            // avís (no en surt fins als 5 minuts seguits), però tampoc no s'ha desactivat. Sense el fitxer i amb Warp tancat o
            // encara arrencant (ronda 5), o sense la carpeta de Warp (decisió 5), és el de sèrie fins que Warp sigui obert amb
            // algun terminal.
            let ajust = switch (refresc.avis, refresc.pendent) {
            case (nil, nil): "L'ajust de Warp torna a quedar desactivat, i el permís"
            case (nil, .quanSObriWarp?), (nil, .warpMaiObert?):
                "L'ajust de Warp ha quedat activat, com ve de sèrie (Warp no té «settings.toml»): Warp Launch el desactivarà "
                    + "quan Warp sigui obert amb alguna pestanya. El permís"
            default:
                "L'ajust de Warp ha quedat activat, i no s'ha pogut tornar a desactivar: Warp Launch ho tornarà a provar "
                    + "d'aquí a un minut. El permís"
            }
            throw ErrorRetirada(description: "No s'ha pogut retirar el permís: \(error.description). \(ajust) no ha canviat.")
        }
        estat = .retirat
        Registre.consentiment.notice("retirat")
    }

    /// L'únic lloc que crea el refresc i l'entorn de l'ajust de Warp: només amb el consentiment acceptat.
    private func creaRefresc() {
        guard estat == .acceptat, refresc == nil, let creaEntornRefresc else { return }
        refresc = RefrescWarp(entorn: creaEntornRefresc())
    }
}
