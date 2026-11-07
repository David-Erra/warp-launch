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
        #expect(cerca.demanades == [AppWarp.identificador, AppWarp.identificadorPreview], "només els dos de Warp")
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

    /// Cap Warp: ni el diu macOS ni n'hi ha a Aplicacions. Obrir res fallaria, i el binari és el de sempre (no n'hi ha cap).
    @Test func capWarp() throws {
        let tmp = try CarpetaTemporal()
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: CercaFalsa().cerca)
        #expect(warp == InstallacioWarp(app: AppWarp(url: tmp.url("Applications/Warp.app")),
                                        executable: tmp.ruta + "/Applications/Warp.app/Contents/MacOS/stable", hiHaStable: false))
        #expect(!warp.app.esWarp)
        #expect(warp.preview(ProcessosFalsos(), stableObert: false) == nil, "sense Preview, res a dir")
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

    /// El lector fa servir el Warp que li diuen, a cada lectura.
    @Test func elLectorElMiraACadaLectura() throws {
        let tmp = try CarpetaTemporal()
        let inici = try tmp.carpeta("inici")
        try tmp.carpeta("sessions")
        try Data("[general]\nrestore_session = false\n".utf8).write(to: tmp.url("settings.toml"))
        let stable = try paquet(tmp, "inici/Applications/Warp.app", id: AppWarp.identificador, executable: "stable")
        let cerca = CercaFalsa()
        var processos = ProcessosFalsos()
        ambWarp(stable.appending(path: "Contents/MacOS/stable").path, a: &processos)
        let lector = Lector(rutaWarp: tmp.url("warp.sqlite"), rutaAjustos: tmp.url("settings.toml"),
                            carpetaSessions: tmp.url("sessions"), processos: processos,
                            warp: { InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: cerca.cerca) },
                            inici: inici)
        // Encara no s'ha instal·lat: no hi ha Warp, i el que corre no és cap Warp conegut.
        let abans = try lector.llegeix()
        #expect(abans.warpObert == false && abans.terminals.isEmpty && abans.warpPreview == nil)
        #expect(!lector.warpObert())
        // Instal·lat a `~/Applications` amb l'app oberta: la lectura següent ja el veu.
        cerca.apps[AppWarp.identificador] = stable
        let despres = try lector.llegeix()
        #expect(despres.warpObert == true)
        #expect(despres.terminals == [TerminalViu(pid: 51)])
        #expect(lector.warpObert())
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
        #expect(try lector.llegeix().warpPreview == .nomesPreview)
    }

    /// Sense res a dir, el JSON no porta el camp, com el d'abans de la 0.29.2, i es llegeix igual.
    @Test func unaLecturaDAbans() throws {
        let json = try JSONEncoder().encode(LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: ["x"]))
        #expect(!String(decoding: json, as: UTF8.self).contains("warpPreview"))
        let llegida = try JSONDecoder().decode(LecturaWarp.self, from: json)
        #expect(llegida.warpPreview == nil && llegida.avisos == ["x"])
    }
}
