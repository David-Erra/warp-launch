import Foundation
import Testing
@testable import WarpLaunchCore

// La finestra que Warp obre sola en arrencar (1.0.3, `FinestraDeWarp`): quin shell s'acabaria. Processos falsos
// (`ProcessosFalsos`), cap procés de debò, i cap senyal: `acaba` és un fals que només apunta el candidat.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
private let inici = "/Users/prova"
private let warp = ProcessosFalsos.executableWarp

private func hora(_ segons: Double) -> IniciProces {
    let total = t0.timeIntervalSince1970 + segons
    return IniciProces(segons: Int64(total.rounded(.down)),
                       microsegons: Int32(((total - total.rounded(.down)) * 1_000_000).rounded()))
}

/// L'app de Warp (40, arrencada a t0 + 1), el seu `terminal-server` (50), el shell de la pestanya de l'app (101, a /x/t1, amb
/// el seu Claude, 201) i el de la finestra de Warp (102, a l'inici, sense fills, zsh, a t0 + 1,5).
private func processos(warpA: Double = 1, shellWarp: Double = 1.5, carpeta: String = inici,
                       executable: String = "/bin/zsh") -> ProcessosFalsos {
    var p = ProcessosFalsos()
    p.processos[40] = (InfoProces(executable: warp, argv: [warp]), 1)
    p.processos[50] = (InfoProces(executable: warp, argv: [warp, "terminal-server", "--parent-pid=40"]), 40)
    p.processos[101] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 50)
    p.processos[201] = (InfoProces(executable: "/Users/prova/.local/share/claude/versions/2.1.322", argv: ["claude"]), 101)
    p.processos[102] = (InfoProces(executable: executable, argv: ["-zsh"]), 50)
    p.carpetes = [101: "/x/t1", 102: carpeta]
    p.inicis = [40: hora(warpA), 50: hora(warpA + 0.1), 101: hora(2), 201: hora(2.5), 102: hora(shellWarp)]
    return p
}

/// L'URL demanat a t0, una pestanya (amb Claude, reconeguda per la marca), confirmada a t0 + 3.
private func context(pestanyes: Int = 1, nostres: Set<Int32> = [], confirmada: Date? = t0 + 3,
                     dubte: String? = nil) -> FinestraDeWarp.Context {
    FinestraDeWarp.Context(inici: inici, desDe: t0, confirmada: confirmada, nostres: nostres, pestanyes: pestanyes,
                           dubte: dubte)
}

private func tria(_ p: ProcessosFalsos, _ c: FinestraDeWarp.Context = context(),
                  shellUsuari: String? = "/bin/zsh") -> FinestraDeWarp.Decisio {
    FinestraDeWarp.tria(p.fotoFinestraDeWarp(executable: warp), c, shellUsuari: shellUsuari)
}

private func esDubte(_ d: FinestraDeWarp.Decisio) -> Bool {
    if case .no(.dubte) = d { true } else { false }
}

private func pestanya(_ n: Int, carpeta: String, claude: Bool) -> PestanyaAObrir {
    PestanyaAObrir(pestanya: Pestanya(id: id(n), titol: "T\(n)", carpeta: carpeta, claude: ClaudePestanya(activat: claude)),
                   conversa: .terminal, argv: claude ? ["claude"] : nil,
                   yaml: PestanyaYAML(titol: "T\(n)", carpeta: carpeta, exec: nil))
}

private func acabat(_ pestanyes: [PestanyaAObrir], estat: Llancament.Estat = .confirmat, segons: Double? = 1.2,
                    vist: Confirmacio? = nil, finestra: Bool = true, desDe: Date = t0) -> ExecucioObertura.Resultat {
    var llancament = Llancament(id: id(900), fitxer: "f.yaml", mida: 10, creat: desDe, finestra: id(800),
                                pestanyes: pestanyes.map(\.pestanya.id), estat: estat)
    llancament.segons = segons
    return .acabat(ExecucioObertura.Acabat(correcte: true, text: "", llancament: llancament, vist: vist, finestra: finestra,
                                           senseClaude: [], desDe: desDe))
}

