import Foundation

/// Avisos de la configuració (docs/disseny.md, «Avisos»). És una funció pura: si la carpeta existeix ho diu
/// `carpetaExisteix`, que l'app i el CLI fan mirar al disc i les proves, a una llista.
public enum Validacio {
    public static func avisos(_ pestanya: Pestanya, inici: String, carpetaExisteix: (String) -> Bool) -> [Avis] {
        var avisos: [Avis] = []
        let carpeta = pestanya.carpeta
        let carpetaValida: Bool
        if !carpeta.hasPrefix("/") {
            avisos.append(Avis(.carpetaNoAbsoluta))
            carpetaValida = false
        } else if (carpeta as NSString).standardizingPath == (inici as NSString).standardizingPath {
            avisos.append(Avis(.carpetaInici))
            carpetaValida = false
        } else if !carpetaExisteix(carpeta) {
            avisos.append(Avis(.carpetaNoExisteix))
            carpetaValida = false
        } else {
            carpetaValida = true
        }

        guard pestanya.claude.activat else {
            // Una pestanya importada a `~` o a una carpeta perduda queda sense Claude; quan la carpeta ja és bona, l'app
            // ofereix «Activa Claude», però no l'activa sola (decisió d'en David).
            if carpetaValida { avisos.append(Avis(.claudeApagat)) }
            return avisos
        }
        return avisos + Self.avisos(claude: pestanya.claude)
    }

    /// L'avís de la carpeta de Claude (decisió d'en David del 09/11/2026): a «Per revisar», mentre l'app ho sàpiga.
    /// - `carpetaWarp`: la que té la foto de Warp per al pane de la pestanya, si se sap i no coincideix amb la de Claude. Si és
    ///   `~`, Warp l'ha perduda i no avisa. Només hi és a la memòria de l'app, perquè el format d'`estat.json` no canvia
    ///   (`EstatSessions`).
    /// - `vincle.carpetaSessio`: la de l'últim Claude de la pestanya. Sobreviu als reinicis: si no és la de la pestanya (una
    ///   configuració d'abans de la 0.31.5, per exemple), també avisa.
    public static func avisCarpetaDeClaude(_ pestanya: Pestanya, vincle: VincleEstat?, carpetaWarp: String?, inici: String,
                                           carpetaExisteix: (String) -> Bool) -> Avis? {
        // Una pestanya només terminal no obre Claude: on hi hagi corregut no s'ha de revisar.
        guard pestanya.claude.activat, let claude = vincle?.carpetaSessio else { return nil }
        let actual = Rutes.canonica(pestanya.carpeta)
        if let carpetaWarp, carpetaWarp != claude, carpetaWarp != inici, actual == claude || actual == carpetaWarp {
            return Avis(.carpetesDiferents(warp: carpetaWarp, claude: claude, actual: actual))
        }
        guard claude != inici, claude != actual, carpetaExisteix(claude) else { return nil }
        return Avis(.carpetesDiferents(warp: nil, claude: claude, actual: actual))
    }

    /// Els avisos de la plantilla (la Configuració). Amb Claude apagat, cap: les pestanyes noves només serien un
    /// terminal. No compten a «Per revisar» ni al subtítol de l'editor.
    public static func avisos(plantilla: ClaudePestanya) -> [Avis] {
        plantilla.activat ? avisos(claude: plantilla) : []
    }

