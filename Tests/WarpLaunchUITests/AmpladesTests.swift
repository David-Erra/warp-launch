import AppKit
import CoreText
import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// F6 (docs/disseny.md, secció 12): els textos que van en llocs d'amplada fixa hi caben en les 10 llengües. Cada text es mesura
// amb la lletra del sistema (`NSFont.systemFont`, amb CoreText i les lletres de reserva del xinès, el japonès i el coreà), sense
// obrir l'app ni crear cap vista, i es compara amb l'espai que deixen SwiftUI i macOS en aquell lloc (`Mides`).

/// Les mides de SwiftUI a macOS 27.2, mesurades el 12/11/2026 amb un programa a part que dibuixa les vistes sense mostrar cap
/// finestra: el marc de cada vista (`onGeometryChange`) i, per a les etiquetes, l'amplada a partir de la qual passen a dues
/// línies. Arrodonides cap a la banda segura.
enum Mides {
    /// Un `Form` agrupat deixa 30 pt per banda (20 de la secció i 10 de la fila): a 520 pt, la fila en fa 460.
    static let margeForm: CGFloat = 30
    /// El mateix `Form`, a l'inspector, en deixa 20: a 320 pt, la fila en fa 280.
    static let margeInspector: CGFloat = 20
    /// Entre l'etiqueta i un botó o un menú (`LabeledContent`): amb un botó de 157,5 pt en una fila de 460, l'etiqueta es parteix
    /// a partir de 291 pt.
    static let separacio: CGFloat = 12
    /// Entre l'etiqueta i un valor de text (`LabeledContent(_:value:)`).
    static let separacioValor: CGFloat = 20.5
    /// Entre l'etiqueta d'un `Picker` i el desplegable, quan el desplegable hi cap sencer.
    static let separacioDesplegable: CGFloat = 24
    /// Amb un desplegable que no hi cap, SwiftUI l'encongeix (en talla l'opció triada) i l'etiqueta fa una línia fins al 44 % de
    /// la fila. Mesurat amb files de 240, 260, 280, 320 i 380 pt (l'inspector) i de 460 (la Configuració): es parteix a partir de
    /// 108, 117, 126,5, 145, 173 i 207 pt.
    static let etiquetaDeDesplegable: CGFloat = 0.44
    /// Un camp de text (`TextField` amb títol) deixa a l'etiqueta la meitat de la fila, sense la separació: a 280 pt, fins a 136.
    static let separacioCamp: CGFloat = 12
    /// Un botó: el text, i 24,5 pt de vores.
    static let boto: CGFloat = 24.5
    /// Un botó amb menú (`menuStyle(.button)`, amb acció principal): el text, i 48,5 pt.
    static let menu: CGFloat = 48.5
    /// Un desplegable: l'opció més ampla, i 48 pt.
    static let desplegable: CGFloat = 48
    /// Una casella (`toggleStyle(.checkbox)`): el quadre, la separació i el que deixa al final de la fila (a 280 pt, el text es
    /// parteix a partir de 257).
    static let casella: CGFloat = 23.5
    /// Un interruptor petit (`controlSize(.mini)`), amb la separació: a 460 pt, l'etiqueta es parteix a partir de 412.
    static let interruptor: CGFloat = 48.5
    /// La icona d'un `Label` d'una fila, amb la separació.
    static let icona: CGFloat = 26.5
    /// El triangle d'un `DisclosureGroup`, abans del text.
    static let triangle: CGFloat = 11.5
    /// Entre dos botons d'un `HStack`; amb un `Spacer` al mig, el doble.
    static let entreBotons: CGFloat = 8
    static let ambSpacer: CGFloat = 16
    /// Els botons del peu d'un full (`padding(20)`).
    static let margeFull: CGFloat = 20
    /// La barra lateral: el text d'una fila amb icona va de 46 pt a 16 pt de la vora dreta, i una insígnia de dues xifres en treu
    /// 27,5; la capçalera d'una secció, de 14 pt a 2 pt; i el peu de «Prova:», de 32,5 pt a 12 pt.
    static let textLateral: CGFloat = 62
    static let insignia: CGFloat = 27.5
    static let capcaleraLateral: CGFloat = 16
    static let provaLateral: CGFloat = 44.5
    /// La llista de pestanyes: 16 pt per banda.
    static let margeLlista: CGFloat = 16
    /// El `Spacer(minLength: 8)` entre el nom i el resum de la fila d'una pestanya.
    static let spacerFila: CGFloat = 8
    /// La pantalla del permís: `padding(28)`, i la icona de 36 pt amb 14 de separació al costat del títol.
    static let margePermis: CGFloat = 28
    static let iconaPermis: CGFloat = 36 + 14
}

