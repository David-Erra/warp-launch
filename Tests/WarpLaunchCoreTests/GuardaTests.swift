import Foundation
import Testing
import WarpLaunchCore

// Prova de guarda (docs/disseny.md, «Prova de guarda»). Llegeix el codi del repo i falla si:
// - el codi pot obrir Warp, Claude o qualsevol altra cosa, o registrar una arrencada automàtica;
// - una prova pot llegir l'estat real (Warp, Claude, ~/.config/warp-launch) o fer sortir el procés al Dock.
// Aquest fitxer no es revisa a si mateix: hi surten totes les paraules prohibides. Només una prova el llegeix, per mirar
// que cap expressió no fa servir el límit de paraula (`capGuardaFaServirElLimitDeParaula`).

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

/// Cap expressió d'aquest fitxer no fa servir `\b` (`capGuardaFaServirElLimitDeParaula`): amb les expressions de Swift, `\b`
/// segueix les regles d'Unicode, i un punt o dos punts entre lletres no hi fan cap límit de paraula. `\bProcess\(` no veia
/// `Foundation.Process(`, `\bNSApp\b` no veia `NSApp.terminate(nil)`, i `\bregister\b` no veia `mainApp.register()`.
/// Davant d'un nom, `(^|[^A-Za-z0-9_])`; darrere, `(?![A-Za-z0-9_])`.
/// `Process` i `kill`, com a paraula, sense demanar el parèntesi: quan el demanaven, `Process.init()`,
/// `let p: Process = .init()` i `let k = kill` passaven. Cap línia de `Sources` no els esmenta, ni en un comentari.
private let paraulaProcess = #"(^|[^A-Za-z0-9_])Process(?![A-Za-z0-9_])"#
private let paraulaKill = #"(^|[^A-Za-z0-9_])kill(pg)?(?![A-Za-z0-9_])"#
/// Les altres maneres d'executar res que Swift deixa fer a macOS (`popen`, `system` i `fork` no hi són): la família `exec`,
/// que canviaria l'app per l'ordre, i les tasques d'usuari (`NSUserUnixTask`, `NSUserAppleScriptTask`…).
private let paraulaExec = #"(^|[^A-Za-z0-9_])exec(l|lp|le|v|vp|vP|ve)(?![A-Za-z0-9_])"#
private let tascaUsuari = #"NSUser[A-Za-z]*Task"#
/// D19 i D-P4: el refresc de l'ajust de Warp, el consentiment i l'ajust de debò, cadascun creat en un sol lloc
/// (`elCodiNoObreResNiRegistraArrencades`, `lAjustDeWarpNomesLEscriuLApp`).
private let refrescWarp = #"(^|[^A-Za-z0-9_])RefrescWarp\("#
private let consentimentRestauracio = #"(^|[^A-Za-z0-9_])ConsentimentRestauracio\("#
private let ajustRestauracio = #"(^|[^A-Za-z0-9_])AjustRestauracio\("#
/// Decisió A (0.31.2): sense `settings.toml`, l'ajust el crea, i només si Warp no l'ha creat mentrestant. Les crides que
/// posen un fitxer al seu lloc només si no n'hi ha cap, o que l'enllacen (també `linkItem` i `createSymbolicLink` de
/// `FileManager`), les que hi copien un altre fitxer o els seus atributs (`copyfile`, que crearia o sobreescriuria el
/// destí), i el que fa Warp a les proves (`ganxoDeProva`), només a `AjustRestauracio.swift`; `O_CREAT`, només on ja era
/// (`nomesLAjustCreaElFitxerDeWarp`).
private let rutaAjustRestauracio = "Sources/WarpLaunchCore/AjustRestauracio.swift"
private let creaOEnllaca = [#"renamex_np"#, #"renameatx_np"#, #"RENAME_(EXCL|SWAP)"#, #"(^|[^A-Za-z0-9_])(sym)?link(at)?\("#,
                            #"(^|[^A-Za-z0-9_])f?clonefile(at)?\("#, #"(^|[^A-Za-z0-9_])ganxoDeProva(?![A-Za-z0-9_])"#,
                            #"(^|[^A-Za-z0-9_])linkItem(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])createSymbolicLink(?![A-Za-z0-9_])"#,
                            #"(^|[^A-Za-z0-9_])f?copyfile(?![A-Za-z0-9_])"#]
private let ambOCreat = ["Sources/WarpLaunchCore/EscripturaAtomica.swift", "Sources/WarpLaunchCore/FitxersLaunchWarp.swift"]
/// A l'ajust, res que obri un fitxer per escriure-hi directament: el `settings.toml` de Warp quedaria a mitges si l'app
/// s'aturés a mig escriure, i Warp el podria llegir així. Ni `open(` de C (l'ajust llegeix amb `Data(contentsOf:)`), ni
/// `.write(`, ni un `FileHandle` per escriure, ni els modes d'escriure, ni `fopen`, `openat`, `creat(` o `truncate`
/// (`altresCreenOSobreescriuen`). Només hi escriu `EscripturaAtomica.creaFitxerNou`, a la carpeta temporal.
private let escriuenDirectament = [#"(^|[^A-Za-z0-9_])open\("#, #"\.write\("#, #"forWriting"#, #"forUpdating"#,
                                   #"O_(WRONLY|RDWR|APPEND)"#]
    + altresCreenOSobreescriuen[0...3]

/// Les línies que creen o enllacen un fitxer fora de l'ajust, i les d'`O_CREAT` fora d'on ja era.
private func creenForaDeLloc(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try aparicions(de: creaOEnllaca, a: codi.filter { $0.ruta != rutaAjustRestauracio })
        + aparicions(de: [#"O_CREAT"#], a: codi.filter { !ambOCreat.contains($0.ruta) })
}

/// L'estat del consentiment canvia, també amb `self.estat =`.
private let assignacioEstat = #"(^|[^A-Za-z0-9_])estat\s*=(?!=)"#
/// Donar o retirar el consentiment, o construir-ne un: només `MagatzemPreferencies`.
private let donenConsentiment = [#"\.acceptat\("#, #"\.migrat(?![A-Za-z0-9_])"#, #"\.restauracio\s*=(?!=)"#, #"\.retirat\("#]
/// D3: qualsevol aparició de la paraula `register`, també en un comentari.
private let paraulaRegister = #"(^|[^A-Za-z0-9_])register(?![A-Za-z0-9_])"#
/// A les proves, les lectures de Warp només amb rutes de prova, i res de l'app (`lesProvesNoLlegeixenLEstatReal`).
private let lectorProves = #"(^|[^A-Za-z0-9_])Lector\((?!rutaWarp:[^,]+,\s*rutaAjustos:)"#
private let lectorAjustosProves = #"(^|[^A-Za-z0-9_])LectorAjustosWarp\((?!ruta:)"#
private let lectorWarpProves = #"(^|[^A-Za-z0-9_])LectorWarp\((?!ruta:)"#
private let ajustRestauracioProves = #"(^|[^A-Za-z0-9_])AjustRestauracio\((?!ruta: b\.fitxer|ruta: tmp\.url)"#
private let trobaProves = #"(^|[^A-Za-z0-9_])InstallacioWarp\.troba\((?!aplicacions: tmp\.)"#
private let nsApp = #"(^|[^A-Za-z0-9_])NSApp(?![A-Za-z0-9_])"#
/// La carpeta d'inici de debò, de qualsevol manera: una prova que la fes servir podria arribar a `~/.claude` o a
/// `~/.config/warp-launch`. A les proves, `HOME` només es posa als processos fills, amb una carpeta temporal.
private let iniciDeDebo = [#"homeDirectoryForCurrentUser"#, #"NSHomeDirectory"#, #"\.homeDirectory(?![A-Za-z0-9_])"#,
                           #"expandingTildeInPath"#, #"getenv\("#, #"environment\["HOME"\]"#, #"getpw(uid|nam)"#]
/// Fase 3.1: el que `FitxersLaunchWarp` no pot fer amb la carpeta de Warp (`nomesFitxersLaunchWarpTocaLaCarpetaDeWarp`).
private let cridaUnlink = #"(^|[^A-Za-z0-9_])unlink\("#
private let cridaRename = #"(^|[^A-Za-z0-9_])rename\("#
private let cridaMkdir = #"(^|[^A-Za-z0-9_])mkdir\("#
/// Les altres maneres d'esborrar, moure o crear un fitxer o una carpeta, de C i de `FileManager` (revisió de la 0.31.2).
/// Com a paraula, sense demanar el parèntesi (`let f = rmdir` també hi surt), i amb tota la família (`renameatx_np`,
/// `removefileat`). `remove` de C també, sense un punt davant (`remove(ruta)`) o amb el mòdul (`Darwin.remove(`): un
/// mètode d'un valor (`llista.remove(at:)`) sempre en té un. Valen per a la carpeta de Warp (`prohibidesCarpetaWarp`) i per
/// al diagnòstic (`escriuen`), que només miren el seu fitxer: el `renamex_np` de l'ajust (`nomesLAjustCreaElFitxerDeWarp`)
/// no hi té res a veure.
private let altresEsborrenOMouen = [
    #"(^|[^A-Za-z0-9_])rmdir(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])unlinkat(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])renameat(x_np)?(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])renamex_np(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])mkdirat(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])trashItem(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])removefile(at)?(?![A-Za-z0-9_])"#,
    #"((^|[^A-Za-z0-9_.])|(^|[^A-Za-z0-9_])(Darwin|Foundation)\.)remove(?![A-Za-z0-9_])"#,
]
/// Les altres maneres de crear, sobreescriure o enllaçar un fitxer, de C i de `FileManager` (revisió de la 0.31.2): `fopen` i
/// `freopen`, `openat`, `creat(` (la variable `creat` de `FitxersLaunchWarp`, no), `truncate` i `ftruncate`, `copyfile` i
/// `fcopyfile`, `linkItem` i `createSymbolicLink`. Com `altresEsborrenOMouen`, per a la carpeta de Warp i el diagnòstic, que
/// només miren el seu fitxer: el `copyfile` de l'ajust no hi té res a veure.
private let altresCreenOSobreescriuen = [
    #"(^|[^A-Za-z0-9_])f(re)?open(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])openat(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])creat\("#,
    #"(^|[^A-Za-z0-9_])f?truncate(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])f?copyfile(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])linkItem(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])createSymbolicLink(?![A-Za-z0-9_])"#,
]
/// A `FitxersLaunchWarp`, a més de l'única crida que esborra (`cridaUnlink`), res que sobreescrigui, esborri, mogui o creï
/// carpetes: tampoc `createFile` (que sobreescriu el que hi ha), cap `.write(` (també `toFile:`), un `FileHandle` per
/// escriure, `O_RDWR` ni `O_APPEND`. I només les dues crides a `open` d'ara (`obrenAFitxersLaunchWarp`).
private let prohibidesCarpetaWarp = [#"removeItem"#, cridaRename, #"createDirectory"#, #"O_TRUNC"#, #"\.write\("#,
                                     cridaMkdir, #"replaceItem"#, #"moveItem"#, #"copyItem"#, #"createFile"#,
                                     #"forWriting"#, #"forUpdating"#, #"O_RDWR"#, #"O_APPEND"#]
    + altresEsborrenOMouen + altresCreenOSobreescriuen
/// Les dues crides a `open` de `FitxersLaunchWarp`: la que crea el fitxer, només si no n'hi ha cap (`O_EXCL`), i la que en
/// llegeix la marca. Una altra, també amb `O_WRONLY` sense `O_EXCL`, escriuria sobre un fitxer que ja hi és.
private let obrenAFitxersLaunchWarp = [
    "let fd = open(ruta, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))",
    "let fd = open(ruta, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)",
]
/// Les línies amb `open` com a paraula (també `Darwin.open(` i `let o = open`), sense els espais del principi.
private func obertures(_ text: String) throws -> [String] {
    let open = try Regex(#"(^|[^A-Za-z0-9_])open(?![A-Za-z0-9_])"#)
    return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains(open) }
}
/// D-P4: Escapada, a la pantalla del permís (`elPermisSAcceptaAmbRetornINoAmbEscapada`).
private let escapada = [#"cancelAction"#, #"\.escape(?![A-Za-z0-9_])"#, #"onExitCommand"#, #"onKeyPress"#, #"cancelOperation"#,
                        #"\\u\{1[bB]\}"#]

/// El codi no obre res ni tanca res (regles 1 a 4 de CLAUDE.md). De `NSWorkspace`, només «Mostra al Finder»
/// (`activateFileViewerSelecting`, a `Finder.swift`), que selecciona el fitxer en una finestra del Finder, i l'obridor
/// de la fase 3.1 (`ObreWarp`, vegeu `nomesLObridorObreWarp`). De les URL de Warp, només la de llançament (D5), i en un
/// sol lloc (`nomesHiHaLURLDeLlancament`).
private let workspace = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\))"#
private let prohibidesCodi = [
    #"warp://(?!launch/")"#, paraulaProcess,
    workspace, #"openURL"#,
    #"NSAppleScript"#, #"posix_spawn"#, #"(^|[^.\w])system\("#, paraulaExec, tascaUsuari,
    #"SMAppService"#, #"LaunchAgents"#, #"UserDefaults"#,
    #"@AppStorage"#,
    // Tancar o matar Warp o Claude (regla 2), o obrir apps. La paraula `openApplication` només pot ser a l'obridor, per
    // obrir Warp si és tancat (`nomesLObridorObreWarp`).
    #"NSRunningApplication"#, #"forceTerminate"#, #"launchApplication"#, paraulaKill,
]

private let serveiArrencada = "Sources/WarpLaunchApp/ServeiArrencada.swift"

/// D-P12 (excepcions limitades, 0.29.2): on és Warp només ho pregunta `TrobaWarp`, amb aquesta sola crida i l'identificador
/// que li passa `InstallacioWarp.troba` (`nomesTrobaWarpPreguntaOnEsWarp`). A la resta del codi, `workspace` la prohibeix.
private let trobaWarp = "Sources/WarpLaunchObridor/TrobaWarp.swift"
private let workspaceTrobaWarp = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\)|\.shared\.urlForApplication\(withBundleIdentifier: \$0\))"#
/// Decisió 4 (0.31.1): el Warp de macOS sense mirar quin corre (`Lector.installacio()`). Ningú no el fa servir.
private let senseInstallacio = #"lector\.warp(?![A-Za-z0-9_])"#

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

/// Pla A4: a les proves, els lectors de Claude només amb una ruta (també amb `.init(`), i «Copia el diagnòstic» només amb un
/// porta-retalls fals. Sense `\b`: amb les regles d'Unicode, `WarpLaunchCore.LectorConfianca(` no hi té cap límit de paraula.
/// Ni `.init()` sense arguments, de cap tipus: `transcripcions: .init()` en crearia un amb la ruta de debò sense dir-ne el nom.
private let lectorTranscripcions = #"(^|[^A-Za-z0-9_])LectorTranscripcions(\.init)?\((?!carpeta:)"#
private let lectorConfianca = #"(^|[^A-Za-z0-9_])LectorConfianca(\.init)?\((?!ruta:)"#
private let initSenseArguments = #"\.init\(\s*\)"#
private let copiaDiagnostic = #"(^|[^A-Za-z0-9_])CopiaDiagnostic\((?![^\n]*escriu:)"#

/// Pla A4: el diagnòstic només llegeix. Res que escrigui, esborri, mogui, creï carpetes (també `altresEsborrenOMouen` i
/// `altresCreenOSobreescriuen`), executi o toqui el porta-retalls. Sense `\b`: amb les regles d'Unicode, `default.moveItem`
/// o `Darwin.open` no hi tenen cap límit de paraula.
private let escriuen = [
    #"\.desa\("#, #"\.posa\("#, #"\.accepta\("#, #"EscripturaAtomica"#, #"\.write\("#, #"createFile"#,
    #"createDirectory"#, #"removeItem"#, #"(^|[^A-Za-z0-9_])moveItem"#, #"copyItem"#, #"replaceItem"#,
    #"(^|[^A-Za-z0-9_])unlink\("#, #"(^|[^A-Za-z0-9_])rename\("#, #"(^|[^A-Za-z0-9_])open\("#, #"sqlite3_open"#,
    #"forWriting"#, #"forUpdating"#, #"(^|[^A-Za-z0-9_])AjustRestauracio\("#, #"posaRestauracio"#,
    #"recordaRestauracioOriginal"#, paraulaProcess, #"NSPasteboard"#, #"copiaText"#, cridaMkdir,
] + altresEsborrenOMouen + altresCreenOSobreescriuen

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

/// Les sessions de Claude (`~/.claude/sessions`) i els processos de debò. Cap paràmetre no els té per defecte (`Lector`,
/// `LectorSessions`): una prova que se'ls oblidés els llegiria, i cap guarda de línia no ho veuria, perquè el valor per
/// defecte no surt a la crida i els arguments poden ocupar diverses línies. Les línies de `Sources` que els esmenten, fora
/// dels comentaris. De les carpetes, qualsevol `carpetaPerDefecte` (també la de les transcripcions): amb
/// `Self.carpetaPerDefecte`, una extensió de `LectorSessions` en un altre fitxer en podria tornar a fer un valor per defecte.
private let rutaLectorSessions = "Sources/WarpLaunchCore/LectorSessions.swift"
private func sessionsIProcessosDeDebo(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    let rutaEscrita = try Regex(#""[^"]*\.claude/sessions"#)
    return codi.flatMap { f in
        f.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
            .filter { $0.contains("carpetaPerDefecte") || $0.contains("ProcessosDelSistema") || $0.contains(rutaEscrita) }
            .map { "\(f.ruta): \($0)" }
    }
}

/// Els lectors de Claude de debò: `LectorTranscripcions()` llegeix `~/.claude/projects`, i `LectorConfianca()`,
/// `~/.claude.json` (cada `init` en té la ruta per defecte). Com amb les sessions (`sessionsIProcessosDeDebo`), un paràmetre
/// que en tingués un per defecte els faria llegir a una prova, i cap guarda de línia no ho veuria. Les línies de `Sources`,
/// fora dels comentaris, que en creen un (també amb `.init`, `.self` o el mòdul), que donen un valor a una variable o a un
/// paràmetre del tipus (`LectorConfianca = .init()`, també amb el valor a la línia següent), o que en fan un àlies o una
/// extensió; i, als seus fitxers, `Self(` i `.init(`, que en crearien un amb un altre nom (`.deDebo`).
/// Sense dir-ne el nom, també: `.init()` sense arguments, de qualsevol tipus i a qualsevol fitxer (`transcripcions: .init()`
/// en una crida, o `type(of: t).init()`, en crearien un amb la ruta per defecte de l'`init`), i les rutes per defecte
/// (`.init(ruta: LectorConfianca.rutaPerDefecte)`; als seus fitxers, `rutaPerDefecte` i `carpetaPerDefecte` soles).
private let rutesLectorsClaude = [
    "Sources/WarpLaunchCore/LectorConfianca.swift", "Sources/WarpLaunchCore/LectorTranscripcions.swift",
]
private func lectorsDeClaudeDeDebo(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    let nom = #"Lector(Transcripcions|Confianca)"#
    let crea = try Regex(#"(^|[^A-Za-z0-9_])"# + nom
        + #"(\(|\.(init|self|carpetaPerDefecte|rutaPerDefecte)(?![A-Za-z0-9_])|\??\s*=(?!=))"#)
    let initSenseArguments = try Regex(#"\.init\(\s*\)"#)
    let aliesOExtensio = try Regex(#"(^|[^A-Za-z0-9_])(typealias|extension)(?![A-Za-z0-9_]).*[^A-Za-z0-9_]"# + nom
        + #"(?![A-Za-z0-9_])"#)
    let creaSelf = try Regex(#"(^|[^A-Za-z0-9_])(Self(\(|\.init(?![A-Za-z0-9_]))|\.init\(|(carpeta|ruta)PerDefecte(?![A-Za-z0-9_]))"#)
    return codi.flatMap { f in
        let linies = f.text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return linies.indices.compactMap { i -> String? in
            guard !linies[i].hasPrefix("//") else { return nil }
            // `transcripcions: LectorTranscripcions` i, a la línia següent, `= .init()`.
            let linia = i + 1 < linies.count && linies[i + 1].hasPrefix("=") ? linies[i] + " " + linies[i + 1] : linies[i]
            guard linia.contains(crea) || linia.contains(initSenseArguments) || linia.contains(aliesOExtensio)
                || (rutesLectorsClaude.contains(f.ruta) && linia.contains(creaSelf)) else { return nil }
            return "\(f.ruta): \(linia)"
        }
    }
}

/// El que s'arrossega no surt de l'app: ni fitxers, ni text, ni `ShareLink`.
private let onDrag = #"\.onDrag(?![A-Za-z0-9_])"#
private let prohibidesArrossegar = [
    #"ShareLink"#, #"ProxyRepresentation"#, #"FileRepresentation"#, #"CodableRepresentation"#, onDrag,
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
        let refrescos = try aparicions(de: [refrescWarp], a: codi)
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
        for unic in [consentimentRestauracio, #"RefrescWarp\.Entorn\("#, #"^\s*creaEntornRefresc = "#] {
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
        // L'estat del consentiment només canvia en aquestes línies (també amb `self.estat =`).
        let assignacio = try Regex(assignacioEstat)
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
        let consentiments = try aparicions(de: donenConsentiment, a: codi)
        #expect(!consentiments.isEmpty && consentiments.allSatisfy { $0.hasPrefix("\(preferencies):") }, "\(consentiments)")
        #expect(consentiments.contains { $0.hasSuffix("«\\.retirat\\(»") }, "\(consentiments)")
    }

    /// D-P12 (0.29.2): on és Warp només ho pregunta `TrobaWarp`, amb una sola crida, i només per als dos identificadors de
    /// Warp (`InstallacioWarp.troba`). Només el fan servir l'app i el CLI, al seu lector, cap prova. Decisió 4 (0.31.1): el
    /// Warp que compta és el del lector, que també mira quin corre (`Lector.installacio()`), i l'obridor no en té cap altre.
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
            "Sources/WarpLaunchApp/WarpLaunchApp.swift", "Sources/WarpLaunchCLI/main.swift",
        ])
        // L'app i el CLI llegeixen Warp on és de debò: el lector de cadascun en porta la crida.
        #expect(linies("Lector(carpetaSessions:").sorted() == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: let lector = Lector(carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
            "Sources/WarpLaunchCLI/main.swift: let lector = Lector(carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema)",
        ])
        // Decisió 4 (0.31.1): l'app i el CLI obren al Warp del lector (el que corre, si n'hi ha un), i la versió del full
        // és la d'aquell. L'obridor no té cap Warp per defecte, i ningú no se salta el lector amb `lector.warp`.
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        #expect(linies("ObreWarp.obre(").sorted() == [
            "\(app): obre: { try await ObreWarp.obre($0, warp: lector.installacio()) },",
            "\(cli): let obridor = ObridorCLI(obre: { try await ObreWarp.obre($0, warp: lector.installacio()) },",
        ])
        #expect(linies("ObreWarp.engega(").sorted() == [
            "\(app): engegaWarp: { await consentiment.refresc?.tancaEsperant(); try await ObreWarp.engega(warp: lector.installacio()) },",
            "\(cli): engega: { try await ObreWarp.engega(warp: lector.installacio()) },",
        ])
        #expect(linies("versioWarp: {") == ["\(app): versioWarp: { lector.installacio().app.versio },"])
        let obridor = try #require(codi.first { $0.ruta == "Sources/WarpLaunchObridor/ObreWarp.swift" }).text
        #expect(obridor.contains("warp: InstallacioWarp) async throws(ErrorObrir) {")
                && !obridor.contains("warp: InstallacioWarp ="))
        #expect(try aparicions(de: [senseInstallacio], a: codi).isEmpty)
        // El Warp que corre només el mira el lector: `ambLaCopiaOberta` només es crida a `Lector.installacio()`.
        #expect(linies("ambLaCopiaOberta(").filter { !$0.contains(": //") }.sorted() == [
            "Sources/WarpLaunchCore/AppWarp.swift: public func ambLaCopiaOberta(_ processos: any FontProcessos) -> InstallacioWarp {",
            "Sources/WarpLaunchCore/Lector.swift: public func installacio() -> InstallacioWarp { warp().ambLaCopiaOberta(processos) }",
        ])
    }

    /// Decisió 4 (0.31.1): l'`Info.plist` del paquet d'un Warp que corre només el llegeix `FontProcessos.warpDelBinari`. Al
    /// codi, el de `ProcessosDelSistema`; a les proves, el de `ProcessosFalsos`, que només el mira dins de les carpetes
    /// temporals. Una crida a `AppWarp.delBinari` en qualsevol altre lloc (fora dels comentaris) fa fallar la llista.
    @Test func elPaquetDelWarpQueCorreNomesElLlegeixLaFontDeProcessos() throws {
        func linies(_ codi: [(ruta: String, text: String)]) -> [String] {
            codi.flatMap { f in
                f.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.contains("delBinari(") && !$0.hasPrefix("//") }.map { "\(f.ruta): \($0)" }
            }
        }
        #expect(linies(try fitxers("Sources")).sorted() == [
            "Sources/WarpLaunchCore/AppWarp.swift: static func delBinari(_ ruta: String) -> AppWarp? {",
            "Sources/WarpLaunchCore/Processos.swift: public func warpDelBinari(_ ruta: String) -> AppWarp? { AppWarp.delBinari(ruta) }",
        ])
        #expect(linies(try fitxers("Tests")) == [
            "Tests/WarpLaunchCoreTests/Fixtures.swift: ruta.hasPrefix(CarpetaTemporal.prefix) ? AppWarp.delBinari(ruta) : nil",
        ])
        // La mostra: una crida directa, també amb el mòdul, surt; un comentari, no.
        #expect(linies([(ruta: "mostra.swift", text: """
            let a = AppWarp.delBinari(info.executable)
            let b = WarpLaunchCore.AppWarp.delBinari(r)
            /// `AppWarp.delBinari(_:)`
            let c = processos.warpDelBinari(r)
            """)]) == ["mostra.swift: let a = AppWarp.delBinari(info.executable)",
                       "mostra.swift: let b = WarpLaunchCore.AppWarp.delBinari(r)"])
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

    /// Sense cap Warp ni la seva base, l'app diu que no hi ha Warp també amb una carpeta de prova i en refrescar la foto, com
    /// amb la configuració de debò: les dues lectures de l'app són `llegeixDeLApp`, i cap no és `llegeix(`, que fallaria amb
    /// «no trobo la base de Warp».
    @Test func lAppLlegeixWarpAmbLaLecturaDeLApp() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        #expect(app.contains("let warp = EstatWarp(lector: { try lector.llegeixDeLApp(base: base) })"))
        #expect(app.contains("llegeixBase: { try lector.llegeixDeLApp(base: .sempre) })"))
        #expect(app.components(separatedBy: "lector.llegeix").count == 3, "només aquelles dues")
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
        // Amb `\b`, `mainApp.register()` no hi sortia, i la llista buida ho donava per bo: n'hi ha d'haver exactament una.
        #expect(try aparicions(de: [paraulaRegister], a: codi) == ["\(serveiArrencada):18: «\(paraulaRegister)»"])
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

        // L'ajust: un refresc l'activa i el desactiva; només la retirada el posa al valor que li donen, després d'aturar-se. Si
        // `settings.toml` acaba de canviar, cap no hi escriu res (0.31.3); sense el fitxer i amb Warp tancat, tampoc (ronda 5).
        #expect(try linies(rutaRefresc, #"entorn\.posa\("#) == [
            "switch try entorn.posa(valor) {",
            "guard try entorn.posa(true) != .mesTard else {",
            "switch try entorn.posa(false) {",
        ])
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

    /// Les sessions de Claude i els processos de debò només els posen l'app i el CLI, al seu lector, i cap paràmetre no els té
    /// per defecte (`sessionsIProcessosDeDebo`). Una prova no pot crear un `Lector` ni un `LectorSessions` sense dir-los.
    @Test func lesSessionsIElsProcessosDeDeboNomesDeLAppIDelCLI() throws {
        let codi = try fitxers("Sources")
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        let deDebo = try sessionsIProcessosDeDebo(codi)
        #expect(deDebo.sorted() == [
            "\(app): let lector = Lector(carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
            "\(app): let processos = ProcessosDelSistema()",
            "\(cli): let lector = Lector(carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema)",
            "\(cli): let processos = ProcessosDelSistema()",
            "\(rutaLectorSessions): .appending(path: \".claude/sessions\")",
            "\(rutaLectorSessions): public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "Sources/WarpLaunchCore/LectorTranscripcions.swift: public init(carpeta: URL = LectorTranscripcions.carpetaPerDefecte) {",
            "Sources/WarpLaunchCore/LectorTranscripcions.swift: public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "Sources/WarpLaunchCore/Processos.swift: public struct ProcessosDelSistema: FontProcessos {",
        ], "\(deDebo.joined(separator: "\n"))")
        func text(_ ruta: String) throws -> String { try #require(codi.first { $0.ruta == ruta }).text }
        #expect(try text("Sources/WarpLaunchCore/Lector.swift").contains("\n                carpetaSessions: URL,\n"))
        #expect(try text(rutaLectorSessions).contains("\n    public init(carpeta: URL, processos: any FontProcessos) {\n"))
        // La mostra: un valor per defecte, també amb la ruta escrita, dins de `LectorSessions` o en una extensió seva d'un
        // altre fitxer, surt; un comentari, no.
        #expect(try sessionsIProcessosDeDebo([
            (ruta: "Sources/WarpLaunchCore/Lector.swift", text: """
                carpetaSessions: URL = LectorSessions.carpetaPerDefecte,
                processos: any FontProcessos = ProcessosDelSistema(),
                carpetaSessions: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions"),
                carpetaSessions: URL,
                /// `LectorSessions.carpetaPerDefecte` i `ProcessosDelSistema`
                """),
            (ruta: rutaLectorSessions, text: "public init(carpeta: URL = carpetaPerDefecte, processos: any FontProcessos) {"),
            (ruta: "Sources/WarpLaunchCore/OrdreCLI.swift", text: "    Només llegeix Warp, ~/.claude/sessions i ~/.claude/projects."),
            (ruta: "Sources/WarpLaunchCore/Diagnostic.swift", text: """
                extension LectorSessions {
                    init(processos: any FontProcessos) { self.init(carpeta: Self.carpetaPerDefecte, processos: processos) }
                }
                """),
        ]) == [
            "Sources/WarpLaunchCore/Lector.swift: carpetaSessions: URL = LectorSessions.carpetaPerDefecte,",
            "Sources/WarpLaunchCore/Lector.swift: processos: any FontProcessos = ProcessosDelSistema(),",
            "Sources/WarpLaunchCore/Lector.swift: carpetaSessions: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".claude/sessions\"),",
            "\(rutaLectorSessions): public init(carpeta: URL = carpetaPerDefecte, processos: any FontProcessos) {",
            "Sources/WarpLaunchCore/Diagnostic.swift: init(processos: any FontProcessos) { self.init(carpeta: Self.carpetaPerDefecte, processos: processos) }",
        ])
    }

    /// Els lectors de Claude de debò (`~/.claude/projects` i `~/.claude.json`) només els creen l'app i el CLI, i cap paràmetre
    /// ni cap variable del codi no en té un per defecte (`lectorsDeClaudeDeDebo`). Una línia nova que en creï un, a qualsevol
    /// fitxer, fa fallar la llista.
    @Test func elsLectorsDeClaudeDeDeboNomesDeLAppIDelCLI() throws {
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        let deDebo = try lectorsDeClaudeDeDebo(try fitxers("Sources"))
        #expect(deDebo.sorted() == [
            "\(app): confianca: LectorConfianca(),",
            "\(app): let transcripcions = LectorTranscripcions()",
            "\(app): transcripcions: LectorTranscripcions(),",
            "\(app): transcripcions: LectorTranscripcions(), confianca: LectorConfianca())",
            "\(cli): transcripcions: LectorTranscripcions(), confianca: LectorConfianca())",
            "\(rutesLectorsClaude[0]): public init(ruta: URL = LectorConfianca.rutaPerDefecte) {",
            "\(rutesLectorsClaude[0]): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".claude.json\")",
            "\(rutesLectorsClaude[1]): public init(carpeta: URL = LectorTranscripcions.carpetaPerDefecte) {",
            "\(rutesLectorsClaude[1]): public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
        ], "\(deDebo.joined(separator: "\n"))")
        // La mostra: crear-ne un, també amb el mòdul, `.init` o `.self`; un valor per defecte, també a la línia següent o amb
        // un altre nom; un àlies o una extensió; sense dir-ne el nom, amb `.init()` o amb la ruta per defecte, a qualsevol
        // fitxer; i, als seus fitxers, `Self(`, `.init(` i les rutes per defecte. Un comentari, el tipus d'un paràmetre sense
        // valor, els seus tipus i constants, un altre nom, `.init(` amb una ruta, la ruta d'un altre tipus i `Self(` en un
        // altre fitxer, no.
        let diagnostic = "Sources/WarpLaunchCore/Diagnostic.swift"
        let obertura = "Sources/WarpLaunchUI/Obertura.swift"
        #expect(try lectorsDeClaudeDeDebo([
            (ruta: diagnostic, text: """
                transcripcions: LectorTranscripcions = .init(), confianca: LectorConfianca, usuari: String? = nil,
                confianca: LectorConfianca? = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte),
                let t = WarpLaunchCore.LectorTranscripcions.init(carpeta: c)
                let tipus = LectorConfianca.self
                confianca: LectorConfianca
                    = .deDebo,
                public typealias Transcripcions = WarpLaunchCore.LectorTranscripcions
                extension LectorConfianca {
                /// `LectorTranscripcions()`
                // let c = LectorConfianca()
                public var transcripcions: LectorTranscripcions
                transcripcions: LectorTranscripcions, confianca: LectorConfianca,
                let r = LectorTranscripcions.Recent(id: i, darrerMissatge: d)
                guard let p = json[LectorConfianca.clauProjectes] else { return nil }
                let m = MeuLectorConfianca()
                if a == b {}
                return Self(lector: l)
                """),
            (ruta: obertura, text: """
                let entorn = Entorn(lector: l, transcripcions: .init(), confianca: .init( ))
                let altre = type(of: transcripcions).init()
                confianca: .init(ruta: LectorConfianca.rutaPerDefecte),
                transcripcions: .init(carpeta: WarpLaunchCore.LectorTranscripcions.carpetaPerDefecte)
                let t = LectorTranscripcions
                    .init()
                transcripcions: .init(carpeta: carpeta), confianca: .init(ruta: ruta),
                let warp = LectorWarp(ruta: LectorWarp.rutaPerDefecte)
                let carpetaPerDefecte = c
                """),
            (ruta: rutesLectorsClaude[0], text: """
                static let deDebo = Self()
                static var real: LectorConfianca { .init() }
                static let altra = Self.init(ruta: r)
                return Confianca(confiades: Set(confiades), inici: Rutes.canonica(inici))
                public init(ruta: URL = LectorConfianca.rutaPerDefecte) {
                let r = Self.rutaPerDefecte
                """),
            (ruta: rutesLectorsClaude[1], text: "public static let deDebo = Self(carpeta: Self.carpetaPerDefecte)"),
        ]) == [
            "\(diagnostic): transcripcions: LectorTranscripcions = .init(), confianca: LectorConfianca, usuari: String? = nil,",
            "\(diagnostic): confianca: LectorConfianca? = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte),",
            "\(diagnostic): let t = WarpLaunchCore.LectorTranscripcions.init(carpeta: c)",
            "\(diagnostic): let tipus = LectorConfianca.self",
            "\(diagnostic): confianca: LectorConfianca = .deDebo,",
            "\(diagnostic): public typealias Transcripcions = WarpLaunchCore.LectorTranscripcions",
            "\(diagnostic): extension LectorConfianca {",
            "\(obertura): let entorn = Entorn(lector: l, transcripcions: .init(), confianca: .init( ))",
            "\(obertura): let altre = type(of: transcripcions).init()",
            "\(obertura): confianca: .init(ruta: LectorConfianca.rutaPerDefecte),",
            "\(obertura): transcripcions: .init(carpeta: WarpLaunchCore.LectorTranscripcions.carpetaPerDefecte)",
            "\(obertura): .init()",
            "\(rutesLectorsClaude[0]): static let deDebo = Self()",
            "\(rutesLectorsClaude[0]): static var real: LectorConfianca { .init() }",
            "\(rutesLectorsClaude[0]): static let altra = Self.init(ruta: r)",
            "\(rutesLectorsClaude[0]): public init(ruta: URL = LectorConfianca.rutaPerDefecte) {",
            "\(rutesLectorsClaude[0]): let r = Self.rutaPerDefecte",
            "\(rutesLectorsClaude[1]): public static let deDebo = Self(carpeta: Self.carpetaPerDefecte)",
        ])
    }

    /// D19 i regla 7: l'ajust de debò només l'escriu l'app, i només amb la carpeta `.real`. `AjustRestauracio` només es pot
    /// crear a l'app: ni el CLI ni el core poden fer-ho, amb cap ruta.
    @Test func lAjustDeWarpNomesLEscriuLApp() throws {
        let codi = try fitxers("Sources").filter { $0.ruta != "Sources/WarpLaunchCore/AjustRestauracio.swift" }
        let trobades = try aparicions(de: [ajustRestauracio], a: codi)
        #expect(trobades.count == 1 && trobades[0].hasPrefix("Sources/WarpLaunchApp/WarpLaunchApp.swift"), "\(trobades)")
        let app = try fitxers("Sources/WarpLaunchApp").map(\.text).joined()
        // D-P4: dins de l'entorn que `ConsentimentRestauracio` només demana amb el consentiment acceptat
        // (`elCodiNoObreResNiRegistraArrencades`).
        #expect(app.contains("if case .real = arguments.carpeta, let preferencies {\n            creaEntornRefresc = {\n"
            + "                // Sense `settings.toml`, només el crea amb Warp obert des de fa mig minut (ronda 5).\n"
            + "                let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, warpObertDes: { lector.warpObertDes() })\n"))
    }

    /// Decisió A (0.31.2): `settings.toml` de Warp, si no hi és, només el crea `AjustRestauracio`, d'un sol cop i només si
    /// Warp no l'ha creat mentrestant (`renamex_np` amb `RENAME_EXCL`), des d'un fitxer de la carpeta temporal
    /// (`EscripturaAtomica.creaFitxerNou`). No crea la carpeta de Warp, ni obre res per escriure-hi directament, i l'únic
    /// `copyfile` hi copia els atributs estesos de l'original, no al revés. Cap altre fitxer no fa servir aquestes crides, ni
    /// `O_CREAT` fora d'on ja era, i la ruta de debò només la tenen el lector i l'app.
    @Test func nomesLAjustCreaElFitxerDeWarp() throws {
        let codi = try fitxers("Sources")
        let trobades = try creenForaDeLloc(codi)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        let ajust = try #require(codi.first { $0.ruta == rutaAjustRestauracio })
        let crides = try aparicions(de: [#"renamex_np"#], a: [ajust])
        #expect(crides.count == 1, "\(crides)")
        #expect(ajust.text.contains("guard renamex_np(temporal.path, ruta.path, UInt32(RENAME_EXCL)) == 0 else {"))
        let copies = try aparicions(de: [creaOEnllaca[8]], a: [ajust])
        #expect(copies.count == 1, "\(copies)")
        #expect(ajust.text.contains("copyfile(ruta.path, temporal.path, nil, copyfile_flags_t(COPYFILE_XATTR))"))
        #expect(try aparicions(de: [#"renameatx_np"#, #"RENAME_SWAP"#, creaOEnllaca[3], creaOEnllaca[4], creaOEnllaca[6],
                                    creaOEnllaca[7], cridaMkdir, #"mkdirat"#,
                                    #"createDirectory"#, #"O_CREAT"#, #"O_TRUNC"#, #"createFile"#,
                                    #"(^|[^A-Za-z0-9_])moveItem"#, #"copyItem"#, #"replaceItem"#] + escriuenDirectament,
                               a: [ajust]).isEmpty)
        // Cada línia, la seva expressió de `escriuenDirectament`; la crida que prepara el fitxer nou, cap.
        #expect(try aparicions(de: escriuenDirectament, a: [(ruta: rutaAjustRestauracio, text: """
            let fd = open(ruta.path, banderes)
            try resultat.write(to: ruta)
            let h = try FileHandle(forWritingTo: ruta)
            let h = try FileHandle(forUpdating: ruta)
            let banderes = O_WRONLY | O_APPEND
            let f = fopen(ruta.path, "r+")
            let fd = Darwin.openat(AT_FDCWD, ruta.path, banderes)
            let fd = creat(ruta.path, 0o644)
            truncate(ruta.path, 0)
            try EscripturaAtomica.creaFitxerNou(resultat, a: temporal, permisos: permisos)
            """)]) == escriuenDirectament.enumerated().map { "\(rutaAjustRestauracio):\($0.offset + 1): «\($0.element)»" })
        #expect(ajust.text.contains("try EscripturaAtomica.creaFitxerNou(resultat, a: temporal, permisos: permisos)"))

        // La ruta de debò de `settings.toml`: per llegir-la, el lector; per a l'ajust, l'app (`lAjustDeWarpNomesLEscriuLApp`).
        let deDebo = codi.flatMap { f in
            f.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") }
                .filter { $0.contains("LectorAjustosWarp.rutaPerDefecte") || $0.contains(".warp/settings")
                    || (f.ruta.hasSuffix("/LectorAjustosWarp.swift") && $0.contains("rutaPerDefecte")) }
                .map { "\(f.ruta): \($0)" }
        }
        #expect(deDebo.sorted() == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, warpObertDes: { lector.warpObertDes() })",
            "Sources/WarpLaunchCore/Lector.swift: rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,",
            "Sources/WarpLaunchCore/LectorAjustosWarp.swift: public init(ruta: URL = LectorAjustosWarp.rutaPerDefecte) {",
            "Sources/WarpLaunchCore/LectorAjustosWarp.swift: public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".warp/settings.toml\")",
            "Sources/WarpLaunchCore/OrdreCLI.swift: també l'esquema de warp.sqlite, l'Info.plist de Warp, ~/.warp/settings.toml i preferencies.json. No obre ni tanca res,",
        ], "\(deDebo.joined(separator: "\n"))")

        // La mostra: cada línia, a qualsevol altre fitxer (també els que ja creen fitxers), falla; a l'ajust, no. Amb el
        // mòdul davant, també.
        let mostra = [
            "guard renamex_np(temporal.path, ruta.path, UInt32(RENAME_EXCL)) == 0 else {",
            "Darwin.renameatx_np(AT_FDCWD, a, AT_FDCWD, b, UInt32(RENAME_SWAP))",
            "link(a, b)",
            "Darwin.symlink(a, b)",
            "linkat(AT_FDCWD, a, AT_FDCWD, b, 0)",
            "clonefile(a, b, 0)",
            "ajust.ganxoDeProva = { }",
            "try FileManager.default.linkItem(at: a, to: b)",
            "try FileManager.default.createSymbolicLink(atPath: a, withDestinationPath: b)",
            "copyfile(ruta.path, temporal.path, nil, copyfile_flags_t(COPYFILE_XATTR))",
            "_ = Darwin.fcopyfile(x, y, nil, copyfile_flags_t(COPYFILE_ALL))",
        ]
        let altres = ambOCreat + ["Sources/WarpLaunchCore/Diagnostic.swift", "Sources/WarpLaunchCore/LectorAjustosWarp.swift",
                                  "Sources/WarpLaunchUI/RefrescWarp.swift", rutaAppPrincipal, "Sources/WarpLaunchCLI/main.swift",
                                  "Sources/WarpLaunchCore/Altre.swift"]
        for linia in mostra {
            for ruta in altres {
                #expect(try !creenForaDeLloc([(ruta: ruta, text: linia)]).isEmpty, "\(ruta): \(linia)")
            }
            #expect(try creenForaDeLloc([(ruta: rutaAjustRestauracio, text: linia)]).isEmpty, "\(linia)")
        }
        // `O_CREAT`: on ja era, sí; a l'ajust i a qualsevol altre, no.
        let obre = "let fd = open(ruta, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o644))"
        for ruta in ambOCreat { #expect(try creenForaDeLloc([(ruta: ruta, text: obre)]).isEmpty) }
        for ruta in [rutaAjustRestauracio] + altres.filter({ !ambOCreat.contains($0) }) {
            #expect(try creenForaDeLloc([(ruta: ruta, text: obre)]) == ["\(ruta):1: «O_CREAT»"])
        }
        // Un nom que només s'hi assembla, no.
        #expect(try creenForaDeLloc([(ruta: "Sources/WarpLaunchCore/Altre.swift", text: """
            let enllac = unlinkat
            hyperlink(a)
            let deeplink = 1
            let estat = copyfile_state_alloc()
            let linkItems = 0
            """)]).isEmpty)
    }

    @Test func lesProvesNoLlegeixenLEstatReal() throws {
        let proves = try fitxers("Tests")
        #expect(proves.count > 5, "no s'han trobat les proves a \(arrel.path)")
        let prohibides = [
            // `Lector(` només amb les rutes de prova: `Lector()`, `Lector(inici:)` o sense `rutaAjustos` llegirien Warp i
            // Claude de debò; `LectorWarp()`, la base de Warp. Les sessions i els processos no tenen valor per defecte
            // (`lesSessionsIElsProcessosDeDeboNomesDeLAppIDelCLI`).
            lectorProves, lectorAjustosProves, lectorWarpProves, ajustRestauracioProves, #"ProcessosDelSistema"#,
            #"rutaPerDefecte"#, #"carpetaPerDefecte"#,
            #"\.config/warp-launch"#, nsApp, #"NSApplication"#, #"NSWindow"#, #"NSHostingView"#,
            // El porta-retalls d'en David: una prova el buidaria, o hi deixaria pestanyes fictícies.
            #"NSPasteboard"#, #"PortaRetallsSistema\.(enganxa|hiHaPestanyes|escriu)"#,
            // Fase 3.1: res que obri Warp, ni les carpetes de debò de Warp i de Claude.
            #"NSWorkspace"#, #"openURL"#, #"ObreWarp"#, #"FitxersLaunchWarp\.real"#, #"\.warp/"#, #"launch_configurations"#,
            #"\.claude\.json"#, #"\.claude/projects"#,
            // D-P12: on és Warp de debò. `troba` només amb una carpeta temporal; la instal·lació per omissió no es llegeix.
            #"TrobaWarp"#, #"urlForApplication"#, trobaProves, #"perOmissio\.app(?![A-Za-z0-9_])"#,
            // Pla A4 (diagnòstic): els lectors de Claude, sempre amb una ruta de prova (sense, llegirien ~/.claude; ni amb
            // `.init()`, que no en diu el nom), i «Copia el diagnòstic», sempre amb un porta-retalls fals (a la mateixa línia).
            lectorTranscripcions, lectorConfianca, initSenseArguments, copiaDiagnostic,
        ] + iniciDeDebo
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
        // Cada expressió troba la seva línia, i només aquella.
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
            Darwin.mkdir(r, 0o755)
            rmdir(r)
            Darwin.unlinkat(AT_FDCWD, r, 0)
            renameat(AT_FDCWD, r, AT_FDCWD, s)
            renamex_np(r, s, UInt32(RENAME_EXCL))
            Darwin.mkdirat(AT_FDCWD, r, 0o755)
            try FileManager.default.trashItem(at: u, resultingItemURL: nil)
            removefile(r, nil, removefile_flags_t(REMOVEFILE_RECURSIVE))
            remove(r)
            let f = fopen(r, "w")
            let fd = Darwin.openat(AT_FDCWD, r, O_WRONLY)
            let fd = creat(r, 0o644)
            ftruncate(fd, 0)
            copyfile(a, b, nil, copyfile_flags_t(COPYFILE_ALL))
            try FileManager.default.linkItem(at: u, to: v)
            try FileManager.default.createSymbolicLink(at: u, withDestinationURL: v)
            """)]
        #expect(mostra[0].text.split(separator: "\n").count == escriuen.count, "una línia per expressió")
        #expect(try aparicions(de: escriuen, a: mostra)
            == escriuen.enumerated().map { "mostra.swift:\($0.offset + 1): «\($0.element)»" })
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
        // Si una expressió estigués mal escrita, la guarda no trobaria mai res. Els noms, també amb el mòdul davant.
        let mostra = [(ruta: "mostra.swift", text: """
            let p = Process()
            system("ls")
            let f = Font.system(size: 13)
            Lector().llegeix()
            Lector(rutaWarp: url)
            Lector(inici: inici)
            PortaRetallsSistema.escriu(dades)
            let q = Foundation.Process()
            WarpLaunchCore.Lector().llegeix()
            let m = MeuProcess()
            MeuLector()
            """)]
        #expect(try aparicions(de: [paraulaProcess, #"(^|[^.\w])system\("#, lectorProves], a: mostra) == [
            "mostra.swift:1: «\(paraulaProcess)»", "mostra.swift:2: «(^|[^.\\w])system\\(»",
            "mostra.swift:4: «\(lectorProves)»", "mostra.swift:5: «\(lectorProves)»", "mostra.swift:6: «\(lectorProves)»",
            "mostra.swift:8: «\(paraulaProcess)»", "mostra.swift:9: «\(lectorProves)»",
        ])
        #expect(try aparicions(de: [lectorProves], a: [(ruta: "mostra.swift", text: "Lector(rutaWarp: url, rutaAjustos: altra)")]).isEmpty)
        // El refresc de l'ajust (D-P4): crear-lo sí; el seu entorn, no.
        #expect(try aparicions(de: [refrescWarp], a: [(ruta: "mostra.swift", text: """
            let r = RefrescWarp(entorn: e)
            let e = RefrescWarp.Entorn(ajust: a)
            let x = AltreRefrescWarp(entorn: e)
            let m = WarpLaunchUI.RefrescWarp(entorn: e)
            """)]) == ["mostra.swift:1: «\(refrescWarp)»", "mostra.swift:4: «\(refrescWarp)»"])
        // El consentiment i l'ajust de debò, crear-los; l'estat del consentiment, canviar-lo (també amb `self.`), i no
        // comparar-lo.
        #expect(try aparicions(de: [consentimentRestauracio, ajustRestauracio, assignacioEstat], a: [(ruta: "mostra.swift", text: """
            let c = ConsentimentRestauracio(magatzem: p, creaEntornRefresc: nil)
            let d = WarpLaunchUI.ConsentimentRestauracio(magatzem: p, creaEntornRefresc: nil)
            let a = AjustRestauracio(ruta: u)
            let b = WarpLaunchCore.AjustRestauracio(ruta: u)
            let v = try AjustRestauracio.analitza(text)
            estat = .acceptat
            self.estat = .acceptat
            if estat == .acceptat {}
            subestat = 1
            """)]) == [
            "mostra.swift:1: «\(consentimentRestauracio)»", "mostra.swift:2: «\(consentimentRestauracio)»",
            "mostra.swift:3: «\(ajustRestauracio)»", "mostra.swift:4: «\(ajustRestauracio)»",
            "mostra.swift:6: «\(assignacioEstat)»", "mostra.swift:7: «\(assignacioEstat)»",
        ])
        // El consentiment (revisió de la 0.29.0): acceptar-lo i construir-ne un d'acceptat, sí; definir `accepta` o
        // comparar-hi, no.
        let consentiment = [#"\.accepta\("#] + donenConsentiment
        let migrat = donenConsentiment[1]
        #expect(try aparicions(de: consentiment, a: [(ruta: "mostra.swift", text: """
            consentiment.accepta()
            public func accepta(ara: Date) {}
            guard estat == .acceptat else { return }
            p.restauracio = .acceptat(ara)
            Preferencies(restauracio: .migrat)
            if p.restauracio == .migrat {}
            Preferencies(restauracio: .retirat(ara))
            estat = .retirat
            Preferencies(restauracio: Restauracio.migrat.normalitzat)
            if p.restauracio == .migratDeProva {}
            """)]) == [
            "mostra.swift:1: «\\.accepta\\(»", "mostra.swift:4: «\\.acceptat\\(»", "mostra.swift:4: «\\.restauracio\\s*=(?!=)»",
            "mostra.swift:5: «\(migrat)»", "mostra.swift:6: «\(migrat)»", "mostra.swift:7: «\\.retirat\\(»",
            "mostra.swift:9: «\(migrat)»",
        ])
        // D3: la paraula `register`, també darrere d'un punt i en un comentari; `unregister` i `registerUndo`, no.
        #expect(try aparicions(de: [paraulaRegister], a: [(ruta: "mostra.swift", text: """
            activa: { try SMAppService.mainApp.register() },
            desactiva: { try SMAppService.mainApp.unregister() },
            desfer.registerUndo(withTarget: self) { _ in }
            // `register()`
            """)]) == ["mostra.swift:1: «\(paraulaRegister)»", "mostra.swift:4: «\(paraulaRegister)»"])
        // D-P12: `troba` només amb una carpeta temporal.
        #expect(try aparicions(de: [trobaProves, #"perOmissio\.app(?![A-Za-z0-9_])"#], a: [(ruta: "mostra.swift", text: """
            InstallacioWarp.troba(aplicacions: AppWarp.rutaPerDefecte, cerca: c)
            InstallacioWarp.troba(aplicacions: url, cerca: c)
            InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: c)
            InstallacioWarp.perOmissio.app.versio
            InstallacioWarp.perOmissio.executable
            WarpLaunchCore.InstallacioWarp.troba(aplicacions: url, cerca: c)
            """)]) == ["mostra.swift:1: «\(trobaProves)»", "mostra.swift:2: «\(trobaProves)»",
                       "mostra.swift:4: «perOmissio\\.app(?![A-Za-z0-9_])»", "mostra.swift:6: «\(trobaProves)»"])
        // Decisió 4 (0.31.1): el Warp de `lector.warp` sense passar per `installacio()`, sí; `warpObert()`, no.
        #expect(try aparicions(de: [senseInstallacio], a: [(ruta: "mostra.swift", text: """
            let w = lector.warp()
            versioWarp: { lector.warp().app.versio }
            obre: { try await ObreWarp.obre($0, warp: lector.installacio()) }
            if lector.warpObert() {}
            """)]) == ["mostra.swift:1: «\(senseInstallacio)»", "mostra.swift:2: «\(senseInstallacio)»"])
        // Pla A4: els lectors de Claude i «Copia el diagnòstic».
        #expect(try aparicions(de: [lectorTranscripcions, lectorConfianca, initSenseArguments, copiaDiagnostic],
                               a: [(ruta: "mostra.swift", text: """
            LectorTranscripcions()
            LectorTranscripcions(carpeta: tmp.url("p"))
            LectorConfianca()
            LectorConfianca(ruta: tmp.url("c"))
            CopiaDiagnostic(diagnostic: d)
            CopiaDiagnostic(diagnostic: d, escriu: { _ in })
            WarpLaunchCore.LectorTranscripcions()
            WarpLaunchCore.LectorConfianca()
            WarpLaunchUI.CopiaDiagnostic(diagnostic: d)
            let t = LectorTranscripcions.init(carpeta: tmp.url("p"))
            let c = WarpLaunchCore.LectorConfianca.init()
            let d = Diagnostic(lector: l, inici: i, transcripcions: .init(), confianca: .init(ruta: tmp.url("c")))
            let e = type(of: t).init( )
            let f = LectorTranscripcions.init(carpeta: c), g = Foo.init(x: 1)
            """)]) == ["mostra.swift:1: «\(lectorTranscripcions)»", "mostra.swift:3: «\(lectorConfianca)»",
                       "mostra.swift:5: «\(copiaDiagnostic)»", "mostra.swift:7: «\(lectorTranscripcions)»",
                       "mostra.swift:8: «\(lectorConfianca)»", "mostra.swift:9: «\(copiaDiagnostic)»",
                       "mostra.swift:11: «\(lectorConfianca)»", "mostra.swift:11: «\(initSenseArguments)»",
                       "mostra.swift:12: «\(initSenseArguments)»", "mostra.swift:13: «\(initSenseArguments)»"])
        // Ni `MeuLectorConfianca(`, que és un altre nom.
        #expect(try aparicions(de: [lectorConfianca], a: [(ruta: "mostra.swift", text: "MeuLectorConfianca()")]).isEmpty)
        // Ni `LectorAjustosWarp()`, que llegiria el `settings.toml` de debò, ni `LectorWarp()`, que en llegiria la base, ni
        // `NSApp`, que és l'app de les proves (també davant d'un punt). `LlegeixLectorWarp(` i `NSApplication` són altres noms.
        #expect(try aparicions(de: [lectorAjustosProves, lectorWarpProves, nsApp], a: [(ruta: "mostra.swift", text: """
            LectorAjustosWarp().desaFinestres()
            LectorAjustosWarp(ruta: tmp)
            WarpLaunchCore.LectorAjustosWarp().desaFinestres()
            try LectorWarp().llegeix()
            try LectorWarp(ruta: base.url).llegeix()
            try WarpLaunchCore.LectorWarp().llegeix()
            @Test func lEsquemaEsTotElQueLlegeixLectorWarp() throws {
            NSApp.terminate(nil)
            AppKit.NSApp.setActivationPolicy(.regular)
            let a = NSApp
            NSApplication.shared.hide(nil)
            """)]) == [
            "mostra.swift:1: «\(lectorAjustosProves)»", "mostra.swift:3: «\(lectorAjustosProves)»",
            "mostra.swift:4: «\(lectorWarpProves)»", "mostra.swift:6: «\(lectorWarpProves)»",
            "mostra.swift:8: «\(nsApp)»", "mostra.swift:9: «\(nsApp)»", "mostra.swift:10: «\(nsApp)»",
        ])
        // La carpeta d'inici de debò, de totes les maneres; posar `HOME` a un procés fill, no.
        #expect(try aparicions(de: iniciDeDebo, a: [(ruta: "mostra.swift", text: """
            FileManager.default.homeDirectoryForCurrentUser
            NSHomeDirectory()
            URL.homeDirectory.appending(path: ".claude")
            FileManager.default.homeDirectory(forUser: "prova")
            ("~/.claude" as NSString).expandingTildeInPath
            getenv("HOME")
            ProcessInfo.processInfo.environment["HOME"]
            getpwuid(getuid())
            procés.environment = ["HOME": tmp.url("inici").path]
            """)]) == [
            "mostra.swift:1: «\(iniciDeDebo[0])»", "mostra.swift:2: «\(iniciDeDebo[1])»", "mostra.swift:3: «\(iniciDeDebo[2])»",
            "mostra.swift:4: «\(iniciDeDebo[2])»", "mostra.swift:5: «\(iniciDeDebo[3])»", "mostra.swift:6: «\(iniciDeDebo[4])»",
            "mostra.swift:7: «\(iniciDeDebo[5])»", "mostra.swift:8: «\(iniciDeDebo[6])»",
        ])
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
        // Fase 3.1: esborrar, canviar de nom i crear carpetes a la de Warp, també amb el mòdul.
        #expect(try aparicions(de: [cridaUnlink, cridaRename, cridaMkdir], a: [(ruta: "mostra.swift", text: """
            unlink(ruta)
            Darwin.unlink(ruta)
            Darwin.rename(a, b)
            Darwin.mkdir(r, 0o755)
            let n = renameFile(a)
            """)]) == ["mostra.swift:1: «\(cridaUnlink)»", "mostra.swift:2: «\(cridaUnlink)»", "mostra.swift:3: «\(cridaRename)»",
                       "mostra.swift:4: «\(cridaMkdir)»"])
        // Les altres maneres d'esborrar, moure o crear (revisió de la 0.31.2), també amb el mòdul i sense cridar-les. Un nom
        // que només s'hi assembla, `remove(at:)` d'un valor (també a la línia següent) i les funcions de l'estat de
        // `removefile`, que no esborren res, no.
        let altresManeres = [(ruta: "mostra.swift", text: """
            rmdir(ruta)
            Darwin.unlinkat(AT_FDCWD, ruta, 0)
            renameat(AT_FDCWD, a, AT_FDCWD, b)
            Darwin.renameatx_np(AT_FDCWD, a, AT_FDCWD, b, UInt32(RENAME_EXCL))
            renamex_np(a, b, UInt32(RENAME_EXCL))
            Darwin.mkdirat(AT_FDCWD, r, 0o755)
            try FileManager.default.trashItem(at: u, resultingItemURL: nil)
            removefile(r, nil, removefile_flags_t(REMOVEFILE_RECURSIVE))
            Darwin.removefileat(fd, r, nil, 0)
            let esborra = rmdir
            guard remove(ruta) == 0 else { return }
            _ = Foundation.remove(r)
            let treu = Darwin.remove
            llista.remove(at: 0)
                .remove(x)
            noms.removeAll()
            let n = MeuDarwin.remove(r)
            func rmdirs() {}
            let trashItems = 0
            removefile_state_free(estat)
            elMeuunlinkat(r)
            let nom = "renameatLater"
            """)]
        let noves = altresEsborrenOMouen
        #expect(try aparicions(de: noves, a: altresManeres) == [
            "mostra.swift:1: «\(noves[0])»", "mostra.swift:2: «\(noves[1])»", "mostra.swift:3: «\(noves[2])»",
            "mostra.swift:4: «\(noves[2])»", "mostra.swift:5: «\(noves[3])»", "mostra.swift:6: «\(noves[4])»",
            "mostra.swift:7: «\(noves[5])»", "mostra.swift:8: «\(noves[6])»", "mostra.swift:9: «\(noves[6])»",
            "mostra.swift:10: «\(noves[0])»", "mostra.swift:11: «\(noves[7])»", "mostra.swift:12: «\(noves[7])»",
            "mostra.swift:13: «\(noves[7])»",
        ])
        // Les dues guardes que les fan servir troben les mateixes línies, i cap de les altres.
        func linies(_ expressions: [String]) throws -> [Int] {
            Set(try aparicions(de: expressions, a: altresManeres).compactMap { Int($0.split(separator: ":")[1]) }).sorted()
        }
        #expect(try linies(prohibidesCarpetaWarp) == Array(1...13))
        #expect(try linies(escriuen) == Array(1...13))
        // Les altres maneres de crear, sobreescriure o enllaçar (revisió de la 0.31.2), també amb el mòdul i sense cridar-les.
        // Un nom que només s'hi assembla, la variable `creat` de `FitxersLaunchWarp` i les funcions de l'estat de `copyfile`,
        // no.
        let creenOSobreescriuen = [(ruta: "mostra.swift", text: """
            let f = fopen(r, "w")
            Darwin.freopen(r, "a", stdout)
            let fd = Darwin.openat(AT_FDCWD, r, O_WRONLY)
            let fd = creat(r, 0o644)
            truncate(r, 0)
            Darwin.ftruncate(fd, 0)
            copyfile(a, b, nil, copyfile_flags_t(COPYFILE_ALL))
            fcopyfile(x, y, nil, copyfile_flags_t(COPYFILE_DATA))
            try FileManager.default.linkItem(at: u, to: v)
            try FileManager.default.createSymbolicLink(atPath: a, withDestinationPath: b)
            let obre = fopen
            var creat = stat()
            if fstat(fd, &creat) == 0, creat.st_ino == ara.st_ino {}
            let s = copyfile_state_alloc()
            let t = "untruncated"
            let fopened = 1
            """)]
        let creen = altresCreenOSobreescriuen
        #expect(try aparicions(de: creen, a: creenOSobreescriuen) == [
            "mostra.swift:1: «\(creen[0])»", "mostra.swift:2: «\(creen[0])»", "mostra.swift:3: «\(creen[1])»",
            "mostra.swift:4: «\(creen[2])»", "mostra.swift:5: «\(creen[3])»", "mostra.swift:6: «\(creen[3])»",
            "mostra.swift:7: «\(creen[4])»", "mostra.swift:8: «\(creen[4])»", "mostra.swift:9: «\(creen[5])»",
            "mostra.swift:10: «\(creen[6])»", "mostra.swift:11: «\(creen[0])»",
        ])
        func liniesCreen(_ expressions: [String]) throws -> [Int] {
            Set(try aparicions(de: expressions, a: creenOSobreescriuen).compactMap { Int($0.split(separator: ":")[1]) }).sorted()
        }
        #expect(try liniesCreen(prohibidesCarpetaWarp) == Array(1...11))
        #expect(try liniesCreen(escriuen) == Array(1...11))
        // A la carpeta de Warp, tampoc cap altra manera d'escriure-hi: cada línia, la seva expressió. La crida `write` de C, que
        // escriu al fitxer que s'acaba de crear, no.
        let sobreescriuen = [#"createFile"#, #"\.write\("#, #"forWriting"#, #"forUpdating"#, #"O_RDWR"#, #"O_APPEND"#]
        #expect(try aparicions(de: prohibidesCarpetaWarp, a: [(ruta: "mostra.swift", text: """
            FileManager.default.createFile(atPath: r, contents: d)
            try text.write(toFile: r, atomically: false, encoding: .utf8)
            let h = try FileHandle(forWritingTo: u)
            let h = FileHandle(forUpdatingAtPath: r)
            let fd = open(ruta, O_RDWR | O_NOFOLLOW)
            let fd = open(ruta, O_WRONLY | O_APPEND)
            let n = write(fd, bytes.baseAddress! + escrits, bytes.count - escrits)
            """)]) == sobreescriuen.enumerated().map { "mostra.swift:\($0.offset + 1): «\($0.element)»" })
        // I només les dues crides a `open` d'ara: una altra, també sense cap d'aquestes expressions, ja hi surt.
        let dues = obrenAFitxersLaunchWarp.joined(separator: "\n")
        #expect(try obertures("    " + dues.replacingOccurrences(of: "\n", with: "\n        ")) == obrenAFitxersLaunchWarp)
        for altra in ["let fd = open(ruta, O_WRONLY | O_NOFOLLOW)", "let fd = Darwin.open(ruta, banderes, 0o644)",
                      "let obre = open"] {
            #expect(try obertures(dues + "\n" + altra) == obrenAFitxersLaunchWarp + [altra])
        }
        // Un nom que només s'hi assembla, no (`openat` ja és a `altresCreenOSobreescriuen`).
        #expect(try obertures("let fd = openat(d, r, 0)\nlet o = reopen(x)\nlet obert = isOpen").isEmpty)
        // D-P4: Escapada a la pantalla del permís, de totes les maneres; el botó per defecte, no.
        #expect(try aparicions(de: escapada, a: [(ruta: "mostra.swift", text: """
            .keyboardShortcut(.cancelAction)
            .keyboardShortcut(KeyEquivalent.escape)
            .onExitCommand { }
            .onKeyPress(keys: [.return]) { _ in .handled }
            override func cancelOperation(_ sender: Any?) {}
            .keyboardShortcut(KeyEquivalent("\\u{1b}"))
            .keyboardShortcut(.defaultAction)
            .keyboardShortcut(.escapeDeProva)
            """)]) == escapada.enumerated().map { "mostra.swift:\($0.offset + 1): «\($0.element)»" })
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
            + ["mostra.swift:10: «\(onDrag)»"])
        // Obrir o tancar: cada línia, la seva expressió; «Mostra al Finder», cap; `kill` i `Process` com a part d'un nom, cap,
        // però sense cridar-los o amb `.init`, sí. De Warp, totes les URL menys la de llançament. `NSWorkspace.shared.open(`
        // passa aquesta expressió, però `nomesLObridorObreWarp` el deixa en un sol lloc.
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
            Darwin.kill(pid, SIGKILL)
            Darwin.killpg(grup, SIGKILL)
            let p = Foundation.Process()
            let r = Process.init()
            let s: Process = .init()
            let k = kill
            let g = Darwin.killpg
            let e = ProcessInfo.processInfo.environment
            let d = ProcessosDelSistema()
            execv("/usr/bin/open", args)
            Darwin.execvp("open", args)
            try NSUserUnixTask(url: u).execute(withArguments: [])
            NSUserAppleScriptTask(url: u)
            executa(ordre)
            """)]
        let workspace = #"NSWorkspace(?!\.shared\.(activateFileViewerSelecting|open|openApplication)\(|\.OpenConfiguration\(\))"#
        #expect(try aparicions(de: prohibidesCodi, a: obrir) == [
            "mostra.swift:2: «NSRunningApplication»",
            "mostra.swift:3: «forceTerminate»",
            "mostra.swift:4: «\(workspace)»",
            "mostra.swift:4: «launchApplication»",
            "mostra.swift:6: «\(paraulaKill)»",
            "mostra.swift:9: «\(paraulaKill)»",
            "mostra.swift:10: «warp://(?!launch/\")»",
            "mostra.swift:12: «warp://(?!launch/\")»",
            "mostra.swift:13: «\(paraulaKill)»",
            "mostra.swift:14: «\(paraulaKill)»",
            "mostra.swift:15: «\(paraulaProcess)»",
            "mostra.swift:16: «\(paraulaProcess)»",
            "mostra.swift:17: «\(paraulaProcess)»",
            "mostra.swift:18: «\(paraulaKill)»",
            "mostra.swift:19: «\(paraulaKill)»",
            "mostra.swift:22: «\(paraulaExec)»",
            "mostra.swift:23: «\(paraulaExec)»",
            "mostra.swift:24: «\(tascaUsuari)»",
            "mostra.swift:25: «\(tascaUsuari)»",
        ])
    }

    /// Cap expressió d'aquest fitxer no fa servir `\b` (vegeu `paraulaProcess`): una guarda nova que el fes servir no veuria els
    /// noms amb el mòdul davant. És l'única prova que llegeix aquest fitxer, i només en mira les línies que no són comentaris.
    @Test func capGuardaFaServirElLimitDeParaula() throws {
        let limit = "\\" + "b"
        func ambLimit(_ text: String) -> [Int] {
            text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") && $0.element.contains(limit) }
                .map { $0.offset + 1 }
        }
        let aquest = try String(contentsOf: URL(filePath: #filePath), encoding: .utf8)
        #expect(aquest.contains("@Test func capGuardaFaServirElLimitDeParaula()"), "no s'ha llegit aquest fitxer")
        #expect(ambLimit(aquest).isEmpty, "\(ambLimit(aquest).map { "GuardaTests.swift:\($0)" })")
        // La mostra: una expressió, una cadena del resultat o una de nova, amb `\b`, surt; un comentari, no.
        #expect(ambLimit("""
            private let p = #"\(limit)Process\\("#
            /// Sense `\(limit)`.
            "mostra.swift:1: «\\\(limit)Process\\\\(»"
            #expect(try aparicions(de: [#"(^|[^A-Za-z0-9_])Process\\("#], a: mostra).isEmpty)
                // `\(limit)NSApp\(limit)`
            let r = try Regex(#"\\.migrat\(limit)"#)
            """) == [1, 3, 6])
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
        let escapades = try aparicions(de: escapada, a: [vista])
        #expect(escapades.isEmpty, "\(escapades)")
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
    /// canviar de nom, esborrar de cap altra manera ni crear carpetes (`prohibidesCarpetaWarp`), i sense cap altra crida a
    /// `open` que les dues d'ara (`obrenAFitxersLaunchWarp`).
    @Test func nomesFitxersLaunchWarpTocaLaCarpetaDeWarp() throws {
        let codi = try fitxers("Sources")
        #expect(codi.filter { $0.text.contains("launch_configurations") }.map(\.ruta)
            == ["Sources/WarpLaunchCore/FitxersLaunchWarp.swift"])
        let fitxer = try #require(codi.first { $0.ruta.hasSuffix("/FitxersLaunchWarp.swift") })
        #expect(try aparicions(de: [cridaUnlink], a: [fitxer]).count == 1)
        let trobades = try aparicions(de: prohibidesCarpetaWarp, a: [fitxer])
        #expect(trobades.isEmpty, "\(trobades)")
        #expect(fitxer.text.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW"))
        #expect(try obertures(fitxer.text) == obrenAFitxersLaunchWarp)
    }

    /// A les proves, `Process` només és als helpers que fan llegir una línia a zsh o executen un script de `scripts/`. Com a
    /// paraula (`paraulaProcess`): `Process.init()` tampoc no pot ser enlloc més.
    @Test func processNomesAlHelperDeZsh() throws {
        let llocs = Set(try aparicions(de: [paraulaProcess], a: fitxers("Tests")).map { $0.prefix { $0 != ":" } })
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