    /// Els avisos de les opcions de Claude, encès: els de la pestanya després dels de la carpeta, i els de la plantilla.
    static func avisos(claude: ClaudePestanya) -> [Avis] {
        var avisos: [Avis] = []
        let c = claude.normalitzada()
        if let esforc = c.esforc, !ClaudePestanya.esforcosConeguts.contains(esforc) {
            avisos.append(Avis(.esforcDesconegut(esforc)))
        }
        if let mode = c.modePermisos {
            if !ClaudePestanya.modesPermisos.contains(mode) { avisos.append(Avis(.modePermisosDesconegut(mode))) }
            if c.saltaPermisos { avisos.append(Avis(.saltaPermisosAmbMode(mode))) }
        }
        let settingsMalmesos = c.settings.map { SettingsClaude.esJSON($0) && !SettingsClaude.esValid($0) } ?? false
        if settingsMalmesos { avisos.append(Avis(.settingsNoJSON)) }

        if !c.altres.isEmpty {
            let analisi = OpcionsClaude.analitzaAmbNoms(["claude"] + c.altres)
            if !analisi.opcions.desconegudes.isEmpty {
                avisos.append(Avis(.opcionsDesconegudes(analisi.opcions.desconegudes, textos: analisi.textosDesconeguts)))
            }
            let dUnSolUs = analisi.noms.filter(opcionsDUnSolUs.contains)
            if !dUnSolUs.isEmpty { avisos.append(Avis(.opcionsDUnSolUs(dUnSolUs))) }
        }

        do {
            _ = try OrdreClaude.argv(c, repren: nil)
        } catch .settingsNoEsJSON where settingsMalmesos {
            // Ja ho diu l'avís dels settings.
        } catch {
            avisos.append(Avis(.ordreImpossible(error)))
        }
        if c.ultracode { avisos.append(Avis(.ultracode)) }
        return avisos
    }

    /// Els avisos de totes les finestres i pestanyes, per id.
    public static func avisos(_ configuracio: Configuracio, inici: String,
                              carpetaExisteix: (String) -> Bool) -> AvisosConfiguracio {
        var resultat = AvisosConfiguracio()
        var perNom: [String: Int] = [:]
        for finestra in configuracio.finestres { perNom[clauDeNom(finestra.nom), default: 0] += 1 }
        for finestra in configuracio.finestres {
            let clau = clauDeNom(finestra.nom)
            if !clau.isEmpty, perNom[clau, default: 0] > 1 { resultat.finestres[finestra.id] = [Avis(.nomRepetit(finestra.nom))] }
            for pestanya in finestra.pestanyes {
                let avisos = avisos(pestanya, inici: inici, carpetaExisteix: carpetaExisteix)
                if !avisos.isEmpty { resultat.pestanyes[pestanya.id] = avisos }
            }
        }
        return resultat
    }

    /// Si una carpeta existeix al disc (i és una carpeta). Per a l'app i el CLI; les proves no la fan servir.
    public static func carpetaExisteixAlDisc(_ ruta: String) -> Bool {
        var esCarpeta: ObjCBool = false
        return FileManager.default.fileExists(atPath: ruta, isDirectory: &esCarpeta) && esCarpeta.boolValue
    }

    /// Dos noms de finestra són el mateix si només canvien les majúscules o els espais dels extrems.
    static func clauDeNom(_ nom: String) -> String {
        nom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Opcions de Claude Code que fan una cosa que només s'ha de fer un cop: a cada obertura en tornarien a fer una
    /// (un worktree, una branca de la conversa, una PR, rebobinar fitxers…). Noms llargs de `TaulaOpcionsClaude`.
    static let opcionsDUnSolUs: Set<String> = [
        "--worktree", "--fork-session", "--from-pr", "--teleport", "--resume-session-at", "--rewind-files", "--prefill",
        "--prefill-b64",
    ]
}

/// Un avís d'una pestanya o d'una finestra. Sempre amb text (la interfície hi posa la icona).
public struct Avis: Sendable, Equatable, CustomStringConvertible {
    public enum Gravetat: Int, Sendable, Comparable {
        /// Només a l'inspector: res no va malament.
        case info
        /// Triangle a la fila: la pestanya s'obrirà, però potser no com s'espera.
        case avis
        /// La pestanya no es pot obrir com diu la configuració (no hi ha ordre, o Claude s'aturaria amb un error).
        case error

        public static func < (a: Gravetat, b: Gravetat) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Tipus: Sendable, Equatable {
        case carpetaNoAbsoluta
        case carpetaInici
        case carpetaNoExisteix
        /// Claude apagat i la carpeta ja és bona: l'inspector ofereix «Activa Claude».
        case claudeApagat
        /// Warp i Claude no coincideixen (`Validacio.avisCarpetaDeClaude`). `warp`, si la foto de Warp ho diu.
        case carpetesDiferents(warp: String?, claude: String, actual: String)
        case ultracode
        case esforcDesconegut(String)
        case modePermisosDesconegut(String)
        case saltaPermisosAmbMode(String)
        case settingsNoJSON
        /// `textos`: els que segueixen les opcions desconegudes. Si no en són el valor, són el primer missatge.
        case opcionsDesconegudes([String], textos: [String])
        case opcionsDUnSolUs([String])
        case ordreImpossible(OrdreClaude.ErrorOrdre)
        case nomRepetit(String)
    }

