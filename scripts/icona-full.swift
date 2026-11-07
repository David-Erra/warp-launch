import AppKit

// Posa diverses imatges de la icona l'una al costat de l'altra sobre una franja grisa, cadascuna a la seva mida.
// La crida scripts/icona-revisa.sh: swift icona-full.swift <sortida.png> <entrada.png>...
// Adaptat de BAMA (daveebbelaar/bama, MIT): vegeu .claude/skills/app-icon/LICENSE-BAMA.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("ús: swift icona-full.swift <sortida.png> <entrada.png>...\n".utf8))
    exit(64)
}
let imatges = args.dropFirst(2).map { ruta -> (rep: NSBitmapImageRep, imatge: NSImage) in
    guard let dades = FileManager.default.contents(atPath: ruta), let rep = NSBitmapImageRep(data: dades) else {
        FileHandle.standardError.write(Data("icona-full: no puc llegir \(ruta)\n".utf8))
        exit(1)
    }
    let imatge = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    imatge.addRepresentation(rep)
    return (rep, imatge)
}

let marge = 48
let alcada = (imatges.map(\.rep.pixelsHigh).max() ?? 0) + marge * 2
let amplada = imatges.reduce(marge) { $0 + $1.rep.pixelsWide + marge }
let full = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: amplada, pixelsHigh: alcada, bitsPerSample: 8,
                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: full)
NSColor(white: 0.55, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: amplada, height: alcada).fill()
var x = marge
for (rep, imatge) in imatges {
    // ictool escriu PNG de 16 bits; dibuixar la NSImage en conserva les cantonades transparents.
    let y = (alcada - rep.pixelsHigh) / 2
    imatge.draw(in: NSRect(x: x, y: y, width: rep.pixelsWide, height: rep.pixelsHigh),
                from: .zero, operation: .sourceOver, fraction: 1)
    x += rep.pixelsWide + marge
}
NSGraphicsContext.current = nil
guard let png = full.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[1]))
