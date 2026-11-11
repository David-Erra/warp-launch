import Foundation
import Testing
@testable import WarpLaunchCore

// El pla d'obrir una finestra i la confirmació (fase 3.1, 0.18.0; docs/disseny.md, secció 7). Funcions pures: lectures,
// estats i transcripcions fictícies, i carpetes que no existeixen (`/x/…`), que `carpetaExisteix` diu si hi són.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)  // 04/11/2026 00:00:00Z
private let inici = "/Users/prova"
private func pane(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }
private let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"

private func pestanya(_ n: Int, carpeta: String? = nil, titol: String? = nil,
                      claude: ClaudePestanya = .habituals) -> Pestanya {
    Pestanya(id: id(n), titol: titol ?? "T\(n)", carpeta: carpeta ?? "/x/t\(n)", claude: claude)
}

private func finestra(_ pestanyes: [Pestanya]) -> Finestra { Finestra(id: id(100), nom: "feina", pestanyes: pestanyes) }

private func sessio(_ sessionId: String, pane: String?, marca: UUID? = nil, dinsDeWarp: Bool = true,
                    iniciada: Date? = t0) -> SessioClaude {
    SessioClaude(pid: 10, sessionId: sessionId, carpeta: "/x", iniciada: iniciada, ordre: ["claude"],
                 opcions: OpcionsClaude(), paneUUID: pane, dinsDeWarp: dinsDeWarp, marca: marca)
}

/// Una pestanya llegida de Warp, amb un sol pane.
private struct Llegida {
    var titol: String?
    var pane: String
    var carpeta: String
    var claude: SessioClaude?
}

private func lectura(_ finestres: [[Llegida]], sense: [SessioClaude] = [], segonPla: [SessioViva] = []) -> LecturaWarp {
    var lectura = LecturaWarp(finestres: finestres.enumerated().map { n, pestanyes in
        FinestraLlegida(numero: n + 1, pestanyaActiva: 0, pestanyes: pestanyes.enumerated().map { posicio, p in
            PestanyaLlegida(posicio: posicio, titol: p.titol, color: nil, panes: [
                PaneLlegit(uuid: p.pane, carpeta: p.carpeta, origenCarpeta: .pane, carpetaExisteix: true, claude: p.claude),
            ])
        })
    }, sessionsSensePestanya: sense, avisos: [])
    lectura.sessionsNoInteractives = segonPla
    lectura.warpObert = true
    return lectura
}

private func entrada(_ lectura: LecturaWarp, estat: EstatApp = EstatApp(),
                     transcripcions: [String: LectorTranscripcions.On] = [:], confiades: Set<String>? = nil,
                     noExisteixen: Set<String> = [], ara: Date = t0, enCurs: [String: UUID] = [:],
                     recents: [String: [LectorTranscripcions.Recent]] = [:]) -> EntradaObertura {
    EntradaObertura(lectura: lectura, estat: estat, inici: inici, ara: ara,
                    carpetaExisteix: { !noExisteixen.contains($0) },
                    transcripcio: { id, _ in transcripcions[id] ?? .enlloc },
                    conversesRecents: { recents[$0] ?? [] },
                    confianca: confiades.map { Confianca(confiades: $0, inici: inici) }, conversesEnCurs: enCurs)
}

private func vincle(pane: String? = nil, sessio: String? = nil) -> VincleEstat {
    VincleEstat(pane: pane, sessio: sessio, origen: .importacio, vista: t0)
}

@Suite struct PlaOberturaTests {
    // MARK: Ja obertes (D13, R9)

