import Foundation
import Observation
import WarpLaunchCore

/// La darrera lectura de Warp, en xifres, per al menú de la icona; i la lectura sencera per al full d'importació.
/// Llegeix fora del fil principal (la base de Warp té un `busy_timeout` de 3 s). Només llegeix: no obre ni toca res de
/// Warp ni de Claude.
@MainActor
@Observable
public final class EstatWarp {
    public enum Estat: Equatable {
        case senseLlegir
        case llegint
        case llegit(ResumWarp)
        case error(String)
    }

    public private(set) var estat: Estat = .senseLlegir
    /// Si el que diu `descripcio` surt d'una foto que pot no ser el que hi ha obert (D19). Dura fins a la lectura següent.
    public private(set) var avisFoto: String?
    @ObservationIgnored private let lector: @Sendable () throws -> LecturaWarp
    /// La lectura que s'està fent: qui torna a demanar-ne una mentrestant, l'espera i en rep el mateix resultat.
    @ObservationIgnored private var enCurs: Task<Result<LecturaWarp, ErrorLectura>, Never>?
    /// Després de cada lectura bona: l'app hi posa al dia els lligams de les pestanyes (`EstatSessions`).
    @ObservationIgnored public var enLlegir: @MainActor (LecturaWarp) -> Void = { _ in }

    /// Qui refresca la foto de les finestres (D19). `nil` si l'app no gestiona l'ajust de Warp (carpeta de prova, o sense
    /// el consentiment, D-P4).
    @ObservationIgnored public var refresc: RefrescWarp?

    /// Per què no s'ha pogut llegir Warp (sovint, el permís de Privacitat i seguretat).
    public struct ErrorLectura: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    /// - Parameter lector: la lectura; l'app hi passa `Lector(…).llegeixDeLApp`, i les proves, una de falsa.
    public init(lector: @escaping @Sendable () throws -> LecturaWarp) {
        self.lector = lector
    }

    public var descripcio: String {
        switch estat {
        case .senseLlegir: "Warp: encara no s'ha llegit"
        case .llegint: "Warp: llegint…"
        case let .llegit(resum): resum.descripcio
        case let .error(missatge): "Warp: no s'ha pogut llegir (\(missatge))"
        }
    }

    /// Llegeix Warp. Si ja s'està llegint, espera aquella lectura i en torna el mateix resultat (també el motiu, si
    /// falla: no s'ha de mirar `estat`, que potser encara no s'ha posat al dia). La lectura no es guarda: només les
    /// xifres.
    @discardableResult
    public func llegeix() async -> Result<LecturaWarp, ErrorLectura> {
        if let enCurs { return await enCurs.value }
        estat = .llegint
        let lector = self.lector
        let tasca = Task.detached { () -> Result<LecturaWarp, ErrorLectura> in
            do {
                return .success(try lector())
            } catch {
                return .failure(ErrorLectura(description: String(describing: error)))
            }
        }
        enCurs = tasca
        let resultat = await tasca.value
        enCurs = nil
        switch resultat {
        case let .success(lectura):
            estat = .llegit(ResumWarp(lectura))
            avisFoto = nil
            enLlegir(lectura)
        case let .failure(error): estat = .error(error.description)
        }
        return resultat
    }

    /// «Torna a llegir», importar i lligar (D19): també les finestres i els títols. Amb Warp obert, llegeix de Warp; amb
    /// Warp tancat, l'última foto. Pot trigar fins a 30 s. La lectura de cada minut torna als terminals.
    @discardableResult
    public func llegeixAmbFinestres() async -> Result<LecturaWarp, ErrorLectura> {
        guard let refresc else { return await llegeix() }
        estat = .llegint
        let resultat = await refresc.refresca()
        switch resultat {
        case let .success(lectura):
            estat = .llegit(ResumWarp(lectura))
            avisFoto = lectura.avisFoto
            enLlegir(lectura)
        case let .failure(error): estat = .error(error.description)
        }
        return resultat
    }
}

/// Per què una lectura no té finestres per importar ni lligar (`FullImportacio`, `Lligam`): el mateix text als dos fulls,
/// i cadascú hi afegeix què es pot fer.
enum MotiuSenseFinestres: Equatable {
    /// No hi ha cap Warp Stable (0.31.1: cap Warp, o només Warp Preview), i la lectura no n'ha llegit la base
    /// (`Lector.llegeixDeLApp`): el text del full d'obrir (`WarpPreview.text`), amb la configuració de debò i amb una de prova.
    /// També amb Warp Preview obert i un Warp Stable sense la seva base (`.obert` i `LecturaWarp.warpSenseBase`).
    case senseWarp(WarpPreview)
    /// Warp Stable hi és, però la seva base no (`LecturaWarp.warpSenseBase`): Warp encara no hi ha desat res, com en un
    /// usuari de macOS on no s'ha obert mai. No és per l'ajust: de sèrie, Warp desa les finestres. Amb una carpeta de prova i
    /// amb la configuració de debò, el mateix text que el CLI (`LecturaWarp.senseBase`).
    case senseBase(warpObert: Bool)
    /// Sense refresc (D19), l'app no ha pogut demanar a Warp que desi les finestres: és una carpeta de prova (`--config`),
    /// on l'app no toca l'ajust, i no és que Warp no tingui res. Sense el consentiment tampoc no n'hi ha, però llavors els
    /// fulls no es poden obrir (D-P4).
    case deProva
    /// Amb el refresc, la foto sempre hi és (`BaseWarp.sempre`): per si de cas.
    case restauracioDesactivada

    /// `nil`: la lectura té les finestres de Warp (`warpDesaFinestres` no és `false`). `ambRefresc`: si l'app gestiona
    /// l'ajust (`EstatWarp.refresc`).
    init?(_ lectura: LecturaWarp, ambRefresc: Bool) {
        guard lectura.warpDesaFinestres == false else { return nil }
        // Amb Warp Preview obert, Warp Stable hi és, i la lectura és la de sempre. Si Warp Stable, però, encara no hi ha desat
        // res (`warpSenseBase`), el text de Warp Preview, com el CLI: «obre'l» no s'entendria amb un Warp obert.
        if let preview = lectura.warpPreview, preview != .obert || lectura.warpSenseBase == true {
            self = .senseWarp(preview)
        } else if lectura.warpSenseBase == true {
            self = .senseBase(warpObert: lectura.warpObert == true)
        } else {
            self = ambRefresc ? .restauracioDesactivada : .deProva
        }
    }

    var text: String {
        switch self {
        case let .senseWarp(preview): preview.text
        case let .senseBase(warpObert): LecturaWarp.senseBase(warpObert: warpObert)
        case .deProva:
            LecturaWarp.senseFinestres + " Amb una configuració de prova (--config), l'app no toca aquest ajust i no pot "
                + "demanar a Warp que les desi. Amb la configuració de debò, sí: l'activa uns segons perquè Warp les desi, i "
                + "el torna a desactivar."
        case .restauracioDesactivada: LecturaWarp.senseFinestres
        }
    }
}
