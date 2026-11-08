import Foundation
import Testing
@testable import WarpLaunchCore

// On és Warp (D-P12, 0.29.2): Warp Stable en qualsevol carpeta, i Warp Preview, que encara no és compatible. macOS no hi
// és: `cerca` és falsa, els paquets són carpetes temporals amb el seu `Info.plist`, i els processos, inventats.

/// Un paquet d'app amb el seu `Info.plist`, a `ruta` dins de la carpeta temporal.
private func paquet(_ tmp: CarpetaTemporal, _ ruta: String, id: String, executable: String?,
                    versio: String? = nil) throws -> URL {
    let url = URL(filePath: try tmp.carpeta(ruta), directoryHint: .isDirectory)
    try tmp.carpeta(ruta + "/Contents/MacOS")
    var info: [String: Any] = ["CFBundleIdentifier": id]
    if let executable { info["CFBundleExecutable"] = executable }
    if let versio { info["CFBundleShortVersionString"] = versio }
    let dades = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try dades.write(to: url.appending(path: "Contents/Info.plist"))
    return url
}

/// Una `cerca` que coneix aquestes apps, i apunta què se li demana.
private final class CercaFalsa: @unchecked Sendable {
    var apps: [String: URL]
    var demanades: [String] = []

    init(_ apps: [String: URL] = [:]) { self.apps = apps }

    func cerca(_ identificador: String) -> URL? {
        demanades.append(identificador)
        return apps[identificador]
    }
}

/// L'app de Warp d'aquest binari (sense arguments, pid `pid`) i el seu `terminal-server`, amb un shell.
private func ambWarp(_ executable: String, pid: Int32 = 40, a processos: inout ProcessosFalsos) {
    processos.processos[pid] = (InfoProces(executable: executable, argv: [executable]), 1)
    processos.processos[pid + 10] = (InfoProces(executable: executable,
                                                argv: [executable, "terminal-server", "--parent-pid=\(pid)"]), pid)
    processos.processos[pid + 11] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), pid + 10)
}

