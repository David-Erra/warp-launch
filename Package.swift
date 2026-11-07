// swift-tools-version: 6.0
// Warp Launch: app de barra de menú per a macOS que llegeix, edita i torna a obrir
// les finestres i pestanyes de Warp amb les sessions de Claude Code.
// Sense dependències externes: només frameworks de macOS (vegeu CLAUDE.md).
import PackageDescription

let package = Package(
    name: "WarpLaunch",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "WarpLaunch", targets: ["WarpLaunchApp"]),
        .executable(name: "warp-launch", targets: ["WarpLaunchCLI"]),
        .library(name: "WarpLaunchCore", targets: ["WarpLaunchCore"]),
    ],
    targets: [
        // Lògica sense interfície: models, lectura de Warp i de Claude Code, configuració.
        .target(name: "WarpLaunchCore"),
        // Model de l'editor i vistes SwiftUI. No toca NSApp: es pot provar.
        .target(name: "WarpLaunchUI", dependencies: ["WarpLaunchCore"]),
        // L'única crida que fa obrir alguna cosa a Warp (fase 3.1): la fan servir l'app i el CLI (`obre --obre`, D17).
        // També hi ha l'única pregunta a macOS d'on és Warp (`TrobaWarp`, D-P12). Cap prova no en depèn.
        .target(name: "WarpLaunchObridor", dependencies: ["WarpLaunchCore"]),
        // App de barra de menú, prima: escenes, activació i Dock (s'empaqueta amb scripts/build-app.sh).
        .executableTarget(name: "WarpLaunchApp", dependencies: ["WarpLaunchCore", "WarpLaunchUI", "WarpLaunchObridor"]),
        // Comanda `warp-launch` per a proves i diagnòstic des del terminal.
        .executableTarget(name: "WarpLaunchCLI", dependencies: ["WarpLaunchCore", "WarpLaunchObridor"]),
        .testTarget(name: "WarpLaunchCoreTests", dependencies: ["WarpLaunchCore"]),
        .testTarget(name: "WarpLaunchUITests", dependencies: ["WarpLaunchUI", "WarpLaunchCore"]),
    ]
)
