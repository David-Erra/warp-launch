import Foundation

/// El que fa falta per calcular el pla: la lectura de Warp i de Claude, l'estat de l'app i el disc. L'app i el CLI hi
/// posen els valors reals; les proves, fixtures.
public struct EntradaObertura {
    public var lectura: LecturaWarp
    public var estat: EstatApp
    /// Carpeta d'inici canònica.
    public var inici: String
    public var ara: Date
    public var carpetaExisteix: (String) -> Bool
    /// On és la transcripció d'una conversa (`LectorTranscripcions.on`): (sessió, carpeta de la pestanya).
    public var transcripcio: (String, String) -> LectorTranscripcions.On
    /// Les converses d'una carpeta canònica, de la més recent a la més antiga (`LectorTranscripcions.recents`).
    public var conversesRecents: (String) -> [LectorTranscripcions.Recent]
    /// `nil` si no se sap (llavors no s'avisa).
    public var confianca: Confianca?
    /// Converses que reprèn una pestanya oberta fa poc (la del valor), on encara no s'ha vist el seu Claude (l'app ho
    /// recorda en memòria). Una altra pestanya amb la mateixa conversa compta com a oberta, perquè no hi hagi dues
    /// sessions sobre la mateixa conversa (R9).
    public var conversesEnCurs: [String: UUID]
    /// La ruta de `EntornClaude`, per a les pestanyes en bypass. `nil`: les línies no el porten.
    public var entornClaude: String?
    /// Converses que ja reprenen pestanyes d'altres finestres que s'obriran alhora («Obre-ho tot»): es tracten com les
    /// represes abans dins la mateixa finestra, perquè dues pestanyes no reprenguin mai la mateixa (R9).
    public var jaRepreses: Set<String> = []

    public init(lectura: LecturaWarp, estat: EstatApp, inici: String, ara: Date,
                carpetaExisteix: @escaping (String) -> Bool,
                transcripcio: @escaping (String, String) -> LectorTranscripcions.On,
                conversesRecents: @escaping (String) -> [LectorTranscripcions.Recent] = { _ in [] }, confianca: Confianca?,
                conversesEnCurs: [String: UUID] = [:], entornClaude: String? = nil) {
        self.lectura = lectura
        self.estat = estat
        self.inici = inici
        self.ara = ara
        self.carpetaExisteix = carpetaExisteix
        self.transcripcio = transcripcio
        self.conversesRecents = conversesRecents
        self.confianca = confianca
        self.conversesEnCurs = conversesEnCurs
        self.entornClaude = entornClaude
    }
}

/// On és oberta una pestanya que no s'obrirà (D13, R9).
public enum OnOberta: Sendable, Equatable, CustomStringConvertible {
    /// Un Claude viu porta la marca de la pestanya. `lloc`: la finestra i la pestanya de Warp, si se sap.
    case marca(lloc: String?)
    /// El pane recordat és a Warp.
    case pane(lloc: String, ambClaude: Bool)
    /// El pane recordat és viu: hi corre un procés que el porta. Sense la base de Warp, no se sap en quina finestra.
    case paneViu(ambClaude: Bool)
    /// La seva conversa és viva en una pestanya de Warp.
    case conversa(lloc: String)
    case conversaForaDeWarp
    /// La seva conversa és viva dins de Warp, però no se sap en quin pane.
    case conversaAWarp
    case conversaEnSegonPla(String)
    /// Una altra pestanya l'acaba de reprendre, i el seu Claude encara no s'ha vist (`EntradaObertura.conversesEnCurs`).
    case conversaEnCurs
    /// El seu Claude és viu dins de Warp, però el pane ja no hi és: s'acaba de tancar (Warp ho deixa desfer 60 s). La
    /// finestra no s'obre fins que passi (`Pla.motiuEspera`), perquè no quedi partida.
    case tancadaFaPoc

    /// És una pestanya de Warp (si Warp és tancat, de la sessió que restauraria), i no una conversa fora de Warp o en segon pla.
    public var esAWarp: Bool {
        switch self {
        case .marca, .pane, .paneViu, .conversa, .conversaAWarp, .tancadaFaPoc: true
        case .conversaForaDeWarp, .conversaEnSegonPla, .conversaEnCurs: false
        }
    }

