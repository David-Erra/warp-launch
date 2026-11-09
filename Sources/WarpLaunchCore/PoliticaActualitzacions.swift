import Foundation

/// Quan es pot actualitzar l'app i quan no (docs/disseny.md, secció 11, 2.2 i 2.4). Només decisions, sense cap efecte: el model
/// `Actualitzacions` les aplica, i el servei hi posa les dades de debò. Aquí no hi ha res de l'actualitzador ni cap adreça.
public enum PoliticaActualitzacions {
    /// Automàtic: quant de temps seguit sense cap motiu per esperar.
    public static let quietud: TimeInterval = 60
    /// Sense teclat ni ratolí, per poder reiniciar sola (decisió 2 de Sparkle).
    public static let inactivitatMinima: TimeInterval = 120
    /// Quant ha de fer que corre l'app: no es barreja amb l'inici de sessió.
    public static let minimEnMarxa: TimeInterval = 300
    /// Passat aquest temps amb l'app viva després de demanar d'aplicar-la, s'ha cancel·lat.
    public static let tempsAplicant: TimeInterval = 60
    public static let pausaEntreIntents: TimeInterval = 3600
    public static let maximIntents = 3
    /// Un Desfés de fa menys d'aquesta estona es perdria en reiniciar.
    public static let limitDesfes: TimeInterval = 3600
    /// Fins quan després d'escriure l'intent una arrencada compta com la reobertura de l'actualització.
    public static let margeReobertura: TimeInterval = 300
    /// El rellotge pot haver anat una mica enrere: una hora d'aquests segons endavant també compta.
    public static let margeReoberturaEnrere: TimeInterval = 5
    /// El menú avisa que una versió fa dies que és a punt (decisió 5 de Sparkle).
    public static let diesAvis = 7
    /// Límit de «Comprovant…», per si l'actualitzador no respon mai.
    public static let tempsComprovant: TimeInterval = 180
    public static let carpetaAplicacions = "/Applications/"
    /// Quantes fallades, de versions diferents, aturen els reinicis sols (2.3).
    public static let maximFallades = 2
    /// Codi de l'actualitzador quan no hi ha res de nou: no és cap error.
    public static let codiSenseNovetats = 1001
    /// Codi de l'actualitzador quan s'ha cancel·lat la instal·lació: no és cap error.
    public static let codiInstallacioCancellada = 4007

    // MARK: - Per què s'espera

    /// Per què no es reinicia ara. L'ordre dels casos és el de la decisió: `motiuEspera` torna el primer que es compleix.
    public enum Motiu: String, CaseIterable, Sendable {
        case errorEnDesar, nomAMigEscriure, obrint, fullObert, conversesEnCurs, refrescant, ajustPerDesactivar
        case finestraVisible, canvisSenseDesar, desfesRecent, acabaDArrencar, macEnUs, installacioFallida

        /// També atura «Reinicia i actualitza»: si no, es perdria alguna cosa o quedaria a mitges.
        public var valTambeDemanat: Bool {
            switch self {
            case .errorEnDesar, .nomAMigEscriure, .obrint, .fullObert, .conversesEnCurs, .refrescant, .ajustPerDesactivar: true
            case .finestraVisible, .canvisSenseDesar, .desfesRecent, .acabaDArrencar, .macEnUs, .installacioFallida: false
            }
        }

        /// El que va després de «Ara no: ».
        public var text: String {
            switch self {
            case .errorEnDesar: "no s'ha pogut desar la configuració"
            case .nomAMigEscriure: "estàs canviant un nom"
            case .obrint: "s'estan obrint finestres a Warp"
            case .fullObert: "hi ha un full obert"
            case .conversesEnCurs: "encara s'estan reprenent converses a Warp"
            case .refrescant: "s'està llegint Warp"
            case .ajustPerDesactivar: "falta desactivar la restauració de sessió de Warp"
            case .finestraVisible: "hi ha una finestra de l'app oberta"
            case .canvisSenseDesar: "hi ha canvis sense desar"
            case .desfesRecent: "encara pots desfer l'últim canvi"
            case .acabaDArrencar: "l'app s'acaba d'obrir"
            case .macEnUs: "estàs fent servir el Mac"
            case .installacioFallida: "aquesta versió no s'ha pogut instal·lar sola"
            }
        }
    }

    /// El primer motiu per no reiniciar ara, o `nil` si es pot. `demanat`: l'ha demanat l'usuari amb el botó.
    public static func motiuEspera(_ situacio: SituacioApp, demanat: Bool) -> Motiu? {
        Motiu.allCases.first { (!demanat || $0.valTambeDemanat) && situacio.compleix($0) }
    }

    // MARK: - Per què no s'actualitza mai

