/// Busca la primera clau repetida dins d'un mateix objecte d'un JSON **ja validat** (en UTF-8).
///
/// Cal perquè, a macOS 27.2, `JSONSerialization` i `JSONDecoder` es queden amb la primera aparició d'una clau
/// repetida sense dir res, mentre que `jq`, Python i `plutil` es queden amb l'última (comprovat el 03/11/2026).
/// Un fitxer així és ambigu: en David hi pot veure `false` amb `jq` i l'app llegir-hi `true`.
enum ClausRepetides {
    struct Repetida: Equatable {
        /// On és l'objecte, per exemple `finestres[0].pestanyes[2].claude` (buit si és l'arrel).
        let cami: String
        let clau: String
    }

    static func primera(_ bytes: [UInt8]) -> Repetida? {
        var lector = Lector(bytes: bytes)
        return lector.valor(cami: "")
    }

    private struct Lector {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        private var actual: UInt8? { i < bytes.count ? bytes[i] : nil }

        private mutating func espais() {
            while let b = actual, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1 }
        }

        mutating func valor(cami: String) -> Repetida? {
            espais()
            switch actual {
            case UInt8(ascii: "{"): return objecte(cami: cami)
            case UInt8(ascii: "["): return llista(cami: cami)
            case UInt8(ascii: "\""):
                _ = text()
                return nil
            case nil: return nil
            default:  // nombre, true, false o null
                while let b = actual, b != UInt8(ascii: ","), b != UInt8(ascii: "}"), b != UInt8(ascii: "]"),
                      b != 0x20, b != 0x09, b != 0x0A, b != 0x0D { i += 1 }
                return nil
            }
        }

        private mutating func objecte(cami: String) -> Repetida? {
            i += 1  // {
            var vistes = Set<String>()
            espais()
            if actual == UInt8(ascii: "}") {
                i += 1
                return nil
            }
            while actual != nil {
                espais()
                guard actual == UInt8(ascii: "\"") else { return nil }  // no hauria de passar: el JSON és vàlid
                let clau = text()
                if !vistes.insert(clau).inserted { return Repetida(cami: cami, clau: clau) }
                espais()
                i += 1  // :
                if let repetida = valor(cami: cami.isEmpty ? clau : "\(cami).\(clau)") { return repetida }
                espais()
                let separador = actual
                i += 1
                if separador != UInt8(ascii: ",") { return nil }  // }
            }
            return nil
        }

        private mutating func llista(cami: String) -> Repetida? {
            i += 1  // [
            espais()
            if actual == UInt8(ascii: "]") {
                i += 1
                return nil
            }
            var index = 0
            while actual != nil {
                if let repetida = valor(cami: "\(cami)[\(index)]") { return repetida }
                index += 1
                espais()
                let separador = actual
                i += 1
                if separador != UInt8(ascii: ",") { return nil }  // ]
            }
            return nil
        }

        /// Llegeix una cadena (`i` és a la cometa d'obertura) i la retorna descodificada, perquè `"a"` i `"a"`
        /// són la mateixa clau.
        private mutating func text() -> String {
            i += 1
            var utf16: [UInt16] = []
            var tros: [UInt8] = []
            func buidaTros() {
                guard !tros.isEmpty else { return }
                utf16.append(contentsOf: String(decoding: tros, as: UTF8.self).utf16)
                tros.removeAll()
            }
            while let b = actual {
                if b == UInt8(ascii: "\"") {
                    i += 1
                    break
                }
                guard b == UInt8(ascii: "\\"), i + 1 < bytes.count else {
                    tros.append(b)
                    i += 1
                    continue
                }
                buidaTros()
                let escapament = bytes[i + 1]
                i += 2
                switch escapament {
                case UInt8(ascii: "b"): utf16.append(0x08)
                case UInt8(ascii: "f"): utf16.append(0x0C)
                case UInt8(ascii: "n"): utf16.append(0x0A)
                case UInt8(ascii: "r"): utf16.append(0x0D)
                case UInt8(ascii: "t"): utf16.append(0x09)
                case UInt8(ascii: "u"):
                    let hex = String(decoding: bytes[i ..< min(i + 4, bytes.count)], as: UTF8.self)
                    utf16.append(UInt16(hex, radix: 16) ?? 0xFFFD)
                    i += 4
                default: utf16.append(UInt16(escapament))  // " \ /
                }
            }
            buidaTros()
            return String(decoding: utf16, as: UTF16.self)
        }
    }
}