    public var description: String {
        switch self {
        case let .marca(lloc): "oberta a Warp, amb Claude" + (lloc.map { " (\($0))" } ?? "")
        case let .pane(lloc, ambClaude): "oberta a Warp" + (ambClaude ? "" : ", sense Claude") + " (\(lloc))"
        case let .paneViu(ambClaude): "oberta a Warp" + (ambClaude ? "" : ", sense Claude")
        case let .conversa(lloc): "la seva conversa és oberta a Warp (\(lloc))"
        case .conversaForaDeWarp: "la seva conversa és oberta fora de Warp"
        case .conversaAWarp: "la seva conversa és oberta a Warp"
        case .conversaEnCurs: "una altra pestanya acaba de reprendre la seva conversa (el Claude encara no s'ha vist)"
        case let .conversaEnSegonPla(tipus): "la seva conversa és oberta en segon pla (\(tipus))"
        case .tancadaFaPoc: "tancada fa menys d'1 minut: espera i torna-ho a provar"
        }
    }
}

/// Per què una pestanya no es pot obrir.
public enum MotiuExclusio: Sendable, Equatable, CustomStringConvertible {
    /// Warp l'obriria a la seva carpeta per defecte i hi executaria Claude igualment.
    case carpetaNoExisteix
    /// Un error de la validació (el text de l'avís).
    case validacio(String)
    case ordre(OrdreClaude.ErrorOrdre)
    case fitxer(LaunchConfigWarp.ErrorPestanya)

    public var description: String {
        switch self {
        case .carpetaNoExisteix: "la carpeta no existeix"
        case let .validacio(text): text
        case let .ordre(error): "no es pot generar l'ordre: \(error)"
        case let .fitxer(error): "no es pot escriure per a Warp: \(error)"
        }
    }
}

/// Com s'obrirà Claude en una pestanya (D7).
public enum ConversaObertura: Sendable, Equatable {
    case terminal
    case repren(String)
    case nova(MotiuNova)

    public enum MotiuNova: Sendable, Equatable {
        /// La pestanya no continua la conversa.
        case noContinua
        /// No se'n sap la conversa.
        case senseConversa
        /// La conversa no té transcripció: `--resume` sortiria amb un error.
        case senseTranscripcio
        /// La transcripció és en més d'un projecte, cap del qual és el de la pestanya.
        case enDiversosProjectes
        /// Una altra pestanya del mateix llançament ja la reprèn.
        case repetida
    }

    /// La conversa que es reprèn, si n'hi ha.
    public var repren: String? {
        if case let .repren(id) = self { id } else { nil }
    }

    /// «només terminal», «Claude, reprèn 1b2c3d4e» o «Claude, conversa nova» (el motiu és als avisos).
    public var descripcio: String {
        switch self {
        case .terminal: "només terminal"
        case let .repren(id): "Claude, reprèn \(id.prefix(8))"
        case .nova: "Claude, conversa nova"
        }
    }
}

public struct PestanyaOberta: Sendable, Equatable {
    public var pestanya: Pestanya
    public var on: OnOberta
}

public struct PestanyaExclosa: Sendable, Equatable {
    public var pestanya: Pestanya
    public var motiu: MotiuExclusio
}

public struct PestanyaAObrir: Sendable, Equatable {
    public var pestanya: Pestanya
    public var conversa: ConversaObertura
    /// L'ordre de Claude, o `nil` si només és un terminal.
    public var argv: [String]?
    public var yaml: PestanyaYAML
}

