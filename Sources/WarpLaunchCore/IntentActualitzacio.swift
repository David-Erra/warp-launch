import Foundation

/// El que recorda l'app d'una actualització que ha demanat aplicar (docs/disseny.md, secció 11, 2.3): `actualitzacio.json`, al
/// costat de la configuració i de `estat.json`. És de l'app, no de l'usuari, i amb `--config` no es llegeix mai.
///
/// Si la instal·lació falla quan l'app ja ha sortit, l'app no pot avisar. Només en tornar a arrencar pot veure que no s'ha
/// actualitzat, i no tornar-ho a provar sola: la icona desapareix com a molt una vegada per versió, i dues en total.
public struct IntentActualitzacio: Equatable, Sendable {
    public static let versioActual = 1
    public static let nomFitxer = "actualitzacio.json"

    public enum Tipus: String, Codable, Sendable {
        /// S'ha aplicat sola: en reobrir-se, sense cap finestra.
        case automatica
        /// L'ha demanada l'usuari: en reobrir-se, com sempre.
        case demanada
    }

    public struct Pendent: Equatable, Sendable, Codable {
        public var objectiu: String
        public var tipus: Tipus
        /// A segons sencers: és el que es desa.
        public var hora: Date

        public init(objectiu: String, tipus: Tipus, hora: Date) {
            self.objectiu = objectiu
            self.tipus = tipus
            self.hora = Date(timeIntervalSince1970: hora.timeIntervalSince1970.rounded(.down))
        }
    }

    public var versio: Int
    public var pendent: Pendent?
    public var fallades: Int
    public var versioFallada: String?

    public init(versio: Int = IntentActualitzacio.versioActual, pendent: Pendent? = nil, fallades: Int = 0, versioFallada: String? = nil) {
        self.versio = versio
        self.pendent = pendent
        self.fallades = fallades
        self.versioFallada = versioFallada
    }

    /// Si no es pot reiniciar sola per aplicar aquesta versió: és la que ha fallat, o n'han fallat massa.
    public func bloquejaAutomatic(candidat: String) -> Bool {
        candidat == versioFallada || fallades >= PoliticaActualitzacions.maximFallades
    }

    // MARK: - En arrencar

    /// Què s'ha trobat en arrencar.
    public enum Efecte: Equatable, Sendable {
        /// Sense fitxer o sense res pendent.
        case res
        case exit
        case fallada
        /// Fitxer mal format, o d'una versió més nova: com si no hi fos. El motiu és per al registre.
        case ignorat(String)
    }

    public struct Arrencada: Equatable, Sendable {
        /// S'ha reobert per una actualització, i de quin tipus: només si és una de les seves, i de fa poc.
        public var reobertura: Tipus?
        /// L'intent amb què ha de continuar l'app.
        public var intent: IntentActualitzacio
        public var efecte: Efecte
        /// No s'ha pogut desar el resultat: per al registre.
        public var errorDesant: String?
    }

    /// En arrencar: mira què hi havia pendent, ho treu i ho desa. Es fa una sola vegada per arrencada: una segona crida ja no hi
    /// trobaria res. Només amb la configuració de debò.
    /// - Parameter segonsEncesa: des que el Mac s'ha encès. Si l'intent és d'abans, el Mac s'ha reiniciat entremig: és l'inici de
    ///   sessió, encara que l'intent sigui de fa poc, i ha de sortir el full d'«Obre-ho tot».
    public static func enArrencar(magatzem: MagatzemIntent, versioActual: String, ara: Date, segonsEncesa: TimeInterval) -> Arrencada {
        let intent: IntentActualitzacio
        switch magatzem.carrega() {
        case .absent: return Arrencada(reobertura: nil, intent: IntentActualitzacio(), efecte: .res)
        case let .ignorat(motiu): return Arrencada(reobertura: nil, intent: IntentActualitzacio(), efecte: .ignorat(motiu))
        case let .llegit(llegit): intent = llegit
        }
        guard let actual = PoliticaActualitzacions.Versio(versioActual) else {
            return Arrencada(reobertura: nil, intent: intent, efecte: intent.pendent == nil ? .res : .ignorat("versió no vàlida"))
        }

        var nou = intent
        nou.pendent = nil
        var reobertura: Tipus?
        var efecte = Efecte.res
        if let pendent = intent.pendent {
            guard let objectiu = PoliticaActualitzacions.Versio(pendent.objectiu) else {
                return Arrencada(reobertura: nil, intent: intent, efecte: .ignorat("versió no vàlida"))
            }
            if actual >= objectiu {
                let passat = ara.timeIntervalSince(pendent.hora)
                let recent = passat >= -PoliticaActualitzacions.margeReoberturaEnrere && passat <= PoliticaActualitzacions.margeReobertura
                    && passat < segonsEncesa
                reobertura = recent ? pendent.tipus : nil
                nou.fallades = 0
                efecte = .exit
            } else {
                nou.fallades += 1
                nou.versioFallada = pendent.objectiu
                efecte = .fallada
            }
        }
        // L'app ja és a la versió que va fallar, o a una de més nova, també si s'hi ha arribat sense intent (en sortir, amb Homebrew
        // o a mà): si no, amb dues fallades no tornaria a reiniciar-se sola mai més.
        if let fallada = nou.versioFallada.flatMap({ PoliticaActualitzacions.Versio($0) }), actual >= fallada {
            nou.fallades = 0
            nou.versioFallada = nil
        }
        guard nou != intent else { return Arrencada(reobertura: nil, intent: intent, efecte: .res) }

        var errorDesant: String?
        do {
            try magatzem.desa(nou)
        } catch {
            errorDesant = "\(error)"
        }
        return Arrencada(reobertura: reobertura, intent: nou, efecte: efecte, errorDesant: errorDesant)
    }
}

