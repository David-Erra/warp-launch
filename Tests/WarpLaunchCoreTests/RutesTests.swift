import Foundation
import Testing
@testable import WarpLaunchCore

@Suite("Rutes canòniques")
struct RutesTests {
    @Test func resolEnllacosSimbolics() throws {
        let tmp = try CarpetaTemporal()
        let real = try tmp.carpeta("GitHub/projecte")
        try FileManager.default.createSymbolicLink(atPath: tmp.ruta + "/Documents-GitHub",
                                                   withDestinationPath: tmp.ruta + "/GitHub")
        #expect(Rutes.canonica(tmp.ruta + "/Documents-GitHub/projecte") == real)
    }

    @Test func posaLesMajusculesDelDisc() throws {
        let tmp = try CarpetaTemporal()
        let real = try tmp.carpeta("GitHub/Projecte")
        let valors = try URL(filePath: tmp.ruta).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        // Només té sentit en un disc que no distingeix majúscules, com el del Mac d'en David.
        if valors.volumeSupportsCaseSensitiveNames == false {
            #expect(Rutes.canonica(tmp.ruta + "/github/projecte") == real)
        }
    }

    @Test func rutaInexistentQuedaNormalitzada() {
        #expect(Rutes.canonica("/no/existeix//Aquesta/../Carpeta/") == "/no/existeix/Carpeta")
    }

    @Test func abreujaLaCarpetaDInici() {
        #expect(Rutes.abreujada("/Users/prova/GitHub/x", inici: "/Users/prova") == "~/GitHub/x")
        #expect(Rutes.abreujada("/Users/prova", inici: "/Users/prova") == "~")
        #expect(Rutes.abreujada("/Users/provatura/x", inici: "/Users/prova") == "/Users/provatura/x")
        // I a l'inrevés (el camp Carpeta de l'inspector).
        #expect(Rutes.desabreujada("~/GitHub/x", inici: "/Users/prova") == "/Users/prova/GitHub/x")
        #expect(Rutes.desabreujada("~", inici: "/Users/prova") == "/Users/prova")
        #expect(Rutes.desabreujada("~/", inici: "/Users/prova/") == "/Users/prova/")
        #expect(Rutes.desabreujada("~altre/x", inici: "/Users/prova") == "~altre/x")
        #expect(Rutes.desabreujada("/opt/x", inici: "/Users/prova") == "/opt/x")
        #expect(Rutes.desabreujada("GitHub", inici: "/Users/prova") == "GitHub", "una ruta relativa es queda (avís)")
        for ruta in ["/Users/prova/GitHub/x", "/Users/prova", "/opt/x"] {
            #expect(Rutes.desabreujada(Rutes.abreujada(ruta, inici: "/Users/prova"), inici: "/Users/prova") == ruta)
        }
    }
}