/// Un avís del full de confirmació. Cap no impedeix obrir.
public struct AvisObertura: Sendable, Equatable, CustomStringConvertible {
    public enum Tipus: Sendable, Equatable {
        /// Una pestanya sense lligam és a la mateixa carpeta que una d'oberta.
        case potserJaOberta(lloc: String)
        /// Warp no desa les finestres, i a la carpeta de la pestanya hi ha un terminal sense Claude, o un Claude que no és de
        /// cap pestanya de la configuració: potser és aquesta, si Claude n'ha sortit o l'has obert a mà, però no se'n pot
        /// saber el títol. No impedeix obrir: una pestanya de més es veu i es tanca; una que no s'obre perquè «ja és oberta»
        /// no es trobaria enlloc.
        case terminalALaCarpeta(ambClaude: Bool)
        /// Warp no desa les finestres, i les pestanyes vives poden ser d'una finestra acabada de tancar: Warp les manté
        /// 60 s per poder-la desfer, i els processos no ho distingeixen. `partiria`: se n'obririen les altres, i la finestra
        /// quedaria en dues.
        case potserTancadaFaPoc(partiria: Bool)
        /// La conversa és d'un altre projecte: Claude la reprendrà igualment, a la carpeta de la pestanya.
        case conversaDUnaAltraCarpeta(projecte: String)
        case conversaEnDiversosProjectes([String])
        case conversaRepetida
        /// Informació: reprèn la conversa més recent de la carpeta, que no és la darrera vista a la pestanya.
        case conversaMesRecent(fa: TimeInterval)
        /// Informació: no se'n sap la conversa, o no té transcripció.
        case senseConversa
        case senseTranscripcio
        /// Claude preguntarà si confies en la carpeta: la pestanya esperarà una tecla.
        case confianca
        /// `--fork-session` a les altres opcions: cada obertura en farà una còpia.
        case forkSession
        case moltesSessions(Int)
        /// Un avís de la validació (el text): la pestanya s'obrirà, però potser no com s'espera.
        case validacio(String)
        /// L'últim llançament d'aquesta finestra no es va confirmar.
        case darrerSenseConfirmar(minuts: Int)
        /// L'últim llançament d'aquesta finestra va fallar (potser abans d'arribar a Warp).
        case darrerAmbError(minuts: Int)
    }

    /// La pestanya, si és d'una.
    public var pestanya: Pestanya?
    public var tipus: Tipus

    /// Si només és informació.
    public var esInfo: Bool {
        switch tipus {
        case .conversaMesRecent, .senseConversa, .senseTranscripcio: true
        default: false
        }
    }

    public var description: String {
        let text: String = switch tipus {
        case let .potserJaOberta(lloc): "potser ja és oberta a Warp (\(lloc)): és a la mateixa carpeta"
        case let .terminalALaCarpeta(ambClaude):
            "potser ja és oberta a Warp: hi ha " + (ambClaude ? "un Claude a la seva carpeta, que no és de cap pestanya de la "
                + "configuració" : "un terminal a la seva carpeta, sense Claude")
        case let .potserTancadaFaPoc(partiria):
            "si les acabes de tancar, espera 1 minut i torna-ho a provar: Warp les manté vives per poder-les desfer"
                + (partiria ? "; si obres ara, la finestra quedarà partida" : "")
        case let .conversaDUnaAltraCarpeta(projecte):
            "la conversa és d'una altra carpeta (\(projecte)); Claude la reprendrà en aquesta"
        case let .conversaEnDiversosProjectes(projectes):
            "la conversa és en \(projectes.count) projectes de Claude i cap no és el d'aquesta carpeta: en començarà una de nova"
        case .conversaRepetida: "una altra pestanya ja reprèn la mateixa conversa: aquesta en començarà una de nova"
        case let .conversaMesRecent(fa): "reprèn la conversa més recent de la carpeta (\(Self.fa(fa)))"
        case .senseConversa: "no se'n sap la conversa: en començarà una de nova"
        case .senseTranscripcio: "la conversa no té cap missatge desat: en començarà una de nova"
        case .confianca: "Claude preguntarà si confies en la carpeta: la pestanya esperarà una tecla"
        case .forkSession: "porta «--fork-session»: cada obertura farà una còpia de la conversa"
        case let .moltesSessions(n): "s'engegaran \(n) sessions de Claude alhora"
        case let .validacio(text): text
        case let .darrerSenseConfirmar(minuts):
            "l'últim cop que es va obrir aquesta finestra (fa \(minuts) min) no es va poder confirmar: mira Warp abans"
        case let .darrerAmbError(minuts):
            "l'últim intent d'obrir aquesta finestra (fa \(minuts) min) va fallar: si Warp n'ha obert res, mira-ho abans"
        }
        return pestanya.map { "\($0.nomAlFull): \(text)" } ?? text
    }

