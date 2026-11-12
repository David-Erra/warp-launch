import Foundation
import Testing

// `scripts/build-app.sh`, sense compilar ni signar res: en un repo temporal, amb un `swift` fals que deixa els productes on els deixa
// SwiftPM, un `security` fals que diu quines identitats hi ha al clauer (no el llegeix), un `codesign` fals que apunta què se li demana,
// i un `otool` fals. Les proves miren amb quina identitat es signa cada peça, i com (docs/disseny.md, secció 13).

private let arrel = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let hashDeveloperID = "0123456789ABCDEF0123456789ABCDEF01234567"
private let nomDeveloperID = "Developer ID Application: David Prova (ABCDE12345)"
private let liniaDeveloperID = #"  1) \#(hashDeveloperID) "\#(nomDeveloperID)""#
private let liniaDev = #"  1) C1EC55B1CB87C881A2C48A4F5256B10EBC12BCC6 "Warp Launch Dev" (CSSMERR_TP_NOT_TRUSTED)"#
private let capDeValida = "     0 valid identities found"

/// Com respon `security find-identity -p codesigning`: totes les identitats, també les que macOS no dona per vàlides.
private func totes(_ linies: String...) -> String {
    (["Policy: Code Signing", "  Matching identities"] + linies + ["     \(linies.count) identities found", "", "  Valid identities only", capDeValida]).joined(separator: "\n")
}

/// Com respon `security find-identity -v -p codesigning`: només les vàlides.
private func valides(_ linies: String...) -> String {
    linies.isEmpty ? capDeValida : (linies + ["     \(linies.count) valid identities found"]).joined(separator: "\n")
}

@Suite struct ScriptBuildAppTests {
    private struct Banc {
        let carpeta: URL
        var repo: URL { carpeta.appending(path: "repo") }
        var app: URL { repo.appending(path: "build/Warp Launch.app") }
        var registreCodesign: URL { carpeta.appending(path: "codesign.log") }
        var registreSecurity: URL { carpeta.appending(path: "security.log") }
        var registreSwift: URL { carpeta.appending(path: "swift.log") }
        func linies(_ url: URL) -> [String] { ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        var ordresCodesign: [String] { linies(registreCodesign) }
        /// Les signatures, en ordre: una per peça.
        var signatures: [String] { ordresCodesign.filter { $0.hasPrefix("--force ") } }
        var ordresSecurity: [String] { linies(registreSecurity) }
        var compilat: Bool { !linies(registreSwift).isEmpty }

        init() throws {
            carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-build-app-\(UUID().uuidString)")
            let fm = FileManager.default
            for carpetaNova in ["scripts", "Sources/WarpLaunchCore", "Recursos", ".build/artifacts/sparkle/Sparkle"] {
                try fm.createDirectory(at: repo.appending(path: carpetaNova), withIntermediateDirectories: true)
            }
            try fm.copyItem(at: arrel.appending(path: "scripts/build-app.sh"), to: repo.appending(path: "scripts/build-app.sh"))
            try Data("1.2.3\n".utf8).write(to: repo.appending(path: "VERSION"))
            try Data("public enum WarpLaunch {\n    public static let versio = \"1.2.3\"\n}\n".utf8).write(to: repo.appending(path: "Sources/WarpLaunchCore/Versio.swift"))
            for fitxer in ["Recursos/Info.plist", "Recursos/Actualitzacions.plist", "Recursos/en.lproj"] {
                try fm.copyItem(at: arrel.appending(path: fitxer), to: repo.appending(path: fitxer))
            }
            try Data("MIT\n".utf8).write(to: repo.appending(path: "LICENSE"))
            try Data("MIT (Sparkle)\n".utf8).write(to: repo.appending(path: ".build/artifacts/sparkle/Sparkle/LICENSE"))
            // Els productes de `swift build`, on els deixa SwiftPM: l'executable, el framework (amb els serveis XPC, que el paquet treu)
            // i el bundle dels textos.
            try Self.executable(carpeta.appending(path: "bin/swift"), #"""
            #!/bin/bash
            BIN="$SWIFT_FALS_BIN"
            if [[ " $* " == *" --show-bin-path "* ]]; then echo "$BIN"; exit 0; fi
            echo "$*" >> "$SWIFT_FALS_REGISTRE"
            FW="$BIN/Sparkle.framework/Versions/B"
            TEXTOS="$BIN/WarpLaunch_WarpLaunchCore.bundle/Contents"
            mkdir -p "$FW/Updater.app/Contents/MacOS" "$FW/XPCServices/Installer.xpc" "$TEXTOS/Resources/ca.lproj"
            cp /usr/bin/true "$BIN/WarpLaunch"
            cp /usr/bin/true "$FW/Autoupdate"
            cp /usr/bin/true "$FW/Updater.app/Contents/MacOS/Updater"
            printf '"x" = "y";\n' > "$TEXTOS/Resources/ca.lproj/Localizable.strings"
            printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>repo.WarpLaunchCore.resources</string></dict></plist>' > "$TEXTOS/Info.plist"

            """#)
            try Self.executable(carpeta.appending(path: "bin/security"), #"""
            #!/bin/bash
            echo "$*" >> "$SECURITY_FALS_REGISTRE"
            case "$*" in
                "find-identity -v -p codesigning") printf '%s\n' "$SECURITY_FALS_VALIDES" ;;
                "find-identity -p codesigning") printf '%s\n' "$SECURITY_FALS_TOTES" ;;
                *) exit 1 ;;
            esac

