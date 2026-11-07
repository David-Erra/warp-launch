import Foundation
import WarpLaunchCore
import WarpLaunchObridor

// Comanda `warp-launch`. La lògica és a `OrdreCLI` (WarpLaunchCore), que es prova amb fixtures; aquí només hi ha els
// valors reals: Warp, les sessions de Claude i els processos del sistema, la carpeta d'inici, ~/.config/warp-launch,
// i, per a `obre`, les transcripcions i ~/.claude.json (només lectura). Amb `obre --obre` (D17), l'obridor i la carpeta
// de debò de Warp: l'única connexió del CLI amb `ObreWarp`.

let processos = ProcessosDelSistema()
let lector = Lector(processos: processos, warp: TrobaWarp.delSistema)
let entorn = EntornCLI(lector: lector, inici: lector.inici,
                       carpetaReal: Rutes.carpetaConfiguracio(inici: lector.inici),
                       transcripcions: LectorTranscripcions(), confianca: LectorConfianca())
// Ctrl-C a mig `obre --obre`: s'esborra el fitxer temporal (que no quedi a Warp, ⌃⌘L) i es desa el llançament.
var interrupcio: (@MainActor () -> Void)?
let senyal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
if CommandLine.arguments.contains("--obre") {
    signal(SIGINT, SIG_IGN)
    senyal.setEventHandler {
        MainActor.assumeIsolated {
            interrupcio?()
            FileHandle.standardError.write(Data("\nwarp-launch: interromput.\n".utf8))
            exit(130)
        }
    }
    senyal.resume()
}
let obridor = ObridorCLI(obre: { try await ObreWarp.obre($0) }, engega: { try await ObreWarp.engega() },
                         fitxers: FitxersLaunchWarp.real,
                         appOberta: { !processos.pids(nom: WarpLaunch.executableApp).isEmpty },
                         avisa: { FileHandle.standardOutput.write(Data($0.utf8)) },
                         enInterrupcio: { interrupcio = $0 })
@MainActor
func executa() async -> (Int32, Sortida) {
    var sortida = Sortida()
    let codi = await OrdreCLI.executa(Array(CommandLine.arguments.dropFirst()), entorn: entorn, obridor: obridor,
                                      sortida: &sortida)
    return (codi, sortida)
}
let (codi, sortida) = await executa()
FileHandle.standardOutput.write(Data(sortida.text.utf8))
FileHandle.standardError.write(Data(sortida.errors.utf8))
exit(codi)
