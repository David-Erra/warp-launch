/// Diu si un text és JSON vàlid segons la gramàtica estricta (ECMA-404), que és la que fa servir el `JSON.parse` de
/// Claude Code. Només mira la forma: no en construeix cap valor.
///
/// Cal perquè `JSONSerialization` de macOS 27.2 no hi coincideix (comprovat el 04/11/2026 amb node):
/// - accepta comes finals (`{"a":1,}`), que `JSON.parse` rebutja;
/// - rebutja `1e400` i les meitats de parell sola (`"\ud800"`), que `JSON.parse` accepta.
enum JSONEstricte {
    static func esValid(_ bytes: [UInt8]) -> Bool {
        var lector = Lector(bytes: bytes)
        lector.espais()
        guard lector.valor() else { return false }
        lector.espais()
        return lector.i == bytes.count
    }

    private struct Lector {
        let bytes: [UInt8]
        var i = 0
        /// Fondària màxima, perquè un text fet a mà no pugui esgotar la pila.
        var fondaria = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        private var actual: UInt8? { i < bytes.count ? bytes[i] : nil }

        /// Només els quatre espais de JSON: espai, tabulador, salt de línia i retorn.
        mutating func espais() {
            while let b = actual, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1 }
        }

        private mutating func llegeix(_ c: Character) -> Bool {
            guard actual == c.asciiValue else { return false }
            i += 1
            return true
        }

        mutating func valor() -> Bool {
            switch actual {
            case UInt8(ascii: "{"): return contenidor(tanca: "}", element: { $0.parella() })
            case UInt8(ascii: "["): return contenidor(tanca: "]", element: { $0.valor() })
            case UInt8(ascii: "\""): return text()
            case UInt8(ascii: "t"): return paraula("true")
            case UInt8(ascii: "f"): return paraula("false")
            case UInt8(ascii: "n"): return paraula("null")
            default: return nombre()
            }
        }

        /// `{…}` o `[…]`: elements separats per comes, sense coma final.
        private mutating func contenidor(tanca: Character, element: (inout Lector) -> Bool) -> Bool {
            fondaria += 1
            defer { fondaria -= 1 }
            guard fondaria <= 512 else { return false }
            i += 1
            espais()
            if llegeix(tanca) { return true }
            while true {
                espais()
                guard element(&self) else { return false }
                espais()
                if llegeix(tanca) { return true }
                guard llegeix(",") else { return false }
            }
        }

        private mutating func parella() -> Bool {
            guard actual == UInt8(ascii: "\""), text() else { return false }
            espais()
            guard llegeix(":") else { return false }
            espais()
            return valor()
        }

        private mutating func paraula(_ paraula: String) -> Bool {
            for b in paraula.utf8 {
                guard actual == b else { return false }
                i += 1
            }
            return true
        }

        /// Cap caràcter de control sense escapar; escapaments `\" \\ \/ \b \f \n \r \t` i `\uXXXX` (qualsevol valor).
        private mutating func text() -> Bool {
            i += 1
            while let b = actual {
                i += 1
                switch b {
                case UInt8(ascii: "\""): return true
                case 0x00 ..< 0x20: return false
                case UInt8(ascii: "\\"):
                    guard let e = actual else { return false }
                    i += 1
                    if e == UInt8(ascii: "u") {
                        for _ in 0 ..< 4 {
                            guard let h = actual, h.esHex else { return false }
                            i += 1
                        }
                    } else if !"\"\\/bfnrt".utf8.contains(e) {
                        return false
                    }
                default: continue
                }
            }
            return false
        }

        /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, de qualsevol mida.
        private mutating func nombre() -> Bool {
            _ = llegeix("-")
            if llegeix("0") {
                // un zero inicial no pot anar seguit de més xifres
            } else {
                guard xifres() else { return false }
            }
            if llegeix(".") { guard xifres() else { return false } }
            if llegeix("e") || llegeix("E") {
                if !llegeix("+") { _ = llegeix("-") }
                guard xifres() else { return false }
            }
            return true
        }

        private mutating func xifres() -> Bool {
            let inici = i
            while let b = actual, b.esXifra { i += 1 }
            return i > inici
        }
    }
}

private extension UInt8 {
    var esXifra: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
    var esHex: Bool {
        esXifra || (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "f")) || (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "F"))
    }
}