/// La lletra de cada lloc, com la posa SwiftUI a macOS (mesurada amb el mateix programa).
enum Lletra {
    /// 13 pt: les etiquetes, els botons i el text de les files.
    case cos
    /// 13 pt seminegreta: les capçaleres de secció d'un `Form` agrupat.
    case capcalera
    /// 11 pt: el segon text d'una etiqueta (subtítol) i els peus de secció.
    case subtitol
    /// 11 pt seminegreta: les capçaleres de secció de la barra lateral.
    case capcaleraLateral
    /// 10 pt (`.caption`): el peu de «Prova:» de la barra lateral.
    case peu
    /// 17 pt negreta (`.title2.bold()`): el títol de la pantalla del permís.
    case titol

    var font: NSFont {
        switch self {
        case .cos: NSFont.systemFont(ofSize: 13)
        case .capcalera: NSFont.systemFont(ofSize: 13, weight: .semibold)
        case .subtitol: NSFont.systemFont(ofSize: 11)
        case .capcaleraLateral: NSFont.systemFont(ofSize: 11, weight: .semibold)
        case .peu: NSFont.systemFont(ofSize: 10)
        case .titol: NSFont.systemFont(ofSize: 17, weight: .bold)
        }
    }
}

/// Un text que va en un lloc d'amplada fixa: el text (o, si n'hi ha diversos, com les opcions d'un desplegable o els botons que
/// surten segons l'estat, el més ample), la seva lletra i les vores del seu control.
@MainActor
struct Peca: Sendable {
    let textos: @MainActor @Sendable () -> [String]
    let lletra: Lletra
    let vores: CGFloat

    static func text(_ text: @escaping @MainActor @Sendable () -> String, _ lletra: Lletra = .cos, vores: CGFloat = 0) -> Peca {
        Peca(textos: { [text()] }, lletra: lletra, vores: vores)
    }

    static func textos(_ textos: @escaping @MainActor @Sendable () -> [String]) -> Peca {
        Peca(textos: textos, lletra: .cos, vores: 0)
    }

    static func boto(_ text: @escaping @MainActor @Sendable () -> String) -> Peca { .text(text, vores: Mides.boto) }

    static func botons(_ textos: @escaping @MainActor @Sendable () -> [String]) -> Peca {
        Peca(textos: textos, lletra: .cos, vores: Mides.boto)
    }

    static func desplegable(_ opcions: @escaping @MainActor @Sendable () -> [String]) -> Peca {
        Peca(textos: opcions, lletra: .cos, vores: Mides.desplegable)
    }

    /// El text més ample, i el que fa amb les vores.
    func amplada() -> (text: String, amplada: CGFloat) {
        let mesurats = textos().map { ($0, AmpladesTests.amplada($0, lletra) + vores) }
        return mesurats.max { $0.1 < $1.1 } ?? ("", vores)
    }
}

/// Un lloc: les peces que hi van en una fila, amb `separacio` entre elles, i l'amplada que hi ha.
@MainActor
struct Cas: Sendable {
    enum Regla: Sendable {
        /// Les peces, en una línia: cap text no es parteix ni es talla, i cap control no s'encongeix.
        case unaLinia
        /// La primera peça pot fer fins a `n` línies (una nota, un subtítol, el detall o el valor d'una fila) en el que hi deixen
        /// les altres, que no es parteixen.
        case linies(Int)
        /// L'etiqueta d'un `Picker`, en una línia, al costat d'aquest desplegable (`Mides.etiquetaDeDesplegable`).
        case etiquetaDeDesplegable(Peca)
    }

    let lloc: String
    let peces: [Peca]
    let separacio: CGFloat
    let disponible: CGFloat
    let regla: Regla

