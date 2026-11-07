// Dibuixa les capes de la icona de Warp Launch (decisió d'en David, 06/11/2026: dibuixada amb codi, no amb nano-banana):
// finestres en cascada, formes blanques planes sobre fons transparent, de 1024 × 1024.
//   principal.png  la finestra del davant, amb la barra de títol (tres punts buits) separada per una franja buida
//   fons.png       dues finestres al darrere, amunt i a l'esquerra, separades entre elles i de la del davant
// Ús: swift scripts/icona-dibuixa.swift [carpeta]   (per defecte, Recursos/AppIcon.icon/Assets)
// Només CoreGraphics i ImageIO. El vidre, l'ombra i els aspectes els posa macOS (vegeu .claude/skills/app-icon).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let mida = 1024
let carpeta = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Recursos/AppIcon.icon/Assets")

// Geometria (origen a baix a l'esquerra). La finestra del davant fa el 51 % de l'amplada.
let amplada: CGFloat = 520, alcada: CGFloat = 440, radi: CGFloat = 64
let pas = CGPoint(x: -96, y: 96)          // de cada finestra a la de darrere
let davant = CGPoint(x: 608, y: 420)      // centre de la del davant: el conjunt queda centrat
let separacio: CGFloat = 26               // franja buida entre finestres
let barra: CGFloat = 100                  // alçada de la barra de títol
let franja: CGFloat = 32                  // franja buida sota la barra (prou gruixuda per a 16 pt)
let punt: CGFloat = 34                    // diàmetre dels tres punts de la barra (els botons d'una finestra de Mac)

func rectangle(_ centre: CGPoint, creix: CGFloat = 0) -> CGRect {
    CGRect(x: centre.x - amplada / 2, y: centre.y - alcada / 2, width: amplada, height: alcada).insetBy(dx: -creix, dy: -creix)
}

func finestra(_ c: CGPoint, creix: CGFloat = 0) -> CGPath {
    CGPath(roundedRect: rectangle(c, creix: creix), cornerWidth: radi + creix, cornerHeight: radi + creix, transform: nil)
}

func capa(_ nom: String, _ dibuixa: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: mida, height: mida, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    dibuixa(context)
    let url = carpeta.appending(path: nom)
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    let desti = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(desti, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(desti) else { throw CocoaError(.fileWriteUnknown) }
    print(url.path)
}

func buida(_ context: CGContext, _ camí: CGPath) {
    context.saveGState()
    context.setBlendMode(.clear)
    context.addPath(camí)
    context.fillPath()
    context.restoreGState()
}

let mig = CGPoint(x: davant.x + pas.x, y: davant.y + pas.y)
let darrere = CGPoint(x: mig.x + pas.x, y: mig.y + pas.y)

try capa("principal.png") { c in
    c.addPath(finestra(davant))
    c.fillPath()
    // La barra de títol: una franja buida que la separa del cos.
    let r = rectangle(davant)
    buida(c, CGPath(rect: CGRect(x: r.minX, y: r.maxY - barra - franja, width: amplada, height: franja), transform: nil))
    // Els tres punts, a l'esquerra de la barra.
    for i in 0..<3 {
        let x = r.minX + 56 + CGFloat(i) * (punt + 22)
        buida(c, CGPath(ellipseIn: CGRect(x: x, y: r.maxY - barra / 2 - punt / 2, width: punt, height: punt), transform: nil))
    }
}

try capa("fons.png") { c in
    c.addPath(finestra(darrere))
    c.fillPath()
    buida(c, finestra(mig, creix: separacio))
    c.addPath(finestra(mig))
    c.fillPath()
    buida(c, finestra(davant, creix: separacio))
}
