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

/// La línia (començant per 1) del primer fitxer que conté `text`.
private func numeroDeLinia(_ text: String, a fitxers: [(ruta: String, text: String)]) throws -> Int {
    let fitxer = try #require(fitxers.first { $0.text.contains(text) })
    return try #require(fitxer.text.split(separator: "\n", omittingEmptySubsequences: false).firstIndex { $0.contains(text) }) + 1
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
/// A les proves, res de l'app (`lesProvesNoLlegeixenLEstatReal`). `Lector`, `LectorWarp` i `LectorAjustosWarp` no tenen cap
/// valor per defecte (`elsLectorsDeWarpDeDeboNomesDeLAppIDelCLI`): sense les rutes, tampoc amb `.init(`, no compilen, i les
/// de debò no es poden escriure en una prova (`rutaPerDefecte`, `iniciDeDebo`).
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
/// Com a paraula, també sense cridar-la (`let f = mkdir`).
private let cridaMkdir = #"(^|[^A-Za-z0-9_])mkdir(?![A-Za-z0-9_])"#
/// L'única crida de `FitxersLaunchWarp` que crea una carpeta (regla 7, decisió d'en David del 09/11/2026): un sol nivell, i
/// `prohibidesCarpetaWarp` continua prohibint qualsevol altra.
private let creaCarpetaWarp = "guard mkdir(carpeta.path, mode_t(0o755)) != 0 else { return true }"
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
/// Les altres maneres d'obrir o de crear un fitxer o una carpeta que no es diuen `open(`, `creat(` o `mkdir(`, de C i de
/// CoreFoundation: `openx_np` (amb `O_WRONLY`, escriuria sobre un fitxer que ja hi és amb el `write(` de C, que
/// `FitxersLaunchWarp` fa servir per al fitxer que acaba de crear);
/// `mkstemp`, `mkstemps`, `mkostemp`, `mkostemps` i `mkdtemp`; `mkdirx_np`, `mkpath_np` i `mkpathat_np`; `mkfifo`,
/// `mkfifoat`, `mkfifox_np`, `mknod` i `mknodat`; i `CFWriteStreamCreateWithFile`. Com a paraula, també amb el mòdul i sense
/// cridar-les. Valen per al diagnòstic (`escriuen`), per a la carpeta de Warp (`prohibidesCarpetaWarp`) i per a l'ajust
/// (`nomesLAjustCreaElFitxerDeWarp`): cap dels tres no en fa servir cap.
/// El `write` de C i els seus germans (`pwrite`, `writev` i `pwritev`), com a paraula, també amb el mòdul i sense cridar-los;
/// el mètode `.write(` d'un valor (ja a `escriuen` i a `escriuenDirectament`), no. Al diagnòstic i a l'ajust, que no en fan
/// servir cap: amb un descriptor obert d'una altra manera, escriurien a un fitxer.
private let cridaWriteDeC = #"((^|[^A-Za-z0-9_.])|(^|[^A-Za-z0-9_])(Darwin|Foundation)\.)p?writev?(?![A-Za-z0-9_])"#
private let altresObrenOCreen = [
    #"(^|[^A-Za-z0-9_])openx_np(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])(mko?stemps?|mkdtemp)(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])(mkdirx_np|mkpath(at)?_np)(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])mk(fifo|nod)(at|x_np)?(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])CFWriteStreamCreateWithFile(?![A-Za-z0-9_])"#,
]
/// Les maneres de canviar els permisos, el propietari, les marques, les dates o els atributs estesos d'un fitxer, o
/// d'intercanviar-ne el contingut amb un altre, de C, de `FileManager`, d'`URL` i de `CFURL`: `chmod`, `fchmod`, `lchmod`,
/// `fchmodat`, `chmodx_np` i `fchmodx_np`; `chown`, `fchown`, `lchown` i `fchownat`; `chflags`, `fchflags` i `lchflags`;
/// `setAttributes`; `setResourceValue` i `setResourceValues`; `exchangedata` i `fexchangedata`; `setxattr`, `fsetxattr`,
/// `removexattr` i `fremovexattr`; `setattrlist`, `fsetattrlist` i `setattrlistat`; `utimes`, `futimes`, `lutimes`, `utime`,
/// `utimensat` i `futimens`; les ACL d'un fitxer (`acl_set_file`, `acl_set_fd`, `acl_set_fd_np`, `acl_set_link_np` i
/// `acl_delete_def_file`), que també en canvien els permisos; i `CFURLSetResourcePropertyForKey` i
/// `CFURLSetResourcePropertiesForKeys`, els d'`URL` amb un altre nom. Com a paraula, també amb el mòdul i sense cridar-les;
/// les que només llegeixen (`getxattr`, `listxattr`, `getattrlist`, `attributesOfItem`, `resourceValues`, `acl_get_file`,
/// `CFURLCopyResourcePropertyForKey`) i les que només canvien una ACL a la memòria (`acl_set_permset`), no. Valen per a tot
/// `Sources`, amb les dues úniques excepcions de `canvienAtributsPermesos` (`canvienAtributsForaDeLloc`), i també per al
/// diagnòstic (`escriuen`) i per a l'ajust (`nomesLAjustCreaElFitxerDeWarp`), que tenen la seva pròpia llista.
private let altresCanvienAtributs = [
    #"(^|[^A-Za-z0-9_])(f|l)?chmod(at|x_np)?(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])(f|l)?chown(at)?(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])(f|l)?chflags(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])setAttributes(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])setResourceValues?(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])f?exchangedata(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])f?(set|remove)xattr(?![A-Za-z0-9_])"#, #"(^|[^A-Za-z0-9_])f?setattrlist(at)?(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])((f|l)?utimes|utimensat|futimens|utime)(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])acl_(set_(file|fd|fd_np|link_np)|delete_def_file)(?![A-Za-z0-9_])"#,
    #"(^|[^A-Za-z0-9_])CFURLSetResourcePropert(yForKey|iesForKeys)(?![A-Za-z0-9_])"#,
]
/// L'única crida de `FitxersLaunchWarp` que canvia els permisos d'un fitxer: la del que acaba de crear amb `O_EXCL`, pel seu
/// descriptor, abans d'escriure-hi. Una altra, també amb el mòdul o amb una ruta, ja hi surt (`canvienAtributs`).
private let canvienAtributsAFitxersLaunchWarp = ["if fchmod(fd, 0o644) != 0 {"]
/// Decisió 7 (ronda 6): les dues úniques crides de `Sources` que canvien els permisos d'un fitxer, cadascuna al seu fitxer i
/// sobre el que la mateixa funció acaba de crear amb `O_EXCL`, pel seu descriptor (`permisosDelFitxerAcabatDeCrear`): la de
/// `EscripturaAtomica.creaFitxerNou` (els permisos que li demanen) i la de `FitxersLaunchWarp` (0644).
private let rutaEscripturaAtomica = "Sources/WarpLaunchCore/EscripturaAtomica.swift"
private let rutaFitxersLaunchWarp = "Sources/WarpLaunchCore/FitxersLaunchWarp.swift"
private let obreAEscripturaAtomica = "let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))"
private let canvienAtributsAEscripturaAtomica = [
    "guard fchmod(fd, mode_t(permisos & 0o7777)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }",
]
private let canvienAtributsPermesos = [
    rutaEscripturaAtomica: canvienAtributsAEscripturaAtomica, rutaFitxersLaunchWarp: canvienAtributsAFitxersLaunchWarp,
]
/// Les línies que canvien els permisos o els atributs d'un fitxer (`altresCanvienAtributs`), sense els espais del principi.
private func canvienAtributs(_ text: String) throws -> [String] {
    let regs = try altresCanvienAtributs.map { try Regex($0) }
    return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { linia in regs.contains { linia.contains($0) } }
}
/// Les línies de `Sources` que canvien els permisos o els atributs d'un fitxer i no són les de `canvienAtributsPermesos` al
/// seu fitxer: qualsevol altra crida a qualsevol fitxer, una de les dues a un altre fitxer, o la mateixa dues vegades. Com
/// `canvienAtributs`, també en un comentari: cap línia de `Sources` no les esmenta.
private func canvienAtributsForaDeLloc(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try codi.flatMap { f -> [String] in
        var sobren = try canvienAtributs(f.text)
        for permesa in canvienAtributsPermesos[f.ruta] ?? [] {
            if let i = sobren.firstIndex(of: permesa) { sobren.remove(at: i) }
        }
        return sobren.map { "\(f.ruta): \($0)" }
    }
}
/// La crida que canvia els permisos és després de l'`open` que crea el fitxer amb `O_EXCL`, i entremig no hi ha cap altra
/// funció ni cap altre `fd`: amb el descriptor d'un fitxer que ja hi era, en canviaria els permisos.
private func permisosDelFitxerAcabatDeCrear(_ text: String, obre: String, permisos: String) -> Bool {
    guard let creat = text.range(of: obre), let crida = text.range(of: permisos), creat.upperBound <= crida.lowerBound else {
        return false
    }
    let entremig = text[creat.upperBound..<crida.lowerBound]
    return !entremig.contains("func ") && !entremig.contains("fd =")
}
/// A `FitxersLaunchWarp`, a més de l'única crida que esborra (`cridaUnlink`), res que sobreescrigui, esborri, mogui o creï
/// carpetes: tampoc `createFile` (que sobreescriu el que hi ha), cap `.write(` (també `toFile:`), un `FileHandle` per
/// escriure, `O_RDWR`, `O_APPEND` ni cap altra manera d'obrir o de crear un fitxer (`altresObrenOCreen`). I només les dues
/// crides a `open` d'ara (`obrenAFitxersLaunchWarp`) i la de `fchmod`
/// (`canvienAtributsAFitxersLaunchWarp`).
private let prohibidesCarpetaWarp = [#"removeItem"#, cridaRename, #"createDirectory"#, #"O_TRUNC"#, #"\.write\("#,
                                     cridaMkdir, #"replaceItem"#, #"moveItem"#, #"copyItem"#, #"createFile"#,
                                     #"forWriting"#, #"forUpdating"#, #"O_RDWR"#, #"O_APPEND"#]
    + altresEsborrenOMouen + altresCreenOSobreescriuen + altresObrenOCreen
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

/// Sparkle només el coneix aquest fitxer (`sparkleNomesAlServei`).
private let serveiActualitzacions = "Sources/WarpLaunchApp/ServeiActualitzacions.swift"
private let nomesAlServei = [#"import Sparkle"#, #"SPU[A-Z]"#, #"(^|[^A-Za-z0-9_])SU[A-Z]"#]
/// Al servei, el delegat `updaterWillRelaunchApplication` porta la paraula a dins. La crida de `NSWorkspace`, no.
private let obrirAppAlServei = #"(^|[^e])launchApplication|(^|[^R]e)launchApplication|(^|[^l]Re)launchApplication"#
/// La firma del delegat que avisa que es baixarà: l'única línia que pot tenir el tipus, i el valor no es fa servir.
private let firmaBaixada = "with request: NSMutableURLRequest) {"
/// `updaterShouldRelaunchApplication` amb `false` avorta la instal·lació; `feedParameters` afegiria dades a la petició.
private let prohibitsAlServei = [#"feedURLString"#, #"setFeedURL"#, #"sendsSystemProfile"#, #"allowedChannels"#, #"startUpdater\(\)"#,
                                 #"updaterShouldRelaunchApplication"#, #"updaterShouldPromptForPermission"#, #"feedParameters"#]
/// Xarxa, a tot `Sources/` i sense excepcions (`capCodiNoFaServirLaXarxa`).
private let xarxa = [#"URLSession"#, #"URLRequest"#, #"NSURLConnection"#, #"import Network"#, #"NWConnection"#, #"NWPathMonitor"#,
                     #"CFNetwork"#, #"WKWebView"#, #"https?://"#]

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
    case serveiActualitzacions: prohibidesCodi.map { $0 == #"launchApplication"# ? obrirAppAlServei : $0 }
    default: prohibidesCodi
    }
}

/// Les línies del codi que poden obrir, tancar o registrar res, amb les expressions de cada fitxer.
private func obrenOTanquen(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try codi.flatMap { try aparicions(de: prohibidesCodi(a: $0.ruta), a: [$0]) }
}

/// Pla A4: a les proves, els lectors de Claude només amb una ruta (també amb `.init(`), i «Copia el diagnòstic» només amb un
/// porta-retalls fals. Sense `\b`: amb les regles d'Unicode, `WarpLaunchCore.LectorConfianca(` no hi té cap límit de paraula.
private let lectorTranscripcions = #"(^|[^A-Za-z0-9_])LectorTranscripcions(\.init)?\((?!carpeta:)"#
private let lectorConfianca = #"(^|[^A-Za-z0-9_])LectorConfianca(\.init)?\((?!ruta:)"#
private let copiaDiagnostic = #"(^|[^A-Za-z0-9_])CopiaDiagnostic\((?![^\n]*escriu:)"#

/// Pla A4: el diagnòstic només llegeix. Res que escrigui, esborri, mogui, creï carpetes (també `altresEsborrenOMouen`,
/// `altresCreenOSobreescriuen` i `altresObrenOCreen`), canviï els permisos o els atributs d'un fitxer (`altresCanvienAtributs`), executi o toqui
/// el porta-retalls. Sense `\b`: amb les regles d'Unicode, `default.moveItem`
/// o `Darwin.open` no hi tenen cap límit de paraula.
private let escriuen = [
    #"\.desa\("#, #"\.posa\("#, #"\.accepta\("#, #"EscripturaAtomica"#, #"\.write\("#, #"createFile"#,
    #"createDirectory"#, #"removeItem"#, #"(^|[^A-Za-z0-9_])moveItem"#, #"copyItem"#, #"replaceItem"#,
    #"(^|[^A-Za-z0-9_])unlink\("#, #"(^|[^A-Za-z0-9_])rename\("#, #"(^|[^A-Za-z0-9_])open\("#, #"sqlite3_open"#,
    #"forWriting"#, #"forUpdating"#, #"(^|[^A-Za-z0-9_])AjustRestauracio\("#, #"posaRestauracio"#,
    #"recordaRestauracioOriginal"#, paraulaProcess, #"NSPasteboard"#, #"copiaText"#, cridaMkdir,
] + altresEsborrenOMouen + altresCreenOSobreescriuen + altresCanvienAtributs + altresObrenOCreen + [cridaWriteDeC]

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

/// Els lectors de Claude de debò: `LectorTranscripcions` llegeix `~/.claude/projects` amb `carpetaPerDefecte`, i
/// `LectorConfianca`, `~/.claude.json` amb `rutaPerDefecte`. Com a les sessions (`sessionsIProcessosDeDebo`), cap `init` no
/// té la ruta per defecte: una prova que se l'oblidés, també amb `.init()` sense dir-ne el nom (`transcripcions: .init()`,
/// `type(of: t).init()`), no compila, i la guarda ja no ha de buscar cap `.init()`. Les línies de `Sources`, fora dels
/// comentaris, que en creen un (també amb `.init`, `.self` o el mòdul), que donen un valor a una variable o a un paràmetre
/// del tipus (`LectorConfianca = .init(ruta: r)`, també amb el valor a la línia següent), que en diuen la ruta de debò
/// (`.init(ruta: LectorConfianca.rutaPerDefecte)`), que en fan un àlies o una extensió, o que en declaren el tipus; i, als
/// seus fitxers, `Self(` i `.init(`, que en crearien un amb un altre nom (`.deDebo`), les rutes per defecte soles i
/// qualsevol `init`. Així, cap `init` nou (tampoc el d'un protocol, que demanaria canviar la declaració del tipus o una
/// extensió) no torna a deixar crear-ne un sense la ruta.
/// Sense dir-ne el nom, a qualsevol fitxer: `.init(carpeta:` i `.init(ruta:`, les úniques etiquetes dels seus `init`
/// (`confianca: .init(ruta: URL(filePath: lector.inici).appending(path: ".claude.json"))` els diria el fitxer de debò sense
/// passar per l'app), també `type(of: c).init(ruta:` i `.init(` al final de la línia; cap altre tipus de `Sources` no es crea
/// així. I una línia que comença amb el nom: la segona d'una
/// extensió, d'un àlies o d'una declaració partida en dues línies (`extension` i, a la següent, `LectorConfianca {`, que
/// hi podria afegir un `init()`).
private let rutesLectorsClaude = [
    "Sources/WarpLaunchCore/LectorConfianca.swift", "Sources/WarpLaunchCore/LectorTranscripcions.swift",
]
private func lectorsDeClaudeDeDebo(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try lectorsDeDebo(codi, nom: #"Lector(Transcripcions|Confianca)"#, etiquetes: "carpeta|ruta", rutes: rutesLectorsClaude)
}

/// Els lectors de Warp de debò (decisió 7, ronda 6), amb la mateixa guarda: `LectorWarp` (`warp.sqlite`), `LectorAjustosWarp`
/// (`settings.toml`) i `Lector`, que els fa servir tots dos i té les etiquetes `rutaWarp`, `rutaAjustos` i `carpetaSessions`.
/// El `Lector` privat que llegeix JSON (`JSONEstricte`, `ClausRepetides`) és un altre tipus, i surt a la llista fixa.
private let rutesLectorsWarp = [
    "Sources/WarpLaunchCore/Lector.swift", "Sources/WarpLaunchCore/LectorAjustosWarp.swift", "Sources/WarpLaunchCore/LectorWarp.swift",
]
private func lectorsDeWarpDeDebo(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    try lectorsDeDebo(codi, nom: #"Lector(Warp|AjustosWarp)?"#, etiquetes: "ruta|rutaWarp|rutaAjustos|carpetaSessions", rutes: rutesLectorsWarp)
}

/// Les línies de `Sources`, fora dels comentaris, que creen o declaren un lector de debò dels noms de `nom`, o que en diuen
/// la ruta; `etiquetes`, les dels seus `init` (per als que es creen sense dir-ne el nom), i `rutes`, els seus fitxers. Un espai
/// davant del parèntesi (`LectorWarp (ruta: r)`) compila igual, i també hi compta.
private func lectorsDeDebo(_ codi: [(ruta: String, text: String)], nom: String, etiquetes: String,
                           rutes: [String]) throws -> [String] {
    let crea = try Regex(#"(^|[^A-Za-z0-9_])"# + nom
        + #"(\s*\(|\.(init|self|carpetaPerDefecte|rutaPerDefecte)(?![A-Za-z0-9_])|\??\s*=(?!=))"#)
    let aliesOExtensio = try Regex(#"(^|[^A-Za-z0-9_])(typealias|extension)(?![A-Za-z0-9_]).*[^A-Za-z0-9_]"# + nom
        + #"(?![A-Za-z0-9_])"#)
    let declaracio = try Regex(#"(^|[^A-Za-z0-9_])(struct|class|enum|actor|protocol)\s+"# + nom + #"(?![A-Za-z0-9_])"#)
    // `self.init(ruta:` i `Tipus.init(ruta:` no: no és el tipus implícit.
    let senseElNom = try Regex(#"(^|[^A-Za-z0-9_])\.init\s*\(\s*(("# + etiquetes + #")\s*:|(//.*)?$)"#)
    // Un tipus seu (`LectorTranscripcions.On`), no.
    let comencaAmbElNom = try Regex(#"^\.?([A-Za-z_][A-Za-z0-9_]*\.)*"# + nom + #"(?![A-Za-z0-9_]|\.[A-Z])"#)
    // Als seus fitxers: `Self(`, `.init(` i les rutes per defecte soles, i la declaració de qualsevol `init` (també `init?(`
    // i `init<T>(`; `self.init(` i `.init(` no la declaren).
    let alSeuFitxer = try Regex(#"(^|[^A-Za-z0-9_])(Self(\s*\(|\.init(?![A-Za-z0-9_]))|\.init\s*\(|(carpeta|ruta)PerDefecte(?![A-Za-z0-9_]))"#
        + #"|(^|[^A-Za-z0-9_.])init[?!]?\s*[(<]"#)
    return codi.flatMap { f in
        let linies = f.text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return linies.indices.compactMap { i -> String? in
            guard !linies[i].hasPrefix("//") else { return nil }
            // `transcripcions: LectorTranscripcions` i, a la línia següent, `= .deDebo`.
            let linia = i + 1 < linies.count && linies[i + 1].hasPrefix("=") ? linies[i] + " " + linies[i + 1] : linies[i]
            guard linia.contains(crea) || linia.contains(aliesOExtensio) || linia.contains(declaracio)
                || linia.contains(senseElNom) || linia.contains(comencaAmbElNom)
                || (rutes.contains(f.ruta) && linia.contains(alSeuFitxer)) else { return nil }
            return "\(f.ruta): \(linia)"
        }
    }
}

/// Les línies d'un `init` de diverses línies, de la que comença amb `comenca` a la que acaba amb `{`, sense els comentaris
/// ni els espais del principi. Un valor per defecte a qualsevol paràmetre hi surt.
private func liniesDelInit(_ text: String, comenca: String) -> [String] {
    let linies = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("//") }
    guard let primera = linies.firstIndex(where: { $0.hasPrefix(comenca) }),
          let darrera = linies[primera...].firstIndex(where: { $0.hasSuffix("{") }) else { return [] }
    return Array(linies[primera...darrera])
}

/// Les línies de `Sources`, fora dels comentaris, que fan servir la carpeta d'inici de debò (`iniciDeDebo`).
private func iniciDeDeboAlCodi(_ codi: [(ruta: String, text: String)]) throws -> [String] {
    let regs = try iniciDeDebo.map { try Regex($0) }
    return codi.flatMap { f in
        f.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { linia in !linia.hasPrefix("//") && regs.contains { linia.contains($0) } }
            .map { "\(f.ruta): \($0)" }
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
        #expect(linies("carpetaSessions: LectorSessions.carpetaPerDefecte").sorted() == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
            "Sources/WarpLaunchCLI/main.swift: carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
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
            "\(app): carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
            "\(app): let processos = ProcessosDelSistema()",
            "\(app): let transcripcions = LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte)",
            "\(cli): carpetaSessions: LectorSessions.carpetaPerDefecte, processos: processos, warp: TrobaWarp.delSistema,",
            "\(cli): let processos = ProcessosDelSistema()",
            "\(cli): transcripcions: LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte),",
            "\(rutaLectorSessions): .appending(path: \".claude/sessions\")",
            "\(rutaLectorSessions): public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
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

    /// Els lectors de Claude de debò (`~/.claude/projects` i `~/.claude.json`) només els creen l'app i el CLI, cap `init` no
    /// en té la ruta per defecte, i cap paràmetre ni cap variable del codi no en té un per defecte (`lectorsDeClaudeDeDebo`).
    /// Una línia nova que en creï un, a qualsevol fitxer (també sense dir-ne el nom, amb `.init(carpeta:` o `.init(ruta:`),
    /// una extensió (també partida en dues línies) o un `init` nou als seus fitxers, fa fallar la llista. Dels `init`
    /// de la llista, `init(confiades:inici:)` és de `Confianca` i `init(id:darrerMissatge:)`, de `Recent`.
    @Test func elsLectorsDeClaudeDeDeboNomesDeLAppIDelCLI() throws {
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        let deDebo = try lectorsDeClaudeDeDebo(try fitxers("Sources"))
        #expect(deDebo.sorted() == [
            "\(app): let confianca = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte)",
            "\(app): let transcripcions = LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte)",
            "\(cli): confianca: LectorConfianca(ruta: LectorConfianca.rutaPerDefecte))",
            "\(cli): transcripcions: LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte),",
            "\(rutesLectorsClaude[0]): public init(confiades: Set<String>, inici: String) {",
            "\(rutesLectorsClaude[0]): public init(ruta: URL) {",
            "\(rutesLectorsClaude[0]): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".claude.json\")",
            "\(rutesLectorsClaude[0]): public struct LectorConfianca: Sendable {",
            "\(rutesLectorsClaude[1]): public init(carpeta: URL) {",
            "\(rutesLectorsClaude[1]): public init(id: String, darrerMissatge: Date) {",
            "\(rutesLectorsClaude[1]): public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "\(rutesLectorsClaude[1]): public struct LectorTranscripcions: Sendable {",
        ], "\(deDebo.joined(separator: "\n"))")
        // La mostra: crear-ne un, també amb el mòdul, `.init` o `.self`; un valor per defecte, també a la línia següent o amb
        // un altre nom; la ruta per defecte, a qualsevol fitxer; un àlies, una extensió o una altra declaració del tipus
        // (també amb una conformitat de més); i, als seus fitxers, `Self(`, `.init(`, les rutes per defecte i qualsevol `init`
        // (un `init()` nou, un de genèric o un que pot fallar). Un comentari, el tipus d'un paràmetre sense valor, els seus
        // tipus i constants, un altre nom, la ruta d'un altre tipus, `Self(` en un altre fitxer i `self.init(` no. Tampoc
        // `.init()` sense arguments: ja no compila. Sense dir-ne el nom, `.init(carpeta:` i `.init(ruta:` (també amb
        // `type(of:)` o amb els arguments a la línia següent) i una extensió partida en dues línies, sí; `.init(` amb una altra
        // etiqueta, `self.init(ruta:`, `Tipus.init(ruta:` i un tipus seu a principi de línia, no.
        let diagnostic = "Sources/WarpLaunchCore/Diagnostic.swift"
        let obertura = "Sources/WarpLaunchUI/Obertura.swift"
        #expect(try lectorsDeClaudeDeDebo([
            (ruta: diagnostic, text: """
                transcripcions: LectorTranscripcions = .init(carpeta: c), confianca: LectorConfianca, usuari: String? = nil,
                confianca: LectorConfianca? = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte),
                let t = WarpLaunchCore.LectorTranscripcions.init(carpeta: c)
                let e = LectorConfianca (ruta: r)
                let tipus = LectorConfianca.self
                confianca: LectorConfianca
                    = .deDebo,
                public typealias Transcripcions = WarpLaunchCore.LectorTranscripcions
                extension LectorConfianca {
                struct LectorConfianca: Sendable {
                /// `LectorTranscripcions(carpeta: LectorTranscripcions.carpetaPerDefecte)`
                // let c = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte)
                public var transcripcions: LectorTranscripcions
                transcripcions: LectorTranscripcions, confianca: LectorConfianca,
                let r = LectorTranscripcions.Recent(id: i, darrerMissatge: d)
                guard let p = json[LectorConfianca.clauProjectes] else { return nil }
                let m = MeuLectorConfianca(ruta: r)
                if a == b {}
                return Self(lector: l)
                public init(lector: Lector) {
                extension
                    LectorConfianca {
                public extension
                    WarpLaunchCore.LectorTranscripcions: AmbRuta {
                self.init(ruta: r)
                LectorTranscripcions.On.trobada(id)
                """),
            (ruta: obertura, text: """
                confianca: .init(ruta: LectorConfianca.rutaPerDefecte),
                transcripcions: .init(carpeta: WarpLaunchCore.LectorTranscripcions.carpetaPerDefecte)
                let entorn = Entorn(lector: l, transcripcions: .init(), confianca: .init( ))
                let altre = type(of: transcripcions).init()
                let t = LectorTranscripcions
                    .init()
                transcripcions: .init(carpeta: carpeta), confianca: .init(ruta: ruta),
                confianca: .init(ruta: URL(filePath: lector.inici).appending(path: ".claude.json")),
                let c = type(of: confianca).init(ruta: r)
                transcripcions: .init(
                    carpeta: c),
                let u = LectorTranscripcions
                    .init(carpeta: c)
                let warp = LectorWarp(ruta: LectorWarp.rutaPerDefecte)
                let carpetaPerDefecte = c
                let lector = Lector.init(rutaWarp: r, rutaAjustos: a, carpetaSessions: c, processos: p, warp: w)
                let l: Lector = .init(carpetaSessions: c, processos: p, warp: w)
                let m = MagatzemConfiguracio.init(carpeta: c, inici: i)
                let a = AjustRestauracio(ruta: r)
                """),
            (ruta: rutesLectorsClaude[0], text: """
                static let deDebo = Self(ruta: r)
                static var real: LectorConfianca { .init(ruta: r) }
                static let altra = Self.init(ruta: r)
                static let ambEspai = Self (ruta: r)
                public init(ruta: URL = LectorConfianca.rutaPerDefecte) {
                let r = Self.rutaPerDefecte
                public init() { self.init(ruta: r) }
                init?(ruta: String) {
                public struct LectorConfianca: Sendable, AmbRutaPerDefecte {
                return Confianca(confiades: Set(confiades), inici: Rutes.canonica(inici))
                self.init(ruta: URL(filePath: ruta))
                let initialitza = reinit(x)
                """),
            (ruta: rutesLectorsClaude[1], text: """
                public static let deDebo = Self(carpeta: Self.carpetaPerDefecte)
                init<T: StringProtocol>(_ c: T) { self.init(carpeta: URL(filePath: String(c))) }
                """),
        ]) == [
            "\(diagnostic): transcripcions: LectorTranscripcions = .init(carpeta: c), confianca: LectorConfianca, usuari: String? = nil,",
            "\(diagnostic): confianca: LectorConfianca? = LectorConfianca(ruta: LectorConfianca.rutaPerDefecte),",
            "\(diagnostic): let t = WarpLaunchCore.LectorTranscripcions.init(carpeta: c)",
            "\(diagnostic): let e = LectorConfianca (ruta: r)",
            "\(diagnostic): let tipus = LectorConfianca.self",
            "\(diagnostic): confianca: LectorConfianca = .deDebo,",
            "\(diagnostic): public typealias Transcripcions = WarpLaunchCore.LectorTranscripcions",
            "\(diagnostic): extension LectorConfianca {",
            "\(diagnostic): struct LectorConfianca: Sendable {",
            "\(diagnostic): LectorConfianca {",
            "\(diagnostic): WarpLaunchCore.LectorTranscripcions: AmbRuta {",
            "\(obertura): confianca: .init(ruta: LectorConfianca.rutaPerDefecte),",
            "\(obertura): transcripcions: .init(carpeta: WarpLaunchCore.LectorTranscripcions.carpetaPerDefecte)",
            "\(obertura): transcripcions: .init(carpeta: carpeta), confianca: .init(ruta: ruta),",
            "\(obertura): confianca: .init(ruta: URL(filePath: lector.inici).appending(path: \".claude.json\")),",
            "\(obertura): let c = type(of: confianca).init(ruta: r)",
            "\(obertura): transcripcions: .init(",
            "\(obertura): .init(carpeta: c)",
            "\(rutesLectorsClaude[0]): static let deDebo = Self(ruta: r)",
            "\(rutesLectorsClaude[0]): static var real: LectorConfianca { .init(ruta: r) }",
            "\(rutesLectorsClaude[0]): static let altra = Self.init(ruta: r)",
            "\(rutesLectorsClaude[0]): static let ambEspai = Self (ruta: r)",
            "\(rutesLectorsClaude[0]): public init(ruta: URL = LectorConfianca.rutaPerDefecte) {",
            "\(rutesLectorsClaude[0]): let r = Self.rutaPerDefecte",
            "\(rutesLectorsClaude[0]): public init() { self.init(ruta: r) }",
            "\(rutesLectorsClaude[0]): init?(ruta: String) {",
            "\(rutesLectorsClaude[0]): public struct LectorConfianca: Sendable, AmbRutaPerDefecte {",
            "\(rutesLectorsClaude[1]): public static let deDebo = Self(carpeta: Self.carpetaPerDefecte)",
            "\(rutesLectorsClaude[1]): init<T: StringProtocol>(_ c: T) { self.init(carpeta: URL(filePath: String(c))) }",
        ])
    }

    /// Decisió 7 (ronda 6): com els de Claude (`elsLectorsDeClaudeDeDeboNomesDeLAppIDelCLI`), `LectorWarp`, `LectorAjustosWarp` i
    /// `Lector` només els creen l'app i el CLI amb les rutes de debò, i el core amb les que li passen (`lectorsDeWarpDeDebo`). Cap
    /// `init` no té cap valor per defecte: un `Lector()` o un `.init()` oblidat a una prova no compila, i per això les proves ja
    /// no necessiten cap expressió pròpia per a aquests lectors. La carpeta d'inici de debò, tampoc: només a les línies d'aquí.
    /// Dels `init` de la llista, `init(_ db:` és de `Sentencia`, la consulta de `LectorWarp`.
    @Test func elsLectorsDeWarpDeDeboNomesDeLAppIDelCLI() throws {
        let app = "Sources/WarpLaunchApp/WarpLaunchApp.swift"
        let cli = "Sources/WarpLaunchCLI/main.swift"
        let diagnostic = "Sources/WarpLaunchCore/Diagnostic.swift"
        let (lector, ajustos, warp) = (rutesLectorsWarp[0], rutesLectorsWarp[1], rutesLectorsWarp[2])
        let codi = try fitxers("Sources")
        let deDebo = try lectorsDeWarpDeDebo(codi)
        #expect(deDebo.sorted() == [
            "\(app): let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, potCrearElFitxer: { lector.warpHaAcabatDArrencar() })",
            "\(app): let lector = Lector(rutaWarp: LectorWarp.rutaPerDefecte, rutaAjustos: LectorAjustosWarp.rutaPerDefecte,",
            "\(cli): let lector = Lector(rutaWarp: LectorWarp.rutaPerDefecte, rutaAjustos: LectorAjustosWarp.rutaPerDefecte,",
            "Sources/WarpLaunchCore/ClausRepetides.swift: private struct Lector {",
            "Sources/WarpLaunchCore/ClausRepetides.swift: var lector = Lector(bytes: bytes)",
            "\(diagnostic): falta = try LectorWarp(ruta: e.rutaWarp).queFalta()",
            "\(diagnostic): let desaFinestres = e.rutaAjustos.map { LectorAjustosWarp(ruta: $0).desaFinestres() }",
            "Sources/WarpLaunchCore/JSONEstricte.swift: private struct Lector {",
            "Sources/WarpLaunchCore/JSONEstricte.swift: var lector = Lector(bytes: bytes)",
            "\(lector): case .segonsAjust: rutaAjustos.map { LectorAjustosWarp(ruta: $0).desaFinestres() }",
            "\(lector): let finestresWarp = desaFinestres == false ? [] : try LectorWarp(ruta: rutaWarp).llegeix()",
            "\(lector): public init(rutaWarp: URL,",
            "\(lector): public struct Lector: Sendable {",
            "\(ajustos): public init(ruta: URL) {",
            "\(ajustos): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".warp/settings.toml\")",
            "\(ajustos): public struct LectorAjustosWarp: Sendable {",
            "\(warp): init(_ db: OpaquePointer, _ sql: String) throws {",
            "\(warp): public init(ruta: URL) {",
            "\(warp): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "\(warp): public struct LectorWarp: Sendable {",
        ].sorted(), "\(deDebo.joined(separator: "\n"))")

        // Cada paràmetre del `init` del `Lector`, sense cap valor per defecte: un valor a la segona línia o a la darrera
        // (`inici: String = …`) no surt a la llista de sobre.
        let parametres = ["public init(rutaWarp: URL,", "rutaAjustos: URL?,", "carpetaSessions: URL,", "processos: any FontProcessos,",
                          "warp: @escaping @Sendable () -> InstallacioWarp,", "inici: String) {"]
        let textLector = try #require(codi.first { $0.ruta == lector }).text
        #expect(liniesDelInit(textLector, comenca: "public init(") == parametres)
        #expect(liniesDelInit("""
                public init(rutaWarp: URL,
                            // Un comentari.
                            rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,
                            inici: String = FileManager.default.homeDirectoryForCurrentUser.path) {
                    self.rutaWarp = rutaWarp
                }
            """, comenca: "public init(") == [
            "public init(rutaWarp: URL,", "rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,",
            "inici: String = FileManager.default.homeDirectoryForCurrentUser.path) {",
        ])

        // La carpeta d'inici de debò: l'app, el CLI i les rutes de debò. Cap altra línia, de cap manera (també `NSHomeDirectory`).
        #expect(try iniciDeDeboAlCodi(codi).sorted() == [
            "\(app): inici = FileManager.default.homeDirectoryForCurrentUser.path",
            "\(cli): inici: FileManager.default.homeDirectoryForCurrentUser.path)",
            "Sources/WarpLaunchCore/FitxersLaunchWarp.swift: FitxersLaunchWarp(carpeta: FileManager.default.homeDirectoryForCurrentUser",
            "\(ajustos): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".warp/settings.toml\")",
            "Sources/WarpLaunchCore/LectorConfianca.swift: public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: \".claude.json\")",
            "\(rutaLectorSessions): public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "Sources/WarpLaunchCore/LectorTranscripcions.swift: public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
            "\(warp): public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser",
        ].sorted())
        #expect(try iniciDeDeboAlCodi([(ruta: diagnostic, text: """
            inici: String = NSHomeDirectory(),
            let c = URL.homeDirectory.appending(path: ".warp")
            /// `NSHomeDirectory()`
            let inici = lector.inici
            """)]) == [
            "\(diagnostic): inici: String = NSHomeDirectory(),", "\(diagnostic): let c = URL.homeDirectory.appending(path: \".warp\")",
        ])

        // La mostra: crear-ne un, també amb el mòdul, `.init` o `.self`; un valor per defecte, també a la línia següent; la ruta
        // de debò, a qualsevol fitxer; un àlies, una extensió o una altra declaració del tipus (també partides en dues línies); i,
        // als seus fitxers, `Self(`, `.init(`, les rutes per defecte i qualsevol `init`. Sense dir-ne el nom, `.init(` amb les
        // etiquetes dels seus `init` (també amb `type(of:)` o amb els arguments a la línia següent). Un comentari, el tipus d'un
        // paràmetre sense valor, els seus tipus i constants, un altre nom, `Self(` en un altre fitxer i `self.init(`, no.
        let obertura = "Sources/WarpLaunchUI/Obertura.swift"
        #expect(try lectorsDeWarpDeDebo([
            (ruta: diagnostic, text: """
                warp: LectorWarp = .init(ruta: r), ajustos: LectorAjustosWarp, usuari: String? = nil,
                ajustos: LectorAjustosWarp? = LectorAjustosWarp(ruta: LectorAjustosWarp.rutaPerDefecte),
                lector: Lector = .deDebo,
                let w = WarpLaunchCore.LectorWarp.init(ruta: r)
                let e = LectorWarp (ruta: r)
                let tipus = LectorAjustosWarp.self
                lector: Lector
                    = .deDebo,
                public typealias Ajustos = WarpLaunchCore.LectorAjustosWarp
                extension Lector {
                extension LectorWarp {
                struct LectorAjustosWarp: Sendable {
                /// `LectorWarp(ruta: LectorWarp.rutaPerDefecte)`
                // let l = Lector(rutaWarp: r)
                public var lector: Lector
                lector: Lector, inici: String,
                lector: inout Lector,
                let t = LectorWarp.TaulaLlegida(nom: n, columnes: c, opcional: false)
                for taula in LectorWarp.esquema {}
                let m = MeuLectorWarp(ruta: r)
                let s = LectorSessions(carpeta: c, processos: p)
                if a == b {}
                return Self(lector: l)
                public init(lector: Lector) {
                extension
                    LectorWarp {
                public extension
                    WarpLaunchCore.Lector: AmbRuta {
                self.init(ruta: r)
                LectorWarp.TaulaLlegida(nom: n, columnes: c, opcional: true)
                """),
            (ruta: obertura, text: """
                let l = Lector(rutaWarp: a, rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i)
                let l: Lector = .init(rutaWarp: a, rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i)
                lector: .init(carpetaSessions: c, processos: p, warp: w, inici: i),
                lector: .init(rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i),
                ajustos: .init(ruta: LectorAjustosWarp.rutaPerDefecte),
                let v = type(of: warp).init(ruta: r)
                warp: .init(
                    ruta: r),
                let u = LectorWarp
                    .init(ruta: r)
                let j = JSONEstricte.Lector(bytes: b)
                let m = MagatzemConfiguracio.init(carpeta: c, inici: i)
                let a = AjustRestauracio(ruta: r)
                let x = LectorConfianca(ruta: r)
                let carpetaPerDefecte = c
                """),
            (ruta: warp, text: """
                static let deDebo = Self(ruta: r)
                static var real: LectorWarp { .init(ruta: r) }
                static let altra = Self.init(ruta: r)
                static let ambEspai = Self (ruta: r)
                public init(ruta: URL = LectorWarp.rutaPerDefecte) {
                let r = Self.rutaPerDefecte
                public init() { self.init(ruta: r) }
                init?(ruta: String) {
                public struct LectorWarp: Sendable, AmbRutaPerDefecte {
                self.init(ruta: URL(filePath: ruta))
                let initialitza = reinit(x)
                """),
            (ruta: ajustos, text: """
                public init(ruta: URL = LectorAjustosWarp.rutaPerDefecte) {
                public static let deDebo = Self(ruta: Self.rutaPerDefecte)
                """),
            (ruta: lector, text: """
                public init(rutaWarp: URL = LectorWarp.rutaPerDefecte,
                rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,
                public static let deDebo = Self(rutaWarp: r, rutaAjustos: a, carpetaSessions: c, processos: p, warp: w, inici: i)
                init<T: StringProtocol>(_ c: T) { self.init(rutaWarp: URL(filePath: String(c))) }
                """),
        ]) == [
            "\(diagnostic): warp: LectorWarp = .init(ruta: r), ajustos: LectorAjustosWarp, usuari: String? = nil,",
            "\(diagnostic): ajustos: LectorAjustosWarp? = LectorAjustosWarp(ruta: LectorAjustosWarp.rutaPerDefecte),",
            "\(diagnostic): lector: Lector = .deDebo,",
            "\(diagnostic): let w = WarpLaunchCore.LectorWarp.init(ruta: r)",
            "\(diagnostic): let e = LectorWarp (ruta: r)",
            "\(diagnostic): let tipus = LectorAjustosWarp.self",
            "\(diagnostic): lector: Lector = .deDebo,",
            "\(diagnostic): public typealias Ajustos = WarpLaunchCore.LectorAjustosWarp",
            "\(diagnostic): extension Lector {",
            "\(diagnostic): extension LectorWarp {",
            "\(diagnostic): struct LectorAjustosWarp: Sendable {",
            "\(diagnostic): LectorWarp {",
            "\(diagnostic): WarpLaunchCore.Lector: AmbRuta {",
            "\(obertura): let l = Lector(rutaWarp: a, rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i)",
            "\(obertura): let l: Lector = .init(rutaWarp: a, rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i)",
            "\(obertura): lector: .init(carpetaSessions: c, processos: p, warp: w, inici: i),",
            "\(obertura): lector: .init(rutaAjustos: b, carpetaSessions: c, processos: p, warp: w, inici: i),",
            "\(obertura): ajustos: .init(ruta: LectorAjustosWarp.rutaPerDefecte),",
            "\(obertura): let v = type(of: warp).init(ruta: r)",
            "\(obertura): warp: .init(",
            "\(obertura): .init(ruta: r)",
            "\(obertura): let j = JSONEstricte.Lector(bytes: b)",
            "\(warp): static let deDebo = Self(ruta: r)",
            "\(warp): static var real: LectorWarp { .init(ruta: r) }",
            "\(warp): static let altra = Self.init(ruta: r)",
            "\(warp): static let ambEspai = Self (ruta: r)",
            "\(warp): public init(ruta: URL = LectorWarp.rutaPerDefecte) {",
            "\(warp): let r = Self.rutaPerDefecte",
            "\(warp): public init() { self.init(ruta: r) }",
            "\(warp): init?(ruta: String) {",
            "\(warp): public struct LectorWarp: Sendable, AmbRutaPerDefecte {",
            "\(ajustos): public init(ruta: URL = LectorAjustosWarp.rutaPerDefecte) {",
            "\(ajustos): public static let deDebo = Self(ruta: Self.rutaPerDefecte)",
            "\(lector): public init(rutaWarp: URL = LectorWarp.rutaPerDefecte,",
            "\(lector): rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,",
            "\(lector): public static let deDebo = Self(rutaWarp: r, rutaAjustos: a, carpetaSessions: c, processos: p, warp: w, inici: i)",
            "\(lector): init<T: StringProtocol>(_ c: T) { self.init(rutaWarp: URL(filePath: String(c))) }",
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
            + "                // Sense `settings.toml`, només el crea amb Warp obert i amb algun terminal (ronda 5).\n"
            + "                let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, potCrearElFitxer: { lector.warpHaAcabatDArrencar() })\n"))
    }

    /// Decisió A (0.31.2): `settings.toml` de Warp, si no hi és, només el crea `AjustRestauracio`, d'un sol cop i només si
    /// Warp no l'ha creat mentrestant (`renamex_np` amb `RENAME_EXCL`), des d'un fitxer de la carpeta temporal
    /// (`EscripturaAtomica.creaFitxerNou`). No crea la carpeta de Warp, ni obre res per escriure-hi directament, i l'únic
    /// `copyfile` hi copia els atributs estesos de l'original, no al revés. Tampoc no canvia els permisos ni els atributs de
    /// cap fitxer (`altresCanvienAtributs`): els del fitxer nou els posa `EscripturaAtomica.creaFitxerNou`. L'únic `rename` és
    /// el que substitueix el fitxer que ja hi és, i no esborra res més que el fitxer de la carpeta temporal. Cap altre fitxer no
    /// fa servir aquestes crides, ni `O_CREAT` fora d'on ja era, i la ruta de debò només la tenen `LectorAjustosWarp`, l'app i el CLI.
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
        // L'únic `rename` (que no mira si hi ha res) és el de `substitueix`, just després de mirar que el fitxer encara és el
        // que s'ha llegit: un altre, o `renameat`, crearia `settings.toml` si no hi és, sense `RENAME_EXCL` i sense mirar si
        // Warp és obert (`potCrearElFitxer`). Tampoc no esborra res (`unlink`, `remove`, `removefile`, `trashItem`…), i l'únic
        // `removeItem` és el del fitxer de la carpeta temporal.
        let renames = try aparicions(de: [cridaRename], a: [ajust])
        #expect(renames.count == 1, "\(renames)")
        let substitueix = try #require(ajust.text.range(of: "private func substitueix("))
        let comprova = try #require(ajust.text.range(of: "guard lstat(ruta.path, &ara) == 0, Identitat(ara) == llegit,"))
        let rename = try #require(ajust.text.range(of: "guard rename(temporal.path, ruta.path) == 0 else {"))
        let crea = try #require(ajust.text.range(of: "private func crea("))
        #expect(substitueix.lowerBound < comprova.lowerBound && comprova.lowerBound < rename.lowerBound
                && rename.lowerBound < crea.lowerBound)
        #expect(!ajust.text[comprova.upperBound..<rename.lowerBound].contains("func "))
        func esborraAltres(_ text: String) -> [String] {
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("removeItem") && $0 != "try? FileManager.default.removeItem(at: temporal)" }
        }
        #expect(esborraAltres(ajust.text).isEmpty, "\(esborraAltres(ajust.text))")
        #expect(esborraAltres("""
            try? FileManager.default.removeItem(at: temporal)
            try? FileManager.default.removeItem(at: ruta)
            try FileManager.default.removeItem(atPath: temporal.path)
            """) == ["try? FileManager.default.removeItem(at: ruta)", "try FileManager.default.removeItem(atPath: temporal.path)"])
        let esborrenOMouen = [cridaUnlink] + altresEsborrenOMouen.filter { !$0.contains("renamex_np") }
        let noFaLAjust = [#"renameatx_np"#, #"RENAME_SWAP"#, creaOEnllaca[3], creaOEnllaca[4], creaOEnllaca[6],
                          creaOEnllaca[7], cridaMkdir, #"mkdirat"#,
                          #"createDirectory"#, #"O_CREAT"#, #"O_TRUNC"#, #"createFile"#,
                          #"(^|[^A-Za-z0-9_])moveItem"#, #"copyItem"#, #"replaceItem"#] + escriuenDirectament
            + altresCanvienAtributs + esborrenOMouen + altresObrenOCreen + [cridaWriteDeC]
        #expect(try aparicions(de: noFaLAjust, a: [ajust]).isEmpty)
        #expect(try aparicions(de: noFaLAjust, a: [(ruta: rutaAjustRestauracio, text: "let n = pwrite(fd, p, mida, 0)")])
            == ["\(rutaAjustRestauracio):1: «\(cridaWriteDeC)»"])
        #expect(try aparicions(de: noFaLAjust, a: [(ruta: rutaAjustRestauracio, text: "let fd = mkstemp(&plantilla)")])
            == ["\(rutaAjustRestauracio):1: «\(altresObrenOCreen[1])»"])
        // Cada línia, la seva expressió de `esborrenOMouen`; el `renamex_np` de crear-lo, el `rename` de substituir-lo i un
        // mètode que s'hi assembla, cap.
        #expect(try aparicions(de: esborrenOMouen, a: [(ruta: rutaAjustRestauracio, text: """
            _ = unlink(ruta.path)
            rmdir(ruta.deletingLastPathComponent().path)
            Darwin.unlinkat(AT_FDCWD, ruta.path, 0)
            guard renameat(AT_FDCWD, temporal.path, AT_FDCWD, ruta.path) == 0 else {
            Darwin.mkdirat(AT_FDCWD, carpeta.path, 0o755)
            try FileManager.default.trashItem(at: ruta, resultingItemURL: nil)
            removefile(ruta.path, nil, 0)
            remove(ruta.path)
            guard renamex_np(temporal.path, ruta.path, UInt32(RENAME_EXCL)) == 0 else {
            guard rename(temporal.path, ruta.path) == 0 else {
            linies.remove(at: 0)
            """)]) == esborrenOMouen.enumerated().map { "\(rutaAjustRestauracio):\($0.offset + 1): «\($0.element)»" })
        // La crida de `fchmod` de `FitxersLaunchWarp`, a l'ajust, surt.
        #expect(try aparicions(de: noFaLAjust, a: [(ruta: rutaAjustRestauracio, text: canvienAtributsAFitxersLaunchWarp[0])])
            == ["\(rutaAjustRestauracio):1: «\(altresCanvienAtributs[0])»"])
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

        // La ruta de debò de `settings.toml`: per llegir-la, el `Lector` de l'app i el del CLI; per a l'ajust, l'app
        // (`lAjustDeWarpNomesLEscriuLApp`).
        let deDebo = codi.flatMap { f in
            f.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") }
                .filter { $0.contains("LectorAjustosWarp.rutaPerDefecte") || $0.contains(".warp/settings")
                    || (f.ruta.hasSuffix("/LectorAjustosWarp.swift") && $0.contains("rutaPerDefecte")) }
                .map { "\(f.ruta): \($0)" }
        }
        #expect(deDebo.sorted() == [
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: let ajust = AjustRestauracio(ruta: LectorAjustosWarp.rutaPerDefecte, potCrearElFitxer: { lector.warpHaAcabatDArrencar() })",
            "Sources/WarpLaunchApp/WarpLaunchApp.swift: let lector = Lector(rutaWarp: LectorWarp.rutaPerDefecte, rutaAjustos: LectorAjustosWarp.rutaPerDefecte,",
            "Sources/WarpLaunchCLI/main.swift: let lector = Lector(rutaWarp: LectorWarp.rutaPerDefecte, rutaAjustos: LectorAjustosWarp.rutaPerDefecte,",
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
            // Els lectors de Warp, les sessions i els processos no tenen valor per defecte (`elsLectorsDeWarpDeDeboNomesDeLAppIDelCLI`,
            // `lesSessionsIElsProcessosDeDeboNomesDeLAppIDelCLI`): sense les rutes, no compilen, i aquí no se'n pot dir cap de debò.
            ajustRestauracioProves,
            #"ProcessosDelSistema"#,
            #"rutaPerDefecte"#, #"carpetaPerDefecte"#,
            #"\.config/warp-launch"#, nsApp, #"NSApplication"#, #"NSWindow"#, #"NSHostingView"#,
            // El porta-retalls d'en David: una prova el buidaria, o hi deixaria pestanyes fictícies.
            #"NSPasteboard"#, #"PortaRetallsSistema\.(enganxa|hiHaPestanyes|escriu)"#,
            // Fase 3.1: res que obri Warp, ni les carpetes de debò de Warp i de Claude.
            #"NSWorkspace"#, #"openURL"#, #"ObreWarp"#, #"FitxersLaunchWarp\.real"#, #"\.warp/"#, #"launch_configurations"#,
            #"\.claude\.json"#, #"\.claude/projects"#,
            // D-P12: on és Warp de debò. `troba` només amb una carpeta temporal; la instal·lació per omissió no es llegeix.
            #"TrobaWarp"#, #"urlForApplication"#, trobaProves, #"perOmissio\.app(?![A-Za-z0-9_])"#,
            // Pla A4 (diagnòstic): els lectors de Claude, sempre amb una ruta de prova, i «Copia el diagnòstic», sempre amb un
            // porta-retalls fals (a la mateixa línia).
            lectorTranscripcions, lectorConfianca, copiaDiagnostic,
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
            Darwin.chmod(r, 0o777)
            fchown(fd, uid, gid)
            lchflags(r, 0)
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: r)
            try url.setResourceValues(valors)
            exchangedata(a, b, 0)
            fsetxattr(fd, nom, valor, mida, 0, 0)
            setattrlist(r, &llista, &dades, mida, 0)
            utimensat(AT_FDCWD, r, &temps, 0)
            acl_set_file(r, ACL_TYPE_EXTENDED, acl)
            CFURLSetResourcePropertyForKey(u as CFURL, kCFURLIsHiddenKey, kCFBooleanTrue, nil)
            let fd = openx_np(r, O_WRONLY, nil)
            let fd = mkstemp(&plantilla)
            mkpath_np(r, 0o755)
            mkfifo(r, 0o644)
            let s = CFWriteStreamCreateWithFile(nil, u as CFURL)
            let n = write(fd, p, mida)
            """)]
        #expect(mostra[0].text.split(separator: "\n").count == escriuen.count, "una línia per expressió")
        #expect(try aparicions(de: escriuen, a: mostra)
            == escriuen.enumerated().map { "mostra.swift:\($0.offset + 1): «\($0.element)»" })
        // Tampoc la crida de `fchmod` de `FitxersLaunchWarp`, que només val allà.
        #expect(try aparicions(de: escriuen, a: [(ruta: "Sources/WarpLaunchCore/Diagnostic.swift",
                                                 text: canvienAtributsAFitxersLaunchWarp[0])])
            == ["Sources/WarpLaunchCore/Diagnostic.swift:1: «\(altresCanvienAtributs[0])»"])
        #expect(try aparicions(de: escriuen, a: [(ruta: "mostra.swift", text: """
            try AjustRestauracio.analitza(text).valor
            try MagatzemPreferencies(carpeta: c).carrega()
            try LectorWarp(ruta: r).queFalta()
            let permisos = try FileManager.default.attributesOfItem(atPath: r)[.posixPermissions]
            let mida = getxattr(r, nom, nil, 0, 0, 0)
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
            PortaRetallsSistema.escriu(dades)
            let q = Foundation.Process()
            let m = MeuProcess()
            """)]
        #expect(try aparicions(de: [paraulaProcess, #"(^|[^.\w])system\("#], a: mostra) == [
            "mostra.swift:1: «\(paraulaProcess)»", "mostra.swift:2: «(^|[^.\\w])system\\(»", "mostra.swift:5: «\(paraulaProcess)»",
        ])
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
        #expect(try aparicions(de: [lectorTranscripcions, lectorConfianca, copiaDiagnostic],
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
            let f = LectorTranscripcions.init(carpeta: c), g = Foo.init(x: 1)
            """)]) == ["mostra.swift:1: «\(lectorTranscripcions)»", "mostra.swift:3: «\(lectorConfianca)»",
                       "mostra.swift:5: «\(copiaDiagnostic)»", "mostra.swift:7: «\(lectorTranscripcions)»",
                       "mostra.swift:8: «\(lectorConfianca)»", "mostra.swift:9: «\(copiaDiagnostic)»",
                       "mostra.swift:11: «\(lectorConfianca)»"])
        // Ni `MeuLectorConfianca(`, que és un altre nom.
        #expect(try aparicions(de: [lectorConfianca], a: [(ruta: "mostra.swift", text: "MeuLectorConfianca()")]).isEmpty)
        // Ni `NSApp`, que és l'app de les proves (també davant d'un punt). `NSApplication` és un altre nom.
        #expect(try aparicions(de: [nsApp], a: [(ruta: "mostra.swift", text: """
            NSApp.terminate(nil)
            AppKit.NSApp.setActivationPolicy(.regular)
            let a = NSApp
            NSApplication.shared.hide(nil)
            """)]) == ["mostra.swift:1: «\(nsApp)»", "mostra.swift:2: «\(nsApp)»", "mostra.swift:3: «\(nsApp)»"])
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
            "mostra.swift:4: «PortaRetallsSistema\\.(enganxa|hiHaPestanyes|escriu)»",
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
        // Les maneres de canviar els permisos o els atributs d'un fitxer, o d'intercanviar-lo, també amb el mòdul i sense
        // cridar-les. Les que només llegeixen, un nom que només s'hi assembla i el `copyfile` dels atributs estesos (que és a
        // `altresCreenOSobreescriuen`), no.
        let canvienAtributsMostra = [(ruta: "mostra.swift", text: """
            chmod(r, 0o777)
            Darwin.fchmod(fd, 0o600)
            let canvia = lchmod
            fchmodat(AT_FDCWD, r, 0o644, 0)
            chown(r, 0, 0)
            Darwin.fchown(fd, uid, gid)
            lchown(r, uid, gid)
            fchownat(AT_FDCWD, r, uid, gid, 0)
            chflags(r, UInt32(UF_IMMUTABLE))
            fchflags(fd, 0)
            lchflags(r, 0)
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: r)
            try url.setResourceValues(valors)
            try (url as NSURL).setResourceValue(true, forKey: .isHiddenKey)
            exchangedata(a, b, 0)
            Darwin.fexchangedata(x, y, 0)
            setxattr(r, nom, valor, mida, 0, 0)
            fsetxattr(fd, nom, valor, mida, 0, 0)
            removexattr(r, nom, 0)
            Darwin.fremovexattr(fd, nom, 0)
            setattrlist(r, &llista, &dades, mida, 0)
            fsetattrlist(fd, &llista, &dades, mida, 0)
            setattrlistat(AT_FDCWD, r, &llista, &dades, mida, 0)
            utimes(r, nil)
            Darwin.futimes(fd, &temps)
            lutimes(r, nil)
            utime(r, nil)
            utimensat(AT_FDCWD, r, &temps, 0)
            futimens(fd, &temps)
            chmodx_np(r, seguretat)
            Darwin.fchmodx_np(fd, seguretat)
            acl_set_file(r, ACL_TYPE_EXTENDED, acl)
            acl_set_fd(fd, acl)
            Darwin.acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED)
            acl_set_link_np(r, ACL_TYPE_EXTENDED, acl)
            let esborra = acl_delete_def_file
            CFURLSetResourcePropertyForKey(u as CFURL, kCFURLIsHiddenKey, kCFBooleanTrue, nil)
            _ = CFURLSetResourcePropertiesForKeys(u as CFURL, valors as CFDictionary, nil)
            let mida = getxattr(r, nom, nil, 0, 0, 0)
            let noms = listxattr(r, nil, 0, 0)
            getattrlist(r, &llista, &dades, mida, 0)
            let permisos = try FileManager.default.attributesOfItem(atPath: r)[.posixPermissions]
            let valors = try url.resourceValues(forKeys: [.isHiddenKey])
            let chmodBits = 0o644
            let p = MeuChown(r)
            let utimesPerDefecte = 0
            let acl = acl_get_file(r, ACL_TYPE_EXTENDED)
            acl_set_permset(entrada, permisos)
            CFURLCopyResourcePropertyForKey(u as CFURL, kCFURLIsHiddenKey, &valor, nil)
            let chmodx = 0
            """)]
        let atributs = altresCanvienAtributs
        let familia = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 4, 4, 5, 5, 6, 6, 6, 6, 7, 7, 7, 8, 8, 8, 8, 8, 8,
                       0, 0, 9, 9, 9, 9, 9, 10, 10]
        #expect(try aparicions(de: atributs, a: canvienAtributsMostra)
            == familia.enumerated().map { "mostra.swift:\($0.offset + 1): «\(atributs[$0.element])»" })
        // La carpeta de Warp (`canvienAtributs`) i el diagnòstic (`escriuen`) troben les mateixes línies, i cap de les altres.
        let mostraAtributs = canvienAtributsMostra[0].text.split(separator: "\n").map(String.init)
        #expect(try canvienAtributs(canvienAtributsMostra[0].text) == Array(mostraAtributs[0..<familia.count]))
        #expect(Set(try aparicions(de: escriuen, a: canvienAtributsMostra).compactMap { Int($0.split(separator: ":")[1]) })
            .sorted() == Array(1...familia.count))
        // Les altres maneres d'obrir o de crear un fitxer o una carpeta: cada línia, la seva expressió, també amb el mòdul i
        // sense cridar-les; la carpeta de Warp i el diagnòstic les troben totes. Les que només llegeixen, `open(` (que ja té les
        // seves guardes) i un nom que només s'hi assembla, no.
        let obrenOCreenMostra = [(ruta: "mostra.swift", text: """
            let fd = openx_np(r, O_WRONLY, nil)
            let fd = Darwin.openx_np(r, O_RDONLY, seguretat)
            let fd = mkstemp(&plantilla)
            let fd = mkstemps(&plantilla, 5)
            let fd = Darwin.mkostemp(&plantilla, O_CLOEXEC)
            let crea = mkostemps
            let carpeta = mkdtemp(&plantilla)
            mkdirx_np(r, seguretat)
            _ = mkpath_np(r, 0o755)
            mkpathat_np(AT_FDCWD, r, 0o755)
            mkfifo(r, 0o644)
            mkfifoat(AT_FDCWD, r, 0o644)
            mkfifox_np(r, seguretat)
            Darwin.mknod(r, S_IFREG | 0o644, 0)
            mknodat(AT_FDCWD, r, S_IFREG | 0o644, 0)
            let s = CFWriteStreamCreateWithFile(nil, u as CFURL)
            let s = CFReadStreamCreateWithFile(nil, u as CFURL)
            let info = statx_np(r, &estat, seguretat)
            let mkstempLater = 0
            let mknods = 0
            """)]
        // El `write` de C, també amb el mòdul i sense cridar-lo; el mètode d'un valor i un nom que s'hi assembla, no.
        #expect(try aparicions(de: [cridaWriteDeC], a: [(ruta: "mostra.swift", text: """
            let n = write(fd, p, mida)
            Darwin.pwrite(fd, p, mida, 0)
            let escriu = writev
            _ = Foundation.pwritev(fd, v, n, 0)
            try d.write(to: u)
            FileHandle.standardError.write(d)
            let r = rewrite(x)
            let writeLater = 0
            """)]) == (1...4).map { "mostra.swift:\($0): «\(cridaWriteDeC)»" })
        let obrenOCreen = altresObrenOCreen
        let familiaObren = [0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 4]
        #expect(try aparicions(de: obrenOCreen, a: obrenOCreenMostra)
            == familiaObren.enumerated().map { "mostra.swift:\($0.offset + 1): «\(obrenOCreen[$0.element])»" })
        #expect(Set(try aparicions(de: prohibidesCarpetaWarp, a: obrenOCreenMostra).compactMap { Int($0.split(separator: ":")[1]) })
            .sorted() == Array(1...familiaObren.count))
        #expect(Set(try aparicions(de: escriuen, a: obrenOCreenMostra).compactMap { Int($0.split(separator: ":")[1]) })
            .sorted() == Array(1...familiaObren.count))
        // A `FitxersLaunchWarp`, només la crida d'ara: una altra, també amb el mòdul, amb una ruta o sense cridar-la, ja hi surt.
        let fitxersLaunch = "    if fchmod(fd, 0o644) != 0 {\n        error = String(cString: strerror(errno))\n    }"
        #expect(try canvienAtributs(fitxersLaunch) == canvienAtributsAFitxersLaunchWarp)
        for altra in ["if Darwin.fchmod(fd, 0o644) != 0 {", "chmod(ruta, 0o644)", "if fchmod(fd, 0o666) != 0 {",
                      "let canvia = fchmod", "_ = fsetxattr(fd, nom, valor, mida, 0, 0)", "fchmodx_np(fd, seguretat)",
                      "acl_set_fd(fd, acl)"] {
            #expect(try canvienAtributs(fitxersLaunch + "\n" + altra) == canvienAtributsAFitxersLaunchWarp + [altra])
        }
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
        // L'única crida a `mkdir`, exactament, un sol cop; i només s'hi arriba si qui escriu ho demana.
        #expect(fitxer.text.components(separatedBy: creaCarpetaWarp).count == 2)
        #expect(fitxer.text.components(separatedBy: "creaLaCarpeta()").count == 3)
        #expect(fitxer.text.contains("guard creaCarpeta, creaLaCarpeta() else { throw .senseCarpeta }"))
        let senseLaCrida = fitxer.text.replacingOccurrences(of: creaCarpetaWarp, with: "")
        let trobades = try aparicions(de: prohibidesCarpetaWarp, a: [(ruta: fitxer.ruta, text: senseLaCrida)])
        #expect(trobades.isEmpty, "\(trobades)")
        #expect(fitxer.text.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW"))
        #expect(try obertures(fitxer.text) == obrenAFitxersLaunchWarp)
        #expect(try canvienAtributs(fitxer.text) == canvienAtributsAFitxersLaunchWarp)
        // I és la del fitxer que `escriu` acaba de crear. A `comencaAmbLaMarca`, el descriptor de només lectura també deixaria
        // canviar els permisos d'un fitxer que ja hi era.
        #expect(permisosDelFitxerAcabatDeCrear(fitxer.text, obre: obrenAFitxersLaunchWarp[0],
                                               permisos: canvienAtributsAFitxersLaunchWarp[0]))
    }

    /// Decisió d'en David del 09/11/2026: els dos fulls d'obrir (una finestra i «Obre-ho tot») i el README avisen de les feines
    /// en segon pla.
    @Test func elsDosFullsAvisenDeLesFeinesEnSegonPla() throws {
        let full = try #require(try fitxers("Sources").first { $0.ruta == "Sources/WarpLaunchUI/FullObertura.swift" })
        // Una línia de codi a cada full, no un comentari: «Obre-ho tot» és abans de `seccions`, i la finestra, a dins.
        let parts = full.text.components(separatedBy: "private func seccions(")
        try #require(parts.count == 2)
        for part in parts {
            #expect(part.split(separator: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("Label(Obertura.textFeinesEnSegonPla")
            }.count == 1)
        }
        let readme = try String(contentsOf: arrel.appending(path: "README.md"), encoding: .utf8)
        #expect(readme.contains("tancar Warp pot deixar-les a mitges, i reobrir les pestanyes no les fa continuar"))
    }

    /// Regla 7 (09/11/2026): la carpeta de Warp només la crea l'app, i només amb el refresc (la carpeta de debò i el permís).
    @Test func nomesLAppCreaLaCarpetaDeWarpAmbElPermis() throws {
        let codi = try fitxers("Sources")
        func llocs(_ text: String) -> [String] { codi.filter { $0.text.contains(text) }.map(\.ruta).sorted() }
        func linies(_ expressio: String) throws -> [String] {
            let reg = try Regex(expressio)
            return codi.flatMap { fitxer in
                fitxer.text.split(separator: "\n").filter {
                    !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && $0.contains(reg)
                }.map { "\(fitxer.ruta): \($0.trimmingCharacters(in: .whitespaces))" }
            }.sorted()
        }
        // Qui demana crear-la: només l'execució, i només amb el que digui qui la crida.
        #expect(try linies(#"creaCarpeta\s*:"#) == [
            "Sources/WarpLaunchCore/ExecucioObertura.swift: _ = try entorn.fitxers.escriu(fitxer, creaCarpeta: entorn.potCrearCarpeta())",
            "Sources/WarpLaunchCore/FitxersLaunchWarp.swift: public func escriu(_ fitxer: FitxerLaunch, creaCarpeta: Bool = false) "
                + "throws(ErrorFitxers) -> Int {",
        ])
        // Qui ho permet: només `Obertura`, amb el permís. Per defecte (el CLI), no.
        #expect(try linies(#"potCrearCarpeta\s*:"#) == [
            "Sources/WarpLaunchCore/ExecucioObertura.swift: potCrearCarpeta: @escaping @MainActor () -> Bool = { false },",
            "Sources/WarpLaunchCore/ExecucioObertura.swift: public var potCrearCarpeta: @MainActor () -> Bool",
            "Sources/WarpLaunchUI/Obertura.swift: potCrearCarpeta: { [consentiment] in consentiment.potCrearCarpetaDeWarp },",
        ])
        #expect(llocs("potCrearCarpetaDeWarp: Bool { estat == .acceptat && refresc != nil }")
            == ["Sources/WarpLaunchUI/ConsentimentRestauracio.swift"])
        // Ningú més no crea carpetes a la de Warp: l'única crida a tot `Sources`, i la ruta no surt de `FitxersLaunchWarp`.
        #expect(try aparicions(de: [cridaMkdir], a: codi) == ["Sources/WarpLaunchCore/FitxersLaunchWarp.swift:"
            + "\(try numeroDeLinia(creaCarpetaWarp, a: codi)): «\(cridaMkdir)»"])
        #expect(try linies(#"(itxers[A-Za-z]*|\.real)\.carpeta(?![A-Za-z0-9_])"#).isEmpty)
        // I `createDirectory` només on ja era, cap a la carpeta de configuració de Warp Launch.
        #expect(try aparicions(de: [#"createDirectory"#], a: codi).map { String($0.split(separator: ":")[0]) }.sorted() == [
            "Sources/WarpLaunchCore/EscripturaAtomica.swift", "Sources/WarpLaunchCore/MagatzemConfiguracio.swift",
            "Sources/WarpLaunchCore/MagatzemConfiguracio.swift",
        ])
    }

    /// Decisió 7 (ronda 6): a tot `Sources`, només dues crides canvien els permisos o els atributs d'un fitxer, cadascuna al seu
    /// lloc i sobre el fitxer que la mateixa funció acaba de crear (`canvienAtributsPermesos`). L'ajust de Warp no en fa servir
    /// cap: els permisos del fitxer nou els posa `EscripturaAtomica.creaFitxerNou`, i els atributs estesos, l'únic `copyfile`
    /// (`nomesLAjustCreaElFitxerDeWarp`).
    @Test func nomesDuesCridesCanvienElsPermisosIElsAtributs() throws {
        let codi = try fitxers("Sources")
        #expect(codi.count > 10, "no s'ha trobat el codi a \(arrel.path)")
        let trobades = try canvienAtributsForaDeLloc(codi)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        #expect(try codi.filter { !(try canvienAtributs($0.text)).isEmpty }.map(\.ruta).sorted()
            == [rutaEscripturaAtomica, rutaFitxersLaunchWarp])
        let escriptura = try #require(codi.first { $0.ruta == rutaEscripturaAtomica }).text
        #expect(try canvienAtributs(escriptura) == canvienAtributsAEscripturaAtomica)
        #expect(permisosDelFitxerAcabatDeCrear(escriptura, obre: obreAEscripturaAtomica, permisos: canvienAtributsAEscripturaAtomica[0]))
        #expect(escriptura.contains("static func creaFitxerNou(_ dades: Data, a url: URL, permisos: Int) throws {\n        \(obreAEscripturaAtomica)\n"))

        // La mostra: una línia de cada família, a qualsevol fitxer, també als de les dues excepcions, surt.
        let mostra = [
            "chmod(r, 0o777)", "Darwin.fchmod(fd, 0o600)", "chmodx_np(r, seguretat)", "let canvia = lchown", "chown(r, 0, 0)",
            "chflags(r, UInt32(UF_IMMUTABLE))", "try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: r)",
            "try url.setResourceValues(valors)", "exchangedata(a, b, 0)", "setxattr(r, nom, valor, mida, 0, 0)",
            "Darwin.fremovexattr(fd, nom, 0)", "setattrlist(r, &llista, &dades, mida, 0)", "utimes(r, nil)", "futimens(fd, &temps)",
            "acl_set_file(r, ACL_TYPE_EXTENDED, acl)", "CFURLSetResourcePropertyForKey(u as CFURL, kCFURLIsHiddenKey, kCFBooleanTrue, nil)",
            "_ = CFURLSetResourcePropertiesForKeys(u as CFURL, valors as CFDictionary, nil)",
        ]
        let altres = [rutaAjustRestauracio, "Sources/WarpLaunchCore/Diagnostic.swift", rutaRefresc, rutaAppPrincipal,
                      "Sources/WarpLaunchCLI/main.swift", "Sources/WarpLaunchObridor/ObreWarp.swift", "Sources/WarpLaunchUI/Altre.swift"]
        for ruta in altres + [rutaEscripturaAtomica, rutaFitxersLaunchWarp] {
            for linia in mostra {
                #expect(try canvienAtributsForaDeLloc([(ruta: ruta, text: linia)]) == ["\(ruta): \(linia)"], "\(ruta): \(linia)")
            }
        }
        // Les dues crides: al seu fitxer, no; a l'altre o a qualsevol altre, sí. La mateixa dues vegades, la segona surt.
        let (atomica, launch) = (canvienAtributsAEscripturaAtomica[0], canvienAtributsAFitxersLaunchWarp[0])
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaEscripturaAtomica, text: atomica)]).isEmpty)
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaFitxersLaunchWarp, text: launch)]).isEmpty)
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaEscripturaAtomica, text: launch)]) == ["\(rutaEscripturaAtomica): \(launch)"])
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaFitxersLaunchWarp, text: atomica)]) == ["\(rutaFitxersLaunchWarp): \(atomica)"])
        for ruta in altres {
            for linia in [atomica, launch] {
                #expect(try canvienAtributsForaDeLloc([(ruta: ruta, text: linia)]) == ["\(ruta): \(linia)"], "\(ruta): \(linia)")
            }
        }
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaEscripturaAtomica, text: atomica + "\n" + atomica)])
            == ["\(rutaEscripturaAtomica): \(atomica)"])
        // Amb el mòdul, amb altres permisos o sense cridar-la, tampoc; una crida que només llegeix i un altre nom, no.
        for altra in ["guard Darwin.fchmod(fd, mode_t(permisos & 0o7777)) == 0 else { throw e }", "guard fchmod(fd, mode_t(permisos)) == 0 else { throw e }",
                      "if fchmod(fd, 0o666) != 0 {", "let canvia = fchmod"] {
            #expect(try canvienAtributsForaDeLloc([(ruta: rutaEscripturaAtomica, text: atomica + "\n" + altra)])
                == ["\(rutaEscripturaAtomica): \(altra)"], "\(altra)")
        }
        #expect(try canvienAtributsForaDeLloc([(ruta: rutaAjustRestauracio, text: """
            let permisos = try FileManager.default.attributesOfItem(atPath: r)[.posixPermissions]
            let mida = getxattr(r, nom, nil, 0, 0, 0)
            copyfile(ruta.path, temporal.path, nil, copyfile_flags_t(COPYFILE_XATTR))
            let chmodBits = 0o644
            """)]).isEmpty)
        // Sobre el fitxer que s'acaba de crear: abans de crear-lo, amb un altre `fd`, en una altra funció o sense l'`open`, no.
        let (obre, crida) = ("let fd = open(r, O_CREAT | O_EXCL)", "fchmod(fd, 0o644)")
        #expect(permisosDelFitxerAcabatDeCrear("\(obre)\nguard fd >= 0 else { return }\n\(crida)", obre: obre, permisos: crida))
        for dolenta in ["\(crida)\n\(obre)", "\(obre)\nlet fd = altre()\n\(crida)", "\(obre)\nfunc altra() {\n\(crida)", crida, obre] {
            #expect(!permisosDelFitxerAcabatDeCrear(dolenta, obre: obre, permisos: crida), "\(dolenta)")
        }
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
        // I la de Sparkle, que hi va inclòs.
        #expect(script.contains(#"cp -X .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/LICENSE-Sparkle""#))
        // Abans de signar: un fitxer afegit després trencaria la signatura.
        let copia = try #require(script.range(of: "LICENSE-Sparkle\"\n"))
        let signa = try #require(script.range(of: #"signa "$FW/Versions/B/Autoupdate""#))
        #expect(copia.lowerBound < signa.lowerBound)
    }

    @Test func elScriptDelPaquetSignaAmbElCertificatPropi() throws {
        // D12: amb el certificat, el permís per llegir Warp no es perd a cada compilació; sense, ad hoc.
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("Warp Launch Dev"))
        #expect(script.contains(#"FIRMA="$IDENTITAT""#))
        #expect(script.contains(#"FIRMA="-""#))
        #expect(script.contains(#"codesign --force --sign "$FIRMA" --timestamp=none "$1""#))
        #expect(!script.contains("--options runtime\"") && !script.contains("--options=runtime"))
    }

    // MARK: - Sparkle (docs/disseny.md, secció 11, 10)

    /// Una signatura de fora tanca les de dins: l'ordre, i la comprovació amb `--deep`, que és la que veu un framework a mig signar.
    @Test func elPaquetSignaDeDinsCapAForaIComprovaAmbDeep() throws {
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        let ordre = [#"signa "$FW/Versions/B/Autoupdate""#, #"signa "$FW/Versions/B/Updater.app""#, #"signa "$FW"\#n"#, #"signa "$APP"\#n"#,
                     #"codesign --verify --deep --strict "$APP""#]
        var darrer = script.startIndex
        for pas in ordre {
            let trobat = try #require(script.range(of: pas, range: darrer..<script.endIndex), "\(pas)")
            darrer = trobat.upperBound
        }
        #expect(script.contains(#"rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices""#))
        #expect(script.contains(#"-Xlinker -rpath -Xlinker "$RPATH""#))
        #expect(script.contains(#"RPATH="@executable_path/../Frameworks""#))
        for fitxer in ["scripts/publica.sh", "scripts/instal·la.sh"] {
            let text = try String(contentsOf: arrel.appending(path: fitxer), encoding: .utf8)
            let verificacions = text.split(separator: "\n").filter { $0.contains("codesign --verify") }
            #expect(!verificacions.isEmpty && verificacions.allSatisfy { $0.contains("--deep --strict") }, "\(fitxer)")
        }
    }

    /// Sparkle només el coneix el servei. Avui, cap altre fitxer de `Sources/` no en té cap nom.
    @Test func sparkleNomesAlServei() throws {
        let codi = try fitxers("Sources")
        let fora = try aparicions(de: nomesAlServei, a: codi.filter { $0.ruta != serveiActualitzacions })
        #expect(fora.isEmpty, "\(fora.joined(separator: "\n"))")
        // Una línia de mostra per expressió: si una no veiés res, la llista buida ho donaria per bo.
        for mostra in ["@preconcurrency import Sparkle", "let a: SPUUpdater", "SUAppcastItem", "SUError.noUpdateError"] {
            let trobades = try aparicions(de: nomesAlServei, a: [(ruta: "mostra", text: mostra)])
            #expect(!trobades.isEmpty, "\(mostra)")
        }
        #expect(try aparicions(de: nomesAlServei, a: [(ruta: "mostra", text: "let situacio: SituacioApp")]).isEmpty)
        let proves = try fitxers("Tests")
        #expect(try aparicions(de: [#"import Sparkle"#], a: proves).isEmpty)
    }

    /// Cap codi propi no parla amb la xarxa, ni la de l'actualitzador: això ho fa Sparkle, amb l'adreça que porta el paquet.
    @Test func capCodiNoFaServirLaXarxa() throws {
        var codi = try fitxers("Sources")
        let i = try #require(codi.firstIndex { $0.ruta == serveiActualitzacions })
        #expect(codi[i].text.components(separatedBy: firmaBaixada).count == 2)
        // El valor no es fa servir: el cos del delegat és només aquesta línia.
        #expect(codi[i].text.contains(firmaBaixada + "\n        model?.rep(.baixant(item.displayVersionString), ara: ara)\n    }"))
        codi[i].text = codi[i].text.replacingOccurrences(of: firmaBaixada, with: "")
        let trobades = try aparicions(de: xarxa, a: codi)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        for mostra in ["URLSession.shared", "URLRequest(url: a)", "NSURLConnection", "import Network", "NWConnection(", "NWPathMonitor()",
                       "import CFNetwork", "WKWebView()", "http://a.b", "https://a.b"] {
            #expect(!(try aparicions(de: xarxa, a: [(ruta: "mostra", text: mostra)])).isEmpty, "\(mostra)")
        }
    }

    /// El que Sparkle deixa canviar per codi i no s'ha de fer: l'adreça, el perfil del sistema, els canals i engegar amb una alerta.
    @Test func elServeiNoFaServirElQueNoToca() throws {
        let servei = try #require(try fitxers("Sources/WarpLaunchApp").first { $0.ruta == serveiActualitzacions })
        #expect(try aparicions(de: prohibitsAlServei, a: [servei]).isEmpty)
        // L'excepció de `launchApplication` només és per al nom del delegat.
        let obrir = [(ruta: serveiActualitzacions, text: "NSWorkspace.shared.launchApplication(x)")]
        #expect(try aparicions(de: prohibidesCodi(a: serveiActualitzacions), a: obrir).contains { $0.contains("launchApplication") })
        let delegat = [(ruta: serveiActualitzacions, text: "func updaterWillRelaunchApplication(_ u: SPUUpdater) {}")]
        #expect(try aparicions(de: prohibidesCodi(a: serveiActualitzacions), a: delegat).isEmpty)
        for mostra in ["u.feedURLString", "u.setFeedURL(a)", "sendsSystemProfile", "allowedChannels", "c.startUpdater()",
                       "func updaterShouldRelaunchApplication(_ u: X) -> Bool", "func updaterShouldPromptForPermissionToCheckForUpdates(_ u: X)",
                       "func feedParameters(for u: X, sendingSystemProfile s: Bool)"] {
            #expect(!(try aparicions(de: prohibitsAlServei, a: [(ruta: "mostra", text: mostra)])).isEmpty, "\(mostra)")
        }
        // Sense cap finestra sense demanar-la: la decisió és una sola línia que torna `false`.
        #expect(servei.text.contains("andInImmediateFocus immediateFocus: Bool) -> Bool {\n        false\n    }"))
        // Els mètodes dels quals depèn la seguretat, comprovats abans d'engegar.
        for selector in ["willInstallUpdateOnQuit:immediateInstallationBlock:", "shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
                         "updaterWillRelaunchApplication(_:)", "updater(_:mayPerform:)", "shouldProceedWithUpdate:updateCheck:",
                         "didAbortWithError:", "standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)"] {
            #expect(servei.text.contains(selector), "\(selector)")
        }
    }

    /// Les accions de l'actualitzador, només al servei. El bloc que instal·la només es crida des del model, que abans escriu l'intent.
    @Test func lesAccionsDeLActualitzadorNomesAlServei() throws {
        let codi = try fitxers("Sources")
        let accions = [#"checkForUpdates"#, #"secondsSinceLastEventType"#]
        let fora = try aparicions(de: accions, a: codi.filter { $0.ruta != serveiActualitzacions })
        #expect(fora.isEmpty, "\(fora.joined(separator: "\n"))")
        let servei = try #require(codi.first { $0.ruta == serveiActualitzacions })
        for accio in ["updater.checkForUpdatesInBackground()", "updater.checkForUpdateInformation()", "updater.checkForUpdates()"] {
            #expect(servei.text.components(separatedBy: accio).count == 2, "\(accio)")
        }
        #expect(servei.text.components(separatedBy: "secondsSinceLastEventType").count == 2)
        // Al servei, `bloc()` només dins de la clausura que es passa al model.
        let blocs = servei.text.split(separator: "\n").filter { $0.contains("bloc()") }
        #expect(blocs.count == 2 && blocs.allSatisfy { $0.contains("aplica: { bloc() })") }, "\(blocs)")
        let model = try #require(codi.first { $0.ruta == "Sources/WarpLaunchUI/Actualitzacions.swift" })
        let despres = model.text.components(separatedBy: "try magatzem.desa(nou)")
        #expect(despres.count == 3 && despres[2].contains("bloc()"), "el bloc, després d'haver escrit l'intent")
    }

    /// La secció, on toca; la versió, només aquí; i el menú, als dos llocs. El text del permís (decisió 7 de Sparkle), a la pantalla.
    @Test func laSeccioIElsMenusDeLActualitzacio() throws {
        let vista = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/VistaConfiguracio.swift"), encoding: .utf8)
        // A la seva pestanya: a «General», passaria dels 640 pt.
        #expect(vista.contains("            case .actualitzacions:\n                seccioActualitzacions\n"))
        #expect(vista.components(separatedBy: "seccioActualitzacions").count == 3)
        #expect(vista.components(separatedBy: #"LabeledContent("Versió""#).count == 2)
        #expect(vista.contains("TabView(selection: $actualitzacions.pestanyaConfiguracio)"))
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        #expect(app.contains("CommandGroup(after: .appInfo) {\n                ItemActualitzacions(aplicacio: aplicacio)\n                    .disabled(!aplicacio.consentiment.potContinuar)"))
        #expect(app.components(separatedBy: "ItemActualitzacions(aplicacio: aplicacio)").count == 3)
        let permis = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchUI/VistaConsentiment.swift"), encoding: .utf8)
        #expect(permis.contains("Text(ConsentimentRestauracio.textActualitzacions)"))
    }

    /// `actualitzacio.json` només amb la configuració de debò (`--config` no el toca mai). La reobertura silenciosa, només per a l'automàtica.
    @Test func lIntentNomesAmbLaConfiguracioDeDebo() throws {
        let codi = try fitxers("Sources")
        let usos = codi.flatMap { f in
            f.text.split(separator: "\n").filter { $0.contains("enArrencar(magatzem") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .map { _ in f.ruta }
        }
        // `public static func` a Core, i la crida de l'app.
        #expect(usos.sorted() == ["Sources/WarpLaunchApp/WarpLaunchApp.swift", "Sources/WarpLaunchCore/IntentActualitzacio.swift"], "\(usos)")
        let app = try #require(codi.first { $0.ruta == "Sources/WarpLaunchApp/WarpLaunchApp.swift" }).text
        #expect(app.contains("if case let .real(carpeta) = arguments.carpeta {\n            let arrencada = IntentActualitzacio.enArrencar(magatzem:"))
        let creen = try aparicions(de: [#"MagatzemIntent\("#], a: codi.filter { $0.ruta.hasPrefix("Sources/WarpLaunchApp/") })
        #expect(creen.count == 2, "\(creen)")
        let servei = try #require(codi.first { $0.ruta == serveiActualitzacions }).text
        #expect(servei.contains("guard case let .real(carpeta) = arguments.carpeta, let feed"))
        // La reobertura: no surt el full de l'inici de sessió, i només l'automàtica no mostra res.
        #expect(app.contains("reobertaPerActualitzacio: aplicacio.reobertura != nil)"))
        #expect(app.contains(".defaultLaunchBehavior(aplicacio.reobertura == .automatica ? .suppressed : .automatic)"))
        #expect(app.contains("if aplicacio.reobertura == .automatica { NSApp.hide(nil) }"))
        #expect(app.contains("enArrencar(silenciosa: aplicacio.reobertura == .automatica)"))
        #expect(app.components(separatedBy: "NSApp.hide(").count == 2)
    }

    /// Una sola dependència, amb la versió exacta, i només per a l'app (regla 10).
    @Test func sparkleEsLUnicaDependenciaINomesDeLApp() throws {
        let paquet = try String(contentsOf: arrel.appending(path: "Package.swift"), encoding: .utf8)
        let linies = paquet.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(linies.filter { $0.contains(".package(") } == [
            #".package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),"#,
        ])
        #expect(paquet.components(separatedBy: #".product(name: "Sparkle""#).count == 2)
        let inici = try #require(paquet.range(of: #".executableTarget(name: "WarpLaunchApp""#))
        let producte = try #require(paquet.range(of: #".product(name: "Sparkle""#))
        let seguent = try #require(paquet.range(of: ".executableTarget(", range: inici.upperBound..<paquet.endIndex))
        #expect(inici.upperBound < producte.lowerBound && producte.upperBound < seguent.lowerBound)
        // `Package.resolved` és al repo: sense, l'arbre quedaria brut, i `publica.sh` no publicaria.
        let resolt = try String(contentsOf: arrel.appending(path: "Package.resolved"), encoding: .utf8)
        #expect(resolt.contains(#""version" : "2.10.1""#) && resolt.contains("ab7d71291238df6e0492143b120c9b696a35f603"))
    }

    /// El que porta tota còpia, publicada o no. La decisió 1 de Sparkle no es pot activar després per a les còpies que ja corren.
    @Test func lInfoPlistPortaLesClausDeLActualitzacio() throws {
        let dades = try Data(contentsOf: arrel.appending(path: "Recursos/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: dades, format: nil) as? [String: Any])
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(plist["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        for absent in ["SUEnableSystemProfiling", "SUFeedURL", "SUPublicEDKey", "SUEnableInstallerLauncherService"] {
            #expect(plist[absent] == nil, "\(absent)")
        }
    }

    /// Fins que l'autor no ha creat la clau (pas 11), cap còpia no pot portar l'adreça ni la clau pública.
    @Test func lesAdrecesDeLActualitzacioEncaraNoHiSon() {
        #expect(!FileManager.default.fileExists(atPath: arrel.appending(path: "Recursos/Actualitzacions.plist").path))
    }

    /// Decisió 3 de Sparkle: només les còpies per publicar porten l'adreça.
    @Test func lAdrecaNomesAmbAmbFeed() throws {
        let script = try String(contentsOf: arrel.appending(path: "scripts/build-app.sh"), encoding: .utf8)
        #expect(script.components(separatedBy: "PlistBuddy").count == 2)
        let branca = try #require(script.range(of: #"if [[ "$AMB_FEED" -eq 1 ]]; then\#n    /usr/libexec/PlistBuddy -c "Merge $FEED" "$APP/Contents/Info.plist" > /dev/null\#nfi"#))
        #expect(!branca.isEmpty)
        // Cap script no el passa, llevat de `publica.sh`, que és el que publica.
        let scripts = try FileManager.default.contentsOfDirectory(at: arrel.appending(path: "scripts"), includingPropertiesForKeys: nil)
        for fitxer in scripts where !["build-app.sh", "publica.sh"].contains(fitxer.lastPathComponent) && fitxer.pathExtension == "sh" {
            #expect(!(try String(contentsOf: fitxer, encoding: .utf8)).contains("--amb-feed"), "\(fitxer.lastPathComponent)")
        }
        let publica = try String(contentsOf: arrel.appending(path: "scripts/publica.sh"), encoding: .utf8)
        #expect(publica.contains("env -u GH_TOKEN -u GITHUB_TOKEN scripts/build-app.sh release --amb-feed\n"))
    }

    /// Cap script no pot crear ni mostrar la clau de signar les versions, i només `publica.sh` signa: sempre amb la clau del clauer, mai amb un fitxer
    /// o un valor passat per arguments. Com que la crida porta la variable (`$SIGN_UPDATE`), les línies es miren sense distingir majúscules.
    private func usDeLaClauForaDeLloc(_ fitxers: [(ruta: String, text: String)]) throws -> [String] {
        let opcioDeClau = try Regex(#"(?:^|[\s"'])-[sfx]|--ed-key-file"#)
        var trobades: [String] = []
        for fitxer in fitxers {
            for (numero, linia) in fitxer.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let minuscules = linia.lowercased()
                for prohibida in ["generate_keys", "generate_appcast", "find-generic-password", "dump-keychain", "sparkle-project.org"] where minuscules.contains(prohibida) {
                    trobades.append("\(fitxer.ruta):\(numero + 1): \(prohibida)")
                }
                guard minuscules.contains("sign_update") else { continue }
                if fitxer.ruta != "scripts/publica.sh" { trobades.append("\(fitxer.ruta):\(numero + 1): sign_update") }
                if linia.contains(opcioDeClau) { trobades.append("\(fitxer.ruta):\(numero + 1): opció de clau") }
            }
        }
        return trobades
    }

    @Test func laClauDeSignarNoEsToca() throws {
        let carpeta = arrel.appending(path: "scripts")
        let noms = try FileManager.default.contentsOfDirectory(atPath: carpeta.path).sorted()
        #expect(noms.contains("publica.sh") && noms.contains("verifica-signatura.swift"), "\(noms)")
        let scripts = try noms.map { (ruta: "scripts/\($0)", text: try String(contentsOf: carpeta.appending(path: $0), encoding: .utf8)) }
        let trobades = try usDeLaClauForaDeLloc(scripts)
        #expect(trobades.isEmpty, "\(trobades.joined(separator: "\n"))")
        // Una sola crida, d'una sola línia, amb el zip i res més: una opció a la línia següent no la veuria la comprovació de sobre.
        let publica = try #require(scripts.first { $0.ruta == "scripts/publica.sh" }).text
        #expect(publica.components(separatedBy: #""$SIGN_UPDATE""#).count == 2)
        #expect(publica.contains(#"env -u GH_TOKEN -u GITHUB_TOKEN "$SIGN_UPDATE" "$ZIP")"; then"#))
        // Línies de mostra, perquè una expressió que no veiés res no ho doni per bo.
        for ruta in noms.map({ "scripts/\($0)" }) {
            #expect(try usDeLaClauForaDeLloc([(ruta: ruta, text: ".build/artifacts/sparkle/Sparkle/bin/generate_keys")]).count == 1, "\(ruta)")
            #expect(try usDeLaClauForaDeLloc([(ruta: ruta, text: "generate_keys -x clau")]).count == 1, "\(ruta)")
            for dolenta in [".build/artifacts/sparkle/Sparkle/bin/generate_appcast build", "security find-generic-password -s x -w", "security dump-keychain -d", #"-s "https://sparkle-project.org""#] {
                #expect(try usDeLaClauForaDeLloc([(ruta: ruta, text: dolenta)]).count == 1, "\(ruta): \(dolenta)")
            }
        }
        for ruta in noms.map({ "scripts/\($0)" }) where ruta != "scripts/publica.sh" {
            #expect(try usDeLaClauForaDeLloc([(ruta: ruta, text: #"sign_update "$ZIP""#)]) == ["\(ruta):1: sign_update"], "\(ruta)")
        }
        for dolenta in [#"sign_update -f clau "$ZIP""#, #"sign_update -s "$CLAU" "$ZIP""#, #""$SIGN_UPDATE" --ed-key-file clau "$ZIP""#,
                        #""$SIGN_UPDATE" "-f" clau "$ZIP""#, #"SIGN_UPDATE="$X" -fclau"#] {
            #expect(try usDeLaClauForaDeLloc([(ruta: "scripts/publica.sh", text: dolenta)]) == ["scripts/publica.sh:1: opció de clau"], "\(dolenta)")
        }
        for bona in [#"env "$SIGN_UPDATE" "$ZIP""#, #"SIGN_UPDATE="${WARP_LAUNCH_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}""#] {
            #expect(try usDeLaClauForaDeLloc([(ruta: "scripts/publica.sh", text: bona)]).isEmpty, "\(bona)")
        }
    }

    /// Decisions 6 i 13 de Sparkle: cap agent no crea ni fa servir la clau, ni publica. Les regles `deny` es compleixen fins i tot saltant els permisos.
    @Test func capAgentNoPotSignarNiPublicar() throws {
        let dades = try Data(contentsOf: arrel.appending(path: ".claude/settings.json"))
        let arbre = try #require(try JSONSerialization.jsonObject(with: dades) as? [String: Any])
        let permisos = try #require(arbre["permissions"] as? [String: Any])
        let deny = try #require(permisos["deny"] as? [String])
        for regla in ["Bash(generate_keys*)", "Bash(*/generate_keys*)", "Bash(sign_update*)", "Bash(*/sign_update*)", "Bash(*publica.sh*--aplica*)",
                      "Bash(*generate_appcast*)", "Bash(*Sparkle/bin/*)"] {
            #expect(deny.contains(regla), "\(regla)")
        }
        // Com les aplica Claude Code: l'asterisc val per a qualsevol text, i la regla ha de cobrir tota l'ordre.
        let patrons = try deny.filter { $0.hasPrefix("Bash(") }.map { regla in
            try Regex("^" + regla.dropFirst(5).dropLast().split(separator: "*", omittingEmptySubsequences: false).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: ".*") + "$")
        }
        let bloqueja = { (ordre: String) in patrons.contains { ordre.wholeMatch(of: $0) != nil } }
        let bin = ".build/artifacts/sparkle/Sparkle/bin"
        for ordre in [
            "scripts/publica.sh --aplica", "./scripts/publica.sh --aplica", "bash scripts/publica.sh --aplica", #"GH_TOKEN="x" scripts/publica.sh --aplica"#,
            "scripts/publica.sh  --aplica", "scripts/publica.sh\t--aplica", #"scripts/publica.sh "--aplica""#, #""scripts/publica.sh" --aplica"#, "cd scripts && ./publica.sh --aplica",
            "sign_update x.zip", "\(bin)/sign_update x.zip", "./sign_update x.zip", "env -u GH_TOKEN \(bin)/sign_update x.zip", "env sign_update x.zip", "command sign_update x.zip",
            "exec sign_update x.zip", "PATH=\(bin):$PATH sign_update x.zip", "\(bin)/sign_up* x.zip", #""\#(bin)/sign_update" x.zip"#,
            "generate_keys", "generate_keys -x clau", "\(bin)/generate_keys", "./generate_keys -p", "env generate_keys", "command generate_keys", "exec generate_keys",
            "PATH=\(bin):$PATH generate_keys", "\(bin)/generate_appcast carpeta", "generate_appcast carpeta",
        ] {
            #expect(bloqueja(ordre), "\(ordre)")
        }
        // El que fa cada dia qualsevol agent ha de continuar passant.
        for ordre in ["scripts/publica.sh", "GH_TOKEN=x scripts/publica.sh", "scripts/test.sh", "swift build", "scripts/build-app.sh release", "grep -n sign_update scripts/publica.sh"] {
            #expect(!bloqueja(ordre), "\(ordre)")
        }
    }

    /// Sense `--amb-feed` no hi ha res a demanar; amb, el que falta s'atura abans de compilar. Els arguments, sense compilar res.
    @Test func elsArgumentsDelPaquet() throws {
        let script = arrel.appending(path: "scripts/build-app.sh")
        let camins = ["PATH": "/usr/bin:/bin"]
        for dolent in [["provatura"], ["--amb-fed"], ["release", "debug"]] {
            let (codi, sortida) = try executaScript(script, dolent, entorn: camins)
            #expect(codi == 64, "\(dolent): \(sortida)")
        }
        let (codi, sortida) = try executaScript(script, ["release", "--amb-feed"],
                                                entorn: camins.merging(["WARP_LAUNCH_IDENTITAT": "Prova"]) { _, nou in nou })
        #expect(codi == 1 && sortida.contains("no accepta WARP_LAUNCH_IDENTITAT"), "\(sortida)")
    }

    /// L'XML no admet dos guions dins d'un comentari. Els lectors d'Apple ho deixen passar; un de més estricte refusaria la plantilla del paquet.
    @Test func elsComentarisDeLInfoPlistSonXMLValid() throws {
        let text = try String(contentsOf: arrel.appending(path: "Recursos/Info.plist"), encoding: .utf8)
        let comentaris = text.components(separatedBy: "<!--").dropFirst().map { $0.components(separatedBy: "-->")[0] }
        #expect(!comentaris.isEmpty)
        #expect(comentaris.allSatisfy { !$0.contains("--") }, "\(comentaris.filter { $0.contains("--") })")
    }

    /// Abans del permís, cap connexió: l'actualitzador només s'engega des de `enContinuar`, i cada comprovació torna a mirar el permís
    /// (el de debò, que es pot retirar amb l'app oberta).
    @Test func lActualitzadorNomesSEngegaAmbElPermis() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        #expect(app.contains("aplicacio.consentiment.enContinuar {\n            aplicacio.servei?.engega()\n"))
        #expect(app.components(separatedBy: ".engega()").count == 2)
        #expect(app.contains("permis: { consentiment.potContinuar }, models:"))
        let servei = try #require(try fitxers("Sources/WarpLaunchApp").first { $0.ruta == serveiActualitzacions }).text
        #expect(servei.contains("SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)"))
        #expect(!servei.contains("startingUpdater: true"))
        #expect(servei.components(separatedBy: "SPUStandardUpdaterController(").count == 2)
        #expect(servei.contains("func engega() {\n        do {\n            try updater.start()\n"))
        #expect(servei.components(separatedBy: "updater.start()").count == 2)
        #expect(servei.contains("mayPerform updateCheck: SPUUpdateCheck) throws {\n        guard permis() else {"))
    }

    /// El que decideix si una versió s'accepta i qui la instal·la. L'appcast no va signat: aquests camps podrien obrir finestres i enllaços.
    @Test func elsDelegatsQueDecideixen() throws {
        let servei = try #require(try fitxers("Sources/WarpLaunchApp").first { $0.ruta == serveiActualitzacions }).text
        #expect(servei.contains("guard !item.isInformationOnlyUpdate, !item.isCriticalUpdate, !item.isMajorUpgrade, let fitxer,\n"
            + "              PoliticaActualitzacions.enclosureValid(feed: feed, enclosure: fitxer) else {\n            throw "))
        // Amb `false`, l'actualitzador continua sol i el model no rep el bloc.
        #expect(servei.contains("immediateInstallationBlock bloc: @escaping () -> Void) -> Bool {\n"
            + "        model?.rep(.aPunt(item.displayVersionString, aplica: { bloc() }), ara: ara)\n        return true\n    }"))
        #expect(servei.contains("guard !handleShowingUpdate else { return }"))
    }

    /// El reinici surt per `applicationShouldTerminate`: desa, atura el refresc i no surt amb l'ajust de Warp a mig desactivar.
    @Test func elReiniciSurtPelTancamentDeSempre() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        let inici = try #require(app.range(of: "func applicationShouldTerminate("))
        var darrer = inici.upperBound
        for pas in ["aplicacio.editor.acabaNom(desant: true)", "aplicacio.refresc?.atura()", "if aplicacio.editor.desaSiCal() {",
                    "aplicacio.obertura?.enSortir()", "return surtAmbLAjustDesactivat()"] {
            let trobat = try #require(app.range(of: pas, range: darrer..<app.endIndex), "\(pas)")
            darrer = trobat.upperBound
        }
        #expect(app.contains("guard let refresc = aplicacio.refresc, refresc.pendent == .acabaDeCanviar else { return .terminateNow }"))
        #expect(app.contains("await refresc.acabaDeDesactivar()\n            NSApp.reply(toApplicationShouldTerminate: true)"))
        #expect(app.contains("aplicacio.refresc?.repren()\n            return .terminateCancel"))
    }

    /// Cada motiu per no reiniciar ha de sortir del model que el sap: una dada mal connectada compila, i l'app es reiniciaria igual.
    @Test func elsMotiusDeEsperaSurtenDelsModelsDeDebo() throws {
        let app = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/WarpLaunchApp.swift"), encoding: .utf8)
        for connexio in ["errorEnDesar: editor.errorDesat != nil", "nomAMigEscriure: editor.nomEnEdicio != nil", "obrint: obertura?.estaObrint == true",
                         "fullObert: obertura?.mostraFull == true || lligam?.mostraFull == true || desinstallacio.confirmant",
                         "|| editor.demanaImportacio || editor.demanaNovaPestanya || activacio.hiHaFullObert",
                         "conversesEnCurs: obertura?.teConversesEnCurs == true", "refrescant: consentiment.refresc?.refrescant == true",
                         "ajustPerDesactivar: consentiment.refresc?.pendent == .acabaDeCanviar", "finestraVisible: activacio.hiHaFinestraVisible",
                         "canvisSenseDesar: editor.canvisSenseDesar", "potDesfer: editor.undoManager.canUndo || editor.desferPlantilla.canUndo",
                         "segonsDesDelDarrerCanvi: editor.darrerCanvi.map { Date().timeIntervalSince($0) }",
                         "actualitzacions.vigila(ara: ProcessInfo.processInfo.systemUptime)",
                         "obertura?.aplicantActualitzacio = { actualitzacions.aplicant }"] {
            #expect(app.contains(connexio), "\(connexio)")
        }
        // El diagnòstic demana el text al fil principal: només des del fil on corre `CopiaDiagnostic`, o es bloquejaria.
        let codi = try fitxers("Sources")
        #expect(try aparicions(de: [#"DispatchQueue\.main\.sync"#], a: codi).count == 1)
        let copia = try #require(codi.first { $0.ruta == "Sources/WarpLaunchUI/CopiaDiagnostic.swift" }).text
        #expect(copia.contains("await Task.detached { diagnostic(anonimitzat) }.value"))
    }

    /// Una finestra minimitzada continua oberta, i una app amagada per la reobertura silenciosa ha de tornar a mostrar el que s'obri.
    @Test func lesFinestresOcultesNoEnganyenLActualitzacio() throws {
        let activacio = try String(contentsOf: arrel.appending(path: "Sources/WarpLaunchApp/Activacio.swift"), encoding: .utf8)
        #expect(activacio.contains("var hiHaFinestraVisible: Bool {\n        NSApp.windows.contains { ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled) }"))
        let mostra = try #require(activacio.range(of: "func posaAlDavant() {"))
        let unhide = try #require(activacio.range(of: "if NSApp.isHidden { NSApp.unhide(nil) }"))
        let activa = try #require(activacio.range(of: "NSApp.activate()", range: mostra.upperBound..<activacio.endIndex))
        #expect(mostra.upperBound < unhide.lowerBound && unhide.upperBound < activa.lowerBound)
    }
}
