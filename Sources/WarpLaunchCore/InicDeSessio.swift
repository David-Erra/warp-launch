import Foundation

/// D3 (en David, 06/11/2026): en iniciar sessió, l'app s'obre sola i mostra el full «Obre-ho tot a Warp…»; no obre res fins
/// que s'hi fa clic. Aquí només es decideix si una arrencada és la de l'inici de sessió.
public enum InicDeSessio {
    /// Un Mac encès fa menys d'aquesta estona: l'arrencada és la de l'inici de sessió, encara que macOS no ho digui.
    public static let marge: TimeInterval = 600

    /// - Parameters:
    ///   - comElementDInici: macOS diu que l'ha obert com a element d'inici (l'esdeveniment d'obertura porta
    ///     `keyAELaunchedAsLogInItem`). No està comprovat que ho digui sempre: per això també compta el temps.
    ///   - segonsEncesa: des que el Mac s'ha encès, també les estones en repòs (`CLOCK_MONOTONIC`).
    ///   - registrada: l'app és als ítems d'inici, i macOS l'obrirà sola (aprovada). Si no, mai: obrir-la a mà just després
    ///     d'encendre el Mac no ha de mostrar cap full.
    public static func es(comElementDInici: Bool, segonsEncesa: TimeInterval, registrada: Bool) -> Bool {
        registrada && (comElementDInici || segonsEncesa < marge)
    }
}