@Suite struct FinestraDeWarpTests {
    /// Un sol shell desconegut, a l'inici, sense fills, zsh, començat en arrencar Warp: és el que s'acaba, i `tanca` crida
    /// `acaba` un sol cop, amb ell.
    @Test func unSolCandidatEsTanca() throws {
        let p = processos()
        let esperat = FinestraDeWarp.Candidat(pid: 102, pare: 50, inici: hora(1.5), carpeta: inici)
        #expect(tria(p) == .acaba(esperat))
        var acabats: [FinestraDeWarp.Candidat] = []
        let resultat = FinestraDeWarp.tanca(context(), foto: { p.fotoFinestraDeWarp(executable: warp) }, shellUsuari: nil,
                                            acaba: { acabats.append($0); return .tancada($0.pid) })
        #expect(resultat == .tancada(102) && acabats == [esperat])
        #expect(FinestraDeWarp.text(resultat) == nil, "si s'ha tancat, el resultat no en parla")
        // Encara és el mateix procés, sense fills: es pot acabar.
        #expect(esperat.encaraEs(p))
    }

    /// El shell de l'usuari compta, encara que no sigui de la llista; `claude` i `node`, mai, ni com a shell de l'usuari.
    @Test(arguments: [("/opt/homebrew/bin/nu", "/opt/homebrew/bin/nu", true), ("/opt/homebrew/bin/nu", "/bin/zsh", false),
                      ("/bin/bash", nil, true), ("/opt/homebrew/bin/fish", nil, true), ("/bin/sh", nil, true),
                      ("/usr/local/bin/node", "/usr/local/bin/node", false),
                      ("/Users/prova/.local/bin/claude", "/Users/prova/.local/bin/claude", false),
                      ("/Users/prova/.local/share/claude/versions/zsh", nil, false)] as [(String, String?, Bool)])
    func lExecutableHaDeSerUnShell(executable: String, usuari: String?, tanca: Bool) {
        let d = tria(processos(executable: executable), shellUsuari: usuari)
        #expect(tanca ? d == .acaba(FinestraDeWarp.Candidat(pid: 102, pare: 50, inici: hora(1.5), carpeta: inici)) : esDubte(d))
    }

    /// Dos shells desconeguts (una pestanya feta a mà): no es tanca res.
    @Test func dosCandidatsNoEsTancaRes() {
        var p = processos()
        p.processos[103] = (InfoProces(executable: "/bin/zsh", argv: ["-zsh"]), 50)
        p.carpetes[103] = inici
        p.inicis[103] = hora(1.6)
        #expect(esDubte(tria(p)))
        // Encara que l'app esperés dues pestanyes: només una seva, i dues de desconegudes.
        #expect(esDubte(tria(p, context(pestanyes: 2))))
    }

    /// Amb un procés fill (una ordre que hi corre, també d'un altre usuari), fora de l'inici, o sense saber-ne els fills: res.
    @Test func ambFillsOForaDeLIniciNoEsTanca() {
        var ambFill = processos()
        ambFill.processos[300] = (InfoProces(executable: "/usr/bin/top", argv: ["top"]), 102)
        #expect(esDubte(tria(ambFill)))
        #expect(esDubte(tria(processos(carpeta: "/x/altra"))))
        var senseCarpeta = processos()
        senseCarpeta.carpetes[102] = nil
        #expect(esDubte(tria(senseCarpeta)))
    }

    /// Un shell que l'app ha reconegut com a seu (`perCarpeta`, `shells`) no es tanca mai, encara que sigui a l'inici: el
    /// desconegut és llavors el del Claude, que té fills.
    @Test func unDelsNostresNoEsTanca() {
        #expect(esDubte(tria(processos(), context(nostres: [102]))))
        // Ni un fill d'un dels nostres.
        #expect(esDubte(tria(processos(), context(nostres: [50]))))
    }

    /// El pid reutilitzat (una altra hora d'inici o un altre pare), o un fill nou abans d'acabar-lo: `encaraEs` fals, i
    /// l'obridor no hi envia res.
    @Test func elPidReutilitzatNoEsTanca() throws {
        let p = processos()
        guard case let .acaba(candidat) = tria(p) else {
            Issue.record("hi havia d'haver un candidat")
            return
        }
        var reutilitzat = p
        reutilitzat.inicis[102] = hora(40)
        #expect(!candidat.encaraEs(reutilitzat))
        var altrePare = p
        altrePare.processos[102]?.pare = 1
        #expect(!candidat.encaraEs(altrePare))
        var ambFill = p
        ambFill.processos[300] = (InfoProces(executable: "/usr/bin/vim", argv: ["vim"]), 102)
        #expect(!candidat.encaraEs(ambFill))
        var acabat = p
        acabat.processos[102] = nil
        #expect(!candidat.encaraEs(acabat))
        var altraCarpeta = p
        altraCarpeta.carpetes[102] = "/x/altra"
        #expect(!candidat.encaraEs(altraCarpeta))
    }

