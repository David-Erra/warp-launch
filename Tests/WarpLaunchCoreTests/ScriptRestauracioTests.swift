import Foundation
import Testing

// `scripts/warp-restauracio.sh`: l'única cosa de Warp que es pot escriure (excepció de la regla 7 de CLAUDE.md). Sempre sobre
// un fitxer temporal, amb `WARP_SETTINGS`: mai sobre el de debò.

private let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/warp-restauracio.sh")

private let ajustos = """
    is_settings_sync_enabled = true

    [agents.warp_agent.other]
    restored = 'text que no s'ha de tocar: true false'

    [general]
    login_item = true
    restore_session = false

    [appearance]
    theme = "true"

    """

@Suite struct ScriptRestauracioTests {
    private struct Banc {
        let carpeta: URL
        var fitxer: URL { carpeta.appending(path: "settings.toml") }

        init(_ text: String = ajustos) throws {
            carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-script-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: carpeta.appending(path: "tmp"), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: fitxer)
        }

        var text: String { (try? String(contentsOf: fitxer, encoding: .utf8)) ?? "" }

        /// Els fitxers de la carpeta: no n'ha de quedar cap de provisional.
        var noms: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []).sorted() }

        /// Els fitxers de la carpeta temporal.
        var temporals: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: carpeta.appending(path: "tmp").path)) ?? []).sorted()
        }

        func executa(_ arguments: String...) throws -> (codi: Int32, sortida: String) {
            try executaScript(script, arguments, entorn: [
                "WARP_SETTINGS": fitxer.path, "TMPDIR": carpeta.appending(path: "tmp").path, "HOME": carpeta.path,
                "PATH": "/usr/bin:/bin",
            ])
        }

        /// Com `executa`, amb una ordre posada davant de les del sistema: `cos` és el seu script de bash.
        func executa(interposant ordre: String, cos: String, _ arguments: String...) throws -> (codi: Int32, sortida: String) {
            let bin = carpeta.appending(path: "bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let fitxerOrdre = bin.appending(path: ordre)
            try Data(("#!/bin/bash\n" + cos + "\n").utf8).write(to: fitxerOrdre)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fitxerOrdre.path)
            return try executaScript(script, arguments, entorn: [
                "WARP_SETTINGS": fitxer.path, "TMPDIR": carpeta.appending(path: "tmp").path, "HOME": carpeta.path,
                "PATH": bin.path + ":/usr/bin:/bin",
            ])
        }
    }

    @Test func estatNoEscriuRes() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("estat")
        #expect(codi == 0)
        #expect(sortida == "restore_session = false (línia 8): Warp no desa les finestres.\n")
        #expect(b.text == ajustos)
    }

    /// Sense `--aplica`, no s'escriu res (regla 4).
    @Test func perDefecteNomesDiuQueFaria() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("activa")
        #expect(codi == 0)
        #expect(sortida.hasPrefix("Mode de prova: canviaria la línia 8"))
        #expect(sortida.contains("restore_session = false → true"))
        #expect(b.text == ajustos)
        #expect(b.noms == ["settings.toml", "tmp"])
    }

    /// Activar i desactivar: només canvia aquella línia, i el fitxer torna a ser idèntic. Els altres «true» i «false» no es
    /// toquen, ni els permisos, i no queda cap fitxer provisional.
    @Test func nomesCanviaLaLinia() throws {
        let b = try Banc()
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: b.fitxer.path)
        let (codi, sortida) = try b.executa("activa", "--aplica")
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("restore_session = false → true"))
        #expect(sortida.contains("desactiva --aplica"), "recorda com es torna enrere")
        #expect(b.text == ajustos.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
        #expect(b.noms == ["settings.toml", "tmp"])
        let permisos = try FileManager.default.attributesOfItem(atPath: b.fitxer.path)[.posixPermissions] as? Int
        #expect(permisos == 0o640)
        #expect(try b.executa("estat").sortida.hasPrefix("restore_session = true"))

        #expect(try b.executa("desactiva", "--aplica").codi == 0)
        #expect(b.text == ajustos)
    }

    /// La còpia d'abans es queda, i té el contingut d'abans.
    @Test func desaUnaCopia() throws {
        let b = try Banc()
        _ = try b.executa("activa", "--aplica")
        let copies = try FileManager.default.contentsOfDirectory(atPath: b.carpeta.appending(path: "tmp").path)
        #expect(copies.count == 1)
        let copia = try String(contentsOf: b.carpeta.appending(path: "tmp/\(copies[0])"), encoding: .utf8)
        #expect(copia == ajustos)
    }

    @Test func siJaEsAixiNoFaRes() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("desactiva", "--aplica")
        #expect(codi == 0)
        #expect(sortida.contains("ja és false"))
        #expect(b.text == ajustos)
    }

    /// Un comentari a la mateixa línia no es perd.
    @Test func respectaElComentari() throws {
        let b = try Banc("[general]\nrestore_session = false # comentari\n")
        #expect(try b.executa("activa", "--aplica").codi == 0)
        #expect(b.text == "[general]\nrestore_session = true # comentari\n")
    }

    /// `estat` no deixa res enlloc, i el mode de prova tampoc.
    @Test func sensAplicarNoQuedaCapTemporal() throws {
        let b = try Banc()
        _ = try b.executa("estat")
        _ = try b.executa("activa")
        #expect(b.temporals.isEmpty)
    }

    /// Si Warp escriu després que l'script hagi llegit, no es trepitja el seu canvi.
    @Test func siWarpEscriuDespresNoEsTrepitja() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(interposant: "mktemp", cos: #"""
            case "$1" in *warp-settings-nou*) printf 'de_warp = 1\n' >> "$WARP_SETTINGS" ;; esac
            exec /usr/bin/mktemp "$@"
            """#, "activa", "--aplica")
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("acaba de canviar"))
        #expect(b.text == ajustos + "de_warp = 1\n", "el canvi de Warp hi és, i `restore_session` no ha canviat")
    }

    /// L'script no crea mai `settings.toml` (ronda 5: si el creés abans que Warp, Warp se saltaria la migració d'arrencada).
    /// Sense el fitxer no escriu res (`senseLaLiniaEsActivatDeSerie`), i si Warp l'esborra mentre l'script el canvia, no el
    /// torna a crear: el fitxer ja no és el que s'ha llegit, i no es toca res.
    @Test func siWarpLEsborraMentrestantNoElTornaACrear() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(interposant: "mktemp", cos: #"""
            case "$1" in *warp-settings-nou*) /bin/rm -f "$WARP_SETTINGS" ;; esac
            exec /usr/bin/mktemp "$@"
            """#, "activa", "--aplica")
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("acaba de canviar. No s'ha tocat res."), "\(sortida)")
        #expect(b.noms == ["bin", "tmp"])
        #expect(b.temporals.isEmpty)
    }

    /// Si Warp escriu just abans de llegir, es conserva, i el número de línia és el de la lectura. Abans, amb una línia nova a
    /// dalt entre dues lectures, l'script canviava el valor de la línia anterior, `login_item`.
    @Test func siWarpEscriuAbansEsConserva() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(interposant: "cp", cos: #"""
            case "$3" in *warp-settings-copia*) /usr/bin/sed -i '' '1i\
            de_warp = 1
            ' "$WARP_SETTINGS" ;; esac
            exec /bin/cp "$@"
            """#, "activa", "--aplica")
        #expect(codi == 0, "\(sortida)")
        #expect(b.text == "de_warp = 1\n" + ajustos.replacingOccurrences(of: "restore_session = false", with: "restore_session = true"))
    }

    /// El fitxer nou no es crea mai a la carpeta de Warp: si el procés morís, s'hi quedaria (i Warp vigila la carpeta).
    @Test func elProvisionalNoEsALaCarpetaDeWarp() throws {
        let b = try Banc()
        let registre = b.carpeta.appending(path: "tmp/registre-mv")
        let (codi, sortida) = try b.executa(interposant: "mv", cos: #"""
            printf '%s\n' "$2" > "$TMPDIR/registre-mv"
            exec /bin/mv "$@"
            """#, "activa", "--aplica")
        #expect(codi == 0, "\(sortida)")
        let origen = try String(contentsOf: registre, encoding: .utf8)
        #expect(origen.hasPrefix(b.carpeta.appending(path: "tmp").path + "/"), "\(origen)")
    }

    /// `mv` entre volums no és atòmic: si la carpeta temporal és en un altre, no es fa.
    @Test func refusaUnaCarpetaTemporalDUnAltreVolum() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(interposant: "stat", cos: #"""
            case "$3" in */tmp) echo 1 ;; *) echo 2 ;; esac
            """#, "activa", "--aplica")
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("mateix volum"))
        #expect(b.text == ajustos)
    }

    /// Una variable buida per error no pot acabar al fitxer de debò: es nega, en lloc de fer servir el de `HOME`.
    @Test func unaVariableBuidaNoFaServirElDeDebo() throws {
        let b = try Banc()
        let carpetaWarp = b.carpeta.appending(path: ".warp")
        try FileManager.default.createDirectory(at: carpetaWarp, withIntermediateDirectories: true)
        let delHome = carpetaWarp.appending(path: "settings.toml")
        try Data(ajustos.utf8).write(to: delHome)
        let (codi, sortida) = try executaScript(script, ["activa", "--aplica"], entorn: [
            "WARP_SETTINGS": "", "TMPDIR": b.carpeta.appending(path: "tmp").path, "HOME": b.carpeta.path, "PATH": "/usr/bin:/bin",
        ])
        #expect(codi == 1, "\(sortida)")
        #expect(try String(contentsOf: delHome, encoding: .utf8) == ajustos)
    }

    /// Si no té exactament la forma esperada, no toca res.
    @Test(arguments: [
        "[altra]\nrestore_session = false\n", // En una altra taula.
        "general.restore_session = false\n", // Fora de la taula.
        "restore_session = false\n[general]\nx = 1\n", // Abans de la taula.
        "[general]\nrestore_session = false\nrestore_session = true\n", // Dues vegades.
        "[general]\nrestore_session = false\n[a]\nb = 'restore_session'\n", // També en un text.
        "[general]\nrestore_session = \"false\"\n", // No és un booleà.
        "[general]\nrestore_session = false", // Sense salt de línia final: awk en canviaria els bytes.
    ])
    func refusaLesFormesEstranyes(text: String) throws {
        let b = try Banc(text)
        let (codi, sortida) = try b.executa("activa", "--aplica")
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("No s'ha tocat res"))
        #expect(b.text == text)
        #expect(b.noms == ["settings.toml", "tmp"])
    }

    @Test func refusaUnEnllacOUnFitxerQueNoHiEs() throws {
        let b = try Banc()
        let real = b.carpeta.appending(path: "real.toml")
        try FileManager.default.moveItem(at: b.fitxer, to: real)
        #expect(try b.executa("desactiva", "--aplica").codi == 1, "no hi és")
        try FileManager.default.createSymbolicLink(at: b.fitxer, withDestinationURL: real)
        #expect(try b.executa("activa", "--aplica").codi == 1, "és un enllaç")
        #expect(try b.executa("estat").codi == 1, "és un enllaç")
        #expect(try String(contentsOf: real, encoding: .utf8) == ajustos)
        // Un enllaç trencat també és un enllaç, no un fitxer que no hi és.
        try FileManager.default.removeItem(at: real)
        #expect(try b.executa("estat").codi == 1, "és un enllaç trencat")
    }

    /// Sense la línia (0.31.2), o sense el fitxer, Warp fa servir el valor de sèrie, activat: `estat` ho diu, `activa` no
    /// ha de fer res, i `desactiva` falla amb el motiu, perquè l'script no afegeix la línia. No s'escriu res.
    @Test(arguments: [("[general]\nlogin_item = true\n", "sense la línia"), ("", "sense la línia"),
                      ("[general]\nx = 1", "sense la línia"), (nil, "sense el fitxer")] as [(String?, String)])
    func senseLaLiniaEsActivatDeSerie(text: String?, motiu: String) throws {
        let b = try Banc(text ?? "")
        if text == nil { try FileManager.default.removeItem(at: b.fitxer) }
        let estat = try b.executa("estat")
        #expect(estat.codi == 0, "\(estat.sortida)")
        #expect(estat.sortida == "restore_session: activat (de sèrie, \(motiu)): Warp desa les finestres i les restaura en obrir-se.\n")
        for opcio in ["", "--aplica"] {
            let activa = try opcio.isEmpty ? b.executa("activa") : b.executa("activa", opcio)
            #expect(activa.codi == 0, "\(activa.sortida)")
            #expect(activa.sortida == "restore_session ja és activat (de sèrie, \(motiu)): no cal canviar res.\n")
            let desactiva = try opcio.isEmpty ? b.executa("desactiva") : b.executa("desactiva", opcio)
            #expect(desactiva.codi == 1, "\(desactiva.sortida)")
            #expect(desactiva.sortida.hasPrefix("warp-restauracio: «restore_session» no hi és (\(motiu)): Warp fa servir el "
                + "valor de sèrie, activat, i aquest script no afegeix la línia."), "\(desactiva.sortida)")
            #expect(desactiva.sortida.hasSuffix("No s'ha tocat res.\n"))
        }
        #expect(b.noms == (text == nil ? ["tmp"] : ["settings.toml", "tmp"]))
        if let text { #expect(b.text == text) }
        #expect(b.temporals.isEmpty)
    }

    @Test func refusaLesOrdresQueNoConeix() throws {
        let b = try Banc()
        #expect(try b.executa().codi == 2)
        #expect(try b.executa("activat").codi == 2)
        #expect(try b.executa("activa", "--apli").codi == 2)
        #expect(try b.executa("estat", "--aplica").codi == 2)
        #expect(b.text == ajustos)
    }
}
