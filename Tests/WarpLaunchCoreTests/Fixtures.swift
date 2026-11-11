import Foundation
import SQLite3
@testable import WarpLaunchCore

// Dades de prova. Cap prova llegeix l'estat real de Warp ni de Claude.

/// Carpeta temporal pròpia de cada prova, amb la ruta ja canònica (`/private/var/…`).
struct CarpetaTemporal {
    let ruta: String

    /// El començament de la ruta de totes: la carpeta temporal del sistema, canònica, i el nom de les proves.
    static let prefix = Rutes.canonica(FileManager.default.temporaryDirectory.path) + "/warp-launch-proves-"

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-proves-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        ruta = Rutes.canonica(url.path)
    }

    /// Crea una subcarpeta i en retorna la ruta.
    @discardableResult
    func carpeta(_ nom: String) throws -> String {
        let ruta = (self.ruta as NSString).appendingPathComponent(nom)
        try FileManager.default.createDirectory(atPath: ruta, withIntermediateDirectories: true)
        return ruta
    }

    func url(_ nom: String) -> URL { URL(filePath: (ruta as NSString).appendingPathComponent(nom)) }
}

/// Base SQLite amb el subconjunt de l'esquema de `warp.sqlite` que llegim (Warp 0.2026.10.21).
final class BaseWarpDeProva {
    let url: URL
    private var db: OpaquePointer?

    /// Amb `wal`, la connexió d'escriptura queda oberta, com fa Warp mentre corre. Amb `crea: false`, obre una base de
    /// prova que ja existeix (per afegir-hi files).
    init(a url: URL, wal: Bool = false, crea: Bool = true) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw ErrorLectura.sqlite("no puc crear la base de prova")
        }
        if wal { try executa("PRAGMA journal_mode = WAL") }
        guard crea else { return }
        try executa("""
            CREATE TABLE windows (id INTEGER PRIMARY KEY NOT NULL, active_tab_index INTEGER NOT NULL);
            CREATE TABLE tabs (id INTEGER PRIMARY KEY NOT NULL, window_id INTEGER NOT NULL, custom_title TEXT,
                               color TEXT, tab_group_id INTEGER, pinned BOOLEAN NOT NULL DEFAULT FALSE);
            CREATE TABLE pane_nodes (id INTEGER PRIMARY KEY NOT NULL, tab_id INTEGER NOT NULL,
                                     parent_pane_node_id INTEGER, flex FLOAT, is_leaf BOOLEAN NOT NULL);
            CREATE TABLE pane_leaves (pane_node_id INTEGER NOT NULL UNIQUE, kind TEXT NOT NULL,
                                      is_focused BOOLEAN NOT NULL DEFAULT FALSE, custom_vertical_tabs_title TEXT,
                                      PRIMARY KEY (pane_node_id, kind));
            CREATE TABLE terminal_panes (id INTEGER PRIMARY KEY NOT NULL, kind TEXT NOT NULL DEFAULT 'terminal',
                                         uuid BLOB NOT NULL UNIQUE, cwd TEXT, is_active BOOLEAN NOT NULL DEFAULT FALSE);
            CREATE TABLE blocks (id INTEGER PRIMARY KEY, pane_leaf_uuid BLOB, pwd TEXT, start_ts TEXT);
            """)
    }

    deinit { sqlite3_close(db) }

    func executa(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw ErrorLectura.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    func finestra(_ id: Int, pestanyaActiva: Int = 0) throws {
        try executa("INSERT INTO windows VALUES (\(id), \(pestanyaActiva))")
    }

    func pestanya(_ id: Int, finestra: Int, titol: String? = nil, color: String? = nil) throws {
        try executa("INSERT INTO tabs (id, window_id, custom_title, color) VALUES (\(id), \(finestra), \(sql(titol)), \(sql(color)))")
    }

    /// Pane de terminal (fulla) d'una pestanya. `pare` és el node arrel si la pestanya està dividida.
    func paneTerminal(_ id: Int, pestanya: Int, uuid: String, cwd: String?, pare: Int? = nil) throws {
        try executa("""
            INSERT INTO pane_nodes VALUES (\(id), \(pestanya), \(pare.map(String.init) ?? "NULL"), \(pare == nil ? "NULL" : "0.5"), 1);
            INSERT INTO pane_leaves (pane_node_id, kind) VALUES (\(id), 'terminal');
            INSERT INTO terminal_panes (id, uuid, cwd) VALUES (\(id), x'\(uuid)', \(sql(cwd)));
            """)
    }

    /// Pestanya que no és de terminal (per exemple, Settings).
    func paneSettings(_ id: Int, pestanya: Int) throws {
        try executa("""
            INSERT INTO pane_nodes VALUES (\(id), \(pestanya), NULL, NULL, 1);
            INSERT INTO pane_leaves (pane_node_id, kind) VALUES (\(id), 'settings');
            """)
    }

    func nodeArrel(_ id: Int, pestanya: Int) throws {
        try executa("INSERT INTO pane_nodes VALUES (\(id), \(pestanya), NULL, NULL, 0)")
    }

    func bloc(uuid: String, pwd: String, hora: String) throws {
        try executa("INSERT INTO blocks (pane_leaf_uuid, pwd, start_ts) VALUES (x'\(uuid)', \(sql(pwd)), '\(hora)')")
    }

    private func sql(_ text: String?) -> String {
        guard let text else { return "NULL" }
        return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }
}