    /// Warp ja era obert abans de demanar l'URL (l'app de Warp va arrencar abans): no l'ha engegat l'app, i no es toca res.
    @Test func warpJaObertNoEsTanca() {
        #expect(esDubte(tria(processos(warpA: -60, shellWarp: -59))))
        // Ni amb dues apps de Warp, o sense saber-ne l'hora.
        var dues = processos()
        dues.processos[41] = (InfoProces(executable: warp, argv: [warp]), 1)
        dues.inicis[41] = hora(1)
        #expect(esDubte(tria(dues)))
        var senseHora = processos()
        senseHora.inicis[40] = nil
        #expect(esDubte(tria(senseHora)))
    }

    /// Un shell començat massa tard (després de la confirmació i dels 10 s d'arrencada) pot ser una pestanya nova feta a mà:
    /// res. Un d'abans que arrenqués Warp, tampoc. Sense confirmació, els 10 s compten.
    @Test func elShellHaDeComencarEnArrencarWarp() {
        #expect(esDubte(tria(processos(shellWarp: 20))))
        #expect(esDubte(tria(processos(shellWarp: 0.5))))
        let als9 = FinestraDeWarp.Decisio.acaba(FinestraDeWarp.Candidat(pid: 102, pare: 50, inici: hora(9), carpeta: inici))
        #expect(tria(processos(shellWarp: 9)) == als9 && tria(processos(shellWarp: 9), context(confirmada: nil)) == als9)
        #expect(!esDubte(tria(processos(shellWarp: 25), context(confirmada: t0 + 30))), "abans de la confirmació, encara que tard")
    }

    /// Tants terminals com pestanyes: Warp no n'ha obert cap de seu, i no hi ha res a dir. Un dubte del context: ni es miren
    /// els processos.
    @Test func capFinestraIDubteDelContext() {
        var sense = processos()
        sense.processos[102] = nil
        #expect(tria(sense) == .no(.capFinestra))
        #expect(FinestraDeWarp.text(.capFinestra) == nil)
        var llegida = false
        let r = FinestraDeWarp.tanca(context(dubte: "x"), foto: {
            llegida = true
            return processos().fotoFinestraDeWarp(executable: warp)
        }, shellUsuari: nil, acaba: { _ in
            Issue.record("no s'havia d'acabar res")
            return .capFinestra
        })
        #expect(r == .dubte("x") && !llegida)
        #expect(FinestraDeWarp.text(r) == "Warp ha obert també una finestra seva, que pots tancar.")
    }

    /// El context de l'acció: les pestanyes demanades, els shells reconeguts de totes les finestres, l'hora de la
    /// confirmació de la primera, i els dubtes (la primera no s'ha obert, o alguna pestanya és a l'inici).
    @Test func elContextDeLAccio() {
        let t1 = pestanya(1, carpeta: "/x/t1", claude: true)
        let t2 = pestanya(2, carpeta: "/x/t2", claude: false)
        let t3 = pestanya(3, carpeta: "/x/t3", claude: false)
        let vist = Confirmacio(finestra: nil, panes: [:], sessions: [:], perCarpeta: [id(2): 602],
                               shells: [id(3): ShellRecordat(pid: 603, inici: hora(3))])
        let c = FinestraDeWarp.context([([t1, t2], acabat([t1, t2], vist: vist)), ([t3], acabat([t3], vist: vist)),
                                        ([t1], acabat([t1], estat: .error, segons: nil)), ([t2], nil)], inici: inici)
        #expect(c == FinestraDeWarp.Context(inici: inici, desDe: t0, confirmada: t0 + 1.2, nostres: [602, 603], pestanyes: 3))
        // La primera, sense confirmar: cap hora de confirmació (compten els 10 s de Warp).
        #expect(FinestraDeWarp.context([([t1], acabat([t1], finestra: false))], inici: inici).confirmada == nil)
        // La primera no s'ha obert, o no s'ha intentat: dubte.
        #expect(FinestraDeWarp.context([([t1], acabat([t1], estat: .error, segons: nil))], inici: inici).dubte != nil)
        #expect(FinestraDeWarp.context([([t1], ExecucioObertura.Resultat.noEsPot("x"))], inici: inici).dubte != nil)
        #expect(FinestraDeWarp.context([([t1], nil)], inici: inici).dubte != nil)
        // Una pestanya de l'app a l'inici (de qualsevol finestra): seria igual que la de Warp.
        let aLInici = pestanya(4, carpeta: inici, claude: false)
        #expect(FinestraDeWarp.context([([t1], acabat([t1])), ([aLInici], acabat([aLInici]))], inici: inici).dubte != nil)
        #expect(FinestraDeWarp.context([([t1], acabat([t1]))], inici: inici).dubte == nil)
    }
}
