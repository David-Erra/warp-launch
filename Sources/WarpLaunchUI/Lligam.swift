import Foundation
import Observation
import WarpLaunchCore

/// «Lliga amb Warp…» (docs/disseny.md, secció 7, «Lligar amb Warp»): llegeix Warp, proposa la pestanya de Warp de cada
/// pestanya de la configuració sense lligam (`LligamWarp`) i, només amb «Lliga» al full, ho desa a `estat.json`. No
/// canvia la configuració, ni obre o tanca res de Warp ni de Claude.
@MainActor
@Observable
public final class Lligam {
    public enum Estat: Equatable {
        case cap
        case llegint
        case error(String)
        case llest(LligamWarp.Proposta)
        /// Desat: quantes pestanyes s'han lligat, o per què no s'ha pogut desar.
        case fet(Int, error: String?)
    }

    public private(set) var estat: Estat = .cap
    /// Si la lectura de Warp pot ser antiga (`RefrescWarp`): el full ho diu.
    public private(set) var avisLectura: String?
    /// Les parelles que en David ha desmarcat al full: no es lliguen.
    public var desmarcades: Set<UUID> = []
    @ObservationIgnored private let editor: Editor
    @ObservationIgnored private let sessions: EstatSessions
    @ObservationIgnored private let llegeix: @MainActor () async -> Result<LecturaWarp, EstatWarp.ErrorLectura>
    /// Si l'app gestiona l'ajust de Warp (`EstatWarp.refresc`): sense, és una carpeta de prova, i el full ho diu.
    @ObservationIgnored private let ambRefresc: @MainActor () -> Bool
    @ObservationIgnored private let inici: String
    /// Si el full es tanca i es torna a obrir mentre es llegia, la lectura vella no hi arriba.
    @ObservationIgnored private var peticio = 0

    /// - Parameters:
    ///   - llegeix: la lectura de Warp; a l'app, `EstatWarp.llegeixAmbFinestres`, que també posa al dia `estat.json`.
    ///   - ambRefresc: a l'app, si `EstatWarp.refresc` hi és (es posa en acceptar el consentiment).
    public init(editor: Editor, sessions: EstatSessions, inici: String,
                llegeix: @escaping @MainActor () async -> Result<LecturaWarp, EstatWarp.ErrorLectura>,
                ambRefresc: @escaping @MainActor () -> Bool) {
        self.editor = editor
        self.sessions = sessions
        self.inici = Rutes.canonica(inici)
        self.llegeix = llegeix
        self.ambRefresc = ambRefresc
    }

    public var mostraFull: Bool { estat != .cap }

    /// La configuració és oberta, `estat.json` es pot fer servir, no hi ha cap altre full i no s'aplica cap actualització: llegeix
    /// Warp amb les finestres (D19), i l'app sortiria a mig refresc (`Obertura.impedeixRefresc`).
    public var potLligar: Bool {
        estat == .cap && editor.estat == .oberta && sessions.motiuNoEsPotObrir == nil && !editor.demanaImportacio
            && !editor.demanaNovaPestanya && editor.obertura?.mostraFull != true && editor.obertura?.impedeixRefresc != true
    }

    /// Llegeix Warp i prepara el full. No desa res.
    public func demana() async {
        guard potLligar else { return }
        peticio += 1
        let aquesta = peticio
        desmarcades = []
        avisLectura = nil
        estat = .llegint
        let resultat = await llegeix()
        guard estat == .llegint, peticio == aquesta else { return }
        switch resultat {
        case let .success(lectura):
            // El mateix motiu que el full d'importar: amb una carpeta de prova, que és per això. Sense cap Warp Stable, o amb
            // Warp Preview obert, l'app no n'obre cap.
            if let motiu = MotiuSenseFinestres(lectura, ambRefresc: ambRefresc()) {
                if case .senseWarp = motiu {
                    estat = .error(motiu.text)
                } else {
                    estat = .error(Idioma.frases(motiu.text, t("Les pestanyes amb Claude que obre l'app es lliguen soles.")))
                }
                return
            }
            avisLectura = lectura.avisFoto
            let proposta = LligamWarp.proposa(editor.configuracio, lectura: lectura, estat: sessions.estat, inici: inici)
            estat = .llest(proposta)
            Registre.lligam.notice("""
                proposta \(proposta.parelles.count) parelles (\(proposta.parelles.filter { !$0.criteri.segur }.count) per \
                comprovar), \(proposta.senseParella.count) sense, \(proposta.jaLligades) ja lligades
                """)
        case let .failure(error):
            estat = .error(error.description)
        }
    }

    public func cancela() { estat = .cap }

    /// «Lliga»: desa a `estat.json` les parelles que no s'han desmarcat.
    public func confirma() {
        guard case let .llest(proposta) = estat else { return }
        let vincles = proposta.vincles(excepte: desmarcades)
        guard !vincles.isEmpty else { return }
        let error = sessions.lligaAmbWarp(vincles)
        estat = .fet(error == nil ? vincles.count : 0, error: error)
        Registre.lligam.notice("lligades \(error == nil ? vincles.count : 0)\(error.map { ": \($0)" } ?? "")")
    }
}
