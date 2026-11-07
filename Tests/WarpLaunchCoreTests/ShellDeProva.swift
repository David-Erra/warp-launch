import Foundation
import Testing

/// El que escriu una shell en executar `script`, separat per NUL (`printf '%s\0'`). zsh va sense fitxers d'inici
/// (`-f`): les opcions per defecte, que són les que importen per a les cometes. No s'executa mai `claude`.
func sortidaDe(_ shell: String, _ script: String) throws -> [String] {
    let procés = Process()
    procés.executableURL = URL(filePath: shell)
    procés.arguments = (shell.hasSuffix("zsh") ? ["-f"] : []) + ["-c", script]
    let sortida = Pipe()
    procés.standardOutput = sortida
    try procés.run()
    let dades = sortida.fileHandleForReading.readDataToEndOfFile()
    procés.waitUntilExit()
    #expect(procés.terminationStatus == 0, "\(shell) -c: \(script)")
    var parts = dades.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    if parts.last == "" { parts.removeLast() }
    return parts
}

/// Executa un script de `scripts/` amb bash i un entorn triat per la prova: el codi de sortida i el que ha escrit.
func executaScript(_ script: URL, _ arguments: [String], entorn: [String: String]) throws -> (codi: Int32, sortida: String) {
    let procés = Process()
    procés.executableURL = URL(filePath: "/bin/bash")
    procés.arguments = [script.path] + arguments
    procés.environment = entorn
    let sortida = Pipe()
    procés.standardOutput = sortida
    procés.standardError = sortida
    try procés.run()
    let dades = sortida.fileHandleForReading.readDataToEndOfFile()
    procés.waitUntilExit()
    return (procés.terminationStatus, String(decoding: dades, as: UTF8.self))
}

/// Executa `script` amb un zsh que sí que llegeix els seus fitxers d'inici, els de la carpeta `zdotdir`, de la prova.
func zshAmbInici(_ script: String, zdotdir: URL) throws -> (codi: Int32, sortida: String) {
    let procés = Process()
    procés.executableURL = URL(filePath: "/bin/zsh")
    procés.arguments = ["-c", script]
    procés.environment = ["ZDOTDIR": zdotdir.path, "HOME": zdotdir.path, "PATH": "/usr/bin:/bin"]
    let sortida = Pipe()
    procés.standardOutput = sortida
    procés.standardError = sortida
    try procés.run()
    let dades = sortida.fileHandleForReading.readDataToEndOfFile()
    procés.waitUntilExit()
    return (procés.terminationStatus, String(decoding: dades, as: UTF8.self))
}

/// Com parteix una shell el text d'una ordre.
func argvSegons(_ shell: String, _ text: String) throws -> [String] {
    try sortidaDe(shell, "printf '%s\\0' " + text)
}

/// Executa un programa (no un script de bash) amb `arguments` i `entorn`, i en torna el codi i la sortida, amb els errors.
func executaPrograma(_ programa: String, _ arguments: [String], entorn: [String: String]) throws -> (codi: Int32, sortida: String) {
    let procés = Process()
    procés.executableURL = URL(filePath: programa)
    procés.arguments = arguments
    procés.environment = entorn
    let sortida = Pipe()
    procés.standardOutput = sortida
    procés.standardError = sortida
    try procés.run()
    let dades = sortida.fileHandleForReading.readDataToEndOfFile()
    procés.waitUntilExit()
    return (procés.terminationStatus, String(decoding: dades, as: UTF8.self))
}
