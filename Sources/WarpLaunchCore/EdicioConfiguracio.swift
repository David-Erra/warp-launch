import Foundation

/// Les operacions d'edició de la configuració (docs/disseny.md, «Ordres»). Són pures: no desen ni registren el
/// Desfés, que és cosa de l'`Editor`. Els id que no hi són s'ignoren.
extension Configuracio {
    public func finestra(_ id: Finestra.ID) -> Finestra? {
        finestres.first { $0.id == id }
    }

    public func pestanya(_ id: Pestanya.ID) -> Pestanya? {
        finestres.lazy.flatMap(\.pestanyes).first { $0.id == id }
    }

    /// La finestra on és una pestanya.
    public func finestra(dePestanya id: Pestanya.ID) -> Finestra.ID? {
        finestres.first { $0.pestanyes.contains { $0.id == id } }?.id
    }

    /// `base`, o `base 2`, `base 3`… si ja hi ha una finestra amb aquest nom (sense distingir majúscules).
    public func nomUnic(_ base: String) -> String {
        let usats = Set(finestres.map { Validacio.clauDeNom($0.nom) })
        if !usats.contains(Validacio.clauDeNom(base)) { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !usats.contains(Validacio.clauDeNom($0)) }!
    }

    // MARK: - Finestres

    /// Afegeix una finestra després de `despresDe`, o al final.
    public mutating func afegeix(_ finestra: Finestra, despresDe: Finestra.ID? = nil) {
        let index = despresDe.flatMap { id in finestres.firstIndex { $0.id == id } }.map { $0 + 1 } ?? finestres.count
        finestres.insert(finestra, at: index)
    }

    /// Elimina una finestra i en torna la posició.
    @discardableResult
    public mutating func eliminaFinestra(_ id: Finestra.ID) -> Int? {
        guard let index = finestres.firstIndex(where: { $0.id == id }) else { return nil }
        finestres.remove(at: index)
        return index
    }

    /// Canvia el nom d'una finestra. Un nom buit (o només d'espais) no es posa.
    public mutating func reanomenaFinestra(_ id: Finestra.ID, a nom: String) {
        guard !nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = finestres.firstIndex(where: { $0.id == id })
        else { return }
        finestres[index].nom = nom
    }

    /// Mou finestres a una posició de la llista, en l'ordre en què hi són.
    /// - Parameter index: la posició **abans** de treure les que es mouen, com `move(fromOffsets:toOffset:)` (el que
    ///   dona `onMove` a la barra lateral).
    public mutating func mouFinestres(_ ids: Set<Finestra.ID>, a index: Int) {
        let mogudes = finestres.filter { ids.contains($0.id) }
        guard !mogudes.isEmpty else { return }
        let posicio = min(max(index, 0), finestres.count)
        let abansDeLaPosicio = finestres.prefix(posicio).filter { ids.contains($0.id) }.count
        finestres.removeAll { ids.contains($0.id) }
        finestres.insert(contentsOf: mogudes, at: posicio - abansDeLaPosicio)
    }

    /// Una còpia de la finestra just després, amb id nous, el nom «X còpia» i les pestanyes sense nom fix de sessió
    /// (dues sessions amb el mateix nom es confondrien). En torna l'id.
    public mutating func duplicaFinestra(_ id: Finestra.ID, nouId: () -> UUID) -> Finestra.ID? {
        guard let original = finestra(id) else { return nil }
        let copia = Finestra(id: nouId(), nom: nomUnic(t("\(original.nom) còpia")),
                             pestanyes: original.pestanyes.map { $0.duplicada(id: nouId()) })
        afegeix(copia, despresDe: id)
        return copia.id
    }

    // MARK: - Pestanyes

    /// Afegeix una pestanya a una finestra, a la posició `index` o al final.
    public mutating func afegeix(_ pestanya: Pestanya, a finestra: Finestra.ID, index: Int? = nil) {
        guard let f = finestres.firstIndex(where: { $0.id == finestra }) else { return }
        let total = finestres[f].pestanyes.count
        finestres[f].pestanyes.insert(pestanya, at: min(max(index ?? total, 0), total))
    }

    public mutating func eliminaPestanyes(_ ids: Set<Pestanya.ID>) {
        for f in finestres.indices { finestres[f].pestanyes.removeAll { ids.contains($0.id) } }
    }

    /// Còpies de les pestanyes, cadascuna just després de l'última de les duplicades de la seva finestra, en ordre,
    /// amb id nous i sense nom fix de sessió. En torna els id nous.
    public mutating func duplicaPestanyes(_ ids: Set<Pestanya.ID>, nouId: () -> UUID) -> [Pestanya.ID] {
        var noves: [Pestanya.ID] = []
        for f in finestres.indices {
            let originals = finestres[f].pestanyes.filter { ids.contains($0.id) }
            guard let darrera = finestres[f].pestanyes.lastIndex(where: { ids.contains($0.id) }) else { continue }
            let copies = originals.map { $0.duplicada(id: nouId()) }
            finestres[f].pestanyes.insert(contentsOf: copies, at: darrera + 1)
            noves += copies.map(\.id)
        }
        return noves
    }

