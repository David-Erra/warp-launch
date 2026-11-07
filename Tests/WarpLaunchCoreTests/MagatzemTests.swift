import Foundation
import Testing
@testable import WarpLaunchCore

// Desar i llegir la configuració (docs/disseny.md, «Desar»). Sempre en una carpeta temporal.

private let inici = "/Users/prova"
/// 03/11/2026 10:20:30 UTC.
private let moment = Date(timeIntervalSince1970: 1_793_701_230)

private func magatzem(_ carpeta: CarpetaTemporal, ara: Date = moment) -> MagatzemConfiguracio {
    MagatzemConfiguracio(carpeta: carpeta.url("config"), inici: inici, ara: { ara }, zona: TimeZone(identifier: "UTC")!)
}

private func configuracio(_ nom: String = "feina") -> Configuracio {
    Configuracio(plantilla: .habituals, finestres: [
        Finestra(id: uuid(1), nom: nom, pestanyes: [
            Pestanya(id: uuid(2), titol: "Botiga", carpeta: "/Users/prova/GitHub/botiga", claude: .habituals),
        ]),
    ])
}

/// L'error que llança `cos`, o `nil` si no en llança cap.
private func error(_ cos: () throws -> Void) -> ErrorMagatzem? {
    do {
        try cos()
        return nil
    } catch {
        return error as? ErrorMagatzem
    }
}

private extension ErrorMagatzem {
    var esLectura: Bool { if case .lectura = self { true } else { false } }
    var esEscriptura: Bool { if case .escriptura = self { true } else { false } }
}

/// Crea còpies pròpies amb contingut diferent (`configuracio-2026<mes><dia>-090000-sessio.json`) i en retorna els noms.
@discardableResult
private func posaCopies(_ m: MagatzemConfiguracio, dies: ClosedRange<Int>, mes: String) throws -> [String] {
    try FileManager.default.createDirectory(at: m.copies, withIntermediateDirectories: true)
    return try dies.map { dia in
        let nom = String(format: "configuracio-2026%@%02d-090000-sessio.json", mes, dia)
        try Data("{\"copia\": \(dia)}".utf8).write(to: m.copies.appending(path: nom))
        return nom
    }.sorted()
}

/// Tots els fitxers que hi ha a sota d'una carpeta, amb ruta relativa.
private func contingut(_ carpeta: URL) -> [String] {
    let fm = FileManager.default
    guard let enumerador = fm.enumerator(atPath: carpeta.path) else { return [] }
    return (enumerador.allObjects as? [String] ?? []).sorted()
}

