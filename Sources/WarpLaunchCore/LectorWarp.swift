import Foundation
import SQLite3

/// Un pane de terminal tal com és a `warp.sqlite`.
public struct PaneWarp: Sendable, Equatable {
    public var uuid: String
    public var cwd: String?
    /// Carpeta de l'última comanda d'aquest pane a l'historial (`blocks.pwd`).
    public var darrerPwd: String?
}

public struct PestanyaWarp: Sendable, Equatable {
    public var posicio: Int
    public var titol: String?
    public var color: String?
    public var panes: [PaneWarp]
}

public struct FinestraWarp: Sendable, Equatable {
    public var numero: Int
    public var pestanyaActiva: Int
    public var pestanyes: [PestanyaWarp]
}

public enum ErrorLectura: Error, Equatable, CustomStringConvertible {
    case noHiHaBase(String)
    case sqlite(String)
    /// macOS no deixa obrir el fitxer: les dades de Warp són d'una altra app, i macOS 27 ho bloqueja sense
    /// preguntar. `open()` torna EPERM, i la SQLite d'Apple el dona com a `SQLITE_AUTH` («authorization denied»).
    /// No fem servir cap autoritzador de SQLite, així que aquest codi només pot venir d'aquí.
    case macOSNoDeixaLlegir

    public var description: String {
        switch self {
        case .noHiHaBase(let ruta): t("no trobo la base de Warp: \(ruta)")
        case .sqlite(let missatge): t("error de SQLite: \(missatge)")
        case .macOSNoDeixaLlegir:
            t("macOS no deixa que Warp Launch llegeixi les dades de Warp; cal donar-li permís a Configuració del Sistema › Privacitat i seguretat")
        }
    }

    /// L'error d'un codi de SQLite.
    static func de(codi: Int32, missatge: String) -> ErrorLectura {
        codi & 0xff == SQLITE_AUTH ? .macOSNoDeixaLlegir : .sqlite(missatge)
    }

    /// L'error de la darrera operació d'una connexió.
    static func de(_ db: OpaquePointer?) -> ErrorLectura {
        guard let db else { return .sqlite(t("no s'ha pogut obrir")) }
        return de(codi: sqlite3_errcode(db), missatge: String(cString: sqlite3_errmsg(db)))
    }
}

/// Llegeix finestres, pestanyes i panes de `warp.sqlite`.
/// **Només lectura:** obre la base amb `SQLITE_OPEN_READONLY`, perquè Warp l'escriu en calent.
public struct LectorWarp: Sendable {
    public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite")

    public var ruta: URL

    /// Sense valor per defecte, com `LectorSessions`: una prova que se l'oblidés llegiria el `warp.sqlite` de debò, i cap
    /// guarda de línia no ho veuria (el valor per defecte no surt a la crida). L'app i el CLI hi posen `rutaPerDefecte`, al
    /// seu `Lector`.
    public init(ruta: URL) {
        self.ruta = ruta
    }

    /// Una taula de `warp.sqlite` i les columnes que se'n llegeixen.
    public struct TaulaLlegida: Sendable, Equatable {
        public var nom: String
        public var columnes: [String]
        /// Sense, la lectura continua: només es perd alguna dada (`blocks`: la carpeta de l'última comanda).
        public var opcional: Bool
    }

    /// Les taules i columnes que llegeix `llegeixTaules` (Warp 0.2026.10.21). El diagnòstic les busca a la base per dir si
    /// Warp l'ha canviada; una prova comprova que una base amb només aquestes es llegeix sencera.
    public static let esquema: [TaulaLlegida] = [
        TaulaLlegida(nom: "windows", columnes: ["id", "active_tab_index"], opcional: false),
        TaulaLlegida(nom: "tabs", columnes: ["id", "window_id", "custom_title", "color"], opcional: false),
        TaulaLlegida(nom: "pane_nodes", columnes: ["id", "tab_id", "is_leaf"], opcional: false),
        TaulaLlegida(nom: "pane_leaves", columnes: ["pane_node_id", "kind"], opcional: false),
        TaulaLlegida(nom: "terminal_panes", columnes: ["id", "uuid", "cwd"], opcional: false),
        TaulaLlegida(nom: "blocks", columnes: ["pane_leaf_uuid", "pwd", "start_ts"], opcional: true),
    ]

    public func llegeix() throws -> [FinestraWarp] {
        try ambConnexio { db in
            // Una sola transacció: totes les consultes veuen el mateix desat de Warp,
            // que renumera finestres i pestanyes cada vegada que desa.
            try executa(db, "BEGIN")
            // Les sentències viuen dins de `llegeixTaules` i ja estan finalitzades quan es tanca la transacció.
            let resultat = Result { try llegeixTaules(db) }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            return try resultat.get()
        }
    }

    /// Les taules i columnes d'`esquema` que no són a la base (`taula`, o `taula.columna`), les obligatòries i les
    /// opcionals, per al diagnòstic. Només llegeix l'esquema (`PRAGMA table_info`), en només lectura com `llegeix`.
    public func queFalta() throws -> (obligatories: [String], opcionals: [String]) {
        try ambConnexio { db in
            var obligatories: [String] = []
            var opcionals: [String] = []
            for taula in Self.esquema {
                // Els noms són els d'`esquema`, fixos: no venen de fora.
                let consulta = try Sentencia(db, "PRAGMA table_info(\(taula.nom))")
                var columnes = Set<String>()
                while try consulta.seguent() {
                    if let nom = consulta.text(1) { columnes.insert(nom) }
                }
                let falten = columnes.isEmpty ? [taula.nom] : taula.columnes.filter { !columnes.contains($0) }
                    .map { "\(taula.nom).\($0)" }
                if taula.opcional { opcionals += falten } else { obligatories += falten }
            }
            return (obligatories, opcionals)
        }
    }

