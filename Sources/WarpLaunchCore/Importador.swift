import Foundation

/// De la lectura de Warp a una configuració nova (R2, docs/disseny.md, «Importació»). És una funció pura: no toca el
/// disc, i els id surten de `nouId`. La `inici` ha de ser canònica, com les carpetes de la lectura.
public enum Importador {
    /// Què reben les pestanyes on no hi corria Claude. Les de `~` i les d'una carpeta que no existeix queden sempre
    /// sense Claude (D11).
    public enum SenseSessio: Sendable, Equatable {
        /// Una configuració nova: només terminal (D-P5a, en David, 07/11/2026). Si s'hi activa Claude, ja té les opcions
        /// de la plantilla.
        case nomesTerminal
        /// Tornar a importar sobre una configuració que ja existeix: Claude, amb la plantilla (D11).
        case plantilla
    }

    public static func importa(_ lectura: LecturaWarp, inici: String, plantilla: ClaudePestanya,
                               senseSessio: SenseSessio, nouId: () -> UUID) -> Importacio {
        let plantilla = plantilla.normalitzada()
        // La de cada pestanya, sense nom fix de sessió (decisió d'en David, 04/11/2026): si no, totes les pestanyes
        // importades sense sessió s'obririen amb el mateix nom. La de la configuració es queda tal com és.
        let perPestanya = plantilla.perAPestanyaNova()
        var finestres: [Finestra] = []
        var origens: [UUID: OrigenClaude] = [:]
        var vincles: [UUID: VincleImportat] = [:]
        var notes: [NotaImportacio] = []
        var nomsUsats = Set<String>()

        for (f, llegida) in lectura.finestres.enumerated() {
            var pestanyes: [Pestanya] = []
            var notesFinestra: [(pestanya: Int, nota: (Lloc) -> NotaImportacio)] = []

            for (p, pestanyaWarp) in llegida.pestanyes.enumerated() {
                guard let principal = pestanyaWarp.panes.first(where: { $0.claude != nil }) ?? pestanyaWarp.panes.first
                else { continue }
                var carpeta = principal.carpeta
                let claude: ClaudePestanya
                let origen: OrigenClaude
                let n = pestanyes.count

                if let sessio = principal.claude {
                    var c = ClaudePestanya(sessio.opcions)
                    c.continua = true  // R4: les sessions vives es tornen a obrir continuant
                    claude = c
                    origen = .sessio
                    // A `~`, Warp probablement ha perdut la carpeta: la de la sessió és la bona. Si no, mana la de la
                    // pestanya (el shell no es mou mentre Claude hi corre, i el `cwd` de la sessió potser segueix els
                    // `cd` de Claude), però es diu.
                    if sessio.carpeta != principal.carpeta {
                        if principal.carpeta == inici {
                            carpeta = sessio.carpeta
                            notesFinestra.append((n, { .carpetaDeLaSessio($0, pestanya: principal.carpeta, sessio: sessio.carpeta) }))
                        } else {
                            notesFinestra.append((n, { .carpetesDiferents($0, pestanya: principal.carpeta, sessio: sessio.carpeta) }))
                        }
                    }
                    if !sessio.opcions.prompt.isEmpty {
                        let missatge = sessio.opcions.prompt.joined(separator: " ")
                        notesFinestra.append((n, { .primerMissatgeDescartat($0, missatge: missatge) }))
                    }
                    if let repren = sessio.opcions.repren, !repren.isEmpty {
                        notesFinestra.append((n, { .sessioConcreta($0, opcio: "--resume") }))
                    } else if sessio.opcions.idSessio != nil {
                        notesFinestra.append((n, { .sessioConcreta($0, opcio: "--session-id") }))
                    }
                } else if carpeta == inici {
                    claude = desactivada(perPestanya)
                    origen = .carpetaInici
                } else if !principal.carpetaExisteix {
                    claude = desactivada(perPestanya)
                    origen = .carpetaNoExisteix
                } else if senseSessio == .nomesTerminal {
                    claude = desactivada(perPestanya)
                    origen = .nomesTerminal
                } else {
                    claude = perPestanya
                    origen = .plantilla
                }

                if pestanyaWarp.panes.count > 1 {
                    let ambClaude = pestanyaWarp.panes.filter { $0.claude != nil }.count
                    let perduts = ambClaude - (principal.claude == nil ? 0 : 1)
                    notesFinestra.append((n, { .panesDescartats($0, panes: pestanyaWarp.panes.count, sessions: perduts) }))
                }

                let id = nouId()
                origens[id] = origen
                vincles[id] = VincleImportat(pane: principal.uuid, sessio: principal.claude?.sessionId,
                                             carpetaSessio: principal.claude?.carpeta)
                pestanyes.append(Pestanya(id: id, titol: titol(pestanyaWarp.titol, carpeta: carpeta, inici: inici, numero: p + 1),
                                          carpeta: carpeta, claude: claude))
            }

            // Una finestra només amb pestanyes que no són de terminal (Settings…) no té res per tornar a obrir.
            guard !pestanyes.isEmpty else {
                notes.append(.finestraSensePestanyes(numero: f + 1))
                continue
            }
            let nom = unic(nomDeFinestra(pestanyes.map(\.carpeta), inici: inici) ?? "Finestra \(f + 1)", usats: &nomsUsats)
            let finestra = Finestra(id: nouId(), nom: nom, pestanyes: pestanyes)
            for (p, nota) in notesFinestra {
                notes.append(nota(Lloc(pestanya: pestanyes[p].id, text: "\(nom) › \(pestanyes[p].titol)")))
            }
            finestres.append(finestra)
        }

        // Una sessió que no s'ha pogut lligar (dins de tmux, o una pestanya que Warp encara no ha desat) pot ser d'una
        // pestanya que s'ha importat sense les seves opcions, o només terminal (en una configuració nova, D-P5a): es diu
        // quina és a la mateixa carpeta.
        for sessio in lectura.sessionsSensePestanya {
            let mateixaCarpeta = finestres.flatMap { f in
                f.pestanyes.filter { $0.carpeta == sessio.carpeta && origens[$0.id] != .sessio }
                    .map { (ambClaude: $0.claude.activat, text: "\(f.nom) › \($0.titol)") }
            }
            notes.append(.sessioSensePestanya(carpeta: sessio.carpeta, nom: sessio.nom, dinsDeWarp: sessio.dinsDeWarp,
                                              pestanyes: mateixaCarpeta.filter(\.ambClaude).map(\.text),
                                              terminals: mateixaCarpeta.filter { !$0.ambClaude }.map(\.text)))
        }
        // Les pestanyes de les finestres descartades no hi són.
        let ids = Set(finestres.flatMap(\.pestanyes).map(\.id))
        return Importacio(configuracio: Configuracio(plantilla: plantilla, finestres: finestres), origens: origens,
                          notes: notes, vincles: vincles.filter { ids.contains($0.key) })
    }

