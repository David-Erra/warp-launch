import Foundation

/// El pla d'obrir una finestra, per al CLI (`warp-launch obre`, D17): el que diria el full de confirmació, i el fitxer i
/// l'URL exactes. No escriu res.
enum InformeObertura {
    /// La capçalera del mode de prova. La primera línia de la sortida.
    static let modeDeProva = "Mode de prova: no s'ha escrit ni obert res."

    struct Dades {
        var pla: Pla
        /// La posició de la finestra a la configuració (1…) i quantes n'hi ha.
        var numero: Int
        var finestres: Int
        var configuracio: URL
        var warpObert: Bool?
        /// `nil` si no hi ha cap pestanya per obrir.
        var fitxer: FitxerLaunch?
        /// L'error del fitxer, si n'hi ha d'obrir però no es pot generar.
        var errorFitxer: String?
        var inici: String
        /// La primera línia: el mode de prova, o que s'obre de debò (`--obre`).
        var capcalera = InformeObertura.modeDeProva
    }

    static func text(_ d: Dades) -> String {
        var linies = [d.capcalera]
        let pla = d.pla
        linies.append("Finestra \(d.numero) de \(d.finestres): «\(pla.finestra.nom)» (\(d.configuracio.path))")
        switch d.warpObert {
        case true?: linies.append("Warp és obert.")
        case false?: linies.append("Warp és tancat: primer s'obriria Warp.")
        case nil: linies.append("No se sap si Warp és obert.")
        }
        linies.append(pla.xifres.text)
        if let motiu = pla.motiuEspera { linies.append("⏳ \(motiu)") }

        let posicio = Dictionary(uniqueKeysWithValues: pla.finestra.pestanyes.enumerated().map { ($1.id, $0 + 1) })
        func fila(_ pestanya: Pestanya, _ detall: String) -> String {
            let numero = String(posicio[pestanya.id] ?? 0)
            return String(repeating: " ", count: max(0, 4 - numero.count)) + numero
                + "  \(pestanya.titol) · \(Rutes.abreujada(pestanya.carpeta, inici: d.inici)) · \(detall)"
        }
        if !pla.obertes.isEmpty {
            linies.append("")
            linies.append("Ja obertes (\(pla.obertes.count)):")
            linies += pla.obertes.map { fila($0.pestanya, $0.on.description) }
        }
        if !pla.excloses.isEmpty {
            linies.append("")
            linies.append("No s'obriran (\(pla.excloses.count)):")
            linies += pla.excloses.map { fila($0.pestanya, "✗ \($0.motiu)") }
        }
        if !pla.aObrir.isEmpty {
            linies.append("")
            linies.append("S'obririen (\(pla.aObrir.count)):")
            linies += pla.aObrir.map { fila($0.pestanya, $0.conversa.descripcio) }
        }
        if !pla.avisos.isEmpty {
            linies.append("")
            linies.append("Avisos:")
            linies += pla.avisos.map { "  \($0.esInfo ? "·" : "⚠") \($0)" }
        }
        if let error = d.errorFitxer {
            linies.append("")
            linies.append("✗ No es pot generar el fitxer per a Warp: \(error)")
        }
        if let fitxer = d.fitxer {
            linies.append("")
            linies.append("Fitxer per a Warp: \(fitxer.nomFitxer) (en obrir de debò, l'id serà un altre)")
            linies.append("URL: \(fitxer.url)")
            linies.append("")
            linies.append(fitxer.text.hasSuffix("\n") ? String(fitxer.text.dropLast()) : fitxer.text)
        }
        return linies.map { $0 + "\n" }.joined()
    }

    // MARK: - JSON

    struct JSON: Encodable {
        struct Finestra: Encodable { var id: UUID, nom: String, numero: Int }
        struct Xifres: Encodable {
            var pestanyes, ambClaude, reprenen, noves, terminal, jaObertes, excloses: Int
            var memoriaGB: Double
        }
        struct Oberta: Encodable { var id: UUID, titol: String, carpeta: String, on: String }
        struct Exclosa: Encodable { var id: UUID, titol: String, carpeta: String, motiu: String }
        struct AObrir: Encodable {
            var id: UUID, titol: String, carpeta: String
            /// «terminal», «repren» o «nova».
            var conversa: String
            var repren: String?
            var argv: [String]?
            var exec: String?
        }
        struct AvisJSON: Encodable {
            var pestanya: UUID?
            var text: String
            var info: Bool
        }
        struct Fitxer: Encodable { var nom: String, url: String, text: String }

        var mode = "prova"
        var configuracio: String
        var finestra: Finestra
        var warpObert: Bool?
        var resum: String
        /// Per què encara no s'ha d'obrir (`Pla.motiuEspera`).
        var espera: String?
        var xifres: Xifres
        var obertes: [Oberta]
        var excloses: [Exclosa]
        var aObrir: [AObrir]
        var avisos: [AvisJSON]
        var fitxer: Fitxer?
        var errorFitxer: String?
    }

    static func json(_ d: Dades) throws -> Data {
        let pla = d.pla
        let x = pla.xifres
        let valor = JSON(
            configuracio: d.configuracio.path,
            finestra: .init(id: pla.finestra.id, nom: pla.finestra.nom, numero: d.numero),
            warpObert: d.warpObert, resum: x.text, espera: pla.motiuEspera,
            xifres: .init(pestanyes: x.pestanyes, ambClaude: x.ambClaude, reprenen: x.reprenen, noves: x.noves,
                          terminal: x.terminal, jaObertes: x.jaObertes, excloses: x.excloses, memoriaGB: x.memoriaGB),
            obertes: pla.obertes.map {
                .init(id: $0.pestanya.id, titol: $0.pestanya.titol, carpeta: $0.pestanya.carpeta, on: $0.on.description)
            },
            excloses: pla.excloses.map {
                .init(id: $0.pestanya.id, titol: $0.pestanya.titol, carpeta: $0.pestanya.carpeta,
                      motiu: $0.motiu.description)
            },
            aObrir: pla.aObrir.map { p in
                let tipus = switch p.conversa {
                case .terminal: "terminal"
                case .repren: "repren"
                case .nova: "nova"
                }
                return .init(id: p.pestanya.id, titol: p.pestanya.titol, carpeta: p.pestanya.carpeta, conversa: tipus,
                             repren: p.conversa.repren, argv: p.argv, exec: p.yaml.exec)
            },
            avisos: pla.avisos.map { .init(pestanya: $0.pestanya?.id, text: $0.description, info: $0.esInfo) },
            fitxer: d.fitxer.map { .init(nom: $0.nomFitxer, url: $0.url.description, text: $0.text) },
            errorFitxer: d.errorFitxer)
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try codificador.encode(valor)
    }
}