    /// Les tres regles, en ordre: la marca, el pane recordat i la conversa recordada.
    @Test func lesPestanyesJaObertes() {
        let warp = lectura([[
            Llegida(titol: "Botiga", pane: pane("a"), carpeta: "/x/t1", claude: sessio("s1", pane: pane("a"), marca: id(1))),
            Llegida(titol: nil, pane: pane("b"), carpeta: "/x/t2"),
            Llegida(titol: "Altra", pane: pane("c"), carpeta: "/x/c", claude: sessio("s3", pane: pane("c"))),
        ]], sense: [sessio("s4", pane: nil, dinsDeWarp: false), sessio("s6", pane: pane("y"))],
            segonPla: [SessioViva(pid: 50, sessionId: "s5", tipus: "bg", carpeta: "/x")])
        let estat = EstatApp(pestanyes: [
            id(2): vincle(pane: pane("b")),
            id(3): vincle(pane: pane("z"), sessio: "s3"),
            id(4): vincle(sessio: "s4"),
            id(5): vincle(sessio: "s5"),
            id(6): vincle(sessio: "s6"),
            id(7): vincle(pane: pane("z"), sessio: "s7"),
        ])
        let pla = PlaObertura.calcula(finestra((1...7).map { pestanya($0) }), entrada(warp, estat: estat))
        #expect(pla.obertes.map(\.on) == [
            .marca(lloc: "finestra 1 › Botiga"),
            .pane(lloc: "finestra 1 › t2", ambClaude: false),
            .conversa(lloc: "finestra 1 › Altra"),
            .conversaForaDeWarp,
            .conversaEnSegonPla("bg"),
            .tancadaFaPoc,
        ])
        #expect(pla.obertes.map(\.pestanya.id) == (1...6).map(id))
        #expect(pla.aObrir.map(\.pestanya.id) == [id(7)], "la 7 no és enlloc: s'obre")
        #expect(pla.obertes[1].on.description == "oberta a Warp, sense Claude (finestra 1 › t2)")
    }

    /// La marca d'un Claude viu dins de Warp amb un pane que ja no hi és: la pestanya s'acaba de tancar (Warp encara la
    /// pot desfer). No s'obre res de la finestra fins que passi, perquè no quedi partida (revisió de la 0.20.0).
    @Test func unaPestanyaTancadaFaPocAturaLaFinestra() {
        let tancada = lectura([], sense: [sessio("s1", pane: pane("z"), marca: id(1))])
        let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2)]), entrada(tancada))
        #expect(pla.obertes.map(\.on) == [.tancadaFaPoc])
        #expect(pla.aObrir.map(\.pestanya.id) == [id(2)])
        #expect(pla.motiuEspera?.hasPrefix("Alguna pestanya d'aquesta finestra s'ha tancat fa menys d'1 minut") == true)
        // Sense pane conegut, o fora de Warp: és oberta (no se sap on), i no cal esperar.
        for sessio in [sessio("s1", pane: nil, marca: id(1)), sessio("s1", pane: pane("z"), marca: id(1), dinsDeWarp: false)] {
            let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2)]), entrada(lectura([], sense: [sessio])))
            #expect(pla.obertes.map(\.on) == [.marca(lloc: nil)])
            #expect(pla.motiuEspera == nil)
        }
        // Si no hi ha res per obrir, no cal esperar.
        #expect(PlaObertura.calcula(finestra([pestanya(1)]), entrada(tancada)).motiuEspera == nil)
        // Per la conversa recordada, igual: amb un pane que ja no hi és, s'acaba de tancar; sense pane, no se sap on és
        // (i no atura la finestra, que podria ser per hores).
        let estat = EstatApp(pestanyes: [id(1): vincle(sessio: "s1")])
        for (sessio, on) in [(sessio("s1", pane: pane("z")), OnOberta.tancadaFaPoc), (sessio("s1", pane: nil), .conversaAWarp)] {
            let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2)]), entrada(lectura([], sense: [sessio]), estat: estat))
            #expect(pla.obertes.map(\.on) == [on])
            #expect((pla.motiuEspera != nil) == (on == .tancadaFaPoc))
        }
    }

    /// Totes obertes: no s'obre res, i no hi ha fitxer.
    @Test func totesObertes() {
        let warp = lectura([[Llegida(titol: "T1", pane: pane("a"), carpeta: "/x/t1")]])
        let pla = PlaObertura.calcula(finestra([pestanya(1)]), entrada(warp, estat: EstatApp(pestanyes: [id(1): vincle(pane: pane("a"))])))
        #expect(pla.aObrir.isEmpty)
        #expect(pla.xifres.text == "No s'obrirà res. · ja obertes: 1")
        #expect(throws: LaunchConfigWarp.ErrorLaunch.capPestanya) { try pla.fitxer(llancament: id(500)) }
    }

    // MARK: La conversa (D7)

    @Test func laConversaDeLesQueSObren() throws {
        let estat = EstatApp(pestanyes: [
            id(3): vincle(sessio: conversa),
            id(4): vincle(sessio: "c4"),
            id(5): vincle(sessio: "c5"),
            id(6): vincle(sessio: "c6"),
            id(7): vincle(sessio: conversa),
            id(9): vincle(sessio: "c9"),
        ])
        let pestanyes = [
            pestanya(1, claude: ClaudePestanya(continua: false)),
            pestanya(2),
            pestanya(3),
            pestanya(4),
            pestanya(5),
            pestanya(6),
            pestanya(7),
            pestanya(8, claude: ClaudePestanya(activat: false)),
            pestanya(9, claude: ClaudePestanya(continua: false)),
        ]
        let pla = PlaObertura.calcula(finestra(pestanyes), entrada(lectura([]), estat: estat, transcripcions: [
            conversa: .aLaCarpeta, "c4": .altres(["-x-altre"]), "c5": .enlloc, "c6": .altres(["-a", "-b"]),
            "c9": .aLaCarpeta,
        ]))
        #expect(pla.aObrir.map(\.conversa) == [
            .nova(.noContinua), .nova(.senseConversa), .repren(conversa), .repren("c4"), .nova(.senseTranscripcio),
            .nova(.enDiversosProjectes), .nova(.repetida), .terminal, .nova(.noContinua),
        ])
        #expect(pla.aObrir[2].argv == ["claude", "--dangerously-skip-permissions", "--effort", "ultracode", "--resume", conversa])
        #expect(pla.aObrir[1].argv == ["claude", "--dangerously-skip-permissions", "--effort", "ultracode"])
        #expect(pla.aObrir[7].argv == nil && pla.aObrir[7].yaml.exec == nil)
        #expect(pla.aObrir[2].yaml == PestanyaYAML(titol: "T3", carpeta: "/x/t3", exec:
            " WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000003 claude --dangerously-skip-permissions --effort ultracode --resume \(conversa)"))
        for p in pla.aObrir {
            #expect(!(p.argv ?? []).contains { $0 == "--continue" || $0 == "-c" }, "mai --continue (D7, D15)")
        }
        #expect(pla.avisos.map(\.tipus) == [
            .senseConversa, .conversaDUnaAltraCarpeta(projecte: "-x-altre"), .senseTranscripcio,
            .conversaEnDiversosProjectes(["-a", "-b"]), .conversaRepetida,
        ])
        #expect(pla.avisos.map { $0.pestanya?.id } == [id(2), id(4), id(5), id(6), id(7)])
        #expect(pla.avisos.map(\.esInfo) == [true, false, true, false, false])
        #expect(pla.xifres.text == "S'obrirà 1 finestra nova de Warp amb 9 pestanyes: 8 amb Claude (2 reprenen la seva "
            + "conversa, 6 en comencen una de nova) i 1 només terminal · unes 4 GB")
    }

    // MARK: Les que no es poden obrir

    @Test func lesQueNoEsPodenObrir() {
        let pestanyes = [
            pestanya(1, carpeta: "/x/perduda"),
            pestanya(2, claude: ClaudePestanya(modePermisos: "inventat")),
            pestanya(3, titol: "amb \u{7} campana"),
            pestanya(4, carpeta: "relativa"),
            pestanya(5),
        ]
        let pla = PlaObertura.calcula(finestra(pestanyes), entrada(lectura([]), noExisteixen: ["/x/perduda"]))
        #expect(pla.excloses.map(\.motiu) == [
            .carpetaNoExisteix,
            .validacio(Avis(.modePermisosDesconegut("inventat")).description),
            .fitxer(.titol(.caracterNoAdmes("\u{7}"))),
            .fitxer(.carpetaNoAbsoluta("relativa")),
        ])
        #expect(pla.aObrir.map(\.pestanya.id) == [id(5)])
        #expect(pla.xifres.text.hasSuffix(" · no s'obriran: 4"))
    }

    // MARK: Avisos

    @Test func avisosQueNoImpedeixenObrir() {
        let warp = lectura([[
            Llegida(titol: "X", pane: pane("a"), carpeta: "/x/t1"),
            Llegida(titol: "Y", pane: pane("b"), carpeta: inici),
        ]])
        let pestanyes = [
            pestanya(1),
            pestanya(2, claude: ClaudePestanya(altres: ["--fork-session"])),
            pestanya(3, carpeta: inici),
            pestanya(4, carpeta: "/confiada/sub"),
        ]
        let pla = PlaObertura.calcula(finestra(pestanyes), entrada(warp, estat: EstatApp(pestanyes: [id(2): vincle(sessio: "c2")]),
                                                                  transcripcions: ["c2": .aLaCarpeta],
                                                                  confiades: ["/confiada"]))
        let perPestanya = Dictionary(grouping: pla.avisos, by: { $0.pestanya?.id }).mapValues { $0.map(\.tipus) }
        #expect(perPestanya[id(1)] == [.senseConversa, .confianca, .potserJaOberta(lloc: "finestra 1 › X")])
        #expect(perPestanya[id(2)] == [.validacio(Avis(.opcionsDUnSolUs(["--fork-session"])).description), .confianca,
                                       .forkSession])
        // A la carpeta d'inici: Warp en té molts panes, i no vol dir res; però Claude sempre hi pregunta.
        #expect(perPestanya[id(3)] == [.validacio(Avis(.carpetaInici).description), .senseConversa, .confianca])
        #expect(perPestanya[id(4)] == [.senseConversa])
        #expect(pla.avisos.first { $0.tipus == .forkSession }?.description
            == "T2: porta «--fork-session»: cada obertura farà una còpia de la conversa")
    }

    /// Una conversa que una altra pestanya acaba de reprendre (el seu Claude encara no s'ha vist): compta com a oberta
    /// (R9). La pestanya que la reprèn no en queda afectada.
    @Test func unaConversaEnCursCompta() {
        let estat = EstatApp(pestanyes: [id(1): vincle(sessio: conversa), id(2): vincle(sessio: conversa)])
        let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2)]),
                                      entrada(lectura([]), estat: estat, transcripcions: [conversa: .aLaCarpeta],
                                              enCurs: [conversa: id(1)]))
        #expect(pla.obertes.map(\.pestanya.id) == [id(2)])
        #expect(pla.obertes.first?.on.description
            == "una altra pestanya acaba de reprendre la seva conversa (el Claude encara no s'ha vist)")
        #expect(pla.aObrir.map(\.conversa) == [.repren(conversa)])
    }

    /// Més de 10 sessions alhora, i l'últim llançament d'aquesta finestra sense confirmar fa menys de 10 min.
    @Test func avisosDeLaFinestra() {
        var estat = EstatApp()
        estat.desa(Llancament(id: id(500), fitxer: "f", mida: 1, creat: t0, finestra: id(100), pestanyes: [],
                              estat: .senseConfirmar))
        let onze = finestra((1...11).map { pestanya($0) })
        let ara = PlaObertura.calcula(onze, entrada(lectura([]), estat: estat, ara: t0 + 3 * 60)).avisos
            .filter { $0.pestanya == nil }
        #expect(ara.map(\.tipus) == [.moltesSessions(11), .darrerSenseConfirmar(minuts: 3)])
        #expect(ara.map(\.description) == [
            "s'engegaran 11 sessions de Claude alhora",
            "l'últim cop que es va obrir aquesta finestra (fa 3 min) no es va poder confirmar: mira Warp abans",
        ])
        let despres = PlaObertura.calcula(finestra([pestanya(1)]), entrada(lectura([]), estat: estat, ara: t0 + 11 * 60))
        #expect(despres.avisos.allSatisfy { $0.pestanya != nil })

        // També si encara és pendent, i amb un altre text si va fallar; no si es va confirmar.
        for (tipus, avis) in [(Llancament.Estat.error, AvisObertura.Tipus.darrerAmbError(minuts: 1)),
                              (.pendent, .darrerSenseConfirmar(minuts: 1)), (.confirmat, nil)] {
            var estat = EstatApp()
            estat.desa(Llancament(id: id(500), fitxer: "f", mida: 1, creat: t0, finestra: id(100), pestanyes: [],
                                  estat: tipus))
            let avisos = PlaObertura.calcula(finestra([pestanya(1)]), entrada(lectura([]), estat: estat, ara: t0 + 60)).avisos
            #expect(avisos.filter { $0.pestanya == nil }.map(\.tipus) == (avis.map { [$0] } ?? []), "\(tipus)")
        }
        #expect(AvisObertura(tipus: .darrerAmbError(minuts: 1)).description
            == "l'últim intent d'obrir aquesta finestra (fa 1 min) va fallar: si Warp n'ha obert res, mira-ho abans")
        // Una pestanya sense títol es diu pel nom de la carpeta.
        #expect(AvisObertura(pestanya: pestanya(1, carpeta: "/x/Botiga", titol: ""), tipus: .confianca).description
            .hasPrefix("Botiga: "))
    }

    // MARK: Xifres i fitxer

    @Test func lesXifres() {
        #expect(XifresObertura(pestanyes: 9, ambClaude: 6, reprenen: 4, terminal: 3, jaObertes: 14, excloses: 1).text
            == "S'obrirà 1 finestra nova de Warp amb 9 pestanyes: 6 amb Claude (4 reprenen la seva conversa, 2 en "
            + "comencen una de nova) i 3 només terminal · unes 3 GB · ja obertes: 14 · no s'obriran: 1")
        #expect(XifresObertura(pestanyes: 1, ambClaude: 1, reprenen: 1, terminal: 0, jaObertes: 0, excloses: 0).text
            == "S'obrirà 1 finestra nova de Warp amb 1 pestanya: 1 amb Claude (1 reprèn la seva conversa) · unes 0,5 GB")
        #expect(XifresObertura(pestanyes: 1, ambClaude: 0, reprenen: 0, terminal: 1, jaObertes: 0, excloses: 0).text
            == "S'obrirà 1 finestra nova de Warp amb 1 pestanya: 1 només terminal")
    }

    /// El fitxer porta les pestanyes que falten, en ordre, amb la marca de cadascuna.
    @Test func elFitxer() throws {
        let warp = lectura([[Llegida(titol: "T1", pane: pane("a"), carpeta: "/x/t1")]])
        let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2), pestanya(3, claude: ClaudePestanya(activat: false))]),
                                      entrada(warp, estat: EstatApp(pestanyes: [id(1): vincle(pane: pane("a"))])))
        let fitxer = try pla.fitxer(llancament: id(500))
        #expect(fitxer.nomFitxer == "warp-launch-00000000-0000-0000-0000-000000000500.yaml")
        #expect(fitxer.text.contains("T2") && fitxer.text.contains("T3") && !fitxer.text.contains("\"T1\""))
        #expect(fitxer.text.contains("WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000002 claude"))
        #expect(!fitxer.text.contains("WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000003"))
        #expect(!fitxer.text.contains("export"))
    }
}

