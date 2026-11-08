import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// Decisió 3 (0.31.0): «Deixa de fer servir Warp Launch». L'ajust de Warp i els ítems d'inici són falsos, i
// `preferencies.json`, en una carpeta temporal.

private let t0 = Date(timeIntervalSince1970: 1_793_750_400)

/// Una carpeta temporal, que s'esborra en acabar.
private final class Carpeta {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-desinstallacio-\(UUID().uuidString)",
                                                               directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    var magatzem: MagatzemPreferencies { MagatzemPreferencies(carpeta: url) }

    func posaPermisos(_ permisos: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: permisos], ofItemAtPath: url.path)
    }
}

/// L'ajust de Warp, fals. Com el de l'app, el primer canvi desa a `preferencies.json` el valor que hi havia.
private final class AjustFals: @unchecked Sendable {
    private let pany = NSLock()
    private var estat: (valor: Bool, posats: [Bool], fallades: Int, falladesDesactivar: Int)

    init(_ valor: Bool) {
        estat = (valor, [], 0, 0)
    }

    /// Canviat a mà, a Warp.
    var valor: Bool { get { pany.withLock { estat.valor } } set { pany.withLock { estat.valor = newValue } } }
    /// Cada `posa` de l'app, també si no canvia res.
    var posats: [Bool] { pany.withLock { estat.posats } }
    /// Quantes vegades més falla el pròxim `posa` (Warp acaba d'escriure el fitxer).
    var fallades: Int { get { pany.withLock { estat.fallades } } set { pany.withLock { estat.fallades = newValue } } }
    /// Com `fallades`, però només per desactivar-lo.
    var falladesDesactivar: Int {
        get { pany.withLock { estat.falladesDesactivar } } set { pany.withLock { estat.falladesDesactivar = newValue } }
    }

    func entorn(_ magatzem: MagatzemPreferencies) -> RefrescWarp.Entorn {
        RefrescWarp.Entorn(
            ajust: { [self] in valor },
            posa: { [self] nou in
                try magatzem.posaRestauracio(nou, valor: { [self] in valor }, posa: { [self] nou in
                    try pany.withLock {
                        if estat.fallades > 0 {
                            estat.fallades -= 1
                            throw AjustRestauracio.Refusat(description: "«settings.toml» acaba de canviar")
                        }
                        if !nou, estat.falladesDesactivar > 0 {
                            estat.falladesDesactivar -= 1
                            throw AjustRestauracio.Refusat(description: "«settings.toml» acaba de canviar")
                        }
                        estat.posats.append(nou)
                        estat.valor = nou
                    }
                })
            },
            warpObert: { true },
            llegeixBase: { LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) },
            espera: { _ in })
    }
}

/// Els ítems d'inici de macOS, falsos.
@MainActor
private final class ItemsDInici {
    var estat: ArrencadaSessio.Estat = .desactivada
    var crides: [String] = []
    var falla = false

    var entorn: ArrencadaSessio.Entorn {
        ArrencadaSessio.Entorn(
            estat: { [unowned self] in estat },
            activa: { [unowned self] in crides.append("activa"); estat = .activada },
            desactiva: { [unowned self] in
                crides.append("desactiva")
                if falla { throw CocoaError(.featureUnsupported) }
                estat = .desactivada
            },
            obreAjustos: {})
    }
}

/// L'app, amb la configuració «de debò» (amb l'entorn de l'ajust) a la carpeta temporal.
@MainActor
private final class Mon {
    let carpeta: Carpeta
    let ajust: AjustFals
    let items = ItemsDInici()
    /// Quantes vegades s'ha demanat l'entorn de l'ajust (només amb el permís).
    var demanats = 0
    var sortides = 0

    init(ajust valor: Bool) throws {
        carpeta = try Carpeta()
        ajust = AjustFals(valor)
    }

    func consentiment() -> ConsentimentRestauracio {
        ConsentimentRestauracio(magatzem: carpeta.magatzem, creaEntornRefresc: { [unowned self] in
            demanats += 1
            return ajust.entorn(carpeta.magatzem)
        }, rellotge: { t0 })
    }

    func desinstallacio(_ consentiment: ConsentimentRestauracio) -> Desinstallacio {
        Desinstallacio(consentiment: consentiment, arrencada: ArrencadaSessio(entorn: items.entorn, motiuNoDisponible: nil),
                       surt: { [unowned self] in sortides += 1 })
    }

