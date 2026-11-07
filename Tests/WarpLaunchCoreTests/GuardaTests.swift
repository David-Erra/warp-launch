import Foundation
import Testing
import WarpLaunchCore

// Prova de guarda (docs/disseny.md, «Prova de guarda»). Llegeix el codi del repo i falla si:
// - el codi pot obrir Warp, Claude o qualsevol altra cosa, o registrar una arrencada automàtica;
// - una prova pot llegir l'estat real (Warp, Claude, ~/.config/warp-launch) o fer sortir el procés al Dock.
// Aquest fitxer no es revisa a si mateix: hi surten totes les paraules prohibides.

private let arrel = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Fitxers `.swift` d'una carpeta del repo, amb ruta relativa i contingut.
private func fitxers(_ carpeta: String) throws -> [(ruta: String, text: String)] {
    let base = arrel.appending(path: carpeta)
    guard let enumerador = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
    return try enumerador.compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "GuardaTests.swift" }
        .map { (String($0.path.dropFirst(arrel.path.count + 1)), try String(contentsOf: $0, encoding: .utf8)) }
}

/// Línies (ruta:línia) on surt alguna expressió. Cada expressió és una expressió regular.
private func aparicions(de expressions: [String], a fitxers: [(ruta: String, text: String)]) throws -> [String] {
    let regs = try expressions.map { try Regex($0) }
    var trobades: [String] = []
    for fitxer in fitxers {
        for (numero, linia) in fitxer.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for (expressio, reg) in zip(expressions, regs) where linia.contains(reg) {
                trobades.append("\(fitxer.ruta):\(numero + 1): «\(expressio)»")
            }
        }
    }
    return trobades
}

/// El codi no obre res ni tanca res (regles 1 a 4 de CLAUDE.md). De `NSWorkspace`, només «Mostra al Finder»
/// (`activateFileViewerSelecting`, a `Finder.swift`), que selecciona el fitxer en una finestra del Finder, i l'obridor
/// de la fase 3.1 (`ObreWarp`, vegeu `nomesLObridorObreWarp`). De les URL de Warp, només la de llançament (D5), i en un
/// sol lloc (`nomesHiHaLURLDeLlancament`).
private let prohibidesCodi = [
    #"warp://(?!launch/")"#, #"\bProcess\("#,
    #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\))"#, #"openURL"#,
    #"NSAppleScript"#, #"posix_spawn"#, #"(^|[^.\w])system\("#, #"SMAppService"#, #"LaunchAgents"#, #"UserDefaults"#,
    #"@AppStorage"#,
    // Tancar o matar Warp o Claude (regla 2), o obrir apps. La paraula `openApplication` només pot ser a l'obridor, per
    // obrir Warp si és tancat (`nomesLObridorObreWarp`).
    #"NSRunningApplication"#, #"forceTerminate"#, #"launchApplication"#, #"\bkill(pg)?\("#,
]

private let serveiArrencada = "Sources/WarpLaunchApp/ServeiArrencada.swift"

/// El que s'arrossega no surt de l'app: ni fitxers, ni text, ni `ShareLink`.
private let prohibidesArrossegar = [
    #"ShareLink"#, #"ProxyRepresentation"#, #"FileRepresentation"#, #"CodableRepresentation"#, #"\.onDrag\b"#,
    #"NSFilePromiseProvider"#, #"suggestedFileName"#, #"registerObject"#, #"\.register\("#,
]

