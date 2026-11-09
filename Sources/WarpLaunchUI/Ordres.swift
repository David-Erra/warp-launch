import SwiftUI
import WarpLaunchCore

private struct ClauEditor: FocusedValueKey {
    typealias Value = Editor
}

private struct ClauColumna: FocusedValueKey {
    typealias Value = ColumnaEditor
}

extension FocusedValues {
    /// L'editor de la finestra activa. Les ordres del menú només hi actuen si l'editor té el focus.
    /// (Sense `@Entry`: amb les Command Line Tools no hi ha el connector de les macros de SwiftUI.)
    public var editor: Editor? {
        get { self[ClauEditor.self] }
        set { self[ClauEditor.self] = newValue }
    }

    /// La columna de l'editor amb el focus (la barra lateral o la llista): Duplica i «Canvia el nom» hi actuen.
    public var columnaEditor: ColumnaEditor? {
        get { self[ClauColumna.self] }
        set { self[ClauColumna.self] = newValue }
    }
}

/// «Actualitza l'estat de Warp», al menú Arxiu i al de la icona: una sola vista, perquè es digui igual i es desactivi igual
/// a tots dos. Una vista, i no un `Button` dins d'`OrdresEditor`, perquè observi l'estat de Warp i el permís.
public struct ItemActualitzaWarp: View {
    private let ordre: OrdreActualitzaWarp

    public init(ordre: OrdreActualitzaWarp) {
        self.ordre = ordre
    }

    public var body: some View {
        Button(WarpLaunch.ordreActualitzaEstat) { Task { await ordre.executa() } }
            .disabled(!ordre.potExecutar)
    }
}

/// Ordres de la barra de menús (docs/disseny.md, «Ordres»). Una ordre que no s'aplica surt desactivada; Edició
/// (Desfés, Retalla, Copia, Enganxa, Elimina) és la del sistema, i hi arriba des de la llista i la barra lateral.
public struct OrdresEditor: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.columnaEditor) private var columna
    private let actualitzaWarp: OrdreActualitzaWarp

    public init(actualitzaWarp: OrdreActualitzaWarp) {
        self.actualitzaWarp = actualitzaWarp
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nova finestra") { editor?.afegeixFinestra() }
                .keyboardShortcut("n")
                .disabled(editor?.ordresActives != true)
            Button("Nova pestanya…") { editor?.demanaPestanyaNova() }
                .keyboardShortcut("t")
                .disabled(editor?.potNovaPestanya != true)
            Divider()
            Button(editor?.titolDuplica(columna) ?? "Duplica") { editor?.duplica(columna) }
                .keyboardShortcut("d")
                .disabled(editor?.objecte(columna) == nil)
            // Sense drecera al menú: Retorn és dels camps de text. A la llista i a la barra lateral, Retorn hi és
            // (`onKeyPress`).
            Button("Canvia el nom") { editor?.canviaElNom(columna) }
                .disabled(editor?.potCanviarElNom(columna) != true)
            Divider()
            // Amb importar i lligar, que també llegeixen Warp amb les finestres. No depèn de l'editor (com al menú de la icona).
            ItemActualitzaWarp(ordre: actualitzaWarp)
            Button(editor?.estat == .oberta ? "Torna a importar-ho tot de Warp…" : "Importa de Warp…") {
                editor?.demanaImportacio = true
            }
            .disabled(editor?.potImportar != true)
            // Només desa a `estat.json`, i amb el full: no obre ni canvia res.
            Button("Lliga amb Warp…") { editor?.demanaLligam() }
                .disabled(editor?.potLligar != true)
            Button("Mostra el fitxer al Finder") {
                if let fitxer = editor?.fitxerPerMostrar { Finder.mostra(fitxer) }
            }
            .disabled(editor?.fitxerPerMostrar == nil)
            Divider()
            // Fase 3.1: sempre amb confirmació (el full) i sense drecera (docs/disseny.md, «Ordres»).
            Button("Obre a Warp…") { if let id = editor?.finestra?.id { editor?.demanaObertura(id) } }
                .disabled(editor?.potObrir(editor?.finestra?.id) != true)
            Button("Obre-ho tot a Warp…") { editor?.demanaObreTot() }
                .disabled(editor?.potObrirTot != true)
        }
        // ⌘S no fa res: l'app desa sola, i no hi ha cap «Desa». El grup `.saveItem` no es toca: també porta «Tanca»
        // (⌘W) i «Tanca-ho tot» (⌥⌘W).
        CommandMenu("Pestanya") {
            Menu("Mou a") {
                let ids = Set(editor?.pestanyes.map(\.id) ?? [])
                let destins = editor?.finestresPerMoure(ids) ?? []
                if destins.isEmpty {
                    Button("Cap altra finestra") {}
                        .disabled(true)
                }
                ForEach(destins) { desti in
                    Button(editor?.etiquetaPerMoure(desti) ?? desti.nom) { editor?.mouA(ids, a: desti.id) }
                }
            }
            .disabled(editor?.potMoureTriades != true)
            Divider()
            Button("Activa Claude") { editor?.activaClaudeTriades(true) }
                .disabled(editor?.potActivarClaude != true)
            Button("Desactiva Claude") { editor?.activaClaudeTriades(false) }
                .disabled(editor?.potDesactivarClaude != true)
            Divider()
            let ordres = editor?.ordresSeleccionades ?? ""
            Button((editor?.pestanyes.count ?? 0) > 1 ? "Copia les ordres" : "Copia l'ordre") {
                PortaRetallsSistema.copiaText(ordres)
            }
            .disabled(ordres.isEmpty)
        }
        // Pròpia en lloc d'`InspectorCommands()`, i amb ⌥⌘I (la de Pages, Keynote i Numbers): amb ⌃⌘I, tant la
        // d'`InspectorCommands()` (prova 3) com aquesta (prova 4) no feien res amb la tecla, i sí amb un clic al menú
        // (docs/fets-verificats.md, 04/11/2026).
        // Abans del grup de la barra lateral (que també porta «Entra a pantalla completa»), al costat de «Mostra la
        // barra lateral». «Amaga» només si l'inspector és a la vista.
        CommandGroup(before: .sidebar) {
            Button(editor?.estat == .oberta && editor?.mostraInspector == true ? "Amaga l'inspector" : "Mostra l'inspector") {
                editor?.mostraInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])
            .disabled(editor?.estat != .oberta)
        }
    }
}
