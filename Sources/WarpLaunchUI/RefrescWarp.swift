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
/// acceptat. **«Deixa de fer servir Warp Launch» (0.31.0) el retira** (`retira`): torna l'ajust com era i, a partir d'aquí,
/// no el toca mai més, tampoc en sortir de l'app.
///
/// **Si `settings.toml` acaba de canviar (0.31.3):** Warp el podria estar escrivint, i l'ajust no hi escriu res
/// (`AjustRestauracio.Escriptura.mesTard`). No és cap error: la vigilància de cada minut ho torna a provar, sense cap avís, i
/// al final d'un refresc es torna a provar cada segon uns quants cops (`segonsTornaAProvar`), perquè l'ajust quedi activat
/// tan poca estona com es pugui.
@MainActor
@Observable
public final class RefrescWarp {
    public struct Entorn: Sendable {
        /// El valor de l'ajust, o `nil` si `settings.toml` acaba de canviar (`AjustRestauracio.valor`).
        public var ajust: @Sendable () throws -> Bool?
        /// Amb `.mesTard`, no s'hi ha escrit res, i no és cap error (`AjustRestauracio.posa`).
        public var posa: @Sendable (Bool) throws -> AjustRestauracio.Escriptura
        public var warpObert: @Sendable () -> Bool
        /// La base de Warp, sigui quin sigui l'ajust (`Lector.llegeixDeLApp(base: .sempre)`). Sense cap Warp ni la seva base,
        /// els processos, sense finestres (`warpDesaFinestres` a `false`).
        public var llegeixBase: @Sendable () throws -> LecturaWarp
        public var espera: @Sendable (Duration) async throws -> Void

