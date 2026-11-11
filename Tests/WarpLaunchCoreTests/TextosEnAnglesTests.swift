import Foundation
import Testing
@testable import WarpLaunchCore

// Els textos del Core en anglès (fase F2, docs/disseny.md, secció 12): una mostra de cada mena (un error, un avís amb plural,
// un text amb un pid, l'ajuda del CLI), amb `Idioma.$deProva`. La resta de proves els miren en català. La sortida d'ordres del
// CLI en anglès és a `OrdreCLITests` (`elPlaDObrirEnAngles`, `validaEnAngles`).

@Suite struct TextosEnAnglesTests {
    /// Un error amb valors: la versió del format surt com a text, sense separador de milers.
    @Test func unError() {
        let error = ErrorConfiguracio.versioMesNova(1000)
        #expect(error.description == "el fitxer és de la versió 1000 del format, i aquesta app només entén fins a la "
            + "\(Configuracio.versioActual): cal una versió més nova de Warp Launch")
        Idioma.$deProva.withValue("en") {
            #expect(error.description == "the file is in version 1000 of the format, and this app only understands up to "
                + "version \(Configuracio.versioActual): a newer version of Warp Launch is needed")
            #expect(ErrorLectura.macOSNoDeixaLlegir.description
                == "macOS doesn't let Warp Launch read Warp's data; give it permission in System Settings › Privacy & Security")
            #expect(MotiuExclusio.carpetaNoExisteix.description == "the folder doesn't exist")
        }
    }

    /// Un avís amb plural, en les dues llengües: el singular i el plural surten del `.stringsdict`, i les parts de la frase
    /// s'uneixen amb la conjunció i el separador decimal de la llengua.
    @Test func unAvisAmbPlural() {
        let una = XifresObertura(pestanyes: 1, ambClaude: 1, reprenen: 1, terminal: 0, jaObertes: 0, excloses: 0)
        let moltes = XifresObertura(pestanyes: 9, ambClaude: 6, reprenen: 4, terminal: 3, jaObertes: 14, excloses: 1)
        #expect(una.text == "S'obrirà 1 finestra nova de Warp amb 1 pestanya: 1 amb Claude (1 reprèn la seva conversa) · unes 0,5 GB")
        #expect(moltes.text == "S'obrirà 1 finestra nova de Warp amb 9 pestanyes: 6 amb Claude (4 reprenen la seva conversa, "
            + "2 en comencen una de nova) i 3 només terminal · unes 3 GB · ja obertes: 14 · no s'obriran: 1")
        Idioma.$deProva.withValue("en") {
            #expect(una.text == "1 new Warp window will open with 1 tab: 1 with Claude (1 resumes its conversation) · about 0.5 GB")
            #expect(moltes.text == "1 new Warp window will open with 9 tabs: 6 with Claude (4 resume their conversation, "
                + "2 start a new one) and 3 terminal only · about 3 GB · already open: 14 · won't open: 1")
            #expect(AvisObertura(tipus: .moltesSessions(12)).description == "12 Claude sessions will start at once")
            #expect(ResumWarp(finestres: 1, pestanyes: 2, sessionsClaude: 1).descripcio
                == "Warp: 1 window · 2 tabs · 1 Claude session")
        }
    }

    /// Un text amb un pid: el pid surt tal com és (12345, no 12.345 ni 12,345), en català i en anglès.
    @Test func unTextAmbUnPid() throws {
        let tmp = try CarpetaTemporal()
        let sessions = tmp.url("sessions")
        try escriuSessio(a: sessions, pid: 12345, sessionId: "s-1", cwd: tmp.ruta)
        let lector = LectorSessions(carpeta: sessions, processos: ProcessosFalsos.ambWarp())
        #expect(lector.llegeixTotes().avisos == ["la sessió s-1 apunta al pid 12345, que ja no existeix"])
        Idioma.$deProva.withValue("en") {
            #expect(lector.llegeixTotes().avisos == ["session s-1 points to pid 12345, which no longer exists"])
        }
    }

    /// L'ajuda del CLI: el text es tradueix, i les ordres i les opcions no.
    @Test func lAjudaDelCLI() {
        let ajuda = Idioma.$deProva.withValue("en") { OrdreCLI.ajuda }
        let linies = ajuda.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(linies.prefix(5) == [
            "\(WarpLaunch.nom) \(WarpLaunch.versio)",
            "",
            "Usage:",
            "  warp-launch llegeix [--json] [--warp <warp.sqlite>] [--sessions <folder>]",
            "      Windows and tabs open in Warp, and the Claude session of each tab.",
        ])
        #expect(linies.contains("  warp-launch --versio"))
        #expect(linies.last == "64 incorrect usage.")
        // El mateix nombre d'ordres que en català, amb els mateixos noms.
        let ordres = { (text: String) in text.split(separator: "\n").filter { $0.hasPrefix("  warp-launch ") }
            .map { $0.split(separator: " ").prefix(2).joined(separator: " ") } }
        #expect(ordres(ajuda) == ordres(OrdreCLI.ajuda))
    }

    /// Una enumeració amb la conjunció de la llengua (`Idioma.llista`), com la feia el codi abans en català.
    @Test func unaLlista() {
        #expect(Idioma.llista([]) == "")
        #expect(Idioma.llista(["«A»"]) == "«A»")
        #expect(Idioma.llista(["«A»", "«B»"]) == "«A» i «B»")
        #expect(Idioma.llista(["«A»", "«B»", "«C»"]) == "«A», «B» i «C»")
        Idioma.$deProva.withValue("en") {
            #expect(Idioma.llista(["“A”", "“B”", "“C”"]) == "“A”, “B”, and “C”")
        }
    }

    /// F4: l'anglès, revisat. Els termes de macOS són els de macOS 15 i posteriors («Login Items & Extensions», a Configuració
    /// del Sistema; la llista, «login items»), l'app és «Settings», i un Claude que corre és una «Claude session». Els ítems de
    /// menú, els botons i les capçaleres, amb majúscules a cada paraula; les etiquetes i els interruptors, només la primera.
    @Test func elsTermesDeMacOSIElsDeLApp() {
        Idioma.$deProva.withValue("en") {
            #expect(t("Mostra Ítems d’inici de sessió i extensions…") == "Show Login Items & Extensions…")
            #expect(t("macOS no l'obrirà sola fins que la permetis a Ítems d’inici de sessió i extensions")
                == "macOS won't open it until you allow it in Login Items & Extensions")
            #expect(t("""
                Quan Warp és a punt, mostra «Obre-ho tot a Warp…» amb les finestres que falten. No obre res fins que hi fas \
                clic. També es desactiva a Configuració del Sistema › General › Ítems d’inici de sessió i extensions.
                """).hasSuffix("System Settings › General › Login Items & Extensions."))
            #expect(t("No s'ha pogut treure Warp Launch dels ítems d'inici de sessió: \("x"). No s'ha canviat res més.")
                == "Couldn't remove Warp Launch from your login items: x. Nothing else was changed.")
            #expect(t("Configuració…") == "Settings…")
            #expect(t("tots els Claude s'engegaran alhora") == "all Claude sessions will start at once")
            // Ítems de menú i botons.
            #expect(["Actualitza l'estat de Warp", "Obre-ho tot a Warp…", "Torna a importar-ho tot de Warp…", "Mostra el fitxer al Finder",
                     "Restaura Warp i surt…", "Comprova si hi ha actualitzacions…", "Comença en blanc"].map { t($0) }
                == ["Refresh Warp Status", "Open All in Warp…", "Re-import Everything from Warp…", "Show File in Finder",
                    "Restore Warp and Quit…", "Check for Updates…", "Start from Scratch"])
            // Etiquetes i interruptors.
            #expect(["Obre Warp Launch en iniciar sessió", "Actualitza automàticament", "Salta els permisos", "Mode de permisos",
                     "Idioma de l'app"].map { t($0) }
                == ["Open Warp Launch at login", "Update automatically", "Skip permissions", "Permission mode", "App language"])
        }
    }
}
