import WarpLaunchCore

// Dades de prova compartides per les proves del model de l'editor.

extension ClaudePestanya {
    /// Dada de prova: `claude --dangerously-skip-permissions --effort ultracode`, continuant la conversa (les opcions amb
    /// què en David obre Claude, 03/11/2026). Fins a la 0.27.3 era la plantilla d'importar sense configuració; des de la
    /// 0.28.0 l'app ja no la té (D11, revisada el 07/11/2026). La mateixa a `WarpLaunchCoreTests/Fixtures.swift`.
    static let habituals = ClaudePestanya(esforc: "xhigh", ultracode: true, saltaPermisos: true)
}
