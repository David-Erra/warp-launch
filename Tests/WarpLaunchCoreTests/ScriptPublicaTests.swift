import CryptoKit
import Foundation
import Testing
@testable import WarpLaunchCore

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
      auto_updates true
      app "Warp Launch.app"
    end

    """
}

private let signaturaDeProva = String(repeating: "S", count: 86) + "=="
private let clauPublicaDeProva = String(repeating: "A", count: 43) + "="
private let feedDeProva = "https://github.com/exemple/prova/releases/latest/download/appcast.xml"

/// El fitxer amb l'adreça i la clau pública, com el de debò: només al repo temporal de la prova.
private func actualitzacionsPlist(feed: String = feedDeProva, clau: String = clauPublicaDeProva) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>SUFeedURL</key><string>\(feed)</string>
    <key>SUPublicEDKey</key><string>\(clau)</string>
    </dict></plist>

    """
}

@Suite struct ScriptPublicaTests {
    /// L'eina de debò, amb una clau d'un sol ús que només existeix durant la prova: bona 0, un byte canviat 1, una altra clau 1, entrada mal formada 64.
    @Test func laVerificacioDeLaSignatura() throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-verifica-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let eina = script.deletingLastPathComponent().appending(path: "verifica-signatura.swift")
        let entorn = ["HOME": carpeta.path, "TMPDIR": carpeta.path, "PATH": "/usr/bin:/bin"]
        let clau = Curve25519.Signing.PrivateKey()
        let publica = clau.publicKey.rawRepresentation.base64EncodedString()
        let altra = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let contingut = Data("un zip de prova".utf8)
        let signatura = try clau.signature(for: contingut).base64EncodedString()
        let zip = carpeta.appending(path: "prova.zip")
        let tocat = carpeta.appending(path: "tocat.zip")
        try contingut.write(to: zip)
        try Data("un zip de provb".utf8).write(to: tocat)
        for (arguments, esperat) in [
            ([publica, signatura, zip.path], 0), ([publica, signatura, tocat.path], 1), ([altra, signatura, zip.path], 1),
            ([publica, signatura], 64), (["no-es-base64", signatura, zip.path], 64), ([publica, "no-es-base64", zip.path], 64),
            ([publica, signatura, carpeta.appending(path: "no-hi-es").path], 64),
        ] as [([String], Int32)] {
            let (codi, sortida) = try executaPrograma("/usr/bin/swift", [eina.path] + arguments, entorn: entorn)
            #expect(codi == esperat, "\(arguments): \(sortida)")
        }
    }

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
        var fitxerTokenCompilacio: URL { carpeta.appending(path: "token-compilacio.txt") }
        var fitxerZipPujat: URL { carpeta.appending(path: "zip-pujat.txt") }
        var fitxerArgumentsCompilacio: URL { carpeta.appending(path: "arguments-compilacio.txt") }
        var fitxerActualitzacions: URL { repo.appending(path: "Recursos/Actualitzacions.plist") }
        var registreSign: URL { carpeta.appending(path: "sign.log") }
        var ordresSign: [String] { ((try? String(contentsOf: registreSign, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        var fitxerTokenSign: URL { carpeta.appending(path: "token-sign.txt") }
        var registreVerifica: URL { carpeta.appending(path: "verifica.log") }
        var ordresVerifica: [String] { ((try? String(contentsOf: registreVerifica, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        var appcast: String { (try? String(contentsOf: repo.appending(path: "build/appcast.xml"), encoding: .utf8)) ?? "" }
        var appcastDeProva: String { (try? String(contentsOf: repo.appending(path: "build/appcast-prova-0.28.0.xml"), encoding: .utf8)) ?? "" }
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
            printf '%s' "$*" > "$BUILD_FALS_ARGUMENTS"
            APP="build/Warp Launch.app"
            rm -rf "$APP"
            mkdir -p "$APP/Contents/MacOS"
            VERSIO_INFO="${BUILD_FALS_BUNDLE_VERSION:-$(cat VERSION)}"
            cat > "$APP/Contents/Info.plist" <<EOF
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>cat.davide.warp-launch</string>
            <key>CFBundleExecutable</key><string>WarpLaunch</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>$(cat VERSION)</string>
            <key>CFBundleVersion</key><string>$VERSIO_INFO</string>
            <key>LSMinimumSystemVersion</key><string>26.0</string>
            </dict></plist>
            EOF
            if [[ -z "${BUILD_FALS_SENSE_FEED:-}" ]]; then /usr/libexec/PlistBuddy -c "Merge Recursos/Actualitzacions.plist" "$APP/Contents/Info.plist" > /dev/null; fi
            if [[ -n "${BUILD_FALS_SENSE_MINIM:-}" ]]; then /usr/libexec/PlistBuddy -c "Delete LSMinimumSystemVersion" "$APP/Contents/Info.plist"; fi
            if [[ -n "${BUILD_FALS_ALTRA_CLAU:-}" ]]; then /usr/libexec/PlistBuddy -c "Set SUPublicEDKey $BUILD_FALS_ALTRA_CLAU" "$APP/Contents/Info.plist"; fi
            printf '%s' "${GH_TOKEN:-}${GITHUB_TOKEN:-}" > "$BUILD_FALS_TOKEN"
            printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/WarpLaunch"
            chmod 755 "$APP/Contents/MacOS/WarpLaunch"
            # Les peces de Sparkle: l'identificador és el seu, i `BUILD_FALS_ALIE` en signa una com si fos d'un altre.
            signa_peca() {
                local id=prova.interior
                [[ "${BUILD_FALS_ALIE:-}" == "$1" ]] && id=prova.alie
                codesign --force --sign - --timestamp=none --identifier "$id" "$2" 2>/dev/null
            }
            if [[ -z "${BUILD_FALS_SENSE_FRAMEWORK:-}" ]]; then
                FW="$APP/Contents/Frameworks/Sparkle.framework"
                mkdir -p "$FW/Versions/B/Resources" "$FW/Versions/B/Updater.app/Contents/MacOS"
                cp /usr/bin/true "$FW/Versions/B/Sparkle"
                cp /usr/bin/true "$FW/Versions/B/Autoupdate"
                cp /usr/bin/true "$FW/Versions/B/Updater.app/Contents/MacOS/Updater"
                peca() { printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>prova.interior</string><key>CFBundleExecutable</key><string>%s</string><key>CFBundlePackageType</key><string>%s</string></dict></plist>' "$1" "$2"; }
                peca Sparkle FMWK > "$FW/Versions/B/Resources/Info.plist"
                peca Updater APPL > "$FW/Versions/B/Updater.app/Contents/Info.plist"
                ln -s B "$FW/Versions/Current"
                ln -s Versions/Current/Sparkle "$FW/Sparkle"
                ln -s Versions/Current/Resources "$FW/Resources"
                signa_peca Autoupdate "$FW/Versions/B/Autoupdate"
                signa_peca Updater.app "$FW/Versions/B/Updater.app"
                signa_peca Sparkle.framework "$FW"
            fi
            codesign --force --sign - --timestamp=none "$APP" 2>/dev/null

            """#)
            try Data("\(versio)\n".utf8).write(to: repo.appending(path: "VERSION"))
            try Data("/build/\n".utf8).write(to: repo.appending(path: ".gitignore"))
            try Data(recepta().utf8).write(to: fitxerRecepta)
            try FileManager.default.createDirectory(at: fitxerActualitzacions.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(actualitzacionsPlist().utf8).write(to: fitxerActualitzacions)
            // `gh` fals: `release view` diu si ja hi és (GH_FALS_JA_HI_ES), `release list` diu l'última (GH_FALS_ANTERIOR). I `api`
            // fa de GitHub per a la recepta: el GET torna el JSON de debò (el base64 amb salts de línia, i el sha de git del fitxer)
            // i hi aplica el --jq, i el PUT només passa si el sha és el del fitxer d'ara. Les eines, amb la ruta sencera: unes
            // proves en posen de falses al PATH, només per a l'script.
            try Self.executable(carpeta.appending(path: "bin/gh"), #"""
            #!/bin/bash
            echo "${GH_TOKEN:+[token:$GH_TOKEN] }$*" >> "$GH_FALS_REGISTRE"
            case "$1 $2" in
                "release view")
                    if [[ "${7:-}" == isDraft ]]; then [[ -n "${GH_FALS_ES_ESBORRANY:-}" ]] || exit 1; echo "$GH_FALS_ES_ESBORRANY"; exit 0; fi
                    if [[ "$3" != --repo ]]; then [[ -n "${GH_FALS_JA_HI_ES:-}" ]] && exit 0 || exit 1; fi
                    # Sense etiqueta, `gh` torna la marcada com a última.
                    if [[ "$6" == tagName,assets ]]; then
                        [[ -z "${GH_FALS_DESPRES_FALLA:-}" ]] || exit 1
                        /usr/bin/jq -n --arg tag "${GH_FALS_DESPRES_ULTIMA:-$(cat "$GH_FALS_CREADA")}" --arg actius "${GH_FALS_ACTIUS:-WarpLaunch-0.28.0.zip appcast.xml}" \
                            '{tagName: $tag, assets: ($actius | split(" ") | map({name: .}))}' | /usr/bin/jq -r "$8"
                        exit 0
                    fi
                    [[ -z "${GH_FALS_ULTIMA_FALLA:-}" ]] || exit 1
                    ULTIMA="${GH_FALS_ULTIMA:-${GH_FALS_ANTERIOR:-}}"
                    [[ -n "$ULTIMA" ]] || exit 1
                    /usr/bin/jq -n --arg tag "$ULTIMA" '{tagName: $tag}' | /usr/bin/jq -r "$8"
                    exit 0 ;;
                "release list") echo "${GH_FALS_ANTERIOR:-}"; exit 0 ;;
                "release create")
                    [[ -z "${GH_FALS_RELEASE_FALLA:-}" ]] || exit 1
                    /usr/bin/shasum -a 256 "$4" | cut -c1-64 > "$GH_FALS_ZIP_PUJAT"
                    printf '%s' "$3" > "$GH_FALS_CREADA"
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
            CONTINGUT="$(/usr/bin/base64 < "$GH_FALS_RECEPTA" | /usr/bin/fold -w 60)"
            [[ -z "${GH_FALS_TRUNCA:-}" ]] || CONTINGUT="${CONTINGUT:0:$GH_FALS_TRUNCA}"
            /usr/bin/jq -n --arg contingut "$CONTINGUT" --arg blob "$BLOB" \
                --arg codificacio "${GH_FALS_CODIFICACIO:-base64}" \
                '{type: "file", encoding: $codificacio, sha: $blob, content: ($contingut + "\n")}' | /usr/bin/jq -r "$FILTRE"
            [[ -z "${GH_FALS_CANVIA_EN_LLEGIR:-}" ]] || printf '# un altre canvi\n' >> "$GH_FALS_RECEPTA"

            """#)
            // Les eines de signar i comprovar, falses: mai no toquen el clauer. La falsa de signar només accepta el zip, sense opcions.
            try Self.executable(carpeta.appending(path: "bin/sign-fals"), #"""
            #!/bin/bash
            echo "$*" >> "$SIGN_FALS_REGISTRE"
            printf '%s' "${GH_TOKEN:-}${GITHUB_TOKEN:-}" >> "$SIGN_FALS_TOKEN"
            [[ -z "${SIGN_FALS_FALLA:-}" ]] || exit 1
            if [[ -n "${SIGN_FALS_SORTIDA:-}" ]]; then printf '%s\n' "$SIGN_FALS_SORTIDA"; exit 0; fi
            [[ $# -eq 1 ]] || exit 9
            printf 'sparkle:edSignature="%s" length="%s"\n' "$SIGN_FALS_SIGNATURA" "${SIGN_FALS_MIDA:-$(/usr/bin/wc -c < "$1" | /usr/bin/tr -d ' ')}"

            """#)
            try Self.executable(carpeta.appending(path: "bin/verifica-fals"), #"""
            #!/bin/bash
            echo "$*" >> "$VERIFICA_FALS_REGISTRE"
            printf '%s' "${GH_TOKEN:-}${GITHUB_TOKEN:-}" >> "$SIGN_FALS_TOKEN"
            exit "${VERIFICA_FALS_CODI:-0}"

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
                "GH_FALS_CREADA": carpeta.appending(path: "creada.txt").path,
                "WARP_LAUNCH_SIGN_UPDATE": carpeta.appending(path: "bin/sign-fals").path,
                "WARP_LAUNCH_VERIFICA": carpeta.appending(path: "bin/verifica-fals").path,
                "SIGN_FALS_REGISTRE": registreSign.path, "SIGN_FALS_TOKEN": fitxerTokenSign.path, "SIGN_FALS_SIGNATURA": signaturaDeProva,
                "VERIFICA_FALS_REGISTRE": registreVerifica.path,
                "BUILD_FALS_TOKEN": fitxerTokenCompilacio.path, "BUILD_FALS_ARGUMENTS": fitxerArgumentsCompilacio.path,
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
        func comprovaRefus(conte text: String, entorn extra: [String: String] = [:], sourceLocation: SourceLocation = #_sourceLocation) throws {
            for arguments: [String] in [[], ["--aplica"]] {
                let (codi, sortida) = try executaScript(repo.appending(path: "scripts/publica.sh"), arguments, entorn: entornDeProva.merging(extra) { _, nou in nou })
                #expect(codi == 1, "\(sortida)", sourceLocation: sourceLocation)
                #expect(sortida.contains(text), "\(sortida)", sourceLocation: sourceLocation)
                #expect(sortida.contains("No s'ha publicat res."), "\(sortida)", sourceLocation: sourceLocation)
                #expect(!compilat, "no ha de compilar res", sourceLocation: sourceLocation)
                #expect(!ordresGh.contains("release create"), sourceLocation: sourceLocation)
                #expect(!ordresGh.contains("--method PUT"), sourceLocation: sourceLocation)
            }
        }

        /// Signatura ad hoc: el requisit només hi demana l'identificador (sense el certificat de debò).
        static let requisitDeProva = ["WARP_LAUNCH_REQUISIT": #"identifier "cat.davide.warp-launch""#,
                                      "WARP_LAUNCH_REQUISIT_SPARKLE": #"identifier "prova.interior""#]

        /// Refusa després de compilar: amb --aplica i sense, sense res a GitHub.
        func comprovaRefusDespresDeCompilar(conte text: String, entorn extra: [String: String]) throws {
            for arguments: [String] in [[], ["--aplica"]] {
                let (codi, sortida) = try executaScript(repo.appending(path: "scripts/publica.sh"), arguments,
                                                        entorn: entornDeProva.merging(Self.requisitDeProva) { $1 }.merging(extra) { $1 })
                #expect(codi == 1, "\(sortida)")
                #expect(sortida.contains(text), "\(sortida)")
                #expect(sortida.contains("No s'ha publicat res."), "\(sortida)")
                #expect(!ordresGh.contains("release create"))
                #expect(!ordresGh.contains("--method PUT"))
                #expect(ordresSign.isEmpty, "un paquet refusat no es signa")
                #expect(ordresVerifica.isEmpty, "un paquet refusat no es comprova")
            }
        }

        /// Canvia el fitxer de l'adreça, i ho deixa tot a origin/main.
        func posaActualitzacions(_ text: String?) throws {
            if let text { try Data(text.utf8).write(to: fitxerActualitzacions) } else { try FileManager.default.removeItem(at: fitxerActualitzacions) }
            try commit("chore: l'adreça", afegeix: true)
            try git("push", "-q", "origin", "main")
        }
    }

    /// Només la còpia que es publica porta l'adreça (decisió 3).
    @Test func compilaAmbLAdreca() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(try String(contentsOf: b.fitxerArgumentsCompilacio, encoding: .utf8) == "release --amb-feed")
    }

    /// El requisit de les peces de Sparkle és el certificat de l'app, sense el seu identificador: les peces tenen el seu.
    @Test func elRequisitDeSparkleEsNomesElCertificat() throws {
        let text = try String(contentsOf: script, encoding: .utf8)
        let linies = text.split(separator: "\n").filter { $0.hasPrefix("REQUISIT=") || $0.hasPrefix("REQUISIT_SPARKLE=") }.map(String.init)
        #expect(linies.count == 2, "\(linies)")
        let valor = try sortidaDe("/bin/bash", "IDENTIFICADOR=cat.davide.warp-launch; unset WARP_LAUNCH_REQUISIT WARP_LAUNCH_REQUISIT_SPARKLE; "
                                  + linies.joined(separator: "; ") + "; printf '%s\\0' \"$REQUISIT_SPARKLE\"")
        #expect(valor.first?.hasPrefix(#"certificate leaf = H""#) == true, "\(valor)")
        #expect(valor.first?.contains("identifier") == false, "\(valor)")
        let binari = FileManager.default.temporaryDirectory.appending(path: "warp-launch-requisit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: binari) }
        let csreq = try executaPrograma("/usr/bin/csreq", ["-r=" + (valor.first ?? ""), "-b", binari.path], entorn: [:])
        #expect(csreq.codi == 0, "\(csreq.sortida)")
    }

    /// Una còpia que no porta bé l'adreça o la clau no es publica.
    @Test(arguments: [
        (nil, "ha de portar SUFeedURL"),
        (actualitzacionsPlist(feed: "http://127.0.0.1:48917/appcast.xml"), "ha de portar SUFeedURL"),
        (actualitzacionsPlist(feed: "https://github.com/exemple/una-altra/releases/latest/download/appcast.xml"), "ha de portar SUFeedURL"),
        (actualitzacionsPlist(clau: ""), "ha de portar SUFeedURL"),
    ] as [(String?, String)])
    func senseLAdrecaNoEsPublica(text: String?, missatge: String) throws {
        let b = try Banc()
        try b.posaActualitzacions(text)
        try b.comprovaRefus(conte: missatge)
    }

    /// Mirat al paquet ja compilat: el que va als Macs és això.
    @Test(arguments: [
        (["BUILD_FALS_SENSE_FRAMEWORK": "1"], "no porta Sparkle.framework"),
        (["BUILD_FALS_BUNDLE_VERSION": "0.27.0"], "CFBundleVersion"),
        (["BUILD_FALS_SENSE_MINIM": "1"], "quina versió de macOS"),
        (["BUILD_FALS_SENSE_FEED": "1"], "no porta l'adreça i la clau"),
        (["BUILD_FALS_ALTRA_CLAU": String(repeating: "B", count: 43) + "="], "no porta l'adreça i la clau"),
        (["BUILD_FALS_ALIE": "Autoupdate"], "Versions/B/Autoupdate» no està signada"),
        (["BUILD_FALS_ALIE": "Updater.app"], "Versions/B/Updater.app» no està signada"),
        (["BUILD_FALS_ALIE": "Sparkle.framework"], "Sparkle.framework» no està signada"),
    ] as [([String: String], String)])
    func unPaquetIncorrecteNoEsPublica(entorn: [String: String], missatge: String) throws {
        let b = try Banc()
        try b.comprovaRefusDespresDeCompilar(conte: missatge, entorn: entorn)
    }

    /// El mode de prova escriu l'appcast sense signar, amb tot el que porta el de debò.
    @Test func elModeDeProvaEscriuLAppcastSenseSignar() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let xml = b.appcastDeProva
        let mida = try #require(try FileManager.default.attributesOfItem(atPath: b.zip.path)[.size] as? Int)
        let url = "https://github.com/exemple/prova/releases/download/v0.28.0/WarpLaunch-0.28.0.zip"
        #expect(xml.contains("<sparkle:version>0.28.0</sparkle:version>"), "\(xml)")
        #expect(xml.contains("<sparkle:shortVersionString>0.28.0</sparkle:shortVersionString>"), "\(xml)")
        #expect(xml.contains("<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>"), "\(xml)")
        #expect(xml.contains("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"), "\(xml)")
        #expect(xml.contains(#"<enclosure url="\#(url)" length="\#(mida)" type="application/octet-stream" sparkle:edSignature="SENSE-SIGNAR"/>"#), "\(xml)")
        #expect(xml.components(separatedBy: "<item>").count == 2, "\(xml)")
        // La mateixa regla que aplica l'app: si no la passés, totes les còpies refusarien l'actualització.
        #expect(PoliticaActualitzacions.enclosureValid(feed: feedDeProva, enclosure: url))
    }

    /// Els canvis de l'actualitzador avisen; no aturen res.
    @Test(arguments: ["Package.resolved", "Sources/WarpLaunchApp/ServeiActualitzacions.swift", "scripts/build-app.sh"])
    func avisaSiCanviaLActualitzador(fitxer: String) throws {
        let b = try Banc()
        try b.git("tag", "v0.27.0")
        try b.git("push", "-q", "origin", "v0.27.0")
        try b.git("tag", "-d", "v0.27.0")
        let ruta = b.repo.appending(path: fitxer)
        try FileManager.default.createDirectory(at: ruta.deletingLastPathComponent(), withIntermediateDirectories: true)
        let abans = (try? Data(contentsOf: ruta)) ?? Data()
        try (abans + Data("\n".utf8)).write(to: ruta)
        try b.commit("chore: toca \(fitxer)", afegeix: true)
        try b.git("push", "-q", "origin", "main")
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["GH_FALS_ANTERIOR": "v0.27.0"]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("Avís: aquesta versió canvia l'actualitzador: passa les rondes A i C"), "\(sortida)")
    }

    /// Sense canvis de l'actualitzador, cap avís.
    @Test func senseCanvisDeLActualitzadorNoAvisa() throws {
        let b = try Banc()
        try b.git("tag", "v0.27.0")
        try b.git("push", "-q", "origin", "v0.27.0")
        try b.git("tag", "-d", "v0.27.0")
        try Data("x".utf8).write(to: b.repo.appending(path: "un-altre.txt"))
        try b.commit("chore: una altra cosa", afegeix: true)
        try b.git("push", "-q", "origin", "main")
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["GH_FALS_ANTERIOR": "v0.27.0"]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(!sortida.contains("canvia l'actualitzador"), "\(sortida)")
    }

    // --- `latest`: el que llegeixen totes les còpies, abans de compilar.

    @Test(arguments: ["v0.28.0", "v0.28.1", "v0.100.0", "v1.0.0"])
    func unaUltimaIgualOMesNovaNoEsPublica(etiqueta: String) throws {
        let b = try Banc()
        try b.comprovaRefus(conte: "no és anterior a la 0.28.0", entorn: ["GH_FALS_ULTIMA": etiqueta])
    }

    @Test(arguments: ["v0.9.0", "v0.27.99"])
    func unaUltimaAnteriorEsPublica(etiqueta: String) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva.merging(["GH_FALS_ULTIMA": etiqueta]) { $1 })
        #expect(codi == 0, "\(sortida)")
    }

    @Test func unaUltimaAmbUnaAltraFormaNoEsPublica() throws {
        let b = try Banc()
        try b.comprovaRefus(conte: "no té la forma vX.Y.Z", entorn: ["GH_FALS_ULTIMA": "latest"])
    }

    /// Si hi ha versions però no se sap quina és l'última, no es continua a cegues.
    @Test func senseSaberLUltimaNoEsPublica() throws {
        let b = try Banc()
        try b.git("tag", "v0.27.0")
        try b.git("push", "-q", "origin", "v0.27.0")
        try b.git("tag", "-d", "v0.27.0")
        try b.comprovaRefus(conte: "no s'ha pogut saber quina és l'última", entorn: ["GH_FALS_ANTERIOR": "v0.27.0", "GH_FALS_ULTIMA_FALLA": "1"])
    }

    /// Sense `auto_updates`, Homebrew trepitjaria el que l'app s'ha actualitzat sola. Cal exactament aquesta línia.
    @Test(arguments: [
        recepta().replacing("  auto_updates true\n", with: ""),
        recepta().replacing("  auto_updates true\n", with: "  auto_updates false\n"),
        recepta().replacing("  auto_updates true\n", with: "    auto_updates true\n"),
        recepta().replacing("  auto_updates true\n", with: "  auto_updates true # comentari\n"),
        recepta().replacing("  auto_updates true\n", with: "  auto_updates true\n  auto_updates true\n"),
    ])
    func unaReceptaSenseAutoUpdatesNoEsPublica(text: String) throws {
        let b = try Banc()
        try Data(text.utf8).write(to: b.fitxerRecepta)
        try b.comprovaRefus(conte: "«  auto_updates true»")
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
        #expect(b.ordresGh.contains("release create v0.28.0 build/WarpLaunch-0.28.0.zip build/appcast.xml --repo exemple/prova --latest --target \(commit)"
                                    + " --title Warp Launch 0.28.0 --notes-file build/notes-0.28.0.md"))
        #expect(!sortida.contains("release delete"), "publicar ja no es desfà: \(sortida)")
        #expect(sortida.contains("Publicar ja no es desfà."), "\(sortida)")
    }

    // --- La signatura: només amb --aplica, i abans de crear res a GitHub.

    /// El mode de prova no toca el clauer: ni signa ni comprova.
    @Test func elModeDeProvaNoSigna() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresSign.isEmpty)
        #expect(b.ordresVerifica.isEmpty)
        #expect(b.appcast.isEmpty)
    }

    /// Signa el zip que es puja, una sola vegada i sense cap opció, i comprova la signatura amb la clau que porta l'app compilada.
    @Test func signaIComprovaElZipQueEsPuja() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresSign == ["build/WarpLaunch-0.28.0.zip"])
        #expect(b.ordresVerifica == ["\(clauPublicaDeProva) \(signaturaDeProva) build/WarpLaunch-0.28.0.zip"])
    }

    /// L'appcast que es puja porta la versió, l'adreça, la mida i la signatura del zip.
    @Test func lAppcastPortaElQueToca() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        let xml = b.appcast
        let mida = try #require(try FileManager.default.attributesOfItem(atPath: b.zip.path)[.size] as? Int)
        let url = "https://github.com/exemple/prova/releases/download/v0.28.0/WarpLaunch-0.28.0.zip"
        #expect(xml.contains("<sparkle:version>0.28.0</sparkle:version>"), "\(xml)")
        #expect(xml.contains(#"<enclosure url="\#(url)" length="\#(mida)" type="application/octet-stream" sparkle:edSignature="\#(signaturaDeProva)"/>"#), "\(xml)")
        #expect(!xml.contains("SENSE-SIGNAR"), "\(xml)")
    }

    /// Si la signatura no és bona, no es crea res a GitHub ni es toca la recepta.
    @Test(arguments: [
        (["SIGN_FALS_FALLA": "1"], "no s'ha pogut signar"),
        (["SIGN_FALS_SORTIDA": "alguna cosa"], "no té la forma esperada"),
        (["SIGN_FALS_SORTIDA": #"sparkle:edSignature="\#(String(repeating: "S", count: 85))==" length="10""#], "no té la forma esperada"),
        (["SIGN_FALS_SORTIDA": #"sparkle:edSignature="\#(signaturaDeProva)""#], "no té la forma esperada"),
        (["SIGN_FALS_SORTIDA": "avís\nsparkle:edSignature=\"\(signaturaDeProva)\" length=\"10\""], "no té la forma esperada"),
        (["SIGN_FALS_MIDA": "1"], "bytes"),
        (["VERIFICA_FALS_CODI": "1"], "la clau d'aquest clauer no és la que porten les apps"),
        (["VERIFICA_FALS_CODI": "64"], "la clau d'aquest clauer no és la que porten les apps"),
    ] as [([String: String], String)])
    func siLaSignaturaNoEsBonaNoEsPublica(entorn: [String: String], missatge: String) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(entorn) { $1 })
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains(missatge), "\(sortida)")
        #expect(sortida.contains("No s'ha publicat res."), "\(sortida)")
        #expect(!b.ordresGh.contains("release create"), "\(b.ordresGh)")
        #expect(!b.ordresGh.contains("--method PUT"), "\(b.ordresGh)")
    }

    /// Si GitHub no la dona com a última amb l'appcast, la versió es queda però la recepta no es toca, i ho diu.
    @Test(arguments: [
        ["GH_FALS_DESPRES_ULTIMA": "v0.27.0"], ["GH_FALS_ACTIUS": "WarpLaunch-0.28.0.zip"], ["GH_FALS_ACTIUS": "appcast.xml"], ["GH_FALS_DESPRES_FALLA": "1"],
    ])
    func siGitHubNoLaDonaComAUltimaAvisa(entorn: [String: String]) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(entorn) { $1 })
        #expect(codi == 2, "\(sortida)")
        #expect(sortida.contains("GitHub no la dona com a última amb el seu appcast.xml"), "\(sortida)")
        #expect(b.ordresGh.contains("release create"))
        #expect(!b.ordresGh.contains("--method PUT"))
        #expect(!b.ordresGh.contains("release delete"))
        #expect(sortida.contains("sha256 \"\(b.zipPujat)\""), "\(sortida)")
        #expect(!sortida.contains("Fet:"), "\(sortida)")
    }

    /// Les notes diuen que l'app s'actualitza sola, que va encès de sèrie, com apagar-ho i que la primera vegada és a mà.
    @Test func lesNotesDiuenQueSActualitzaSola() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.notes().contains("L'app s'actualitza sola"), "\(b.notes())")
        #expect(b.notes().contains("Va encès de sèrie"), "\(b.notes())")
        #expect(b.notes().contains("Configuració › «Actualitzacions» › «Actualitza automàticament»"), "\(b.notes())")
        // La 0.31.5 és l'última publicada sense actualitzador: qui la tingui no es podria actualitzar sol.
        #expect(b.notes().contains("Si tens la 0.31.5 o una d'anterior, l'has d'actualitzar a mà una última vegada"), "\(b.notes())")
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

    /// Una VERSION que no sigui X.Y.Z no es publica: va a la substitució de la recepta, i la recepta només en sap llegir aquesta forma.
    @Test(arguments: ["0.28", "0.28.0-beta", "1.2.3.4", "v0.28.0", "0.28/0", "0.28.0&", "0.28.0\\", ""])
    func unaVersioAmbUnaAltraFormaNoEsPublica(versio: String) throws {
        let b = try Banc(versio: versio)
        try b.comprovaRefus(conte: "no té la forma X.Y.Z")
        #expect(b.ordresGh.isEmpty, "\(b.ordresGh)")
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

    /// El contingut descodificat ha de ser el del blob que GitHub diu: el `base64` de macOS no falla amb una entrada tallada.
    /// Tallat aquí, encara hi ha les línies `version` i `sha256`.
    @Test(arguments: [("GH_FALS_TRUNCA", "200"), ("GH_FALS_BLOB", "xyz"), ("GH_FALS_BLOB", String(repeating: "0", count: 40))])
    func siElContingutNoEsElDelBlobNoEsPublica(clau: String, valor: String) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging([clau: valor]) { $1 })
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("com s'esperava"), "\(sortida)")
        #expect(sortida.contains("No s'ha publicat res."), "\(sortida)")
        #expect(!b.compilat)
        #expect(!b.ordresGh.contains("release create"))
        #expect(!b.ordresGh.contains("--method PUT"))
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

    /// La URL ha de dependre de `version` i ser la d'aquest repo: si no, la recepta nova demanaria un altre zip amb el sha256 d'aquest.
    @Test(arguments: [
        recepta().replacing("v#{version}/WarpLaunch-#{version}.zip", with: "v0.27.0/WarpLaunch-0.27.0.zip"),  // la versió, escrita a mà
        recepta().replacing("v#{version}/WarpLaunch-#{version}.zip", with: "v#{version}/WarpLaunch-0.27.0.zip"),
        recepta().replacing("github.com/exemple/prova/", with: "github.com/exemple/una-altra/"),
        recepta().replacing("WarpLaunch-#{version}.zip\"", with: "WarpLaunch-#{version}.zip\" # comentari"),
        recepta().replacing("  url \"https", with: "    url \"https"),  // dins d'un bloc
        recepta().replacing("  name \"Warp Launch\"\n", with: "  url \"https://github.com/exemple/prova/releases/download/v#{version}/WarpLaunch-#{version}.zip\"\n  name \"Warp Launch\"\n"),  // dues
        recepta().split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.contains("  url ") }.joined(separator: "\n"),  // sense la línia
    ])
    func unaReceptaAmbUnaAltraUrlNoEsPublica(text: String) throws {
        let b = try Banc()
        try Data(text.utf8).write(to: b.fitxerRecepta)
        try b.comprovaRefus(conte: "no té exactament una línia «  url")
    }

    /// Una recepta que ja va per davant no es fa baixar de versió. Es compara com a nombres: la 0.100 és posterior a la 0.28.
    @Test(arguments: ["0.29.0", "0.28.1", "0.100.0", "1.0.0"])
    func unaReceptaMesNovaNoEsPublica(versio: String) throws {
        let b = try Banc()
        try Data(recepta(versio: versio).utf8).write(to: b.fitxerRecepta)
        try b.comprovaRefus(conte: "més nova que la 0.28.0")
    }

    /// Una d'anterior o la mateixa sí: la 0.9 és anterior a la 0.28.
    @Test(arguments: ["0.9.0", "0.27.99", "0.28.0"])
    func unaReceptaAnteriorOIgualEsPublica(versio: String) throws {
        let b = try Banc()
        try Data(recepta(versio: versio).utf8).write(to: b.fitxerRecepta)
        let (codi, sortida) = try b.executa(entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
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
        let abans = Data("# Recepta amb accents: línia\n  # version \"9.9.9\"\n#  version \"9.9.9\"\n#  sha256 \"\(sha256Antic)\"\n\tdesc \"x\"   \r\n  auto_updates true\n".utf8) + Data([0xFF, 0x00, 0x0A])
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

              auto_updates true

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
    @Test(arguments: ["base64", "shasum", "xmllint"])
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

    /// Si la recepta ja diu aquesta versió i aquest sha256, no hi ha res per escriure: cap PUT, i els missatges ho diuen.
    @Test func siLaReceptaJaDiuElMateixNoLaEscriu() throws {
        let b = try Banc()
        // Un `ditto` fals: el zip, i per tant el sha256, sempre són els mateixos.
        try Banc.executable(b.carpeta.appending(path: "bin/ditto"), #"""
        #!/bin/bash
        printf 'zip fix\n' > "${@: -1}"

        """#)
        let fix = b.carpeta.appending(path: "fix")
        try Data("zip fix\n".utf8).write(to: fix)
        try Data(recepta(versio: "0.28.0", sha256: try b.sha256(de: fix)).utf8).write(to: b.fitxerRecepta)

        let prova = try b.executa(entorn: Banc.requisitDeProva)
        #expect(prova.codi == 0, "\(prova.sortida)")
        #expect(prova.sortida.contains("no caldria escriure-la"), "\(prova.sortida)")
        #expect(!prova.sortida.contains("I canviaria"), "\(prova.sortida)")

        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresGh.contains("release create"))
        #expect(!b.ordresGh.contains("--method PUT"))
        #expect(sortida.contains("no s'ha escrit"), "\(sortida)")
        #expect(sortida.contains("Publicar ja no es desfà."), "\(sortida)")
        #expect(!sortida.contains("git revert"), "no hi ha cap commit per revertir: \(sortida)")
    }

    /// La mateixa versió amb un altre zip (una versió esborrada i tornada a publicar): el PUT hi va, i si falla, el missatge no diu que Homebrew va bé.
    @Test func laMateixaVersioAmbUnAltreZip() throws {
        let b = try Banc()
        try Data(recepta(versio: "0.28.0").utf8).write(to: b.fitxerRecepta)
        let bona = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(bona.codi == 0, "\(bona.sortida)")
        let contingut = try #require(Data(base64Encoded: b.campsPut["content"] ?? ""))
        #expect(String(decoding: contingut, as: UTF8.self) == recepta(versio: "0.28.0", sha256: b.zipPujat))

        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_PUT_FALLA": "1"]) { $1 })
        #expect(codi == 2, "\(sortida)")
        #expect(sortida.contains("Homebrew refusarà la 0.28.0"), "\(sortida)")
        #expect(!sortida.contains("continua instal·lant"), "\(sortida)")
    }

    /// El token només arriba a `gh`: ni a la compilació ni a cap missatge, tampoc quan falla l'escriptura.
    @Test(arguments: [(true, [:]), (true, ["GH_FALS_PUT_FALLA": "1"]), (false, [:])] as [(Bool, [String: String])])
    func elTokenNomesArribaAGh(aplica: Bool, extra: [String: String]) throws {
        let token = "token-de-prova-1", altre = "token-de-prova-2"
        let b = try Banc()
        let entorn = Banc.requisitDeProva.merging(extra) { $1 }.merging(["GH_TOKEN": token, "GITHUB_TOKEN": altre]) { $1 }
        let (codi, sortida) = aplica ? try b.executa("--aplica", entorn: entorn) : try b.executa(entorn: entorn)
        #expect(codi == (extra.isEmpty ? 0 : 2), "\(sortida)")
        #expect(!sortida.contains(token) && !sortida.contains(altre), "\(sortida)")
        #expect(try String(contentsOf: b.fitxerTokenCompilacio, encoding: .utf8) == "")
        #expect(((try? String(contentsOf: b.fitxerTokenSign, encoding: .utf8)) ?? "") == "", "ni a les eines de signar i comprovar")
        #expect(b.ordresGh.contains("[token:\(token)] api repos/"), "\(b.ordresGh)")
        if aplica {
            #expect(b.ordresGh.contains("[token:\(token)] release create"), "\(b.ordresGh)")
            #expect(b.ordresGh.contains("[token:\(token)] api --method PUT"), "\(b.ordresGh)")
        }
    }

    /// El missatge final diu com s'atura: tornar `latest` a l'anterior, revertir la recepta i publicar una correcció. Esborrar no serveix.
    @Test func elMissatgeFinalDiuComSAtura() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_ULTIMA": "v0.27.0"]) { $1 })
        #expect(codi == 0, "\(sortida)")
        let anterior = try #require(sortida.range(of: "gh release edit v0.27.0 --latest --repo exemple/prova"), "\(sortida)")
        let revert = try #require(sortida.range(of: "git revert \(commitDelTap) en un clon de \(tapDeProva)"), "\(sortida)")
        let correccio = try #require(sortida.range(of: "publica una correcció amb una versió superior"), "\(sortida)")
        #expect(anterior.lowerBound < revert.lowerBound && revert.lowerBound < correccio.lowerBound, "\(sortida)")
        #expect(!sortida.contains("release delete"), "\(sortida)")
    }

    /// La primera publicació no té cap versió anterior a la qual tornar.
    @Test func laPrimeraVersioNoProposaTornarEnrere() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva)
        #expect(codi == 0, "\(sortida)")
        #expect(!sortida.contains("gh release edit"), "\(sortida)")
        #expect(sortida.contains("publica una correcció"), "\(sortida)")
    }

    /// Si la publicació falla, la recepta no es toca.
    @Test func siLaPublicacioFallaNoEscriuLaRecepta() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_RELEASE_FALLA": "1"]) { $1 })
        #expect(codi == 1, "\(sortida)")
        #expect(!b.ordresGh.contains("--method PUT"))
        #expect(sortida.contains("no s'ha pogut crear la v0.28.0 a exemple/prova"), "\(sortida)")
        #expect(sortida.contains("la recepta de Homebrew no s'ha tocat"), "\(sortida)")
        #expect(sortida.contains("gh release view v0.28.0 --repo exemple/prova"), "\(sortida)")
        // Una pujada a mitges pot deixar un esborrany: dir que no s'ha publicat res podria no ser veritat.
        #expect(!sortida.contains("No s'ha publicat res."), "\(sortida)")
        #expect(!sortida.contains("Fet:"), "\(sortida)")
    }

    /// `gh` pot fallar quan GitHub ja l'ha publicada: no pot dir que no s'ha creat, ni que només hi ha un esborrany.
    @Test func siGhFallaPeroJaEsPublicadaHoDiu() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_RELEASE_FALLA": "1", "GH_FALS_ES_ESBORRANY": "false", "GH_FALS_ULTIMA": "v0.27.0"]) { $1 })
        #expect(codi == 2, "\(sortida)")
        #expect(sortida.contains("la v0.28.0 ja és publicada a exemple/prova"), "\(sortida)")
        #expect(!sortida.contains("no s'ha pogut crear"), "\(sortida)")
        #expect(sortida.contains("gh release edit v0.27.0 --latest --repo exemple/prova"), "\(sortida)")
        #expect(sortida.contains("sha256 \"\(try b.sha256(de: b.zip))\""), "\(sortida)")
        #expect(!b.ordresGh.contains("--method PUT"))
        #expect(!sortida.contains("Fet:"), "\(sortida)")
    }

    /// Si només n'ha quedat un esborrany, el missatge és el de sempre: no és públic.
    @Test func siGhFallaIQuedaUnEsborranyNoDiuQueEsPublicada() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--aplica", entorn: Banc.requisitDeProva.merging(["GH_FALS_RELEASE_FALLA": "1", "GH_FALS_ES_ESBORRANY": "true"]) { $1 })
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("no s'ha pogut crear la v0.28.0"), "\(sortida)")
        #expect(!sortida.contains("ja és publicada"), "\(sortida)")
    }

    /// Les variables de les proves canvien qui signa i què es comprova: contra el repo de debò, no valen, si n'hi ha alguna.
    @Test(arguments: ["WARP_LAUNCH_SIGN_UPDATE", "WARP_LAUNCH_VERIFICA", "WARP_LAUNCH_REQUISIT", "WARP_LAUNCH_REQUISIT_SPARKLE"],
          ["David-Erra/warp-launch", "david-erra/WARP-launch"])
    func lesVariablesDeProvaNoValenContraElRepoDeDebo(variable: String, repo: String) throws {
        let b = try Banc()
        let netes = ["WARP_LAUNCH_SIGN_UPDATE": "", "WARP_LAUNCH_VERIFICA": "", "WARP_LAUNCH_REQUISIT": "", "WARP_LAUNCH_REQUISIT_SPARKLE": ""]
        let entorn = netes.merging(["WARP_LAUNCH_REPO": repo, variable: "/usr/bin/true"]) { $1 }
        try b.comprovaRefus(conte: "només valen per a proves", entorn: entorn)
        #expect(b.ordresGh.isEmpty, "\(b.ordresGh)")
        #expect(b.ordresSign.isEmpty)
    }

    /// Sense cap d'aquestes variables, el repo de debò no es refusa per això.
    @Test func senseVariablesDeProvaElRepoDeDeboNoEsRefusaPerAixo() throws {
        let b = try Banc()
        let (_, sortida) = try b.executa(entorn: ["WARP_LAUNCH_REPO": "David-Erra/warp-launch", "WARP_LAUNCH_SIGN_UPDATE": "", "WARP_LAUNCH_VERIFICA": ""])
        #expect(!sortida.contains("només valen per a proves"), "\(sortida)")
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
        #expect(sortida.contains("Homebrew continua instal·lant la 0.27.0"), "\(sortida)")
        #expect(sortida.contains("Publicar ja no es desfà."), "\(sortida)")
        #expect(!sortida.contains("release delete"), "\(sortida)")
        #expect(!sortida.contains("Fet:"))
    }
}
