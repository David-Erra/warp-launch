import Foundation
import Testing
@testable import WarpLaunchCore

// Warp diu A i Claude corre a B (decisió d'en David del 09/11/2026): l'avís de «Per revisar», «Lliga amb Warp…» i el pla
// d'obertura. Lectures inventades; les carpetes no existeixen.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
private let inici = "/Users/prova"
private let A = "/x/repo-a", B = "/x/repo-b"
private let paneP = String(repeating: "a", count: 32)

private func sessio(carpeta: String = B) -> SessioClaude {
    SessioClaude(pid: 10, sessionId: "s-b", carpeta: carpeta, iniciada: t0, ordre: ["claude"], opcions: OpcionsClaude(),
                 paneUUID: paneP, dinsDeWarp: true)
}

private func lectura(titol: String? = nil, carpeta: String = A, claude: SessioClaude? = sessio()) -> LecturaWarp {
    LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
        PestanyaLlegida(posicio: 0, titol: titol, color: nil, panes: [
            PaneLlegit(uuid: paneP, carpeta: carpeta, origenCarpeta: .pane, carpetaExisteix: true, claude: claude),
        ]),
    ])], sessionsSensePestanya: [], avisos: [])
}

private func pestanya(_ carpeta: String, titol: String = "T") -> Pestanya {
    Pestanya(id: id(1), titol: titol, carpeta: carpeta, claude: .habituals)
}

private func configuracio(_ p: Pestanya) -> Configuracio {
    Configuracio(plantilla: .habituals, finestres: [Finestra(id: id(100), nom: "f", pestanyes: [p])])
}

private func vincle(claude: String? = B) -> VincleEstat {
    VincleEstat(pane: paneP, sessio: "s-b", carpetaSessio: claude, origen: .importacio, vista: t0)
}

private func avis(_ p: Pestanya, vincle v: VincleEstat? = vincle(), warp: String? = nil,
                  existeix: @escaping (String) -> Bool = { _ in true }) -> Avis? {
    Validacio.avisCarpetaDeClaude(p, vincle: v, carpetaWarp: warp, inici: inici, carpetaExisteix: existeix)
}

@Suite struct CarpetaDeClaudeTests {
    // MARK: L'avís

