import Foundation

/// La finestra que Warp obre sola en arrencar (1.0.3, decisió d'en David del 14/11/2026, «fes-ho»): quan l'app engega Warp
/// amb l'URL de la primera finestra (`Peticio.arrencaWarp`, 1.0.1), Warp obre igualment la seva finestra per defecte, amb
/// una pestanya a la carpeta d'inici i res més (docs/fets-verificats.md, 14/11/2026). L'app la tanca acabant-ne el shell,
/// com si s'hi escrivís `exit`: Warp tanca la pestanya, i amb ella la finestra.
///
/// **Només quan l'app mateixa ha engegat Warp en aquesta acció**, i només amb totes les condicions de `tria`: amb qualsevol
/// dubte, no fa res, i el resultat diu que Warp ha obert també una finestra seva (`ExecucioObertura.finestraSeva`). Aquí
/// només hi ha la tria, pura i amb proves; el senyal l'envia `ObreWarp.acabaShellDeLaFinestraDeWarp` (WarpLaunchObridor), que
/// ho torna a comprovar just abans (`Candidat.encaraEs`).
public enum FinestraDeWarp {
    /// Fins quan, després que arrenqui Warp, pot haver començat el shell de la seva finestra, si la primera finestra de l'app
    /// encara no s'havia confirmat (o no s'ha confirmat mai).
    public static let margeArrencada: TimeInterval = 10
    /// Marge del rellotge entre el moment que l'app demana obrir l'URL i l'hora d'inici de l'app de Warp.
    public static let margeRellotge: TimeInterval = 1
    /// Els shells que es poden acabar, pel nom de l'executable (a més del de l'usuari, `SHELL`).
    public static let shells: Set<String> = ["zsh", "bash", "fish", "sh"]
    /// Mai aquests, encara que siguin el «shell» de l'usuari.
    static let mai: Set<String> = ["claude", "node"]

    /// Què se sap de l'acció, quan s'han acabat d'obrir totes les finestres.
    public struct Context: Equatable, Sendable {
        /// La carpeta d'inici, canònica.
        public var inici: String
        /// Quan l'app ha demanat obrir l'URL de la primera finestra, la que engega Warp.
        public var desDe: Date
        /// Quan s'ha vist la primera finestra, si s'ha vist.
        public var confirmada: Date?
        /// Els shells que l'app ha reconegut com a seus (`Confirmacio.perCarpeta` i `Confirmacio.shells`), de totes les finestres.
        public var nostres: Set<Int32>
        /// Quantes pestanyes s'han demanat a Warp, de totes les finestres: Warp en té una més, la de la seva finestra.
        public var pestanyes: Int
        /// Un dubte que ja es veu sense mirar els processos: llavors no es fa res.
        public var dubte: String?

        public init(inici: String, desDe: Date, confirmada: Date? = nil, nostres: Set<Int32> = [], pestanyes: Int,
                    dubte: String? = nil) {
            self.inici = inici
            self.desDe = desDe
            self.confirmada = confirmada
            self.nostres = nostres
            self.pestanyes = pestanyes
            self.dubte = dubte
        }
    }

    /// Un shell de Warp: un fill del `terminal-server` de l'app de Warp.
    public struct Shell: Equatable, Sendable {
        public var pid: Int32
        public var pare: Int32
        public var inici: IniciProces?
        /// Canònica.
        public var carpeta: String?
        public var executable: String?
        /// Quants processos fills té, de qualsevol usuari; `nil` si no es pot saber.
        public var fills: Int?

        public init(pid: Int32, pare: Int32, inici: IniciProces?, carpeta: String?, executable: String?, fills: Int?) {
            self.pid = pid
            self.pare = pare
            self.inici = inici
            self.carpeta = carpeta
            self.executable = executable
            self.fills = fills
        }
    }

    /// El Warp que corre: les seves apps (n'hi ha d'haver una), els seus `terminal-server` (un) i els shells.
    public struct Foto: Equatable, Sendable {
        /// L'hora d'inici de cada app de Warp (`nil`: no s'ha pogut llegir).
        public var apps: [IniciProces?]
        public var servidors: Int
        public var shells: [Shell]

        public init(apps: [IniciProces?], servidors: Int, shells: [Shell]) {
            self.apps = apps
            self.servidors = servidors
            self.shells = shells
        }
    }

    /// El shell que s'acabarà, i el que se n'ha de tornar a comprovar just abans.
    public struct Candidat: Equatable, Sendable {
        public var pid: Int32
        public var pare: Int32
        public var inici: IniciProces
        public var carpeta: String

