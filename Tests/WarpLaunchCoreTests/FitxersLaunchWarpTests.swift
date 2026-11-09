import Foundation
import Testing
@testable import WarpLaunchCore

// Escriure i esborrar el fitxer temporal (fase 3.1, 0.19.0). Sempre en una carpeta temporal que fa de la de Warp: cap
// prova no toca la de debò.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)

private struct Carpeta {
    let tmp: CarpetaTemporal
    let fitxers: FitxersLaunchWarp

    init() throws {
        tmp = try CarpetaTemporal()
        fitxers = FitxersLaunchWarp(carpeta: URL(filePath: try tmp.carpeta("warp")))
    }

    func url(_ nom: String) -> URL { fitxers.carpeta.appending(path: nom) }
    func existeix(_ nom: String) -> Bool { FileManager.default.fileExists(atPath: url(nom).path) }
    func noms() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: fitxers.carpeta.path).sorted() }

    /// Fa que el fitxer sembli escrit fa `segons`.
    func envelleix(_ nom: String, segons: TimeInterval, ara: Date = t0) throws {
        try FileManager.default.setAttributes([.modificationDate: ara - segons], ofItemAtPath: url(nom).path)
    }
}

private func fitxer(_ n: Int) throws -> FitxerLaunch {
    try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "T", carpeta: "/x", exec: nil)], llancament: id(n))
}

