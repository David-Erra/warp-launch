import Foundation

/// L'única peça que escriu i esborra a la carpeta de launch configurations de Warp (fase 3.1, D5; docs/disseny.md,
/// secció 7, «Fitxer temporal»). Només hi toca els seus fitxers: `warp-launch-<uuid>.yaml`, que comencen amb la marca.
/// Mai els d'en David (les `espai-*.yaml` ni cap altre). La carpeta només la crea si qui escriu ho demana (`escriu`).
public struct FitxersLaunchWarp: Sendable {
    /// La carpeta. A les proves, una de temporal.
    public let carpeta: URL

    public init(carpeta: URL) {
        self.carpeta = carpeta
    }

    /// La de debò: l'única que llegeix Warp, també amb `--config`.
    public static var real: FitxersLaunchWarp {
        FitxersLaunchWarp(carpeta: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".warp/launch_configurations", directoryHint: .isDirectory))
    }

    /// En arrencar, quant ha de tenir un fitxer propi que no és a `estat.json` perquè s'esborri.
    public static let edatPerNetejar: TimeInterval = 2 * 60

    public enum ErrorFitxers: Error, Equatable, CustomStringConvertible {
        /// La carpeta no hi és, o no és una carpeta, i no s'ha creat: no es podia (`~/.warp` no hi és, o el camí passa per un
        /// enllaç o un fitxer) o no s'havia de fer (`--config`, sense el permís o `warp-launch obre --obre`).
        case senseCarpeta
        /// Ja hi ha un fitxer amb aquest nom: no se sobreescriu mai.
        case jaExisteix
        case escriptura(String)
        /// Hi ha alguna cosa amb el nom, però no és un fitxer normal (un enllaç, una carpeta…): no s'esborra.
        case noEsUnFitxer
        /// El fitxer no fa el que es va escriure: algú l'ha canviat, i no s'esborra.
        case midaDiferent(esperada: Int, trobada: Int)
        /// La primera línia no és la marca del llançament: no és el fitxer de l'app, i no s'esborra.
        case senseMarca
        case lectura(String)
        case esborrat(String)

        public var description: String {
            switch self {
            case .senseCarpeta: t("Warp no té la carpeta de launch configurations, i no s'ha creat: pot ser que Warp encara no s'hagi obert mai, que el camí passi per un enllaç o un fitxer, o que sigui una prova amb --config o el CLI, que no la creen")
            case .jaExisteix: t("ja hi ha un fitxer amb aquest nom, i no se sobreescriu")
            case let .escriptura(error): t("no s'ha pogut escriure el fitxer: \(error)")
            case .noEsUnFitxer: t("no és un fitxer normal, i no s'esborra")
            case let .midaDiferent(esperada, trobada):
                t("fa \(trobada) bytes i se n'havien escrit \(esperada): algú l'ha canviat, i no s'esborra")
            case .senseMarca: t("no comença amb la marca de l'app, i no s'esborra")
            case let .lectura(error): t("no s'ha pogut llegir: \(error)")
            case let .esborrat(error): t("no s'ha pogut esborrar: \(error)")
            }
        }
    }

    public enum Esborrat: Sendable, Equatable {
        case esborrat
        /// No hi era (ja s'havia esborrat).
        case noHiEra
    }

    // MARK: - Escriure

    /// Escriu el fitxer d'un llançament, i en retorna la mida (bytes). Només si no n'hi ha cap amb el mateix nom
    /// (`O_EXCL`); 0644 i sincronitzat abans de tornar, perquè Warp el trobi sencer.
    /// - Parameter creaCarpeta: si la carpeta no hi és, la crea (decisió d'en David del 09/11/2026, regla 7: només l'app, amb
    ///   la carpeta de debò i el permís; `ExecucioObertura.Entorn.potCrearCarpeta`).
    public func escriu(_ fitxer: FitxerLaunch, creaCarpeta: Bool = false) throws(ErrorFitxers) -> Int {
        if !esCarpeta() {
            guard creaCarpeta, creaLaCarpeta() else { throw .senseCarpeta }
        }
        let dades = Data(fitxer.text.utf8)
        let ruta = carpeta.appending(path: fitxer.nomFitxer).path
        let fd = open(ruta, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else {
            throw errno == EEXIST ? .jaExisteix : .escriptura(String(cString: strerror(errno)))
        }
        var error: String?
        if fchmod(fd, 0o644) != 0 {
            error = String(cString: strerror(errno))
        } else if !escriuTot(dades, a: fd) {
            error = String(cString: strerror(errno))
        } else if fsync(fd) != 0 {
            error = String(cString: strerror(errno))
        }
        if let error {
            // A mig escriure: és el fitxer que s'acaba de crear (el mateix inode), i es treu.
            var creat = stat()
            var ara = stat()
            if fstat(fd, &creat) == 0, lstat(ruta, &ara) == 0, creat.st_ino == ara.st_ino, creat.st_dev == ara.st_dev {
                _ = treu(fitxer.nomFitxer)
            }
            close(fd)
            throw .escriptura(error)
        }
        guard close(fd) == 0 else { throw .escriptura(String(cString: strerror(errno))) }
        return dades.count
    }

    /// La carpeta, un sol nivell: el pare (`~/.warp`) ha de ser una carpeta de debò, ni un enllaç (es crearia a una altra banda)
    /// ni un fitxer, i no el crea mai. Si el camí ja és un fitxer o un enllaç, encara que sigui trencat, la crida falla, i no s'hi
    /// toca res. Si ja hi és una carpeta de debò, només pot ser que Warp l'hagi creada just ara.
    private func creaLaCarpeta() -> Bool {
        guard esCarpetaDeDebo(carpeta.deletingLastPathComponent().path) else { return false }
        guard mkdir(carpeta.path, mode_t(0o755)) != 0 else { return true }
        return errno == EEXIST && esCarpetaDeDebo(carpeta.path)
    }

    /// Sense seguir enllaços, a diferència de `esCarpeta`.
    private func esCarpetaDeDebo(_ ruta: String) -> Bool {
        var info = stat()
        return lstat(ruta, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private func escriuTot(_ dades: Data, a fd: Int32) -> Bool {
        dades.withUnsafeBytes { bytes in
            var escrits = 0
            while escrits < bytes.count {
                let n = write(fd, bytes.baseAddress! + escrits, bytes.count - escrits)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { return false }
                escrits += n
            }
            return true
        }
    }

    // MARK: - Esborrar

    /// Esborra el fitxer d'un llançament, només si és el que l'app va escriure: nom propi, fitxer normal (no un
    /// enllaç) a la carpeta, amb la marca del llançament a la primera línia i la mida que es va escriure.
    public func esborra(llancament: UUID, mida: Int) throws(ErrorFitxers) -> Esborrat {
        try esborra(nomFitxer: FitxerLaunch.nomFitxer(llancament), llancament: llancament, mida: mida)
    }

    private func esborra(nomFitxer: String, llancament: UUID, mida: Int?) throws(ErrorFitxers) -> Esborrat {
        guard LaunchConfigWarp.esNomPropi(nomFitxer) else { throw .senseMarca }
        let ruta = carpeta.appending(path: nomFitxer).path
        var info = stat()
        guard lstat(ruta, &info) == 0 else {
            if errno == ENOENT { return .noHiEra }
            throw .lectura(String(cString: strerror(errno)))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .noEsUnFitxer }
        if let mida, Int(info.st_size) != mida { throw .midaDiferent(esperada: mida, trobada: Int(info.st_size)) }
        guard try comencaAmbLaMarca(ruta, llancament: llancament) else { throw .senseMarca }
        guard treu(nomFitxer) else {
            if errno == ENOENT { return .noHiEra }
            throw .esborrat(String(cString: strerror(errno)))
        }
        return .esborrat
    }

    /// L'única crida que esborra.
    private func treu(_ nomFitxer: String) -> Bool {
        unlink(carpeta.appending(path: nomFitxer).path) == 0
    }

    private func comencaAmbLaMarca(_ ruta: String, llancament: UUID) throws(ErrorFitxers) -> Bool {
        let esperada = Array((LaunchConfigWarp.marca(llancament) + "\n").utf8)
        let fd = open(ruta, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw .lectura(String(cString: strerror(errno))) }
        defer { close(fd) }
        var llegits = [UInt8](repeating: 0, count: esperada.count)
        var total = 0
        while total < esperada.count {
            let n = llegits.withUnsafeMutableBytes { read(fd, $0.baseAddress! + total, esperada.count - total) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            total += n
        }
        return total == esperada.count && llegits == esperada
    }

    // MARK: - Netejar

    /// En arrencar l'app: esborra els fitxers dels llançaments que `estat.json` no dona per esborrats (amb totes les
    /// comprovacions), i qualsevol altre fitxer propi amb la marca que faci més de 2 min que es va escriure. El
    /// resultat va per llançament (l'id del nom), per posar-lo al dia a `estat.json` i al registre.
    public func neteja(llancaments: [Llancament], ara: Date) -> [UUID: Result<Esborrat, ErrorFitxers>] {
        var resultats: [UUID: Result<Esborrat, ErrorFitxers>] = [:]
        for llancament in llancaments where !llancament.esborrat {
            resultats[llancament.id] = Result { () throws(ErrorFitxers) in
                try esborra(llancament: llancament.id, mida: llancament.mida)
            }
        }
        guard esCarpeta(), let noms = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else {
            return resultats
        }
        for nom in noms.sorted() where LaunchConfigWarp.esNomPropi(nom) {
            guard let id = FitxerLaunch.llancament(deNomFitxer: nom), resultats[id] == nil else { continue }
            var info = stat()
            guard lstat(carpeta.appending(path: nom).path, &info) == 0 else { continue }
            let modificat = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard ara.timeIntervalSince(modificat) > Self.edatPerNetejar else { continue }
            resultats[id] = Result { () throws(ErrorFitxers) in
                try esborra(nomFitxer: nom, llancament: id, mida: nil)
            }
        }
        return resultats
    }

    private func esCarpeta() -> Bool {
        var esCarpeta: ObjCBool = false
        return FileManager.default.fileExists(atPath: carpeta.path, isDirectory: &esCarpeta) && esCarpeta.boolValue
    }
}

extension FitxerLaunch {
    /// `warp-launch-<llançament en minúscules>.yaml`.
    static func nomFitxer(_ llancament: UUID) -> String {
        LaunchConfigWarp.prefix + llancament.uuidString.lowercased() + ".yaml"
    }

    /// El llançament d'un nom de fitxer propi; `nil` si no ho és.
    static func llancament(deNomFitxer nom: String) -> UUID? {
        guard LaunchConfigWarp.esNomPropi(nom) else { return nil }
        return UUID(uuidString: String(nom.dropFirst(LaunchConfigWarp.prefix.count).dropLast(".yaml".count)))
    }
}
