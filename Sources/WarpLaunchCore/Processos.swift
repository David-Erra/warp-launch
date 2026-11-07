import Foundation

/// Què sabem d'un procés viu.
public struct InfoProces: Sendable, Equatable {
    /// Ruta de l'executable.
    public var executable: String
    public var argv: [String]
    public var entorn: [String: String]

    public init(executable: String, argv: [String], entorn: [String: String] = [:]) {
        self.executable = executable
        self.argv = argv
        self.entorn = entorn
    }

    /// El pid es pot reutilitzar quan un procés acaba: comprova que és `claude`.
    var esClaude: Bool {
        let primer = argv.first.map { ($0 as NSString).lastPathComponent }
        return primer == "claude" || executable.contains("/claude")
    }
}

/// D'on surt la informació dels processos. Les proves en fan servir una de falsa.
public protocol FontProcessos: Sendable {
    /// `nil` si el procés no existeix o no és de l'usuari.
    func proces(_ pid: Int32) -> InfoProces?
    /// Pid del pare, o `nil` si el procés no existeix.
    func pare(_ pid: Int32) -> Int32?
    /// Pids dels processos de l'usuari amb aquest nom (`p_comm`: el nom de l'executable, tallat a 16 caràcters).
    func pids(nom: String) -> [Int32]
    /// Els fills de cada procés de l'usuari (pare → fills), d'una sola lectura.
    func fills() -> [Int32: [Int32]]
    /// La carpeta de treball d'un procés, o `nil` si no es pot saber.
    func carpeta(_ pid: Int32) -> String?
}

extension FontProcessos {
    /// L'executable de l'app de Warp que obre l'app (`ObreWarp`). El mateix binari fa de `terminal-server` i de CLI.
    public static var executableWarp: String { "/Applications/Warp.app/Contents/MacOS/stable" }

    /// Warp és obert: corre l'app de `/Applications` sense cap argument, com l'obre macOS (el 04/11/2026, `ps`). Amb
    /// arguments és el seu `terminal-server` o el CLI (`--help`, subcomandes).
    public func warpObert() -> Bool {
        pids(nom: "stable").contains { pid in
            guard let info = proces(pid), info.executable == Self.executableWarp else { return false }
            return info.argv.count <= 1
        }
    }

    /// Els terminals vius de Warp: els fills del seu `terminal-server`, un per pane. No depèn de `warp.sqlite`, i és el
    /// que hi ha ara mateix. Del shell només se'n sap el pid i la carpeta (el seu entorn surt buit): el pane i la marca
    /// surten dels seus fills, que els hereten (docs/fets-verificats.md, 05/11/2026).
    public func terminalsDeWarp() -> [TerminalViu] {
        let servidors = pids(nom: "stable").filter { pid in
            guard let info = proces(pid), info.executable == Self.executableWarp else { return false }
            return info.argv.contains("terminal-server")
        }
        guard !servidors.isEmpty else { return [] }
        let arbre = fills()
        return servidors.flatMap { arbre[$0] ?? [] }.sorted().compactMap { shell in
            guard proces(shell) != nil else { return nil }
            var terminal = TerminalViu(pid: shell, carpeta: carpeta(shell).map(Rutes.canonica))
            for fill in (arbre[shell] ?? []).sorted() {
                guard let info = proces(fill) else { continue }
                if terminal.pane == nil { terminal.pane = info.entorn["WARP_TERMINAL_SESSION_UUID"]?.lowercased() }
                if terminal.marca == nil { terminal.marca = info.entorn[OrdreClaude.variableMarca].flatMap(UUID.init(uuidString:)) }
                if info.esClaude {
                    terminal.claude = true
                    terminal.conversa = OpcionsClaude.analitza(info.argv).repren
                }
            }
            return terminal
        }
    }
}

/// Processos reals del Mac, llegits amb `sysctl`. Només llegeix: no envia cap senyal.
public struct ProcessosDelSistema: FontProcessos {
    public init() {}

    /// `KERN_PROC_UID`: els processos de l'usuari.
    private func llista() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        for _ in 0..<3 {
            var mida = 0
            guard sysctl(&mib, 4, nil, &mida, nil, 0) == 0, mida > 0 else { return [] }
            mida += mida / 8  // marge: entre les dues crides poden començar processos
            var processos = [kinfo_proc](repeating: kinfo_proc(), count: mida / MemoryLayout<kinfo_proc>.stride)
            mida = processos.count * MemoryLayout<kinfo_proc>.stride
            guard sysctl(&mib, 4, &processos, &mida, nil, 0) == 0 else {
                if errno == ENOMEM { continue }
                return []
            }
            return Array(processos.prefix(mida / MemoryLayout<kinfo_proc>.stride))
        }
        return []
    }

    public func pids(nom: String) -> [Int32] {
        llista().compactMap { info in
            var comm = info.kp_proc.p_comm
            let text = withUnsafeBytes(of: &comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return text == nom ? info.kp_proc.p_pid : nil
        }
    }

    public func fills() -> [Int32: [Int32]] {
        Dictionary(grouping: llista(), by: \.kp_eproc.e_ppid).mapValues { $0.map(\.kp_proc.p_pid) }
    }

    /// `PROC_PIDVNODEPATHINFO`: la carpeta de treball del procés.
    public func carpeta(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let mida = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, mida) == mida else { return nil }
        let ruta = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ruta.isEmpty ? nil : ruta
    }

    public func pare(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var mida = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &mida, nil, 0) == 0, mida > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// `KERN_PROCARGS2`: argc, ruta de l'executable, argv i entorn, separats per zeros.
    public func proces(_ pid: Int32) -> InfoProces? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var mida = 0
        guard sysctl(&mib, 3, nil, &mida, nil, 0) == 0, mida > 0 else { return nil }
        var dades = [UInt8](repeating: 0, count: mida)
        guard sysctl(&mib, 3, &dades, &mida, nil, 0) == 0, mida > MemoryLayout<Int32>.size else { return nil }
        let argc = dades.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size

        func cadena() -> String {
            let inici = i
            while i < mida, dades[i] != 0 { i += 1 }
            let text = String(decoding: dades[inici..<i], as: UTF8.self)
            i += 1
            return text
        }

        let executable = cadena()
        while i < mida, dades[i] == 0 { i += 1 }  // farciment després de la ruta
        var argv: [String] = []
        for _ in 0..<max(argc, 0) where i < mida {
            argv.append(cadena())
        }
        var entorn: [String: String] = [:]
        while i < mida {
            let variable = cadena()
            guard !variable.isEmpty else { break }
            if let igual = variable.firstIndex(of: "=") {
                entorn[String(variable[..<igual])] = String(variable[variable.index(after: igual)...])
            }
        }
        return InfoProces(executable: executable, argv: argv, entorn: entorn)
    }
}