    /// «fa menys d'1 h», «fa 5 h» o «fa 3 dies».
    private static func fa(_ segons: TimeInterval) -> String {
        let hores = Int(segons / 3600)
        if hores < 1 { return "fa menys d'1 h" }
        if hores < 24 { return "fa \(hores) h" }
        return "fa " + Plural.compta(hores / 24, "dia", "dies")
    }
}

/// Les xifres del full de confirmació.
public struct XifresObertura: Sendable, Equatable {
    public var pestanyes: Int
    public var ambClaude: Int
    public var reprenen: Int
    public var terminal: Int
    public var jaObertes: Int
    public var excloses: Int

    public var noves: Int { ambClaude - reprenen }
    public var memoriaGB: Double { Double(ambClaude) * PlaObertura.memoriaPerSessioGB }

    /// «S'obrirà 1 finestra nova de Warp amb 9 pestanyes: 6 amb Claude (4 reprenen la seva conversa, 2 en comencen una
    /// de nova) i 3 només terminal · unes 3 GB · ja obertes: 14 · no s'obriran: 1».
    public var text: String {
        guard pestanyes > 0 else { return "No s'obrirà res." + resta }
        var parts: [String] = []
        if ambClaude > 0 {
            var detall: [String] = []
            if reprenen > 0 {
                detall.append(reprenen == 1 ? "1 reprèn la seva conversa" : "\(reprenen) reprenen la seva conversa")
            }
            if noves > 0 { detall.append(noves == 1 ? "1 en comença una de nova" : "\(noves) en comencen una de nova") }
            parts.append("\(ambClaude) amb Claude (\(detall.joined(separator: ", ")))")
        }
        if terminal > 0 { parts.append("\(terminal) només terminal") }
        let memoria = ambClaude > 0 ? " · unes \(Self.gb(memoriaGB)) GB" : ""
        return "S'obrirà 1 finestra nova de Warp amb \(Plural.compta(pestanyes, "pestanya", "pestanyes")): "
            + parts.joined(separator: " i ") + memoria + resta
    }

    private var resta: String {
        (jaObertes > 0 ? " · ja obertes: \(jaObertes)" : "") + (excloses > 0 ? " · no s'obriran: \(excloses)" : "")
    }

    private static func gb(_ valor: Double) -> String {
        valor == valor.rounded() ? String(Int(valor)) : String(format: "%.1f", valor).replacingOccurrences(of: ".", with: ",")
    }
}

/// El pla d'obrir una finestra.
public struct Pla: Sendable, Equatable {
    public var finestra: Finestra
    public var obertes: [PestanyaOberta]
    public var excloses: [PestanyaExclosa]
    public var aObrir: [PestanyaAObrir]
    public var avisos: [AvisObertura]

    /// Per què no s'ha d'obrir encara: alguna pestanya s'acaba de tancar, i el seu Claude encara és viu. Si s'obrissin
    /// les altres, la finestra quedaria partida en dues.
    public var motiuEspera: String? {
        guard !aObrir.isEmpty, obertes.contains(where: { $0.on == .tancadaFaPoc }) else { return nil }
        return "Alguna pestanya d'aquesta finestra s'ha tancat fa menys d'1 minut i el seu Claude encara és viu: "
            + "espera 1 minut i torna-ho a provar."
    }

    /// Pestanyes sense lligam a la mateixa carpeta que una d'oberta («potser ja és oberta»): el full d'obrir proposa
    /// «Lliga amb Warp…».
    public var potserObertes: Int {
        avisos.filter { if case .potserJaOberta = $0.tipus { true } else { false } }.count
    }

    /// Si alguna línia porta `EntornClaude`: llavors el fitxer s'ha d'escriure abans d'obrir.
    public var necessitaEntornClaude: Bool {
        aObrir.contains { $0.argv != nil && $0.pestanya.claude.enBypass }
    }