@Suite struct InstallacioWarpTests {
    /// Warp Stable a `~/Applications`: és el que diu macOS, i el binari surt del seu `Info.plist`.
    @Test func trobaWarpStableEnUnaAltraCarpeta() throws {
        let tmp = try CarpetaTemporal()
        let stable = try paquet(tmp, "inici/Applications/Warp.app", id: AppWarp.identificador, executable: "stable",
                                versio: "0.2026.11.04.08.17.01")
        let cerca = CercaFalsa([AppWarp.identificador: stable])
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca)
        #expect(warp == InstallacioWarp(app: AppWarp(url: stable), executable: tmp.ruta + "/inici/Applications/Warp.app/Contents/MacOS/stable",
                                        hiHaStable: true))
        #expect(warp.app.versio == "0.2026.11.04.08.17.01")
        #expect(cerca.demanades == ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"], "només els dos de Warp")
    }

    /// El nom del binari és el que diu el paquet, no un de fix.
    @Test func elBinariSurtDelPaquet() throws {
        let tmp = try CarpetaTemporal()
        let stable = try paquet(tmp, "Apps/Warp nou.app", id: AppWarp.identificador, executable: "warp-stable")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificador: stable]).cerca)
        #expect(warp.executable == tmp.ruta + "/Apps/Warp nou.app/Contents/MacOS/warp-stable")
        // Un `CFBundleExecutable` que no és un nom de fitxer no compta: el de sempre.
        let estrany = try paquet(tmp, "Apps/Estrany.app", id: AppWarp.identificador, executable: "../../bin/sh")
        #expect(AppWarp(url: estrany).executable == nil)
        #expect(InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                      cerca: CercaFalsa([AppWarp.identificador: estrany]).cerca).executable
            == tmp.ruta + "/Apps/Estrany.app/Contents/MacOS/stable")
    }

    /// Si macOS no en sap res, o diu una carpeta on ja no hi és, o que no és Warp Stable, es mira a Aplicacions, com fins
    /// a la 0.29.1.
    @Test func sinoLaDAplicacions() throws {
        let tmp = try CarpetaTemporal()
        _ = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let esborrada = tmp.url("Antiga/Warp.app")
        let altra = try paquet(tmp, "Altres/Warp.app", id: "dev.warp.Warp-Dev", executable: "dev")
        for trobada in [nil, esborrada, altra] {
            let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                             cerca: CercaFalsa(trobada.map { [AppWarp.identificador: $0] } ?? [:]).cerca)
            #expect(warp == InstallacioWarp(app: AppWarp(url: tmp.url("Applications/Warp.app")),
                                            executable: tmp.ruta + "/Applications/Warp.app/Contents/MacOS/stable",
                                            hiHaStable: true), "\(trobada?.path ?? "res")")
        }
    }

    /// Una còpia a la Paperera (la de l'usuari o la d'un altre disc) no és cap Warp instal·lat, encara que macOS la doni:
    /// es mira a Aplicacions, i si tampoc n'hi ha, no hi ha Warp Stable. Amb Warp Preview, igual.
    @Test func laPapereraNoCompta() throws {
        let tmp = try CarpetaTemporal()
        let paperera = try paquet(tmp, "inici/.Trash/Warp.app", id: AppWarp.identificador, executable: "stable")
        let disc = try paquet(tmp, "Volumes/Disc/.Trashes/501/Warp.app", id: AppWarp.identificador, executable: "stable")
        let preview = try paquet(tmp, "inici/.Trash/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "preview")
        for trobada in [paperera, disc] {
            let cerca = CercaFalsa([AppWarp.identificador: trobada, AppWarp.identificadorPreview: preview]).cerca
            let sense = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca)
            #expect(sense == InstallacioWarp(app: AppWarp(url: tmp.url("Applications/Warp.app")),
                                             executable: tmp.ruta + "/Applications/Warp.app/Contents/MacOS/stable",
                                             hiHaStable: false), "\(trobada.path)")
            #expect(sense.preview(ProcessosFalsos(), stableObert: false) == .capWarp,
                    "Warp Preview a la Paperera no compta: no hi ha cap Warp")
        }
        // Amb Warp a Aplicacions, és aquest.
        _ = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificador: paperera]).cerca)
        #expect(warp.hiHaStable && warp.app == AppWarp(url: tmp.url("Applications/Warp.app")))
        // Una carpeta que només s'hi assembla sí que compta.
        let semblant = try paquet(tmp, "inici/Trash/.Trash-no/Warp.app", id: AppWarp.identificador, executable: "stable")
        #expect(InstallacioWarp.troba(aplicacions: tmp.url("Res/Warp.app"),
                                      cerca: CercaFalsa([AppWarp.identificador: semblant]).cerca).app == AppWarp(url: semblant))
    }

    /// Cap Warp: ni el diu macOS ni n'hi ha a Aplicacions. Obrir res fallaria, i el binari és el de sempre (no n'hi ha cap).
    /// Des de la 0.31.1, ho diu (abans, res a dir: el full proposava obrir Warp i fallava en confirmar).
    @Test func capWarp() throws {
        let tmp = try CarpetaTemporal()
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: CercaFalsa().cerca)
        #expect(warp == InstallacioWarp(app: AppWarp(url: tmp.url("Applications/Warp.app")),
                                        executable: tmp.ruta + "/Applications/Warp.app/Contents/MacOS/stable", hiHaStable: false))
        #expect(!warp.app.esWarp)
        #expect(warp.preview(ProcessosFalsos(), stableObert: false) == .capWarp)
    }

    /// Només Warp Preview: no hi ha Stable, i l'app ho diu, obert o no.
    @Test func nomesPreview() throws {
        let tmp = try CarpetaTemporal()
        let preview = try paquet(tmp, "Applications/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "preview")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificadorPreview: preview]).cerca)
        let binari = tmp.ruta + "/Applications/WarpPreview.app/Contents/MacOS/preview"
        #expect(!warp.hiHaStable)
        #expect(warp.executablePreview == binari)
        var processos = ProcessosFalsos()
        #expect(warp.preview(processos, stableObert: false) == .nomesPreview)
        ambWarp(binari, a: &processos)
        #expect(warp.preview(processos, stableObert: false) == .nomesPreview)
        // Warp Preview no és Warp Stable: ni obert, ni els seus terminals.
        #expect(!processos.warpObert(executable: warp.executable))
        #expect(processos.terminalsDeWarp(executable: warp.executable).isEmpty)
        // Un paquet que macOS dona per Preview però que no ho és: com si no n'hi hagués.
        let fals = try paquet(tmp, "Altres/WarpPreview.app", id: AppWarp.identificador, executable: "stable")
        #expect(InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                      cerca: CercaFalsa([AppWarp.identificadorPreview: fals]).cerca).executablePreview == nil)
    }

    /// Amb tots dos instal·lats: Warp Preview obert i Warp Stable no, ho diu; amb tots dos oberts, o només Stable, res.
    @Test func previewObertISenseStable() throws {
        let tmp = try CarpetaTemporal()
        let stable = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let preview = try paquet(tmp, "Applications/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "preview")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificador: stable, AppWarp.identificadorPreview: preview]).cerca)
        let binariPreview = try #require(warp.executablePreview)
        var nomesPreview = ProcessosFalsos()
        ambWarp(binariPreview, a: &nomesPreview)
        #expect(warp.preview(ProcessosFalsos(), stableObert: false) == nil, "Preview tancat")
        #expect(warp.preview(nomesPreview, stableObert: false) == .obert)
        #expect(warp.preview(nomesPreview, stableObert: true) == nil, "amb Stable obert, l'app fa servir Stable")
        // El `terminal-server` de Preview, o el seu CLI, no són Preview obert.
        var servidor = ProcessosFalsos()
        ambWarp(binariPreview, a: &servidor)
        servidor.processos[40] = nil
        servidor.processos[60] = (InfoProces(executable: binariPreview, argv: [binariPreview, "--help"]), 1)
        #expect(warp.preview(servidor, stableObert: false) == nil)
    }

    /// El text que surt a l'app i al CLI.
    @Test func elText() {
        #expect(WarpPreview.noCompatible == "Warp Preview encara no és compatible: cal Warp Stable.")
        for preview in [WarpPreview.nomesPreview, .obert] {
            #expect(preview.text.hasPrefix("Warp Preview encara no és compatible: cal Warp Stable. "))
        }
        #expect(WarpPreview.capWarp.text == "No s'ha trobat Warp en aquest Mac: cal Warp Stable.")
    }

    /// La instal·lació per omissió (la de les proves) és la de sempre, i és el binari dels processos de prova.
    @Test func laDeSempre() {
        #expect(InstallacioWarp.perOmissio.executable == "/Applications/Warp.app/Contents/MacOS/stable")
        #expect(InstallacioWarp.perOmissio.executable == ProcessosFalsos.executableWarp)
        #expect(InstallacioWarp.perOmissio.hiHaStable && InstallacioWarp.perOmissio.executablePreview == nil)
    }
}

@Suite struct WarpEnUnaAltraCarpetaTests {
    /// Warp a `~/Applications`: és obert, i se'n veuen els terminals. Una còpia a Aplicacions (la ruta fixa d'abans) no
    /// compta: no és la que s'obriria.
    @Test func elsProcessosDelWarpTrobat() throws {
        let tmp = try CarpetaTemporal()
        let stable = try paquet(tmp, "inici/Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificador: stable]).cerca)
        var processos = ProcessosFalsos()
        ambWarp(warp.executable, a: &processos)
        #expect(processos.warpObert(executable: warp.executable))
        #expect(processos.terminalsDeWarp(executable: warp.executable) == [TerminalViu(pid: 51)])
        #expect(!processos.warpObert(executable: ProcessosFalsos.executableWarp))
        #expect(processos.terminalsDeWarp(executable: ProcessosFalsos.executableWarp).isEmpty)
        #expect(!ProcessosFalsos.ambWarp().warpObert(executable: warp.executable))
        #expect(ProcessosFalsos.ambWarp().terminalsDeWarp(executable: warp.executable).isEmpty)
    }

    /// Des de quan és obert Warp (ronda 5): quan va arrencar l'app de Warp (el procés sense arguments), la més antiga si n'hi
    /// ha més d'una. El `terminal-server` no compta, ni un altre Warp. Tancat, o sense saber quan va arrencar, `nil`.
    @Test func desDeQuanEsObertWarp() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        var processos = ProcessosFalsos.ambWarp()
        let warp = ProcessosFalsos.executableWarp
        #expect(processos.warpObertDes(executable: warp) == nil, "no se sap quan va arrencar")
        processos.arrencades = [40: t, 50: t - 100, 60: t - 200]
        #expect(processos.warpObertDes(executable: warp) == t)
        #expect(processos.warpObertDes(executable: "/Users/prova/Applications/Warp.app/Contents/MacOS/stable") == nil)
        processos.processos[41] = (InfoProces(executable: warp, argv: [warp]), 1)
        processos.arrencades[41] = t + 5
        #expect(processos.warpObertDes(executable: warp) == t)
        processos.processos[40] = nil
        processos.processos[41] = nil
        #expect(!processos.warpObert(executable: warp))
        #expect(processos.warpObertDes(executable: warp) == nil, "tancat")
    }

    /// El lector fa servir el Warp que li diuen, a cada lectura.
    @Test func elLectorElMiraACadaLectura() throws {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        try tmp.carpeta("sessions")
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        let stable = try paquet(tmp, "inici/Applications/Warp.app", id: AppWarp.identificador, executable: "stable",
                                versio: "0.2026.11.04.08.17.01")
        let cerca = CercaFalsa()
        var lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                            carpetaSessions: tmp.url("sessions"), processos: ProcessosFalsos(),
                            warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca) },
                            inici: inici)
        // Encara no s'ha instal·lat: no hi ha Warp, ni en corre cap.
        let abans = try lector.llegeix()
        #expect(abans.warpObert == false && abans.terminals.isEmpty && abans.warpPreview == .capWarp)
        #expect(!lector.warpObert() && lector.installacio().app.versio == nil)
        // Instal·lat a `~/Applications`: la lectura següent ja el veu, tancat.
        cerca.apps[AppWarp.identificador] = stable
        let installat = try lector.llegeix()
        #expect(installat.warpObert == false && installat.warpPreview == nil)
        #expect(lector.installacio().app.versio == "0.2026.11.04.08.17.01")
        // I obert, amb un terminal.
        var processos = ProcessosFalsos()
        ambWarp(stable.appending(path: "Contents/MacOS/stable").path, a: &processos)
        lector.processos = processos
        let despres = try lector.llegeix()
        #expect(despres.warpObert == true)
        #expect(despres.terminals == [TerminalViu(pid: 51)])
        #expect(lector.warpObert())
        // Des de quan, el del Warp que corre (ronda 5).
        #expect(lector.warpObertDes() == nil)
        processos.arrencades[40] = Date(timeIntervalSince1970: 1_800_000_000)
        lector.processos = processos
        #expect(lector.warpObertDes() == Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// La lectura diu si Warp Preview no deixa obrir res, i `llegeix` també ho diu, en text i en JSON.
    @Test func laLecturaHoDiu() throws {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        try tmp.carpeta("sessions")
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        let stable = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let preview = try paquet(tmp, "Applications/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "preview")
        let cerca = CercaFalsa([AppWarp.identificador: stable, AppWarp.identificadorPreview: preview])
        var processos = ProcessosFalsos()
        ambWarp(preview.appending(path: "Contents/MacOS/preview").path, a: &processos)
        var lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                            carpetaSessions: tmp.url("sessions"), processos: processos,
                            warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca) },
                            inici: inici)
        let lectura = try lector.llegeix()
        #expect(lectura.warpObert == false)
        #expect(lectura.warpPreview == .obert)
        let text = Informe.text(lectura, inici: inici)
        #expect(text.contains("Warp és tancat.\n⚠ Warp Preview encara no és compatible: cal Warp Stable. Ara és obert Warp Preview"),
                "\(text)")
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        let json = try codificador.encode(lectura)
        #expect(String(decoding: json, as: UTF8.self).contains(#""warpPreview":"obert""#))
        let descodificador = JSONDecoder()
        descodificador.dateDecodingStrategy = .iso8601
        #expect(try descodificador.decode(LecturaWarp.self, from: json) == lectura)

        // Amb Warp Stable obert també, res a dir.
        ambWarp(stable.appending(path: "Contents/MacOS/stable").path, pid: 80, a: &processos)
        lector.processos = processos
        let totsDos = try lector.llegeix()
        #expect(totsDos.warpObert == true && totsDos.warpPreview == nil)
        #expect(!Informe.text(totsDos, inici: inici).contains("Preview"))

        // Sense Warp Stable: només Preview.
        cerca.apps[AppWarp.identificador] = nil
        lector.warp = { InstallacioWarp.troba(aplicacions: tmp.url("Res/Warp.app"), cerca: cerca.cerca) }
        processos.processos = processos.processos.filter { $0.key < 80 }
        lector.processos = processos
        #expect(try lector.llegeix().warpPreview == .nomesPreview)
        // Si macOS no en sap res però Warp Stable corre, és aquell (decisió 4, 0.31.1): res a dir.
        ambWarp(stable.appending(path: "Contents/MacOS/stable").path, pid: 80, a: &processos)
        lector.processos = processos
        let corre = try lector.llegeix()
        #expect(corre.warpObert == true && corre.warpPreview == nil)
    }

    /// Sense cap Warp (0.31.1), la lectura ho diu, i `llegeix` també, en text i en JSON. Una còpia que corre a la Paperera
    /// no hi canvia res.
    @Test func senseCapWarpLaLecturaHoDiu() throws {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        try tmp.carpeta("sessions")
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        let paperera = try paquet(tmp, "inici/.Trash/Warp.app", id: AppWarp.identificador, executable: "stable")
        var lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                            carpetaSessions: tmp.url("sessions"), processos: ProcessosFalsos(),
                            warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: { _ in nil }) },
                            inici: inici)
        let lectura = try lector.llegeix()
        #expect(lectura.warpObert == false && lectura.warpPreview == .capWarp)
        let text = Informe.text(lectura, inici: inici)
        #expect(text.contains("Warp és tancat.\n⚠ No s'ha trobat Warp en aquest Mac: cal Warp Stable."), "\(text)")
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        let json = try codificador.encode(lectura)
        #expect(String(decoding: json, as: UTF8.self).contains(#""warpPreview":"capWarp""#))
        let descodificador = JSONDecoder()
        descodificador.dateDecodingStrategy = .iso8601
        #expect(try descodificador.decode(LecturaWarp.self, from: json) == lectura)
        var processos = ProcessosFalsos()
        ambWarp(paperera.appending(path: "Contents/MacOS/stable").path, a: &processos)
        lector.processos = processos
        #expect(try lector.llegeix().warpPreview == .capWarp)
    }

    /// On no s'ha instal·lat mai Warp, tampoc no hi ha `settings.toml` ni la base: amb una carpeta de prova (`.segonsAjust`,
    /// l'ajust per defecte diu que es llegeixi la base) o en refrescar la foto (`.sempre`), `llegeix` falla amb «no trobo la
    /// base de Warp». La lectura de l'app no: és la de la configuració de debò (`.mai`), que diu que no hi ha Warp. El CLI
    /// continua fallant (`llegeix`). Amb només Warp Preview, el seu motiu; amb Warp Stable sense base, o sense Warp però amb
    /// la base, com sempre.
    @Test func laLecturaDeLAppSenseCapWarpNiBaseDiuQueNoHiHaWarp() throws {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        try tmp.carpeta("sessions")
        let cerca = CercaFalsa()
        let lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                            carpetaSessions: tmp.url("sessions"), processos: ProcessosFalsos(),
                            warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca) },
                            inici: inici)
        #expect(lector.senseWarpStable() == .capWarp)
        #expect(throws: ErrorLectura.noHiHaBase(tmp.url("warp.sqlite").path)) { try lector.llegeix() }
        let deDebo = try lector.llegeix(base: .mai)
        #expect(deDebo.warpPreview == .capWarp && deDebo.warpDesaFinestres == false && deDebo.finestres.isEmpty)
        for base in [BaseWarp.segonsAjust, .sempre, .mai] {
            #expect(try lector.llegeixDeLApp(base: base) == deDebo, "\(base)")
        }

        // Només Warp Preview: el seu motiu.
        let preview = try paquet(tmp, "Applications/Warp Preview.app", id: AppWarp.identificadorPreview, executable: "preview")
        cerca.apps[AppWarp.identificadorPreview] = preview
        #expect(lector.senseWarpStable() == .nomesPreview)
        #expect(try lector.llegeixDeLApp(base: .segonsAjust).warpPreview == .nomesPreview)

        // Sense Warp però amb la base (d'un Warp que ja no hi és): la llegeix, com sempre.
        cerca.apps = [:]
        do {
            let sqlite = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
            try sqlite.finestra(1)
            try sqlite.pestanya(10, finestra: 1)
            try sqlite.paneTerminal(100, pestanya: 10, uuid: uuidDeProva("a"), cwd: inici)
        }
        let ambBase = try lector.llegeixDeLApp(base: .segonsAjust)
        #expect(ambBase.finestres.count == 1 && ambBase.warpDesaFinestres == true && ambBase.warpPreview == .capWarp)

        // Amb Warp Stable i sense la base: no és que no hi hagi Warp, i l'error de sempre.
        try FileManager.default.removeItem(at: tmp.url("warp.sqlite"))
        _ = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        #expect(lector.senseWarpStable() == nil)
        for base in [BaseWarp.segonsAjust, .sempre] {
            #expect(throws: ErrorLectura.noHiHaBase(tmp.url("warp.sqlite").path)) { try lector.llegeixDeLApp(base: base) }
        }
    }

    /// Sense res a dir, el JSON no porta el camp, com el d'abans de la 0.29.2, i es llegeix igual.
    @Test func unaLecturaDAbans() throws {
        let json = try JSONEncoder().encode(LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: ["x"]))
        #expect(!String(decoding: json, as: UTF8.self).contains("warpPreview"))
        let llegida = try JSONDecoder().decode(LecturaWarp.self, from: json)
        #expect(llegida.warpPreview == nil && llegida.avisos == ["x"])
    }
}

