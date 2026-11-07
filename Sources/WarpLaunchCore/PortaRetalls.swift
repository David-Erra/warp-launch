import Foundation

/// Pestanyes copiades o retallades a l'editor (⌘C, ⌘X), per enganxar-les en una altra finestra (⌘V), i arrossegades a
/// la fila d'una finestra (pas 10).
///
/// El contingut és el JSON de la configuració (format v1) amb una sola finestra, amb un tipus propi declarat a
/// `Info.plist` que conforma a `public.data` i **no a text**: enganxat a Warp o a qualsevol altra app, no hi escriu res
/// (si hi anés l'ordre de Claude, quedaria al prompt d'un terminal). Per copiar l'ordre com a text hi ha «Copia l'ordre».
public enum PortaRetalls {
    /// Identificador del tipus (UTI), que és també el tipus del porta-retalls de macOS.
    public static let tipus = "cat.davide.warp-launch.pestanyes"

    /// - Parameter origen: l'id de la finestra del JSON. En arrossegar és el de l'execució de l'app, per saber en
    ///   deixar-les anar que vénen d'aquesta mateixa app (`origenIIds`); al porta-retalls, un de qualsevol.
    public static func dades(_ pestanyes: [Pestanya], origen: UUID = UUID()) throws -> Data {
        let finestra = Finestra(id: origen, nom: "Porta-retalls", pestanyes: pestanyes)
        return try Configuracio(finestres: [finestra], generador: "\(WarpLaunch.nom) \(WarpLaunch.versio)").json()
    }

    /// Les pestanyes, o `nil` si les dades no són pestanyes de Warp Launch (o són d'una versió més nova del format).
    public static func pestanyes(de dades: Data, inici: String) -> [Pestanya]? {
        guard let llegida = try? Configuracio.llegeix(dades, inici: inici) else { return nil }
        let pestanyes = llegida.configuracio.finestres.flatMap(\.pestanyes)
        return pestanyes.isEmpty ? nil : pestanyes
    }

    /// L'origen (`dades(_:origen:)`) i els id de les pestanyes, per moure-les. No en llegeix les carpetes, i per això
    /// no cal la carpeta d'inici. `nil` si no és una sola finestra amb pestanyes de Warp Launch.
    public static func origenIIds(de dades: Data) -> (origen: UUID, ids: [Pestanya.ID])? {
        guard let llegida = try? Configuracio.llegeix(dades, inici: "/"), llegida.configuracio.finestres.count == 1,
              let finestra = llegida.configuracio.finestres.first, !finestra.pestanyes.isEmpty
        else { return nil }
        return (finestra.id, finestra.pestanyes.map(\.id))
    }
}
