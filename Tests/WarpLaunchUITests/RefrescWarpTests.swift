import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// D19: l'ajust de la restauració sempre desactivat, i la foto de les finestres. Tot fals: cap fitxer ni cap Warp de debò.

private func foto(_ panes: [String], titol: String = "T") -> LecturaWarp {
    LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: panes.enumerated().map { i, p in
        PestanyaLlegida(posicio: i, titol: titol, color: nil, panes: [
            PaneLlegit(uuid: p, carpeta: "/x", origenCarpeta: .pane, carpetaExisteix: true),
        ])
    })], sessionsSensePestanya: [], avisos: [])
}

private final class Mon: @unchecked Sendable {
    private let pany = NSLock()
    private var estat = (ajust: false, obert: true, canvis: [Bool](), esperes: 0, fallades: 0, potPosar: true, posats: 0,
                         mesTard: 0, mesTardDesactivar: 0, ajustMesTard: 0, quanSObriWarp: 0)
    private var lectura: @Sendable (Bool, Int) -> LecturaWarp = { _, _ in LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) }
    var enEsperar: @Sendable (Int) -> Void = { _ in }

    var ajust: Bool { get { pany.withLock { estat.ajust } } set { pany.withLock { estat.ajust = newValue } } }
    var obert: Bool { get { pany.withLock { estat.obert } } set { pany.withLock { estat.obert = newValue } } }
    var canvis: [Bool] { pany.withLock { estat.canvis } }
    var esperes: Int { pany.withLock { estat.esperes } }
    /// Quantes vegades més falla el pròxim `posa`.
    var fallades: Int { get { pany.withLock { estat.fallades } } set { pany.withLock { estat.fallades = newValue } } }
    /// Quantes vegades més el pròxim `posa` torna `.mesTard`, sense canviar res (0.31.3: `settings.toml` acaba de canviar).
    var mesTard: Int { get { pany.withLock { estat.mesTard } } set { pany.withLock { estat.mesTard = newValue } } }
    /// Com `mesTard`, però només per desactivar-lo.
    var mesTardDesactivar: Int {
        get { pany.withLock { estat.mesTardDesactivar } } set { pany.withLock { estat.mesTardDesactivar = newValue } }
    }
    /// Quantes vegades més el pròxim `ajust` torna `nil` (0.31.3).
    var ajustMesTard: Int {
        get { pany.withLock { estat.ajustMesTard } } set { pany.withLock { estat.ajustMesTard = newValue } }
    }
    /// Cada crida a `posa`, també les que no canvien res.
    var posats: Int { pany.withLock { estat.posats } }
    /// Quantes vegades més desactivar-lo torna `.quanSObriWarp`, sense canviar res (ronda 5: sense `settings.toml`, i amb
    /// Warp tancat o acabat d'obrir).
    var quanSObriWarp: Int {
        get { pany.withLock { estat.quanSObriWarp } } set { pany.withLock { estat.quanSObriWarp = newValue } }
    }

    /// `(ajust activat, segons passats)` → què hi ha a la base.
    func base(_ cos: @escaping @Sendable (Bool, Int) -> LecturaWarp) { pany.withLock { lectura = cos } }

    var entorn: RefrescWarp.Entorn {
        RefrescWarp.Entorn(
            ajust: { [self] in
                pany.withLock {
                    guard estat.ajustMesTard == 0 else {
                        estat.ajustMesTard -= 1
                        return nil
                    }
                    return estat.ajust
                }
            },
            posa: { [self] nou in
                try pany.withLock {
                    estat.posats += 1
                    if estat.fallades > 0 {
                        estat.fallades -= 1
                        throw AjustRestauracio.Refusat(description: "no s'ha pogut escriure")
                    }
                    if estat.mesTard > 0 {
                        estat.mesTard -= 1
                        return .mesTard
                    }
                    if !nou, estat.mesTardDesactivar > 0 {
                        estat.mesTardDesactivar -= 1
                        return .mesTard
                    }
                    if !nou, estat.quanSObriWarp > 0 {
                        estat.quanSObriWarp -= 1
                        return .quanSObriWarp
                    }
                    let canvia = estat.ajust != nou
                    if canvia { estat.canvis.append(nou) }
                    estat.ajust = nou
                    return canvia ? .escrit : .jaHiEra
                }
            },
            warpObert: { [self] in obert },
            llegeixBase: { [self] in pany.withLock { lectura(estat.ajust, estat.esperes) } },
            espera: { [self] _ in
                let n = pany.withLock { estat.esperes += 1; return estat.esperes }
                enEsperar(n)
                try Task.checkCancellation()
            })
    }
}

