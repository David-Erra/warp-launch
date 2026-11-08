/// Identitat de l'app. La versió ha de coincidir amb el fitxer VERSION de l'arrel
/// (ho comprova `VersioTests`).
public enum WarpLaunch {
    public static let nom = "Warp Launch"
    public static let identificador = "cat.davide.warp-launch"
    public static let versio = "0.31.3"
    /// El nom de l'executable de l'app (al `.app` i a `.build`): el CLI no obre res mentre n'hi ha cap en marxa (D17).
    public static let executableApp = "WarpLaunch"
}
