import Foundation
import Observation
import WarpLaunchCore

/// D19: la restauració de sessió de Warp sempre queda desactivada, perquè Warp no restauri finestres sense Claude en
/// arrencar. Només quan en David ho demana («Torna a llegir Warp», importar i lligar), i amb Warp obert, l'app l'activa uns
/// segons perquè Warp desi les finestres a la seva base («la foto»), i la torna a desactivar. Amb Warp tancat, la llegeixen
/// tal com és.
///
/// **Ja no cada 5 minuts (0.27.3, en David, 06/11/2026):** en un reinici de prova, Warp va restaurar la foto (les
/// pestanyes, sense Claude), perquè la restauració era activada quan Warp va arrencar. Com menys estona és activada, menys risc.
///
/// Obrir finestres no en depèn: es fa pels processos (`Obertura`).
///
/// **Només amb el consentiment de l'usuari (D-P4, 0.29.0):** l'únic que el crea és `ConsentimentRestauracio`, quan s'ha
/// acceptat.
@MainActor
@Observable
public final class RefrescWarp {
    public struct Entorn: Sendable {
        public var ajust: @Sendable () throws -> Bool
        public var posa: @Sendable (Bool) throws -> Void
        public var warpObert: @Sendable () -> Bool
        /// La base de Warp, sigui quin sigui l'ajust (`Lector.llegeix(base: .sempre)`).
        public var llegeixBase: @Sendable () throws -> LecturaWarp
        public var espera: @Sendable (Duration) async throws -> Void

        public init(ajust: @escaping @Sendable () throws -> Bool, posa: @escaping @Sendable (Bool) throws -> Void,
                    warpObert: @escaping @Sendable () -> Bool, llegeixBase: @escaping @Sendable () throws -> LecturaWarp,
                    espera: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
            self.ajust = ajust
            self.posa = posa
            self.warpObert = warpObert
            self.llegeixBase = llegeixBase
            self.espera = espera
        }
    }

    public typealias Resultat = Result<LecturaWarp, EstatWarp.ErrorLectura>

    /// Com a màxim, l'estona que l'ajust queda activat.
    public static let segonsMaxim = 30
    /// Si no hi ha cap canvi, l'estona mínima: a la prova, Warp va desar en menys de 5 s.
    public static let segonsMinim = 5

    /// Per què l'app no pot fer la seva feina amb l'ajust: el menú de la icona ho diu.
    public private(set) var avis: String?
    @ObservationIgnored private let entorn: Entorn
    @ObservationIgnored private var enCurs: Task<Resultat, Never>?
    /// L'app està sortint: cap cicle pot tornar a activar l'ajust (`atura`).
    @ObservationIgnored private var aturat = false

    public init(entorn: Entorn) {
        self.entorn = entorn
    }

    /// Una lectura de les finestres: amb Warp obert, activa l'ajust i espera que Warp desi; amb Warp tancat, llegeix el que hi
    /// ha. Si ja s'està fent, n'espera el resultat.
    public func refresca() async -> Resultat {
        if let enCurs { return await enCurs.value }
        let tasca = Task { await cicle() }
        enCurs = tasca
        let resultat = await tasca.value
        enCurs = nil
        return resultat
    }

    /// Cada minut i en arrencar: l'ajust ha de ser desactivat si no hi ha cap refresc. Pot ser activat si l'app es va penjar
    /// a mig refresc, si el núvol de Warp hi ha tornat a posar un valor antic o si s'ha activat a mà.
    public func vigila() {
        guard enCurs == nil else { return }
        do {
            if try entorn.ajust() {
                Registre.refresc.notice("l'ajust era activat fora d'un refresc: es desactiva")
                desactiva()
            } else {
                avis = nil
            }
        } catch {
            avis = "No es pot mirar la restauració de sessió de Warp: \(error)"
            Registre.refresc.error("\(String(describing: error), privacy: .public)")
        }
    }

    /// Abans de sortir de l'app o d'engegar Warp: desactiva l'ajust ara mateix, sense esperar res. Sincrònic: l'app pot sortir
    /// tot seguit.
    public func tanca() {
        enCurs?.cancel()
        desactiva()
    }

    /// En demanar sortir: cap cicle tornarà a activar l'ajust mentre una alerta pugui aturar la sortida.
    public func atura() {
        aturat = true
        tanca()
    }

    /// La sortida s'ha cancel·lat.
    public func repren() {
        aturat = false
    }

    private func cicle() async -> Resultat {
        guard entorn.warpObert() else { return avisant(await base(), warpTancat: true) }
        // Sense poder llegir la base (per exemple, sense permís), activar l'ajust no serviria de res.
        let inicial = await base()
        guard case let .success(lecturaAbans) = inicial else { return inicial }
        // `tanca` pot haver arribat durant la lectura, i Warp pot haver-se tancat.
        guard !aturat, !Task.isCancelled, entorn.warpObert() else { return avisant(inicial, warpTancat: !entorn.warpObert()) }
        let abans = lecturaAbans.fotoFinestres
        do {
            try entorn.posa(true)
        } catch {
            avis = "No es pot activar la restauració de sessió de Warp: \(error)"
            Registre.refresc.error("\(String(describing: error), privacy: .public)")
            return avisant(inicial, warpTancat: false)
        }
        for segon in 1...Self.segonsMaxim {
            do { try await entorn.espera(.seconds(1)) } catch { break }
            guard !Task.isCancelled, entorn.warpObert() else { break }
            guard case let .success(lectura) = await base(), lectura.finestresQuadrenAmbTerminals else { continue }
            if lectura.fotoFinestres != abans || segon >= Self.segonsMinim { break }
        }
        desactiva()
        return avisant(await base(), warpTancat: !entorn.warpObert())
    }

    /// Una foto que pot no ser el que hi ha obert ho ha de dir: a importar i a lligar, i al menú.
    private func avisant(_ resultat: Resultat, warpTancat: Bool) -> Resultat {
        guard case var .success(lectura) = resultat else { return resultat }
        if warpTancat {
            lectura.avisFoto = LecturaWarp.avisFotoWarpTancat
        } else if !lectura.finestresQuadrenAmbTerminals {
            lectura.avisFoto = lectura.avisFinestresAntigues
        }
        if let avis = lectura.avisFoto { lectura.avisos.append(avis) }
        return .success(lectura)
    }

    /// Warp l'escriu en calent: si acaba de canviar, es torna a provar de seguida.
    private func desactiva() {
        var darrer: (any Error)?
        for _ in 0..<3 {
            do {
                try entorn.posa(false)
                darrer = nil
                break
            } catch {
                darrer = error
            }
        }
        if let darrer {
            avis = "No s'ha pogut desactivar la restauració de sessió de Warp: \(darrer). Si Warp es tanca, restaurarà les finestres sense Claude."
            Registre.refresc.error("\(String(describing: darrer), privacy: .public)")
        } else {
            avis = nil
        }
    }

    /// Fora del fil principal: la base té un `busy_timeout` de 3 s.
    private func base() async -> Resultat {
        let lector = entorn.llegeixBase
        return await Task.detached { () -> Resultat in
            do {
                return .success(try lector())
            } catch {
                return .failure(EstatWarp.ErrorLectura(description: String(describing: error)))
            }
        }.value
    }
}