    var preferencies: Preferencies {
        get throws { try carpeta.magatzem.carrega() }
    }
}

@MainActor
@Suite struct DesinstallacioTests {
    /// Valor original activat: la confirmació ho diu, i en confirmar l'ajust torna a estar activat, el permís es retira, l'app
    /// surt dels ítems d'inici i surt. Després, ni sortir ni la vigilància de cada minut no el tornen a desactivar.
    @Test func ambElValorOriginalActivatElTornaAActivar() throws {
        let mon = try Mon(ajust: true)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        #expect(!mon.ajust.valor && mon.ajust.posats == [false])
        #expect(try mon.preferencies == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true))
        mon.items.estat = .activada

        let d = mon.desinstallacio(c)
        #expect(d.retirada == .disponible(.original(true)) && d.disponible)
        #expect(d.textAjust == "L'ajust de Warp «Restore windows, tabs, and panes on startup» tornarà a estar activat, com el "
            + "tenies abans de Warp Launch.")
        #expect(d.peu.hasPrefix("Torna l'ajust de Warp com era, retira el permís de Warp Launch, la treu dels ítems d'inici"))
        d.demana()
        #expect(d.confirmant)
        #expect(d.missatgeConfirmacio.hasPrefix(try #require(d.textAjust)))
        #expect(d.missatgeConfirmacio.contains("Warp tornarà a obrir les pestanyes de l'última vegada, sense Claude. Si tens "
            + "Settings Sync, l'ajust també canviarà als teus altres Macs."))
        #expect(d.missatgeConfirmacio.contains("sortirà dels ítems d'inici de sessió i es tancarà"))
        #expect(d.missatgeConfirmacio.contains("La configuració no s'esborra."))
        #expect(mon.sortides == 0 && mon.items.crides.isEmpty, "res fins a confirmar")

        d.confirma()
        #expect(!d.confirmant && d.error == nil)
        #expect(mon.ajust.valor && mon.ajust.posats == [false, true])
        #expect(try mon.preferencies == Preferencies(restauracio: .retirat(t0)))
        #expect(mon.items.crides == ["desactiva"] && mon.items.estat == .desactivada)
        #expect(mon.sortides == 1)
        #expect(c.estat == .retirat && !c.potContinuar && !c.potAcceptar)

        // Sortir de l'app (`applicationShouldTerminate`), una sortida cancel·lada i el minut següent: res.
        c.refresc?.atura()
        c.refresc?.repren()
        c.refresc?.vigila()
        c.refresc?.tanca()
        #expect(mon.ajust.valor && mon.ajust.posats == [false, true])
        // Si no surt, només deixa sortir, i no torna a acceptar.
        #expect(c.textSortir == "Warp Launch ha deixat l'ajust de Warp com t'ha dit en confirmar-ho, i ja no té permís per "
            + "tocar-lo. Si la tornes a obrir, te'l tornarà a demanar.", "\(c.textSortir)")
        c.accepta()
        #expect(c.estat == .retirat && mon.demanats == 1)
        #expect(!c.continuaEnTancarFinestra { mon.sortides += 1 })
        #expect(mon.sortides == 2)
        d.actualitza()
        #expect(!d.disponible && d.peu == "Ja has deixat de fer servir Warp Launch.")
    }

    /// Valor original desactivat (desat en el primer refresc): es queda desactivat, i la confirmació no parla dels ítems
    /// d'inici si l'app no hi és.
    @Test func ambElValorOriginalDesactivatEsQuedaDesactivat() async throws {
        let mon = try Mon(ajust: false)
        let c = mon.consentiment()
        c.accepta()
        _ = await try #require(c.refresc).refresca()
        #expect(mon.ajust.posats == [true, false])
        #expect(try mon.preferencies.restauracioOriginal == false)

        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.original(false)))
        #expect(d.textAjust == "L'ajust de Warp «Restore windows, tabs, and panes on startup» es quedarà desactivat, com el "
            + "tenies abans de Warp Launch.")
        #expect(!d.missatgeConfirmacio.contains("sense Claude") && !d.missatgeConfirmacio.contains("ítems d'inici"))
        #expect(!d.missatgeConfirmacio.contains("Settings Sync"), "no canvia res que es pugui sincronitzar")
        d.confirma()
        #expect(!mon.ajust.valor && mon.ajust.posats == [true, false, false])
        #expect(try mon.preferencies == Preferencies(restauracio: .retirat(t0)))
        #expect(mon.items.crides.isEmpty && mon.sortides == 1)
    }

    /// Valor desconegut (`migrat`: la carpeta ja tenia `configuracio.json`, i l'app ja havia desactivat l'ajust abans de
    /// demanar permís): el de sèrie de Warp, activat, i la confirmació ho diu abans.
    @Test func senseSaberElValorPosaElDeSerie() throws {
        let mon = try Mon(ajust: false)
        try Data("{}".utf8).write(to: mon.carpeta.url.appending(path: MagatzemConfiguracio.nomFitxer))
        let c = mon.consentiment()
        #expect(c.estat == .acceptat && c.refresc != nil)

        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.deSerie))
        #expect(d.textAjust == "No se sap com tenies l'ajust de Warp «Restore windows, tabs, and panes on startup» abans de "
            + "Warp Launch, perquè ja la feies servir abans que demanés permís: quedarà activat, com ve de sèrie a Warp.")
        #expect(d.missatgeConfirmacio.contains("sense Claude. Si tens Settings Sync, l'ajust també canviarà als teus altres Macs."))
        d.confirma()
        #expect(mon.ajust.valor && mon.sortides == 1)
        #expect(try mon.preferencies == Preferencies(restauracio: .retirat(t0)))
    }

    /// L'app no l'ha canviat mai (sempre era desactivat): es queda com és, sense escriure res a Warp.
    @Test func siLAppNoLHaCanviatMaiEsQuedaComEs() throws {
        let mon = try Mon(ajust: false)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.senseCanvis))
        #expect(d.textAjust == "Warp Launch no ha canviat mai l'ajust de Warp «Restore windows, tabs, and panes on startup»: "
            + "es queda com és.")
        d.confirma()
        #expect(mon.ajust.posats.isEmpty && !mon.ajust.valor && mon.sortides == 1)
        #expect(try mon.preferencies == Preferencies(restauracio: .retirat(t0)))
    }

    /// Després de retirar el permís, la propera vegada l'app no toca res i torna a preguntar, encara que la carpeta tingui
    /// `configuracio.json` i `estat.json` (la migració no el torna a donar per acceptat). Si s'accepta, torna a començar.
    @Test func despresDeRetirarNoTocaResITornaAPreguntar() throws {
        let mon = try Mon(ajust: true)
        try Data("{}".utf8).write(to: mon.carpeta.url.appending(path: MagatzemConfiguracio.nomFitxer))
        try Data("{}".utf8).write(to: mon.carpeta.url.appending(path: EstatApp.nomFitxer))
        let c = mon.consentiment()
        try #require(c.refresc).vigila()
        let d = mon.desinstallacio(c)
        d.demana()
        d.confirma()
        #expect(mon.ajust.valor && mon.ajust.posats == [false, true] && mon.sortides == 1)

        let altra = mon.consentiment()
        #expect(altra.estat == .pendent && altra.potAcceptar && !altra.potContinuar)
        #expect(altra.refresc == nil && mon.demanats == 1, "l'entorn de l'ajust ni es demana")
        altra.refresc?.vigila()
        altra.refresc?.tanca()
        #expect(mon.ajust.valor && mon.ajust.posats == [false, true])
        #expect(!mon.desinstallacio(altra).disponible)

        altra.accepta()
        #expect(altra.estat == .acceptat && mon.demanats == 2)
        try #require(altra.refresc).vigila()
        #expect(!mon.ajust.valor)
        #expect(try mon.preferencies == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true),
                "el primer canvi d'aquesta vegada")
    }

    /// Amb una carpeta de prova (sense l'entorn de l'ajust), sense carpeta o sense el permís: el botó és desactivat, el peu
    /// diu per què, i confirmar no fa res.
    @Test func senseLaConfiguracioDeDeboNoEsPot() throws {
        let mon = try Mon(ajust: true)
        let deProva = ConsentimentRestauracio(magatzem: mon.carpeta.magatzem, creaEntornRefresc: nil, rellotge: { t0 })
        deProva.accepta()
        let d = mon.desinstallacio(deProva)
        #expect(!d.disponible && d.textAjust == nil)
        #expect(d.peu.hasPrefix("Amb una configuració de prova (--config), Warp Launch no toca l'ajust de Warp"), "\(d.peu)")
        d.demana()
        #expect(!d.confirmant)
        d.confirma()
        #expect(mon.sortides == 0 && mon.items.crides.isEmpty && mon.ajust.posats.isEmpty)
        #expect(try mon.preferencies == Preferencies(restauracio: .acceptat(t0)))

        let senseCarpeta = mon.desinstallacio(ConsentimentRestauracio(magatzem: nil, creaEntornRefresc: nil))
        #expect(!senseCarpeta.disponible && senseCarpeta.peu.hasPrefix("Sense carpeta de configuració"))

        let nou = try Mon(ajust: true)
        let pendent = nou.desinstallacio(nou.consentiment())
        #expect(!pendent.disponible && pendent.peu.hasPrefix("Sense el teu permís"))
        #expect(nou.demanats == 0)
    }

    /// Si l'ajust no es pot posar, no ha canviat res (els ítems d'inici, sí, i ho diu), no surt, i el refresc continua.
    @Test func siNoEsPotPosarLAjustNoCanviaRes() throws {
        let mon = try Mon(ajust: true)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        mon.items.estat = .activada
        let d = mon.desinstallacio(c)
        d.demana()
        mon.ajust.fallades = 1
        d.confirma()
        let error = try #require(d.error)
        #expect(error.hasPrefix("No s'ha pogut tornar l'ajust de Warp com era: «settings.toml» acaba de canviar. L'ajust i el "
            + "permís no han canviat."), "\(error)")
        #expect(error.hasSuffix("Warp Launch ja no s'obre en iniciar sessió: si vols, torna a activar l'interruptor de dalt."))
        #expect(!mon.ajust.valor && mon.ajust.posats == [false] && mon.sortides == 0)
        #expect(c.estat == .acceptat && d.disponible)
        #expect(try mon.preferencies == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true))
        mon.ajust.valor = true
        c.refresc?.vigila()
        #expect(!mon.ajust.valor, "la vigilància continua")

        // Es pot tornar a provar.
        d.demana()
        #expect(d.error == nil)
        d.confirma()
        #expect(mon.ajust.valor && mon.sortides == 1 && c.estat == .retirat)
    }

    /// Si el permís no es pot desar, l'ajust torna a quedar desactivat, el permís no canvia i no surt.
    @Test func siNoEsPotRetirarElPermisLAjustTornaADesactivar() throws {
        let mon = try Mon(ajust: true)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        let d = mon.desinstallacio(c)
        d.demana()
        try mon.carpeta.posaPermisos(0o555)
        d.confirma()
        try mon.carpeta.posaPermisos(0o755)
        let error = try #require(d.error)
        #expect(error.hasPrefix("No s'ha pogut retirar el permís: "), "\(error)")
        #expect(error.hasSuffix("L'ajust de Warp torna a quedar desactivat, i el permís no ha canviat."), "\(error)")
        #expect(!mon.ajust.valor && mon.ajust.posats == [false, true, false] && mon.sortides == 0)
        #expect(c.estat == .acceptat)
        #expect(try mon.preferencies == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true))
        mon.ajust.valor = true
        c.refresc?.vigila()
        #expect(!mon.ajust.valor, "la vigilància continua")
    }

    /// Revisió de la 0.31.0: si el permís no es pot desar i l'ajust tampoc no es pot tornar a desactivar, no diu que s'ha
    /// desactivat. La vigilància de cada minut el desactiva.
    @Test func siTampocNoEsPotTornarADesactivarNoDiuQueSHaDesactivat() throws {
        let mon = try Mon(ajust: true)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        let d = mon.desinstallacio(c)
        d.demana()
        try mon.carpeta.posaPermisos(0o555)
        mon.ajust.falladesDesactivar = 3
        d.confirma()
        try mon.carpeta.posaPermisos(0o755)
        let error = try #require(d.error)
        #expect(error.hasPrefix("No s'ha pogut retirar el permís: "), "\(error)")
        #expect(error.hasSuffix("L'ajust de Warp ha quedat activat, i no s'ha pogut tornar a desactivar: Warp Launch ho "
            + "tornarà a provar d'aquí a un minut. El permís no ha canviat."), "\(error)")
        #expect(mon.ajust.valor && mon.sortides == 0 && c.estat == .acceptat)
        c.refresc?.vigila()
        #expect(!mon.ajust.valor, "la vigilància continua")
    }

    /// Si l'app no es pot treure dels ítems d'inici, no fa res més.
    @Test func siNoEsPotTreureDelsItemsDIniciNoFaResMes() throws {
        let mon = try Mon(ajust: true)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        mon.items.estat = .activada
        mon.items.falla = true
        let d = mon.desinstallacio(c)
        d.demana()
        d.confirma()
        #expect(d.error?.hasPrefix("No s'ha pogut treure Warp Launch dels ítems d'inici de sessió:") == true, "\(d.error ?? "")")
        #expect(!mon.ajust.valor && mon.ajust.posats == [false] && mon.sortides == 0 && c.estat == .acceptat)
        #expect(try mon.preferencies.restauracio == .acceptat(t0))
    }

    /// Si mentre la confirmació és a la vista l'app desa el valor original (Warp l'ha canviat), no fa el que no ha dit: ho
    /// diu, i la propera confirmació ja ho diu bé.
    @Test func siHaCanviatMentrestantNoFaRes() throws {
        let mon = try Mon(ajust: false)
        let c = mon.consentiment()
        c.accepta()
        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.senseCanvis))
        mon.ajust.valor = true
        c.refresc?.vigila()
        d.confirma()
        #expect(d.error == "Mentrestant, «preferencies.json» ha canviat: torna-ho a provar.")
        #expect(mon.sortides == 0 && c.estat == .acceptat && !mon.ajust.valor)
        #expect(d.retirada == .disponible(.original(true)))
    }

    /// Revisió de la 0.31.0: si ha canviat mentrestant, tampoc no la treu dels ítems d'inici (la confirmació deia una altra
    /// cosa de l'ajust): cap pas no es fa.
    @Test func siHaCanviatMentrestantNoLaTreuDelsItemsDInici() throws {
        let mon = try Mon(ajust: false)
        let c = mon.consentiment()
        c.accepta()
        mon.items.estat = .activada
        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.missatgeConfirmacio.contains("sortirà dels ítems d'inici de sessió"))
        mon.ajust.valor = true
        c.refresc?.vigila()
        d.confirma()
        #expect(d.error == "Mentrestant, «preferencies.json» ha canviat: torna-ho a provar.")
        #expect(mon.items.crides.isEmpty && mon.items.estat == .activada)
        #expect(mon.sortides == 0 && c.estat == .acceptat)
    }
}