    /// La plantilla, però sense Claude: a `~` o a una carpeta que no existeix, Claude no s'obre fins que se n'arregli la
    /// carpeta (D11); i, en una configuració nova, on no hi corria (D-P5a). En activar-lo, ja té les opcions de la
    /// plantilla.
    private static func desactivada(_ plantilla: ClaudePestanya) -> ClaudePestanya {
        var c = plantilla
        c.activat = false
        return c
    }

    /// El títol de Warp; si no n'hi ha, l'últim component de la carpeta; i si la carpeta és `~` o `/`, «Pestanya N».
    static func titol(_ deWarp: String?, carpeta: String, inici: String, numero: Int) -> String {
        if let deWarp, !deWarp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return deWarp }
        let darrer = (carpeta as NSString).lastPathComponent
        if carpeta == inici || darrer.isEmpty || darrer == "/" { return "Pestanya \(numero)" }
        return darrer
    }

    /// La carpeta pare que reuneix més de la meitat de les pestanyes, sense comptar les de `~`. La carpeta d'inici i
    /// l'arrel no serveixen de nom (no agrupen res).
    static func nomDeFinestra(_ carpetes: [String], inici: String) -> String? {
        let compten = carpetes.filter { $0 != inici }
        guard !compten.isEmpty else { return nil }
        var perPare: [String: Int] = [:]
        for carpeta in compten { perPare[(carpeta as NSString).deletingLastPathComponent, default: 0] += 1 }
        guard let (pare, quantes) = perPare.max(by: { $0.value < $1.value }), quantes * 2 > compten.count,
              pare != inici, pare != "/", !pare.isEmpty
        else { return nil }
        return (pare as NSString).lastPathComponent
    }

    /// `nom`, o `nom 2`, `nom 3`… si ja s'ha fet servir (sense distingir majúscules, com la validació).
    private static func unic(_ nom: String, usats: inout Set<String>) -> String {
        var candidat = nom
        var n = 2
        while usats.contains(Validacio.clauDeNom(candidat)) {
            candidat = "\(nom) \(n)"
            n += 1
        }
        usats.insert(Validacio.clauDeNom(candidat))
        return candidat
    }
}

