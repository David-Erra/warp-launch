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
private let workspace = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\))"#
private let prohibidesCodi = [
    #"warp://(?!launch/")"#, #"\bProcess\("#,
    workspace, #"openURL"#,
    #"NSAppleScript"#, #"posix_spawn"#, #"(^|[^.\w])system\("#, #"SMAppService"#, #"LaunchAgents"#, #"UserDefaults"#,
    #"@AppStorage"#,
    // Tancar o matar Warp o Claude (regla 2), o obrir apps. La paraula `openApplication` només pot ser a l'obridor, per
    // obrir Warp si és tancat (`nomesLObridorObreWarp`).
    #"NSRunningApplication"#, #"forceTerminate"#, #"launchApplication"#, #"\bkill(pg)?\("#,
]

private let serveiArrencada = "Sources/WarpLaunchApp/ServeiArrencada.swift"

/// D-P12 (excepcions limitades, 0.29.2): on és Warp només ho pregunta `TrobaWarp`, amb aquesta sola crida i l'identificador
/// que li passa `InstallacioWarp.troba` (`nomesTrobaWarpPreguntaOnEsWarp`). A la resta del codi, `workspace` la prohibeix.
private let trobaWarp = "Sources/WarpLaunchObridor/TrobaWarp.swift"
private let workspaceTrobaWarp = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\)|\.shared\.urlForApplication\(withBundleIdentifier: \$0\))"#

