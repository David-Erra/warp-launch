import AppKit

// Converteix una imatge de nano-banana (figura blanca sobre fons negre) en una capa d'icona d'Icon Composer:
// blanc pur amb transparència, 1024 × 1024. La transparència surt de la lluminositat: el negre queda transparent,
// el blanc opac, i les vores conserven l'antialiàsing.
// Ús: swift scripts/icona-capa.swift <entrada.png> <capa.png>
// Diu quina part de l'amplada ocupa la figura (l'objectiu de la principal és entre el 45 i el 55 %).

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("ús: swift scripts/icona-capa.swift <entrada.png> <capa.png>\n".utf8))
    exit(64)
}
guard let entrada = NSImage(contentsOfFile: args[1]),
      let origen = entrada.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("icona-capa: no puc llegir \(args[1])\n".utf8))
    exit(1)
}
guard origen.width == origen.height else {
    FileHandle.standardError.write(Data("icona-capa: la imatge ha de ser quadrada (\(origen.width) × \(origen.height))\n".utf8))
    exit(1)
}

let mida = 1024
// 1. L'entrada, en escala de grisos i a 1024 × 1024.
let grisos = CGContext(data: nil, width: mida, height: mida, bitsPerComponent: 8, bytesPerRow: mida,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
grisos.interpolationQuality = .high
grisos.draw(origen, in: CGRect(x: 0, y: 0, width: mida, height: mida))
let lluminositat = grisos.data!.bindMemory(to: UInt8.self, capacity: mida * mida)

// 2. Blanc amb alfa (premultiplicat). Per sota de `baix` és fons; per sobre d'`alt`, figura opaca.
let baix = 0.15, alt = 0.85
let capa = CGContext(data: nil, width: mida, height: mida, bitsPerComponent: 8, bytesPerRow: mida * 4,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let pixels = capa.data!.bindMemory(to: UInt8.self, capacity: mida * mida * 4)
var (minX, maxX, minY, maxY) = (mida, -1, mida, -1)
for i in 0..<(mida * mida) {
    let l = Double(lluminositat[i]) / 255
    let t = min(max((l - baix) / (alt - baix), 0), 1)
    let alfa = UInt8((t * t * (3 - 2 * t) * 255).rounded())
    pixels[i * 4] = alfa
    pixels[i * 4 + 1] = alfa
    pixels[i * 4 + 2] = alfa
    pixels[i * 4 + 3] = alfa
    if alfa >= 128 {
        let (x, y) = (i % mida, i / mida)
        (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
    }
}
guard maxX >= 0 else {
    FileHandle.standardError.write(Data("icona-capa: no hi ha cap figura clara sobre el fons\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: capa.makeImage()!)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try FileManager.default.createDirectory(at: URL(fileURLWithPath: args[2]).deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: args[2]))
let percentatge = Int((Double(maxX - minX + 1) / Double(mida) * 100).rounded())
print("\(args[2]): figura del \(percentatge) % de l'amplada, centrada a (\((minX + maxX) / 2), \((minY + maxY) / 2))")