        public init(pid: Int32, pare: Int32, inici: IniciProces, carpeta: String) {
            self.pid = pid
            self.pare = pare
            self.inici = inici
            self.carpeta = carpeta
        }

        /// Encara és el mateix procés (el pid no s'ha reutilitzat: mateixa hora d'inici i mateix pare), a la mateixa
        /// carpeta, i continua sense cap fill.
        public func encaraEs(_ processos: any FontProcessos) -> Bool {
            processos.inici(pid) == inici && processos.pare(pid) == pare
                && processos.carpeta(pid).map(Rutes.canonica) == carpeta && processos.nombreDeFills(pid) == 0
        }
    }

    public enum Resultat: Equatable, Sendable {
        /// S'ha enviat el senyal al shell de la finestra de Warp.
        case tancada(Int32)
        /// Warp no té cap terminal de més: no hi ha res a tancar ni a dir.
        case capFinestra
        /// No s'ha fet res, i per què (només per al registre).
        case dubte(String)
    }

    public enum Decisio: Equatable, Sendable {
        case acaba(Candidat)
        case no(Resultat)
    }

    /// El text del resultat, si n'hi ha: res si s'ha tancat o no n'hi havia cap; si no, que Warp n'ha obert una de seva.
    public static func text(_ resultat: Resultat) -> String? {
        if case .dubte = resultat { return ExecucioObertura.finestraSeva }
        return nil
    }

    /// El context d'una acció. `finestres`: cada finestra, en ordre (la primera és la que ha engegat Warp), amb les
    /// pestanyes que s'han demanat i el seu resultat (`nil`: no s'ha intentat). `inici`: la carpeta d'inici canònica.
    public static func context(_ finestres: [(pestanyes: [PestanyaAObrir], resultat: ExecucioObertura.Resultat?)],
                               inici: String) -> Context {
        guard let primera = finestres.first, case let .acabat(fet)? = primera.resultat, fet.llancament.estat != .error else {
            return Context(inici: inici, desDe: .distantPast, pestanyes: 0,
                           dubte: "la primera finestra no s'ha pogut obrir: Warp potser no l'ha engegat l'app")
        }
        var nostres = Set<Int32>()
        var pestanyes = 0
        var aLInici = false
        for finestra in finestres {
            guard case let .acabat(f)? = finestra.resultat, f.llancament.estat != .error else { continue }
            pestanyes += finestra.pestanyes.count
            if let vist = f.vist {
                nostres.formUnion(vist.perCarpeta.values)
                nostres.formUnion(vist.shells.values.map(\.pid))
            }
            if finestra.pestanyes.contains(where: { Rutes.canonica($0.yaml.carpeta) == inici }) { aLInici = true }
        }
        let confirmada = fet.finestra ? fet.llancament.segons.map { fet.desDe.addingTimeInterval($0) } : nil
        return Context(inici: inici, desDe: fet.desDe, confirmada: confirmada, nostres: nostres, pestanyes: pestanyes,
                       dubte: aLInici ? "alguna pestanya de l'app és a la carpeta d'inici, com la de Warp" : nil)
    }

    /// Si l'executable és un shell: el de l'usuari (`SHELL`) o un de `shells`, i mai `claude` ni `node`.
    static func esShell(_ executable: String, usuari: String?) -> Bool {
        let nom = (executable as NSString).lastPathComponent
        guard !mai.contains(nom), !executable.contains("/claude"), !executable.contains("/node") else { return false }
        return shells.contains(nom) || (usuari.map { !$0.isEmpty && $0 == executable } ?? false)
    }

    static func data(_ inici: IniciProces) -> Date {
        Date(timeIntervalSince1970: TimeInterval(inici.segons) + TimeInterval(inici.microsegons) / 1_000_000)
    }