    /// Enganxa pestanyes (del porta-retalls) a una finestra, després de `despresDe` o, si no hi és, al final.
    ///
    /// Una pestanya que encara hi és (s'ha copiat) entra com a còpia, igual que amb «Duplica»: id nou i sense nom fix
    /// de sessió. Una que ja no hi és (s'ha retallat) hi torna tal com era, amb el seu id: és un moviment. Si el seu nom
    /// fix ja el fa servir una altra pestanya (ve d'una altra configuració, o d'abans de tornar a importar), entra
    /// sense: dues sessions amb el mateix nom es confondrien.
    /// - Returns: els id de les enganxades, en ordre; buit si la finestra no existeix.
    public mutating func enganxa(_ pestanyes: [Pestanya], a desti: Finestra.ID, despresDe: Pestanya.ID? = nil,
                                 nouId: () -> UUID) -> [Pestanya.ID] {
        guard let d = finestres.firstIndex(where: { $0.id == desti }) else { return [] }
        var existents = Set(finestres.flatMap(\.pestanyes).map(\.id))
        var noms = Set(finestres.flatMap(\.pestanyes).compactMap(\.claude.nom))
        let noves = pestanyes.map { pestanya in
            var nova = existents.contains(pestanya.id) ? pestanya.duplicada(id: nouId()) : pestanya
            if let nom = nova.claude.nom, noms.contains(nom) { nova.claude.nom = nil }
            existents.insert(nova.id)
            if let nom = nova.claude.nom { noms.insert(nom) }
            return nova
        }
        let posicio = despresDe.flatMap { id in finestres[d].pestanyes.firstIndex { $0.id == id } }.map { $0 + 1 }
            ?? finestres[d].pestanyes.count
        finestres[d].pestanyes.insert(contentsOf: noves, at: posicio)
        return noves.map(\.id)
    }

    /// Mou pestanyes (de la mateixa finestra o de diverses) a una finestra, en l'ordre en què hi són.
    /// - Parameter index: la posició a la llista de destinació **abans** de treure'n les que es mouen (com
    ///   `move(fromOffsets:toOffset:)` i el que dona una llista en deixar-hi anar res); `nil`, al final.
    public mutating func mouPestanyes(_ ids: Set<Pestanya.ID>, a desti: Finestra.ID, index: Int? = nil) {
        guard let d = finestres.firstIndex(where: { $0.id == desti }) else { return }
        let mogudes = finestres.flatMap(\.pestanyes).filter { ids.contains($0.id) }
        guard !mogudes.isEmpty else { return }
        let total = finestres[d].pestanyes.count
        let posicio = min(max(index ?? total, 0), total)
        let abansDeLaPosicio = finestres[d].pestanyes.prefix(posicio).filter { ids.contains($0.id) }.count
        eliminaPestanyes(ids)
        finestres[d].pestanyes.insert(contentsOf: mogudes, at: posicio - abansDeLaPosicio)
    }

    /// Aplica un canvi a cada pestanya de la llista.
    public mutating func canviaPestanyes(_ ids: Set<Pestanya.ID>, _ canvi: (inout Pestanya) -> Void) {
        for f in finestres.indices {
            for p in finestres[f].pestanyes.indices where ids.contains(finestres[f].pestanyes[p].id) {
                canvi(&finestres[f].pestanyes[p])
            }
        }
    }
}

extension ClaudePestanya {
    /// La plantilla per a una pestanya nova o importada sense sessió: normalitzada i sense nom fix de sessió (decisió
    /// d'en David, 04/11/2026), com «Duplica» i «Enganxa». Si no, totes s'obririen amb el mateix nom.
    public func perAPestanyaNova() -> ClaudePestanya {
        var claude = normalitzada()
        claude.nom = nil
        return claude
    }
}

extension Pestanya {
    /// La pestanya per a una carpeta nova: el títol és el nom de la carpeta i Claude, el de la plantilla. A `~`, sense
    /// Claude, com a la importació (D11): probablement no és la carpeta que es volia.
    /// `~` es compara com als avisos (`Validacio`): amb la ruta estandarditzada de tots dos costats.
    public static func nova(id: UUID, carpeta: String, plantilla: ClaudePestanya, inici: String) -> Pestanya {
        let estandard = (carpeta as NSString).standardizingPath
        let aInici = estandard == (inici as NSString).standardizingPath
        var claude = plantilla.perAPestanyaNova()
        if aInici { claude.activat = false }
        let nom = (estandard as NSString).lastPathComponent
        return Pestanya(id: id, titol: aInici || nom.isEmpty || nom == "/" ? t("Pestanya nova") : nom, carpeta: carpeta,
                        claude: claude)
    }

    /// Una còpia amb un altre id i sense nom fix de sessió.
    func duplicada(id: UUID) -> Pestanya {
        var copia = self
        copia.id = id
        copia.claude.nom = nil
        return copia
    }
}