/// UUID de pane de prova: 32 xifres hexadecimals a partir d'una sola lletra.
func uuidDeProva(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }

/// Processos inventats: pid → (info, pare).
struct ProcessosFalsos: FontProcessos {
    /// El binari de Warp Stable d'Aplicacions (`InstallacioWarp.perOmissio`): el de `ambWarp`.
    static let executableWarp = "/Applications/Warp.app/Contents/MacOS/stable"

    var processos: [Int32: (info: InfoProces, pare: Int32)] = [:]
    var carpetes: [Int32: String] = [:]
    /// L'hora d'inici de cada procés (0.34.0); sense, `nil`, com si no s'hagués pogut llegir.
    var inicis: [Int32: IniciProces] = [:]

    func fills() -> [Int32: [Int32]] {
        Dictionary(grouping: processos, by: \.value.pare).mapValues { $0.map(\.key) }
    }
    func carpeta(_ pid: Int32) -> String? { carpetes[pid] }
    func inici(_ pid: Int32) -> IniciProces? { processos[pid] == nil ? nil : inicis[pid] }
    func proces(_ pid: Int32) -> InfoProces? { processos[pid]?.info }
    func pare(_ pid: Int32) -> Int32? { processos[pid]?.pare }
    func pids(nom: String) -> [Int32] {
        processos.filter { String(URL(filePath: $0.value.info.executable).lastPathComponent.prefix(16)) == nom }
            .keys.sorted()
    }
    /// Decisió 4 (0.31.1): només els paquets de les carpetes temporals de les proves (`CarpetaTemporal`). Un binari
    /// inventat amb una ruta de debò (`executableWarp`) no llegeix mai l'`Info.plist` del Warp de debò: no és cap Warp.
    func warpDelBinari(_ ruta: String) -> AppWarp? {
        ruta.hasPrefix(CarpetaTemporal.prefix) ? AppWarp.delBinari(ruta) : nil
    }

    /// `stable terminal-server` de Warp (pid 50) penjant de l'app (pid 40), i un `zsh` de Terminal (pid 60).
    static func ambWarp() -> ProcessosFalsos {
        var p = ProcessosFalsos()
        p.processos[40] = (InfoProces(executable: "/Applications/Warp.app/Contents/MacOS/stable",
                                      argv: ["/Applications/Warp.app/Contents/MacOS/stable"]), 1)
        p.processos[50] = (InfoProces(executable: "/Applications/Warp.app/Contents/MacOS/stable",
                                      argv: ["/Applications/Warp.app/Contents/MacOS/stable", "terminal-server",
                                             "--parent-pid=40"]), 40)
        p.processos[60] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 1)
        return p
    }

    /// Un `claude` amb el seu shell. `dinsDeWarp` decideix si el shell penja de Warp (50) o de Terminal (60).
    mutating func claude(_ pid: Int32, argv: [String], uuid: String?, dinsDeWarp: Bool = true,
                         entorn mesEntorn: [String: String] = [:]) {
        let shell = pid + 1000
        processos[shell] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), dinsDeWarp ? 50 : 60)
        var entorn = mesEntorn
        if let uuid { entorn["WARP_TERMINAL_SESSION_UUID"] = uuid }
        processos[pid] = (InfoProces(executable: "/Users/prova/.local/share/claude/versions/2.1.317",
                                     argv: argv, entorn: entorn), shell)
    }
}

/// Escriu un fitxer de sessió de Claude com els de `~/.claude/sessions/<pid>.json`.
func escriuSessio(a carpeta: URL, pid: Int32, sessionId: String, cwd: String, kind: String = "interactive",
                  nom: String? = nil, iniciadaMs: Double = 1_793_700_000_000) throws {
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    var json: [String: Any] = ["pid": pid, "sessionId": sessionId, "cwd": cwd, "kind": kind,
                               "startedAt": iniciadaMs, "status": "idle", "version": "2.1.317",
                               "procStart": "Tue Nov  3 10:00:00 2026", "entrypoint": "cli"]
    if let nom { json["name"] = nom; json["nameSource"] = "cli" }
    let dades = try JSONSerialization.data(withJSONObject: json)
    try dades.write(to: carpeta.appending(path: "\(pid).json"))
}

extension ClaudePestanya {
    /// Dada de prova: `claude --dangerously-skip-permissions --effort ultracode`, continuant la conversa. Fins a la 0.27.3
    /// era la plantilla d'importar sense configuració; des de la 0.28.0 l'app ja no la té (D11, revisada el 07/11/2026). La mateixa a `WarpLaunchUITests/AjudesDeProva.swift`.
    static let habituals = ClaudePestanya(esforc: "xhigh", ultracode: true, saltaPermisos: true)
}