    public var xifres: XifresObertura {
        let ambClaude = aObrir.filter { $0.argv != nil }
        return XifresObertura(pestanyes: aObrir.count, ambClaude: ambClaude.count,
                              reprenen: ambClaude.filter { $0.conversa.repren != nil }.count,
                              terminal: aObrir.count - ambClaude.count, jaObertes: obertes.count, excloses: excloses.count)
    }

    /// El fitxer temporal per obrir les pestanyes que falten. Error si no n'hi ha cap.
    public func fitxer(llancament: UUID) throws(LaunchConfigWarp.ErrorLaunch) -> FitxerLaunch {
        try LaunchConfigWarp.genera(pestanyes: aObrir.map(\.yaml), llancament: llancament)
    }
}

/// Què passaria si s'obrís una finestra de la configuració a Warp (fase 3.1, R12; docs/disseny.md, secció 7): quines
/// pestanyes ja són obertes (D13, R9), quines no es poden obrir, i com s'obriria cadascuna de les altres (D7). No
/// escriu res; del disc només mira el que li diu l'entrada i la ruta canònica de les carpetes.
public enum PlaObertura {
    public static let memoriaPerSessioGB = 0.5
    /// A partir de quantes sessions s'avisa que s'engegaran alhora.
    public static let moltesSessions = 10
    /// Fins quan s'avisa que l'últim llançament no es va confirmar.
    public static let tempsDarrerLlancament: TimeInterval = 10 * 60