// MARK: - JSON i disc

extension IntentActualitzacio {
    public enum Lectura: Equatable, Sendable {
        case absent
        case llegit(IntentActualitzacio)
        /// Mal format, o d'una versió més nova: com si no hi fos. El motiu és per al registre.
        case ignorat(String)
    }

    private struct Fitxer: Codable {
        var versio: Int
        var pendent: Pendent?
        var fallades: Int
        var versioFallada: String?
    }

    private struct NomesVersio: Decodable {
        var versio: Int
    }

    /// Llegeix i comprova el JSON.
    public static func llegeix(_ dades: Data) -> Lectura {
        guard let versio = try? JSONDecoder().decode(NomesVersio.self, from: dades).versio else {
            return .ignorat("no és JSON o no té «versio»")
        }
        guard versio <= versioActual else { return .ignorat("és de la versió \(versio), més nova que aquesta app (\(versioActual))") }
        guard versio >= 1 else { return .ignorat("versió \(versio) no vàlida") }
        let descodificador = JSONDecoder()
        descodificador.dateDecodingStrategy = .iso8601
        guard let fitxer = try? descodificador.decode(Fitxer.self, from: dades) else { return .ignorat("forma incorrecta") }
        guard fitxer.fallades >= 0 else { return .ignorat("«fallades» negatiu") }
        if let pendent = fitxer.pendent, PoliticaActualitzacions.Versio(pendent.objectiu) == nil { return .ignorat("«objectiu» no vàlid") }
        if let fallada = fitxer.versioFallada, PoliticaActualitzacions.Versio(fallada) == nil { return .ignorat("«versioFallada» no vàlida") }
        return .llegit(IntentActualitzacio(versio: versio, pendent: fitxer.pendent, fallades: fitxer.fallades, versioFallada: fitxer.versioFallada))
    }

    public func json() throws -> Data {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        var dades = try codificador.encode(Fitxer(versio: versio, pendent: pendent, fallades: fallades, versioFallada: versioFallada))
        dades.append(0x0A)
        return dades
    }
}

/// Llegeix i desa `actualitzacio.json` a la carpeta de la configuració. **No té ruta per defecte**, com `MagatzemEstat`: l'app hi
/// passa la seva carpeta, i les proves, una de temporal.
public struct MagatzemIntent: Sendable {
    public let carpeta: URL

    public init(carpeta: URL) {
        self.carpeta = carpeta
    }

    public var fitxer: URL { carpeta.appending(path: IntentActualitzacio.nomFitxer) }

    /// No escriu ni crea res.
    public func carrega() -> IntentActualitzacio.Lectura {
        let dades: Data
        do {
            dades = try Data(contentsOf: fitxer)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .absent
        } catch {
            return .ignorat("no s'ha pogut llegir: \(error.localizedDescription)")
        }
        return IntentActualitzacio.llegeix(dades)
    }

    public func desa(_ intent: IntentActualitzacio) throws {
        try EscripturaAtomica.escriu(try intent.json(), a: fitxer)
    }
}
