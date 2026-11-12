import Foundation
import Testing
@testable import WarpLaunchCore

// F6 (docs/disseny.md, secció 12): una pseudollengua feta del català, per trobar els trossos de frase que no passen per `t(_:)`.
// Cada text hi és entre ⟦…⟧, un 40 % més llarg, i amb totes les lletres i els signes de puntuació canviats per uns altres que s'hi
// assemblen («Obre a Warp…» és «⟦Öƀŕé à Ŵàŕƥ…·····⟧»). Els valors (`%@`, `%lld`) no es toquen. Amb aquesta llengua (`Idioma.
// textosDeProva`), el que componen les funcions del Core no ha de tenir cap lletra llatina ni cap «,», «;», «:», «(», «)», ««» o
// «»» que no vingui d'un valor de la prova o d'un nom que no es tradueix: tot el que no passa per `t(_:)` es veu.

private let arrel = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite struct PseudollenguaTests {
    // MARK: - La pseudollengua

    /// Les lletres i els signes, amb uns altres que s'hi assemblen; la resta (xifres, espais, « · », «›»), igual.
    static let canvis: [Character: Character] = {
        let de = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ,;:()«»“”'’.")
        let a = Array("àƀçđéƒĝĥïĵķļɱñöƥʠŕšţüʋŵẋÿžÀƁÇĐÉƑĜĤÏĴĶĻṀÑÖƤɊŔŠŢÜṼŴẊŸŽ‚⁏꞉⁽⁾‹›„‟‛ʼ․")
        precondition(de.count == a.count)
        return Dictionary(uniqueKeysWithValues: zip(de, a))
    }()

    /// Un especificador de format (`%@`, `%lld`, `%2$@`, `%%`, `%#@p@`), que es deixa tal com és.
    static var especificador: Regex<AnyRegexOutput> { try! Regex(#"%(?:#@[A-Za-z0-9_]+@|(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|hh|h|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA%])"#) }

    /// Un text del català, en la pseudollengua.
    static func pseudo(_ text: String) -> String {
        var resultat = "", resta = text[...]
        while let trobat = resta.firstMatch(of: especificador) {
            resultat += String(resta[..<trobat.range.lowerBound].map { canvis[$0] ?? $0 })
            resultat += String(resta[trobat.range])
            resta = resta[trobat.range.upperBound...]
        }
        resultat += String(resta.map { canvis[$0] ?? $0 })
        return "⟦" + resultat + String(repeating: "·", count: (text.count * 2 + 4) / 5) + "⟧"
    }

    /// Els textos del català, en la pseudollengua: un paquet de textos temporal, amb la carpeta `xx.lproj`.
    static func textos() throws -> Textos {
        let catala = arrel.appending(path: "Sources/WarpLaunchCore/Textos/ca.lproj")
        let strings = try #require(PropertyListSerialization.propertyList(
            from: Data(contentsOf: catala.appending(path: "Localizable.strings")), format: nil) as? [String: String])
        let plurals = try #require(PropertyListSerialization.propertyList(
            from: Data(contentsOf: catala.appending(path: "Localizable.stringsdict")), format: nil) as? [String: [String: Any]])
        let paquet = try CarpetaTemporal().url("Pseudo.bundle")
        let lproj = paquet.appending(path: "xx.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: strings.mapValues(pseudo), format: .xml, options: 0)
            .write(to: lproj.appending(path: "Localizable.strings"))
        let pseudoPlurals = plurals.mapValues { entrada in
            entrada.mapValues { valor -> Any in
                if let format = valor as? String { return pseudo(format) }
                guard let formes = valor as? [String: String] else { return valor }
                return formes.reduce(into: [String: String]()) { res, forma in
                    res[forma.key] = forma.key.hasPrefix("NSString") ? forma.value : pseudo(forma.value)
                }
            }
        }
        try PropertyListSerialization.data(fromPropertyList: pseudoPlurals, format: .xml, options: 0)
            .write(to: lproj.appending(path: "Localizable.stringsdict"))
        return try #require(Textos(bundle: paquet))
    }

    /// En la pseudollengua. Les llistes, amb les del japonès («、»), que no fan servir cap lletra ni cap signe llatí.
    static func enPseudo<T>(_ textos: Textos, _ cos: () throws -> T) rethrows -> T {
        try Idioma.$textosDeProva.withValue(.init(textos: textos, llengua: "xx", locale: Locale(identifier: "ja")), operation: cos)
    }

    /// El que no ha passat per `t(_:)`: les lletres llatines i els signes de puntuació que queden, sense els `permesos`.
    static func foraDeT(_ text: String, permesos: [String] = []) -> String? {
        var resta = text
        for permes in permesos.sorted(by: { $0.count > $1.count }) { resta = resta.replacingOccurrences(of: permes, with: "") }
        let dolents = resta.filter { $0.isASCII && $0.isLetter || ",;:()«»“”".contains($0) }
        return dolents.isEmpty && text.contains("⟦") ? nil : "«\(text)» porta «\(dolents)» fora de t()"
    }

    // MARK: - Proves

    @Test func laPseudollenguaDeixaElsValorsIEsMesLlarga() throws {
        #expect(Self.pseudo("Obre a Warp…") == "⟦Öƀŕé à Ŵàŕƥ…·····⟧")
        #expect(Self.pseudo("%lld amb Claude (%@)") == "⟦%lld àɱƀ Çļàüđé ⁽%@⁾········⟧")
        #expect(Self.pseudo("%2$@ i %1$@: 100%%") == "⟦%2$@ ï %1$@꞉ 100%%········⟧")
        let textos = try Self.textos()
        Self.enPseudo(textos) {
            #expect(Idioma.efectiva == "xx")
            #expect(t("Obre a Warp…") == "⟦Öƀŕé à Ŵàŕƥ…·····⟧")
            #expect(t("\(3) finestres").contains("3 ƒïñéšţŕéš"))
            #expect(Idioma.llista(["1", "2"]) == "1、2")
        }
        // Fora del bloc, el català de sempre.
        #expect(t("Obre a Warp…") == "Obre a Warp…")
    }

    /// La guarda funciona: un tros enganxat al codi es veu, i un text sencer, no.
    @Test func esVeuElQueNoPassaPerT() throws {
        let textos = try Self.textos()
        Self.enPseudo(textos) {
            #expect(Self.foraDeT(t("Obre a Warp…")) == nil)
            #expect(Self.foraDeT(t("Obre a Warp…") + ", " + t("Obre a Warp…")) != nil)
            #expect(Self.foraDeT(t("Obre a Warp…") + " (no)") != nil)
            #expect(Self.foraDeT("Claude", permesos: ["Claude"]) != nil)  // cap ⟦⟧: no ha passat per t()
            #expect(Self.foraDeT(t("Obre a Warp…") + " · " + t("Obre a Warp…")) == nil)
        }
    }

    /// Les frases del Core que es componen de diversos trossos o amb valors, en la pseudollengua: cap tros fora de `t(_:)`.
    @Test func lesFrasesDelCorePassenPerT() throws {
        let textos = try Self.textos()
        let pestanya = Pestanya(id: UUID(), titol: "7", carpeta: "/1/2", claude: ClaudePestanya())
        let lloc = "12 › 7"
        let modes = ClaudePestanya.modesPermisos
        let casos: [(String, () -> String, [String])] = [
            ("XifresObertura", { XifresObertura(pestanyes: 9, ambClaude: 6, reprenen: 4, terminal: 3, jaObertes: 14, excloses: 1).text }, []),
            ("XifresObertura, una", { XifresObertura(pestanyes: 1, ambClaude: 1, reprenen: 0, terminal: 0, jaObertes: 0, excloses: 0).text }, []),
            ("XifresObertura, res", { XifresObertura(pestanyes: 0, ambClaude: 0, reprenen: 0, terminal: 0, jaObertes: 2, excloses: 0).text }, []),
            ("ResumImportacio", { ResumImportacio(finestres: 4, pestanyes: 30, ambSessio: 6, senseClaude: 24, senseClaudeObert: 18,
                                                  saltenPermisos: 2).descripcio }, []),
            ("ResumImportacio, sense", { ResumImportacio(finestres: 1, pestanyes: 3, ambSessio: 0, senseClaude: 3, senseClaudeObert: 0,
                                                         saltenPermisos: 0).descripcio }, []),
            ("ResumWarp", { ResumWarp(finestres: 1, pestanyes: 2, sessionsClaude: 1).descripcio }, []),
            ("Finestra.resum", { Finestra(id: UUID(), nom: "12", pestanyes: [pestanya]).resum }, []),
            ("nomMode", { ClaudePestanya.nomMode("bypassPermissions") }, ["bypassPermissions"]),
            ("resum, sense Claude", { ClaudePestanya(activat: false).resum }, []),
            ("resum", { ClaudePestanya(model: "opus", esforc: "xhigh", ultracode: true).resum }, ["Opus", "Ultracode"]),
            ("AvisObertura", { AvisObertura(pestanya: pestanya, tipus: .potserJaOberta(lloc: lloc)).description }, []),
            ("AvisObertura, conversa", { AvisObertura(pestanya: pestanya, tipus: .conversaMesRecent(fa: 7200)).description }, []),
            ("AvisObertura, projectes", { AvisObertura(pestanya: nil, tipus: .conversaEnDiversosProjectes(["1", "2"])).description }, []),
            ("AvisObertura, sessions", { AvisObertura(pestanya: nil, tipus: .moltesSessions(12)).description }, []),
            ("OnOberta", { OnOberta.marca(lloc: lloc).description }, []),
            ("OnOberta, pane", { OnOberta.pane(lloc: lloc, ambClaude: false).description }, []),
            ("MotiuExclusio", { MotiuExclusio.ordre(.sessioBuida).description }, []),
            ("ConversaObertura", { ConversaObertura.repren("1234567890").descripcio }, []),
            ("NotaImportacio", { NotaImportacio.sessioSensePestanya(carpeta: "/1", nom: "2", dinsDeWarp: false,
                                                                  terminals: ["3", "4"]).description }, []),
            ("Avis, mode", { Avis(.modePermisosDesconegut("9")).description }, modes),
            ("Avis, opcions", { Avis(.opcionsDUnSolUs(["-1", "-2"])).description }, []),
            ("WarpPreview", { WarpPreview.obert.text }, []),
            ("LecturaWarp.senseFinestres", { LecturaWarp.senseFinestres }, []),
        ]
        var problemes: [String] = []
        Self.enPseudo(textos) {
            for (nom, text, permesos) in casos {
                if let problema = Self.foraDeT(text(), permesos: permesos) { problemes.append("\(nom): \(problema)") }
            }
        }
        #expect(problemes.isEmpty, "\(problemes.joined(separator: "\n"))")
    }
}