/// La configuració que surt d'importar, i el que se n'ha de dir abans de desar-la.
public struct Importacio: Sendable, Equatable {
    public var configuracio: Configuracio
    /// D'on surt el Claude de cada pestanya (per id).
    public var origens: [UUID: OrigenClaude]
    public var notes: [NotaImportacio]
    /// El pane de cada pestanya, i la seva conversa si hi corria Claude: per a `estat.json` (fase 3.1).
    public var vincles: [UUID: VincleImportat] = [:]

    public var resum: ResumImportacio {
        let pestanyes = configuracio.finestres.flatMap(\.pestanyes)
        let ambClaude = pestanyes.filter(\.claude.activat)
        return ResumImportacio(
            finestres: configuracio.finestres.count, pestanyes: pestanyes.count,
            ambSessio: ambClaude.filter { origens[$0.id] == .sessio }.count,
            ambPlantilla: ambClaude.filter { origens[$0.id] == .plantilla }.count,
            senseClaude: pestanyes.count - ambClaude.count,
            senseClaudeObert: pestanyes.filter { origens[$0.id] == .nomesTerminal }.count,
            saltenPermisos: ambClaude.filter(\.claude.saltaPermisos).count)
    }
}

/// D'on surten les opcions de Claude d'una pestanya importada.
public enum OrigenClaude: String, Sendable, Equatable {
    /// Hi corria una sessió: les opcions de la seva ordre.
    case sessio
    /// No hi corria Claude, i es torna a importar: la plantilla (D11).
    case plantilla
    /// No hi corria Claude, i la configuració és nova: només terminal (D-P5a).
    case nomesTerminal
    /// A `~`: sense Claude (probablement Warp ha perdut la carpeta).
    case carpetaInici
    /// La carpeta ja no existeix: sense Claude.
    case carpetaNoExisteix
}

/// On és una pestanya importada: el seu id i «finestra › pestanya», per dir-ho.
public struct Lloc: Sendable, Equatable {
    public var pestanya: UUID
    public var text: String
}

/// Coses de la importació que en David ha de saber abans de desar-la.
public enum NotaImportacio: Sendable, Equatable, CustomStringConvertible {
    /// La sessió es va obrir amb un primer missatge. No es desa: s'enviaria a cada obertura.
    case primerMissatgeDescartat(Lloc, missatge: String)
    /// La sessió reprenia una conversa concreta (`--resume <id>`) o tenia `--session-id`. Només es desa que continua.
    case sessioConcreta(Lloc, opcio: String)
    /// La pestanya és a `~` i la sessió en una altra carpeta: es fa servir la de la sessió.
    case carpetaDeLaSessio(Lloc, pestanya: String, sessio: String)
    /// La sessió diu una carpeta diferent de la de la pestanya (que no és `~`): es fa servir la de la pestanya.
    case carpetesDiferents(Lloc, pestanya: String, sessio: String)
    /// Pestanya dividida: només s'importa el pane principal (el primer amb Claude, o el primer).
    case panesDescartats(Lloc, panes: Int, sessions: Int)
    /// Una sessió de Claude que no és a cap pestanya de Warp. No s'importa. De les importades sense les opcions d'una
    /// sessió que són a la mateixa carpeta («finestra › pestanya»), `pestanyes` són les que obren Claude (amb la
    /// plantilla) i `terminals`, les que queden només terminal (a `~`, o en una configuració nova, D-P5a).
    case sessioSensePestanya(carpeta: String, nom: String?, dinsDeWarp: Bool, pestanyes: [String], terminals: [String])
    /// Una finestra de Warp sense pestanyes de terminal (la `numero`-èsima de la lectura). No s'importa.
    case finestraSensePestanyes(numero: Int)

    public var lloc: Lloc? {
        switch self {
        case let .primerMissatgeDescartat(lloc, _), let .sessioConcreta(lloc, _), let .carpetaDeLaSessio(lloc, _, _),
             let .carpetesDiferents(lloc, _, _), let .panesDescartats(lloc, _, _):
            lloc
        case .sessioSensePestanya, .finestraSensePestanyes: nil
        }
    }