    public static func calcula(_ finestra: Finestra, _ entrada: EntradaObertura) -> Pla {
        let lectura = entrada.lectura
        // Amb la restauració de sessió desactivada, Warp no desa les finestres i no hi ha `panes`: que un pane no hi sigui
        // no vol dir res, i el que hi ha obert ho diuen els processos.
        let desaFinestres = lectura.warpDesaFinestres != false
        // Els panes de Warp, amb on són («finestra 2 › Botiga»).
        var panes: [String: (pane: PaneLlegit, lloc: String)] = [:]
        for f in lectura.finestres {
            for p in f.pestanyes {
                for pane in p.panes {
                    let titol = p.titol.flatMap { $0.isEmpty ? nil : $0 } ?? (pane.carpeta as NSString).lastPathComponent
                    panes[pane.uuid] = (pane, "finestra \(f.numero) › \(titol)")
                }
            }
        }
        let interactives = lectura.sessionsInteractives
        let perMarca = Dictionary(interactives.compactMap { s in s.marca.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        let perSessio = Dictionary(interactives.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let segonPla = Dictionary(lectura.sessionsNoInteractives.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let terminalPerMarca = Dictionary(lectura.terminals.compactMap { t in t.marca.map { ($0, t) } },
                                          uniquingKeysWith: { a, _ in a })
        let terminalPerPane = Dictionary(lectura.terminals.compactMap { t in t.pane.map { ($0, t) } },
                                         uniquingKeysWith: { a, _ in a })
        let panesRecordats = Set(entrada.estat.pestanyes.values.compactMap(\.pane))
        // També les dels Claude que encara no han escrit la sessió: no surten a `perSessio` (R9).
        let enCurs = entrada.conversesEnCurs.merging(lectura.conversesArrencant) { _, viu in viu }

        /// La conversa més recent de la carpeta (D7) que no sigui viva, ni d'una altra pestanya, ni ja represa en aquest
        /// llançament (R9). `represes` és el que porta el càlcul fins ara.
        func mesRecent(_ pestanya: Pestanya, represes: Set<String>) -> LectorTranscripcions.Recent? {
            entrada.conversesRecents(Rutes.canonica(pestanya.carpeta)).first { conversa in
                guard !represes.contains(conversa.id), perSessio[conversa.id] == nil, segonPla[conversa.id] == nil else { return false }
                if let altra = enCurs[conversa.id], altra != pestanya.id { return false }
                return !entrada.estat.recordadaPerUnaAltra(conversa.id, pestanya: pestanya.id)
            }
        }

        func lloc(_ sessio: SessioClaude) -> String? {
            guard sessio.dinsDeWarp, let pane = sessio.paneUUID else { return nil }
            return panes[pane]?.lloc
        }

        func oberta(_ pestanya: Pestanya) -> OnOberta? {
            if let sessio = perMarca[pestanya.id] {
                // Dins de Warp, amb un pane que ja no hi és: s'acaba de tancar.
                if desaFinestres, sessio.dinsDeWarp, sessio.paneUUID != nil, lloc(sessio) == nil { return .tancadaFaPoc }
                return .marca(lloc: lloc(sessio))
            }
            // Un Claude amb la marca que encara no ha escrit la sessió: acaba d'arrencar o s'ha aturat a preguntar.
            if let terminal = terminalPerMarca[pestanya.id] {
                let pane = terminal.pane.flatMap { panes[$0] }
                if desaFinestres, terminal.pane != nil, pane == nil { return .tancadaFaPoc }
                return .marca(lloc: pane?.lloc)
            }
            let vincle = entrada.estat.pestanyes[pestanya.id]
            if let pane = vincle?.pane {
                if let (llegit, lloc) = panes[pane] { return .pane(lloc: lloc, ambClaude: llegit.claude != nil) }
                if !desaFinestres, let terminal = terminalPerPane[pane] { return .paneViu(ambClaude: terminal.claude) }
            }
            if let id = vincle?.sessio {
                if let sessio = perSessio[id] {
                    if let lloc = lloc(sessio) { return .conversa(lloc: lloc) }
                    guard sessio.dinsDeWarp else { return .conversaForaDeWarp }
                    // Amb un pane que ja no hi és, s'acaba de tancar; sense pane conegut, no se sap on és.
                    return sessio.paneUUID == nil || !desaFinestres ? .conversaAWarp : .tancadaFaPoc
                }
                if let viva = segonPla[id] { return .conversaEnSegonPla(viva.tipus) }
                if let altra = enCurs[id], altra != pestanya.id { return .conversaEnCurs }
            }
            return nil
        }

        var obertes: [PestanyaOberta] = []
        var excloses: [PestanyaExclosa] = []
        var aObrir: [PestanyaAObrir] = []
        var avisos: [AvisObertura] = []
        var represes = entrada.jaRepreses

        for pestanya in finestra.pestanyes {
            if let on = oberta(pestanya) {
                obertes.append(PestanyaOberta(pestanya: pestanya, on: on))
                continue
            }
            func exclou(_ motiu: MotiuExclusio) { excloses.append(PestanyaExclosa(pestanya: pestanya, motiu: motiu)) }
            if pestanya.carpeta.hasPrefix("/"), !entrada.carpetaExisteix(pestanya.carpeta) {
                exclou(.carpetaNoExisteix)
                continue
            }
            let validacio = Validacio.avisos(pestanya, inici: entrada.inici, carpetaExisteix: entrada.carpetaExisteix)
            if let error = validacio.first(where: { $0.gravetat == .error }) {
                exclou(.validacio(error.description))
                continue
            }

            var avisosPestanya = validacio.filter { $0.gravetat == .avis }.map { AvisObertura.Tipus.validacio($0.description) }
            let claude = pestanya.claude.normalitzada()
            var conversa = ConversaObertura.terminal
            if claude.activat {
                let recordada = entrada.estat.conversa(de: pestanya.id)
                if !claude.continua {
                    conversa = .nova(.noContinua)
                } else if let recent = mesRecent(pestanya, represes: represes) {
                    conversa = .repren(recent.id)
                    if recent.id != recordada {
                        avisosPestanya.append(.conversaMesRecent(fa: entrada.ara.timeIntervalSince(recent.darrerMissatge)))
                    }
                } else if let id = recordada {
                    switch entrada.transcripcio(id, Rutes.canonica(pestanya.carpeta)) {
                    case .aLaCarpeta:
                        conversa = .repren(id)
                    case let .altres(projectes) where projectes.count == 1:
                        conversa = .repren(id)
                        avisosPestanya.append(.conversaDUnaAltraCarpeta(projecte: projectes[0]))
                    case let .altres(projectes):
                        conversa = .nova(.enDiversosProjectes)
                        avisosPestanya.append(.conversaEnDiversosProjectes(projectes))
                    case .enlloc:
                        conversa = .nova(.senseTranscripcio)
                        avisosPestanya.append(.senseTranscripcio)
                    }
                } else {
                    conversa = .nova(.senseConversa)
                    avisosPestanya.append(.senseConversa)
                }
                if let id = conversa.repren, represes.contains(id) {
                    conversa = .nova(.repetida)
                    avisosPestanya.removeAll { if case .conversaDUnaAltraCarpeta = $0 { true } else { false } }
                    avisosPestanya.append(.conversaRepetida)
                }
            }

            let argv: [String]?
            do {
                argv = try OrdreClaude.argv(claude, repren: conversa.repren)
            } catch {
                exclou(.ordre(error))
                continue
            }
            let yaml = PestanyaYAML(titol: pestanya.titol, carpeta: pestanya.carpeta,
                                    exec: argv.map {
                                        OrdreClaude.liniaExec($0, pestanya: pestanya.id,
                                                              entorn: claude.enBypass ? entrada.entornClaude : nil)
                                    })
            do {
                try LaunchConfigWarp.comprova(yaml)
            } catch {
                exclou(.fitxer(error))
                continue
            }

            if let id = conversa.repren { represes.insert(id) }
            if argv != nil {
                if entrada.confianca?.confiada(pestanya.carpeta) == false { avisosPestanya.append(.confianca) }
                if OpcionsClaude.analitzaAmbNoms(["claude"] + claude.altres).noms.contains("--fork-session") {
                    avisosPestanya.append(.forkSession)
                }
            }
            let carpeta = Rutes.canonica(pestanya.carpeta)
            if entrada.estat.pestanyes[pestanya.id] == nil, carpeta != entrada.inici {
                if let (_, lloc) = panes.values.filter({ $0.pane.carpeta == carpeta }).min(by: { $0.lloc < $1.lloc }) {
                    avisosPestanya.append(.potserJaOberta(lloc: lloc))
                }
            }
            if !desaFinestres, carpeta != entrada.inici, let viu = lectura.terminals.first(where: { terminal in
                // Un Claude amb marca, o en un pane recordat, és d'una altra pestanya.
                terminal.carpeta == carpeta && (!terminal.claude || (terminal.marca == nil && !panesRecordats.contains(terminal.pane ?? "")))
            }) {
                avisosPestanya.append(.terminalALaCarpeta(ambClaude: viu.claude))
            }
            aObrir.append(PestanyaAObrir(pestanya: pestanya, conversa: conversa, argv: argv, yaml: yaml))
            avisos += avisosPestanya.map { AvisObertura(pestanya: pestanya, tipus: $0) }
        }

        if !desaFinestres, obertes.contains(where: {
            switch $0.on {
            case .marca, .paneViu, .conversaAWarp: true
            default: false
            }
        }) {
            avisos.append(AvisObertura(tipus: .potserTancadaFaPoc(partiria: !aObrir.isEmpty)))
        }
        let sessions = aObrir.filter { $0.argv != nil }.count
        if sessions > moltesSessions { avisos.append(AvisObertura(tipus: .moltesSessions(sessions))) }
        if let darrer = entrada.estat.llancaments.last(where: { $0.finestra == finestra.id }),
           darrer.estat != .confirmat,
           entrada.ara.timeIntervalSince(darrer.creat) < tempsDarrerLlancament {
            let minuts = max(0, Int(entrada.ara.timeIntervalSince(darrer.creat) / 60))
            avisos.append(AvisObertura(tipus: darrer.estat == .error ? .darrerAmbError(minuts: minuts)
                                                                     : .darrerSenseConfirmar(minuts: minuts)))
        }
        return Pla(finestra: finestra, obertes: obertes, excloses: excloses, aObrir: aObrir, avisos: avisos)
    }
}

extension Pestanya {
    /// El nom que es veu al full: el títol o, si és buit, el nom de la carpeta (com a Warp).
    var nomAlFull: String {
        titol.trimmingCharacters(in: .whitespaces).isEmpty ? URL(filePath: carpeta).lastPathComponent : titol
    }
}