@Suite struct ConfirmacioOberturaTests {
    private static let aObrir: [PestanyaAObrir] = {
        let pla = PlaObertura.calcula(finestra([pestanya(1), pestanya(2, titol: "", claude: ClaudePestanya(activat: false))]),
                                      entrada(lectura([])))
        return pla.aObrir
    }()
    private static let abans: Set<String> = [pane("a")]

    private func busca(_ lectura: LecturaWarp, desDe: Date = t0) -> Confirmacio? {
        ConfirmacioObertura.busca(lectura, obertes: Self.aObrir, panesAbans: Self.abans, terminalsAbans: [99], desDe: desDe,
                                  inici: inici)
    }

    private let vella = [Llegida(titol: "Vella", pane: pane("a"), carpeta: "/x/v")]

    /// La finestra nova: tots els panes nous, i els títols i les carpetes en ordre (el títol buit és el de la carpeta).
    @Test func laFinestraNova() {
        let nova = [Llegida(titol: "T1", pane: pane("n"), carpeta: "/x/t1"), Llegida(titol: "t2", pane: pane("m"), carpeta: "/x/t2")]
        #expect(busca(lectura([vella, nova])) == Confirmacio(finestra: 2, panes: [id(1): pane("n"), id(2): pane("m")], sessions: [:]))
        // Sense títol, o amb la carpeta encara a l'inici: també.
        var dubtosa = nova
        dubtosa[0].titol = nil
        dubtosa[1].carpeta = inici
        #expect(busca(lectura([vella, dubtosa]))?.finestra == 2)
        // Però no si no coincideix res: pot ser una finestra feta a mà (⌘N), sense títol i a l'inici.
        let feta = nova.map { var l = $0; l.titol = nil; l.carpeta = inici; return l }
        #expect(busca(lectura([vella, feta])) == nil)
    }

    /// Si una marca és en una finestra nova, a la posició de la seva pestanya, aquesta és la finestra, encara que els
    /// títols no coincideixin; les altres pestanyes es lliguen per ordre.
    @Test func laMarcaReconeixLaFinestra() {
        let s1 = sessio("s1", pane: pane("n"), marca: id(1))
        let nova = [Llegida(titol: "Un altre", pane: pane("n"), carpeta: "/x/t1", claude: s1),
                    Llegida(titol: "zsh", pane: pane("m"), carpeta: "/x/t2")]
        #expect(busca(lectura([vella, nova])) == Confirmacio(finestra: 2, panes: [id(1): pane("n"), id(2): pane("m")],
                                                             sessions: [id(1): "s1"]))
        // A una altra posició no compta: només la marca.
        let girada = [nova[1], nova[0]]
        #expect(busca(lectura([vella, girada])) == Confirmacio(finestra: nil, panes: [id(1): pane("n")], sessions: [id(1): "s1"]))
    }

    /// El que es veu en lectures successives s'acumula; és completa amb la finestra i el Claude de cada pestanya.
    @Test func afegeixICompleta() {
        var vist = Confirmacio(finestra: nil, panes: [id(1): pane("n")], sessions: [id(1): "s1"])
        #expect(!vist.completa(Self.aObrir))
        #expect(vist.senseClaude(Self.aObrir).isEmpty, "la 2 és només terminal")
        vist.afegeix(Confirmacio(finestra: 2, panes: [id(1): pane("n"), id(2): pane("m")], sessions: [id(1): "s1"]))
        #expect(vist == Confirmacio(finestra: 2, panes: [id(1): pane("n"), id(2): pane("m")], sessions: [id(1): "s1"]))
        #expect(vist.completa(Self.aObrir))
        // Una lectura posterior sense finestra no la treu.
        vist.afegeix(Confirmacio(finestra: nil, panes: [id(1): pane("n")], sessions: [id(1): "s1"]))
        #expect(vist.finestra == 2 && vist.panes[id(2)] == pane("m"))
        let senseClaude = Confirmacio(finestra: 2, panes: [:], sessions: [:])
        #expect(!senseClaude.completa(Self.aObrir))
        #expect(senseClaude.senseClaude(Self.aObrir).map(\.pestanya.id) == [id(1)])
    }

    @Test func elQueNoEsLaFinestraNova() {
        let nova = [Llegida(titol: "T1", pane: pane("n"), carpeta: "/x/t1"), Llegida(titol: "t2", pane: pane("m"), carpeta: "/x/t2")]
        var ambUnPaneVell = nova
        ambUnPaneVell[1].pane = pane("a")
        var altreTitol = nova
        altreTitol[0].titol = "Un altre"
        var altraCarpeta = nova
        altraCarpeta[1].carpeta = "/x/altra"
        for finestres in [[vella, ambUnPaneVell], [vella, altreTitol], [vella, altraCarpeta], [vella, Array(nova.prefix(1))],
                          [vella], [vella, nova, nova.map { var l = $0; l.pane = String(l.pane.reversed()) + "9"; return l }]] {
            #expect(busca(lectura(finestres)) == nil)
        }
    }

    /// Una sessió amb la marca d'una pestanya del fitxer, començada després d'obrir (amb 5 s de marge).
    @Test func laMarca() {
        let nova = sessio("s1", pane: pane("n"), marca: id(1), iniciada: t0 - 4)
        #expect(busca(lectura([vella], sense: [nova])) == Confirmacio(finestra: nil, panes: [id(1): pane("n")], sessions: [id(1): "s1"]))
        for sessio in [sessio("s1", pane: pane("n"), marca: id(1), iniciada: t0 - 6),
                       sessio("s1", pane: pane("n"), marca: id(1), iniciada: nil),
                       sessio("s1", pane: pane("n"), marca: id(9))] {
            #expect(busca(lectura([vella], sense: [sessio])) == nil)
        }
    }
}

