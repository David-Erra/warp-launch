// Comprova la signatura EdDSA d'un fitxer amb la clau pública que porta l'app: una eina independent de Sparkle, que no toca el clauer.
// Ús: swift scripts/verifica-signatura.swift <clau pública en base64> <signatura en base64> <fitxer>
// Codi de sortida: 0 si és bona, 1 si no, 64 si els arguments no serveixen.
import CryptoKit
import Foundation
let a = CommandLine.arguments
guard a.count == 4, let pub = Data(base64Encoded: a[1]), let sig = Data(base64Encoded: a[2]),
      let clau = try? Curve25519.Signing.PublicKey(rawRepresentation: pub),
      let dades = FileManager.default.contents(atPath: a[3]) else { fputs("arguments\n", stderr); exit(64) }
exit(clau.isValidSignature(sig, for: dades) ? 0 : 1)
