import Foundation
import Testing
@testable import WarpLaunchCore

// docs/disseny.md, secció 11, 2.3. Sempre en una carpeta temporal.

private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
/// Un Mac encès fa molta estona.
private let encesa: TimeInterval = 100_000

private final class Carpeta {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-intent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var magatzem: MagatzemIntent { MagatzemIntent(carpeta: url) }
    func escriu(_ text: String) throws { try Data(text.utf8).write(to: magatzem.fitxer) }
    var alDisc: IntentActualitzacio.Lectura { magatzem.carrega() }
}

private func pendent(_ objectiu: String = "0.32.1", _ tipus: IntentActualitzacio.Tipus = .automatica, fa segons: TimeInterval = 10) -> IntentActualitzacio.Pendent {
    IntentActualitzacio.Pendent(objectiu: objectiu, tipus: tipus, hora: t0 - segons)
}

@Suite struct IntentActualitzacioTests {
    @Test func senseFitxerNoEsCreaRes() throws {
        let c = try Carpeta()
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(r == .init(reobertura: nil, intent: IntentActualitzacio(), efecte: .res))
        #expect(!FileManager.default.fileExists(atPath: c.magatzem.fitxer.path))
    }

    @Test func senseCapPendentEsDeixaComEra() throws {
        let c = try Carpeta()
        let intent = IntentActualitzacio(fallades: 1, versioFallada: "0.32.2")
        try c.magatzem.desa(intent)
        let abans = try Data(contentsOf: c.magatzem.fitxer)
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .res && r.reobertura == nil && r.intent == intent)
        #expect(try Data(contentsOf: c.magatzem.fitxer) == abans)
    }

    @Test(arguments: [("0.32.1", IntentActualitzacio.Tipus.automatica), ("0.32.2", .demanada)])
    func exitAmbLaVersioObjectiuOMesNova(actual: String, tipus: IntentActualitzacio.Tipus) throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1", tipus), fallades: 1, versioFallada: "0.32.0"))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: actual, ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .exit && r.reobertura == tipus)
        #expect(r.intent == IntentActualitzacio(), "ni el pendent ni la fallada, que ja s'ha superat")
        #expect(c.alDisc == .llegit(r.intent), "el pendent ja no és al fitxer")
    }

    /// Instal·lada en sortir, amb Homebrew o a mà, no hi ha pendent. Si no s'oblida la fallada, amb dues, cap versió futura no
    /// es tornaria a aplicar sola.
    @Test(arguments: ["0.32.1", "0.32.2"])
    func unaFalladaSuperadaSensePendentSOblida(actual: String) throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(fallades: 2, versioFallada: "0.32.1"))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: actual, ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .res && r.reobertura == nil)
        #expect(r.intent == IntentActualitzacio())
        #expect(!r.intent.bloquejaAutomatic(candidat: "0.32.3"))
        #expect(c.alDisc == .llegit(IntentActualitzacio()))
    }

    @Test func unaFalladaNoSuperadaEsConserva() throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(fallades: 2, versioFallada: "0.32.1"))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.0", ara: t0, segonsEncesa: encesa)
        #expect(r.intent == IntentActualitzacio(fallades: 2, versioFallada: "0.32.1"))
        #expect(r.intent.bloquejaAutomatic(candidat: "0.32.3"))
    }

    @Test func falladaAmbUnaVersioAnterior() throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1"), fallades: 0))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.0", ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .fallada && r.reobertura == nil)
        #expect(r.intent == IntentActualitzacio(fallades: 1, versioFallada: "0.32.1"))
        #expect(c.alDisc == .llegit(r.intent))
    }

    @Test func lesFalladesSAcumulenFinsQueUnaActualitzacioVaBe() throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1"), fallades: 1, versioFallada: "0.32.0"))
        var r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.31.9", ara: t0, segonsEncesa: encesa)
        #expect(r.intent.fallades == 2 && r.intent.versioFallada == "0.32.1")
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.2"), fallades: 2, versioFallada: "0.32.1"))
        r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.2", ara: t0, segonsEncesa: encesa)
        #expect(r.intent.fallades == 0 && r.intent.versioFallada == nil)
    }

    /// L'hora de l'intent compta de 5 s enrere fins a 300 s; fora d'aquí no se sap si és aquesta reobertura.
    @Test(arguments: [
        (0.0, true), (299.0, true), (300.0, true), (301.0, false), (10_000.0, false),
        (-5.0, true), (-6.0, false), (-3600.0, false),
    ])
    func laReoberturaNomesSiLHoraEsRecent(fa segons: TimeInterval, reoberta: Bool) throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1", .automatica, fa: segons)))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .exit)
        #expect(r.reobertura == (reoberta ? .automatica : nil), "\(segons)")
        #expect(r.intent.pendent == nil && r.intent.fallades == 0)
    }

    /// Un intent de fa poc, però d'abans d'encendre el Mac: és un reinici, i ha de sortir el full d'«Obre-ho tot».
    @Test(arguments: [(30.0, 120.0, true), (120.0, 30.0, false), (120.0, 120.0, false)])
    func unReiniciDelMacNoEsUnaReobertura(fa segons: TimeInterval, encesa: TimeInterval, reoberta: Bool) throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1", .demanada, fa: segons)))
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .exit)
        #expect(r.reobertura == (reoberta ? .demanada : nil))
    }

    @Test func nomesUnCop() throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1")))
        let primera = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        let segona = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(primera.reobertura == .automatica)
        #expect(segona.reobertura == nil && segona.efecte == .res)

        // Una fallada tampoc no es compta dues vegades.
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.2")))
        _ = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        let altra = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(altra.intent.fallades == 1 && altra.efecte == .res)
    }

    @Test(arguments: [
        "{no és json",
        "[]",
        #"{"fallades":0}"#,
        #"{"versio":"1","fallades":0}"#,
        #"{"versio":0,"fallades":0}"#,
        #"{"versio":1}"#,
        #"{"versio":1,"fallades":-1}"#,
        #"{"versio":1,"fallades":"a"}"#,
        #"{"versio":1,"fallades":0,"versioFallada":"nova"}"#,
        #"{"versio":1,"fallades":0,"pendent":{"objectiu":"x","tipus":"automatica","hora":"2026-11-09T10:42:00Z"}}"#,
        #"{"versio":1,"fallades":0,"pendent":{"objectiu":"0.32.1","tipus":"altra","hora":"2026-11-09T10:42:00Z"}}"#,
        #"{"versio":1,"fallades":0,"pendent":{"objectiu":"0.32.1","tipus":"automatica","hora":"ahir"}}"#,
        #"{"versio":2,"fallades":0,"nou":true}"#,
    ])
    func unFitxerMalFormatEsComSiNoHiFos(text: String) throws {
        let c = try Carpeta()
        try c.escriu(text)
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.31.0", ara: t0, segonsEncesa: encesa)
        guard case .ignorat = r.efecte else {
            Issue.record("\(r.efecte)")
            return
        }
        #expect(r.reobertura == nil && r.intent == IntentActualitzacio())
        #expect(!r.intent.bloquejaAutomatic(candidat: "0.32.1"), "no bloqueja res")
        #expect(try String(contentsOf: c.magatzem.fitxer, encoding: .utf8) == text, "no s'hi toca")
    }

    @Test func laFormaDelFitxer() throws {
        let text = #"{"versio":1,"pendent":{"objectiu":"0.32.1","tipus":"automatica","hora":"2026-11-09T10:42:00Z"},"fallades":0,"versioFallada":null}"#
        let esperat = IntentActualitzacio(pendent: IntentActualitzacio.Pendent(
            objectiu: "0.32.1", tipus: .automatica, hora: ISO8601DateFormatter().date(from: "2026-11-09T10:42:00Z")!))
        #expect(IntentActualitzacio.llegeix(Data(text.utf8)) == .llegit(esperat))
        #expect(IntentActualitzacio.llegeix(try esperat.json()) == .llegit(esperat))
        let objecte = try #require(JSONSerialization.jsonObject(with: try esperat.json()) as? [String: Any])
        #expect(Set(objecte.keys) == ["versio", "pendent", "fallades"], "sense res de més: els nuls no s'escriuen")
    }

    @Test func lHoraEsDesaASegonsSencers() throws {
        let p = IntentActualitzacio.Pendent(objectiu: "0.32.1", tipus: .demanada, hora: t0 + 0.75)
        #expect(p.hora == t0)
        let intent = IntentActualitzacio(pendent: p)
        #expect(IntentActualitzacio.llegeix(try intent.json()) == .llegit(intent))
    }

    @Test func siNoEsPotDesarElResultatEsDiu() throws {
        let c = try Carpeta()
        try c.magatzem.desa(IntentActualitzacio(pendent: pendent("0.32.1")))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: c.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: c.url.path) }
        let r = IntentActualitzacio.enArrencar(magatzem: c.magatzem, versioActual: "0.32.1", ara: t0, segonsEncesa: encesa)
        #expect(r.efecte == .exit && r.reobertura == .automatica)
        #expect(r.errorDesant != nil)
    }

    @Test func quanEsBloquejaElReiniciSol() {
        #expect(!IntentActualitzacio().bloquejaAutomatic(candidat: "0.32.1"))
        #expect(IntentActualitzacio(fallades: 1, versioFallada: "0.32.1").bloquejaAutomatic(candidat: "0.32.1"))
        #expect(!IntentActualitzacio(fallades: 1, versioFallada: "0.32.1").bloquejaAutomatic(candidat: "0.32.2"), "una altra versió")
        #expect(IntentActualitzacio(fallades: 2, versioFallada: "0.32.1").bloquejaAutomatic(candidat: "0.32.2"), "dues en total")
    }

    @Test func elNomEsDelsConegutsDelDiagnostic() {
        #expect(Anonimitzador.coneguts.contains(IntentActualitzacio.nomFitxer))
        #expect(IntentActualitzacio.nomFitxer == "actualitzacio.json")
    }
}