/// Els terminals vius, com els diu la lectura.
private func amb(_ lectura: LecturaWarp, terminals: [String]) -> LecturaWarp {
    var l = lectura
    l.terminals = terminals.enumerated().map { TerminalViu(pid: Int32($0), carpeta: nil, pane: $1) }
    return l
}

@MainActor
@Suite struct RefrescWarpTests {
    /// La foto és antiga fins que l'ajust porta 2 s activat: s'acaba tot just Warp desa, i deixa l'ajust desactivat.
    @Test func quanWarpDesaEsDesactivaDeSeguida() async throws {
        let mon = Mon()
        mon.base { _, segons in amb(segons >= 2 ? foto(["aa", "bb"]) : foto(["aa"]), terminals: ["aa", "bb"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        let lectura = try await r.refresca().get()
        #expect(lectura.finestres[0].pestanyes.count == 2)
        #expect(lectura.avisos.isEmpty)
        #expect(mon.canvis == [true, false])
        #expect(mon.esperes == 2)
        #expect(!mon.ajust)
    }

    /// Sense cap canvi i tot quadra: l'estona mínima, no els 30 s.
    @Test func senseCanvisNomesLEstonaMinima() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        _ = try await RefrescWarp(entorn: mon.entorn).refresca().get()
        #expect(mon.esperes == RefrescWarp.segonsMinim)
        #expect(mon.canvis == [true, false])
    }

    /// Warp no desa: 30 s com a màxim, l'ajust acaba desactivat i la lectura ho avisa.
    @Test func siWarpNoDesaAvisaAlsTrentaSegons() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        let lectura = try await RefrescWarp(entorn: mon.entorn).refresca().get()
        #expect(mon.esperes == RefrescWarp.segonsMaxim)
        #expect(!mon.ajust)
        #expect(lectura.avisos == [lectura.avisFinestresAntigues])
    }

    /// Warp tancat: es llegeix el que hi ha i no s'escriu res: amb l'ajust activat, en obrir-se restauraria les finestres.
    @Test func ambWarpTancatLlegeixIlaFotoSenseEscriure() async throws {
        let mon = Mon()
        mon.obert = false
        mon.base { _, _ in foto(["aa"]) }
        let lectura = try await RefrescWarp(entorn: mon.entorn).refresca().get()
        #expect(lectura.finestres.count == 1)
        #expect(lectura.avisFoto == LecturaWarp.avisFotoWarpTancat)
        #expect(lectura.avisos == [LecturaWarp.avisFotoWarpTancat])
        #expect(mon.canvis.isEmpty && mon.esperes == 0)
    }

    /// Sense cap Warp ni la seva base, la lectura de l'app no té finestres (`Lector.llegeixDeLApp`): no hi ha cap foto, i no
    /// diu que n'és una d'antiga. Ni a la lectura ni al menú.
    @Test func senseCapWarpNoDiuQueEsUnaFoto() async throws {
        let mon = Mon()
        mon.obert = false
        mon.base { _, _ in
            var lectura = LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: [], warpObert: false,
                                      warpDesaFinestres: false)
            lectura.warpPreview = .capWarp
            return lectura
        }
        let lectura = try await RefrescWarp(entorn: mon.entorn).refresca().get()
        #expect(lectura.avisFoto == nil && lectura.avisos.isEmpty && lectura.warpPreview == .capWarp)
        #expect(mon.canvis.isEmpty && mon.esperes == 0)
        let estat = EstatWarp(lector: { LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) })
        estat.refresc = RefrescWarp(entorn: mon.entorn)
        await estat.llegeixAmbFinestres()
        #expect(estat.avisFoto == nil && estat.descripcio == "Warp: 0 terminals · 0 sessions de Claude")
    }

    /// Warp es tanca a mig refresc: es desactiva de seguida, sense esperar.
    @Test func siWarpEsTancaAMigRefrescEsDesactiva() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        mon.enEsperar = { [unowned mon] n in if n == 3 { mon.obert = false } }
        let lectura = try await RefrescWarp(entorn: mon.entorn).refresca().get()
        #expect(mon.esperes == 3 && !mon.ajust)
        #expect(lectura.avisFoto == LecturaWarp.avisFotoWarpTancat)
    }

    /// Dos refrescos alhora són un de sol.
    @Test func dosRefrescosAlhoraSonUnDeSol() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        async let a = r.refresca()
        async let b = r.refresca()
        _ = await (a, b)
        #expect(mon.canvis == [true, false])
    }

    /// `vigila`: fora d'un refresc l'ajust es torna a desactivar (app penjada, núvol de Warp o a mà).
    @Test func laVigilanciaDesactivaLAjust() {
        let mon = Mon()
        mon.ajust = true
        let r = RefrescWarp(entorn: mon.entorn)
        r.vigila()
        #expect(!mon.ajust && r.avis == nil)
        r.vigila()
        #expect(mon.canvis == [false])
    }

    /// Durant un refresc no ha de desactivar l'ajust.
    @Test func laVigilanciaNoToquaUnRefrescEnCurs() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let continua = AsyncStream<Void>.makeStream()
        let comenca = AsyncStream<Void>.makeStream()
        var entorn = mon.entorn
        let primera = entorn.espera
        entorn.espera = { d in
            comenca.continuation.yield()
            for await _ in continua.stream { break }
            try await primera(d)
        }
        let bloquejat = RefrescWarp(entorn: entorn)
        let tasca = Task { await bloquejat.refresca() }
        for await _ in comenca.stream { break }
        #expect(mon.ajust)
        bloquejat.vigila()
        #expect(mon.ajust, "el refresc és obert")
        continua.continuation.finish()
        _ = await tasca.value
        #expect(!mon.ajust)
    }

    /// `tanca`, abans de sortir o d'engegar Warp: en acabar la crida ja és desactivat, sense esperar el refresc.
    @Test func tancarDesactivaAlMoment() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        let comenca = AsyncStream<Void>.makeStream()
        var entorn = mon.entorn
        let primera = entorn.espera
        entorn.espera = { d in
            comenca.continuation.yield()
            try await primera(d)
            try await Task.sleep(for: .milliseconds(20))
        }
        let r = RefrescWarp(entorn: entorn)
        let tasca = Task { await r.refresca() }
        for await _ in comenca.stream { break }
        #expect(mon.ajust)
        r.tanca()
        #expect(!mon.ajust)
        _ = await tasca.value
        #expect(!mon.ajust)
        #expect(mon.esperes < RefrescWarp.segonsMaxim)
    }

    /// Warp ha escrit el fitxer just abans: es torna a provar.
    @Test func desactivarEsTornaAProvar() {
        let mon = Mon()
        mon.ajust = true
        mon.fallades = 2
        let r = RefrescWarp(entorn: mon.entorn)
        r.tanca()
        #expect(!mon.ajust && r.avis == nil)
    }

    /// Si no es pot desactivar, el menú ho ha de dir; i la vigilància ho torna a provar.
    @Test func siNoEsPotDesactivarHoDiu() {
        let mon = Mon()
        mon.ajust = true
        mon.fallades = 3
        let r = RefrescWarp(entorn: mon.entorn)
        r.tanca()
        #expect(mon.ajust)
        #expect(r.avis?.contains("No s'ha pogut desactivar") == true)
        r.vigila()
        #expect(!mon.ajust && r.avis == nil)
    }

    /// Si no es pot activar, es llegeix el que hi ha, sense esperar.
    @Test func siNoEsPotActivarLlegeixElQueHiHa() async throws {
        let mon = Mon()
        mon.fallades = 1
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        let lectura = try await r.refresca().get()
        #expect(lectura.finestres.count == 1)
        #expect(lectura.avisFoto == lectura.avisFinestresAntigues, "encara que no es pugui refrescar, ha de dir que és antiga")
        #expect(mon.esperes == 0 && !mon.ajust)
        #expect(r.avis?.contains("No es pot activar") == true)
    }

    /// Sense poder llegir la base (sense permís), activar l'ajust no serviria de res: 0 canvis, i l'error arriba.
    @Test func senseLlegirLaBaseNoActiva() async {
        let mon = Mon()
        var entorn = mon.entorn
        entorn.llegeixBase = { throw ErrorLectura.macOSNoDeixaLlegir }
        let resultat = await RefrescWarp(entorn: entorn).refresca()
        guard case .failure = resultat else { Issue.record("havia de fallar"); return }
        #expect(mon.canvis.isEmpty && mon.esperes == 0)
    }

    /// Una alerta pot aturar la sortida: mentrestant, cap refresc activa l'ajust; si es cancel·la, tornen.
    @Test func enAturarCapRefrescActiva() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        r.atura()
        _ = await r.refresca()
        #expect(mon.canvis.isEmpty)
        r.repren()
        _ = await r.refresca()
        #expect(mon.canvis == [true, false])
    }

    /// `tanca` mentre el cicle llegeix la base d'abans: no ha d'activar l'ajust després.
    @Test func tancarAbansDActivarNoActiva() async throws {
        let mon = Mon()
        let comenca = AsyncStream<Void>.makeStream()
        let continua = AsyncStream<Void>.makeStream()
        var entorn = mon.entorn
        entorn.llegeixBase = {
            comenca.continuation.yield()
            let semafor = DispatchSemaphore(value: 0)
            Task { for await _ in continua.stream { break }; semafor.signal() }
            semafor.wait()
            return amb(foto(["aa"]), terminals: ["aa"])
        }
        let r = RefrescWarp(entorn: entorn)
        let tasca = Task { await r.refresca() }
        for await _ in comenca.stream { break }
        r.tanca()
        continua.continuation.finish()
        _ = await tasca.value
        #expect(mon.canvis.isEmpty)
    }

    // MARK: - Si `settings.toml` acaba de canviar (0.31.3)

    /// Si no se sap el valor (el fitxer acaba de canviar), la vigilància no hi escriu res ni avisa de res; d'aquí a un
    /// minut, sí.
    @Test func laVigilanciaNoFaResSiNoSeSapElValor() {
        let mon = Mon()
        mon.ajust = true
        mon.ajustMesTard = 1
        let r = RefrescWarp(entorn: mon.entorn)
        r.vigila()
        #expect(mon.ajust && mon.posats == 0 && r.avis == nil && !r.desactivacioPendent)
        r.vigila()
        #expect(!mon.ajust && mon.canvis == [false] && r.avis == nil)
    }

    /// Si en desactivar-lo el fitxer acaba de canviar, no és cap error: cap avís, i no es torna a provar de seguida (no
    /// serviria), sinó amb la vigilància següent.
    @Test func siEnDesactivarAcabaDeCanviarHoTornaAProvarSenseAvis() {
        let mon = Mon()
        mon.ajust = true
        mon.mesTard = 1
        let r = RefrescWarp(entorn: mon.entorn)
        r.vigila()
        #expect(mon.ajust && mon.posats == 1 && r.avis == nil && r.desactivacioPendent)
        r.vigila()
        #expect(!mon.ajust && mon.posats == 2 && r.avis == nil && !r.desactivacioPendent)
        // Sortint de l'app, tampoc no avisa.
        mon.ajust = true
        mon.mesTard = 1
        r.tanca()
        #expect(mon.ajust && r.avis == nil && r.desactivacioPendent)
    }

    /// Un refresc no activa l'ajust si el fitxer acaba de canviar: sense avís de l'ajust, sense esperar, i la lectura diu
    /// que la foto pot ser antiga.
    @Test func siEnActivarAcabaDeCanviarNoActivaNiAvisa() async throws {
        let mon = Mon()
        mon.mesTard = 1
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        let lectura = try await r.refresca().get()
        #expect(lectura.avisFoto == lectura.avisFinestresAntigues)
        #expect(mon.canvis.isEmpty && mon.esperes == 0 && mon.posats == 1 && r.avis == nil)
    }

    /// Al final d'un refresc, si el fitxer acaba de canviar, es torna a provar de desactivar-lo cada segon, i no d'aquí a un
    /// minut: com menys estona activat, millor.
    @Test func alFinalDUnRefrescHoTornaAProvarCadaSegon() async throws {
        let mon = Mon()
        mon.mesTardDesactivar = 2
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        _ = try await r.refresca().get()
        #expect(mon.canvis == [true, false] && !mon.ajust)
        #expect(mon.esperes == RefrescWarp.segonsMinim + 2)
        #expect(r.avis == nil && !r.desactivacioPendent)
    }

    /// Si al final del refresc el fitxer continua canviant, ho deixa per a la vigilància de cada minut, sense avís.
    @Test func siContinuaCanviantHoDeixaPerALaVigilancia() async throws {
        let mon = Mon()
        mon.mesTardDesactivar = 10
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        _ = try await r.refresca().get()
        #expect(mon.ajust && mon.esperes == RefrescWarp.segonsMinim + RefrescWarp.segonsTornaAProvar)
        #expect(r.avis == nil && r.desactivacioPendent)
        mon.mesTardDesactivar = 0
        r.vigila()
        #expect(!mon.ajust && r.avis == nil && !r.desactivacioPendent)
    }

    /// «Restaura Warp i surt…»: si el fitxer acaba de canviar, no hi escriu res, ho diu (l'ha demanat l'usuari), i el refresc
    /// continua com abans.
    @Test func siEnRetirarAcabaDeCanviarNoCanviaRes() {
        let mon = Mon()
        mon.mesTard = 1
        let r = RefrescWarp(entorn: mon.entorn)
        #expect(throws: RefrescWarp.MesTard()) { try r.retira(posant: true) }
        #expect(!mon.ajust && mon.canvis.isEmpty)
        mon.ajust = true
        r.vigila()
        #expect(!mon.ajust, "la vigilància continua")
    }

    // MARK: - Sense `settings.toml`, i amb Warp tancat o acabat d'obrir (ronda 5)

    /// Si l'ajust no crea el fitxer perquè Warp és tancat o acabat d'obrir, no és cap error: cap avís, queda pendent, i la
    /// vigilància següent ho torna a provar.
    @Test func senseElFitxerIAmbWarpTancatQuedaPendentSenseAvis() {
        let mon = Mon()
        mon.ajust = true
        mon.quanSObriWarp = 1
        let r = RefrescWarp(entorn: mon.entorn)
        r.vigila()
        #expect(mon.ajust && mon.posats == 1 && r.avis == nil && r.pendent == .quanSObriWarp && r.desactivacioPendent)
        r.vigila()
        #expect(!mon.ajust && mon.posats == 2 && r.avis == nil && r.pendent == nil)
    }

    /// Al final d'un refresc, si l'ajust no ha creat el fitxer perquè Warp s'ha tancat, no es torna a provar cada segon: no
    /// serviria. Ho fa la vigilància de cada minut.
    @Test func alFinalDUnRefrescSenseElFitxerNoHoTornaAProvarCadaSegon() async throws {
        let mon = Mon()
        mon.quanSObriWarp = 10
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        _ = try await r.refresca().get()
        #expect(mon.esperes == RefrescWarp.segonsMinim && mon.posats == 2)
        #expect(mon.ajust && r.avis == nil && r.pendent == .quanSObriWarp)
    }

    /// «Restaura Warp i surt…»: si l'ajust no pot crear el fitxer perquè Warp és tancat, no canvia res, ho diu (amb què cal
    /// fer), i el refresc continua com abans.
    @Test func siEnRetirarNoEsPotCrearElFitxerNoCanviaRes() {
        let mon = Mon()
        mon.ajust = true
        mon.quanSObriWarp = 1
        let r = RefrescWarp(entorn: mon.entorn)
        #expect(throws: RefrescWarp.QuanSObriWarp()) { try r.retira(posant: false) }
        #expect(RefrescWarp.QuanSObriWarp().description.hasPrefix("Warp no té «settings.toml», i Warp Launch només el crea "
            + "quan fa 30 s que Warp és obert"))
        #expect(mon.ajust && mon.canvis.isEmpty)
        r.vigila()
        #expect(!mon.ajust, "la vigilància continua")
    }

    // MARK: - Deixar de fer servir Warp Launch (0.31.0, decisió 3)

    /// `retira` posa l'ajust al valor d'abans, i després res no el toca: ni la vigilància de cada minut, ni sortir de l'app
    /// (encara que la sortida es cancel·li), ni un refresc, que llegeix la base tal com és.
    @Test func retirarPosaElValorIDespresNoElTocaRes() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let r = RefrescWarp(entorn: mon.entorn)
        try r.retira(posant: true)
        #expect(mon.ajust && mon.canvis == [true])
        r.vigila()
        r.tanca()
        r.atura()
        r.repren()
        r.vigila()
        let lectura = try await r.refresca().get()
        #expect(lectura.finestres.count == 1)
        #expect(mon.ajust && mon.canvis == [true] && mon.esperes == 0)
        try r.retira(posant: false)
        #expect(mon.canvis == [true], "un sol cop")
    }

    /// Sense valor (l'app no l'havia canviat mai), no s'escriu res, i després tampoc.
    @Test func retirarSenseValorNoEscriu() {
        let mon = Mon()
        mon.ajust = true
        let r = RefrescWarp(entorn: mon.entorn)
        try? r.retira(posant: nil)
        r.vigila()
        r.tanca()
        #expect(mon.ajust && mon.canvis.isEmpty)
    }

    /// A mig refresc (l'ajust activat uns segons): s'atura, i en acabar no el desactiva.
    @Test func retirarAturaElRefrescEnCurs() async throws {
        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa", "bb"]) }
        let comenca = AsyncStream<Void>.makeStream()
        let continua = AsyncStream<Void>.makeStream()
        var entorn = mon.entorn
        let primera = entorn.espera
        entorn.espera = { d in
            comenca.continuation.yield()
            for await _ in continua.stream { break }
            try await primera(d)
        }
        let r = RefrescWarp(entorn: entorn)
        let tasca = Task { await r.refresca() }
        for await _ in comenca.stream { break }
        #expect(mon.ajust && mon.canvis == [true])
        try r.retira(posant: true)
        continua.continuation.finish()
        _ = await tasca.value
        #expect(mon.ajust && mon.canvis == [true], "el cicle no l'ha tornat a desactivar")
        #expect(mon.esperes == 1)
    }

    /// Si no es pot posar, no ha canviat res, i el refresc continua com abans.
    @Test func siNoEsPotRetirarContinuaComAbans() {
        let mon = Mon()
        mon.fallades = 1
        let r = RefrescWarp(entorn: mon.entorn)
        #expect(throws: AjustRestauracio.Refusat.self) { try r.retira(posant: true) }
        #expect(!mon.ajust && mon.canvis.isEmpty)
        mon.ajust = true
        r.vigila()
        #expect(!mon.ajust, "la vigilància continua")
    }

    /// Si el permís no s'ha pogut retirar, l'ajust torna a quedar desactivat de seguida, i el refresc continua.
    @Test func desferLaRetiradaTornaADesactivar() {
        let mon = Mon()
        let r = RefrescWarp(entorn: mon.entorn)
        try? r.retira(posant: true)
        r.desfesRetirada()
        #expect(!mon.ajust && mon.canvis == [true, false])
        mon.ajust = true
        r.vigila()
        #expect(!mon.ajust)
        r.desfesRetirada()
        #expect(mon.canvis == [true, false, false], "sense retirada, res a desfer")
    }

    /// El menú diu que és una foto, i ho deixa de dir amb la lectura següent.
    @Test func elMenuDiuQueEsUnaFoto() async throws {
        let mon = Mon()
        mon.obert = false
        mon.base { _, _ in foto(["aa"]) }
        let estat = EstatWarp(lector: { LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) })
        estat.refresc = RefrescWarp(entorn: mon.entorn)
        await estat.llegeixAmbFinestres()
        #expect(estat.avisFoto == LecturaWarp.avisFotoWarpTancat)
        await estat.llegeix()
        #expect(estat.avisFoto == nil)
    }

    /// `EstatWarp`: sense refresc, llegeix com sempre; amb, en fa servir la lectura i avisa qui escolta.
    @Test func estatWarpLlegeixAmbFinestres() async throws {
        let senseRefresc = EstatWarp(lector: { amb(foto(["zz"]), terminals: []) })
        #expect(try await senseRefresc.llegeixAmbFinestres().get().finestres[0].pestanyes[0].panes[0].uuid == "zz")

        let mon = Mon()
        mon.base { _, _ in amb(foto(["aa"]), terminals: ["aa"]) }
        let estat = EstatWarp(lector: { amb(foto(["zz"]), terminals: []) })
        estat.refresc = RefrescWarp(entorn: mon.entorn)
        var escoltades = 0
        estat.enLlegir = { _ in escoltades += 1 }
        #expect(try await estat.llegeixAmbFinestres().get().finestres[0].pestanyes[0].panes[0].uuid == "aa")
        #expect(escoltades == 1)
        #expect(estat.descripcio.hasPrefix("Warp: 1 finestra · 1 pestanya"))
    }
}