    /// Obre la base en només lectura i hi fa `cos`.
    private func ambConnexio<T>(_ cos: (OpaquePointer) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: ruta.path) else { throw ErrorLectura.noHiHaBase(ruta.path) }
        do {
            return try ambConnexio(immutable: false, cos)
        } catch where !FileManager.default.fileExists(atPath: ruta.path + "-shm") {
            // SQLite no pot obrir en només lectura una base WAL sense el fitxer -shm. Sense -shm no hi ha cap
            // connexió que hi escrigui (Warp el crea mentre la té oberta), així que es pot llegir com a
            // immutable: sense bloquejos i sense crear cap fitxer.
            return try ambConnexio(immutable: true, cos)
        }
    }

    private func ambConnexio<T>(immutable: Bool, _ cos: (OpaquePointer) throws -> T) throws -> T {
        var connexio: OpaquePointer?
        let (nom, opcions) = immutable
            ? (ruta.absoluteString + "?immutable=1", SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
            : (ruta.path, SQLITE_OPEN_READONLY)
        guard sqlite3_open_v2(nom, &connexio, opcions, nil) == SQLITE_OK, let db = connexio else {
            let error = ErrorLectura.de(connexio)
            sqlite3_close(connexio)
            throw error
        }
        // close_v2: si quedés alguna sentència viva, la connexió es tancaria en finalitzar-la.
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 3000)
        return try cos(db)
    }

    private func llegeixTaules(_ db: OpaquePointer) throws -> [FinestraWarp] {
        // Posició de cada pestanya dins de la seva finestra, comptant-les totes.
        var posicions: [Int: Int] = [:]
        var comptador: [Int: Int] = [:]
        let pestanyes = try Sentencia(db, "SELECT id, window_id FROM tabs ORDER BY window_id, id")
        while try pestanyes.seguent() {
            let finestra = pestanyes.enter(1)
            posicions[pestanyes.enter(0)] = comptador[finestra, default: 0]
            comptador[finestra, default: 0] += 1
        }

        var finestres: [FinestraWarp] = []
        var indexFinestra: [Int: Int] = [:]
        let consultaFinestres = try Sentencia(db, "SELECT id, active_tab_index FROM windows ORDER BY id")
        while try consultaFinestres.seguent() {
            indexFinestra[consultaFinestres.enter(0)] = finestres.count
            finestres.append(FinestraWarp(numero: consultaFinestres.enter(0),
                                          pestanyaActiva: consultaFinestres.enter(1), pestanyes: []))
        }

        let historial = try existeixTaula(db, "blocks")
            ? """
              (SELECT b.pwd FROM blocks b WHERE b.pane_leaf_uuid = p.uuid AND b.pwd IS NOT NULL AND b.pwd <> ''
               ORDER BY b.start_ts DESC LIMIT 1)
              """
            : "NULL"
        let panes = try Sentencia(db, """
            SELECT t.window_id, t.id, t.custom_title, t.color, lower(hex(p.uuid)), p.cwd, \(historial)
            FROM tabs t
            JOIN pane_nodes n ON n.tab_id = t.id AND n.is_leaf
            JOIN pane_leaves l ON l.pane_node_id = n.id AND l.kind = 'terminal'
            JOIN terminal_panes p ON p.id = n.id
            ORDER BY t.window_id, t.id, n.id
            """)
        var pestanyaActual: (finestra: Int, id: Int)?
        while try panes.seguent() {
            let idFinestra = panes.enter(0)
            let idPestanya = panes.enter(1)
            guard let f = indexFinestra[idFinestra] else { continue }
            let pane = PaneWarp(uuid: panes.text(4) ?? "", cwd: panes.text(5), darrerPwd: panes.text(6))
            if let actual = pestanyaActual, actual == (idFinestra, idPestanya) {
                finestres[f].pestanyes[finestres[f].pestanyes.count - 1].panes.append(pane)
            } else {
                finestres[f].pestanyes.append(PestanyaWarp(posicio: posicions[idPestanya] ?? 0,
                                                           titol: panes.text(2), color: panes.text(3),
                                                           panes: [pane]))
                pestanyaActual = (idFinestra, idPestanya)
            }
        }
        return finestres
    }

    private func executa(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw ErrorLectura.de(db)
        }
    }

    private func existeixTaula(_ db: OpaquePointer, _ nom: String) throws -> Bool {
        let consulta = try Sentencia(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(nom)'")
        return try consulta.seguent()
    }
}

/// Sentència SQLite preparada; es finalitza sola.
private final class Sentencia {
    private let db: OpaquePointer
    private let sentencia: OpaquePointer

    init(_ db: OpaquePointer, _ sql: String) throws {
        var preparada: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &preparada, nil) == SQLITE_OK, let preparada else {
            throw ErrorLectura.de(db)
        }
        self.db = db
        self.sentencia = preparada
    }

    deinit { sqlite3_finalize(sentencia) }

    func seguent() throws -> Bool {
        switch sqlite3_step(sentencia) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw ErrorLectura.de(db)
        }
    }

    func enter(_ columna: Int32) -> Int { Int(sqlite3_column_int64(sentencia, columna)) }

    func text(_ columna: Int32) -> String? {
        guard let c = sqlite3_column_text(sentencia, columna) else { return nil }
        return String(cString: c)
    }
}
