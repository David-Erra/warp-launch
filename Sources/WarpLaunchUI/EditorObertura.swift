import Foundation
import WarpLaunchCore

/// Les ordres «Obre la finestra a Warp…» (menú Fitxer, barra d'eines, menú contextual i inspector de la finestra, i menú
/// de la icona): només demanen el full de confirmació. Obrir de debò només ho fa el botó del full
/// (`Obertura.confirmaIObre`).
extension Editor {
    /// Si es pot demanar el full per a aquesta finestra (vegeu `Obertura.potObrir`).
    public func potObrir(_ finestra: Finestra.ID?) -> Bool {
        obertura?.potObrir(finestra) == true && lligam?.mostraFull != true
    }

    /// Prepara el full de confirmació de la finestra. No obre res.
    public func demanaObertura(_ finestra: Finestra.ID) {
        guard let obertura, potObrir(finestra) else { return }
        Task { await obertura.demana(finestra) }
    }

    /// Si es pot demanar el full de «Obre-ho tot a Warp…» (vegeu `Obertura.potObrirTot`).
    public var potObrirTot: Bool {
        obertura?.potObrirTot == true && lligam?.mostraFull != true
    }

    /// Prepara el full de «Obre-ho tot a Warp…». No obre res.
    public func demanaObreTot() {
        guard let obertura, potObrirTot else { return }
        Task { await obertura.demanaTot() }
    }

    /// Si es pot demanar el full de «Lliga amb Warp…» (vegeu `Lligam.potLligar`).
    public var potLligar: Bool { lligam?.potLligar == true }

    /// Llegeix Warp i mostra el full de «Lliga amb Warp…». No desa res.
    public func demanaLligam() {
        guard let lligam, lligam.potLligar else { return }
        Task { await lligam.demana() }
    }
}
