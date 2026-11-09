import Foundation
import Testing

// `scripts/publica.sh`: sempre en un repo de git temporal amb un origin local (un repo nu), un `build-app.sh` fals que fa una
// app signada ad hoc, i un `gh` fals que apunta què li demanen i fa de recepta de Homebrew. Mai contra GitHub.

private let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/publica.sh")

private let tapDeProva = "exemple/homebrew-proves"
private let sha256Antic = String(repeating: "a1", count: 32)
private let commitDelTap = "fedcba9876543210fedcba9876543210fedcba98"

/// Una recepta com la de debò: la versió i el sha256 en una línia cadascun, i la URL amb `#{version}`.
private func recepta(versio: String = "0.27.0", sha256: String = sha256Antic) -> String {
    """
    cask "warp-launch" do
      version "\(versio)"
      sha256 "\(sha256)"

      url "https://github.com/exemple/prova/releases/download/v#{version}/WarpLaunch-#{version}.zip"
      name "Warp Launch"
      app "Warp Launch.app"
    end

    """
}

@Suite struct ScriptPublicaTests {
    private struct Banc {
        let carpeta: URL
        var repo: URL { carpeta.appending(path: "repo") }
        var registreGh: URL { carpeta.appending(path: "gh.log") }
        var ordresGh: String { (try? String(contentsOf: registreGh, encoding: .utf8)) ?? "" }
        var fitxerRecepta: URL { carpeta.appending(path: "recepta.rb") }
        /// El sha de git de la recepta tal com és ara: el mateix que dona GitHub.
        var blobDeLaRecepta: String { get throws { try git("hash-object", "--no-filters", "--", fitxerRecepta.path) } }
        var zip: URL { repo.appending(path: "build/WarpLaunch-0.28.0.zip") }
        var compilat: Bool { FileManager.default.fileExists(atPath: repo.appending(path: "build").path) }
        var fitxerPut: URL { carpeta.appending(path: "put.txt") }
        var fitxerZipPujat: URL { carpeta.appending(path: "zip-pujat.txt") }
        var zipPujat: String { ((try? String(contentsOf: fitxerZipPujat, encoding: .utf8)) ?? "").trimmingCharacters(in: .newlines) }
        /// Què ha rebut el PUT de la recepta: una línia `camp=valor` per cada `-f` (un valor amb salts de línia ocuparia més d'una línia).
        var liniesPut: [String] { ((try? String(contentsOf: fitxerPut, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        var campsPut: [String: String] {
            Dictionary(liniesPut.map { linia in
                let parts = linia.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                return (parts[0], parts.count > 1 ? parts[1] : "")
            }, uniquingKeysWith: { _, nou in nou })
        }

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
            try Data(recepta().utf8).write(to: fitxerRecepta)
            // `gh` fals: `release view` diu si ja hi és (GH_FALS_JA_HI_ES), `release list` diu l'última (GH_FALS_ANTERIOR). I `api`
            // fa de GitHub per a la recepta: el GET torna el JSON de debò (el base64 amb salts de línia, i el sha de git del fitxer)
            // i hi aplica el --jq, i el PUT només passa si el sha és el del fitxer d'ara. Les eines, amb la ruta sencera: unes
            // proves en posen de falses al PATH, només per a l'script.
            try Self.executable(carpeta.appending(path: "bin/gh"), #"""
            #!/bin/bash
            echo "$*" >> "$GH_FALS_REGISTRE"
            case "$1 $2" in
                "release view") [[ -n "${GH_FALS_JA_HI_ES:-}" ]] && exit 0 || exit 1 ;;
                "release list") echo "${GH_FALS_ANTERIOR:-}"; exit 0 ;;
                "release create")
                    [[ -z "${GH_FALS_RELEASE_FALLA:-}" ]] || exit 1
                    /usr/bin/shasum -a 256 "$4" | cut -c1-64 > "$GH_FALS_ZIP_PUJAT"
                    exit 0 ;;
            esac
            [[ "$1" == api ]] || exit 1
            shift
            METODE=GET; RUTA=""; FILTRE="."; CAMPS=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --method) METODE="$2"; shift 2 ;;
                    --jq) FILTRE="$2"; shift 2 ;;
                    -f) CAMPS+=("$2"); shift 2 ;;
                    *) RUTA="$1"; shift ;;
                esac
            done
            [[ "${RUTA%%\?*}" == "repos/$GH_FALS_TAP/contents/Casks/warp-launch.rb" && -f "$GH_FALS_RECEPTA" ]] || {
                echo '{"message":"Not Found"}'; echo 'gh: Not Found (HTTP 404)' >&2; exit 1
            }
            BLOB="${GH_FALS_BLOB:-$(/usr/bin/git hash-object --no-filters -- "$GH_FALS_RECEPTA")}"
            if [[ "$METODE" == PUT ]]; then
                printf '%s\n' "${CAMPS[@]}" > "$GH_FALS_PUT"
                [[ -z "${GH_FALS_PUT_FALLA:-}" ]] || { echo '{"message":"conflict"}'; echo 'gh: conflict (HTTP 409)' >&2; exit 1; }
                [[ " ${CAMPS[*]} " == *" sha=$BLOB "* ]] || { echo '{"message":"does not match"}'; echo 'gh: does not match (HTTP 409)' >&2; exit 1; }
                /usr/bin/jq -n --arg commit "$GH_FALS_COMMIT" '{commit: {sha: $commit}}' | /usr/bin/jq -r "$FILTRE"
                exit 0
            fi
            /usr/bin/jq -n --arg contingut "$(/usr/bin/base64 < "$GH_FALS_RECEPTA" | /usr/bin/fold -w 60)" --arg blob "$BLOB" \
                --arg codificacio "${GH_FALS_CODIFICACIO:-base64}" \
                '{type: "file", encoding: $codificacio, sha: $blob, content: ($contingut + "\n")}' | /usr/bin/jq -r "$FILTRE"
            [[ -z "${GH_FALS_CANVIA_EN_LLEGIR:-}" ]] || printf '# un altre canvi\n' >> "$GH_FALS_RECEPTA"

            """#)
            try git("init", "-q", "--bare", "-b", "main", carpeta.appending(path: "origen.git").path, a: carpeta)
            try git("init", "-q", "-b", "main")
            try git("config", "user.name", "Prova")
            try git("config", "user.email", "prova@example.com")
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
            try executaScript(repo.appending(path: "scripts/publica.sh"), arguments, entorn: entornDeProva.merging(extra) { _, nou in nou })
        }

        private var entornDeProva: [String: String] {
            [
                "HOME": carpeta.path, "GH_FALS_REGISTRE": registreGh.path, "WARP_LAUNCH_REPO": "exemple/prova",
                "WARP_LAUNCH_TAP": tapDeProva, "GH_FALS_TAP": tapDeProva, "GH_FALS_RECEPTA": fitxerRecepta.path,
                "GIT_CONFIG_NOSYSTEM": "1", "TMPDIR": carpeta.path,
                "GH_FALS_PUT": fitxerPut.path, "GH_FALS_ZIP_PUJAT": fitxerZipPujat.path, "GH_FALS_COMMIT": commitDelTap,
                "LANG": "ca_ES.UTF-8", "LC_ALL": "ca_ES.UTF-8",
                "PATH": carpeta.appending(path: "bin").path + ":/usr/bin:/bin",
            ]
        }

        func notes(_ versio: String = "0.28.0") -> String {
            (try? String(contentsOf: repo.appending(path: "build/notes-\(versio).md"), encoding: .utf8)) ?? ""
        }

        func sha256(de url: URL) throws -> String {
            let (codi, sortida) = try executaPrograma("/usr/bin/shasum", ["-a", "256", url.path], entorn: ["PATH": "/usr/bin:/bin"])
            #expect(codi == 0, "\(sortida)")
            return String(sortida.prefix(64))
        }

        /// Refusa abans de compilar, amb --aplica i sense: no compila res, ni publica res, ni escriu la recepta.
        func comprovaRefus(conte text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
            for arguments: [String] in [[], ["--aplica"]] {
                let (codi, sortida) = try executaScript(repo.appending(path: "scripts/publica.sh"), arguments, entorn: entornDeProva)
                #expect(codi == 1, "\(sortida)", sourceLocation: sourceLocation)
                #expect(sortida.contains(text), "\(sortida)", sourceLocation: sourceLocation)
                #expect(sortida.contains("No s'ha publicat res."), "\(sortida)", sourceLocation: sourceLocation)
                #expect(!compilat, "no ha de compilar res", sourceLocation: sourceLocation)
                #expect(!ordresGh.contains("release create"), sourceLocation: sourceLocation)
                #expect(!ordresGh.contains("--method PUT"), sourceLocation: sourceLocation)
            }
        }

        /// Signatura ad hoc: el requisit només hi demana l'identificador (sense el certificat de debò).
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

    /// Una app sense el certificat de debò no es publica: no es podria instal·lar amb --github.
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

    // --- La recepta de Homebrew: es llegeix abans de compilar, i si no té la forma esperada no es publica res.

    /// El mode de prova llegeix la recepta i diu quin canvi hi faria, sense escriure-hi.
    @Test func elModeDeProvaDiuElCanviDeLaRecepta() throws {
        let b = try Banc()
        let abans = try Data(contentsOf: b.fitxerRecepta)
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresGh.contains("api repos/\(tapDeProva)/contents/Casks/warp-launch.rb?ref=main"))
        #expect(sortida.contains("version: 0.27.0 -> 0.28.0"))
        #expect(sortida.contains("sha256: \(sha256Antic) -> \(try b.sha256(de: b.zip))"))
        #expect(sortida.contains("Prova <prova@example.com>"))
        #expect(!b.ordresGh.contains("--method PUT"))
        #expect(!b.ordresGh.contains("release create"))
        #expect(try Data(contentsOf: b.fitxerRecepta) == abans)
        // Només lectures, per cap branca: qualsevol altra ordre de `gh` fa fallar la prova.
        for ordre in b.ordresGh.split(separator: "\n") {
            #expect(ordre.hasPrefix("release view ") || ordre.hasPrefix("release list ") || ordre == "api repos/\(tapDeProva)/contents/Casks/warp-launch.rb?ref=main --jq .encoding, .sha, .content", "\(ordre)")
        }
    }

    /// Per defecte, el tap és el de debò (`WARP_LAUNCH_TAP` buit fa servir el valor per defecte; el `gh` fals només accepta aquest).
    @Test func elTapPerDefecte() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["WARP_LAUNCH_TAP": "", "GH_FALS_TAP": "David-Erra/homebrew-tap"]) { $1 })
        #expect(codi == 0, "\(sortida)")
    }

    /// Sense poder llegir la recepta, no compila ni publica res.
    @Test func senseLaReceptaNoEsPublica() throws {
        let b = try Banc()
        try FileManager.default.removeItem(at: b.fitxerRecepta)
        try b.comprovaRefus(conte: "no s'ha pogut llegir la recepta")
    }

    /// Un fitxer que GitHub no torna en base64 (per exemple, si és massa gran) tampoc no es fa servir.
    @Test func siGitHubNoLaTornaEnBase64NoEsPublica() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_CODIFICACIO": "none"]) { $1 })
        #expect(codi == 1)
        #expect(sortida.contains("com s'esperava"))
        #expect(!b.compilat)
        #expect(!b.ordresGh.contains("release create"))
    }

    /// Exactament una línia `version` i una `sha256`, amb la forma de la recepta: qualsevol altra cosa es refusa.
    @Test(arguments: [
        recepta().replacing("  version \"0.27.0\"\n", with: ""),  // sense version
        recepta().replacing("  version \"0.27.0\"\n", with: "  version \"0.27.0\"\n  version \"0.26.0\"\n"),  // dues
        recepta().replacing("  version \"0.27.0\"\n", with: "  version \"0.27.0\"\n    version \"0.26.0\"\n"),  // una d'exacta i una altra dins d'un bloc
        recepta().replacing("  sha256 \"\(sha256Antic)\"\n", with: ""),  // sense sha256
        recepta().replacing("  sha256 \"\(sha256Antic)\"\n", with: "  sha256 \"\(sha256Antic)\"\n  sha256 \"\(sha256Antic)\"\n"),  // dues
        recepta().replacing("  sha256 \"\(sha256Antic)\"\n", with: "  sha256 \"\(sha256Antic)\"\n    sha256 \"\(sha256Antic)\"\n"),  // una d'exacta i una altra dins d'un bloc
        recepta().replacing("  version \"0.27.0\"", with: "  version :latest"),
        recepta().replacing("  version \"0.27.0\"", with: "    version \"0.27.0\""),
        recepta().replacing("  version \"0.27.0\"", with: "  version '0.27.0'"),
        recepta().replacing("  version \"0.27.0\"", with: "  version \"0.27.0\" # comentari"),
        recepta().replacing("  version \"0.27.0\"", with: "  version \"0.27.0\"\r"),  // CRLF
        recepta().replacing("\n", with: "\r\n"),  // CRLF a tot el fitxer
        recepta().replacing("  sha256 \"\(sha256Antic)\"", with: "  sha256 :no_check"),
        recepta().replacing("  sha256 \"\(sha256Antic)\"", with: "  sha256 \"abc\""),
        recepta().replacing("  sha256 \"\(sha256Antic)\"", with: "  sha256 \"\(sha256Antic.uppercased())\""),
        recepta().replacing("  sha256 \"\(sha256Antic)\"", with: "\tsha256 \"\(sha256Antic)\""),
        "",
    ])
    func unaReceptaAmbUnaAltraFormaNoEsPublica(text: String) throws {
        let b = try Banc()
        try Data(text.utf8).write(to: b.fitxerRecepta)
        try b.comprovaRefus(conte: "no té exactament una línia")
    }

    /// Sense l'autor del commit del tap a git config, no compila ni publica res.
    @Test(arguments: ["user.name", "user.email"])
    func senseLAutorNoEsPublica(clau: String) throws {
        let b = try Banc()
        try b.git("config", "--unset", clau)
        try b.comprovaRefus(conte: "falta git config user.name o user.email")
    }

    /// Les notes donen primer Homebrew; el camí amb `gh` és l'alternativa.
    @Test func lesNotesDonenPrimerHomebrew() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let notes = b.notes()
        let instal·la = try #require(notes.range(of: "brew install --cask david-erra/tap/warp-launch"))
        let actualitza = try #require(notes.range(of: "brew upgrade --cask warp-launch"))
        let ambGh = try #require(notes.range(of: "gh api -H 'Accept: application/vnd.github.raw'"))
        #expect(instal·la.lowerBound < actualitza.lowerBound)
        #expect(actualitza.lowerBound < ambGh.lowerBound)
    }

    // --- Amb --aplica, la recepta s'escriu després de publicar.

    /// El PUT porta el sha del blob llegit, la branca, l'autor de git config, un missatge en català i el contingut d'una sola línia.
    @Test func escriuLaReceptaDespresDePublicar() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let ordres = b.ordresGh
        let publicacio = try #require(ordres.range(of: "release create"))
        let escriptura = try #require(ordres.range(of: "--method PUT"))
        #expect(publicacio.lowerBound < escriptura.lowerBound)
        #expect(ordres.contains("repos/\(tapDeProva)/contents/Casks/warp-launch.rb"))
        #expect(b.liniesPut.count == 8, "\(b.liniesPut)")
        #expect(b.campsPut["message"] == "chore: warp-launch passa a la 0.28.0")
        #expect(b.campsPut["branch"] == "main")
        #expect(try b.campsPut["sha"] == b.blobDeLaRecepta)
        #expect(b.campsPut["author[name]"] == "Prova")
        #expect(b.campsPut["author[email]"] == "prova@example.com")
        #expect(b.campsPut["committer[name]"] == "Prova")
        #expect(b.campsPut["committer[email]"] == "prova@example.com")
    }

    /// La recepta nova porta la versió i el sha256 del zip que s'ha pujat, i prou.
    @Test func laReceptaNovaEsLaDelZipPujat() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.zipPujat.count == 64)
        #expect(b.zipPujat != sha256Antic)
        let contingut = try #require(Data(base64Encoded: b.campsPut["content"] ?? ""))
        #expect(String(decoding: contingut, as: UTF8.self) == recepta(versio: "0.28.0", sha256: b.zipPujat))
    }

    /// Només canvien les dues línies: la resta queda byte a byte igual, encara que no sigui UTF-8 o no acabi amb un salt de línia.
    @Test func laRestaDeLaReceptaNoCanvia() throws {
        let abans = Data("# Recepta amb accents: línia\n  # version \"9.9.9\"\n#  version \"9.9.9\"\n#  sha256 \"\(sha256Antic)\"\n\tdesc \"x\"   \r\n".utf8) + Data([0xFF, 0x00, 0x0A])
        let despres = Data("\n  url \"https://github.com/exemple/prova/releases/download/v#{version}/WarpLaunch-#{version}.zip\"\n  sha256sum = 1\nend".utf8)
        let b = try Banc()
        try (abans + Data("  version \"0.27.0\"\n  sha256 \"\(sha256Antic)\"\n".utf8) + despres).write(to: b.fitxerRecepta)
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let contingut = try #require(Data(base64Encoded: b.campsPut["content"] ?? ""))
        #expect(contingut == abans + Data("  version \"0.28.0\"\n  sha256 \"\(b.zipPujat)\"\n".utf8) + despres)
    }

    /// Com la recepta de debò (un `livecheck` amb `url`, i textos en UTF-8): en surt la mateixa, amb les dues línies noves.
    @Test func unaReceptaComLaDeDebo() throws {
        func text(_ versio: String, _ sha256: String) -> String {
            #"""
            cask "warp-launch" do
              version "\#(versio)"
              sha256 "\#(sha256)"

              url "https://github.com/exemple/prova/releases/download/v#{version}/WarpLaunch-#{version}.zip"
              name "Warp Launch"
              desc "Reobre les finestres de Warp, cada pestanya amb la seva sessió de Claude Code"

              livecheck do
                url :url
                strategy :github_latest
              end

              postflight_steps do
                run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Warp Launch.app"], must_succeed: false
              end

              caveats <<~EOS
                Abans de desinstal·lar-la, a l'app: Configuració (⌘,) › General › «Restaura Warp i surt…».
                «« ·l· »»
              EOS
            end

            """#
        }
        let b = try Banc()
        try Data(text("0.27.0", sha256Antic).utf8).write(to: b.fitxerRecepta)
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let contingut = try #require(Data(base64Encoded: b.campsPut["content"] ?? ""))
        #expect(contingut == Data(text("0.28.0", b.zipPujat).utf8))
    }

    /// Amb un `base64` que talla la sortida en línies (el de GNU), el contingut continua essent d'una sola línia i el mateix.
    @Test func elContingutEsDUnaSolaLinia() throws {
        let b = try Banc()
        try Banc.executable(b.carpeta.appending(path: "bin/base64"), """
        #!/bin/bash
        [[ "${1:-}" == --decode ]] && exec /usr/bin/base64 "$@"
        exec /usr/bin/base64 -b 76 "$@"

        """)
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.liniesPut.count == 8, "\(b.liniesPut)")
        let contingut = try #require(Data(base64Encoded: b.campsPut["content"] ?? ""))
        #expect(String(decoding: contingut, as: UTF8.self) == recepta(versio: "0.28.0", sha256: b.zipPujat))
    }

    /// Si una eina falla a mig d'una canonada, l'script s'atura abans de publicar (no fa servir el que n'hagi sortit).
    @Test(arguments: ["base64", "shasum"])
    func siUnaEinaFallaNoEsPublica(eina: String) throws {
        let b = try Banc()
        try Banc.executable(b.carpeta.appending(path: "bin/\(eina)"), """
        #!/bin/bash
        [[ "${1:-}" == --decode ]] && exec /usr/bin/\(eina) "$@"
        printf 'a mitges  x'
        exit 1

        """)
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi != 0, "\(sortida)")
        #expect(!b.ordresGh.contains("release create"))
        #expect(!b.ordresGh.contains("--method PUT"))
    }

    /// Si algú canvia la recepta entre la lectura i l'escriptura, GitHub refusa el PUT (porta el sha llegit al principi) i no es trepitja res.
    @Test func siLaReceptaCanviaMentrestantNoLaTrepitja() throws {
        let b = try Banc()
        let blobLlegit = try b.blobDeLaRecepta
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_CANVIA_EN_LLEGIR": "1"]) { $1 })
        #expect(codi == 2, "\(sortida)")
        #expect(b.campsPut["sha"] == blobLlegit)
        #expect(b.ordresGh.components(separatedBy: "?ref=main").count == 2, "una sola lectura: \(b.ordresGh)")
        #expect(try String(contentsOf: b.fitxerRecepta, encoding: .utf8).hasSuffix("# un altre canvi\n"))
        #expect(sortida.contains("sha256 \"\(b.zipPujat)\""))
    }

    /// El missatge final diu com es desfà tot: la versió i el commit del tap.
    @Test func elMissatgeFinalDiuComEsDesfa() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("gh release delete v0.28.0 --repo exemple/prova --cleanup-tag"))
        #expect(sortida.contains("git revert \(commitDelTap)"))
        #expect(sortida.contains(tapDeProva))
    }

    /// Si la publicació falla, la recepta no es toca.
    @Test func siLaPublicacioFallaNoEscriuLaRecepta() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_RELEASE_FALLA": "1"]) { $1 })
        #expect(codi != 0, "\(sortida)")
        #expect(!b.ordresGh.contains("--method PUT"))
    }

    /// Si l'escriptura de la recepta falla, la versió es queda publicada i el missatge diu què cal canviar a mà.
    @Test func siLEscripturaFallaDiuQueCalFerAMa() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_PUT_FALLA": "1"]) { $1 })
        #expect(codi == 2, "\(sortida)")
        #expect(b.ordresGh.contains("release create"))
        #expect(!b.ordresGh.contains("release delete"))
        #expect(sortida.contains("la v0.28.0 ja és publicada a exemple/prova"))
        #expect(sortida.contains("Casks/warp-launch.rb"))
        #expect(sortida.contains("version \"0.28.0\""))
        #expect(sortida.contains("sha256 \"\(b.zipPujat)\""))
        #expect(!sortida.contains("Fet:"))
    }
}
