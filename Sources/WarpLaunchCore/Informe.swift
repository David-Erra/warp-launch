import Foundation

/// Text llegible de la lectura, per a `warp-launch llegeix`.
public enum Informe {
    public static func text(_ lectura: LecturaWarp, inici: String) -> String {
        let iniciCanonic = Rutes.canonica(inici)
        func carpeta(_ ruta: String) -> String { Rutes.abreujada(ruta, inici: iniciCanonic) }

        let pestanyes = lectura.finestres.flatMap(\.pestanyes)
        let panes = pestanyes.flatMap(\.panes)
        let ambClaude = panes.filter { $0.claude != nil }.count
        let desaFinestres = lectura.warpDesaFinestres != false
        var linies = desaFinestres ? [
            "Warp: \(lectura.finestres.count) finestres, \(pestanyes.count) pestanyes de terminal, "
                + "\(ambClaude) amb Claude. Sessions de Claude fora de cap pestanya: \(lectura.sessionsSensePestanya.count).",
            "Carpetes: \(panes.filter { $0.origenCarpeta == .historial }.count) recuperades de l'historial, "
                + "\(panes.filter { !$0.carpetaExisteix }.count) que ja no existeixen, "
                + "\(panes.filter { $0.carpeta == iniciCanonic }.count) a la carpeta d'inici (~).",
        ] : [
            "Warp: \(Plural.compta(lectura.terminals.count, "terminal viu", "terminals vius")), "
                + "\(lectura.terminals.filter(\.claude).count) amb Claude. "
                + "Sessions de Claude fora de Warp: \(lectura.sessionsSensePestanya.filter { !$0.dinsDeWarp }.count).",
            "La restauració de sessió és desactivada: Warp no desa les finestres, i l'app llegeix els processos.",
        ]
        switch lectura.warpObert {
        case true?: linies.append("Warp és obert.")
        case false?: linies.append(desaFinestres ? "Warp és tancat: són les finestres que restaurarà en obrir-se."
                                                 : "Warp és tancat.")
        case nil: break
        }
        if let preview = lectura.warpPreview { linies.append("⚠ \(preview.text)") }
        if !lectura.sessionsNoInteractives.isEmpty {
            let tipus = Set(lectura.sessionsNoInteractives.map(\.tipus)).sorted().joined(separator: ", ")
            linies.append("Sessions de Claude en segon pla: \(lectura.sessionsNoInteractives.count) (\(tipus)).")
        }

        if !desaFinestres, !lectura.terminals.isEmpty {
            linies.append("")
            linies.append("Terminals:")
            for terminal in lectura.terminals {
                let detalls = [terminal.claude ? "Claude" : "sense Claude",
                               terminal.marca.map { "pestanya \($0.uuidString.prefix(8).lowercased())" },
                               terminal.pane.map { "pane \($0.prefix(8))" }].compactMap { $0 }
                linies.append("  · \(terminal.carpeta.map(carpeta) ?? "?") · pid \(terminal.pid) · "
                    + detalls.joined(separator: " · "))
            }
        }

        for finestra in lectura.finestres {
            linies.append("")
            linies.append("Finestra \(finestra.numero) · \(finestra.pestanyes.count) pestanyes")
            for pestanya in finestra.pestanyes {
                let activa = pestanya.posicio == finestra.pestanyaActiva ? "*" : " "
                let numero = String(pestanya.posicio + 1).leftPadding(3)
                let titol = pestanya.titol.flatMap { $0.isEmpty ? nil : $0 } ?? "(sense títol)"
                for (n, pane) in pestanya.panes.enumerated() {
                    let marques = [pane.origenCarpeta == .historial ? "historial" : nil,
                                   pane.carpetaExisteix ? nil : "no existeix"].compactMap { $0 }
                    let notes = marques.isEmpty ? "" : " (" + marques.joined(separator: ", ") + ")"
                    let capcalera = n == 0 ? "\(numero)\(activa) \(titol)" : "     └ pane \(n + 1)"
                    linies.append("\(capcalera) · \(carpeta(pane.carpeta))\(notes)")
                    if let claude = pane.claude {
                        linies.append("       \(ordre(claude.ordre))  [\(descripcio(claude))]")
                    }
                }
            }
        }

        if !lectura.sessionsSensePestanya.isEmpty {
            linies.append("")
            linies.append(desaFinestres ? "Sessions de Claude que no són a cap pestanya de Warp:" : "Sessions de Claude:")
            for sessio in lectura.sessionsSensePestanya {
                let motiu = !sessio.dinsDeWarp ? "fora de Warp" : desaFinestres ? "pestanya no trobada a la base de Warp" : "a Warp"
                linies.append("  · \(ordre(sessio.ordre)) · \(carpeta(sessio.carpeta))  [\(descripcio(sessio)) · \(motiu)]")
            }
        }

        if !lectura.avisos.isEmpty {
            linies.append("")
            linies.append("Avisos:")
            linies.append(contentsOf: lectura.avisos.map { "  · \($0)" })
        }
        return linies.joined(separator: "\n")
    }

    /// `nom · pid · estat`, i la marca de la pestanya que la va obrir (els 8 primers caràcters), si en té.
    private static func descripcio(_ sessio: SessioClaude) -> String {
        let marca = sessio.marca.map { "pestanya \($0.uuidString.prefix(8).lowercased())" }
        return [sessio.nom, "pid \(sessio.pid)", sessio.estat, marca].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ordre per mostrar, amb cometes on calen i `claude` en lloc de la ruta de l'executable.
    public static func ordre(_ argv: [String]) -> String {
        guard let primer = argv.first else { return "" }
        return ([(primer as NSString).lastPathComponent] + argv.dropFirst().map(cometes)).joined(separator: " ")
    }

    /// Cometes simples si calen perquè zsh o sh llegeixin l'argument tal com és. Un `=` al començament també en
    /// porta: zsh hi fa l'expansió `=ordre` (`=ls` es convertiria en `/bin/ls`).
    static func cometes(_ arg: String) -> String {
        let segurs = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !arg.isEmpty, !arg.hasPrefix("="), arg.unicodeScalars.allSatisfy(segurs.contains) { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    func leftPadding(_ amplada: Int) -> String {
        count >= amplada ? self : String(repeating: " ", count: amplada - count) + self
    }
}
