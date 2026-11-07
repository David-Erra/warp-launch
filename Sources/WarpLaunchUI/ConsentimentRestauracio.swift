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

    /// Es pot prémer «Accepta».
    public var potAcceptar: Bool { estat == .pendent }

    /// Què passa si no s'accepta, per a la pantalla. Amb un `preferencies.json` que no es pot llegir, la propera vegada no
    /// es pregunta (torna a sortir l'error): diu on és el fitxer, que s'ha d'arreglar o esborrar (revisió de la 0.29.0).
    public var textSortir: String {
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

    /// L'únic lloc que crea el refresc i l'entorn de l'ajust de Warp: només amb el consentiment acceptat.
    private func creaRefresc() {
        guard estat == .acceptat, refresc == nil, let creaEntornRefresc else { return }
        refresc = RefrescWarp(entorn: creaEntornRefresc())
    }
}