/// Quina conversa reprèn cada pestanya (D7, decisió d'en David del 05/11/2026): sempre la més recent de la seva carpeta, sense
/// agafar-ne cap de viva ni d'una altra pestanya (R9). Abans, en una prova real, gairebé totes les pestanyes n'haurien
/// començat una de nova.
@Suite struct ConversaMesRecentTests {
    private static let vella = "aaaaaaaa-0000-4000-8000-000000000001"
    private static let nova = "bbbbbbbb-0000-4000-8000-000000000002"

    /// A `/x/t1`: la nova, de fa 3 dies, i la vella, de fa 10.
    private static let recents = ["/x/t1": [LectorTranscripcions.Recent(id: nova, darrerMissatge: t0 - 3 * 86400),
                                            LectorTranscripcions.Recent(id: vella, darrerMissatge: t0 - 10 * 86400)]]

    private func pla(_ lectura: LecturaWarp = lectura([]), estat: EstatApp = EstatApp(), pestanyes: [Pestanya] = [pestanya(1)],
                     enCurs: [String: UUID] = [:]) -> Pla {
        PlaObertura.calcula(finestra(pestanyes), entrada(lectura, estat: estat, enCurs: enCurs, recents: Self.recents))
    }

    /// Sense cap conversa recordada: la més recent, amb `--resume`, i el full diu de quan és.
    @Test func senseRecordadaAgafaLaMesRecent() {
        let resultat = pla()
        #expect(resultat.aObrir.map(\.conversa) == [.repren(Self.nova)])
        #expect(resultat.aObrir[0].argv?.suffix(2) == ["--resume", Self.nova])
        #expect(!(resultat.aObrir[0].argv ?? []).contains("--continue"), "mai --continue (D15)")
        #expect(resultat.avisos.map(\.tipus) == [.conversaMesRecent(fa: 3 * 86400)])
        #expect(resultat.avisos[0].esInfo)
        #expect(resultat.avisos[0].description == "T1: reprèn la conversa més recent de la carpeta (fa 3 dies)")
    }

    /// Una recordada sense missatges, com les d'una obertura anterior (05/11/2026): també la més recent.
    @Test func laRecordadaSenseMissatgesNoCompta() {
        let resultat = pla(estat: EstatApp(pestanyes: [id(1): vincle(sessio: "buida")]))
        #expect(resultat.aObrir.map(\.conversa) == [.repren(Self.nova)])
    }

    /// «Sempre la més recent»: també si en recorda una de més antiga. Si la recordada és la més recent, no cal dir res.
    @Test func sempreLaMesRecentEncaraQueEnRecordiUna() {
        let antiga = pla(estat: EstatApp(pestanyes: [id(1): vincle(sessio: Self.vella)]))
        #expect(antiga.aObrir.map(\.conversa) == [.repren(Self.nova)])
        #expect(antiga.avisos.map(\.tipus) == [.conversaMesRecent(fa: 3 * 86400)])

        let mateixa = pla(estat: EstatApp(pestanyes: [id(1): vincle(sessio: Self.nova)]))
        #expect(mateixa.aObrir.map(\.conversa) == [.repren(Self.nova)])
        #expect(mateixa.avisos.isEmpty)
    }

    /// Una conversa viva no es pot reprendre (R9): en una altra pestanya, fora de Warp o en segon pla, agafa la següent.
    @Test func noAgafaUnaDeViva() {
        var viva = lectura([])
        viva.sessionsSensePestanya = [sessio(Self.nova, pane: nil)]
        #expect(pla(viva).aObrir.map(\.conversa) == [.repren(Self.vella)])

        var segonPla = lectura([])
        segonPla.sessionsNoInteractives = [SessioViva(pid: 9, sessionId: Self.nova, tipus: "bg", carpeta: "/x/t1")]
        #expect(pla(segonPla).aObrir.map(\.conversa) == [.repren(Self.vella)])
    }

    /// Un Claude aturat a preguntar si confies en la carpeta encara no ha escrit la sessió, però la conversa ja és seva (R9): ni
    /// la més recent, ni una altra pestanya que la recordi. Abans només ho sabia la memòria de l'app, durant 10 minuts.
    @Test func unClaudeAturatGuardaLaSevaConversa() {
        var aturat = lectura([])
        aturat.terminals = [TerminalViu(pid: 7, carpeta: "/x/t1", marca: id(1), claude: true, conversa: Self.nova)]
        let pestanyes = [pestanya(1), pestanya(2, carpeta: "/x/t1")]
        let resultat = pla(aturat, pestanyes: pestanyes)
        #expect(resultat.obertes.map(\.pestanya.id) == [id(1)])
        #expect(resultat.aObrir.map(\.conversa) == [.repren(Self.vella)])

        let recordada = pla(aturat, estat: EstatApp(pestanyes: [id(2): vincle(sessio: Self.nova)]), pestanyes: pestanyes)
        #expect(recordada.obertes.map(\.on) == [.marca(lloc: nil), .conversaEnCurs])
    }

    /// Si ja ha escrit la sessió, mana la sessió: després d'un `/clear`, els arguments continuen dient la conversa d'abans.
    @Test func elsArgumentsDUnClaudeAmbSessioNoCompten() {
        var viu = lectura([])
        viu.sessionsSensePestanya = [sessio(Self.vella, pane: nil, marca: id(1))]
        viu.terminals = [TerminalViu(pid: 7, carpeta: "/x/t1", marca: id(1), claude: true, conversa: Self.nova)]
        #expect(viu.conversesArrencant.isEmpty)
        #expect(viu.conversesVives == [Self.vella])
        #expect(pla(viu, pestanyes: [pestanya(1), pestanya(2, carpeta: "/x/t1")]).aObrir.map(\.conversa) == [.repren(Self.nova)])
    }

