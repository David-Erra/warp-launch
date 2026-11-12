import Foundation
import Testing
@testable import WarpLaunchCore

// Multidioma (docs/disseny.md, secció 12): la tria de la llengua, el bundle dels textos i `t(_:)`. Les llengües que no són
// al paquet (`ja`, `fr`) es fan amb un bundle de prova, a una carpeta temporal.

/// Un bundle de textos de prova: per a cada llengua, el `.strings` i el `.stringsdict` (el contingut del `<dict>`).
private func bundleDeProva(_ tmp: CarpetaTemporal, _ llengues: [String: (strings: String, plurals: String)]) throws -> URL {
    let bundle = tmp.url("Prova.bundle")
    for (llengua, textos) in llengues {
        let carpeta = bundle.appending(path: "\(llengua).lproj")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data(textos.strings.utf8).write(to: carpeta.appending(path: "Localizable.strings"))
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(textos.plurals)</dict></plist>
            """
        try Data(plist.utf8).write(to: carpeta.appending(path: "Localizable.stringsdict"))
    }
    return bundle
}

/// L'entrada «%lld finestres» d'un `.stringsdict`, amb les formes donades (`one`, `other`…).
private func pluralFinestres(_ formes: [String: String]) -> String {
    let llista = formes.sorted { $0.key < $1.key }.map { "<key>\($0.key)</key><string>\($0.value)</string>" }.joined()
    return """
        <key>%lld finestres</key><dict>
        <key>NSStringLocalizedFormatKey</key><string>%#@finestres@</string>
        <key>finestres</key><dict>
        <key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key><string>lld</string>\(llista)</dict></dict>
        """
}

@Suite struct IdiomaTests {
    /// `scripts/test.sh` posa `WARP_LAUNCH_IDIOMA=ca`: les proves esperen els textos en català, sigui quina sigui la llengua
    /// del Mac. Amb `swift test` sol, aquesta prova falla.
    @Test func lesProvesSonEnCatala() {
        #expect(ProcessInfo.processInfo.environment[Idioma.variable] == "ca", "executa les proves amb scripts/test.sh")
        #expect(Idioma.efectiva == "ca")
        #expect(Idioma.locale.language.languageCode == .catalan)
        #expect(t("Obre a Warp…") == "Obre a Warp…")
    }

    /// Les proves troben el bundle del paquet (al costat del `.xctest`), amb el català i l'anglès.
    @Test func elBundleDelPaquetEsTroba() throws {
        let textos = try #require(Idioma.textos)
        #expect(textos.llengues.contains("ca") && textos.llengues.contains("en"), "\(textos.llengues)")
    }

    @Test func unaClauEnCatalaIEnAngles() {
        #expect(t("Obre a Warp…") == "Obre a Warp…")
        Idioma.$deProva.withValue("en") {
            #expect(t("Obre a Warp…") == "Open in Warp…")
        }
    }

    /// El plural surt del `.stringsdict`, amb les regles de cada llengua: en català i en anglès, 0 va amb `other`.
    @Test func unPluralEnCatalaIEnAngles() {
        #expect([0, 1, 2, 21].map { t("\($0) finestres") } == ["0 finestres", "1 finestra", "2 finestres", "21 finestres"])
        Idioma.$deProva.withValue("en") {
            #expect([0, 1, 2, 21].map { t("\($0) finestres") } == ["0 windows", "1 window", "2 windows", "21 windows"])
        }
    }

    /// En japonès, un plural només té `other`, i serveix per a tots els nombres.
    @Test func japonesAmbNomesOther() throws {
        let tmp = try CarpetaTemporal()
        let bundle = try bundleDeProva(tmp, [
            "ca": (#""Obre a Warp…" = "Obre a Warp…";"#, pluralFinestres(["one": "%lld finestra", "other": "%lld finestres"])),
            "ja": (#""Obre a Warp…" = "Warp で開く…";"#, pluralFinestres(["other": "ウィンドウ %lld 個"])),
        ])
        let textos = try #require(Textos(bundle: bundle))
        #expect(textos.llengues == ["ca", "ja"])
        #expect([0, 1, 2].map { Idioma.text("\($0) finestres", textos: textos, llengua: "ja") }
            == ["ウィンドウ 0 個", "ウィンドウ 1 個", "ウィンドウ 2 個"])
        #expect(Idioma.text("Obre a Warp…", textos: textos, llengua: "ja") == "Warp で開く…")
        #expect(Idioma.tria(disponibles: ["ca", "en", "ja"], preferencies: ["ja-JP"]) == "ja")
    }

    /// Amb el `locale` de la llengua, els plurals segueixen la llengua dels textos i no la regió del Mac: en francès, 0 va
    /// amb `one` («0 fenêtre»).
    @Test func elPluralSegueixLaLlenguaINoLaRegio() throws {
        let tmp = try CarpetaTemporal()
        let bundle = try bundleDeProva(tmp, [
            "fr": (#""Obre a Warp…" = "Ouvrir dans Warp…";"#, pluralFinestres(["one": "%lld fenêtre", "other": "%lld fenêtres"])),
        ])
        let textos = try #require(Textos(bundle: bundle))
        #expect([0, 1, 2].map { Idioma.text("\($0) finestres", textos: textos, llengua: "fr") }
            == ["0 fenêtre", "1 fenêtre", "2 fenêtres"])
    }

    /// Una llengua sense textos cau a l'anglès, si cap altra de les preferides no en té; les equivalències són les de macOS.
    @Test func laReservaEsLAngles() {
        let disponibles = ["ca", "en", "es", "pt-BR", "zh-Hans"]
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["de-DE"]) == "en")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: []) == "en")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["de-DE", "ca-ES"]) == "ca")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["ca-ES", "en-US"]) == "ca")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["pt-PT"]) == "pt-BR")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["zh-CN"]) == "zh-Hans")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["es-MX"]) == "es")
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["ru-RU", "pt-PT"]) == "pt-BR")
        // El xinès tradicional no és el simplificat.
        #expect(Idioma.tria(disponibles: disponibles, preferencies: ["zh-TW"]) == "en")
        // Sense l'anglès, la primera disponible.
        #expect(Idioma.tria(disponibles: ["ca", "es"], preferencies: ["de-DE"]) == "ca")
        Idioma.$deProva.withValue("ru") {
            #expect(Idioma.efectiva == "en")
            #expect(t("Obre a Warp…") == "Open in Warp…")
        }
    }

    /// La variable d'entorn mana sobre les llengües del Mac; buida, no compta.
    @Test func laVariableManaSobreElMac() {
        #expect(Idioma.preferencies(entorn: [Idioma.variable: "ca"], delMac: ["de-DE", "en-US"]) == ["ca"])
        #expect(Idioma.preferencies(entorn: [Idioma.variable: " "], delMac: ["de-DE"]) == ["de-DE"])
        #expect(Idioma.preferencies(entorn: [:], delMac: ["de-DE"]) == ["de-DE"])
    }

    /// `Idioma.$deProva` només val dins del bloc (i de les tasques que s'hi creen), i mana sobre la variable.
    @Test func laLlenguaDeProvaNomesValDinsDelBloc() async {
        #expect(Idioma.efectiva == "ca")
        await Idioma.$deProva.withValue("en") {
            #expect(Idioma.efectiva == "en")
            #expect(Idioma.locale.language.languageCode == .english)
            #expect(await Task { t("Obre a Warp…") }.value == "Open in Warp…")
            Idioma.$deProva.withValue("ca") { #expect(t("Obre a Warp…") == "Obre a Warp…") }
            #expect(t("Obre a Warp…") == "Open in Warp…")
        }
        #expect(Idioma.efectiva == "ca")
        #expect(t("Obre a Warp…") == "Obre a Warp…")
    }

    /// Sense el bundle (un binari copiat sol), `t` torna la clau, amb els valors, en català i sense aturar res.
    @Test func senseElBundleTornaLaClau() throws {
        let tmp = try CarpetaTemporal()
        try tmp.carpeta("Buit.bundle")
        #expect(Textos.delPrimer([tmp.url("NoHiEs.bundle"), tmp.url("Buit.bundle")]) == nil)
        #expect(Idioma.text("Obre a Warp…", textos: nil, llengua: "en") == "Obre a Warp…")
        #expect(Idioma.text("\(3) finestres", textos: nil, llengua: "en") == "3 finestres")
        #expect(Idioma.text("Obre \("prova2") a Warp", textos: nil, llengua: "en") == "Obre prova2 a Warp")
        // Amb el bundle, una llengua que no hi és o una clau que no hi és: també la clau.
        let textos = try #require(Idioma.textos)
        #expect(Idioma.text("Obre a Warp…", textos: textos, llengua: "ru") == "Obre a Warp…")
        #expect(Idioma.text("Una clau que no hi és", textos: textos, llengua: "en") == "Una clau que no hi és")
    }

    /// La cerca agafa el primer candidat amb textos, també amb l'estructura d'un paquet (`Contents/Resources`).
    @Test func laCercaAgafaElPrimerAmbTextos() throws {
        let tmp = try CarpetaTemporal()
        let pla = try bundleDeProva(tmp, ["en": (#""Obre a Warp…" = "Open in Warp…";"#, "")])
        let paquet = tmp.url("Paquet.bundle")
        let recursos = paquet.appending(path: "Contents/Resources/ca.lproj")
        try FileManager.default.createDirectory(at: recursos, withIntermediateDirectories: true)
        try Data(#""Obre a Warp…" = "Obre a Warp…";"#.utf8).write(to: recursos.appending(path: "Localizable.strings"))
        let info = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>"#
        try Data(info.utf8).write(to: paquet.appending(path: "Contents/Info.plist"))
        #expect(Textos.delPrimer([tmp.url("NoHiEs.bundle"), paquet, pla])?.llengues == ["ca"])
        #expect(Textos.delPrimer([pla, paquet])?.llengues == ["en"])
    }

    /// On el deixen `build-app.sh` (`Contents/Resources` de l'app) i SwiftPM (al costat del CLI), els candidats el troben; un
    /// binari copiat sol, no. Amb carpetes de prova: cap app no s'obre.
    @Test func elsCandidatsTrobenElBundleDeLAppIDelCLI() throws {
        let tmp = try CarpetaTemporal()
        func textosA(_ carpeta: URL) throws {
            let lproj = carpeta.appending(path: "\(Idioma.nomDelBundle)/Contents/Resources/ca.lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try Data(#""Obre a Warp…" = "Obre a Warp…";"#.utf8).write(to: lproj.appending(path: "Localizable.strings"))
        }
        let app = tmp.url("Prova.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        let info = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Prova</string>"#
            + #"<key>CFBundlePackageType</key><string>APPL</string></dict></plist>"#
        try Data(info.utf8).write(to: app.appending(path: "Contents/Info.plist"))
        try Data().write(to: app.appending(path: "Contents/MacOS/Prova"))
        try textosA(app.appending(path: "Contents/Resources"))
        let delApp = try #require(Bundle(url: app))
        #expect(Textos.delPrimer(Idioma.candidats(principal: delApp, codi: delApp))?.llengues == ["ca"])

        let cli = URL(filePath: try tmp.carpeta("debug"))
        try Data().write(to: cli.appending(path: "warp-launch"))
        try textosA(cli)
        let delCLI = try #require(Bundle(url: cli))
        #expect(Textos.delPrimer(Idioma.candidats(principal: delCLI, codi: delCLI))?.llengues == ["ca"])

        let sol = try #require(Bundle(url: URL(filePath: try tmp.carpeta("bin"))))
        #expect(Textos.delPrimer(Idioma.candidats(principal: sol, codi: sol)) == nil)
    }

    /// Els valors: un text (`%@`) i un nombre (`%lld`), posats al lloc que diu la traducció.
    @Test func elsValorsVanAlLlocDeLaTraduccio() throws {
        let tmp = try CarpetaTemporal()
        let bundle = try bundleDeProva(tmp, [
            "en": (#""%@ té %lld pestanyes" = "%2$lld tabs in %1$@";"#, ""),
        ])
        let textos = try #require(Textos(bundle: bundle))
        #expect(Idioma.text("\("prova2") té \(3) pestanyes", textos: textos, llengua: "en") == "3 tabs in prova2")
        #expect(Idioma.text("\("prova2") té \(3) pestanyes", textos: nil, llengua: "en") == "prova2 té 3 pestanyes")
    }

    /// Un enter interpolat (`%lld`) s'escriu amb els milers de la llengua: «1.000» en català, «1,000» en anglès. Un número que
    /// no és una quantitat (un PID, un port, una versió) s'ha d'interpolar com a text. El `%` sol no és cap especificador.
    @Test func elsNombresSegueixenLaLlengua() {
        #expect(t("\(1000) finestres") == "1.000 finestres")
        #expect(t("PID \(String(12345))") == "PID 12345")
        #expect(t("\(50)% fet") == "50% fet")
        Idioma.$deProva.withValue("en") {
            #expect(t("\(1000) finestres") == "1,000 windows")
        }
    }

    /// El selector de la Configuració (F4): cada llengua, amb el seu nom en ella mateixa i la primera lletra en majúscula, com als
    /// menús de macOS; l'opció del sistema, amb el nom en la llengua de l'app. Les del paquet són les de les carpetes.
    @Test func elsNomsDeLesLlengues() {
        let esperats = ["ca": "Català", "en": "English", "es": "Español", "fr": "Français", "de": "Deutsch", "it": "Italiano",
                        "pt-BR": "Português (Brasil)", "ja": "日本語", "zh-Hans": "简体中文", "ko": "한국어"]
        for (codi, nom) in esperats {
            #expect(Idioma.nomPropi(codi) == nom, "\(codi)")
        }
        #expect(Idioma.nom("en") == "anglès" && Idioma.nom("ca") == "català")
        Idioma.$deProva.withValue("en") {
            #expect(Idioma.nom("ca") == "Catalan" && Idioma.nom("pt-BR") == "Portuguese (Brazil)")
        }
        #expect(Idioma.llenguesDisponibles == Idioma.textos?.llengues)
        #expect(Idioma.llenguesDisponibles.contains("ca") && Idioma.llenguesDisponibles.contains("en"))
    }
}