@Suite struct MagatzemTests {
    @Test func senseFitxerNoHiHaConfiguracioINoEsCreaRes() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        #expect(try m.carrega() == nil)
        #expect(!FileManager.default.fileExists(atPath: m.carpeta.path))
    }

    @Test func desaICarrega() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        let carregada = try #require(try m.carrega())
        #expect(carregada.empremta == empremta)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(carregada.configuracio.finestres == configuracio().finestres)
        #expect(carregada.configuracio.generador == "Warp Launch \(WarpLaunch.versio)")
        #expect(carregada.avisos.isEmpty)
    }

    @Test func noDeixaFitxersTemporals() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        var empremta = try m.desa(configuracio(), sobre: nil)
        empremta = try m.desa(configuracio("altre"), sobre: empremta)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    @Test func llegirNoEscriuNiCreaRes() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        try m.desa(configuracio(), sobre: nil)
        let abans = try Data(contentsOf: m.fitxer)
        let dataAbans = try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.modificationDate] as? Date
        _ = try m.carrega()
        _ = try m.carrega()
        #expect(try Data(contentsOf: m.fitxer) == abans)
        #expect(try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.modificationDate] as? Date == dataAbans)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    // MARK: Canvis fets fora de l'app

    @Test func siElFitxerHaCanviatForaNoEsDesa() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        let aMa = Data("{\"versio\": 1, \"plantilla\": {}, \"finestres\": []}\n".utf8)
        try aMa.write(to: m.fitxer)
        #expect(throws: ErrorMagatzem.modificadaFora) { try m.desa(configuracio("nova"), sobre: empremta) }
        #expect(try Data(contentsOf: m.fitxer) == aMa)
    }

    @Test func siElFitxerSHaEsborratForaNoEsTornaACrear() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.removeItem(at: m.fitxer)
        #expect(throws: ErrorMagatzem.modificadaFora) { try m.desa(configuracio(), sobre: empremta) }
        #expect(!FileManager.default.fileExists(atPath: m.fitxer.path))
    }

    @Test func siElFitxerSHaCreatForaNoEsTrepitja() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let deFora = try configuracio("de fora").json()
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try deFora.write(to: m.fitxer)
        #expect(throws: ErrorMagatzem.modificadaFora) { try m.desa(configuracio(), sobre: nil) }
        #expect(try Data(contentsOf: m.fitxer) == deFora)
    }

    @Test func unFitxerMalmesNoEsCarregaINoEsToca() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        let malmes = Data("{\n  \"versio\": 1,,\n}".utf8)
        try malmes.write(to: m.fitxer)
        #expect(throws: ErrorMagatzem.format(.jsonMalmes(linia: 2, columna: 15))) { try m.carrega() }
        #expect(try Data(contentsOf: m.fitxer) == malmes)
    }

    // MARK: Còpies

    @Test func faCopiaDelQueHiHaviaAbansDeSobreescriure() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let primera = try m.desa(configuracio(), sobre: nil, copia: .sessio)
        #expect(contingut(m.carpeta) == ["configuracio.json"])  // no hi havia res per copiar
        try m.desa(configuracio("altre"), sobre: primera, copia: .sessio)
        #expect(contingut(m.copies) == ["configuracio-20261103-102030-sessio.json"])
        #expect(try Data(contentsOf: m.copies.appending(path: "configuracio-20261103-102030-sessio.json")) == primera)
    }

    @Test func duesCopiesElMateixSegonNoEsTrepitgen() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        var empremta = try m.desa(configuracio("a"), sobre: nil)
        empremta = try m.desa(configuracio("b"), sobre: empremta, copia: .esborrat)
        empremta = try m.desa(configuracio("c"), sobre: empremta, copia: .esborrat)
        #expect(contingut(m.copies) == ["configuracio-20261103-102030-esborrat-2.json", "configuracio-20261103-102030-esborrat.json"])
    }

    @Test func noFaCopiaNiEscriuSiNoHiHaCanvis() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        let dataAbans = try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.modificationDate] as? Date
        #expect(try m.desa(configuracio(), sobre: empremta, copia: .sessio) == empremta)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
        #expect(try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.modificationDate] as? Date == dataAbans)
    }

    @Test func guardaLes20CopiesMesRecentsINoTocaLesAltres() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let fm = FileManager.default
        try fm.createDirectory(at: m.copies, withIntermediateDirectories: true)
        // 25 còpies antigues, de l'1 al 25 d'octubre, i dos fitxers que no són de l'app.
        for dia in 1...25 {
            let url = m.copies.appending(path: String(format: "configuracio-202610%02d-090000-sessio.json", dia))
            try Data("{}".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000 + Double(dia) * 86_400)],
                                 ofItemAtPath: url.path)
        }
        // Fitxers d'en David, alguns amb noms que s'assemblen als de l'app: no es toquen mai.
        let aliens = ["nota.txt", "abans-migracio-v1.json", "configuracio-bona.json",
                      "configuracio-20260901-090000-sessio.json.bak", "configuracio-20260901-090000-altre.json",
                      "configuracio-20260901-090000-sessio-1.json", "configuracio-2026091-090000-sessio.json"]
        for nom in aliens { try Data("meva".utf8).write(to: m.copies.appending(path: nom)) }
        // Una carpeta i un enllaç amb el nom exacte d'una còpia, més antics que totes les còpies.
        let carpetaAliena = m.copies.appending(path: "configuracio-20260901-080000-sessio.json")
        try fm.createDirectory(at: carpetaAliena, withIntermediateDirectories: true)
        try Data("dins".utf8).write(to: carpetaAliena.appending(path: "nota.txt"))
        try fm.createSymbolicLink(atPath: m.copies.appending(path: "configuracio-20260901-070000-sessio.json").path,
                                  withDestinationPath: "nota.txt")

        let empremta = try m.desa(configuracio(), sobre: nil)
        try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio)

        let queden = contingut(m.copies)
        for nom in aliens { #expect(queden.contains(nom), "\(nom) no s'havia d'esborrar") }
        #expect(queden.contains("configuracio-20260901-080000-sessio.json/nota.txt"))
        #expect(queden.contains("configuracio-20260901-070000-sessio.json"))
        let propies = m.copiesPropies().map(\.lastPathComponent)
        #expect(propies.count == MagatzemConfiguracio.maxCopies)
        #expect(propies.first == "configuracio-20261103-102030-sessio.json")
        #expect(propies.contains("configuracio-20261103-102030-sessio.json"))
        // Han caigut les 6 més antigues (de l'1 al 6 d'octubre).
        #expect(!propies.contains("configuracio-20261006-090000-sessio.json"))
        #expect(propies.contains("configuracio-20261007-090000-sessio.json"))
    }

    @Test func siLaCopiaFallaNoEsDesa() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        // `copies` és un fitxer: no s'hi pot crear la carpeta.
        try Data("no és una carpeta".utf8).write(to: m.copies)
        #expect {
            try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio)
        } throws: { error in
            if case .copiaFallida = error as? ErrorMagatzem { return true }
            return false
        }
        #expect(try Data(contentsOf: m.fitxer) == empremta)
    }

    // MARK: Fitxer

    @Test func unEnllacSimbolicEsConserva() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let real = tmp.url("dotfiles/configuracio.json")
        try tmp.carpeta("dotfiles")
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        let primera = try configuracio().json()
        try primera.write(to: real)
        try FileManager.default.createSymbolicLink(at: m.fitxer, withDestinationURL: real)

        let carregada = try #require(try m.carrega())
        try m.desa(configuracio("altre"), sobre: carregada.empremta)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: m.fitxer.path) == real.path)
        #expect(try Configuracio.llegeix(Data(contentsOf: real), inici: inici).configuracio.finestres[0].nom == "altre")
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    @Test func conservaElsPermisosDelFitxer() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: m.fitxer.path)
        try m.desa(configuracio("altre"), sobre: empremta)
        let permisos = try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.posixPermissions] as? Int
        #expect(permisos == 0o600)
    }

    @Test func desaLaFormaCanonica() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        var c = configuracio()
        c.finestres[0].pestanyes[0].carpeta = "~/GitHub/botiga"
        c.finestres[0].pestanyes[0].claude = ClaudePestanya(esforc: "ultracode", nom: "")
        try m.desa(c, sobre: nil)
        let desada = try #require(try m.carrega()).configuracio.finestres[0].pestanyes[0]
        #expect(desada.carpeta == "/Users/prova/GitHub/botiga")
        #expect(desada.claude == ClaudePestanya(esforc: "xhigh", ultracode: true))
    }

    @Test func unDesatQueFallaNoEsborraCopies() throws {
        // Fitxer només de lectura: cap intent no ha de tocar les 20 còpies, ni afegir-ne.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let anteriors = try posaCopies(m, dies: 1...20, mes: "10")
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: m.fitxer.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path) }
        for _ in 1...3 {
            #expect(error { try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio) }?.esEscriptura == true)
        }
        #expect(m.copiesPropies().map(\.lastPathComponent).sorted() == anteriors)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(contingut(m.carpeta).filter { !$0.hasPrefix("copies") } == ["configuracio.json"])
    }

    @Test func unRenameQueFallaNoEsborraCopiesNiLesRepeteix() throws {
        // La còpia ja s'ha fet quan falla el rename: no es pot haver esborrat cap còpia antiga, i els reintents
        // no n'han de fer més.
        let tmp = try CarpetaTemporal()
        var m = magatzem(tmp)
        let anteriors = try posaCopies(m, dies: 1...20, mes: "10")
        let empremta = try m.desa(configuracio(), sobre: nil)
        m.reanomena = { _, _ in
            errno = EIO
            return -1
        }
        for _ in 1...3 {
            #expect(error { try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio) }?.esEscriptura == true)
        }
        let nova = "configuracio-20261103-102030-sessio.json"
        #expect(m.copiesPropies().map(\.lastPathComponent).sorted() == (anteriors + [nova]).sorted())
        #expect(try Data(contentsOf: m.copies.appending(path: nova)) == empremta)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(contingut(m.carpeta).filter { !$0.hasPrefix("copies") } == ["configuracio.json"])
    }

    @Test func noRepeteixUnaCopiaIgualALaDarrera() throws {
        // La darrera còpia ja té el que hi ha al disc (un desat anterior va fallar després de fer-la).
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.createDirectory(at: m.copies, withIntermediateDirectories: true)
        try empremta.write(to: m.copies.appending(path: "configuracio-20261103-102000-sessio.json"))
        try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio)
        #expect(contingut(m.copies) == ["configuracio-20261103-102000-sessio.json"])
    }

    @Test func siElRellotgeVaEnrereLaCopiaNovaEsConserva() throws {
        // 20 còpies «del futur» (de desembre): la nova, del 3 de novembre, no pot caure a la mateixa poda.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        try posaCopies(m, dies: 1...20, mes: "12")
        let empremta = try m.desa(configuracio(), sobre: nil)
        try m.desa(configuracio("altre"), sobre: empremta, copia: .importacio)
        let propies = m.copiesPropies().map(\.lastPathComponent)
        #expect(propies.count == MagatzemConfiguracio.maxCopies)
        #expect(propies.contains("configuracio-20261103-102030-importacio.json"))
        #expect(!propies.contains("configuracio-20261201-090000-sessio.json"))
        #expect(try Data(contentsOf: m.copies.appending(path: "configuracio-20261103-102030-importacio.json")) == empremta)
    }

    @Test func lesCopiesTenenElsPermisosDelFitxer() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: m.fitxer.path)
        try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio)
        let copia = m.copies.appending(path: "configuracio-20261103-102030-sessio.json")
        #expect(try FileManager.default.attributesOfItem(atPath: copia.path)[.posixPermissions] as? Int == 0o600)
    }

    // MARK: Fitxers editats a mà

    @Test func unFitxerEditatAMaEsCopiaEncaraQueNoEsDemani() throws {
        // La clau «notes» no la coneix l'app: l'avís diu que la còpia la conserva, i ha de ser veritat.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let aMa = Data("""
            {"versio": 1, "notes": "no tocar: producció", "plantilla": {},
             "finestres": [{"id": "\(uuid(1))", "nom": "a", "pestanyes": []}]}

            """.utf8)
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try aMa.write(to: m.fitxer)
        var carregada = try #require(try m.carrega())
        #expect(carregada.avisos == [.clauDesconeguda(cami: "notes")])
        carregada.configuracio.finestres[0].nom = "b"
        let desada = try m.desa(carregada.configuracio, sobre: carregada.empremta)
        #expect(contingut(m.copies) == ["configuracio-20261103-102030-fora.json"])
        #expect(try Data(contentsOf: m.copies.appending(path: "configuracio-20261103-102030-fora.json")) == aMa)
        // Ara el fitxer ja és com l'escriu l'app: el desat següent no en fa cap altra.
        carregada.configuracio.finestres[0].nom = "c"
        try m.desa(carregada.configuracio, sobre: desada)
        #expect(contingut(m.copies).count == 1)
    }

    @Test func unaCarpetaRelativaNoFaUnaCopiaACadaDesat() throws {
        // L'avís de carpeta no absoluta no perd res en desar (la carpeta es desa tal com és). Si fes una còpia
        // «fora» a cada desat, en 20 desats s'esborrarien les còpies bones.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        var config = configuracio()
        config.finestres[0].pestanyes[0].carpeta = "GitHub/botiga"
        var empremta = try m.desa(config, sobre: nil)
        #expect(try #require(try m.carrega()).avisos.contains {
            if case .carpetaNoAbsoluta = $0 { true } else { false }
        })
        for n in 1...25 {
            config.finestres[0].nom = "nom \(n)"
            empremta = try m.desa(config, sobre: empremta)
        }
        #expect(contingut(m.copies).isEmpty)
    }

    @Test func esPotDesarSobreUnFitxerEditatAMa() throws {
        // L'empremta són els bytes crus del disc, no la forma canònica: si no, no es podria desar mai.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let aMa = Data("""
            {  "versio": 1,
               "plantilla": {"esforc": "ultracode"},
               "finestres": [{"id": "\(uuid(1))", "nom": "a",
                              "pestanyes": [{"id": "\(uuid(2))", "carpeta": "~/GitHub/botiga", "claude": {}}]}]}
            """.utf8)
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try aMa.write(to: m.fitxer)
        var carregada = try #require(try m.carrega())
        carregada.configuracio.finestres[0].nom = "b"
        try m.desa(carregada.configuracio, sobre: carregada.empremta, copia: .sessio)
        #expect(try #require(try m.carrega()).configuracio.finestres[0].nom == "b")
        #expect(contingut(m.copies) == ["configuracio-20261103-102030-sessio.json"])
        #expect(try Data(contentsOf: m.copies.appending(path: "configuracio-20261103-102030-sessio.json")) == aMa)
    }

    // MARK: Errors

    @Test func unFitxerQueNoEsPotLlegirNoEsTrepitja() throws {
        // Si «no es pot llegir» es confongués amb «no hi és», l'app en crearia un de nou al damunt, sense còpia.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: m.fitxer.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path) }
        #expect(error { _ = try m.carrega() }?.esLectura == true)
        #expect(error { try m.desa(configuracio("nova"), sobre: nil) }?.esLectura == true)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    @Test func esDesaAmbUnFitxerNouINoSobreElMateix() throws {
        // L'escriptura atòmica substitueix el fitxer (inode nou): un tall a mitja escriptura no el deixa a mitges.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        let abans = try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.systemFileNumber] as? Int
        try m.desa(configuracio("altre"), sobre: empremta)
        let despres = try FileManager.default.attributesOfItem(atPath: m.fitxer.path)[.systemFileNumber] as? Int
        #expect(abans != nil && despres != nil && abans != despres)
    }

    @Test func siNoEsPotEscriureALaCarpetaNoEsTocaRes() throws {
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: m.carpeta.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: m.carpeta.path) }
        #expect(error { try m.desa(configuracio("altre"), sobre: empremta, copia: .sessio) }?.esEscriptura == true)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    @Test func siLaVerificacioFallaNoEsTocaRes() throws {
        // Dues finestres amb el mateix id: en tornar-lo a llegir, una tindria un id nou. No s'ha d'escriure.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        let empremta = try m.desa(configuracio(), sobre: nil)
        var c = configuracio()
        c.finestres.append(c.finestres[0])
        #expect(error { try m.desa(c, sobre: empremta, copia: .sessio) } == .verificacioFallida)
        #expect(try Data(contentsOf: m.fitxer) == empremta)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
    }

    @Test func unEnllacTrencatEsUnErrorINoEsSubstitueix() throws {
        // Dotfiles encara sense clonar: no és «no hi ha configuració».
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: m.fitxer.path, withDestinationPath: "../dotfiles/configuracio.json")
        #expect(error { _ = try m.carrega() }?.esLectura == true)
        #expect(error { try m.desa(configuracio(), sobre: nil) }?.esLectura == true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: m.fitxer.path) == "../dotfiles/configuracio.json")
    }

    @Test func unEnllacRelatiuEsConserva() throws {
        // Com els que crea GNU stow.
        let tmp = try CarpetaTemporal()
        let m = magatzem(tmp)
        try tmp.carpeta("dotfiles")
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        let real = tmp.url("dotfiles/configuracio.json")
        try configuracio().json().write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(atPath: m.fitxer.path, withDestinationPath: "../dotfiles/configuracio.json")

        let carregada = try #require(try m.carrega())
        try m.desa(configuracio("altre"), sobre: carregada.empremta)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: m.fitxer.path) == "../dotfiles/configuracio.json")
        #expect(try Configuracio.llegeix(Data(contentsOf: real), inici: inici).configuracio.finestres[0].nom == "altre")
        #expect(try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int == 0o600)
        #expect(contingut(m.carpeta) == ["configuracio.json"])
        #expect(contingut(tmp.url("dotfiles")) == ["configuracio.json"])
    }

    @Test(arguments: [
        ("configuracio-20261103-102030-sessio.json", true),
        ("configuracio-20261103-102030-esborrat-2.json", true),
        ("configuracio-20261103-102030-fora-15.json", true),
        ("configuracio-20261103-102030-sessio-1.json", false),
        ("configuracio-20261103-102030-sessio-x.json", false),
        ("configuracio-20261103-102030-altre.json", false),
        ("configuracio-2026110-102030-sessio.json", false),
        ("configuracio-bona.json", false),
        ("configuracio-20261103-102030-sessio.json.bak", false),
    ])
    func nomsDeCopiesPropies(nom: String, propia: Bool) {
        #expect((ClauCopia(nom: nom) != nil) == propia)
    }

    @Test func lesCopiesSOrdenenPelNom() {
        let noms = ["configuracio-20261103-102030-esborrat-10.json", "configuracio-20261103-102030-esborrat.json",
                    "configuracio-20261103-102030-esborrat-2.json", "configuracio-20261102-235959-sessio.json"]
        #expect(noms.compactMap(ClauCopia.init(nom:)).sorted().map(\.nom) == [
            "configuracio-20261102-235959-sessio.json", "configuracio-20261103-102030-esborrat.json",
            "configuracio-20261103-102030-esborrat-2.json", "configuracio-20261103-102030-esborrat-10.json",
        ])
    }

    @Test func laCarpetaDeLaConfiguracioEsLaDeD8() {
        // Sense escriure la ruta sencera: la prova de guarda no deixa que cap prova l'esmenti.
        #expect(Rutes.carpetaConfiguracio(inici: "/Users/prova").pathComponents == ["/", "Users", "prova", ".config", "warp-launch"])
    }
}