    /// Com és aquesta còpia de l'app. Ho calcula el servei amb les dades del paquet.
    public struct Paquet: Equatable, Sendable {
        public enum Arguments: Equatable, Sendable {
            case normals
            /// `--config <carpeta>`.
            case deProva
            /// Arguments que l'app no entén, i per tant sense configuració.
            case incorrectes
        }

        public var arguments: Arguments
        /// La ruta del paquet que corre.
        public var ruta: String
        /// L'identificador del paquet; `nil` en un binari sol.
        public var identificador: String?
        /// Porta l'adreça de les actualitzacions: només si s'ha compilat per publicar (decisió 3 de Sparkle).
        public var teFeed: Bool
        public var potEscriure: Bool
        /// El propietari del paquet és l'usuari que corre l'app.
        public var esDeLUsuari: Bool
        public var actualitzadorCompatible: Bool

        public init(arguments: Arguments, ruta: String, identificador: String?, teFeed: Bool, potEscriure: Bool, esDeLUsuari: Bool,
                    actualitzadorCompatible: Bool) {
            self.arguments = arguments
            self.ruta = ruta
            self.identificador = identificador
            self.teFeed = teFeed
            self.potEscriure = potEscriure
            self.esDeLUsuari = esDeLUsuari
            self.actualitzadorCompatible = actualitzadorCompatible
        }
    }

    /// Per què aquesta còpia no s'actualitza mai. Amb motiu, no es crea el servei.
    public enum NoDisponible: Equatable, Sendable {
        case configuracioDeProva, senseConfiguracio, foraDeLPaquet
        case foraDAplicacions(String)
        case senseFeed, dUnAltreUsuari, incompatible

        public var text: String {
            switch self {
            case .configuracioDeProva: "Amb una configuració de prova, l'app no s'actualitza."
            case .senseConfiguracio: "Sense configuració, l'app no s'actualitza."
            case .foraDeLPaquet: "Només s'actualitza l'app instal·lada."
            case let .foraDAplicacions(ruta): "Per actualitzar-se sola, l'app ha de ser a Aplicacions. Ara és a \(ruta)."
            case .senseFeed: "Aquesta còpia no és una versió publicada i no s'actualitza sola."
            case .dUnAltreUsuari: "Aquesta còpia la va instal·lar un altre usuari del Mac: l'ha d'actualitzar ell."
            case .incompatible: "Aquesta versió de l'actualitzador no és compatible."
            }
        }

        /// Per a l'informe del diagnòstic, que és en anglès.
        public var diagnostic: String {
            switch self {
            case .configuracioDeProva: "test configuration (--config)"
            case .senseConfiguracio: "no configuration"
            case .foraDeLPaquet: "not running from an app bundle"
            case let .foraDAplicacions(ruta): "not in /Applications (\(ruta))"
            case .senseFeed: "not a published build (no feed)"
            case .dUnAltreUsuari: "the app belongs to another user or isn't writable"
            case .incompatible: "incompatible updater"
            }
        }
    }

    public static func motiuNoDisponible(_ paquet: Paquet) -> NoDisponible? {
        switch paquet.arguments {
        case .deProva: return .configuracioDeProva
        case .incorrectes: return .senseConfiguracio
        case .normals: break
        }
        guard paquet.ruta.hasSuffix(".app"), paquet.identificador != nil else { return .foraDeLPaquet }
        guard paquet.ruta.hasPrefix(carpetaAplicacions) else { return .foraDAplicacions(paquet.ruta) }
        guard paquet.teFeed else { return .senseFeed }
        guard paquet.potEscriure, paquet.esDeLUsuari else { return .dUnAltreUsuari }
        guard paquet.actualitzadorCompatible else { return .incompatible }
        return nil
    }

    // MARK: - El que arriba de fora