@Suite struct FitxersLaunchWarpTests {
    @Test func escriuElFitxerSencer() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        #expect(try c.fitxers.escriu(f) == f.mida)
        #expect(try String(contentsOf: c.url(f.nomFitxer), encoding: .utf8) == f.text)
        let atributs = try FileManager.default.attributesOfItem(atPath: c.url(f.nomFitxer).path)
        #expect(atributs[.posixPermissions] as? Int == 0o644)
        #expect(try c.noms() == [f.nomFitxer])
    }

    /// Mai no se sobreescriu res, i la carpeta no es crea.
    @Test func noSobreescriuNiCreaLaCarpeta() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        try Data("d'en David".utf8).write(to: c.url(f.nomFitxer))
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.jaExisteix) { try c.fitxers.escriu(f) }
        #expect(try Data(contentsOf: c.url(f.nomFitxer)) == Data("d'en David".utf8))

        // Un enllaç amb el nom: tampoc s'hi escriu a través.
        let desti = c.tmp.url("desti.txt")
        try Data("intacte".utf8).write(to: desti)
        let g = try fitxer(2)
        try FileManager.default.createSymbolicLink(at: c.url(g.nomFitxer), withDestinationURL: desti)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.jaExisteix) { try c.fitxers.escriu(g) }
        #expect(try Data(contentsOf: desti) == Data("intacte".utf8))

        let sense = FitxersLaunchWarp(carpeta: c.tmp.url("no-hi-es"))
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) { try sense.escriu(f) }
        #expect(!FileManager.default.fileExists(atPath: c.tmp.url("no-hi-es").path))
    }

    /// Decisió d'en David del 09/11/2026 (regla 7): amb `creaCarpeta`, la carpeta, un sol nivell.
    @Test func creaLaCarpetaNomesSiEsDemanaIUnSolNivell() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        let mgr = FileManager.default

        let nova = c.fitxers.carpeta.appending(path: "carpeta-nova")
        let fitxers = FitxersLaunchWarp(carpeta: nova)
        #expect(try fitxers.escriu(f, creaCarpeta: true) == f.mida)
        #expect(try String(contentsOf: nova.appending(path: f.nomFitxer), encoding: .utf8) == f.text)
        #expect(try mgr.attributesOfItem(atPath: nova.path)[.posixPermissions] as? Int == 0o755)
        // Ja hi és: torna a escriure-hi, i no toca res del que hi ha.
        #expect(try fitxers.escriu(try fitxer(2), creaCarpeta: true) > 0)
        #expect(try mgr.contentsOfDirectory(atPath: nova.path).count == 2)

        // Sense el pare (`~/.warp`): com fins ara, i no el crea.
        let pare = c.tmp.url("punt-warp")
        let sensePare = FitxersLaunchWarp(carpeta: pare.appending(path: "carpeta-nova"))
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) { try sensePare.escriu(f, creaCarpeta: true) }
        #expect(!mgr.fileExists(atPath: pare.path))
    }

    /// Si el camí és un fitxer o un enllaç trencat, no es crea ni es toca res.
    @Test func noCreaLaCarpetaSiElCamiEsUnFitxerOUnEnllac() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        let mgr = FileManager.default

        let unFitxer = c.fitxers.carpeta.appending(path: "es-un-fitxer")
        try Data("d'en David".utf8).write(to: unFitxer)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: unFitxer).escriu(f, creaCarpeta: true)
        }
        #expect(try Data(contentsOf: unFitxer) == Data("d'en David".utf8))

        // Un enllaç trencat: `mkdir` no el segueix, i el destí no apareix.
        let desti = c.tmp.url("desti-que-no-hi-es")
        let enllac = c.fitxers.carpeta.appending(path: "enllac")
        try mgr.createSymbolicLink(at: enllac, withDestinationURL: desti)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: enllac).escriu(f, creaCarpeta: true)
        }
        #expect(!mgr.fileExists(atPath: desti.path))
        #expect(try mgr.destinationOfSymbolicLink(atPath: enllac.path) == desti.path)

        // Un enllaç a un fitxer: tampoc.
        let enllacAFitxer = c.fitxers.carpeta.appending(path: "enllac-a-fitxer")
        try mgr.createSymbolicLink(at: enllacAFitxer, withDestinationURL: unFitxer)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: enllacAFitxer).escriu(f, creaCarpeta: true)
        }
        #expect(try Data(contentsOf: unFitxer) == Data("d'en David".utf8))
    }

    /// Si `~/.warp` és un enllaç, la carpeta es crearia a una altra banda: no es crea. Tampoc amb una URL de directori, la de
    /// la carpeta de debò, on una barra final faria seguir l'enllaç trencat a la crida.
    @Test func noCreaLaCarpetaSiElPareEsUnEnllacOUnFitxer() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        let mgr = FileManager.default

        let altra = c.tmp.url("altra-banda")
        try mgr.createDirectory(at: altra, withIntermediateDirectories: false)
        let enllac = c.tmp.url("punt-warp-enllac")
        try mgr.createSymbolicLink(at: enllac, withDestinationURL: altra)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: enllac.appending(path: "carpeta-nova", directoryHint: .isDirectory)).escriu(f, creaCarpeta: true)
        }
        #expect(try mgr.contentsOfDirectory(atPath: altra.path).isEmpty)

        let unFitxer = c.tmp.url("punt-warp-fitxer")
        try Data("d'algú".utf8).write(to: unFitxer)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: unFitxer.appending(path: "carpeta-nova", directoryHint: .isDirectory)).escriu(f, creaCarpeta: true)
        }
        #expect(try Data(contentsOf: unFitxer) == Data("d'algú".utf8))

        let desti = c.tmp.url("desti-que-no-hi-es")
        let trencat = c.fitxers.carpeta.appending(path: "enllac-trencat")
        try mgr.createSymbolicLink(at: trencat, withDestinationURL: desti)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseCarpeta) {
            try FitxersLaunchWarp(carpeta: c.fitxers.carpeta.appending(path: "enllac-trencat", directoryHint: .isDirectory)).escriu(f, creaCarpeta: true)
        }
        #expect(!mgr.fileExists(atPath: desti.path))
    }

    @Test func esborraElQueVaEscriure() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        let mida = try c.fitxers.escriu(f)
        #expect(try c.fitxers.esborra(llancament: id(1), mida: mida) == .esborrat)
        #expect(try c.noms().isEmpty)
        #expect(try c.fitxers.esborra(llancament: id(1), mida: mida) == .noHiEra)
    }

    /// Si no és exactament el que va escriure, no l'esborra: ni si ha canviat la mida o la marca, ni si és un enllaç o
    /// una carpeta.
    @Test func noEsborraElQueNoEsSeu() throws {
        let c = try Carpeta()
        let f = try fitxer(1)
        let mida = try c.fitxers.escriu(f)
        try (f.text + "# afegit\n").write(to: c.url(f.nomFitxer), atomically: false, encoding: .utf8)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.midaDiferent(esperada: mida, trobada: mida + 9)) {
            try c.fitxers.esborra(llancament: id(1), mida: mida)
        }
        // La mateixa mida, però una altra marca.
        try f.text.replacingOccurrences(of: "temporal 0", with: "temporal 9")
            .write(to: c.url(f.nomFitxer), atomically: false, encoding: .utf8)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseMarca) { try c.fitxers.esborra(llancament: id(1), mida: mida) }
        #expect(c.existeix(f.nomFitxer))

        let desti = c.tmp.url("desti.yaml")
        let g = try fitxer(2)
        try g.text.write(to: desti, atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: c.url(g.nomFitxer), withDestinationURL: desti)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.noEsUnFitxer) { try c.fitxers.esborra(llancament: id(2), mida: g.mida) }
        #expect(FileManager.default.fileExists(atPath: desti.path))

        try FileManager.default.createDirectory(at: c.url(try fitxer(3).nomFitxer), withIntermediateDirectories: false)
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.noEsUnFitxer) { try c.fitxers.esborra(llancament: id(3), mida: 0) }
        #expect(try c.noms().count == 3)
    }

    /// En arrencar: els llançaments que `estat.json` no dona per esborrats, i els fitxers propis amb la marca de més de
    /// 2 min. Res més: ni els d'en David, ni un nom que s'hi assembla, ni un fitxer propi sense la marca o massa nou.
    @Test func neteja() throws {
        let c = try Carpeta()
        let pendent = try fitxer(1)
        let mida = try c.fitxers.escriu(pendent)
        let esborrat = try fitxer(2)
        _ = try c.fitxers.escriu(esborrat)
        let vell = try fitxer(3)
        _ = try c.fitxers.escriu(vell)
        try c.envelleix(vell.nomFitxer, segons: 121)
        let nou = try fitxer(4)
        _ = try c.fitxers.escriu(nou)
        try c.envelleix(nou.nomFitxer, segons: 60)
        let senseMarca = try fitxer(5)
        try "# un altre\n".write(to: c.url(senseMarca.nomFitxer), atomically: false, encoding: .utf8)
        try c.envelleix(senseMarca.nomFitxer, segons: 3600)
        let deDavid = ["espai-feina.yaml", "warp-launch-ABCDEF00-0000-0000-0000-000000000006.yaml",
                       "warp-launch-prova.yaml", "warp-launch-00000000-0000-0000-0000-000000000007.yml"]
        for nom in deDavid {
            try LaunchConfigWarp.marca(id(6)).write(to: c.url(nom), atomically: false, encoding: .utf8)
            try c.envelleix(nom, segons: 3600)
        }

        let llancaments = [
            Llancament(id: id(1), fitxer: pendent.nomFitxer, mida: mida, creat: t0, finestra: id(100), pestanyes: [],
                       estat: .senseConfirmar),
            Llancament(id: id(2), fitxer: esborrat.nomFitxer, mida: 1, creat: t0, finestra: id(100), pestanyes: [],
                       estat: .confirmat, esborrat: true),
            Llancament(id: id(8), fitxer: "x", mida: 1, creat: t0, finestra: id(100), pestanyes: [], estat: .pendent),
        ]
        let resultats = c.fitxers.neteja(llancaments: llancaments, ara: t0)
        #expect(resultats.mapValues { try? $0.get() } == [id(1): .esborrat, id(3): .esborrat, id(5): nil, id(8): .noHiEra])
        #expect(throws: FitxersLaunchWarp.ErrorFitxers.senseMarca) { try resultats[id(5)]?.get() }
        // Queden: el que estat.json ja dona per esborrat (no és d'aquesta carpeta de prova), el nou, el que no té la
        // marca i els d'en David.
        #expect(try c.noms() == (deDavid + [esborrat.nomFitxer, nou.nomFitxer, senseMarca.nomFitxer]).sorted())
    }

    /// Les mides i els noms surten del text que s'escriu.
    @Test func elNomILaMida() throws {
        let f = try fitxer(1)
        #expect(f.nomFitxer == "warp-launch-00000000-0000-0000-0000-000000000001.yaml")
        #expect(FitxerLaunch.llancament(deNomFitxer: f.nomFitxer) == id(1))
        #expect(FitxerLaunch.llancament(deNomFitxer: "warp-launch-00000000-0000-0000-0000-00000000000A.yaml") == nil)
        let accents = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "Èxit", carpeta: "/x", exec: nil)],
                                                  llancament: id(1))
        #expect(accents.mida == accents.text.utf8.count && accents.mida > accents.text.count)
    }
}
