import Foundation
import Testing

// `scripts/publica.sh`: sempre en un repo de git temporal amb un origin local (un repo nu), un `build-app.sh` fals que fa una
// app signada ad hoc, i un `gh` fals que apunta què li demanen. Mai contra GitHub.

private let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/publica.sh")

@Suite struct ScriptPublicaTests {
    private struct Banc {
        let carpeta: URL
        var repo: URL { carpeta.appending(path: "repo") }
        var registreGh: URL { carpeta.appending(path: "gh.log") }
        var ordresGh: String { (try? String(contentsOf: registreGh, encoding: .utf8)) ?? "" }

        init(versio: String = "0.28.0") throws {
            carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-publica-\(UUID().uuidString)")
            let scripts = carpeta.appending(path: "repo/scripts")
            try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: script, to: scripts.appending(path: "publica.sh"))
            try Self.executable(scripts.appending(path: "build-app.sh"), #"""
            #!/bin/bash
            set -euo pipefail
            cd "$(dirname "$0")/.."
            APP="build/Warp Launch.app"
            rm -rf "$APP"
            mkdir -p "$APP/Contents/MacOS"
            cat > "$APP/Contents/Info.plist" <<EOF
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>cat.davide.warp-launch</string>
            <key>CFBundleExecutable</key><string>WarpLaunch</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>$(cat VERSION)</string>
            </dict></plist>
            EOF
            printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/WarpLaunch"
            chmod 755 "$APP/Contents/MacOS/WarpLaunch"
            codesign --force --sign - --timestamp=none "$APP" 2>/dev/null

            """#)
            try Data("\(versio)\n".utf8).write(to: repo.appending(path: "VERSION"))
            try Data("/build/\n".utf8).write(to: repo.appending(path: ".gitignore"))
            // `gh` fals: `release view` diu si ja hi és (GH_FALS_JA_HI_ES), `release list` diu l'última (GH_FALS_ANTERIOR).
            try Self.executable(carpeta.appending(path: "bin/gh"), #"""
            #!/bin/bash
            echo "$*" >> "$GH_FALS_REGISTRE"
            case "$1 $2" in
                "release view") [[ -n "${GH_FALS_JA_HI_ES:-}" ]] && exit 0 || exit 1 ;;
                "release list") echo "${GH_FALS_ANTERIOR:-}"; exit 0 ;;
                "release create") exit 0 ;;
            esac
            exit 1

            """#)
            try git("init", "-q", "--bare", "-b", "main", carpeta.appending(path: "origen.git").path, a: carpeta)
            try git("init", "-q", "-b", "main")
            try git("remote", "add", "origin", carpeta.appending(path: "origen.git").path)
            try commit("chore: inici", afegeix: true)
            try git("push", "-q", "origin", "main")
        }

        static func executable(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        @discardableResult
        func git(_ arguments: String..., a carpetaGit: URL? = nil) throws -> String {
            let (codi, sortida) = try executaPrograma("/usr/bin/git", ["-C", (carpetaGit ?? repo).path] + arguments,
                                                     entorn: ["HOME": carpeta.path, "PATH": "/usr/bin:/bin"])
            #expect(codi == 0, "git \(arguments): \(sortida)")
            return sortida.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func commit(_ missatge: String, afegeix: Bool = false) throws {
            if afegeix { try git("add", "-A") }
            try git("-c", "user.name=Prova", "-c", "user.email=prova@example.com", "commit", "-q", "--allow-empty", "-m", missatge)
        }

        func executa(_ arguments: String..., entorn extra: [String: String] = [:]) throws -> (codi: Int32, sortida: String) {
            try executaScript(repo.appending(path: "scripts/publica.sh"), arguments, entorn: [
                "HOME": carpeta.path, "GH_FALS_REGISTRE": registreGh.path, "WARP_LAUNCH_REPO": "exemple/prova",
                "LANG": "ca_ES.UTF-8", "LC_ALL": "ca_ES.UTF-8",
                "PATH": carpeta.appending(path: "bin").path + ":/usr/bin:/bin",
            ].merging(extra) { _, nou in nou })
        }

        func notes(_ versio: String = "0.28.0") -> String {
            (try? String(contentsOf: repo.appending(path: "build/notes-\(versio).md"), encoding: .utf8)) ?? ""
        }

        /// Signatura ad hoc: el requisit només hi demana l'identificador (sense el certificat d'en David).
        static let requisitDeProva = ["WARP_LAUNCH_REQUISIT": #"identifier "cat.davide.warp-launch""#]
    }

    /// Per defecte, mode de prova: compila, fa el zip i les notes, i no crea res a GitHub (regla 3).
    @Test func perDefecteNoPublicaRes() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("Mode de prova: no s'ha publicat res."))
        #expect(sortida.contains("publicaria Warp Launch 0.28.0 a exemple/prova com a v0.28.0"))
        #expect(FileManager.default.fileExists(atPath: b.repo.appending(path: "build/WarpLaunch-0.28.0.zip").path))
        #expect(!b.ordresGh.contains("release create"))
        #expect(b.notes().contains("Primera versió publicada."))
        // La comanda només executa l'script si gh l'ha baixat (amb `bash <(…)`, executaria el JSON de l'error).
        #expect(b.notes().contains(#"s="$(gh api -H 'Accept: application/vnd.github.raw' repos/exemple/prova/contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica"#))
    }

    /// Amb --aplica, crea la versió amb el zip, al commit d'origin/main.
    @Test func laPublica() throws {
        let b = try Banc()
        let commit = try b.git("rev-parse", "HEAD")
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresGh.contains("release create v0.28.0 build/WarpLaunch-0.28.0.zip --repo exemple/prova --target \(commit)"
                                    + " --title Warp Launch 0.28.0 --notes-file build/notes-0.28.0.md"))
        #expect(sortida.contains("gh release delete v0.28.0 --repo exemple/prova --cleanup-tag"))
    }

    /// Les notes diuen els commits des de l'última versió publicada.
    @Test func lesNotesDiuenElsCanvis() throws {
        let b = try Banc()
        try b.git("tag", "v0.27.0")
        try b.git("push", "-q", "origin", "v0.27.0")
        try b.git("tag", "-d", "v0.27.0")
        try b.commit("feat: una cosa nova")
        try b.git("push", "-q", "origin", "main")
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["GH_FALS_ANTERIOR": "v0.27.0"]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(b.notes().contains("Canvis des de la v0.27.0:"))
        #expect(b.notes().contains("- feat: una cosa nova"))
        #expect(!b.notes().contains("chore: inici"))
    }

    /// Una etiqueta que ha quedat a origin en un altre commit (sense versió) no es fa servir: GitHub no faria cas de --target.
    @Test func unaEtiquetaQueHaQuedatNoEsFaServir() throws {
        let b = try Banc()
        try b.git("tag", "v0.28.0")
        try b.git("push", "-q", "origin", "v0.28.0")
        try b.commit("fix: una altra cosa")
        try b.git("push", "-q", "origin", "main")
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 1)
        #expect(sortida.contains("l'etiqueta v0.28.0 ja existeix a origin"))
        #expect(!b.ordresGh.contains("release create"))
    }

    /// La mateixa etiqueta al mateix commit sí que val (per exemple, si la versió es va esborrar sense l'etiqueta).
    @Test func laMateixaEtiquetaAlMateixCommitVal() throws {
        let b = try Banc()
        try b.git("tag", "-a", "v0.28.0", "-m", "v0.28.0")
        try b.git("push", "-q", "origin", "v0.28.0")
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
    }

    /// Si l'última versió publicada no té l'etiqueta a origin, s'atura: no escriu «Primera versió publicada».
    @Test func senseLEtiquetaDeLAnteriorSAtura() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["GH_FALS_ANTERIOR": "v0.9.9"]) { $1 })
        #expect(codi == 1)
        #expect(sortida.contains("no trobo l'etiqueta v0.9.9"))
        #expect(!b.notes().contains("Primera versió publicada."))
    }

    /// Una app sense el certificat d'en David no es publica: no es podria instal·lar amb --github.
    @Test func adHocNoEsPublica() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("no està signada amb «Warp Launch Dev»"))
        #expect(!b.ordresGh.contains("release create"))
    }

    /// Amb canvis sense commit, no publica res.
    @Test func ambCanvisNoPublica() throws {
        let b = try Banc()
        try Data("x".utf8).write(to: b.repo.appending(path: "nou.txt"))
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 1)
        #expect(sortida.contains("canvis sense fer commit"))
        #expect(!b.ordresGh.contains("release create"))
    }

    /// Un commit que no és a origin/main no es publica.
    @Test func senseFerPushNoPublica() throws {
        let b = try Banc()
        try b.commit("feat: sense push")
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 1)
        #expect(sortida.contains("no és el d'origin/main"))
        #expect(!b.ordresGh.contains("release create"))
    }

    /// Una versió que ja és publicada no es torna a publicar: cal pujar VERSION.
    @Test func jaPublicadaNoPublica() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_JA_HI_ES": "1"]) { $1 })
        #expect(codi == 1)
        #expect(sortida.contains("la v0.28.0 ja és publicada a exemple/prova"))
        #expect(!b.ordresGh.contains("release create"))
    }
}
