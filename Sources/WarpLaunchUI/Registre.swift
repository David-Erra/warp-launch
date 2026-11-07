import Foundation
import os

/// El registre de l'app (Console, subsistema `cat.davide.warp-launch`), per entendre el que no es pot provar sense
/// obrir-la, com arrossegar. Només hi van identificadors curts i xifres: cap nom, carpeta ni ordre.
/// - Deixar anar va a `.notice`, que es desa: després de la prova,
///   `/usr/bin/log show --last 10m --predicate 'subsystem == "cat.davide.warp-launch"'`.
/// - Cada moviment del ratolí va a `.debug`, que no es desa: només es veu en directe, amb l'ordre oberta abans,
///   `/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "cat.davide.warp-launch"'`.
/// - Amb les eines de Claude, `log` sol és l'ordre de zsh: cal `/usr/bin/log`.
enum Registre {
    static let arrossegar = Logger(subsystem: "cat.davide.warp-launch", category: "arrossegar")
    /// Obrir una finestra a Warp (fase 3.1): els passos, els temps i les xifres, a `.notice`.
    static let obertura = Logger(subsystem: "cat.davide.warp-launch", category: "obertura")
    /// «Lliga amb Warp…»: la proposta i quantes s'han lligat, a `.notice`.
    static let lligam = Logger(subsystem: "cat.davide.warp-launch", category: "lligam")
    /// L'ajust de la restauració de sessió de Warp i la foto de les finestres (D19).
    static let refresc = Logger(subsystem: "cat.davide.warp-launch", category: "refresc")
    /// El consentiment per gestionar la restauració de Warp (D-P4): si s'accepta, i els errors de `preferencies.json`.
    static let consentiment = Logger(subsystem: "cat.davide.warp-launch", category: "consentiment")

    /// Els 8 primers caràcters d'un id: prou per distingir les finestres d'una prova.
    static func curt(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}
