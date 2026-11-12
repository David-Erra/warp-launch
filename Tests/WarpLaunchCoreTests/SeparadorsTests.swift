import Testing
@testable import WarpLaunchCore

// F6 (docs/disseny.md, secció 12): les comes, els parèntesis, el punt i coma i l'espai entre frases que ajunten textos traduïts
// són els de cada llengua, i no uns de fixos al codi. Els separadors visuals (« · ») es queden: macOS els fa servir igual en
// totes les llengües.

@Suite struct SeparadorsTests {
    /// «6 amb Claude (4 reprenen la seva conversa, 2 en comencen una de nova)»: la coma és dins de la frase, i en japonès i en
    /// xinès és la seva (abans, `", "` al codi).
    @Test func lesDuesXifresDeClaudeAmbLaComaDeLaLlengua() {
        let dues = XifresObertura(pestanyes: 9, ambClaude: 6, reprenen: 4, terminal: 3, jaObertes: 0, excloses: 0)
        #expect(dues.text.contains("6 amb Claude (4 reprenen la seva conversa, 2 en comencen una de nova) i 3 només terminal"))
        Idioma.$deProva.withValue("ja") {
            #expect(dues.text.contains("Claudeあり6個（4個が会話を再開、2個が新しい会話を開始）"), "\(dues.text)")
            #expect(!dues.text.contains(", "), "\(dues.text)")
        }
        Idioma.$deProva.withValue("zh-Hans") {
            #expect(dues.text.contains("6个带Claude（4个恢复其对话，2个开始新对话）"), "\(dues.text)")
        }
        Idioma.$deProva.withValue("en") {
            #expect(dues.text.contains("6 with Claude (4 resume their conversation, 2 start a new one)"))
        }
        // Amb una sola xifra, sense coma; i el plural de cada una.
        let reprenen = XifresObertura(pestanyes: 1, ambClaude: 1, reprenen: 1, terminal: 0, jaObertes: 0, excloses: 0)
        #expect(reprenen.text.contains("1 amb Claude (1 reprèn la seva conversa)"))
        let noves = XifresObertura(pestanyes: 2, ambClaude: 2, reprenen: 0, terminal: 0, jaObertes: 0, excloses: 0)
        #expect(noves.text.contains("2 amb Claude (2 en comencen una de nova)"))
        let una = XifresObertura(pestanyes: 2, ambClaude: 2, reprenen: 1, terminal: 0, jaObertes: 0, excloses: 0)
        #expect(una.text.contains("2 amb Claude (1 reprèn la seva conversa, 1 en comença una de nova)"))
    }

    /// El nom d'un mode de permisos, amb el de Claude entre els parèntesis de la llengua.
    @Test func elNomDelModeAmbElsParentesisDeLaLlengua() {
        #expect(ClaudePestanya.nomMode("bypassPermissions") == "Sense cap permís (bypassPermissions)")
        #expect(ClaudePestanya.nomMode("yolo") == "yolo")
        Idioma.$deProva.withValue("ja") { #expect(ClaudePestanya.nomMode("bypassPermissions") == "権限をバイパス（bypassPermissions）") }
        Idioma.$deProva.withValue("zh-Hans") { #expect(ClaudePestanya.nomMode("plan") == "计划（plan）") }
        Idioma.$deProva.withValue("ko") { #expect(ClaudePestanya.nomMode("plan") == "계획(plan)") }
        Idioma.$deProva.withValue("en") { #expect(ClaudePestanya.nomMode("plan") == "Plan (plan)") }
    }

    /// Dues frases seguides: amb un espai, excepte en japonès i en xinès.
    @Test func lesFrasesSenseEspaiEnJaponesIEnXines() {
        #expect(Idioma.frases("A.", "B.") == "A. B.")
        #expect(Idioma.frases("A.", "", "B.") == "A. B.")
        #expect(Idioma.frases("A.") == "A.")
        Idioma.$deProva.withValue("ja") { #expect(Idioma.frases("A。", "B。") == "A。B。") }
        Idioma.$deProva.withValue("zh-Hans") { #expect(Idioma.frases("A。", "B。") == "A。B。") }
        Idioma.$deProva.withValue("ko") { #expect(Idioma.frases("A.", "B.") == "A. B.") }
        // Un text de debò: Warp Preview, sense Warp Stable.
        Idioma.$deProva.withValue("ja") {
            #expect(!WarpPreview.nomesPreview.text.contains("。 "), "\(WarpPreview.nomesPreview.text)")
        }
        #expect(WarpPreview.nomesPreview.text.hasSuffix(". En aquest Mac només hi ha Warp Preview."))
    }

    /// Una sessió sense pestanya amb terminals a la mateixa carpeta: la llista, amb la conjunció de la llengua, i el punt i coma,
    /// dins de la frase (en francès, amb l'espai no separable de macOS; en japonès, «。»).
    @Test func elsTerminalsDeLaMateixaCarpeta() {
        let nota = NotaImportacio.sessioSensePestanya(carpeta: "/a", nom: nil, dinsDeWarp: true, terminals: ["A", "B"])
        #expect(nota.description == "sessió de Claude a «/a»: no s'importa (la seva pestanya no és a la base de Warp); a la "
            + "mateixa carpeta hi ha «A» i «B», que queden només terminal")
        Idioma.$deProva.withValue("en") {
            #expect(nota.description.hasSuffix("); the same folder has “A” and “B”, which stay terminal only"))
        }
        Idioma.$deProva.withValue("fr") { #expect(nota.description.contains(")\u{00A0}; le même dossier contient"), "\(nota.description)") }
        Idioma.$deProva.withValue("ja") {
            #expect(nota.description.contains("）。同じフォルダに"), "\(nota.description)")
            #expect(!nota.description.contains(", "), "\(nota.description)")
        }
    }

    /// «3 només terminal (1 sense Claude obert)», en una frase: en japonès, sense l'espai d'abans del parèntesi.
    @Test func elResumDeLaImportacio() {
        let resum = ResumImportacio(finestres: 1, pestanyes: 3, ambSessio: 0, senseClaude: 3, senseClaudeObert: 1, saltenPermisos: 0)
        #expect(resum.descripcio == "1 finestra · 3 pestanyes · 0 amb Claude · 3 només terminal (1 sense Claude obert)")
        let sense = ResumImportacio(finestres: 1, pestanyes: 3, ambSessio: 0, senseClaude: 3, senseClaudeObert: 0, saltenPermisos: 0)
        #expect(sense.descripcio == "1 finestra · 3 pestanyes · 0 amb Claude · 3 només terminal")
        Idioma.$deProva.withValue("ja") {
            #expect(resum.descripcio.hasSuffix("ターミナルのみ3個（Claudeが開いていなかったもの1個）"), "\(resum.descripcio)")
        }
    }

    /// Les opcions que Claude no coneix i els modes que existeixen, amb la conjunció de la llengua.
    @Test func lesLlistesDeLaValidacio() {
        let mode = Avis(.modePermisosDesconegut("yolo"))
        #expect(mode.description.hasSuffix("(acceptEdits, auto, bypassPermissions, manual, dontAsk i plan)"))
        Idioma.$deProva.withValue("ja") { #expect(mode.description.contains("dontAsk、plan"), "\(mode.description)") }
        let opcions = Avis(.opcionsDUnSolUs(["--fork-session", "--from-pr"]))
        #expect(opcions.description.hasPrefix("«--fork-session» i «--from-pr» "), "\(opcions.description)")
    }
}