            """#)
            try Self.executable(carpeta.appending(path: "bin/codesign"), #"""
            #!/bin/bash
            echo "$*" >> "$CODESIGN_FALS_REGISTRE"
            case "${1:-}" in
                --force|--verify) exit 0 ;;
                -d) echo 'designated => identifier "cat.davide.warp-launch" and requisit de prova' >&2; exit 0 ;;
            esac
            exit 1

            """#)
            try Self.executable(carpeta.appending(path: "bin/otool"), #"""
            #!/bin/bash
            echo "          path @executable_path/../Frameworks (offset 12)"

            """#)
        }

        static func executable(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        func executa(_ arguments: String..., totes: String, valides: String, entorn extra: [String: String] = [:]) throws -> (codi: Int32, sortida: String) {
            try executa(arguments: arguments, totes: totes, valides: valides, entorn: extra)
        }

        func executa(arguments: [String], totes: String, valides: String, entorn extra: [String: String] = [:]) throws -> (codi: Int32, sortida: String) {
            try executaScript(repo.appending(path: "scripts/build-app.sh"), arguments, entorn: [
                "HOME": carpeta.path, "TMPDIR": carpeta.path, "LANG": "ca_ES.UTF-8", "LC_ALL": "ca_ES.UTF-8",
                "PATH": carpeta.appending(path: "bin").path + ":/usr/bin:/bin",
                "SWIFT_FALS_BIN": carpeta.appending(path: "swiftbin").path, "SWIFT_FALS_REGISTRE": registreSwift.path,
                "SECURITY_FALS_TOTES": totes, "SECURITY_FALS_VALIDES": valides, "SECURITY_FALS_REGISTRE": registreSecurity.path,
                "CODESIGN_FALS_REGISTRE": registreCodesign.path,
            ].merging(extra) { $1 })
        }

        /// Les peces, de dins cap a fora, com les signa l'script.
        static let peces = ["build/Warp Launch.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
                            "build/Warp Launch.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app",
                            "build/Warp Launch.app/Contents/Frameworks/Sparkle.framework",
                            "build/Warp Launch.app/Contents/Resources/WarpLaunch_WarpLaunchCore.bundle",
                            "build/Warp Launch.app"]
    }

    /// Amb un Developer ID vàlid al clauer, mana sobre «Warp Launch Dev»: totes les peces, de dins cap a fora, amb el seu SHA-1, el
    /// «hardened runtime» i el segell de temps, i sense entitlements. I ho diu.
    @Test(arguments: [[], ["--amb-feed"]])
    func ambDeveloperIDSignaAmbRuntimeISegell(opcions: [String]) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa(arguments: ["release"] + opcions, totes: totes(liniaDeveloperID, liniaDev), valides: valides(liniaDeveloperID))
        #expect(codi == 0, "\(sortida)")
        #expect(b.signatures == Banc.peces.map { "--force --sign \(hashDeveloperID) --options runtime --timestamp \($0)" }, "\(b.signatures)")
        #expect(!b.ordresCodesign.contains { $0.contains("--entitlements") || $0.contains("--timestamp=none") }, "\(b.ordresCodesign)")
        #expect(b.ordresCodesign.last(where: { $0.hasPrefix("--verify") }) == "--verify --deep --strict build/Warp Launch.app", "\(b.ordresCodesign)")
        #expect(sortida.contains("signada amb: «\(nomDeveloperID)» (Developer ID, amb «hardened runtime» i segell de temps)"), "\(sortida)")
        // Amb Developer ID, «Warp Launch Dev» ni es busca.
        #expect(b.ordresSecurity == ["find-identity -v -p codesigning"], "\(b.ordresSecurity)")
        // Els serveis XPC no hi són: no s'han de signar.
        #expect(!FileManager.default.fileExists(atPath: b.app.appending(path: "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices").path))
        let feed = NSDictionary(contentsOf: b.app.appending(path: "Contents/Info.plist"))?["SUFeedURL"] as? String
        #expect((feed != nil) == opcions.contains("--amb-feed"), "\(String(describing: feed))")
    }

    /// Sense Developer ID, com fins ara: «Warp Launch Dev», sense «hardened runtime» ni segell de temps. També si n'hi ha un de caducat o
    /// revocat (surt entre totes, no entre les vàlides): Apple no el notaritzaria.
    @Test(arguments: [
        totes(liniaDev),
        totes(#"  1) \#(hashDeveloperID) "\#(nomDeveloperID)" (CSSMERR_TP_CERT_EXPIRED)"#, liniaDev),
    ])
    func senseDeveloperIDComFinsAra(totes: String) throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("release", totes: totes, valides: valides())
        #expect(codi == 0, "\(sortida)")
        #expect(b.signatures == Banc.peces.map { "--force --sign Warp Launch Dev --timestamp=none \($0)" }, "\(b.signatures)")
        #expect(!b.ordresCodesign.contains { $0.contains("--options") || $0.contains("--entitlements") }, "\(b.ordresCodesign)")
        #expect(sortida.contains("signada amb: «Warp Launch Dev»\n"), "\(sortida)")
        #expect(b.ordresSecurity == ["find-identity -v -p codesigning", "find-identity -p codesigning"], "\(b.ordresSecurity)")
    }

    /// Sense cap dels dos, ad hoc, com fins ara; i amb --amb-feed, s'atura abans de compilar.
    @Test func senseCapCertificat() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("debug", totes: totes(), valides: valides())
        #expect(codi == 0, "\(sortida)")
        #expect(b.signatures == Banc.peces.map { "--force --sign - --timestamp=none \($0)" }, "\(b.signatures)")
        #expect(sortida.contains("no hi ha el certificat «Warp Launch Dev» al clauer: signatura ad hoc."), "\(sortida)")
        #expect(sortida.contains("signada amb: ad hoc\n"), "\(sortida)")

        let c = try Banc()
        let (codiFeed, sortidaFeed) = try c.executa("release", "--amb-feed", totes: totes(), valides: valides())
        #expect(codiFeed == 1, "\(sortidaFeed)")
        #expect(sortidaFeed.contains("--amb-feed necessita un certificat «Developer ID Application» vàlid o «Warp Launch Dev», i no n'hi ha cap al clauer."), "\(sortidaFeed)")
        #expect(!c.compilat && c.ordresCodesign.isEmpty)
    }

    /// El mateix certificat de dos clauers compta com un de sol.
    @Test func elMateixDeveloperIDDeDosClauersEsUnDeSol() throws {
        let b = try Banc()
        let segona = liniaDeveloperID.replacing("  1) ", with: "  2) ")
        let (codi, sortida) = try b.executa("release", totes: totes(liniaDeveloperID, segona), valides: valides(liniaDeveloperID, segona))
        #expect(codi == 0, "\(sortida)")
        #expect(b.signatures.count == 5 && b.signatures.allSatisfy { $0.hasPrefix("--force --sign \(hashDeveloperID) --options runtime --timestamp ") }, "\(b.signatures)")
    }

    /// Dos Developer ID diferents: no endevina amb quin signar. S'atura abans de compilar, i diu com triar.
    @Test func dosDeveloperIDsNoSignaRes() throws {
        let b = try Banc()
        let altre = #"  2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: David Prova (ABCDE12345)""#
        let (codi, sortida) = try b.executa("release", "--amb-feed", totes: totes(liniaDeveloperID, altre), valides: valides(liniaDeveloperID, altre))
        #expect(codi == 1, "\(sortida)")
        #expect(sortida.contains("més d'un certificat «Developer ID Application» vàlid"), "\(sortida)")
        #expect(sortida.contains(hashDeveloperID) && sortida.contains("FEDCBA9876543210FEDCBA9876543210FEDCBA98"), "\(sortida)")
        #expect(!b.compilat && b.ordresCodesign.isEmpty)
    }

    /// WARP_LAUNCH_IDENTITAT força la identitat pel nom, sense buscar el Developer ID (per a una còpia de proves). No val amb --amb-feed.
    @Test func laIdentitatForcadaNoBuscaElDeveloperID() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("release", totes: totes(liniaDeveloperID, liniaDev), valides: valides(liniaDeveloperID),
                                            entorn: ["WARP_LAUNCH_IDENTITAT": "Warp Launch Dev"])
        #expect(codi == 0, "\(sortida)")
        #expect(b.signatures == Banc.peces.map { "--force --sign Warp Launch Dev --timestamp=none \($0)" }, "\(b.signatures)")
        #expect(b.ordresSecurity == ["find-identity -p codesigning"], "\(b.ordresSecurity)")
    }
}