    /// Si l'adreça del fitxer de la versió és on toca: la carpeta de l'adreça del feed, amb el pas de l'última versió canviat pel
    /// de les baixades. L'appcast no va signat: una adreça de fora, o que surti de la carpeta amb `..`, es refusa.
    public static func enclosureValid(feed: String, enclosure: String) -> Bool {
        guard let final = feed.range(of: "/", options: .backwards), !feed[final.upperBound...].isEmpty else { return false }
        let carpeta = String(feed[..<final.upperBound])
            .replacingOccurrences(of: "/releases/latest/download/", with: "/releases/download/")
        guard carpeta.contains("://"), enclosure.hasPrefix(carpeta) else { return false }
        let resta = enclosure.dropFirst(carpeta.count)
        guard !resta.isEmpty, resta.unicodeScalars.allSatisfy(caractersDeRuta.contains) else { return false }
        return resta.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Lletres, xifres i poca cosa més. Ni `%`, ni `?`, ni `#`, ni `@`, ni `\`: res que pugui canviar on porta l'adreça.
    private static let caractersDeRuta = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/")

    /// Si un error de l'actualitzador s'ha de dir a l'usuari. Sense novetats o amb una instal·lació cancel·lada, no.
    public static func esErrorVisible(codi: Int) -> Bool {
        codi != codiSenseNovetats && codi != codiInstallacioCancellada
    }

    // MARK: - Versions

    /// Una versió de tres enters: `0.31.10`. Qualsevol altra forma no és vàlida.
    public struct Versio: Comparable, Sendable {
        let parts: [Int]

        public init?(_ text: String) {
            let trossos = text.split(separator: ".", omittingEmptySubsequences: false)
            guard trossos.count == 3 else { return nil }
            var parts: [Int] = []
            for tros in trossos {
                guard !tros.isEmpty, tros.utf8.allSatisfy({ (48...57).contains($0) }), let valor = Int(tros) else { return nil }
                parts.append(valor)
            }
            self.parts = parts
        }

        public static func < (a: Versio, b: Versio) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
    }
}

/// El que cal saber de l'app per decidir si es pot reiniciar (`PoliticaActualitzacions.motiuEspera`).
public struct SituacioApp: Equatable, Sendable {
    /// El que diuen els models de l'app (l'editor, l'obertura, l'ajust de Warp i les finestres).
    public struct Models: Equatable, Sendable {
        public var errorEnDesar: Bool
        public var nomAMigEscriure: Bool
        public var obrint: Bool
        public var fullObert: Bool
        public var conversesEnCurs: Bool
        public var refrescant: Bool
        public var ajustPerDesactivar: Bool
        public var finestraVisible: Bool
        public var canvisSenseDesar: Bool
        /// L'editor o la plantilla tenen algun pas per desfer.
        public var potDesfer: Bool
        /// Quant fa de l'últim canvi, segons el rellotge; `nil` si no n'hi ha cap en aquesta sessió. Negatiu si el rellotge ha anat enrere.
        public var segonsDesDelDarrerCanvi: TimeInterval?

        public init(errorEnDesar: Bool, nomAMigEscriure: Bool, obrint: Bool, fullObert: Bool, conversesEnCurs: Bool, refrescant: Bool,
                    ajustPerDesactivar: Bool, finestraVisible: Bool, canvisSenseDesar: Bool, potDesfer: Bool,
                    segonsDesDelDarrerCanvi: TimeInterval?) {
            self.errorEnDesar = errorEnDesar
            self.nomAMigEscriure = nomAMigEscriure
            self.obrint = obrint
            self.fullObert = fullObert
            self.conversesEnCurs = conversesEnCurs
            self.refrescant = refrescant
            self.ajustPerDesactivar = ajustPerDesactivar
            self.finestraVisible = finestraVisible
            self.canvisSenseDesar = canvisSenseDesar
            self.potDesfer = potDesfer
            self.segonsDesDelDarrerCanvi = segonsDesDelDarrerCanvi
        }
    }

    public var models: Models
    public var segonsEnMarxa: TimeInterval
    public var segonsInactiu: TimeInterval
    /// La versió que espera ja ha fallat, o n'han fallat massa (`IntentActualitzacio.bloquejaAutomatic`).
    public var installacioFallida: Bool

    public init(models: Models, segonsEnMarxa: TimeInterval, segonsInactiu: TimeInterval, installacioFallida: Bool) {
        self.models = models
        self.segonsEnMarxa = segonsEnMarxa
        self.segonsInactiu = segonsInactiu
        self.installacioFallida = installacioFallida
    }

    func compleix(_ motiu: PoliticaActualitzacions.Motiu) -> Bool {
        switch motiu {
        case .errorEnDesar: models.errorEnDesar
        case .nomAMigEscriure: models.nomAMigEscriure
        case .obrint: models.obrint
        case .fullObert: models.fullObert
        case .conversesEnCurs: models.conversesEnCurs
        case .refrescant: models.refrescant
        case .ajustPerDesactivar: models.ajustPerDesactivar
        case .finestraVisible: models.finestraVisible
        case .canvisSenseDesar: models.canvisSenseDesar
        case .desfesRecent:
            // En valor absolut: si el rellotge ha anat molt enrere, no pot bloquejar fins que torni a arribar a aquella hora.
            models.potDesfer && (models.segonsDesDelDarrerCanvi.map { abs($0) < PoliticaActualitzacions.limitDesfes } ?? false)
        case .acabaDArrencar: segonsEnMarxa < PoliticaActualitzacions.minimEnMarxa
        case .macEnUs: segonsInactiu < PoliticaActualitzacions.inactivitatMinima
        case .installacioFallida: installacioFallida
        }
    }
}
