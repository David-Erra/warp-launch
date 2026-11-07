import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WarpLaunchCore

/// Una pestanya arrossegada de la llista a la fila d'una finestra de la barra lateral (docs/disseny.md, «Arrossegar»).
///
/// Porta el tipus del porta-retalls (`PortaRetalls.tipus`, conforme només a `public.data`: mai text), amb el mateix
/// JSON, i només el veu aquest procés (`.ownProcess`). La finestra del JSON és `aquestProces`: en deixar-les anar, les
/// d'una altra execució de l'app (una altra configuració, que pot tenir els mateixos id després d'un ⌘C ⌘V) no mouen res.
public struct PestanyaArrossegada: Transferable, Identifiable, Sendable, Equatable {
    /// Aquesta execució de l'app. Només és a la memòria.
    public static let aquestProces = UUID()

    public let id: Pestanya.ID
    public let origen: UUID
    let dades: Data

    /// Una pestanya de la llista, per arrossegar-la.
    init(_ pestanya: Pestanya) throws {
        id = pestanya.id
        origen = Self.aquestProces
        dades = try PortaRetalls.dades([pestanya], origen: Self.aquestProces)
    }

    /// El que arriba en deixar-la anar. `nil` si no és una sola pestanya de Warp Launch.
    init?(dades: Data) {
        guard let llegides = PortaRetalls.origenIIds(de: dades), llegides.ids.count == 1 else { return nil }
        id = llegides.ids[0]
        origen = llegides.origen
        self.dades = dades
    }

    /// Només per llegir el que es deixa anar: no s'exporta mai (el que s'arrossega ho dona `proveidor`, només per a
    /// aquest procés). La visibilitat no hi intervé: en deixar anar, SwiftUI només fa servir `readableContentTypes` i
    /// `NSItemProvider.loadTransferable`, que no la miren. Quan la fila d'una finestra rep 0 pestanyes, és que la
    /// càrrega s'ha cancel·lat (-1000/3072), i `Editor.deixaAnar` mou les de l'última pulsació (`pestanyesFixades`). El que
    /// vingui d'una altra execució de l'app no mou res: només s'accepten les d'`aquestProces`.
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: PortaRetallsSistema.tipus) { dades in
            guard let arrossegada = PestanyaArrossegada(dades: dades) else {
                Registre.arrossegar.error("no es poden llegir les dades arrossegades (\(dades.count) bytes)")
                throw CocoaError(.coderReadCorrupt)
            }
            return arrossegada
        }
    }

    /// Per a `itemProvider` de cada fila de la llista: només el tipus propi, només per a aquest procés. No toca el
    /// porta-retalls (`NSPasteboard.general`): és el de l'arrossegament, que omple el sistema.
    static func proveidor(_ pestanya: Pestanya) -> NSItemProvider? {
        guard let arrossegada = try? PestanyaArrossegada(pestanya) else { return nil }
        let proveidor = NSItemProvider()
        proveidor.registerDataRepresentation(forTypeIdentifier: PortaRetalls.tipus, visibility: .ownProcess) { acaba in
            acaba(arrossegada.dades, nil)
            return nil
        }
        return proveidor
    }

    /// Dins de l'app, copiar i moure (la destinació sempre demana moure); cap a una altra app (Warp, el Finder), res.
    /// No està comprovat que SwiftUI l'apliqui a una fila de `List`: és una barrera més, amb `.ownProcess`.
    static var configuracio: DragConfiguration {
        var fora = DragConfiguration.OperationsOutsideApp(allowCopy: false, allowMove: false, allowDelete: false)
        fora.allowAlias = false
        return DragConfiguration(operationsWithinApp: .init(allowCopy: true, allowMove: true, allowDelete: false),
                                 operationsOutsideApp: fora)
    }
}