/// Decisió 4 (0.31.1): si corre Warp Stable, és aquell el que compta, encara que macOS en digui un altre. Les còpies són
/// paquets a la carpeta temporal, i els processos, inventats.
@Suite struct CopiaObertaTests {
    /// Un lector amb aquests processos i el Warp que diu `cerca`, sense res més (ni base, ni sessions).
    private func lector(_ tmp: CarpetaTemporal, _ processos: ProcessosFalsos, cerca: CercaFalsa) throws -> Lector {
        try tmp.carpeta("sessions")
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        return Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                      carpetaSessions: tmp.url("sessions"), processos: processos,
                      warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca) },
                      inici: try tmp.carpeta("inici"))
    }

    /// Dues còpies: macOS diu la d'Aplicacions, però corre la de Descàrregues. És oberta, se'n veuen els terminals i s'hi
    /// obririen les finestres; abans, l'app la veia tancada i hauria obert l'altra (dos Warp).
    @Test func duesCopiesCorreLAltra() throws {
        let tmp = try CarpetaTemporal()
        let installada = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable",
                                    versio: "0.2026.10.21.08.25.02")
        let copia = try paquet(tmp, "inici/Downloads/Warp.app", id: AppWarp.identificador, executable: "stable",
                               versio: "0.2026.11.04.08.17.01")
        let binari = copia.appending(path: "Contents/MacOS/stable").path
        let cerca = CercaFalsa([AppWarp.identificador: installada])
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca)
        var processos = ProcessosFalsos()
        ambWarp(binari, a: &processos)
        #expect(warp.app == AppWarp(url: installada) && !processos.warpObert(executable: warp.executable), "el que diu macOS")

        #expect(warp.ambLaCopiaOberta(processos) == InstallacioWarp(app: AppWarp(url: copia), executable: binari,
                                                                     hiHaStable: true))
        let l = try lector(tmp, processos, cerca: cerca)
        let lectura = try l.llegeix()
        #expect(lectura.warpObert == true && lectura.terminals == [TerminalViu(pid: 51)] && lectura.warpPreview == nil)
        #expect(l.warpObert())
        #expect(l.installacio().app == AppWarp(url: copia) && l.installacio().app.versio == "0.2026.11.04.08.17.01")
        // El diagnòstic també mira aquella.
        let diagnostic = EntornDiagnostic(lector: l, carpetaConfiguracio: nil, transcripcions: LectorTranscripcions(carpeta: tmp.url("p")),
                                          confianca: LectorConfianca(ruta: tmp.url("c.json")), sistema: "prova")
        #expect(diagnostic.warp().app == AppWarp(url: copia))

        // Només el `terminal-server` de la còpia, o el seu CLI, no són Warp obert: el que diu macOS.
        var servidor = processos
        servidor.processos[40] = nil
        servidor.processos[70] = (InfoProces(executable: binari, argv: [binari, "--help"]), 1)
        #expect(warp.ambLaCopiaOberta(servidor) == warp)
        #expect(try !lector(tmp, servidor, cerca: cerca).warpObert())
    }

    /// Amb totes dues obertes, la que diu macOS, com fins ara. Amb dues altres, la de pid més baix.
    @Test func ambTotesDuesObertesLaDeMacOS() throws {
        let tmp = try CarpetaTemporal()
        let installada = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let copia = try paquet(tmp, "inici/Downloads/Warp.app", id: AppWarp.identificador, executable: "stable")
        let altra = try paquet(tmp, "inici/Desktop/Warp.app", id: AppWarp.identificador, executable: "stable")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                         cerca: CercaFalsa([AppWarp.identificador: installada]).cerca)
        var processos = ProcessosFalsos()
        ambWarp(copia.appending(path: "Contents/MacOS/stable").path, pid: 40, a: &processos)
        ambWarp(installada.appending(path: "Contents/MacOS/stable").path, pid: 80, a: &processos)
        #expect(warp.ambLaCopiaOberta(processos) == warp)
        processos.processos = processos.processos.filter { $0.key < 80 }
        ambWarp(altra.appending(path: "Contents/MacOS/stable").path, pid: 20, a: &processos)
        #expect(warp.ambLaCopiaOberta(processos).app == AppWarp(url: altra))
    }

    /// Un Warp que macOS ha traslladat («App Translocation»: l'app corre des d'una còpia que macOS munta a una carpeta
    /// temporal) compta, encara que macOS no en sàpiga res: sense Warp Stable instal·lat, i amb Warp Preview, tampoc no
    /// diu que només hi ha Preview.
    @Test func unaDeTraslladada() throws {
        let tmp = try CarpetaTemporal()
        let traslladada = try paquet(tmp, "private/var/folders/zz/prova/T/AppTranslocation/0A1B2C3D-0000-4000-8000-000000000001/d/Warp.app",
                                     id: AppWarp.identificador, executable: "stable")
        let preview = try paquet(tmp, "Applications/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "preview")
        let binari = traslladada.appending(path: "Contents/MacOS/stable").path
        let cerca = CercaFalsa([AppWarp.identificadorPreview: preview])
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca)
        #expect(!warp.hiHaStable)
        var processos = ProcessosFalsos()
        ambWarp(binari, a: &processos)
        let oberta = warp.ambLaCopiaOberta(processos)
        #expect(oberta == InstallacioWarp(app: AppWarp(url: traslladada), executable: binari, hiHaStable: true,
                                          executablePreview: tmp.ruta + "/Applications/WarpPreview.app/Contents/MacOS/preview"))
        #expect(oberta.app.esWarp)
        let lectura = try lector(tmp, processos, cerca: cerca).llegeix()
        #expect(lectura.warpObert == true && lectura.terminals == [TerminalViu(pid: 51)] && lectura.warpPreview == nil)
    }

    /// Una còpia a la Paperera continua sense comptar (0.29.3), encara que corri: el Warp que compta és el que diu macOS,
    /// tancat.
    @Test func laPapereraContinuaSenseComptar() throws {
        let tmp = try CarpetaTemporal()
        _ = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let cerca = CercaFalsa()
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca)
        for ruta in ["inici/.Trash/Warp.app", "Volumes/Disc/.Trashes/501/Warp.app"] {
            let paperera = try paquet(tmp, ruta, id: AppWarp.identificador, executable: "stable")
            var processos = ProcessosFalsos()
            ambWarp(paperera.appending(path: "Contents/MacOS/stable").path, a: &processos)
            #expect(warp.ambLaCopiaOberta(processos) == warp, "\(ruta)")
            #expect(try !lector(tmp, processos, cerca: cerca).warpObert(), "\(ruta)")
        }
    }

    /// Un binari inventat amb la ruta de debò (`ProcessosFalsos.executableWarp`) no fa llegir el Warp de debò: els processos
    /// falsos només llegeixen l'`Info.plist` dins de les carpetes temporals (`warpDelBinari`). Si el llegissin, en un Mac amb
    /// Warp a Aplicacions, aquí es veuria aquell Warp en lloc de cap.
    @Test func lesProvesNoLlegeixenElWarpDeDebo() throws {
        let tmp = try CarpetaTemporal()
        #expect(tmp.ruta.hasPrefix(CarpetaTemporal.prefix))
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: CercaFalsa().cerca)
        #expect(!warp.hiHaStable)
        let processos = ProcessosFalsos.ambWarp()
        #expect(processos.warpDelBinari(ProcessosFalsos.executableWarp) == nil)
        #expect(warp.ambLaCopiaOberta(processos) == warp)
        // Dins de la carpeta temporal, sí.
        let copia = try paquet(tmp, "inici/Downloads/Warp.app", id: AppWarp.identificador, executable: "stable")
        #expect(processos.warpDelBinari(copia.appending(path: "Contents/MacOS/stable").path) == AppWarp(url: copia))
    }

    /// Només compta un binari que corre sense arguments dins de `<paquet>.app/Contents/MacOS/`, d'un paquet que diu que és
    /// Warp Stable i que aquell és el seu binari.
    @Test func nomesUnWarpStableDeDebo() throws {
        let tmp = try CarpetaTemporal()
        _ = try paquet(tmp, "Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: CercaFalsa().cerca)
        let preview = try paquet(tmp, "Altres/WarpPreview.app", id: AppWarp.identificadorPreview, executable: "stable")
        let dev = try paquet(tmp, "Altres/WarpDev.app", id: "dev.warp.Warp-Dev", executable: "stable")
        let unAltreBinari = try paquet(tmp, "Altres/Warp.app", id: AppWarp.identificador, executable: "warp-stable")
        let senseApp = try paquet(tmp, "Altres/Warp", id: AppWarp.identificador, executable: "stable")
        try tmp.carpeta("bin")
        for binari in [preview.appending(path: "Contents/MacOS/stable").path, dev.appending(path: "Contents/MacOS/stable").path,
                       unAltreBinari.appending(path: "Contents/MacOS/stable").path,
                       senseApp.appending(path: "Contents/MacOS/stable").path, tmp.url("bin/stable").path,
                       "Altres/Warp.app/Contents/MacOS/stable"] {
            var processos = ProcessosFalsos()
            ambWarp(binari, a: &processos)
            #expect(warp.ambLaCopiaOberta(processos) == warp, "\(binari)")
        }
        // El nom del binari surt del paquet: si el de macOS no és `stable`, també es busca aquell.
        let nou = try paquet(tmp, "inici/Applications/Warp nou.app", id: AppWarp.identificador, executable: "warp-stable")
        let copiaNova = try paquet(tmp, "inici/Downloads/Warp nou.app", id: AppWarp.identificador, executable: "warp-stable")
        let ambNom = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"),
                                           cerca: CercaFalsa([AppWarp.identificador: nou]).cerca)
        var processos = ProcessosFalsos()
        ambWarp(copiaNova.appending(path: "Contents/MacOS/warp-stable").path, a: &processos)
        #expect(ambNom.ambLaCopiaOberta(processos).app == AppWarp(url: copiaNova))
    }
}