/// Les expressions de `prohibidesCodi` que valen per a un fitxer de `Sources`: totes, menys les excepcions, cadascuna en
/// un sol fitxer. `SMAppService`, només als ítems d'inici (D3, `nomesLInterruptorRegistraLArrencada`).
private func prohibidesCodi(a ruta: String) -> [String] {
    switch ruta {
    case serveiArrencada: prohibidesCodi.filter { $0 != #"SMAppService"# }
    case trobaWarp: prohibidesCodi.map { $0 == workspace ? workspaceTrobaWarp : $0 }
    default: prohibidesCodi
    }
}

/// Les línies del codi que poden obrir, tancar o registrar res, amb les expressions de cada fitxer.
private func obrenOTanquen(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try codi.flatMap { try aparicions(de: prohibidesCodi(a: $0.ruta), a: [$0]) }
}

/// Pla A4: a les proves, els lectors de Claude només amb una ruta, i «Copia el diagnòstic» només amb un porta-retalls fals.
/// Sense `\b`: amb les regles d'Unicode, `WarpLaunchCore.LectorConfianca(` no hi té cap límit de paraula.
private let lectorTranscripcions = #"(^|[^A-Za-z0-9_])LectorTranscripcions\((?!carpeta:)"#
private let lectorConfianca = #"(^|[^A-Za-z0-9_])LectorConfianca\((?!ruta:)"#
private let copiaDiagnostic = #"(^|[^A-Za-z0-9_])CopiaDiagnostic\((?![^\n]*escriu:)"#

/// Pla A4: el diagnòstic només llegeix. Res que escrigui, esborri, executi o toqui el porta-retalls. Sense `\b`: amb les
/// regles d'Unicode, `default.moveItem` o `Darwin.open` no hi tenen cap límit de paraula.
private let escriuen = [
    #"\.desa\("#, #"\.posa\("#, #"\.accepta\("#, #"EscripturaAtomica"#, #"\.write\("#, #"createFile"#,
    #"createDirectory"#, #"removeItem"#, #"(^|[^A-Za-z0-9_])moveItem"#, #"copyItem"#, #"replaceItem"#,
    #"(^|[^A-Za-z0-9_])unlink\("#, #"(^|[^A-Za-z0-9_])rename\("#, #"(^|[^A-Za-z0-9_])open\("#, #"sqlite3_open"#,
    #"forWriting"#, #"forUpdating"#, #"(^|[^A-Za-z0-9_])AjustRestauracio\("#, #"posaRestauracio"#,
    #"recordaRestauracioOriginal"#, #"(^|[^A-Za-z0-9_])Process\("#, #"NSPasteboard"#, #"copiaText"#,
]

/// Decisió 3 (0.31.0): «Deixa de fer servir Warp Launch». Cada pas és una excepció, i només val al seu fitxer:
/// - posar l'ajust de Warp a un valor que no és el d'un refresc: només `RefrescWarp.retira` (`entorn.posa(`, que fins ara
///   només activava i desactivava l'ajust en un refresc);
/// - retirar el refresc i el permís, i desfer-ho si no es pot desar: només `ConsentimentRestauracio.retira`;
/// - fer-ho tot, i treure l'app dels ítems d'inici fora de l'interruptor: només `Desinstallacio`, que només crea l'app;
/// - confirmar-ho: només el botó de la confirmació de la Configuració.
/// Les expressions no miren qui fa la crida: cap altre fitxer no pot cridar cap funció amb aquests noms.
private let rutaRefresc = "Sources/WarpLaunchUI/RefrescWarp.swift"
private let rutaConsentimentUI = "Sources/WarpLaunchUI/ConsentimentRestauracio.swift"
private let rutaDesinstallacio = "Sources/WarpLaunchUI/Desinstallacio.swift"
private let rutaVistaConfiguracio = "Sources/WarpLaunchUI/VistaConfiguracio.swift"
private let rutaAppPrincipal = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
private let retirada: [(expressio: String, fitxer: String, mostra: String)] = [
    (#"entorn\.posa\("#, rutaRefresc, "try entorn.posa(valor)"),
    (#"\.retira\(posant:"#, rutaConsentimentUI, "try refresc.retira(posant: retorn.valor)"),
    (#"\.desfesRetirada\("#, rutaConsentimentUI, "refresc.desfesRetirada()"),
    (#"\.retira\(ara:"#, rutaConsentimentUI, "try magatzem.retira(ara: rellotge())"),
    (#"\.retira\((?!posant:|ara:)"#, rutaDesinstallacio, "try consentiment.retira(retorn)"),
    (#"\.treuDelsItemsDInici\("#, rutaDesinstallacio, "if let motiu = arrencada.treuDelsItemsDInici() {"),
    (#"(^|[^A-Za-z0-9_])Desinstallacio\("#, rutaAppPrincipal, "let d = Desinstallacio(consentiment: c, arrencada: a, surt: s)"),
    (#"desinstallacio\.confirma\("#, rutaVistaConfiguracio, "desinstallacio.confirma()"),
]

/// Les línies de la retirada que són fora del seu fitxer.
private func retiradaForaDeLloc(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try retirada.flatMap { r in try aparicions(de: [r.expressio], a: codi.filter { $0.ruta != r.fitxer }) }
}

/// El que s'arrossega no surt de l'app: ni fitxers, ni text, ni `ShareLink`.
private let prohibidesArrossegar = [
    #"ShareLink"#, #"ProxyRepresentation"#, #"FileRepresentation"#, #"CodableRepresentation"#, #"\.onDrag\b"#,
    #"NSFilePromiseProvider"#, #"suggestedFileName"#, #"registerObject"#, #"\.register\("#,
]

@Suite struct GuardaTests {
    @Test func elCodiNoObreResNiRegistraArrencades() throws {
        let codi = try fitxers("Sources")
        #expect(codi.count > 10, "no s'ha trobat el codi a \(arrel.path)")
        let trobades = try obrenOTanquen(codi)
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
            // 0.31.0: «Deixa de fer servir Warp Launch» (`deixarDeFerServirLAppNomesDesDelBoto`).
            "estat = .retirat",
        ], "\(assignacions)")
        // El consentiment només el dona l'usuari, amb el botó «Accepta»: cap altre codi no l'accepta ni el desa per ell.
        let accepten = try aparicions(de: [#"\.accepta\("#], a: codi)
        #expect(accepten.count == 2 && accepten.contains { $0.hasPrefix("\(rutaConsentiment):") }
            && accepten.contains { $0.hasPrefix("Sources/WarpLaunchUI/VistaConsentiment.swift:") }, "\(accepten)")
        let vista = try #require(codi.first { $0.ruta == "Sources/WarpLaunchUI/VistaConsentiment.swift" }).text
        #expect(vista.contains(#"Button("Accepta") { consentiment.accepta() }"#))
        // Retirar-lo (`.retirat(`, 0.31.0) tampoc: només `MagatzemPreferencies.retira`.
        let preferencies = "Sources/WarpLaunchCore/Preferencies.swift"
        let consentiments = try aparicions(de: [#"\.acceptat\("#, #"\.migrat\b"#, #"\.restauracio\s*=(?!=)"#, #"\.retirat\("#],
                                           a: codi)
        #expect(!consentiments.isEmpty && consentiments.allSatisfy { $0.hasPrefix("\(preferencies):") }, "\(consentiments)")
        #expect(consentiments.contains { $0.hasSuffix("«\\.retirat\\(»") }, "\(consentiments)")
    }

    /// D-P12 (0.29.2): on és Warp només ho pregunta `TrobaWarp`, amb una sola crida, i només per als dos identificadors de
    /// Warp (`InstallacioWarp.troba`). Només el fan servir l'app i el CLI (també `ObreWarp`, per defecte), cap prova.
    @Test func nomesTrobaWarpPreguntaOnEsWarp() throws {
        let codi = try fitxers("Sources")
        func linies(_ text: String) -> [String] {
            codi.flatMap { f in
                f.text.split(separator: "\n").filter { $0.contains(text) }
                    .map { "\(f.ruta): \($0.trimmingCharacters(in: .whitespaces))" }
            }
        }
        // Qualsevol aparició de la paraula, també en un comentari.
        #expect(linies("urlForApplication") == [
            "\(trobaWarp): cerca: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })",
        ])
        // Ni cap altra manera de demanar on és una app.
        let altres = try aparicions(de: [#"urlsForApplications"#, #"URLForApplication"#, #"LSCopyApplicationURLs"#,
                                         #"fullPathForApplication"#, #"absolutePathForAppBundle"#, #"NSMetadataQuery"#], a: codi)
        #expect(altres.isEmpty, "\(altres)")
        let troba = try #require(codi.first { $0.ruta == trobaWarp }).text
        #expect(troba.contains("InstallacioWarp.troba(aplicacions: AppWarp.rutaPerDefecte,\n"))
        #expect(troba.components(separatedBy: "NSWorkspace").count == 2, "una sola crida a NSWorkspace")
        #expect(linies("InstallacioWarp.troba(").map { $0.prefix(trobaWarp.count) } == [Substring(trobaWarp)])
        // La llista fixa: `troba` només demana els dos identificadors de Warp.
        #expect(linies("cerca(").sorted() == [
            "Sources/WarpLaunchCore/AppWarp.swift: let preview = installada(cerca(AppWarp.identificadorPreview)).flatMap { $0.esPreview ? $0 : nil }",
            "Sources/WarpLaunchCore/AppWarp.swift: let trobada = installada(cerca(AppWarp.identificador)).flatMap { $0.esWarp ? $0 : nil }",
        ])
        // I els dos identificadors són els de Warp, escrits un sol cop (D-P12: les adreces, en una llista fixa). Sense
        // això, canviar-ne el valor faria preguntar per una altra app i cap prova no ho veuria.
        #expect(linies("\"dev.warp.Warp-").sorted() == [
            "Sources/WarpLaunchCore/AppWarp.swift: public static let identificador = \"dev.warp.Warp-Stable\"",
            "Sources/WarpLaunchCore/AppWarp.swift: public static let identificadorPreview = \"dev.warp.Warp-Preview\"",
        ])
        // Fora dels comentaris.
        #expect(Set(linies("TrobaWarp.delSistema").filter { !$0.contains(": //") }.map { String($0.prefix { $0 != ":" }) }) == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift", "Sources/WarpLaunchCLI/main.swift", "Sources/WarpLaunchObridor/ObreWarp.swift",
        ])
        // L'app i el CLI llegeixen Warp on és de debò: el lector de cadascun en porta la crida.
        #expect(linies("Lector(processos:").sorted() == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: let lector = Lector(processos: processos, warp: TrobaWarp.delSistema, inici: inici)",
            "Sources/WarpLaunchCLI/main.swift: let lector = Lector(processos: processos, warp: TrobaWarp.delSistema)",
        ])
    }

    /// La crida de `TrobaWarp` (D-P12) només val en aquell fitxer: a qualsevol altre, la guarda falla. I en aquell, només
    /// aquella crida: cap altra de `NSWorkspace`, ni la mateixa amb un altre identificador.
    @Test func laCridaDeTrobaWarpNomesValAlSeuFitxer() throws {
        let codi = try fitxers("Sources")
        #expect(try obrenOTanquen(codi).isEmpty)
        let crida = "        cerca: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })"
        for ruta in ["Sources/WarpLaunchCore/AppWarp.swift", "Sources/WarpLaunchObridor/ObreWarp.swift",
                     "Sources/WarpLaunchObridor/Altre.swift", "Sources/WarpLaunchApp/WarpLaunchApp.swift", serveiArrencada,
                     "Sources/WarpLaunchCLI/main.swift", "Sources/WarpLaunchUI/Finder.swift", "TrobaWarp.swift"] {
            #expect(try obrenOTanquen(codi + [(ruta: ruta, text: crida)]) == ["\(ruta):1: «\(workspace)»"], "\(ruta)")
        }
        #expect(try obrenOTanquen([(ruta: trobaWarp, text: crida)]).isEmpty)
        let altres = [(ruta: trobaWarp, text: """
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0)
            NSWorkspace.shared.launchApplication("Warp")
            NSWorkspace.shared.urlForApplication(toOpen: url)
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0); NSWorkspace.shared.hideOtherApplications()
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0 + "x")
            """)]
        #expect(try obrenOTanquen(altres) == [
            "\(trobaWarp):1: «\(workspaceTrobaWarp)»", "\(trobaWarp):2: «\(workspaceTrobaWarp)»",
            "\(trobaWarp):3: «\(workspaceTrobaWarp)»", "\(trobaWarp):3: «launchApplication»",
            "\(trobaWarp):4: «\(workspaceTrobaWarp)»", "\(trobaWarp):5: «\(workspaceTrobaWarp)»",
            "\(trobaWarp):6: «\(workspaceTrobaWarp)»",
        ])
        // La resta de la llista hi continua valent: l'excepció només canvia l'expressió de `NSWorkspace`.
        #expect(prohibidesCodi(a: trobaWarp).count == prohibidesCodi.count)
        #expect(Set(prohibidesCodi(a: trobaWarp)).symmetricDifference(prohibidesCodi) == [workspace, workspaceTrobaWarp])
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
        // Treure-la: l'interruptor i, des de la 0.31.0, «Deixa de fer servir Warp Launch» (`treuDelsItemsDInici`, només des de
        // `Desinstallacio`: `deixarDeFerServirLAppNomesDesDelBoto`).
        #expect(model.components(separatedBy: "entorn.desactiva()").count == 3)
        // Dins del servei, `entorn` només es defineix, i `register` només és a la seva línia; enlloc més no hi és.
        #expect(servei.components(separatedBy: "entorn").count == 2)
        #expect(try aparicions(de: [#"\bregister\b"#], a: codi).allSatisfy { $0.hasPrefix("\(serveiArrencada):18:") })
    }

    /// Decisió 3 (0.31.0): «Deixa de fer servir Warp Launch» (vegeu `retirada`). Cada pas, al seu fitxer i amb la seva línia,
    /// en ordre, i tota la cadena només surt del botó de la confirmació.
    @Test func deixarDeFerServirLAppNomesDesDelBoto() throws {
        let codi = try fitxers("Sources")
        let fora = try retiradaForaDeLloc(codi)
        #expect(fora.isEmpty, "\(fora.joined(separator: "\n"))")
        func text(_ ruta: String) throws -> String { try #require(codi.first { $0.ruta == ruta }).text }
        func linies(_ ruta: String, _ expressio: String) throws -> [String] {
            let reg = try Regex(expressio)
            return try text(ruta).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && $0.contains(reg) }
        }
        func abans(_ ruta: String, _ textos: [String]) throws -> Bool {
            let t = try text(ruta)
            let llocs = textos.compactMap { t.range(of: $0)?.lowerBound }
            return llocs.count == textos.count && llocs == llocs.sorted()
        }

        // L'ajust: un refresc l'activa i el desactiva; només la retirada el posa al valor que li donen, després d'aturar-se.
        #expect(try linies(rutaRefresc, #"entorn\.posa\("#) == ["try entorn.posa(valor)", "try entorn.posa(true)",
                                                                 "try entorn.posa(false)"])
        let refresc = try text(rutaRefresc)
        let inici = try #require(refresc.range(of: "    public func retira(posant valor: Bool?) throws {\n"))
        let fi = try #require(refresc[inici.upperBound...].range(of: "\n    }\n"))
        let cos = refresc[inici.upperBound..<fi.lowerBound]
        #expect(cos.hasPrefix("        guard !retirat else { return }\n        retirat = true\n        enCurs?.cancel()\n"))
        #expect(cos.contains("try entorn.posa(valor)"))
        // Retirat, cap altre camí no el toca: la vigilància, el cicle i desactivar-lo (també en sortir) ho miren.
        for guarda in ["guard enCurs == nil, !retirat else { return }", "guard !retirat else { return avisant(",
                       "guard !aturat, !retirat, !Task.isCancelled, entorn.warpObert() else {",
                       "    private func desactiva() {\n        guard !retirat else { return }\n"] {
            #expect(refresc.contains(guarda), "\(guarda)")
        }
        // Només `retira` el retira, i només si no es pot posar i en desfer-la es torna a fals.
        #expect(try linies(rutaRefresc, #"^retirat = "#) == ["retirat = true", "retirat = false", "retirat = false"])

        // El permís: primer l'ajust, després el fitxer (si no es pot desar, l'ajust es torna a desactivar), i llavors l'estat.
        #expect(try linies(rutaConsentimentUI, #"\.retira\(posant:"#) == ["try refresc.retira(posant: retorn.valor)"])
        #expect(try linies(rutaConsentimentUI, #"\.retira\(ara:"#) == ["try magatzem.retira(ara: rellotge())"])
        #expect(try linies(rutaConsentimentUI, #"\.desfesRetirada\("#) == ["refresc.desfesRetirada()"])
        #expect(try abans(rutaConsentimentUI, ["try refresc.retira(posant: retorn.valor)", "try magatzem.retira(ara: rellotge())",
                                               "refresc.desfesRetirada()", "estat = .retirat"]))

        // Tot plegat: els ítems d'inici (si no es poden treure, res més), l'ajust i el permís, i sortir.
        #expect(try linies(rutaDesinstallacio, #"\.treuDelsItemsDInici\("#) == ["if let motiu = arrencada.treuDelsItemsDInici() {"])
        #expect(try linies(rutaDesinstallacio, #"\.retira\("#) == ["try consentiment.retira(retorn)"])
        #expect(try linies(rutaDesinstallacio, #"surt\(\)"#) == ["surt()"])
        #expect(try abans(rutaDesinstallacio, ["public func confirma() {", "arrencada.treuDelsItemsDInici()",
                                               "try consentiment.retira(retorn)", "surt()"]))
        // L'ajust i els ítems d'inici de l'app (els de debò, només amb la configuració de debò), i res més.
        #expect(try linies(rutaAppPrincipal, #"Desinstallacio\("#) == [
            "let desinstallacio = Desinstallacio(consentiment: consentiment, arrencada: arrencada, surt: { NSApp.terminate(nil) })",
        ])
        // I només el botó de la confirmació.
        #expect(try linies(rutaVistaConfiguracio, #"\.confirma\("#) == [
            #"Button("Restaura Warp i surt", role: .destructive) { desinstallacio.confirma() }"#,
        ])
        #expect(try text(rutaVistaConfiguracio).components(separatedBy: ".confirmationDialog(").count == 2)
        // Treure l'app dels ítems d'inici no l'hi pot afegir.
        let arrencada = try text("Sources/WarpLaunchUI/ArrencadaSessio.swift")
        let treu = try #require(arrencada.range(of: "    public func treuDelsItemsDInici() -> String? {\n"))
        let fiTreu = try #require(arrencada[treu.upperBound...].range(of: "\n    }\n"))
        let cosTreu = arrencada[treu.upperBound..<fiTreu.lowerBound]
        #expect(cosTreu.contains("try entorn.desactiva()"))
        #expect(!cosTreu.replacingOccurrences(of: "desactiva()", with: "").contains("activa()"))
    }

    /// Cada línia de la retirada (`retirada`) només val al seu fitxer: a qualsevol altre, la guarda falla.
    @Test func laRetiradaNomesValAlSeuFitxer() throws {
        let codi = try fitxers("Sources")
        #expect(try retiradaForaDeLloc(codi).isEmpty)
        let altres = Set(retirada.map(\.fitxer) + [
            "Sources/WarpLaunchUI/Obertura.swift", "Sources/WarpLaunchUI/ArrencadaSessio.swift",
            "Sources/WarpLaunchUI/VistaConsentiment.swift", "Sources/WarpLaunchUI/EstatWarp.swift",
            "Sources/WarpLaunchCore/Preferencies.swift", "Sources/WarpLaunchCore/AjustRestauracio.swift",
            "Sources/WarpLaunchApp/ServeiArrencada.swift", "Sources/WarpLaunchCLI/main.swift", "Sources/WarpLaunchUI/Altre.swift",
        ])
        // Línia a línia: el codi ja és net, i n'hi ha prou de mirar la línia de mostra a cada fitxer.
        for r in retirada {
            for ruta in altres.sorted() where ruta != r.fitxer {
                #expect(try retiradaForaDeLloc([(ruta: ruta, text: r.mostra)]) == ["\(ruta):1: «\(r.expressio)»"],
                        "\(ruta): \(r.mostra)")
            }
            #expect(try retiradaForaDeLloc([(ruta: r.fitxer, text: r.mostra)]).isEmpty, "\(r.mostra)")
        }
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
            // D-P12: on és Warp de debò. `troba` només amb una carpeta temporal; la instal·lació per omissió no es llegeix.
            #"TrobaWarp"#, #"urlForApplication"#, #"\bInstallacioWarp\.troba\((?!aplicacions: tmp\.)"#, #"perOmissio\.app(?![A-Za-z0-9_])"#,
            // Pla A4 (diagnòstic): els lectors de Claude, sempre amb una ruta de prova (sense, llegirien ~/.claude), i
            // «Copia el diagnòstic», sempre amb un porta-retalls fals (a la mateixa línia).
            lectorTranscripcions, lectorConfianca, copiaDiagnostic,
        ]
        let trobades = try aparicions(de: prohibides, a: proves)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
    }

    /// Pla A4: el diagnòstic només llegeix (`Diagnostic.swift`), i el porta-retalls només l'escriu el clic al botó: l'únic
    /// `CopiaDiagnostic` és el de l'app.
    @Test func elDiagnosticNomesLlegeix() throws {
        let codi = try fitxers("Sources")
        let diagnostic = try #require(codi.first { $0.ruta == "Sources/WarpLaunchCore/Diagnostic.swift" })
        let trobades = try aparicions(de: escriuen, a: [diagnostic])
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        let copies = try aparicions(de: [#"(^|[^A-Za-z0-9_])CopiaDiagnostic\("#], a: codi)
        #expect(copies.count == 1 && copies[0].hasPrefix("Sources/WarpLaunchApp/WarpLaunchApp.swift:"), "\(copies)")
        // Cada expressió troba la seva línia.
        let mostra = [(ruta: "mostra.swift", text: """
            try magatzem.desa(p)
            try ajust.posa(false)
            try m.accepta(ara: ara)
            try EscripturaAtomica.escriu(d, a: u)
            try d.write(to: u)
            FileManager.default.createFile(atPath: r, contents: d)
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            try FileManager.default.removeItem(at: u)
            try FileManager.default.moveItem(at: u, to: v)
            try FileManager.default.copyItem(at: u, to: v)
            try FileManager.default.replaceItem(at: u, withItemAt: v, backupItemName: nil, resultingItemURL: nil)
            Darwin.unlink(r)
            rename(r, s)
            Darwin.open(r, O_WRONLY)
            sqlite3_open(r, &db)
            FileHandle(forWritingTo: u)
            FileHandle(forUpdating: u)
            AjustRestauracio(ruta: u)
            try m.posaRestauracio(true, valor: v, posa: p)
            try m.recordaRestauracioOriginal(true)
            Process()
            NSPasteboard.general.clearContents()
            PortaRetallsSistema.copiaText(t)
            """)]
        #expect(try aparicions(de: escriuen, a: mostra).count == escriuen.count)
        #expect(try aparicions(de: escriuen, a: [(ruta: "mostra.swift", text: """
            try AjustRestauracio.analitza(text).valor
            try MagatzemPreferencies(carpeta: c).carrega()
            try LectorWarp(ruta: r).queFalta()
            """)]).isEmpty)
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
        let consentiment = [#"\.accepta\("#, #"\.acceptat\("#, #"\.migrat\b"#, #"\.restauracio\s*=(?!=)"#, #"\.retirat\("#]
        #expect(try aparicions(de: consentiment, a: [(ruta: "mostra.swift", text: """
            consentiment.accepta()
            public func accepta(ara: Date) {}
            guard estat == .acceptat else { return }
            p.restauracio = .acceptat(ara)
            Preferencies(restauracio: .migrat)
            if p.restauracio == .migrat {}
            Preferencies(restauracio: .retirat(ara))
            estat = .retirat
            """)]) == [
            "mostra.swift:1: «\\.accepta\\(»", "mostra.swift:4: «\\.acceptat\\(»", "mostra.swift:4: «\\.restauracio\\s*=(?!=)»",
            "mostra.swift:5: «\\.migrat\\b»", "mostra.swift:6: «\\.migrat\\b»", "mostra.swift:7: «\\.retirat\\(»",
        ])
        // D-P12: `troba` només amb una carpeta temporal.
        let troba = #"\bInstallacioWarp\.troba\((?!aplicacions: tmp\.)"#
        #expect(try aparicions(de: [troba, #"perOmissio\.app(?![A-Za-z0-9_])"#], a: [(ruta: "mostra.swift", text: """
            InstallacioWarp.troba(aplicacions: AppWarp.rutaPerDefecte, cerca: c)
            InstallacioWarp.troba(aplicacions: url, cerca: c)
            InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: c)
            InstallacioWarp.perOmissio.app.versio
            InstallacioWarp.perOmissio.executable
            """)]) == ["mostra.swift:1: «\(troba)»", "mostra.swift:2: «\(troba)»", "mostra.swift:4: «perOmissio\\.app(?![A-Za-z0-9_])»"])
        // Pla A4: els lectors de Claude i «Copia el diagnòstic».
        #expect(try aparicions(de: [lectorTranscripcions, lectorConfianca, copiaDiagnostic], a: [(ruta: "mostra.swift", text: """
            LectorTranscripcions()
            LectorTranscripcions(carpeta: tmp.url("p"))
            LectorConfianca()
            LectorConfianca(ruta: tmp.url("c"))
            CopiaDiagnostic(diagnostic: d)
            CopiaDiagnostic(diagnostic: d, escriu: { _ in })
            WarpLaunchCore.LectorTranscripcions()
            WarpLaunchCore.LectorConfianca()
            WarpLaunchUI.CopiaDiagnostic(diagnostic: d)
            """)]) == ["mostra.swift:1: «\(lectorTranscripcions)»", "mostra.swift:3: «\(lectorConfianca)»",
                       "mostra.swift:5: «\(copiaDiagnostic)»", "mostra.swift:7: «\(lectorTranscripcions)»",
                       "mostra.swift:8: «\(lectorConfianca)»", "mostra.swift:9: «\(copiaDiagnostic)»"])
        // Ni `MeuLectorConfianca(`, que és un altre nom.
        #expect(try aparicions(de: [lectorConfianca], a: [(ruta: "mostra.swift", text: "MeuLectorConfianca()")]).isEmpty)
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

    /// D-P4 (decisió d'en David del 07/11/2026): a la pantalla del permís, Retorn prem «Accepta», el botó per defecte, i
    /// Escapada no fa res: no accepta mai, ni fa sortir. És l'única drecera de la pantalla, i `elCodiNoObreResNiRegistraArrencades`
    /// ja comprova que `accepta()` només el crida aquest botó.
    @Test func elPermisSAcceptaAmbRetornINoAmbEscapada() throws {
        let codi = try fitxers("Sources")
        let vista = try #require(codi.first { $0.ruta == "Sources/WarpLaunchUI/VistaConsentiment.swift" })
        #expect(vista.text.contains(#"Button("Accepta") { consentiment.accepta() }"#
            + "\n                .keyboardShortcut(.defaultAction)\n"))
        let dreceres = vista.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("keyboardShortcut") && !$0.hasPrefix("//") }
        #expect(dreceres == [".keyboardShortcut(.defaultAction)"], "\(dreceres)")
        let escapada = try aparicions(de: [#"cancelAction"#, #"\.escape\b"#, #"onExitCommand"#, #"onKeyPress"#,
                                           #"cancelOperation"#, #"\\u\{1[bB]\}"#], a: [vista])
        #expect(escapada.isEmpty, "\(escapada)")
    }

    /// D-P4: tancar l'editor o la Configuració amb la pantalla del permís a la vista fa sortir de l'app, sense desar res (la
    /// Configuració, decisió d'en David del 08/11/2026). Tots dos ho pregunten al consentiment abans de fer res més.
    @Test func tancarLaPantallaDelPermisFaSortir() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        let guarda = "guard consentiment.continuaEnTancarFinestra(surt: { NSApp.terminate(nil) }) else { return }"
        for tancar in ["enTancarConfiguracio: {", "enAmagar: {"] {
            let inici = try #require(app.range(of: tancar), "\(tancar)")
            let primera = app[inici.upperBound...].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("//") }
            #expect(primera == guarda, "\(tancar) \(primera ?? "")")
        }
        #expect(app.components(separatedBy: "continuaEnTancarFinestra(").count == 3, "només aquestes dues")
    }

    /// A la pestanya «Pestanyes noves» de la Configuració, cap secció no repeteix el títol de la pestanya (decisió d'en David
    /// del 08/11/2026): només el porta la pestanya. El peu de la primera secció es queda.
    @Test func laPestanyaPestanyesNovesNoRepeteixElTitol() throws {
        let vista = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/VistaConfiguracio.swift"), encoding: .utf8)
        let titols = vista.split(separator: "\n").filter { $0.contains(#""Pestanyes noves""#) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(titols == [#"case .pestanyesNoves: "Pestanyes noves""#], "\(titols)")
        #expect(vista.contains(#"Text(editor.motiuPlantillaNoEditable ?? "S'aplica a les pestanyes noves i a les que s'importen sense ""#))
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