    /// La foto de Warp a la memòria de l'app: diu totes dues carpetes, i quina es fa servir.
    @Test func ambLaFotoDiuTotesDuesCarpetes() throws {
        let aB = try #require(avis(pestanya(B), warp: A))
        #expect(aB.tipus == .carpetesDiferents(warp: A, claude: B, actual: B))
        #expect(aB.gravetat == .avis)
        #expect(aB.description == "Warp diu «/x/repo-a» i Claude corre a «/x/repo-b»: es fa servir la de Claude (comprova-ho)")
        #expect(avis(pestanya(A), warp: A)?.description
            == "Warp diu «/x/repo-a» i Claude corre a «/x/repo-b»: es fa servir la de Warp (comprova-ho)")
    }

    /// Sense la foto (per exemple, després de reiniciar l'app), una pestanya amb Claude a una altra carpeta també avisa:
    /// `carpetaSessio` sí que es desa a `estat.json`.
    @Test func senseLaFotoAvisaAmbLUltimaCarpetaDeClaude() {
        #expect(avis(pestanya(A))?.tipus == .carpetesDiferents(warp: nil, claude: B, actual: A))
        #expect(avis(pestanya(A))?.description == "L'últim Claude d'aquesta pestanya corria a «/x/repo-b», no a aquesta carpeta (comprova-ho)")
        #expect(avis(pestanya(B)) == nil, "ja hi és")
    }

    @Test func noAvisaSiNoHiHaResAComparar() {
        #expect(avis(pestanya(A), vincle: nil) == nil)
        #expect(avis(pestanya(A), vincle: vincle(claude: nil)) == nil)
        #expect(avis(pestanya(A), vincle: vincle(claude: inici)) == nil, "`~` no compta")
        #expect(avis(pestanya(A), existeix: { $0 != B }) == nil, "la de Claude ja no existeix: no hi ha res a fer")
        #expect(avis(pestanya(B), warp: inici) == nil, "Warp a `~` l'ha perduda")
        #expect(avis(pestanya(B), warp: B) == nil)
    }

    /// Si s'ha canviat la carpeta a mà, la foto de Warp ja no hi diu res; només l'última de Claude, si encara és una altra.
    @Test func siSHaCanviatAMaNoDiuLaFoto() {
        #expect(avis(pestanya("/x/repo-c"), warp: A)?.tipus == .carpetesDiferents(warp: nil, claude: B, actual: "/x/repo-c"))
    }

    /// Una pestanya només terminal no obre Claude: que hi hagi corregut a una altra carpeta no s'ha de revisar.
    @Test func noAvisaSiLaPestanyaNoObreClaude() {
        var p = pestanya(A)
        p.claude.activat = false
        #expect(avis(p) == nil)
        #expect(avis(p, warp: A) == nil)
    }

    // MARK: «Lliga amb Warp…»

    /// Una configuració importada amb la regla nova (a B), Warp diu A: amb el títol de la carpeta de Claude es lliga.
    @Test func lligaUnaConfiguracioALaCarpetaDeClaude() {
        let p = LligamWarp.proposa(configuracio(pestanya(B, titol: "repo-b")), lectura: lectura(), estat: EstatApp(), inici: inici)
        #expect(p.parelles.map(\.pane) == [paneP])
        #expect(p.senseParella.isEmpty)
    }

    /// Una configuració importada abans (a A) es continua lligant.
    @Test func lligaUnaConfiguracioALaCarpetaDeWarp() {
        let p = LligamWarp.proposa(configuracio(pestanya(A, titol: "repo-a")), lectura: lectura(), estat: EstatApp(), inici: inici)
        #expect(p.parelles.map(\.pane) == [paneP])
    }

    /// Amb títol propi i la carpeta de Claude, es lliga pel criteri segur.
    @Test func lligaPelTitolILaCarpetaDeClaude() {
        let p = LligamWarp.proposa(configuracio(pestanya(B, titol: "Web")), lectura: lectura(titol: "Web"), estat: EstatApp(), inici: inici)
        #expect(p.parelles.map { "\($0.criteri)" } == ["titolICarpeta"])
    }

    /// Una altra carpeta, sense cap títol igual: no es lliga.
    @Test func noLligaUnaAltraCarpeta() {
        let p = LligamWarp.proposa(configuracio(pestanya("/x/repo-c", titol: "repo-c")), lectura: lectura(), estat: EstatApp(), inici: inici)
        #expect(p.parelles.isEmpty)
    }

    /// Una pestanya de Warp amb títol, al pane `uuid`, i Claude a `claude` si n'hi ha.
    private func deWarp(_ uuid: String, titol: String?, _ carpeta: String, claude: String? = nil) -> PestanyaLlegida {
        let viu = claude.map {
            SessioClaude(pid: 10, sessionId: "s-\(uuid)", carpeta: $0, iniciada: t0, ordre: ["claude"], opcions: OpcionsClaude(),
                         paneUUID: uuid, dinsDeWarp: true)
        }
        return PestanyaLlegida(posicio: 0, titol: titol, color: nil, panes: [
            PaneLlegit(uuid: uuid, carpeta: carpeta, origenCarpeta: .pane, carpetaExisteix: true, claude: viu),
        ])
    }

    private func warp(_ pestanyes: [PestanyaLlegida]) -> LecturaWarp {
        LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: pestanyes)], sessionsSensePestanya: [], avisos: [])
    }

    private func pane(_ n: Int) -> String { String(repeating: "\(n)", count: 32) }

    /// Tres pestanyes de Warp a la mateixa carpeta, una només per Claude, i una sola a la configuració: no se sap quina és.
    @Test func trobarUnaPerClaudeNoDesfaLEmpat() {
        let p = LligamWarp.proposa(configuracio(pestanya(B, titol: "T")), lectura: warp([
            deWarp(pane(1), titol: "T", A, claude: B), deWarp(pane(2), titol: "T", B), deWarp(pane(3), titol: "T", B),
        ]), estat: EstatApp(), inici: inici)
        #expect(p.parelles.isEmpty)
    }

    /// El mateix títol a dues pestanyes de Warp i només una amb Claude: el títol no prou per triar-la.
    @Test func elTitolAmbClaudeNoDesfaLEmpat() {
        let p = LligamWarp.proposa(configuracio(pestanya("/x/repo-c", titol: "T")), lectura: warp([
            deWarp(pane(1), titol: "T", A, claude: B), deWarp(pane(2), titol: "T", "/x/repo-d"),
        ]), estat: EstatApp(), inici: inici)
        #expect(p.parelles.isEmpty)
    }

    /// Tres pestanyes a la mateixa carpeta, a la configuració i a Warp, on una només hi és per Claude: se'n lliguen totes tres.
    @Test func lligaLesTresQueCompartienCarpeta() {
        let tres = (1...3).map { Pestanya(id: id($0), titol: "t\($0)", carpeta: B, claude: .habituals) }
        let c = Configuracio(plantilla: .habituals, finestres: [Finestra(id: id(100), nom: "f", pestanyes: tres)])
        let p = LligamWarp.proposa(c, lectura: warp([
            deWarp(pane(1), titol: "x", A, claude: B), deWarp(pane(2), titol: "y", B), deWarp(pane(3), titol: "z", B),
        ]), estat: EstatApp(), inici: inici)
        #expect(Set(p.parelles.map(\.pane)) == [pane(1), pane(2), pane(3)])
    }

    /// Dues pestanyes de la configuració, una a cada carpeta del mateix pane: només una se'l queda.
    @Test func unPaneNomesEsDeUnaPestanya() {
        let dues = [Pestanya(id: id(1), titol: "t1", carpeta: A, claude: .habituals),
                    Pestanya(id: id(2), titol: "t2", carpeta: B, claude: .habituals)]
        let c = Configuracio(plantilla: .habituals, finestres: [Finestra(id: id(100), nom: "f", pestanyes: dues)])
        let p = LligamWarp.proposa(c, lectura: warp([deWarp(pane(1), titol: "x", A, claude: B)]), estat: EstatApp(), inici: inici)
        #expect(p.parelles.count == 1)
        #expect(p.parelles.first?.pestanya.id == id(1), "primer la carpeta de Warp")
    }

    // MARK: El pla

    @Test func elPlaAvisaSiLaCarpetaEsLaDelClaudeDUnPane() {
        let entrada = EntradaObertura(lectura: lectura(), estat: EstatApp(), inici: inici, ara: t0, carpetaExisteix: { _ in true },
                                      transcripcio: { _, _ in .enlloc }, conversesRecents: { _ in [] }, confianca: nil)
        let finestra = Finestra(id: id(100), nom: "f", pestanyes: [pestanya(B)])
        let pla = PlaObertura.calcula(finestra, entrada)
        #expect(pla.avisos.contains { $0.tipus == .potserJaOberta(lloc: "finestra 1 › repo-a") })
    }
}