    /// Quin shell s'ha d'acabar, si n'hi ha un sense cap dubte. Totes les condicions alhora:
    /// - cap dubte del context (la primera finestra s'ha obert, cap pestanya de l'app a la carpeta d'inici);
    /// - una sola app de Warp, que ha arrencat després que l'app demanés l'URL, i un sol `terminal-server`;
    /// - Warp té exactament un terminal més que les pestanyes demanades, i només un dels que no són dels reconeguts (ni fills
    ///   seus) és a la carpeta d'inici (o no se'n sap la carpeta): aquest, fill del `terminal-server`, a l'inici, sense cap
    ///   fill, i un shell (`esShell`);
    /// - va començar després que arrenqués Warp, i abans de la confirmació de la primera finestra o, si és més tard, dels
    ///   primers `margeArrencada` segons de Warp.
    public static func tria(_ foto: Foto, _ context: Context, shellUsuari: String?) -> Decisio {
        if let dubte = context.dubte { return .no(.dubte(dubte)) }
        guard foto.apps.count == 1, let iniciWarp = foto.apps[0] else {
            return .no(.dubte("\(foto.apps.count) apps de Warp, o sense l'hora d'inici"))
        }
        let warp = data(iniciWarp)
        guard warp >= context.desDe.addingTimeInterval(-margeRellotge) else {
            return .no(.dubte("Warp ja era obert abans de demanar l'URL"))
        }
        guard foto.servidors == 1 else { return .no(.dubte("\(foto.servidors) terminal-server")) }
        if foto.shells.count == context.pestanyes { return .no(.capFinestra) }
        guard foto.shells.count == context.pestanyes + 1 else {
            return .no(.dubte("\(foto.shells.count) terminals per \(context.pestanyes) pestanyes"))
        }
        // Els de l'app reconeguts per la marca (amb Claude) no tenen el pid al context, però no són a l'inici (`dubte`) i
        // tenen fills. Un shell sense carpeta coneguda també compta, per prudència.
        let desconeguts = foto.shells.filter { !context.nostres.contains($0.pid) && !context.nostres.contains($0.pare) }
        let aLInici = desconeguts.filter { $0.carpeta == nil || $0.carpeta == context.inici }
        guard aLInici.count == 1, let shell = aLInici.first, let carpeta = shell.carpeta else {
            return .no(.dubte("\(aLInici.count) terminals a la carpeta d'inici que no són de l'app, o sense carpeta"))
        }
        let pid = shell.pid
        guard shell.fills == 0 else { return .no(.dubte("el terminal \(pid) té processos fills, o no se sap")) }
        guard let executable = shell.executable, esShell(executable, usuari: shellUsuari) else {
            return .no(.dubte("el terminal \(pid) no és un shell"))
        }
        guard let inici = shell.inici else { return .no(.dubte("el terminal \(pid) no té hora d'inici")) }
        let comenca = data(inici)
        let fins = max(context.confirmada ?? .distantPast, warp.addingTimeInterval(margeArrencada))
        guard comenca >= warp, comenca <= fins else {
            return .no(.dubte("el terminal \(pid) no va començar en arrencar Warp"))
        }
        return .acaba(Candidat(pid: pid, pare: shell.pare, inici: inici, carpeta: carpeta))
    }

    /// Tria el shell i, si n'hi ha un, el fa acabar (`acaba`, `ObreWarp.acabaShellDeLaFinestraDeWarp`). Amb un dubte del
    /// context, ni mira els processos (`foto`).
    public static func tanca(_ context: Context, foto: () -> Foto, shellUsuari: String?,
                             acaba: (Candidat) -> Resultat) -> Resultat {
        if let dubte = context.dubte { return .dubte(dubte) }
        switch tria(foto(), context, shellUsuari: shellUsuari) {
        case let .acaba(candidat): return acaba(candidat)
        case let .no(resultat): return resultat
        }
    }
}

extension FontProcessos {
    /// La foto per triar el shell de la finestra de Warp (`FinestraDeWarp.tria`): les apps de Warp (el binari
    /// `executable`, sense arguments), els seus `terminal-server` i els fills d'aquests, amb l'hora d'inici, la carpeta,
    /// l'executable i quants fills té cadascun. Només llegeix.
    public func fotoFinestraDeWarp(executable: String) -> FinestraDeWarp.Foto {
        let tots = processos(executable: executable)
        let apps = tots.filter { $0.info.argv.count <= 1 }
        let pidsApps = Set(apps.map(\.pid))
        let servidors = tots.filter { $0.info.argv.contains("terminal-server") && pare($0.pid).map(pidsApps.contains) == true }
        let arbre = fills()
        let shells = servidors.flatMap { servidor in
            (arbre[servidor.pid] ?? []).sorted().map { pid in
                FinestraDeWarp.Shell(pid: pid, pare: servidor.pid, inici: inici(pid), carpeta: carpeta(pid).map(Rutes.canonica),
                                     executable: proces(pid)?.executable, fills: nombreDeFills(pid))
            }
        }
        return FinestraDeWarp.Foto(apps: apps.map { inici($0.pid) }, servidors: servidors.count, shells: shells)
    }
}
