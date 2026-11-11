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
        let historial = panes.filter { $0.origenCarpeta == .historial }.count
        let noExisteixen = panes.filter { !$0.carpetaExisteix }.count
        let aInici = panes.filter { $0.carpeta == iniciCanonic }.count
        let foraDeWarp = lectura.sessionsSensePestanya.filter { !$0.dinsDeWarp }.count
        var linies = desaFinestres ? [
            t("Warp: \(lectura.finestres.count) finestres, \(pestanyes.count) pestanyes de terminal, \(ambClaude) amb Claude. Sessions de Claude fora de cap pestanya: \(lectura.sessionsSensePestanya.count)."),
            t("Carpetes: \(historial) recuperades de l'historial, \(noExisteixen) que ja no existeixen, \(aInici) a la carpeta d'inici (~)."),
        ] : [
            t("Warp: \(lectura.terminals.count) terminals vius, \(lectura.terminals.filter(\.claude).count) amb Claude. Sessions de Claude fora de Warp: \(foraDeWarp)."),
            t("La restauració de sessió és desactivada: Warp no desa les finestres, i l'app llegeix els processos."),
        ]
        switch lectura.warpObert {
        case true?: linies.append(t("Warp és obert."))
        case false?: linies.append(desaFinestres ? t("Warp és tancat: són les finestres que restaurarà en obrir-se.")
                                                 : t("Warp és tancat."))
        case nil: break
        }
        if let preview = lectura.warpPreview { linies.append("⚠ \(preview.text)") }
        if !lectura.sessionsNoInteractives.isEmpty {
            let tipus = Set(lectura.sessionsNoInteractives.map(\.tipus)).sorted().joined(separator: ", ")
            linies.append(t("Sessions de Claude en segon pla: \(lectura.sessionsNoInteractives.count) (\(tipus))."))
        }

        if !desaFinestres, !lectura.terminals.isEmpty {
            linies.append("")
            linies.append(t("Terminals:"))
            for terminal in lectura.terminals {
                let detalls = [terminal.claude ? "Claude" : t("sense Claude"),
                               terminal.marca.map { t("pestanya \($0.uuidString.prefix(8).lowercased())") },
                               terminal.pane.map { t("pane \(String($0.prefix(8)))") }].compactMap { $0 }
                linies.append("  · \(terminal.carpeta.map(carpeta) ?? "?") · pid \(terminal.pid) · "
                    + detalls.joined(separator: " · "))
            }
        }

        for finestra in lectura.finestres {
            linies.append("")
            linies.append(t("Finestra \(String(finestra.numero)) · \(finestra.pestanyes.count) pestanyes"))
            for pestanya in finestra.pestanyes {
                let activa = pestanya.posicio == finestra.pestanyaActiva ? "*" : " "
                let numero = String(pestanya.posicio + 1).leftPadding(3)
                let titol = pestanya.titol.flatMap { $0.isEmpty ? nil : $0 } ?? t("(sense títol)")
                for (n, pane) in pestanya.panes.enumerated() {
                    let marques = [pane.origenCarpeta == .historial ? t("historial") : nil,
                                   pane.carpetaExisteix ? nil : t("no existeix")].compactMap { $0 }
                    let notes = marques.isEmpty ? "" : " (" + marques.joined(separator: ", ") + ")"
                    let capcalera = n == 0 ? "\(numero)\(activa) \(titol)" : "     └ " + t("pane \(String(n + 1))")
                    linies.append("\(capcalera) · \(carpeta(pane.carpeta))\(notes)")
                    if let claude = pane.claude {
                        linies.append("       \(ordre(claude.ordre))  [\(descripcio(claude))]")
                    }
                }
            }
        }

        if !lectura.sessionsSensePestanya.isEmpty {
            linies.append("")
            linies.append(desaFinestres ? t("Sessions de Claude que no són a cap pestanya de Warp:") : t("Sessions de Claude:"))
            for sessio in lectura.sessionsSensePestanya {
                let motiu = !sessio.dinsDeWarp ? t("fora de Warp") : desaFinestres ? t("pestanya no trobada a la base de Warp") : t("a Warp")
                linies.append("  · \(ordre(sessio.ordre)) · \(carpeta(sessio.carpeta))  [\(descripcio(sessio)) · \(motiu)]")
            }
        }

        if !lectura.avisos.isEmpty {
            linies.append("")
            linies.append(t("Avisos:"))
            linies.append(contentsOf: lectura.avisos.map { "  · \($0)" })
        }
        return linies.joined(separator: "\n")
    }

    /// `nom · pid · estat`, i la marca de la pestanya que la va obrir (els 8 primers caràcters), si en té.
    private static func descripcio(_ sessio: SessioClaude) -> String {
        let marca = sessio.marca.map { t("pestanya \($0.uuidString.prefix(8).lowercased())") }
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