    public var description: String {
        switch self {
        case let .primerMissatgeDescartat(lloc, missatge):
            let curt = missatge.count > 60 ? missatge.prefix(59) + "…" : Substring(missatge)
            return "\(lloc.text): la sessió es va obrir amb el missatge «\(curt)»; no es desa (s'enviaria a cada obertura)"
        case let .sessioConcreta(lloc, opcio):
            return "\(lloc.text): la sessió es va obrir amb «\(opcio)» (una conversa concreta); es desa només que continua"
        case let .carpetaDeLaSessio(lloc, pestanya, sessio):
            return "\(lloc.text): Warp diu «\(pestanya)», però Claude corre a «\(sessio)»; es fa servir la de Claude"
        case let .carpetesDiferents(lloc, pestanya, sessio):
            return "\(lloc.text): Warp diu «\(pestanya)» i Claude «\(sessio)»; es fa servir la de Warp (comprova-ho)"
        case let .panesDescartats(lloc, panes, sessions):
            let perdudes = sessions == 0 ? "" : ", i es perd \(Plural.compta(sessions, "sessió", "sessions")) de Claude"
            return "\(lloc.text): pestanya dividida en \(panes) panes; només s'importa el principal\(perdudes)"
        case let .sessioSensePestanya(carpeta, nom, dinsDeWarp, pestanyes, terminals):
            let qui = nom.map { "«\($0)» " } ?? ""
            let on = dinsDeWarp ? "la seva pestanya no és a la base de Warp" : "corre fora de Warp, o dins de tmux"
            func llista(_ p: [String], _ un: String, _ diverses: String) -> String? {
                p.isEmpty ? nil : p.map { "«\($0)»" }.joined(separator: ", ") + ", " + (p.count == 1 ? un : diverses)
            }
            let parts = [llista(pestanyes, "que no porta les seves opcions", "que no porten les seves opcions"),
                         llista(terminals, "que queda només terminal", "que queden només terminal")].compactMap { $0 }
            let mateixa = parts.isEmpty ? "" : "; a la mateixa carpeta hi ha " + parts.joined(separator: "; i ")
            return "sessió de Claude \(qui)a «\(carpeta)»: no s'importa (\(on))\(mateixa)"
        case let .finestraSensePestanyes(numero):
            return "la finestra \(numero) de Warp no té cap pestanya de terminal: no s'importa"
        }
    }
}

/// Xifres de la importació, per al full de previsualització i el CLI.
public struct ResumImportacio: Sendable, Equatable {
    public var finestres: Int
    public var pestanyes: Int
    /// Pestanyes amb Claude que surten de la seva ordre.
    public var ambSessio: Int
    /// Pestanyes amb Claude que surten de la plantilla.
    public var ambPlantilla: Int
    /// Pestanyes només terminal: les de `~`, les d'una carpeta que no existeix, les de `senseClaudeObert` i, si la
    /// plantilla no obre Claude, les que la prenen.
    public var senseClaude: Int
    /// D'aquestes, les que no tenien Claude obert, en una configuració nova (D-P5a). En tornar a importar, sempre 0:
    /// aquestes pestanyes prenen la plantilla (`ambPlantilla`).
    public var senseClaudeObert: Int
    /// Pestanyes amb Claude que salten els permisos (`--dangerously-skip-permissions`).
    public var saltenPermisos: Int

    public init(finestres: Int, pestanyes: Int, ambSessio: Int, ambPlantilla: Int, senseClaude: Int,
                senseClaudeObert: Int, saltenPermisos: Int) {
        self.finestres = finestres
        self.pestanyes = pestanyes
        self.ambSessio = ambSessio
        self.ambPlantilla = ambPlantilla
        self.senseClaude = senseClaude
        self.senseClaudeObert = senseClaudeObert
        self.saltenPermisos = saltenPermisos
    }

    /// En tornar a importar, «4 finestres · 30 pestanyes · 24 amb Claude (6 amb la seva ordre, 18 amb la plantilla) ·
    /// 6 només terminal». En una configuració nova, la plantilla no hi surt: «4 finestres · 30 pestanyes · 6 amb
    /// Claude, amb la seva ordre · 24 només terminal (18 sense Claude obert)» (D-P5a).
    public var descripcio: String {
        let finestresIPestanyes = "\(Plural.compta(finestres, "finestra", "finestres")) · "
            + Plural.compta(pestanyes, "pestanya", "pestanyes")
        guard senseClaudeObert > 0, ambPlantilla == 0 else {
            return finestresIPestanyes
                + " · \(ambSessio + ambPlantilla) amb Claude (\(ambSessio) amb la seva ordre, \(ambPlantilla) amb la plantilla)"
                + " · \(senseClaude) només terminal"
        }
        return finestresIPestanyes + (ambSessio == 0 ? " · 0 amb Claude" : " · \(ambSessio) amb Claude, amb la seva ordre")
            + " · \(senseClaude) només terminal (\(senseClaudeObert) sense Claude obert)"
    }
}