    /// La d'una altra pestanya de la configuració no s'agafa, encara que sigui a la mateixa carpeta: cadascuna es queda la
    /// seva. Si aquella pestanya ja no és a la configuració, sí.
    @Test func noAgafaLaDUnaAltraPestanya() {
        let pestanyes = [pestanya(1), pestanya(2, carpeta: "/x/t1")]
        let totes = pla(estat: EstatApp(pestanyes: [id(1): vincle(sessio: Self.vella), id(2): vincle(sessio: Self.nova)]), pestanyes: pestanyes)
        #expect(totes.aObrir.map(\.conversa) == [.repren(Self.vella), .repren(Self.nova)])

        var fora = vincle(sessio: Self.nova)
        fora.foraDesDe = t0
        #expect(pla(estat: EstatApp(pestanyes: [id(9): fora])).aObrir.map(\.conversa) == [.repren(Self.nova)])
    }

    /// Dues pestanyes a la mateixa carpeta, cap amb conversa: cadascuna la seva, mai la mateixa en dues (R9). La tercera, nova.
    @Test func duesPestanyesALaMateixaCarpeta() {
        let resultat = pla(pestanyes: [pestanya(1), pestanya(2, carpeta: "/x/t1"), pestanya(3, carpeta: "/x/t1")])
        #expect(resultat.aObrir.map(\.conversa) == [.repren(Self.nova), .repren(Self.vella), .nova(.senseConversa)])
    }

    /// La que una altra pestanya acaba de reprendre no s'agafa; la que ha repres aquesta mateixa, sí.
    @Test func lesEnCurs() {
        #expect(pla(enCurs: [Self.nova: id(9)]).aObrir.map(\.conversa) == [.repren(Self.vella)])
        #expect(pla(enCurs: [Self.nova: id(1)]).aObrir.map(\.conversa) == [.repren(Self.nova)])
    }

    /// Sense converses a la carpeta, com abans: la recordada, si es troba, o una de nova.
    @Test func senseRecentsComAbans() {
        let carpetaBuida = pestanya(2)
        #expect(pla(pestanyes: [carpetaBuida]).aObrir.map(\.conversa) == [.nova(.senseConversa)])
    }

    /// «Continua la conversa» desactivat mana: mai no en reprèn cap.
    @Test func senseContinuarNoEnRepren() {
        var pestanyaNova = pestanya(1)
        pestanyaNova.claude.continua = false
        #expect(pla(pestanyes: [pestanyaNova]).aObrir.map(\.conversa) == [.nova(.noContinua)])
    }

    /// Una pestanya només de terminal no en reprèn cap.
    @Test func unaDeTerminalNoEnRepren() {
        var terminal = pestanya(1)
        terminal.claude.activat = false
        #expect(pla(pestanyes: [terminal]).aObrir.map(\.conversa) == [.terminal])
    }

    /// L'inspector i «Copia l'ordre» diuen el mateix que el full: la més recent, sense les d'altres pestanyes ni les vives; si
    /// no n'hi ha, la recordada.
    @Test func laQueMostraLInspector() {
        let recents = Self.recents["/x/t1"] ?? []
        #expect(EstatApp().conversaAReprendre(de: id(1), recents: recents, vives: []) == Self.nova)
        let altra = EstatApp(pestanyes: [id(2): vincle(sessio: Self.nova)])
        #expect(altra.conversaAReprendre(de: id(1), recents: recents, vives: []) == Self.vella)
        let recordada = EstatApp(pestanyes: [id(1): vincle(sessio: "c")])
        #expect(recordada.conversaAReprendre(de: id(1), recents: [], vives: []) == "c")
        #expect(EstatApp().conversaAReprendre(de: id(1), recents: [], vives: []) == nil)
    }

    /// Una conversa viva (el cas real: una feina en segon pla) no surt a l'ordre que es copia, llevat que sigui
    /// la de la mateixa pestanya, que és oberta.
    @Test func lInspectorNoDonaUnaDeViva() {
        let recents = Self.recents["/x/t1"] ?? []
        #expect(EstatApp().conversaAReprendre(de: id(1), recents: recents, vives: [Self.nova]) == Self.vella)
        let propia = EstatApp(pestanyes: [id(1): vincle(sessio: Self.nova)])
        #expect(propia.conversaAReprendre(de: id(1), recents: recents, vives: [Self.nova]) == Self.nova)
    }

    /// Com es diu quan és: en hores, i en dies a partir de 24 h.
    @Test func quanEs() {
        #expect(AvisObertura(tipus: .conversaMesRecent(fa: 600)).description.hasSuffix("(fa menys d'1 h)"))
        #expect(AvisObertura(tipus: .conversaMesRecent(fa: 5 * 3600)).description.hasSuffix("(fa 5 h)"))
        #expect(AvisObertura(tipus: .conversaMesRecent(fa: 86400)).description.hasSuffix("(fa 1 dia)"))
    }
}

/// Amb la restauració de sessió desactivada, Warp no desa les finestres (docs/fets-verificats.md, 05/11/2026): `finestres` és
/// buit, i el que hi ha obert ho diuen els processos. El 05/11/2026, amb la base d'abans, l'app deia que totes les pestanyes ja
/// eren obertes i no n'obria cap.
@Suite struct SenseFinestresTests {
    /// La lectura tal com surt de `Lector`: sense finestres, amb les sessions i els terminals.
    private func processos(_ terminals: [TerminalViu], sessions: [SessioClaude] = [], warpObert: Bool = true) -> LecturaWarp {
        LecturaWarp(finestres: [], sessionsSensePestanya: sessions, avisos: [], warpObert: warpObert, terminals: terminals,
                    warpDesaFinestres: false)
    }

    private func pla(_ lectura: LecturaWarp, estat: EstatApp = EstatApp(), pestanyes: [Pestanya] = [pestanya(1), pestanya(2)],
                     transcripcions: [String: LectorTranscripcions.On] = [:]) -> Pla {
        PlaObertura.calcula(finestra(pestanyes), entrada(lectura, estat: estat, transcripcions: transcripcions))
    }

    /// Un pane recordat d'un Warp que ja no hi és: la pestanya no és oberta, i reprèn la seva conversa.
    @Test func unPaneRecordatNoVolDirQueSiguiOberta() {
        let estat = EstatApp(pestanyes: [id(1): vincle(pane: pane("a"), sessio: conversa), id(2): vincle(pane: pane("b"))])
        let resultat = pla(processos([]), estat: estat, transcripcions: [conversa: .aLaCarpeta])
        #expect(resultat.obertes.isEmpty)
        #expect(resultat.aObrir.map(\.conversa) == [.repren(conversa), .nova(.senseConversa)])
        #expect(resultat.motiuEspera == nil)
    }