@Suite struct GuardaTests {
    @Test func elCodiNoObreResNiRegistraArrencades() throws {
        let codi = try fitxers("Sources")
        #expect(codi.count > 10, "no s'ha trobat el codi a \(arrel.path)")
        // `SMAppService`, només als ítems d'inici (D3, `nomesLInterruptorRegistraLArrencada`).
        let trobades = try aparicions(de: prohibidesCodi, a: codi.filter { $0.ruta != serveiArrencada })
            + aparicions(de: prohibidesCodi.filter { $0 != #"SMAppService"# }, a: codi.filter { $0.ruta == serveiArrencada })
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")

        // D19 i D-P4 (0.29.0): el refresc de l'ajust de Warp només el crea `ConsentimentRestauracio`, un sol cop i només amb
        // el consentiment acceptat; l'app no en guarda cap altre, ni tampoc per sortir.
        let rutaConsentiment = "Sources/WarpLaunchUI/ConsentimentRestauracio.swift"
        let refrescos = try aparicions(de: [#"\bRefrescWarp\("#], a: codi)
        #expect(refrescos.count == 1 && refrescos[0].hasPrefix("\(rutaConsentiment):"), "\(refrescos)")
        let consentiment = try #require(codi.first { $0.ruta == rutaConsentiment }).text
        #expect(consentiment.contains("    private func creaRefresc() {\n"
            + "        guard estat == .acceptat, refresc == nil, let creaEntornRefresc else { return }\n"
            + "        refresc = RefrescWarp(entorn: creaEntornRefresc())\n    }"))
        #expect(consentiment.components(separatedBy: "refresc = ").count == 2, "només aquella assignació")
        // L'entorn de l'ajust només es demana allà, a tot el codi.
        let crides = try aparicions(de: [#"creaEntornRefresc\(\)"#], a: codi)
        #expect(crides.count == 1 && crides[0].hasPrefix("\(rutaConsentiment):"), "\(crides)")
        // Acceptat: o ho diu `preferencies.json` en carregar, o «Accepta» ho acaba de desar.
        #expect(consentiment.contains("estat = try magatzem.carrega().restauracio.esAcceptat ? .acceptat : .pendent"))
        #expect(consentiment.components(separatedBy: "estat = .acceptat").count == 2)
        let desa = try #require(consentiment.range(of: "try magatzem.accepta(ara: rellotge())"))
        let accepta = try #require(consentiment.range(of: "estat = .acceptat"))
        #expect(desa.upperBound < accepta.lowerBound)
        // A l'app: l'únic consentiment i l'únic entorn de l'ajust, i el refresc només és el del consentiment.
        let app = try #require(codi.first { $0.ruta == "Sources/WarpLaunchApp/WarpLaunchApp.swift" }).text
        for unic in [#"\bConsentimentRestauracio\("#, #"RefrescWarp\.Entorn\("#, #"^\s*creaEntornRefresc = "#] {
            let llocs = try aparicions(de: [unic], a: codi)
            #expect(llocs.count == 1 && llocs[0].hasPrefix("Sources/WarpLaunchApp/WarpLaunchApp.swift:"), "\(llocs)")
        }
        #expect(app.contains("ConsentimentRestauracio(magatzem: preferencies, creaEntornRefresc: creaEntornRefresc)"))
        #expect(app.contains("var refresc: RefrescWarp? { consentiment.refresc }"))
        // Revisió de la 0.29.0: `creaEntornRefresc\(\)` no veia `creaEntornRefresc?()` ni un àlies. Cada línia de codi
        // que l'esmenta, a tot `Sources`, és una d'aquestes.
        let esmenta = codi.flatMap { fitxer in
            fitxer.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("creaEntornRefresc") && !$0.hasPrefix("//") }
                .map { "\(fitxer.ruta): \($0)" }
        }
        let rutaApp = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        #expect(esmenta.sorted() == [
            "\(rutaApp): var creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?",
            "\(rutaApp): creaEntornRefresc = {",
            "\(rutaApp): let consentiment = ConsentimentRestauracio(magatzem: preferencies, creaEntornRefresc: creaEntornRefresc)",
            "\(rutaApp): let base: BaseWarp = creaEntornRefresc == nil ? .segonsAjust : .mai",
            "\(rutaConsentiment): @ObservationIgnored private let creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?",
            "\(rutaConsentiment): public init(magatzem: MagatzemPreferencies?, creaEntornRefresc: (@MainActor () -> RefrescWarp.Entorn)?,",
            "\(rutaConsentiment): self.creaEntornRefresc = creaEntornRefresc",
            "\(rutaConsentiment): guard estat == .acceptat, refresc == nil, let creaEntornRefresc else { return }",
            "\(rutaConsentiment): refresc = RefrescWarp(entorn: creaEntornRefresc())",
        ].sorted(), "\(esmenta.joined(separator: "\n"))")
        // L'estat del consentiment només canvia en aquestes quatre línies (també amb `self.estat =`).
        let assignacio = try Regex(#"\bestat\s*=(?!=)"#)
        let assignacions = consentiment.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && $0.contains(assignacio) }
        #expect(assignacions == [
            "estat = .noCal",
            "estat = try magatzem.carrega().restauracio.esAcceptat ? .acceptat : .pendent",
            "estat = .error(error.description)",
            "estat = .acceptat",
        ], "\(assignacions)")
        // El consentiment només el dona l'usuari, amb el botó «Accepta»: cap altre codi no l'accepta ni el desa per ell.
        let accepten = try aparicions(de: [#"\.accepta\("#], a: codi)
        #expect(accepten.count == 2 && accepten.contains { $0.hasPrefix("\(rutaConsentiment):") }
            && accepten.contains { $0.hasPrefix("Sources/WarpLaunchUI/VistaConsentiment.swift:") }, "\(accepten)")
        let vista = try #require(codi.first { $0.ruta == "Sources/WarpLaunchUI/VistaConsentiment.swift" }).text
        #expect(vista.contains(#"Button("Accepta") { consentiment.accepta() }"#))
        let preferencies = "Sources/WarpLaunchCore/Preferencies.swift"
        let consentiments = try aparicions(de: [#"\.acceptat\("#, #"\.migrat\b"#, #"\.restauracio\s*=(?!=)"#], a: codi)
        #expect(!consentiments.isEmpty && consentiments.allSatisfy { $0.hasPrefix("\(preferencies):") }, "\(consentiments)")
    }

    /// La foto de Warp (D19) només es refresca quan en David ho demana, mai sola (0.27.3, 06/11/2026): l'únic que crida
    /// `refresca()` és la lectura amb finestres, que fan «Torna a llegir Warp», importar i lligar.
    @Test func laFotoNomesEsFaQuanEsDemana() throws {
        let codi = try fitxers("Sources").filter { $0.ruta != "Sources/WarpLaunchUI/RefrescWarp.swift" }
        let crides = try aparicions(de: [#"\.refresca\("#], a: codi)
        #expect(crides.count == 1 && crides[0].hasPrefix("Sources/WarpLaunchUI/EstatWarp.swift"), "\(crides)")
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        #expect(!app.contains("refrescaPeriodicament"))
    }

    /// D3 i regla 3: l'app només s'afegeix als ítems d'inici amb l'interruptor de la Configuració. Només l'app principal
    /// (cap agent ni dimoni), només amb la configuració de debò, i res més no hi registra.
    @Test func nomesLInterruptorRegistraLArrencada() throws {
        let codi = try fitxers("Sources")
        let servei = try #require(codi.first { $0.ruta == serveiArrencada }).text
        #expect(servei.contains("SMAppService.mainApp.register()"))
        for prohibit in ["SMAppService.agent", "SMAppService.daemon", "SMAppService.loginItem", "SMLoginItemSetEnabled"] {
            #expect(!servei.contains(prohibit), "\(prohibit)")
        }
        #expect(try aparicions(de: [#"\.register\(\)"#], a: codi) == ["\(serveiArrencada):18: «\\.register\\(\\)»"])
        let usos = try aparicions(de: [#"ServeiArrencada\.entorn"#], a: codi)
        #expect(usos.count == 1 && usos[0].hasPrefix("Sources/WarpLaunchApp/WarpLaunchApp.swift"), "\(usos)")
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        #expect(app.contains("if case .real = arguments.carpeta {\n            arrencada = ArrencadaSessio(entorn: ServeiArrencada.entorn"))
        // L'únic lloc que activa: `posa`, l'acció de l'interruptor.
        let model = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/ArrencadaSessio.swift"), encoding: .utf8)
        #expect(model.components(separatedBy: "entorn.activa()").count == 2)
        // `posa` només es crida des de l'interruptor, a tot el codi (també a l'app), i el model no se la crida a si mateix.
        let altres = codi.filter { $0.ruta != "Sources/WarpLaunchUI/ArrencadaSessio.swift" }
        let posa = try aparicions(de: [#"arrencada\.posa\("#], a: altres)
        #expect(posa.count == 1 && posa[0].hasPrefix("Sources/WarpLaunchUI/VistaConfiguracio.swift"), "\(posa)")
        #expect(model.components(separatedBy: "posa(").count == 2)
        // Dins del servei, `entorn` només es defineix, i `register` només és a la seva línia; enlloc més no hi és.
        #expect(servei.components(separatedBy: "entorn").count == 2)
        #expect(try aparicions(de: [#"\bregister\b"#], a: codi).allSatisfy { $0.hasPrefix("\(serveiArrencada):18:") })
    }

    /// D19 i regla 7: l'ajust de debò només l'escriu l'app, i només amb la carpeta `.real`. `AjustRestauracio` només es pot
    /// crear a l'app: ni el CLI ni el core poden fer-ho, amb cap ruta.
    @Test func lAjustDeWarpNomesLEscriuLApp() throws {
        let codi = try fitxers("Sources").filter { $0.ruta != "Sources/WarpLaunchCore/AjustRestauracio.swift" }
        let trobades = try aparicions(de: [#"\bAjustRestauracio\("#], a: codi)
        #expect(trobades.count == 1 && trobades[0].hasPrefix("Sources/WarpLaunchApp/WarpLaunchApp.swift"), "\(trobades)")
        let app = try fitxers("Sources/WarpLaunchApp").map(\.text).joined()
        // D-P4: dins de l'entorn que `ConsentimentRestauracio` només demana amb el consentiment acceptat
        // (`elCodiNoObreResNiRegistraArrencades`).
        #expect(app.contains("if case .real = arguments.carpeta, let preferencies {\n            creaEntornRefresc = {\n"
            + "                let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte)\n"))
    }

    @Test func lesProvesNoLlegeixenLEstatReal() throws {
        let proves = try fitxers("Tests")
        #expect(proves.count > 5, "no s'han trobat les proves a \(arrel.path)")
        let prohibides = [
            // `Lector(` només amb les rutes de prova: `Lector()`, `Lector(inici:)` o sense `rutaAjustos` llegirien Warp i
            // Claude de debò.
            #"\bLector\((?!rutaWarp:[^,]+,\s*rutaAjustos:)"#, #"\bLectorAjustosWarp\((?!ruta:)"#, #"\bAjustRestauracio\((?!ruta: b\.fitxer|ruta: tmp\.url)"#, #"ProcessosDelSistema"#,
            #"rutaPerDefecte"#, #"carpetaPerDefecte"#,
            #"\.config/warp-launch"#, #"\bNSApp\b"#, #"NSApplication"#, #"NSWindow"#, #"NSHostingView"#,
            #"homeDirectoryForCurrentUser"#, #"NSHomeDirectory"#,
            // El porta-retalls d'en David: una prova el buidaria, o hi deixaria pestanyes fictícies.
            #"NSPasteboard"#, #"PortaRetallsSistema\.(enganxa|hiHaPestanyes|escriu)"#,
            // Fase 3.1: res que obri Warp, ni les carpetes de debò de Warp i de Claude.
            #"NSWorkspace"#, #"openURL"#, #"ObreWarp"#, #"FitxersLaunchWarp\.real"#, #"\.warp/"#, #"launch_configurations"#,
            #"\.claude\.json"#, #"\.claude/projects"#,
        ]
        let trobades = try aparicions(de: prohibides, a: proves)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
    }

    /// Res del que s'arrossega no surt de l'app (docs/disseny.md, «Arrossegar»): ni fitxers, ni text, ni `ShareLink`.
    @Test func arrossegarNomesDinsDeLApp() throws {
        // Els ítems d'inici fan servir `SMAppService.mainApp.register()`, que no té res a veure amb arrossegar: al servei,
        // tota la resta de la llista.
        let codi = try fitxers("Sources")
        let trobades = try aparicions(de: prohibidesArrossegar, a: codi.filter { $0.ruta != serveiArrencada })
            + aparicions(de: prohibidesArrossegar.filter { $0 != #"\.register\("# }, a: codi.filter { $0.ruta == serveiArrencada })
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        let arrossegar = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/Arrossegar.swift"), encoding: .utf8)
        // El que s'arrossega només ho dona el proveïdor, per a aquest procés; el tipus només es llegeix.
        #expect(arrossegar.contains("visibility: .ownProcess"))
        #expect(!arrossegar.contains("visibility: .all"))
        #expect(arrossegar.contains("DataRepresentation(importedContentType:"))
        #expect(!arrossegar.contains("exportedContentType"))
        #expect(!arrossegar.contains("DataRepresentation(contentType:"))
    }

    @Test func laGuardaDetectaElQueHaDeDetectar() throws {
        // Si una expressió estigués mal escrita, la guarda no trobaria mai res.
        let mostra = [(ruta: "mostra.swift", text: """
            let p = Process()
            system("ls")
            let f = Font.system(size: 13)
            Lector().llegeix()
            Lector(rutaWarp: url)
            Lector(inici: inici)
            PortaRetallsSistema.escriu(dades)
            """)]
        let lector = #"\bLector\((?!rutaWarp:[^,]+,\s*rutaAjustos:)"#
        #expect(try aparicions(de: [#"\bProcess\("#, #"(^|[^.\w])system\("#, lector], a: mostra) == [
            "mostra.swift:1: «\\bProcess\\(»", "mostra.swift:2: «(^|[^.\\w])system\\(»",
            "mostra.swift:4: «\(lector)»", "mostra.swift:5: «\(lector)»", "mostra.swift:6: «\(lector)»",
        ])
        #expect(try aparicions(de: [lector], a: [(ruta: "mostra.swift", text: "Lector(rutaWarp: url, rutaAjustos: altra)")]).isEmpty)
        // El refresc de l'ajust (D-P4): crear-lo sí; el seu entorn, no.
        #expect(try aparicions(de: [#"\bRefrescWarp\("#], a: [(ruta: "mostra.swift", text: """
            let r = RefrescWarp(entorn: e)
            let e = RefrescWarp.Entorn(ajust: a)
            let x = AltreRefrescWarp(entorn: e)
            """)]) == ["mostra.swift:1: «\\bRefrescWarp\\(»"])
        // El consentiment (revisió de la 0.29.0): acceptar-lo i construir-ne un d'acceptat, sí; definir `accepta` o
        // comparar-hi, no.
        let consentiment = [#"\.accepta\("#, #"\.acceptat\("#, #"\.migrat\b"#, #"\.restauracio\s*=(?!=)"#]
        #expect(try aparicions(de: consentiment, a: [(ruta: "mostra.swift", text: """
            consentiment.accepta()
            public func accepta(ara: Date) {}
            guard estat == .acceptat else { return }
            p.restauracio = .acceptat(ara)
            Preferencies(restauracio: .migrat)
            if p.restauracio == .migrat {}
            """)]) == [
            "mostra.swift:1: «\\.accepta\\(»", "mostra.swift:4: «\\.acceptat\\(»", "mostra.swift:4: «\\.restauracio\\s*=(?!=)»",
            "mostra.swift:5: «\\.migrat\\b»", "mostra.swift:6: «\\.migrat\\b»",
        ])
        // `\b` no ha de deixar passar `LectorAjustosWarp()`, que llegiria el `settings.toml` d'en David.
        let ajustos = #"\bLectorAjustosWarp\((?!ruta:)"#
        #expect(try aparicions(de: [ajustos], a: [(ruta: "mostra.swift", text: "LectorAjustosWarp().desaFinestres()")]).count == 1)
        #expect(try aparicions(de: [ajustos], a: [(ruta: "mostra.swift", text: "LectorAjustosWarp(ruta: tmp)")]).isEmpty)
        #expect(try aparicions(de: [#"PortaRetallsSistema\.(enganxa|hiHaPestanyes|escriu)"#], a: mostra) == [
            "mostra.swift:7: «PortaRetallsSistema\\.(enganxa|hiHaPestanyes|escriu)»",
        ])
        // Fase 3.1: les carpetes de debò.
        let carpetes = [(ruta: "mostra.swift", text: """
            FitxersLaunchWarp.real.escriu(f)
            FitxersLaunchWarp(carpeta: tmp)
            let u = inici + "/.claude.json"
            let p = "~/.claude/projects/x"
            let w = "~/.warp/launch_configurations"
            """)]
        #expect(try aparicions(de: [#"FitxersLaunchWarp\.real"#, #"\.claude\.json"#, #"\.claude/projects"#, #"\.warp/"#],
                               a: carpetes).count == 4)
        // Arrossegar: cada expressió troba la seva línia (i `.onDragSessionUpdated`, que no fa sortir res, no).
        let arrossegar = [(ruta: "mostra.swift", text: """
            ShareLink(item: x)
            ProxyRepresentation(exporting: \\.text)
            FileRepresentation(contentType: .data) { _ in x }
            CodableRepresentation(contentType: .json)
            .onDrag { NSItemProvider() }
            NSFilePromiseProvider(fileType: t, delegate: d)
            p.suggestedFileName = "x"
            p.registerObject(x, visibility: .all)
            proveidor.register(x)
            .onDrag({ NSItemProvider() })
            .onDragSessionUpdated { _ in }
            """)]
        let trobades = try aparicions(de: prohibidesArrossegar, a: arrossegar)
        #expect(trobades == prohibidesArrossegar.enumerated().map { "mostra.swift:\($0.offset + 1): «\($0.element)»" }
            + ["mostra.swift:10: «\\.onDrag\\b»"])
        // Obrir o tancar: cada línia, la seva expressió; «Mostra al Finder», cap; `kill` com a part d'un nom, cap.
        // De Warp, totes les URL menys la de llançament. `NSWorkspace.shared.open(` passa aquesta expressió, però
        // `nomesLObridorObreWarp` el deixa en un sol lloc.
        let obrir = [(ruta: "mostra.swift", text: """
            NSWorkspace.shared.open(url)
            NSRunningApplication.current
            app.forceTerminate()
            NSWorkspace.shared.launchApplication("Warp")
            workspace.openApplication(at: url, configuration: c)
            kill(pid, SIGTERM)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            func killLinia() {}
            killpg(getpgid(pid), SIGTERM)
            URL(string: "warp://action/new_window")
            URL(string: "warp://launch/" + nom)
            URL(string: "warp://launch/x")
            """)]
        let workspace = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\))"#
        #expect(try aparicions(de: prohibidesCodi, a: obrir) == [
            "mostra.swift:2: «NSRunningApplication»",
            "mostra.swift:3: «forceTerminate»",
            "mostra.swift:4: «\(workspace)»",
            "mostra.swift:4: «launchApplication»",
            "mostra.swift:6: «\\bkill(pg)?\\(»",
            "mostra.swift:9: «\\bkill(pg)?\\(»",
            "mostra.swift:10: «warp://(?!launch/\")»",
            "mostra.swift:12: «warp://(?!launch/\")»",
        ])
    }
}

@Suite struct PaquetTests {
    private func infoPlist() throws -> [String: Any] {
        let dades = try Data(contentsOf: arrel.appending(path: "Recursos/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: dades, format: nil) as? [String: Any])
    }

    /// ⌃⌘I no amagava l'inspector, ni amb `InspectorCommands()` (prova 3) ni amb una ordre pròpia (prova 4): l'ordre
    /// és pròpia, amb ⌥⌘I (docs/fets-verificats.md).
    @Test func lInspectorTeLaSevaOrdre() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        let ordres = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/Ordres.swift"), encoding: .utf8)
        #expect(!app.contains("InspectorCommands()"))
        #expect(ordres.contains(#".keyboardShortcut("i", modifiers: [.option, .command])"#))
    }

    /// La fila d'una finestra decideix si accepta pestanyes en cada arrossegament, no quan es dibuixa: amb `isEnabled`,
    /// la d'una finestra triada en crear-la no les acceptava mai més (prova 7).
    @Test func laFilaDeLaFinestraDecideixEnArrossegar() throws {
        let vista = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/VistaEditor.swift"), encoding: .utf8)
        #expect(!vista.contains("isEnabled: editor.acceptaPestanyes"))
        #expect(vista.contains("let accepta = editor.acceptaPestanyes(finestra)"))
        #expect(vista.contains("DropConfiguration(operation: accepta ? .move : .forbidden)"))
    }

    /// «Mostra al Finder» és l'única crida a `NSWorkspace`, i només és a `Finder.swift`.
    @Test func nomesFinderMostraElFitxer() throws {
        let codi = try fitxers("Sources")
        let llocs = codi.filter { $0.text.contains("activateFileViewerSelecting") }.map(\.ruta)
        #expect(llocs == ["Sources/WarpLaunchUI/Finder.swift"])
    }

    /// Fase 3.1 (D5): l'única URL de Warp és la de llançament, i només la fa `URLLlancament`, en una sola línia.
    @Test func nomesHiHaLURLDeLlancament() throws {
        let linies = try fitxers("Sources").flatMap { fitxer in
            fitxer.text.split(separator: "\n").filter { $0.contains("warp://") }.map { (fitxer.ruta, String($0)) }
        }
        #expect(linies.count == 1, "\(linies)")
        #expect(linies.first?.0 == "Sources/WarpLaunchCore/LaunchConfigWarp.swift")
        #expect(linies.first?.1.contains(#"URL(string: "warp://launch/" + nom)"#) == true)
    }

    /// Fase 3.1: obrir una cosa a Warp només ho fa `ObreWarp.obre`, amb una sola crida a `NSWorkspace.shared.open(`;
    /// només el connecten l'app (a `Obertura`) i el CLI (`obre --obre`, D17). Tots dos passen per `ExecucioObertura`,
    /// l'única que escriu el fitxer i crida l'obridor. Dins d'`Obertura` només hi arriba `confirmaIObre`, que només
    /// crida el botó del full de confirmació; al CLI, només `obreDeDebo`, amb `--obre`.
    @Test func nomesLObridorObreWarp() throws {
        let codi = try fitxers("Sources")
        func llocs(_ text: String) -> [String] {
            codi.flatMap { f in f.text.split(separator: "\n").filter { $0.contains(text) }.map { _ in f.ruta } }
        }
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        let ordre = "Sources/WarpLaunchCore/OrdreCLI.swift"
        let execucio = "Sources/WarpLaunchCore/ExecucioObertura.swift"
        #expect(llocs("NSWorkspace.shared.open(") == ["Sources/WarpLaunchObridor/ObreWarp.swift"])
        // Obrir Warp, si és tancat (0.22.0): també només l'obridor.
        // Qualsevol aparició de la paraula, amb qualsevol objecte, també en un comentari.
        #expect(llocs("openApplication") == ["Sources/WarpLaunchObridor/ObreWarp.swift"])
        #expect(Set(llocs("NSWorkspace.OpenConfiguration")) == ["Sources/WarpLaunchObridor/ObreWarp.swift"])
        #expect(Set(llocs("ObreWarp.obre(")) == [app, cli] && llocs("ObreWarp.obre(").count == 2)
        #expect(Set(llocs("ObreWarp.engega(")) == [app, cli] && llocs("ObreWarp.engega(").count == 2)
        #expect(llocs("entorn.engegaWarp(") == ["Sources/WarpLaunchUI/Obertura.swift"])
        #expect(llocs("obridor.engega(") == [ordre])
        #expect(Set(llocs("import WarpLaunchObridor")) == [app, cli] && llocs("import WarpLaunchObridor").count == 2)
        #expect(Set(llocs("FitxersLaunchWarp.real")) == [app, cli] && llocs("FitxersLaunchWarp.real").count == 2)
        #expect(llocs("entorn.obre(") == [execucio])
        #expect(llocs("entorn.fitxers.escriu(") == [execucio])
        #expect(Set(llocs("ExecucioObertura.executa(")) == ["Sources/WarpLaunchUI/Obertura.swift", ordre])
        #expect(llocs("obreDeDebo(").count == 2, "la definició i la crida, amb --obre")
        #expect(Set(llocs("confirmaIObre(")) == ["Sources/WarpLaunchUI/Obertura.swift", "Sources/WarpLaunchUI/FullObertura.swift"])
        #expect(llocs("confirmaIObre(").count == 2, "la definició i el botó del full")
        #expect(Set(llocs("confirmaIObreTot(")) == ["Sources/WarpLaunchUI/ObreTot.swift", "Sources/WarpLaunchUI/FullObertura.swift"])
        #expect(llocs("confirmaIObreTot(").count == 2, "la definició i el botó del full")
        // Els passos d'obrir d'una finestra només es criden des dels dos botons del full.
        #expect(Set(llocs("await executa(").filter { $0.hasPrefix("Sources/WarpLaunchUI/") }) == ["Sources/WarpLaunchUI/Obertura.swift", "Sources/WarpLaunchUI/ObreTot.swift"])
        // Al CLI, `--obre` només el mira l'entrada asíncrona, que és la que arriba a `obreDeDebo`.
        let ordreCLI = try #require(codi.first { $0.ruta == ordre })
        let definicio = try #require(ordreCLI.text.range(of: "private static func obreDeDebo("))
        let crida = try #require(ordreCLI.text.range(of: "try await obreDeDebo("))
        let entrada = try #require(ordreCLI.text.range(of: "obridor: ObridorCLI,\n                               sortida: inout Sortida) async -> Int32"))
        #expect(entrada.upperBound < crida.lowerBound && crida.lowerBound < definicio.lowerBound)
        #expect(ordreCLI.text[entrada.upperBound..<crida.lowerBound].contains(#"args.first == "obre", args.contains("--obre")"#))
    }

    /// Els botons i les ordres «Obre…» només demanen el full (`demanaObertura`), i cap no té drecera; el del full
    /// tampoc, ni és el botó per defecte (docs/disseny.md, secció 7, «Seguretat»).
    @Test func elsBotonsDObrirNomesDemanenElFull() throws {
        let codi = try fitxers("Sources")
        var trobats = 0
        for fitxer in codi {
            let linies = fitxer.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (n, linia) in linies.enumerated() where linia.contains(#"Button("Obre"#) {
                trobats += 1
                let seguents = linies[n..<min(linies.count, n + 6)].joined(separator: "\n")
                if fitxer.ruta.hasSuffix("/FullObertura.swift") {
                    #expect(seguents.contains("confirmaIObre()") || seguents.contains("confirmaIObreTot()"),
                            "\(fitxer.ruta):\(n + 1)")
                } else {
                    // «Obre-ho tot a Warp…» (fase 3.2) també només demana el seu full.
                    #expect(linia.contains("demanaObertura(") || seguents.contains("editor.demanaObertura(")
                            || linia.contains("demanaObreTot()") || seguents.contains("editor.demanaObreTot()"),
                            "\(fitxer.ruta):\(n + 1)")
                }
                let finsAlSeguentBoto = linies[(n + 1)..<min(linies.count, n + 6)].prefix { !$0.contains("Button(") }
                #expect(!finsAlSeguentBoto.contains { $0.contains("keyboardShortcut") }, "\(fitxer.ruta):\(n + 1)")
            }
        }
        // Menú Fitxer, inspector, menú de la icona, barra d'eines i menú contextual de l'editor, i el full; i «Obre-ho tot»
        // al menú Fitxer, al menú de la icona i al seu full.
        #expect(trobats == 9)
    }

    /// Fase 3.1: només `FitxersLaunchWarp` sap on és la carpeta de Warp, i dins seu només esborra una crida (`treu`), a
    /// la qual només s'arriba amb totes les comprovacions o just després de crear el fitxer. Sense sobreescriure,
    /// canviar de nom ni crear carpetes.
    @Test func nomesFitxersLaunchWarpTocaLaCarpetaDeWarp() throws {
        let codi = try fitxers("Sources")
        #expect(codi.filter { $0.text.contains("launch_configurations") }.map(\.ruta)
            == ["Sources/WarpLaunchCore/FitxersLaunchWarp.swift"])
        let fitxer = try #require(codi.first { $0.ruta.hasSuffix("/FitxersLaunchWarp.swift") })
        #expect(try aparicions(de: [#"\bunlink\("#], a: [fitxer]).count == 1)
        let prohibides = [#"removeItem"#, #"\brename\("#, #"createDirectory"#, #"O_TRUNC"#, #"\.write\(to:"#,
                          #"\bmkdir\("#, #"replaceItem"#, #"moveItem"#, #"copyItem"#]
        #expect(try aparicions(de: prohibides, a: [fitxer]).isEmpty)
        #expect(fitxer.text.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW"))
    }

    /// A les proves, `Process(` només és als helpers que fan llegir una línia a zsh o executen un script de `scripts/`.
    @Test func processNomesAlHelperDeZsh() throws {
        let llocs = try fitxers("Tests").filter { $0.text.contains("Process(") }.map(\.ruta)
        #expect(llocs == ["Tests/WarpLaunchCoreTests/ShellDeProva.swift"])
    }

    /// `estat.json` només l'escriu l'app (fase 3.1) i, amb `obre --obre` (D17), el CLI: el magatzem només es crea dins
    /// d'`obreDeDebo`.
    @Test func elCLINoEscriuLEstat() throws {
        let main = try fitxers("Sources/WarpLaunchCLI")
        #expect(main.count >= 1)
        let trobades = try aparicions(de: [#"MagatzemEstat"#, #"EstatSessions"#, #"EscripturaAtomica"#], a: main)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        let ordre = try #require(try fitxers("Sources").first { $0.ruta.hasSuffix("/OrdreCLI.swift") })
        #expect(try aparicions(de: [#"EstatSessions"#, #"EscripturaAtomica"#], a: [ordre]).isEmpty)
        let usos = ordre.text.ranges(of: "MagatzemEstat(")
        #expect(usos.count == 1)
        let inici = try #require(ordre.text.range(of: "private static func obreDeDebo("))
        let fi = try #require(ordre.text.range(of: "/// La finestra pel número (1…) o pel nom"))
        #expect(usos.allSatisfy { inici.upperBound < $0.lowerBound && $0.upperBound < fi.lowerBound })
    }

    /// Substituir el grup `.saveItem` treu «Tanca» (⌘W) i «Tanca-ho tot» (⌥⌘W) del menú Fitxer.
    @Test func tancaTeLaSevaDrecera() throws {
        let ordres = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/Ordres.swift"), encoding: .utf8)
        #expect(!ordres.contains("replacing: .saveItem"))
    }

    /// Les pestanyes copiades són dades, mai text: enganxades a Warp, no hi han d'escriure cap ordre.
    @Test func elTipusDelPortaRetallsNoEsText() throws {
        let tipus = try #require(infoPlist()["UTExportedTypeDeclarations"] as? [[String: Any]])
        let pestanyes = try #require(tipus.first { $0["UTTypeIdentifier"] as? String == PortaRetalls.tipus })
        #expect(pestanyes["UTTypeConformsTo"] as? [String] == ["public.data"])
    }

    @Test func esUnaAppDeBarraDeMenuEnCatala() throws {
        let plist = try infoPlist()
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["CFBundleIdentifier"] as? String == "cat.davide.warp-launch")
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "ca")
        #expect(plist["CFBundleLocalizations"] as? [String] == ["ca"])
        #expect(FileManager.default.fileExists(atPath: arrel.appending(path: "Recursos/ca.lproj/InfoPlist.strings").path))
    }

    /// Pas 12: el que el Finder mostra a «Obtén informació» i la categoria de l'app.
    @Test func elPaquetEsComplet() throws {
        let plist = try infoPlist()
        #expect(plist["CFBundleInfoDictionaryVersion"] as? String == "6.0")
        #expect(plist["LSApplicationCategoryType"] as? String == "public.app-category.developer-tools")
        #expect((plist["NSHumanReadableCopyright"] as? String)?.contains("David Erra") == true)
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }

    /// La icona (pas 12): `icon.json` només fa servir capes que existeixen (si en falta una, `actool` falla i `ictool`
    /// dibuixa un fons buit), i la compilada no és més vella que el dibuix (`build-app.sh` s'aturaria).
    @Test func laIconaTeTotesLesCapes() throws {
        let icona = arrel.appending(path: "Recursos/AppIcon.icon")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: icona.appending(path: "icon.json"))) as? [String: Any])
        let grups = try #require(json["groups"] as? [[String: Any]])
        let capes = grups.flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }.compactMap { $0["image-name"] as? String }
        #expect(capes.sorted() == ["fons.png", "principal.png"])
        for capa in capes {
            #expect(FileManager.default.fileExists(atPath: icona.appending(path: "Assets/\(capa)").path), "falta \(capa)")
        }
        for compilada in ["Recursos/Assets.car", "Recursos/AppIcon.icns"] {
            #expect(FileManager.default.fileExists(atPath: arrel.appending(path: compilada).path), "falta \(compilada)")
        }
    }

    @Test func elScriptDelPaquetCopiaElCatala() throws {
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("Recursos/ca.lproj"))
    }

    /// El repo és públic amb llicència MIT, i l'app compilada la porta a `Contents/Resources/LICENSE`.
    @Test func laLlicenciaEsMITIVaDinsDelPaquet() throws {
        let llicencia = try String(contentsOf: arrel.appending(path: "LICENSE"), encoding: .utf8)
        #expect(llicencia.hasPrefix("MIT License\n\nCopyright (c) 2026 David Erra\n"))
        #expect(llicencia.contains("Permission is hereby granted, free of charge, to any person obtaining a copy"))
        #expect(llicencia.contains(#"THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND"#))
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains(#"cp -X LICENSE "$APP/Contents/Resources/LICENSE""#))
        // Abans de signar: un fitxer afegit després trencaria la signatura.
        let copia = try #require(script.range(of: "cp -X LICENSE"))
        let signa = try #require(script.range(of: "codesign --force"))
        #expect(copia.lowerBound < signa.lowerBound)
    }

    @Test func elScriptDelPaquetSignaAmbElCertificatPropi() throws {
        // D12: amb el certificat, el permís per llegir Warp no es perd a cada compilació; sense, ad hoc.
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("Warp Launch Dev"))
        #expect(script.contains("codesign --force --sign \"$IDENTITAT\""))
        #expect(script.contains("codesign --force --sign - "))
    }
}