        public init(ajust: @escaping @Sendable () throws -> Bool?,
                    posa: @escaping @Sendable (Bool) throws -> AjustRestauracio.Escriptura,
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
    /// Al final d'un refresc, si `settings.toml` acabava de canviar: quants cops es torna a provar de desactivar l'ajust,
    /// d'un en un segon. Els 2 s d'`AjustRestauracio.segonsRecent`, i un de marge.
    public static let segonsTornaAProvar = 3

    /// «Restaura Warp i surt…» no ha pogut posar l'ajust: `settings.toml` acabava de canviar, i no s'hi ha escrit res.
    public struct MesTard: Error, Equatable, CustomStringConvertible {
        public var description: String { "«settings.toml» de Warp acaba de canviar (torna-ho a provar d'aquí a uns segons)" }
    }

    /// Per què l'app no pot fer la seva feina amb l'ajust: el menú de la icona ho diu.
    public private(set) var avis: String?
    /// L'última vegada que s'havia de desactivar l'ajust, `settings.toml` acabava de canviar: no s'hi ha escrit res, i no
    /// és cap error (no hi ha `avis`). La vigilància de cada minut ho torna a provar.
    @ObservationIgnored public private(set) var desactivacioPendent = false
    /// Sense la carpeta de Warp (0.31.2), l'app no la crea (`AjustRestauracio`). No és que Warp hagi de restaurar res: no ha
    /// obert mai cap finestra. Quan Warp creï la carpeta, la vigilància de cada minut hi afegirà la línia. No diu «quan
    /// l'obris»: no s'ha vist si Warp la crea en obrir-se per primer cop.
    public static let avisWarpMaiObert = "Warp encara no s'ha obert mai en aquest usuari: no té la seva carpeta d'ajustos, "
        + "ni cap finestra per restaurar. Quan Warp la creï, Warp Launch en desactivarà la restauració de sessió en menys "
        + "d'un minut."
    @ObservationIgnored private let entorn: Entorn
    @ObservationIgnored private var enCurs: Task<Resultat, Never>?
    /// L'app està sortint: cap cicle pot tornar a activar l'ajust (`atura`).
    @ObservationIgnored private var aturat = false
    /// «Deixa de fer servir Warp Launch» (`retira`): ni la vigilància de cada minut, ni cap cicle, ni sortir de l'app no
    /// toquen l'ajust. Només `desfesRetirada` el torna a fals.
    @ObservationIgnored private var retirat = false

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
        guard enCurs == nil, !retirat else { return }
        do {
            switch try entorn.ajust() {
            case .some(true):
                Registre.refresc.notice("l'ajust era activat fora d'un refresc: es desactiva")
                desactiva()
            case .some(false):
                desactivacioPendent = false
                avis = nil
            case .none:
                // No és cap error: d'aquí a un minut es torna a mirar, sense avís.
                Registre.refresc.notice("settings.toml acaba de canviar: es torna a mirar d'aquí a un minut")
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

    /// «Deixa de fer servir Warp Launch» (0.31.0, decisió 3 d'en David): posa l'ajust a `valor` (el d'abans de l'app, o el
    /// de sèrie de Warp) o, amb `nil`, el deixa com és; i, a partir d'aquí, l'app no el toca mai més: ni la vigilància de
    /// cada minut, ni un refresc (el que estigui en curs s'atura), ni sortir de l'app (`tanca`, `atura`). L'única crida que
    /// el posa a un valor que no és el d'un refresc.
    ///
    /// Si no es pot posar, no ha canviat res: el refresc continua com abans (la vigilància el tornarà a desactivar), i llança
    /// l'error. Sincrònic, al fil principal: cap cicle no pot canviar l'ajust entre la retirada i l'escriptura.
    public func retira(posant valor: Bool?) throws {
        guard !retirat else { return }
        retirat = true
        enCurs?.cancel()
        guard let valor else { return }
        do {
            guard try entorn.posa(valor) != .mesTard else { throw MesTard() }
        } catch {
            retirat = false
            throw error
        }
        Registre.refresc.notice("retirat: l'ajust torna a \(valor ? "activat" : "desactivat", privacy: .public)")
    }

    /// Si la retirada no s'ha pogut acabar (el permís no s'ha pogut retirar): el refresc torna a gestionar l'ajust, i el
    /// desactiva de seguida.
    public func desfesRetirada() {
        guard retirat else { return }
        retirat = false
        desactiva()
    }

    private func cicle() async -> Resultat {
        // Retirat: la base tal com és, sense activar res.
        guard !retirat else { return avisant(await base(), warpTancat: !entorn.warpObert()) }
        guard entorn.warpObert() else { return avisant(await base(), warpTancat: true) }
        // Sense poder llegir la base (per exemple, sense permís), activar l'ajust no serviria de res.
        let inicial = await base()
        guard case let .success(lecturaAbans) = inicial else { return inicial }
        // `tanca` o `retira` poden haver arribat durant la lectura, i Warp pot haver-se tancat.
        guard !aturat, !retirat, !Task.isCancelled, entorn.warpObert() else {
            return avisant(inicial, warpTancat: !entorn.warpObert())
        }
        let abans = lecturaAbans.fotoFinestres
        do {
            // `settings.toml` acaba de canviar: no s'activa, i no és cap error. La lectura d'ara diu si és antiga.
            guard try entorn.posa(true) != .mesTard else {
                Registre.refresc.notice("settings.toml acaba de canviar: aquest refresc no activa l'ajust")
                return avisant(inicial, warpTancat: false)
            }
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
        // Si `settings.toml` acabava de canviar, d'aquí a un segon i no d'aquí a un minut: com menys estona activat, millor.
        var intents = 0
        while desactivacioPendent, !retirat, intents < Self.segonsTornaAProvar {
            intents += 1
            do { try await entorn.espera(.seconds(1)) } catch { break }
            desactiva()
        }
        return avisant(await base(), warpTancat: !entorn.warpObert())
    }

    /// Una foto que pot no ser el que hi ha obert ho ha de dir: a importar i a lligar, i al menú. Sense cap Warp ni la seva
    /// base, no hi ha cap foto: res a dir.
    private func avisant(_ resultat: Resultat, warpTancat: Bool) -> Resultat {
        guard case var .success(lectura) = resultat, lectura.warpDesaFinestres != false else { return resultat }
        if warpTancat {
            lectura.avisFoto = LecturaWarp.avisFotoWarpTancat
        } else if !lectura.finestresQuadrenAmbTerminals {
            lectura.avisFoto = lectura.avisFinestresAntigues
        }
        if let avis = lectura.avisFoto { lectura.avisos.append(avis) }
        return .success(lectura)
    }

    /// Si `settings.toml` acaba de canviar, no s'hi escriu res, i no és cap error: tornar-ho a provar de seguida no serviria
    /// (`AjustRestauracio.segonsRecent`), i ho fa la vigilància de cada minut, sense avís. Un error es torna a provar de
    /// seguida, fins a tres cops. Retirat, res.
    private func desactiva() {
        guard !retirat else { return }
        var darrer: (any Error)?
        for _ in 0..<3 {
            do {
                if try entorn.posa(false) == .mesTard {
                    desactivacioPendent = true
                    Registre.refresc.notice("settings.toml acaba de canviar: l'ajust es desactivarà més tard")
                    return
                }
                darrer = nil
                break
            } catch {
                darrer = error
            }
        }
        desactivacioPendent = false
        if let darrer {
            avis = (darrer as? AjustRestauracio.Refusat)?.warpMaiObert == true ? Self.avisWarpMaiObert
                : "No s'ha pogut desactivar la restauració de sessió de Warp: \(darrer). Si Warp es tanca, restaurarà les finestres sense Claude."
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
