import Foundation
import Testing

// `scripts/instal·la.sh` (pas 12, i --github): sempre amb una app falsa i una carpeta de destí temporals (`WARP_LAUNCH_ORIGEN` i
// `WARP_LAUNCH_DESTI`), i amb un `pgrep` fals, perquè la prova no depengui de si l'app de debò és oberta. Mai a /Applications.

private let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/instal·la.sh")

@Suite struct ScriptInstallaTests {
    private struct Banc {
        let carpeta: URL
        var origen: URL { carpeta.appending(path: "build/Warp Launch.app") }
        var desti: URL { carpeta.appending(path: "Applications") }
        var instal·lada: URL { desti.appending(path: "Warp Launch.app") }

        init(versio: String = "0.26.0") throws {
            carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-installa-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: desti, withIntermediateDirectories: true)
            try Self.app(a: origen, versio: versio)
            try pgrep(obert: false)
        }

        /// Un `.app` mínim, signat ad hoc.
        static func app(a url: URL, versio: String, identificador: String = "cat.davide.warp-launch") throws {
            let macos = url.appending(path: "Contents/MacOS")
            try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": identificador, "CFBundleExecutable": "WarpLaunch",
                                        "CFBundleShortVersionString": versio, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: url.appending(path: "Contents/Info.plist"))
            let executable = macos.appending(path: "WarpLaunch")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            _ = try sortidaDe("/bin/bash", "codesign --force --sign - --timestamp=none '\(url.path)' 2>/dev/null")
        }

        /// Hi posa un framework com el de Sparkle, amb un executable de dins, i ho torna a signar tot de dins cap a fora.
        static func ambFramework(_ url: URL) throws {
            let fw = url.appending(path: "Contents/Frameworks/Sparkle.framework")
            let b = fw.appending(path: "Versions/B")
            try FileManager.default.createDirectory(at: b.appending(path: "Resources"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: b.appending(path: "Sparkle").path)
            try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: b.appending(path: "Autoupdate").path)
            let plist: [String: Any] = ["CFBundleIdentifier": "cat.exemple.sparkle-fals", "CFBundleExecutable": "Sparkle", "CFBundlePackageType": "FMWK"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: b.appending(path: "Resources/Info.plist"))
            try FileManager.default.createSymbolicLink(atPath: fw.appending(path: "Versions/Current").path, withDestinationPath: "B")
            try FileManager.default.createSymbolicLink(atPath: fw.appending(path: "Sparkle").path, withDestinationPath: "Versions/Current/Sparkle")
            try FileManager.default.createSymbolicLink(atPath: fw.appending(path: "Resources").path, withDestinationPath: "Versions/Current/Resources")
            for dins in [b.appending(path: "Autoupdate"), fw, url] {
                _ = try sortidaDe("/bin/bash", "codesign --force --sign - --timestamp=none '\(dins.path)' 2>/dev/null")
            }
        }

        /// `pgrep` fals: diu si «Warp Launch» és oberta.
        func pgrep(obert: Bool) throws {
            let bin = carpeta.appending(path: "bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let fitxer = bin.appending(path: "pgrep")
            try Data("#!/bin/bash\nexit \(obert ? 0 : 1)\n".utf8).write(to: fitxer)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fitxer.path)
        }

        func executa(_ arguments: String..., entorn extra: [String: String] = [:]) throws -> (codi: Int32, sortida: String) {
            try executaScript(script, arguments, entorn: [
                "WARP_LAUNCH_ORIGEN": origen.path, "WARP_LAUNCH_DESTI": desti.path, "HOME": carpeta.path,
                "TMPDIR": carpeta.path, "GH_FALS_REGISTRE": registreGh.path,
                // Amb UTF-8, el bash de macOS (3.2) llegeix «$DESTI»» com una variable que inclou «»» (cal «${DESTI}»).
                "LANG": "ca_ES.UTF-8", "LC_ALL": "ca_ES.UTF-8",
                "PATH": carpeta.appending(path: "bin").path + ":/usr/bin:/bin",
            ].merging(extra) { _, nou in nou })
        }

        // --- --github: un `gh` fals que deixa el zip de `GH_FALS_ZIP` a la carpeta de `--dir`, i apunta què li demanen.

        var registreGh: URL { carpeta.appending(path: "gh.log") }
        var ordresGh: String { (try? String(contentsOf: registreGh, encoding: .utf8)) ?? "" }

        func ghFals() throws {
            let fitxer = carpeta.appending(path: "bin/gh")
            try Data(#"""
            #!/bin/bash
            echo "$*" >> "$GH_FALS_REGISTRE"
            if [[ "$1 $2" == "release download" ]]; then
                [[ -n "${GH_FALS_ZIP:-}" ]] || exit 1
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == --dir ]]; then cp "$GH_FALS_ZIP" "$2/"; exit 0; fi
                    shift
                done
            fi
            exit 1

            """#.utf8).write(to: fitxer)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fitxer.path)
        }

        /// El zip que publicaria `publica.sh`, amb una app signada ad hoc i, si cal, marcada com a baixada d'internet.
        func zip(versio: String, quarantena: Bool = false) throws -> URL {
            let font = carpeta.appending(path: "release/Warp Launch.app")
            try Self.app(a: font, versio: versio)
            if quarantena {
                // A tots els fitxers: la de la carpeta de l'app no entra al zip, però la dels fitxers de dins sí.
                _ = try sortidaDe("/bin/bash", "xattr -rw com.apple.quarantine '0081;00000000;Prova;' '\(font.path)'")
            }
            let zip = carpeta.appending(path: "WarpLaunch-\(versio).zip")
            _ = try sortidaDe("/bin/bash", "ditto -c -k --sequesterRsrc --keepParent '\(font.path)' '\(zip.path)'")
            return zip
        }

        /// Signatura ad hoc: el requisit només hi demana l'identificador (sense el certificat d'en David).
        static let requisitDeProva = ["WARP_LAUNCH_REQUISIT": #"identifier "cat.davide.warp-launch""#]

        var versioInstal·lada: String? {
            (NSDictionary(contentsOf: instal·lada.appending(path: "Contents/Info.plist"))?["CFBundleShortVersionString"]) as? String
        }

        var noms: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: desti.path)) ?? []).sorted() }
    }

    /// Una app amb el framework ben signat s'instal·la.
    @Test func ambElFrameworkSignatSInstalla() throws {
        let b = try Banc()
        try Banc.ambFramework(b.origen)
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 0, "\(sortida)")
        #expect(b.versioInstal·lada == "0.26.0")
        #expect(FileManager.default.fileExists(atPath: b.instal·lada.appending(path: "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate").path))
    }

    /// Un executable del framework tornat a signar després del framework: `--strict` sol no ho veu, i `--deep` sí.
    @Test func ambElFrameworkAMigSignarNoSInstalla() throws {
        let b = try Banc()
        try Banc.ambFramework(b.origen)
        let autoupdate = b.origen.appending(path: "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate")
        _ = try sortidaDe("/bin/bash", "codesign --force --sign - --identifier altre --timestamp=none '\(autoupdate.path)' 2>/dev/null")
        // Aquí hi ha la gràcia de la prova.
        _ = try sortidaDe("/bin/bash", "codesign --verify --strict '\(b.origen.path)'")
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi != 0, "\(sortida)")
        #expect(sortida.contains("no és vàlida"), "\(sortida)")
        #expect(b.noms.isEmpty)
    }

    /// Un framework sense signar tampoc no s'instal·la.
    @Test func ambElFrameworkSenseSignarNoSInstalla() throws {
        let b = try Banc()
        try Banc.ambFramework(b.origen)
        let fw = b.origen.appending(path: "Contents/Frameworks/Sparkle.framework")
        _ = try sortidaDe("/bin/bash", "codesign --remove-signature '\(fw.path)'")
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi != 0, "\(sortida)")
        #expect(b.noms.isEmpty)
    }

    /// Per defecte, mode de prova: no copia res (regla 4).
    @Test func perDefecteNoCopiaRes() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa()
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("Mode de prova: no s'ha copiat res."))
        #expect(sortida.contains("copiaria Warp Launch 0.26.0"))
        #expect(b.noms.isEmpty)
    }

    /// Amb `--aplica`, la copia; la segona vegada, substitueix la d'abans, sense deixar còpies provisionals.
    @Test func laCopiaILaSubstitueix() throws {
        let b = try Banc(versio: "0.26.0")
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 0, "\(sortida)")
        #expect(b.versioInstal·lada == "0.26.0")
        #expect(sortida.contains("Per desinstal·lar-la:"))
        #expect(sortida.contains("No s'ha obert ni registrat res."))

        try FileManager.default.removeItem(at: b.origen)
        try Banc.app(a: b.origen, versio: "0.27.0")
        let (codi2, sortida2) = try b.executa("--aplica")
        #expect(codi2 == 0, "\(sortida2)")
        #expect(sortida2.contains("s'ha substituït Warp Launch 0.26.0 per la 0.27.0"))
        #expect(b.versioInstal·lada == "0.27.0")
        #expect(b.noms == ["Warp Launch.app"])
    }

    /// Amb l'app oberta, no copia res i no la tanca.
    @Test func ambLAppObertaNoFaRes() throws {
        let b = try Banc()
        try b.pgrep(obert: true)
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("Warp Launch és oberta"))
        #expect(b.noms.isEmpty)
    }

    /// Una «Warp Launch.app» que no és d'aquesta app (un altre identificador) no es toca.
    @Test func noTocaUnaAltraApp() throws {
        let b = try Banc()
        try Banc.app(a: b.instal·lada, versio: "9.9", identificador: "com.exemple.altra")
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("hi ha una altra cosa que no és Warp Launch"))
        #expect(b.versioInstal·lada == "9.9")
    }

    /// Sense l'app empaquetada, no fa res.
    @Test func senseAppNoFaRes() throws {
        let b = try Banc()
        try FileManager.default.removeItem(at: b.origen)
        let (codi, sortida) = try b.executa("--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("primer scripts/build-app.sh"))
        #expect(b.noms.isEmpty)
    }

    // MARK: --github (la instal·lació en un altre Mac, sense compilar)

    /// Per defecte, també amb --github, mode de prova: la baixa a una carpeta temporal i no copia res.
    @Test func githubPerDefecteNoCopiaRes() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.28.0")
        let (codi, sortida) = try b.executa("--github", entorn: Banc.requisitDeProva.merging(["GH_FALS_ZIP": zip.path]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("Mode de prova: no s'ha copiat res."))
        #expect(sortida.contains("copiaria Warp Launch 0.28.0 (de GitHub (David-Erra/warp-launch))"))
        #expect(b.ordresGh.contains("release download --repo David-Erra/warp-launch --pattern WarpLaunch-*.zip --dir "))
        #expect(b.noms.isEmpty)
        // La carpeta temporal no queda.
        let restes = try FileManager.default.contentsOfDirectory(atPath: b.carpeta.path).filter { $0.hasPrefix("warp-launch-installa.") }
        #expect(restes.isEmpty)
    }

    /// Amb --aplica, la instal·la, i li treu la marca de baixada d'internet (si no, macOS no l'obriria).
    @Test func githubLaInstal·la() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.28.0", quarantena: true)
        let (codi, sortida) = try b.executa("--github", "--aplica",
                                            entorn: Banc.requisitDeProva.merging(["GH_FALS_ZIP": zip.path]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(b.versioInstal·lada == "0.28.0")
        #expect(sortida.contains("No s'ha obert ni registrat res."))
        let marques = try executaPrograma("/usr/bin/xattr", ["-r", b.instal·lada.path], entorn: [:])
        #expect(!marques.sortida.contains("com.apple.quarantine"), "\(marques.sortida)")
    }

    /// La prova d'aquí dalt només val si la marca arriba a l'app baixada: es comprova que el zip la porta.
    @Test func elZipDeProvaPortaLaMarca() throws {
        let b = try Banc()
        let zip = try b.zip(versio: "0.28.0", quarantena: true)
        let fora = b.carpeta.appending(path: "fora")
        _ = try sortidaDe("/bin/bash", "ditto -x -k '\(zip.path)' '\(fora.path)'")
        let marca = try executaPrograma("/usr/bin/xattr", ["-p", "com.apple.quarantine",
                                                           fora.appending(path: "Warp Launch.app/Contents/MacOS/WarpLaunch").path], entorn: [:])
        #expect(marca.codi == 0, "\(marca.sortida)")
    }

    /// «v0.27.3», com surt a GitHub, també val.
    @Test func githubVersioAmbV() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.27.3")
        let (codi, sortida) = try b.executa("--github", "--versio", "v0.27.3",
                                            entorn: Banc.requisitDeProva.merging(["GH_FALS_ZIP": zip.path]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresGh.contains("release download v0.27.3 --repo"))
    }

    /// Una versió que no hi és: diu com veure les publicades, no només la sessió de gh.
    @Test func githubVersioQueNoHiEs() throws {
        let b = try Banc()
        try b.ghFals()
        let (codi, sortida) = try b.executa("--github", "--versio", "0.1.0")
        #expect(codi == 1)
        #expect(sortida.contains("Potser la 0.1.0 no està publicada"))
        #expect(sortida.contains("gh release list --repo David-Erra/warp-launch"))
    }

    /// Sense permís per escriure a la carpeta (un compte que no és administrador), ho diu abans de baixar res, també en mode de prova.
    @Test func senseDretsDEscripturaHoDiu() throws {
        let b = try Banc()
        try b.ghFals()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: b.desti.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: b.desti.path) }
        for arguments in [["--github"], ["--github", "--aplica"], ["--aplica"]] {
            let (codi, sortida) = try executaScript(script, arguments, entorn: [
                "WARP_LAUNCH_ORIGEN": b.origen.path, "WARP_LAUNCH_DESTI": b.desti.path, "HOME": b.carpeta.path,
                "TMPDIR": b.carpeta.path, "GH_FALS_REGISTRE": b.registreGh.path, "LANG": "ca_ES.UTF-8", "LC_ALL": "ca_ES.UTF-8",
                "PATH": b.carpeta.appending(path: "bin").path + ":/usr/bin:/bin",
            ])
            #expect(codi == 1, "\(arguments): \(sortida)")
            #expect(sortida.contains("cal entrar amb un compte d'administrador del Mac (no amb sudo)"), "\(arguments)")
        }
        #expect(!b.ordresGh.contains("release download"))
    }

    /// Si la d'abans no es pot esborrar després del canvi, la nova queda instal·lada i només s'avisa.
    @Test func siLaDAbansNoEsPotEsborrarNomesAvisa() throws {
        let b = try Banc(versio: "0.27.0")
        try Banc.app(a: b.instal·lada, versio: "0.26.0")
        let macos = b.instal·lada.appending(path: "Contents/MacOS")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: macos.path)
        let (codi, sortida) = try b.executa("--aplica")
        // Es torna a deixar esborrar, per netejar.
        for nom in b.noms where nom.contains(".vella-") {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: b.desti.appending(path: nom + "/Contents/MacOS").path)
        }
        #expect(codi == 0, "\(sortida)")
        #expect(sortida.contains("s'ha substituït Warp Launch 0.26.0 per la 0.27.0"))
        #expect(sortida.contains("Avís: la versió d'abans ha quedat a"))
        #expect(b.versioInstal·lada == "0.27.0")
    }

    /// Un requisit que no es pot llegir no es confon amb una app d'algú altre: es diu l'error de codesign.
    @Test func unRequisitTrencatEsDiuTalQual() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.28.0")
        let (codi, sortida) = try b.executa("--github", entorn: ["GH_FALS_ZIP": zip.path, "WARP_LAUNCH_REQUISIT": "identifier"])
        #expect(codi == 1)
        #expect(sortida.contains("no s'ha pogut comprovar la signatura"))
        #expect(!sortida.contains("no està signada amb el certificat"))
    }

    /// El requisit de la signatura és el mateix a publica.sh i a instal·la.sh, i és vàlid (`csreq`).
    @Test func elRequisitEsElMateixIEsValid() throws {
        let publica = script.deletingLastPathComponent().appending(path: "publica.sh")
        let linies = try [script, publica].map { url in
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("REQUISIT=") }
        }
        #expect(linies[0].count == 1 && linies[0] == linies[1], "\(linies)")
        let requisit = try sortidaDe("/bin/bash", "IDENTIFICADOR=cat.davide.warp-launch; unset WARP_LAUNCH_REQUISIT; "
                                     + linies[0][0] + "; printf '%s\\0' \"$REQUISIT\"")
        #expect(requisit.first?.contains(#"identifier "cat.davide.warp-launch" and certificate leaf = H""#) == true, "\(requisit)")
        let binari = FileManager.default.temporaryDirectory.appending(path: "warp-launch-requisit-\(UUID().uuidString)")
        let csreq = try executaPrograma("/usr/bin/csreq", ["-r=" + (requisit.first ?? ""), "-b", binari.path], entorn: [:])
        #expect(csreq.codi == 0, "\(csreq.sortida)")
    }

    /// --versio en demana una de concreta; sense, l'última.
    @Test func githubUnaVersioConcreta() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.27.3")
        let (codi, sortida) = try b.executa("--github", "--versio", "0.27.3",
                                            entorn: Banc.requisitDeProva.merging(["GH_FALS_ZIP": zip.path]) { $1 })
        #expect(codi == 0, "\(sortida)")
        #expect(b.ordresGh.contains("release download v0.27.3 --repo David-Erra/warp-launch"))
    }

    /// Sense el certificat d'en David, no s'instal·la: la de la prova és ad hoc.
    @Test func githubNomesAmbElCertificatDenDavid() throws {
        let b = try Banc()
        try b.ghFals()
        let zip = try b.zip(versio: "0.28.0")
        let (codi, sortida) = try b.executa("--github", "--aplica", entorn: ["GH_FALS_ZIP": zip.path])
        #expect(codi == 1)
        #expect(sortida.contains("no està signada amb el certificat d'en David"))
        #expect(b.noms.isEmpty)
    }

    /// Sense `gh`, diu com tenir-lo.
    @Test func githubSenseGh() throws {
        let b = try Banc()
        let (codi, sortida) = try b.executa("--github", "--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("cal l'eina de GitHub"))
        #expect(sortida.contains("gh auth login"))
        #expect(b.noms.isEmpty)
    }

    /// Si no es pot baixar (sense sessió o sense accés al repo), ho diu i no copia res.
    @Test func githubSiNoEsPotBaixar() throws {
        let b = try Banc()
        try b.ghFals()
        let (codi, sortida) = try b.executa("--github", "--aplica")
        #expect(codi == 1)
        #expect(sortida.contains("no s'ha pogut baixar"))
        #expect(sortida.contains("gh auth status"))
        #expect(sortida.contains("has d'haver entrat a `gh` amb un compte de GitHub"))
        #expect(b.noms.isEmpty)
    }

    /// --versio només té sentit amb --github.
    @Test func versioSenseGithub() throws {
        let b = try Banc()
        let (codi, _) = try b.executa("--versio", "0.27.3")
        #expect(codi == 64)
    }
}
