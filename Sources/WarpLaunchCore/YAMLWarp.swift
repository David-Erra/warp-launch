import Foundation

/// Escalars per al YAML que llegeix Warp (serde_yaml 0.8, amb yaml-rust). **No escriu res:** només dona el text.
///
/// Si un fitxer té un camp que falta o d'un tipus que no toca, Warp el descarta sencer sense avisar (només ho diu a
/// `warp.log`). Per això l'app no fa servir cap biblioteca ni cap forma de YAML que no hagi provat: tots els escalars
/// van entre cometes dobles, i només s'escapen `\` (`\\`) i `"` (`\"`), els dos escapaments que tota implementació
/// de YAML llegeix igual. Els caràcters que s'haurien d'escriure d'una altra manera no s'escriuen: són un error.
public enum YAMLWarp {
    public enum ErrorYAML: Error, Equatable, CustomStringConvertible {
        /// Un caràcter de control (C0, DEL o C1, també el tabulador i els salts de línia), un separador de línia o de
        /// paràgraf (U+2028, U+2029), o U+FEFF, U+FFFE i U+FFFF.
        case caracterNoAdmes(Unicode.Scalar)

        public var description: String {
            switch self {
            case let .caracterNoAdmes(c):
                "hi ha un caràcter que l'app no sap escriure per a Warp (U+\(String(format: "%04X", c.value)))"
            }
        }
    }

    /// El text entre cometes dobles, amb `\` i `"` escapats.
    public static func escalar(_ text: String) throws(ErrorYAML) -> String {
        if let c = text.unicodeScalars.first(where: { !admes($0) }) { throw .caracterNoAdmes(c) }
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Si es pot escriure tal com és, entre cometes dobles.
    static func admes(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF: false
        default: true
        }
    }
}