    public var tipus: Tipus

    public init(_ tipus: Tipus) { self.tipus = tipus }

    public var gravetat: Gravetat {
        switch tipus {
        case .claudeApagat, .ultracode: .info
        case .carpetaNoAbsoluta, .carpetaInici, .carpetaNoExisteix, .carpetesDiferents, .esforcDesconegut, .saltaPermisosAmbMode,
             .opcionsDesconegudes, .opcionsDUnSolUs, .nomRepetit:
            .avis
        case .modePermisosDesconegut, .settingsNoJSON, .ordreImpossible: .error
        }
    }

    public var description: String {
        switch tipus {
        case .carpetaNoAbsoluta: "La carpeta ha de ser una ruta absoluta"
        case .carpetaInici: "Carpeta d'inici: probablement Warp l'ha perduda"
        case .carpetaNoExisteix: "La carpeta no existeix"
        case .claudeApagat: "Claude és apagat en aquesta pestanya"
        case let .carpetesDiferents(warp?, claude, actual):
            "Warp diu «\(warp)» i Claude corre a «\(claude)»: es fa servir la de "
                + (actual == claude ? "Claude" : "Warp") + " (comprova-ho)"
        case let .carpetesDiferents(nil, claude, _):
            "L'últim Claude d'aquesta pestanya corria a «\(claude)», no a aquesta carpeta (comprova-ho)"
        case .ultracode: "Comprova que el model admet ultracode i que tens els dynamic workflows activats"
        case let .esforcDesconegut(esforc):
            "Esforç «\(esforc)» desconegut: Claude el deixa córrer i fa servir el de per defecte"
        case let .modePermisosDesconegut(mode):
            "Claude no arrencarà: el mode de permisos «\(mode)» no existeix ("
                + ClaudePestanya.modesPermisos.joined(separator: ", ") + ")"
        case let .saltaPermisosAmbMode(mode): "Amb «Salta els permisos», Claude no fa cas del mode «\(mode)»"
        case .settingsNoJSON: "Claude no arrencarà: els settings no són JSON vàlid"
        case let .opcionsDesconegudes(opcions, textos):
            "Claude \(TaulaOpcionsClaude.versio) no coneix " + llista(opcions)
                + ": potser no l'entén (si és d'una versió nova, cal posar al dia la taula d'opcions)"
                + (textos.isEmpty ? "" : ". Si " + llista(textos)
                    + " no n'és el valor, Claude el prendria pel primer missatge i l'enviaria a cada obertura")
        case let .opcionsDUnSolUs(opcions): llista(opcions) + " és d'un sol ús: es tornaria a fer a cada obertura"
        case let .ordreImpossible(error): "No es pot generar l'ordre: \(error)"
        case let .nomRepetit(nom): "Hi ha més d'una finestra amb el nom «\(nom)»"
        }
    }

    private func llista(_ opcions: [String]) -> String {
        var vistes = Set<String>()
        return opcions.filter { vistes.insert($0).inserted }.map { "«\($0)»" }.joined(separator: ", ")
    }
}

/// Avisos de tota la configuració, per id de finestra i de pestanya (només els que en tenen).
public struct AvisosConfiguracio: Sendable, Equatable {
    public var finestres: [UUID: [Avis]] = [:]
    public var pestanyes: [UUID: [Avis]] = [:]

    public init() {}

    public var tots: [Avis] { finestres.values.flatMap { $0 } + pestanyes.values.flatMap { $0 } }

    /// Quants n'hi ha d'una gravetat.
    public func compta(_ gravetat: Avis.Gravetat) -> Int { tots.filter { $0.gravetat == gravetat }.count }
}