/// Decisió A (0.31.2): sense la línia `restore_session`, amb l'ajust de debò (`AjustRestauracio`) sobre un `settings.toml`
/// d'una carpeta temporal, connectat com a l'app. El refresc l'afegeix, i «Restaura Warp i surt…» no falla ni escriu res
/// si no hi és.
@MainActor
private final class MonSenseLinia {
    let tmp: Carpeta
    let ajust: AjustRestauracio
    let items = ItemsDInici()
    var sortides = 0

    /// Amb `nil`, sense el fitxer; amb `carpetaWarp: false`, tampoc sense la carpeta de Warp.
    init(_ contingut: String?, carpetaWarp: Bool = true, migrat: Bool = false) throws {
        tmp = try Carpeta()
        try FileManager.default.createDirectory(at: tmp.url("tmp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.url("config"), withIntermediateDirectories: true)
        if carpetaWarp { try FileManager.default.createDirectory(at: tmp.url("warp"), withIntermediateDirectories: true) }
        ajust = AjustRestauracio(ruta: tmp.url("warp/settings.toml"), carpetaTemporal: tmp.url("tmp"))
        if let contingut { try Data(contingut.utf8).write(to: ajust.ruta) }
        if migrat { try Data("{}".utf8).write(to: tmp.url("config").appending(path: MagatzemConfiguracio.nomFitxer)) }
    }

    var magatzem: MagatzemPreferencies { MagatzemPreferencies(carpeta: tmp.url("config")) }
    var contingut: String? { (try? Data(contentsOf: ajust.ruta)).map { String(decoding: $0, as: UTF8.self) } }

    func consentiment() -> ConsentimentRestauracio {
        let ajust = ajust, magatzem = magatzem
        return ConsentimentRestauracio(magatzem: magatzem, creaEntornRefresc: {
            RefrescWarp.Entorn(ajust: { try ajust.valor() },
                               posa: { nou in
                                   try magatzem.posaRestauracio(nou, valor: { try ajust.valor() }, posa: { try ajust.posa($0) })
                               },
                               warpObert: { true },
                               llegeixBase: { LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []) },
                               espera: { _ in })
        }, rellotge: { t0 })
    }

    func desinstallacio(_ consentiment: ConsentimentRestauracio) -> Desinstallacio {
        Desinstallacio(consentiment: consentiment, arrencada: ArrencadaSessio(entorn: items.entorn, motiuNoDisponible: nil),
                       surt: { [unowned self] in sortides += 1 })
    }
}

extension Carpeta {
    func url(_ nom: String) -> URL { url.appending(path: nom) }
}

@MainActor
@Suite struct SenseLiniaTests {
    /// La vigilància hi afegeix `restore_session = false` i desa que abans era activat (el de sèrie); un refresc l'activa i
    /// la torna a desactivar canviant només el valor; i «Restaura Warp i surt…» el deixa activat, com venia de sèrie.
    @Test func elRefrescLAfegeixIEnDesinstallarQuedaActivat() async throws {
        let mon = try MonSenseLinia("[general]\nlogin_item = true\n")
        let c = mon.consentiment()
        c.accepta()
        let refresc = try #require(c.refresc)
        refresc.vigila()
        #expect(refresc.avis == nil)
        #expect(mon.contingut == "[general]\nrestore_session = false\nlogin_item = true\n")
        #expect(try mon.magatzem.carrega() == Preferencies(restauracio: .acceptat(t0), restauracioOriginal: true))

        _ = await refresc.refresca()
        #expect(refresc.avis == nil)
        #expect(mon.contingut == "[general]\nrestore_session = false\nlogin_item = true\n")
        #expect(try mon.magatzem.carrega().restauracioOriginal == true)

        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.original(true)))
        d.confirma()
        #expect(d.error == nil && mon.sortides == 1)
        #expect(mon.contingut == "[general]\nrestore_session = true\nlogin_item = true\n")
        #expect(try mon.magatzem.carrega() == Preferencies(restauracio: .retirat(t0)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: mon.tmp.url("tmp").path).isEmpty)
    }

    /// Sense el fitxer, la vigilància el crea només amb la línia.
    @Test func elRefrescCreaElFitxer() throws {
        let mon = try MonSenseLinia(nil)
        let c = mon.consentiment()
        c.accepta()
        try #require(c.refresc).vigila()
        #expect(c.refresc?.avis == nil)
        #expect(mon.contingut == "[general]\nrestore_session = false\n")
    }

    /// Sense la carpeta de Warp, no la crea: el menú diu per què.
    @Test func senseLaCarpetaDeWarpElRefrescNoLaCrea() throws {
        let mon = try MonSenseLinia(nil, carpetaWarp: false)
        let c = mon.consentiment()
        c.accepta()
        let refresc = try #require(c.refresc)
        refresc.vigila()
        #expect(refresc.avis?.contains("Warp encara no s'ha obert mai en aquest usuari") == true, "\(refresc.avis ?? "")")
        #expect(!FileManager.default.fileExists(atPath: mon.tmp.url("warp").path))
    }

    /// Amb `migrat` (el de sèrie) i sense la línia, sense el fitxer o sense la carpeta de Warp, «Restaura Warp i surt…»
    /// acaba bé sense escriure res a Warp: l'ajust ja és activat.
    @Test(arguments: [("[general]\nlogin_item = true\n", true), (nil, true), (nil, false)] as [(String?, Bool)])
    func desinstallarSenseLiniaNoEscriuRes(contingut: String?, carpetaWarp: Bool) throws {
        let mon = try MonSenseLinia(contingut, carpetaWarp: carpetaWarp, migrat: true)
        let inode = try? FileManager.default.attributesOfItem(atPath: mon.ajust.ruta.path)[.systemFileNumber] as? Int
        let c = mon.consentiment()
        #expect(c.estat == .acceptat)
        let d = mon.desinstallacio(c)
        d.demana()
        #expect(d.retirada == .disponible(.deSerie))
        d.confirma()
        #expect(d.error == nil, "\(d.error ?? "")")
        #expect(mon.sortides == 1)
        #expect(try mon.magatzem.carrega() == Preferencies(restauracio: .retirat(t0)))
        #expect(mon.contingut == contingut)
        #expect((try? FileManager.default.attributesOfItem(atPath: mon.ajust.ruta.path)[.systemFileNumber] as? Int) == inode)
        #expect(FileManager.default.fileExists(atPath: mon.tmp.url("warp").path) == carpetaWarp)
        #expect(try FileManager.default.contentsOfDirectory(atPath: mon.tmp.url("tmp").path).isEmpty)
    }
}