    /// Una sessió viva amb la marca és oberta: no «s'acaba de tancar» perquè el seu pane no sigui a la base. Era el que deia
    /// de les 6 pestanyes de «Principal», i la finestra no s'hauria pogut tornar a obrir mai.
    @Test func laMarcaNoEsConfonAmbUnaPestanyaTancada() {
        let viva = sessio("s1", pane: pane("n"), marca: id(1))
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true)],
                                     sessions: [viva]))
        #expect(resultat.obertes.map(\.on) == [.marca(lloc: nil)])
        #expect(resultat.aObrir.map(\.pestanya.id) == [id(2)])
        #expect(resultat.motiuEspera == nil)
    }

    /// Un Claude amb la marca que encara no ha escrit la sessió (s'ha aturat a preguntar si confies en la carpeta): és obert.
    @Test func unClaudeAturatEsObert() {
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true)]))
        #expect(resultat.obertes.map(\.on) == [.marca(lloc: nil)])
    }

    /// El pane recordat és viu perquè hi corre un procés que el porta, encara que no sigui Claude.
    @Test func elPaneRecordatEsViu() {
        let estat = EstatApp(pestanyes: [id(1): vincle(pane: pane("n")), id(2): vincle(pane: pane("m"))])
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x", pane: pane("n")),
                                      TerminalViu(pid: 8, carpeta: "/x", pane: pane("m"), claude: true)]), estat: estat)
        #expect(resultat.obertes.map(\.on) == [.paneViu(ambClaude: false), .paneViu(ambClaude: true)])
        #expect(resultat.obertes[0].on.description == "oberta a Warp, sense Claude")
    }

    /// La conversa recordada és viva a Warp, sense marca (un `/resume` a mà): és oberta, i no atura la finestra.
    @Test func laConversaVivaEsAWarp() {
        let estat = EstatApp(pestanyes: [id(1): vincle(sessio: "s1")])
        let resultat = pla(processos([], sessions: [sessio("s1", pane: pane("z"))]), estat: estat)
        #expect(resultat.obertes.map(\.on) == [.conversaAWarp])
        #expect(resultat.motiuEspera == nil)
    }

    /// Un terminal sense Claude a la carpeta de la pestanya potser és aquesta, però no se'n sap el títol: avisa i s'obre. A la
    /// carpeta d'inici (la finestra buida que obre Warp en arrencar) no diu res, ni un terminal amb Claude.
    @Test func unTerminalALaCarpetaNomesAvisa() {
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x/t1"),
                                      TerminalViu(pid: 9, carpeta: inici)]),
                           pestanyes: [pestanya(1), pestanya(3, carpeta: inici)])
        #expect(resultat.aObrir.count == 2)
        #expect(avisosDeTerminal(resultat) == [id(1): false])
        #expect(resultat.potserObertes == 0, "no proposa «Lliga amb Warp…», que no pot fer res")
    }

    /// Un Claude obert a mà a la carpeta també avisa: amb la base, sortia «potser ja és oberta». El d'una altra pestanya, no.
    @Test func unClaudeObertAMaALaCarpetaAvisa() {
        let estat = EstatApp(pestanyes: [id(8): vincle(pane: pane("r"))])
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x/t1", pane: pane("h"), claude: true),
                                      TerminalViu(pid: 8, carpeta: "/x/t2", pane: pane("m"), marca: id(9), claude: true),
                                      TerminalViu(pid: 9, carpeta: "/x/t3", pane: pane("r"), claude: true)]),
                           estat: estat, pestanyes: [pestanya(1), pestanya(2), pestanya(3)])
        #expect(resultat.aObrir.count == 3)
        #expect(avisosDeTerminal(resultat) == [id(1): true])
        #expect(resultat.avisos.first { if case .terminalALaCarpeta = $0.tipus { true } else { false } }?
            .description.contains("no és de cap pestanya") == true)
    }

    /// Sense la base (la restauració desactivada, D6): un Claude que corre a la carpeta de la pestanya, amb el shell a una altra,
    /// també avisa (decisió d'en David del 09/11/2026). El d'una altra pestanya, no.
    @Test func unClaudeALaCarpetaAmbElShellAUnaAltraAvisa() {
        func claude(_ id: String, _ p: Character, _ carpeta: String, marca: UUID? = nil) -> SessioClaude {
            var s = sessio(id, pane: pane(p), marca: marca)
            s.carpeta = carpeta
            return s
        }
        let resultat = pla(processos([TerminalViu(pid: 7, carpeta: "/x/altra", pane: pane("h"), claude: true),
                                      TerminalViu(pid: 8, carpeta: "/x/altra", pane: pane("m"), marca: id(9), claude: true)],
                                     sessions: [claude("s1", "h", "/x/t1"), claude("s2", "m", "/x/t2", marca: id(9))]),
                           pestanyes: [pestanya(1), pestanya(2)])
        #expect(avisosDeTerminal(resultat) == [id(1): true])
    }

    /// Les pestanyes amb l'avís del terminal, i si és un Claude.
    private func avisosDeTerminal(_ pla: Pla) -> [UUID: Bool] {
        var avisos: [UUID: Bool] = [:]
        for avis in pla.avisos {
            if case let .terminalALaCarpeta(ambClaude) = avis.tipus, let pestanya = avis.pestanya { avisos[pestanya.id] = ambClaude }
        }
        return avisos
    }

    // MARK: Una finestra acabada de tancar

    private static let viva = TerminalViu(pid: 1, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true)

    private func avisTancada(_ pla: Pla) -> [AvisObertura.Tipus] {
        pla.avisos.map(\.tipus).filter { if case .potserTancadaFaPoc = $0 { true } else { false } }
    }

    /// Warp en manté els Claude 60 s, i no es pot saber si són d'una finestra oberta o d'una de tancada: el full ho diu, sense
    /// bloquejar. Si n'obriria només una part, diu que la finestra quedaria partida.
    @Test func lesVivesPodenSerDUnaFinestraTancada() {
        let totes = pla(processos([Self.viva, TerminalViu(pid: 2, carpeta: "/x/t2", pane: pane("m"), marca: id(2), claude: true)]))
        #expect(totes.aObrir.isEmpty)
        #expect(avisTancada(totes) == [.potserTancadaFaPoc(partiria: false)])

        let partida = pla(processos([Self.viva]))
        #expect(partida.aObrir.map(\.pestanya.id) == [id(2)])
        #expect(avisTancada(partida) == [.potserTancadaFaPoc(partiria: true)])
        #expect(partida.motiuEspera == nil, "no es pot bloquejar: una finestra oberta a la qual falta una pestanya és igual")
        #expect(partida.avisos.first { if case .potserTancadaFaPoc = $0.tipus { true } else { false } }?
            .description.hasSuffix("la finestra quedarà partida") == true)
    }

    /// Sense res viu, no cal avisar; i amb la restauració activada, ja ho diu la base.
    @Test func senseVivesOAmbLaBaseNoAvisa() {
        #expect(avisTancada(pla(processos([]))).isEmpty)
        var warp = lectura([])
        warp.terminals = [Self.viva]
        #expect(avisTancada(PlaObertura.calcula(finestra([pestanya(1), pestanya(2)]), entrada(warp))).isEmpty)
    }

    /// Els avisos del terminal només hi són sense la base: amb la base, ja ho diu el pane.
    @Test func ambLaBaseNoEsMiraLaCarpetaDelsTerminals() {
        var warp = lectura([])
        warp.terminals = [TerminalViu(pid: 7, carpeta: "/x/t1")]
        #expect(avisosDeTerminal(PlaObertura.calcula(finestra([pestanya(1)]), entrada(warp))).isEmpty)
    }

    // MARK: Confirmació

    private static let aObrir: [PestanyaAObrir] = PlaObertura.calcula(
        finestra([pestanya(1), pestanya(2)]), entrada(lectura([]))).aObrir

    private func busca(_ lectura: LecturaWarp, abans: Set<Int32> = [99], obertes: [PestanyaAObrir] = Self.aObrir,
                       warpAcabatDEngegar: Bool = false, carpetesDAltres: Set<String> = []) -> Confirmacio? {
        ConfirmacioObertura.busca(lectura, obertes: obertes, panesAbans: [], terminalsAbans: abans, desDe: t0, inici: inici,
                                  warpAcabatDEngegar: warpAcabatDEngegar, carpetesDAltres: carpetesDAltres)
    }

    /// El cas real (05/11/2026): cap finestra a la base, i un terminal nou amb la marca per pestanya. Abans, «No s'ha pogut
    /// reconèixer la finestra nova» després d'esperar 30 s, encara que s'havia vist Claude a totes les pestanyes.
    @Test func lesMarquesConfirmenSenseFinestra() throws {
        let terminals = [TerminalViu(pid: 1, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true),
                         TerminalViu(pid: 2, carpeta: "/x/t2", pane: pane("m"), marca: id(2), claude: true)]
        let sessions = [sessio("s1", pane: pane("n"), marca: id(1)), sessio("s2", pane: pane("m"), marca: id(2))]
        let vist = try #require(busca(processos(terminals, sessions: sessions)))
        #expect(vist == Confirmacio(finestra: nil, panes: [id(1): pane("n"), id(2): pane("m")],
                                    sessions: [id(1): "s1", id(2): "s2"], terminals: [id(1), id(2)], marcats: [id(1), id(2)]))
        #expect(vist.vista([id(1), id(2)]))
        #expect(vist.completa(Self.aObrir))
        #expect(vist.segura)
    }

    /// Un terminal sense marca es pren per la carpeta, però no és segur que sigui d'aquest fitxer: amb altres finestres
    /// alhora, podria ser d'una altra.
    @Test func perLaCarpetaNoEsSegur() throws {
        let terminals = [TerminalViu(pid: 7, carpeta: "/x/t2")]
        let vist = try #require(busca(processos(terminals)))
        #expect(vist.terminals == [id(2)] && vist.perCarpeta == [id(2): 7] && vist.marcats.isEmpty)
        #expect(!vist.segura)
        // Si ja l'ha pres una altra finestra, no compta.
        #expect(busca(processos(terminals), abans: [99, 7]) == nil)
    }

    /// Un Claude aturat a preguntar: el terminal és vist i en surt el pane, però encara falta la sessió.
    @Test func unClaudeAturatEsVeuPeroNoEsComplet() throws {
        let terminals = [TerminalViu(pid: 1, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true),
                         TerminalViu(pid: 2, carpeta: "/x/t2", pane: pane("m"), marca: id(2), claude: true)]
        let vist = try #require(busca(processos(terminals)))
        #expect(vist.vista([id(1), id(2)]))
        #expect(vist.panes == [id(1): pane("n"), id(2): pane("m")])
        #expect(!vist.completa(Self.aObrir))
        #expect(vist.senseClaude(Self.aObrir).map(\.pestanya.id) == [id(1), id(2)])
    }

    /// Mentre Claude no ha arrencat, el terminal compta per la carpeta; n'hi ha d'haver un per pestanya.
    @Test func senseMarcaCompteElTerminalDeLaCarpeta() throws {
        let vist = try #require(busca(processos([TerminalViu(pid: 1, carpeta: "/x/t1"), TerminalViu(pid: 2, carpeta: "/x/t2")])))
        #expect(vist.terminals == [id(1), id(2)])
        #expect(vist.vista([id(1), id(2)]))
        #expect(vist.panes.isEmpty, "del shell no se'n sap el pane")

        let dues = PlaObertura.calcula(finestra([pestanya(1, carpeta: "/x/c"), pestanya(2, carpeta: "/x/c")]), entrada(lectura([]))).aObrir
        let una = try #require(busca(processos([TerminalViu(pid: 1, carpeta: "/x/c")]), obertes: dues))
        #expect(una.terminals.count == 1 && !una.vista(dues.map(\.pestanya.id)), "un terminal, una pestanya")
    }

    /// Els terminals d'abans d'obrir no compten, ni un de nou a una altra carpeta o amb la marca d'una altra pestanya.
    @Test func elQueNoComptaComAFinestraNova() throws {
        let terminals = [TerminalViu(pid: 99, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true),
                         TerminalViu(pid: 1, carpeta: "/x/altra"),
                         TerminalViu(pid: 2, carpeta: "/x/t2", marca: id(9), claude: true)]
        #expect(busca(processos(terminals)) == nil)
    }

    /// Una pestanya a la carpeta d'inici es confirma pel seu terminal; però no si l'app acaba d'engegar Warp, perquè la
    /// finestra buida també hi és.
    @Test func laCarpetaDIniciComptaSiWarpJaEraObert() throws {
        let aInici = PlaObertura.calcula(finestra([pestanya(1, carpeta: inici)]), entrada(lectura([]))).aObrir
        let shell = processos([TerminalViu(pid: 1, carpeta: inici)])
        let vist = try #require(busca(shell, obertes: aInici))
        #expect(vist.vista([id(1)]))
        #expect(busca(shell, obertes: aInici, warpAcabatDEngegar: true) == nil)
    }

    /// Amb la restauració activada, mana la base: un shell restaurat tard no és de la finestra nova, i sense la finestra no
    /// se sabrien els panes de les pestanyes de terminal.
    @Test func ambLaRestauracioActivadaElsTerminalsNoCompten() {
        var warp = lectura([])
        warp.terminals = [Self.viva, TerminalViu(pid: 2, carpeta: "/x/t2")]
        #expect(busca(warp) == nil)
    }

    /// `afegeix` acumula els terminals de cada lectura.
    @Test func afegeixAcumulaElsTerminals() {
        var vist = Confirmacio(finestra: nil, panes: [:], sessions: [:], terminals: [id(1)])
        vist.afegeix(Confirmacio(finestra: nil, panes: [:], sessions: [:], terminals: [id(2)]))
        #expect(vist.vista([id(1), id(2)]))
        #expect(!vist.vista([id(1), id(2), id(3)]))
        #expect(!Confirmacio(finestra: nil, panes: [:], sessions: [:]).vista([]), "sense res, no s'ha vist res")
    }

    // MARK: El shell de les pestanyes de terminal (0.34.0)

    private static let hora = IniciProces(segons: 1_793_750_000, microsegons: 42)

    /// Un shell amb l'hora d'inici (`TerminalViu.inici`).
    private func shell(_ pid: Int32, _ carpeta: String?, hora: IniciProces? = Self.hora) -> TerminalViu {
        TerminalViu(pid: pid, carpeta: carpeta, inici: hora)
    }

    private func recordat(_ pid: Int32) -> ShellRecordat { ShellRecordat(pid: pid, inici: Self.hora) }

    /// Les pestanyes per obrir d'una finestra, totes sense lligam.
    private func aObrir(_ pestanyes: [Pestanya]) -> [PestanyaAObrir] {
        PlaObertura.calcula(finestra(pestanyes), entrada(lectura([]))).aObrir
    }

    /// T1 amb Claude, a /x/t1, i T2 només terminal, a /x/t2.
    private static let ambTerminal: [PestanyaAObrir] = PlaObertura.calcula(
        finestra([pestanya(1), pestanya(2, claude: .nomesTerminal)]), entrada(lectura([]))).aObrir

    /// El Claude de T1, amb la marca: el seu shell no és de cap pestanya de terminal.
    private static let claudeT1 = TerminalViu(pid: 1, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true,
                                              inici: hora)

    /// En confirmar, el shell nou de la pestanya de terminal, a la seva carpeta i sense Claude, és seu: el pid i l'hora d'inici.
    @Test func elShellDeLaPestanyaDeTerminal() throws {
        let vist = try #require(busca(processos([Self.claudeT1, shell(2, "/x/t2")]), obertes: Self.ambTerminal))
        #expect(vist.shells == [id(2): recordat(2)])
        #expect(vist.perCarpeta == [id(2): 2])
    }

    /// Dues pestanyes de terminal a la mateixa carpeta són intercanviables: per ordre de pid, cada shell a una sola.
    @Test func duesPestanyesDeTerminalALaMateixaCarpeta() throws {
        let dues = aObrir([pestanya(2, carpeta: "/x/c", claude: .nomesTerminal), pestanya(3, carpeta: "/x/c", claude: .nomesTerminal)])
        let vist = try #require(busca(processos([shell(9, "/x/c"), shell(8, "/x/c")]), obertes: dues))
        #expect(vist.shells == [id(2): recordat(8), id(3): recordat(9)])
    }

    /// Si hi ha cap dubte, no se'n desa cap: la pestanya es tornarà a obrir, com abans de la 0.34.0.
    @Test func ambDubtesNoEsDesaCapShell() throws {
        let dues = aObrir([pestanya(2, carpeta: "/x/c", claude: .nomesTerminal), pestanya(3, carpeta: "/x/c", claude: .nomesTerminal)])
        // Un shell de més (una pestanya oberta a mà) o de menys a la carpeta.
        #expect(try #require(busca(processos([Self.claudeT1, shell(2, "/x/t2"), shell(3, "/x/t2")]), obertes: Self.ambTerminal))
            .shells.isEmpty)
        #expect(try #require(busca(processos([shell(8, "/x/c")]), obertes: dues)).shells.isEmpty)
        // D'algun shell nou no se'n sap la carpeta: podria ser de qualsevol pestanya.
        #expect(try #require(busca(processos([Self.claudeT1, shell(2, "/x/t2"), shell(3, nil)]), obertes: Self.ambTerminal))
            .shells.isEmpty)
        // No se'n sap l'hora d'inici.
        #expect(try #require(busca(processos([Self.claudeT1, shell(2, "/x/t2", hora: nil)]), obertes: Self.ambTerminal))
            .shells.isEmpty)
        // Una altra finestra que s'obre alhora («Obre-ho tot») té alguna pestanya a la mateixa carpeta.
        #expect(try #require(busca(processos([Self.claudeT1, shell(2, "/x/t2")]), obertes: Self.ambTerminal,
                                   carpetesDAltres: ["/x/t2"])).shells.isEmpty)
        // Amb la restauració activada, els terminals no compten (mana la base).
        var ambBase = lectura([])
        ambBase.terminals = [Self.claudeT1, shell(2, "/x/t2")]
        #expect(busca(ambBase, obertes: Self.ambTerminal)?.shells.isEmpty ?? true)
        // Un shell d'abans d'obrir no és de la finestra nova.
        #expect(busca(processos([Self.claudeT1, shell(2, "/x/t2")]), abans: [2], obertes: Self.ambTerminal)?.shells.isEmpty == true)
    }

    /// Una pestanya amb Claude a la mateixa carpeta, mentre el seu Claude no porta la marca: el seu shell és igual que el de la
    /// de terminal. Quan la porta, el dubte s'acaba.
    @Test func unaPestanyaAmbClaudeSenseMarcaFaDubtar() throws {
        let mateixa = aObrir([pestanya(1, carpeta: "/x/c"), pestanya(2, carpeta: "/x/c", claude: .nomesTerminal)])
        let abansDeClaude = try #require(busca(processos([shell(1, "/x/c"), shell(2, "/x/c")]), obertes: mateixa))
        #expect(abansDeClaude.shells.isEmpty)
        let claude = TerminalViu(pid: 1, carpeta: "/x/c", pane: pane("n"), marca: id(1), claude: true, inici: Self.hora)
        let ambClaude = try #require(busca(processos([claude, shell(2, "/x/c")]), obertes: mateixa))
        #expect(ambClaude.shells == [id(2): recordat(2)])

        // `afegeix`: els shells són els de l'última lectura, també si ara fan dubtar.
        var vist = abansDeClaude
        vist.afegeix(ambClaude)
        #expect(vist.shells == [id(2): recordat(2)])
        vist.afegeix(try #require(busca(processos([claude, shell(2, "/x/c"), shell(3, "/x/c")]), obertes: mateixa)))
        #expect(vist.shells.isEmpty)
    }

    /// La carpeta d'inici, només si Warp ja era obert: si l'app l'acaba d'engegar, hi ha la finestra buida.
    @Test func elShellALaCarpetaDInici() throws {
        let aInici = aObrir([pestanya(2, carpeta: inici, claude: .nomesTerminal)])
        #expect(try #require(busca(processos([shell(2, inici)]), obertes: aInici)).shells == [id(2): recordat(2)])
        #expect(busca(processos([shell(2, inici)]), obertes: aInici, warpAcabatDEngegar: true)?.shells.isEmpty ?? true)
    }

    // MARK: Reconèixer-la pel shell (0.34.0)

    private func ambShell(_ n: Int, pid: Int32, hora: IniciProces = Self.hora) -> EstatApp {
        EstatApp(pestanyes: [id(n): VincleEstat(origen: .llancament, vista: t0, shell: ShellRecordat(pid: pid, inici: hora))])
    }

    /// Una pestanya de terminal amb el seu shell viu, el mateix pid i la mateixa hora d'inici, és oberta: no es torna a obrir.
    /// Si després s'hi ha engegat un Claude a mà, també.
    @Test func laPestanyaDeTerminalEsReconeixPelShell() {
        let terminal = pestanya(2, claude: .nomesTerminal)
        let viu = pla(processos([shell(7, "/x/t2")]), estat: ambShell(2, pid: 7), pestanyes: [terminal])
        #expect(viu.obertes.map(\.on) == [.shellViu(ambClaude: false)])
        #expect(viu.aObrir.isEmpty)
        #expect(viu.obertes.first?.on.description == "oberta a Warp, sense Claude")
        // Com el pane viu: pot ser una pestanya acabada de tancar, i el full ho diu.
        #expect(avisTancada(viu) == [.potserTancadaFaPoc(partiria: false)])

        // El shell s'ha mogut de carpeta, o hi corre un Claude: continua sent la pestanya.
        let ambClaude = pla(processos([TerminalViu(pid: 7, carpeta: "/x/altra", pane: pane("h"), claude: true, inici: Self.hora)]),
                            estat: ambShell(2, pid: 7), pestanyes: [terminal])
        #expect(ambClaude.obertes.map(\.on) == [.shellViu(ambClaude: true)])
    }

    /// El pid sol no val: si el procés ha acabat i el pid és d'un altre (una altra hora d'inici), o el shell ja no hi és (Warp
    /// tancat, o el Mac reiniciat), la pestanya es torna a obrir, com abans.
    @Test func elPidSolNoVal() {
        let terminal = pestanya(2, claude: .nomesTerminal)
        let altraHora = IniciProces(segons: Self.hora.segons, microsegons: Self.hora.microsegons + 1)
        let reutilitzat = pla(processos([shell(7, "/x/t2", hora: altraHora)]), estat: ambShell(2, pid: 7), pestanyes: [terminal])
        #expect(reutilitzat.obertes.isEmpty && reutilitzat.aObrir.map(\.pestanya.id) == [id(2)])
        let senseHora = pla(processos([shell(7, "/x/t2", hora: nil)]), estat: ambShell(2, pid: 7), pestanyes: [terminal])
        #expect(senseHora.obertes.isEmpty)
        let reiniciat = pla(processos([]), estat: ambShell(2, pid: 7), pestanyes: [terminal])
        #expect(reiniciat.obertes.isEmpty && reiniciat.aObrir.map(\.pestanya.id) == [id(2)])
    }

    /// Amb la restauració activada, mana la base (com amb el pane viu): el shell no es mira.
    @Test func ambLaBaseNoEsMiraElShell() {
        var warp = lectura([])
        warp.terminals = [shell(7, "/x/t2")]
        let resultat = PlaObertura.calcula(finestra([pestanya(2, claude: .nomesTerminal)]), entrada(warp, estat: ambShell(2, pid: 7)))
        #expect(resultat.obertes.isEmpty)
    }

    /// El shell recordat d'una pestanya no fa dir «potser ja és oberta» d'una altra a la mateixa carpeta; un shell que no és de
    /// cap pestanya, sí.
    @Test func elShellDUnaPestanyaNoFaAvisarUnaAltra() {
        let pestanyes = [pestanya(2, carpeta: "/x/c", claude: .nomesTerminal), pestanya(3, carpeta: "/x/c", claude: .nomesTerminal)]
        let reconegut = pla(processos([shell(7, "/x/c")]), estat: ambShell(2, pid: 7), pestanyes: pestanyes)
        #expect(reconegut.obertes.map(\.pestanya.id) == [id(2)] && reconegut.aObrir.map(\.pestanya.id) == [id(3)])
        #expect(avisosDeTerminal(reconegut).isEmpty)
        let desconegut = pla(processos([shell(7, "/x/c")]), pestanyes: pestanyes)
        #expect(avisosDeTerminal(desconegut) == [id(2): false, id(3): false])
    }
}
