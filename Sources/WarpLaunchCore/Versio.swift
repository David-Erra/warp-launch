/// Identitat de l'app. La versió ha de coincidir amb el fitxer VERSION de l'arrel
/// (ho comprova `VersioTests`).
public enum WarpLaunch {
    public static let nom = "Warp Launch"
    public static let identificador = "cat.davide.warp-launch"
    public static let versio = "0.34.2"
    /// El nom de l'executable de l'app (al `.app` i a `.build`): el CLI no obre res mentre n'hi ha cap en marxa (D17).
    public static let executableApp = "WarpLaunch"
    /// El nom de l'ordre que llegeix Warp amb les finestres (D19), igual al menú Arxiu, al de la icona i al full d'importació
    /// (en David, 09/11/2026: la mateixa funció es diu igual a tots dos menús; `laMateixaOrdreEsDiuIgualAlsDosMenus`).
    public static var ordreActualitzaEstat: String { t("Actualitza l'estat de Warp") }
    /// «Sobre» i «Surt» del menú de la icona i de la pantalla del permís: els textos del menú de l'app, que posa macOS
    /// (`MainMenu.loctable` de SwiftUI, amb el seu apòstrof; docs/fets-verificats.md, «Els menús del sistema en català»).
    public static var ordreSobre: String { t("Sobre l’app \(nom)") }
    public static var ordreSurt: String { t("Surt de l’app \(nom)") }
}