    init(_ lloc: String, _ peces: [Peca], separacio: CGFloat = 0, disponible: CGFloat, regla: Regla = .unaLinia) {
        self.lloc = lloc
        self.peces = peces
        self.separacio = separacio
        self.disponible = disponible
        self.regla = regla
    }

    /// Una fila d'un `Form`: l'etiqueta, la separació i el control.
    static func fila(_ lloc: String, _ etiqueta: @escaping @MainActor @Sendable () -> String, _ control: Peca,
                     separacio: CGFloat = Mides.separacio, disponible: CGFloat) -> Cas {
        Cas(lloc, [.text(etiqueta), control], separacio: separacio, disponible: disponible)
    }

    /// Un `Picker` amb títol: l'etiqueta i el desplegable, sencer, en una línia.
    static func desplegable(_ lloc: String, _ etiqueta: @escaping @MainActor @Sendable () -> String,
                            _ opcions: @escaping @MainActor @Sendable () -> [String], disponible: CGFloat) -> Cas {
        Cas(lloc, [.text(etiqueta), .desplegable(opcions)], separacio: Mides.separacioDesplegable, disponible: disponible)
    }
}

@MainActor
@Suite struct AmpladesTests {
    // MARK: - Mesurar

    /// L'amplada d'una línia de text, amb les lletres de reserva del sistema per als caràcters que la lletra no té. És la que
    /// dona SwiftUI (mesurat: «ウインドウ12 のコピー», 128,3 pt aquí i 128,5 a SwiftUI, que arrodoneix al mig punt).
    static func amplada(_ text: String, _ lletra: Lletra) -> CGFloat {
        let linia = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: lletra.font]))
        return CGFloat(CTLineGetTypographicBounds(linia, nil, nil, nil))
    }

    /// Les línies que fa un text en una amplada, amb els salts de línia de cada llengua (CoreText).
    static func linies(_ text: String, _ lletra: Lletra, amplada: CGFloat) -> Int {
        let atribuit = NSAttributedString(string: text, attributes: [.font: lletra.font])
        let compositor = CTTypesetterCreateWithAttributedString(atribuit)
        var inici = 0, linies = 0
        while inici < atribuit.length {
            let caracters = CTTypesetterSuggestLineBreak(compositor, inici, Double(amplada))
            guard caracters > 0 else { return .max }
            inici += caracters
            linies += 1
        }
        return linies
    }

    /// Què no hi cap d'un lloc, en la llengua del bloc, o `nil` si hi cap.
    static func problema(_ cas: Cas) -> String? {
        let mesures = cas.peces.map { $0.amplada() }
        let textos = mesures.map { "«\($0.text)»" }.joined(separator: " + ")
        switch cas.regla {
        case .unaLinia:
            let total = mesures.map(\.amplada).reduce(0, +) + cas.separacio * CGFloat(max(0, mesures.count - 1))
            guard total > cas.disponible else { return nil }
            return "\(textos) fa \(format(total)) pt, i hi ha \(format(cas.disponible)) pt"
        case let .linies(maxim):
            let peca = cas.peces[0]
            let altres = mesures.dropFirst().map(\.amplada).reduce(0, +) + cas.separacio * CGFloat(mesures.count - 1)
            let amplada = cas.disponible - altres - peca.vores
            let linies = linies(mesures[0].text, peca.lletra, amplada: amplada)
            guard linies > maxim else { return nil }
            return "\(textos) fa \(linies) línies de \(format(amplada)) pt (\(format(mesures[0].amplada)) pt en una), i n'hi "
                + "caben \(maxim)"
        case let .etiquetaDeDesplegable(desplegable):
            let etiqueta = mesures[0].amplada
            let control = desplegable.amplada().amplada
            let maxim = max(cas.disponible - Mides.separacioDesplegable - control, cas.disponible * Mides.etiquetaDeDesplegable)
            guard etiqueta > maxim else { return nil }
            return "\(textos) fa \(format(etiqueta)) pt al costat d'un desplegable de \(format(control)) pt, i en una fila de "
                + "\(format(cas.disponible)) pt n'hi caben \(format(maxim)) en una línia"
        }
    }

    static func format(_ x: CGFloat) -> String { String(format: "%.1f", Double(x)) }

    // MARK: - Els llocs

    /// La fila d'un `Form` agrupat de `amplada` pt.
    static func filaForm(_ amplada: CGFloat) -> CGFloat { amplada - 2 * Mides.margeForm }

    static var casos: [Cas] {
        configuracio + inspector + fulls + barraLateral + llistaDePestanyes + editorBuit
    }

    /// Les opcions d'un desplegable de Claude (model, esforç o mode de permisos), les de l'editor, amb «Valors diversos» si les
    /// pestanyes triades no hi coincideixen.
    static func opcions(_ camp: Editor.CampTria, diversos: Bool = false) -> [String] {
        let opcions = Editor.opcions(camp, de: [ClaudePestanya()]).map(\.text)
        return diversos ? [t("Valors diversos")] + opcions : opcions
    }

    /// La Configuració (`VistaConfiguracio.amplada`): les capçaleres i les files amb etiqueta i control.
    static var configuracio: [Cas] {
        let fila = filaForm(VistaConfiguracio.amplada)
        let capcaleres: [@MainActor @Sendable () -> String] = [
            { t("En iniciar sessió") }, { t("Idioma") }, { t("Fitxer") }, { t("Diagnòstic") },
            { t("Deixar de fer servir Warp Launch") }, { t("Actualitzacions") }, { t("Ordre") }, { t("Altres opcions") },
        ]
        let interruptors: [@MainActor @Sendable () -> String] = [
            { t("Obre Warp Launch en iniciar sessió") }, { t("Actualitza automàticament") },
            { t("Obre Claude Code a les pestanyes noves") }, { t("Continua la conversa") }, { t("Salta els permisos") },
            { ClaudePestanya.nomUltracode },
        ]
        return capcaleres.map { Cas("Configuració, capçalera", [.text($0, .capcalera)], disponible: fila) }
            + interruptors.map { Cas("Configuració, interruptor", [.text($0, vores: Mides.interruptor)], disponible: fila) }
            + [
                // «En iniciar sessió», sense el permís de macOS: l'avís, fins a dues línies, i a sota el botó (`VistaConfiguracio`).
                Cas("Configuració, avís d'ítems d'inici", [.text({
                    t("macOS no l'obrirà sola fins que la permetis a Ítems d’inici de sessió i extensions")
                }, vores: Mides.icona)], disponible: fila, regla: .linies(2)),
                Cas("Configuració, avís d'ítems d'inici", [.boto { t("Mostra Ítems d’inici de sessió i extensions…") }],
                    disponible: fila),
                // La llengua del sistema, amb el nom més llarg de les 10, i les 10 en elles mateixes.
                .desplegable("Configuració, idioma", { t("Idioma de l'app") }, {
                    Idioma.llenguesDisponibles.map { t("El del sistema (\(Idioma.nom($0)))") }
                        + Idioma.llenguesDisponibles.map(Idioma.nomPropi)
                }, disponible: fila),
                Cas("Configuració, fitxer", [.text({ t("El fitxer ha canviat fora de l'app") }, vores: Mides.icona),
                                             .botons { [t("Torna a carregar"), t("Torna-ho a provar")] }],
                    separacio: Mides.ambSpacer, disponible: fila),
                Cas("Configuració, fitxer", [.text({ t("Configuració de prova (--config)") }, vores: Mides.icona)],
                    disponible: fila),
                Cas("Configuració, fitxer", [.boto { t("Mostra al Finder") }], disponible: fila),
                .fila("Configuració, diagnòstic", { t("Informe per a una issue a GitHub") },
                      .text({ t("Copia el diagnòstic") }, vores: Mides.menu), disponible: fila),
                // El subtítol, després de copiar: fins a dues línies al costat del botó.
                Cas("Configuració, diagnòstic", [
                    .text({ t("Copiat (anonimitzat): \(12) bé, \(12) avisos, \(12) errors.") }, .subtitol),
                    .text({ t("Copia el diagnòstic") }, vores: Mides.menu),
                ], separacio: Mides.separacio, disponible: fila, regla: .linies(2)),
                .fila("Configuració, deixar de fer servir", { t("Torna a deixar Warp com era") },
                      .boto { t("Restaura Warp i surt…") }, disponible: fila),
                .fila("Configuració, actualitzacions", { t("Estat") }, .botons {
                    [t("Comprova ara"), t("Actualitza ara"), t("Reinicia i actualitza"), t("Mostra la finestra")]
                }, disponible: fila),
                .fila("Configuració, actualitzacions", { t("Versió") }, .text { WarpLaunch.versio },
                      separacio: Mides.separacioValor, disponible: fila),
                // «Pestanyes noves»: els desplegables hi caben sencers, també amb «Sense cap permís (bypassPermissions)».
                .desplegable("Configuració, pestanyes noves", { t("Model") }, { opcions(.model) }, disponible: fila),
                .desplegable("Configuració, pestanyes noves", { t("Esforç") }, { opcions(.esforc) }, disponible: fila),
                .desplegable("Configuració, pestanyes noves", { t("Mode de permisos") }, { opcions(.modePermisos) },
                             disponible: fila),
                Cas("Configuració, pestanyes noves", [.boto { t("Treu el mode de permisos") }], disponible: fila),
                .fila("Configuració, pestanyes noves", { t("Nom de la sessió") }, .text { t("\("Botiga") (no s'aplica)") },
                      separacio: Mides.separacioValor, disponible: fila),
            ]
    }

    /// L'inspector, a l'amplada mínima (`VistaEditor.inspectorMinim`).
    static var inspector: [Cas] {
        let fila = VistaEditor.inspectorMinim - 2 * Mides.margeInspector
        let capcaleres: [@MainActor @Sendable () -> String] = [
            { t("Pestanya") }, { t("Finestra") }, { t("Claude Code a \(12) pestanyes") }, { t("Altres opcions") }, { t("Ordre") },
        ]
        let caselles: [@MainActor @Sendable () -> String] = [
            { t("Obre Claude Code en aquesta pestanya") }, { t("Obre Claude Code") }, { ClaudePestanya.nomUltracode },
            { t("Continua la conversa") }, { t("Salta els permisos") },
        ]
        let botons: [@MainActor @Sendable () -> String] = [
            { t("Treu el mode de permisos") }, { t("Copia l'ordre") }, { t("Copia les ordres") }, { t("Obre a Warp…") },
            { t("Tria…") },
        ]
        let camps: [@MainActor @Sendable () -> String] = [{ t("Nom") }, { t("Carpeta") }, { t("Nom de la sessió") }]
        return capcaleres.map { Cas("Inspector, capçalera", [.text($0, .capcalera)], disponible: fila) }
            + caselles.map { Cas("Inspector, casella", [.text($0, vores: Mides.casella)], disponible: fila) }
            + botons.map { Cas("Inspector, botó", [.boto($0)], disponible: fila) }
            + camps.map { Cas("Inspector, camp de text", [.text($0)], disponible: (fila - Mides.separacioCamp) / 2) }
            + [
                .desplegable("Inspector, model", { t("Model") }, { opcions(.model, diversos: true) }, disponible: fila),
                .desplegable("Inspector, esforç", { t("Esforç") }, { opcions(.esforc, diversos: true) }, disponible: fila),
                // Les opcions porten el nom de Claude entre parèntesis («Sense cap permís (bypassPermissions)»): el desplegable
                // no hi cap sencer en cap llengua, i en talla l'opció triada; l'etiqueta, en una línia.
                Cas("Inspector, mode de permisos", [.text { t("Mode de permisos") }], disponible: fila,
                    regla: .etiquetaDeDesplegable(.desplegable { opcions(.modePermisos, diversos: true) })),
                .fila("Inspector, conversa", { t("Conversa") }, .textos { [t("reprèn \("1b2c3d4e")"), t("nova")] },
                      separacio: Mides.separacioValor, disponible: fila),
                // El valor, fins a dues línies al costat de l'etiqueta.
                Cas("Inspector, finestra", [.text { t("\(12) pestanyes · \(12) amb Claude") }, .text { t("Pestanyes") }],
                    separacio: Mides.separacioValor, disponible: fila, regla: .linies(2)),
            ]
    }

    /// Els fulls d'obrir (`FullObertura.amplada`), de lligar (`FullLligam.amplada`) i d'importar (`VistaImportacio.amplada`),
    /// i la pantalla del permís (`VistaConsentiment.amplada`).
    static var fulls: [Cas] {
        let obrir = filaForm(FullObertura.amplada)
        let lligar = filaForm(FullLligam.amplada)
        let importar = filaForm(VistaImportacio.amplada)
        let capcaleresObrir: [@MainActor @Sendable () -> String] = [
            { t("Obre «\(t("Finestra \("12")"))» a Warp") }, { t("No es pot obrir") }, { t("Obre-ho tot a Warp") },
            { t("Finestres") }, { t("S'obriran (\(12))") }, { t("Avisos") }, { t("Ja obertes (\(12)): no s'obriran") },
            { t("No es poden obrir (\(12))") },
        ]
        let capcaleresLligar: [@MainActor @Sendable () -> String] = [
            { t("Lliga amb Warp") }, { t("No es pot lligar amb Warp") }, { t("Per finestra") }, { t("Comprova-les (\(12))") },
            { t("Sense parella (\(12)): s'obriran si n'obres la finestra") },
        ]
        let capcaleresImportar: [@MainActor @Sendable () -> String] = [
            { t("Importa de Warp") }, { t("Torna a importar-ho tot de Warp") }, { t("Avisos de la lectura") },
            { t("Pestanyes que no tenien Claude obert") }, { t("Finestres") }, { t("Notes") },
        ]
        let desplegables: [(String, CGFloat, @MainActor @Sendable () -> String)] = [
            ("Full d'obrir, detalls", obrir, { t("Detalls") }), ("Full d'obrir, avisos", obrir, { t("\(12) avisos") }),
            ("Full de lligar, les altres", lligar, { t("Les altres (\(12))") }),
        ]
        // El detall de cada pestanya, a la dreta, al costat del títol i la carpeta («~/GitHub/warp-launch», en 11 pt): fins a
        // dues línies (`FullObertura.fila`).
        let detall = obrir - amplada("~/GitHub/warp-launch", .subtitol) - Mides.separacioValor
        let lloc = t("finestra \("12") › \("warp-launch")")
        let detalls: [@MainActor @Sendable () -> String] = [
            { ConversaObertura.terminal.descripcio }, { ConversaObertura.repren("1b2c3d4e-5f60").descripcio },
            { ConversaObertura.nova(.senseConversa).descripcio },
            { OnOberta.marca(lloc: lloc).description }, { OnOberta.pane(lloc: lloc, ambClaude: false).description },
            { OnOberta.conversa(lloc: lloc).description }, { OnOberta.conversaForaDeWarp.description },
            { OnOberta.conversaEnCurs.description }, { OnOberta.conversaEnSegonPla("bg").description },
            { OnOberta.tancadaFaPoc.description }, { MotiuExclusio.carpetaNoExisteix.description },
            { MotiuExclusio.ordre(.sessioBuida).description },
        ]
        let permis = VistaConsentiment.amplada - 2 * Mides.margePermis
        let titols: [@MainActor @Sendable () -> String] = [
            { t("Warp Launch ha de desactivar un ajust de Warp") }, { t("Has deixat de fer servir Warp Launch") },
        ]
        return capcaleresObrir.map { Cas("Full d'obrir, capçalera", [.text($0, .capcalera)], disponible: obrir) }
            + capcaleresLligar.map { Cas("Full de lligar, capçalera", [.text($0, .capcalera)], disponible: lligar) }
            + capcaleresImportar.map { Cas("Full d'importar, capçalera", [.text($0, .capcalera)], disponible: importar) }
            + desplegables.map { Cas($0.0, [.text($0.2, vores: Mides.triangle)], disponible: $0.1) }
            + detalls.map { Cas("Full d'obrir, detall de la fila", [.text($0)], disponible: detall, regla: .linies(2)) }
            + titols.map { Cas("Pantalla del permís, títol", [.text($0, .titol)], disponible: permis - Mides.iconaPermis) }
            + [
                Cas("Full de lligar, per finestra", [
                    .text { t("\(12) de \(12) · finestres \(Idioma.llista(["1", "2", "4"])) de Warp") }, .text { "warp-launch" },
                ], separacio: Mides.separacioValor, disponible: lligar, regla: .linies(2)),
                // Els botons del peu.
                Cas("Full d'importar, botons", [
                    .boto { WarpLaunch.ordreActualitzaEstat }, .boto { t("Cancel·la") }, .botons { [t("Crea"), t("Substitueix")] },
                ], separacio: Mides.ambSpacer, disponible: VistaImportacio.amplada - 2 * Mides.margeFull),
                Cas("Full d'obrir, botons", [
                    .boto { t("Cancel·la") }, .botons { [t("Obre \(12) pestanyes"), t("Obre \(12) finestres")] },
                ], separacio: Mides.entreBotons, disponible: FullObertura.amplada - 2 * Mides.margeFull),
                Cas("Full de lligar, botons", [.boto { t("Cancel·la") }, .boto { t("Lliga \(12) pestanyes") }],
                    separacio: Mides.entreBotons, disponible: FullLligam.amplada - 2 * Mides.margeFull),
                Cas("Pantalla del permís, botons", [.boto { WarpLaunch.ordreSurt }, .boto { t("Accepta") }],
                    separacio: Mides.entreBotons, disponible: permis),
            ]
    }

    /// La barra lateral, a l'amplada mínima (`VistaEditor.barraLateralMinima`). Els noms de les finestres són de l'usuari: els
    /// que posa l'app («Finestra nova», «Finestra 3») es mesuren a l'amplada ideal (`VistaEditor.barraLateralIdeal`); a la mínima,
    /// es tallen com qualsevol nom llarg. El de les còpies («X còpia») depèn del nom de l'original, i no es mesura.
    static var barraLateral: [Cas] {
        let amplada = VistaEditor.barraLateralMinima
        let ideal = VistaEditor.barraLateralIdeal
        return [
            Cas("Barra lateral, fila amb insígnia", [.text { t("Per revisar") }],
                disponible: amplada - Mides.textLateral - Mides.insignia),
            Cas("Barra lateral, nom de finestra amb insígnia", [.textos { [t("Finestra nova"), t("Finestra \("12")")] }],
                disponible: ideal - Mides.textLateral - Mides.insignia),
            Cas("Barra lateral, capçalera", [.text({ t("Finestres") }, .capcaleraLateral)],
                disponible: amplada - Mides.capcaleraLateral),
            // `lineLimit(1)`: una ruta llarga es talla pel mig, però «Prova:» i una de curta s'hi han de veure.
            Cas("Barra lateral, configuració de prova", [.text({ t("Prova: \("/tmp/prova")") }, .peu)],
                disponible: amplada - Mides.provaLateral),
        ]
    }

    /// L'estat buit de l'editor, el primer ús (0.36.0, `SenseConfiguracio`), a la finestra més estreta: cada pas, fins a dues
    /// línies a l'amplada dels passos, al costat de la icona del número; i els botons, en una fila (el conjunt més ample, encara
    /// que SwiftUI els posi un sota l'altre): «Importa de Warp…», «Comença en blanc» i l'enllaç, sense vores.
    static var editorBuit: [Cas] {
        let passos: [@MainActor @Sendable () -> String] = [{ PrimerUs.passos[0] }, { PrimerUs.passos[1] }, { PrimerUs.passos[2] }]
        return passos.map {
            Cas("Editor buit, pas", [.text($0, vores: Mides.icona)], disponible: SenseConfiguracio.ampladaPassos, regla: .linies(2))
        } + [
            Cas("Editor buit, botons", [
                .boto { t("Importa de Warp…") }, .boto { t("Comença en blanc") }, .text { t("Fes que s'obri sola en iniciar sessió…") },
            ], separacio: Mides.entreBotons, disponible: VistaEditor.ampladaMinima - 2 * Mides.margeFull),
        ]
    }

    /// La fila d'una pestanya a la llista (`lineLimit(1)`), amb la finestra a la mida per defecte (`VistaEditor.ampladaPerDefecte`)
    /// i les columnes a la seva amplada ideal: el nom, a l'esquerra, i el resum de Claude, a la dreta, no s'han de tallar amb els
    /// noms que posa l'app («Pestanya nova», «Pestanya 3») o un de curt («warp-launch»). La línia de sota (la carpeta o l'avís,
    /// en 11 pt) es talla pel mig, i l'avís sencer és a l'ajuda de la fila i a l'inspector.
    static var llistaDePestanyes: [Cas] {
        let fila = VistaEditor.ampladaPerDefecte - VistaEditor.barraLateralIdeal - VistaEditor.inspectorIdeal
            - 2 * Mides.margeLlista
        let noms = Peca.textos { [t("Pestanya nova"), t("Pestanya \("12")"), "warp-launch"] }
        let resums = Peca.textos {
            [t("Només terminal")] + ClaudePestanya.modelsConeguts.flatMap { model in
                ClaudePestanya.esforcosConeguts.map { ClaudePestanya(model: model, esforc: $0, ultracode: true).resum }
            }
        }
        return [Cas("Llista, fila d'una pestanya", [noms, resums], separacio: Mides.spacerFila, disponible: fila)]
    }

    // MARK: - Proves

    /// Cada text hi cap, en cada llengua. Si no, diu quina llengua, en quin lloc, quin text (la clau, en català, i el traduït),
    /// quant fa i quant espai hi ha.
    @Test func elsTextosHiCapenEnCadaLlengua() {
        let llengues = Idioma.llenguesDisponibles
        #expect(llengues.count == 10)
        let casos = Self.casos
        // La taula sencera: si un lloc desapareix, es veu.
        #expect(casos.count == 103, "\(casos.count) llocs")
        let claus = Idioma.$deProva.withValue("ca") {
            casos.map { cas in cas.peces.map { "«\($0.amplada().text)»" }.joined(separator: " + ") }
        }
        var problemes: [String] = []
        for llengua in llengues {
            Idioma.$deProva.withValue(llengua) {
                for (cas, clau) in zip(casos, claus) {
                    if let problema = Self.problema(cas) { problemes.append("\(llengua): \(cas.lloc), clau \(clau): \(problema)") }
                }
            }
        }
        #expect(problemes.isEmpty, "\(problemes.count) textos no hi caben:\n\(problemes.joined(separator: "\n"))")
    }

    /// La regla de cada lloc: el que hi cap just, hi cap, i el que en passa, no.
    @Test func lesReglesDeMesura() {
        let llarg = Peca.text { String(repeating: "m ", count: 40) }
        #expect(Self.problema(Cas("prova", [.text { "abc" }], disponible: 100)) == nil)
        #expect(Self.problema(Cas("prova", [llarg], disponible: 100)) != nil)
        // Dues línies: un text de 1,5 amplades hi cap, i un de 3, no.
        let mig = Self.amplada(String(repeating: "m ", count: 40), .cos) / 1.5
        #expect(Self.problema(Cas("prova", [llarg], disponible: mig + 20, regla: .linies(2))) == nil)
        #expect(Self.problema(Cas("prova", [llarg], disponible: mig / 2, regla: .linies(2))) != nil)
        // Un desplegable que no hi cap: l'etiqueta, fins al 44 % de la fila.
        let ample = Peca.desplegable { [String(repeating: "m", count: 60)] }
        #expect(Self.problema(Cas("prova", [.text { String(repeating: "m", count: 8) }], disponible: 280,
                                  regla: .etiquetaDeDesplegable(ample))) == nil)
        #expect(Self.problema(Cas("prova", [.text { String(repeating: "m", count: 14) }], disponible: 280,
                                  regla: .etiquetaDeDesplegable(ample))) != nil)
        // El missatge diu el text, quant fa i quant n'hi ha.
        let missatge = Self.problema(Cas("prova", [.text { "Torna a deixar Warp com era" }, .boto { "Restaura Warp i surt…" }],
                                         separacio: Mides.separacio, disponible: 200))
        #expect(missatge?.hasPrefix("«Torna a deixar Warp com era» + «Restaura Warp i surt…» fa 343.3 pt") == true)
        #expect(missatge?.hasSuffix("pt, i hi ha 200.0 pt") == true)
    }
}
