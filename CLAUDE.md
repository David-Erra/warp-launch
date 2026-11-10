# CLAUDE.md — Warp Launch

App de macOS de **David Erra** per **llegir, editar i tornar a obrir les finestres i pestanyes
de Warp, cadascuna amb la seva sessió de Claude Code**. Ha de poder fer-ho sola en iniciar sessió al Mac.
És una app nativa de barra de menú (SwiftUI). Comanda: `warp-launch`. Identificador: `cat.davide.warp-launch`.

**Idioma:** català (codi, comentaris, missatges, commits i documentació). **To:** directe, concís, amb xifres i fets.

## El problema

Qui fa servir Warp amb moltes sessions de Claude Code les ha de tornar a obrir a mà després de cada reinici: totes les
finestres i, a cada pestanya, la seva sessió de Claude. La configuració que desa Warp no ho resol: les sessions s'han
d'iniciar a mà i s'ha de recordar tota la configuració.

Aquí, **una finestra de Warp és un grup de sessions**; no ho confonguis amb els *tab groups* de Warp.
Cada pestanya sol ser un repo, amb el seu agent de Claude Code. En un Mac de prova (03/11/2026) hi havia desenes de
pestanyes de terminal, però menys d'una quarta part amb una sessió de Claude viva, d'uns 500 MB cadascuna.
Els requisits són a `docs/especificacio.md`.

## Estat (10/11/2026, 0.32.9 al codi; publicada, 0.31.5)

- **Repo:** `David-Erra/warp-launch` a GitHub, públic, amb llicència MIT (`LICENSE`). Comença amb un sol commit inicial,
  sense l'historial anterior ni les versions d'abans de la 0.28.0. El `README.md` explica com instal·lar-la.
  - **Homebrew:** el tap és `David-Erra/homebrew-tap`, públic (`Casks/warp-launch.rb`): `brew install --cask
    david-erra/tap/warp-launch`. `publica.sh --aplica` en posa al dia la recepta: provat de debò una vegada, amb la 0.31.5
    (09/11/2026, commit `cd8c304` del tap; l'script de la 0.32.x, amb la clau i l'appcast, encara no s'ha executat de debò).
    `docs/disseny.md`, secció 10, «Homebrew»; `docs/fets-verificats.md`, «Homebrew».
  - **Compte de GitHub:** les ordres de `gh` que escriuen (`publica.sh`, `gh release`) necessiten `GH_TOKEN` d'un compte
    que pugui escriure al repo i al tap, passat només a aquella ordre (`GH_TOKEN="$(gh auth token -u <compte>)"`). No canviïs el compte
    actiu de `gh` (`gh auth switch`): el poden fer servir altres sessions.
- **Fase 1 (lectura) feta, versió 0.2.0.** `warp-launch llegeix [--json]` mostra les finestres, les pestanyes, la
  carpeta i la sessió de Claude de cada pestanya.
- **Fase 2 (editor) feta (06/11/2026; en David dona per bona la icona):** format v1 de la configuració, magatzem (desar i còpies), esquelet de
  l'app (pas 4, prova 1 feta el 04/11/2026), ordre de Claude (pas 5), importació i avisos (pas 6, al CLI:
  `warp-launch importa`), model de l'editor (pas 7) i barra lateral, llista i full d'importació (pas 8: l'app ja
  pot crear la configuració des de Warp; prova 2 feta el 04/11/2026), inspector (pas 9, prova 3) i copiar i enganxar
  pestanyes (pas 9b, proves 4 i 5), arrossegar i «Mou a ▸» (pas 10, prova 6), obrir la finestra arrossegant per
  deixar-hi les pestanyes en una posició (pas 10b, prova 7) i reordenar les finestres a la barra lateral (arrossegant-les,
  o «Mou amunt» i «Mou avall»; prova 7c feta el 04/11/2026), i menús, dreceres, menú de la icona i la plantilla a la
  Configuració, amb el seu Desfés (pas 11, provat a l'app el 04/11/2026). Del pas 12, el paquet és fet (0.26.0: `Info.plist` i `scripts/instal·la.sh`); la icona, dibuixada amb codi (`scripts/icona-dibuixa.swift`, decisió d'en David del 06/11/2026), a la 0.26.1.
  Prova 8 feta el 06/11/2026 amb la 0.26.0. Passos a `docs/disseny.md`, secció 4.
- **Fase 3.1 (obrir una finestra a Warp, R12): passos fets, de la 0.15.0 a la 0.24.0** (triada per en David abans del pas 12).
  Per donar-la per feta falten proves reals (L2, L5 i la del CLI `--obre`) i l'OK d'en David. Pla, passos i proves L1 a L5 a
  `docs/disseny.md`, secció 7. Fet: l'ordre sense `--continue` (D15),
  el generador del fitxer temporal (D5, D16), la lectura per obrir (marca, sessions
  en segon pla, Warp obert, transcripcions i confiança), `estat.json` (el pane i la conversa de cada pestanya, al
  costat de la configuració; l'app el posa al dia cada 60 s, D18), i el pla d'obertura amb `warp-launch obre
  <finestra>` en mode de prova (D17: mostra què s'obriria, el fitxer i l'URL; no escriu ni obre res). **Des de la
  0.20.0, l'app pot obrir una finestra a Warp** («Obre a Warp…», el full de confirmació i `ObreWarp`). Abans, dues
  revisions (correccions a la 0.20.1 i la 0.20.2). **L1 feta el 05/11/2026** (4 obertures, 3 amb Claude): Warp accepta
  el fitxer i l'app confirma en 0,6 s, però D16 queda desmentit (la línia surt a l'historial). En arrencar, l'app
  esborra els seus fitxers temporals que hagin quedat a la carpeta de launch configurations de Warp (només els
  propis, amb la marca). **0.21.0: «Lliga amb Warp…»** lliga una configuració sense `estat.json` (com `prova2`) amb
  les pestanyes ja obertes, per a L3 amb `/tmp/warp-launch-provaL3`. **El 05/11/2026, en una prova real, l'app torna a obrir
  totes les finestres i pestanyes** (totes confirmades, però cap conversa represa, i diversos Claude aturats perquè l'app
  no avisava bé de la confiança; corregit a la 0.21.1). «Obrir-ho tot» és la fase 3.2 (0.25.0) i obrir-se en iniciar sessió, la 3.3 (0.27.0).
- **0.22.1: cada pestanya reprèn sempre la conversa més recent de la seva carpeta** (D7, revisada per en David el 05/11/2026),
  si no és viva ni d'una altra pestanya. **0.22.2:** només compten les escrites al terminal on Claude ha respost, i la més recent
  és la de l'últim missatge al terminal, no la data del fitxer.
- **0.22.3: les feines noves `claude --bg` dels agents van en bypass** (en David, 05/11/2026), si la pestanya hi va: la línia porta `CLAUDE_ENV_FILE`
  (`EntornClaude`, `entorn-claude.sh` a la carpeta de la configuració). Les que ja existeixen es desperten sense el paràmetre, per no fer còpies.
  Sense efecte a les pestanyes ja obertes. Prova real feta el 05/11/2026 amb una feina: va en bypass.
- **D6 (05/11/2026): la restauració de sessió de Warp va desactivada** («aquesta app substitueix la funcionalitat»).
  Així, Warp no desa les finestres a `warp.sqlite`. **Des de la 0.22.0, l'app sap què hi ha obert pels processos** (els fills
  de `stable terminal-server`, `docs/disseny.md`, «Sense la base de Warp») i no llegeix la base si la restauració és
  desactivada; no en veu les finestres ni els títols. Per importar i lligar, des de la 0.23.0 en fa una foto (D19). Si Warp és tancat, «Obre» l'obre.
- **0.23.0 (D19): l'app gestiona `restore_session`.** Sempre desactivat, també en sortir. **Des de la 0.27.3, només quan l'usuari ho demana** (abans, cada 5 min):
  amb Warp obert, l'activa fins que Warp desa (de 5 a 30 s) perquè la base tingui una foto de les finestres. En un reinici de prova,
  Warp va restaurar la foto sol (les pestanyes, sense Claude). «Actualitza l'estat de Warp», importar i lligar: amb Warp obert, refresquen i llegeixen; amb Warp tancat, l'última foto. Obrir
  finestres continua pels processos. Prova real feta el 05/11/2026: dos refrescs de 5 i 6 s, i la foto quadra amb tots els terminals oberts.
- **0.24.0 (D17): `warp-launch obre <finestra> --obre`** obre la finestra pel mateix camí que el botó de l'app (`ExecucioObertura`, compartit).
  No fa res si l'app és oberta (tots dos escriurien `estat.json`), i si Warp és tancat, primer l'obre (en David, 05/11/2026). Sense prova real encara:
  **mai sense l'OK d'en David per a cada prova** (regla 1).
- **Fase 3.2, 0.25.0 (D4): «Obre-ho tot a Warp…»** (menú Fitxer i menú de la icona): un full amb una casella per finestra, totes
  marcades, i les obre totes de cop; si una falla, les altres continuen. **Provat el 06/11/2026 amb la 0.26.0**, amb la represa d'una conversa (prova 1), una finestra oberta en part (3) i la prova 8 (4): totes bé. `docs/disseny.md`, secció 8.
- **Fase 3.3, 0.27.0 (D3): obrir-se en iniciar sessió.** Un interruptor a la Configuració afegeix l'app als ítems d'inici de macOS
  (`SMAppService.mainApp`, només a `ServeiArrencada`; regla 3: només quan en David l'activa, i només amb l'app a `/Applications`). En
  iniciar sessió, mostra de seguida el full de «Obre-ho tot» (0.27.2: sense esperar Warp): no obre res sense el clic. **En un reinici de prova
  amb la 0.27.2,** l'app s'obre sola i prepara el full en 2 s, però Warp també s'obre sol i restaura les pestanyes sense Claude
  (`docs/fets-verificats.md`). D'aquí la 0.27.3: la foto només quan l'usuari la demana, i el full avisa de les pestanyes que no
  reconeix. Falta un reinici amb la 0.27.3. Warp es va obrir sol amb l'opció que l'obre en iniciar sessió («Start Warp at login»)
  desactivada, segons en David (07/11/2026): no se sap qui l'obre. `docs/disseny.md`, secció 9.
- **0.28.0 (D11, revisada per en David el 07/11/2026): la plantilla segura.** Una configuració nova (sense fitxer) s'importa amb
  `claude` sense saltar els permisos ni ultracode (`.perOmissio`, continuant la conversa). «Salta els permisos», l'esforç i
  «Ultracode» es trien a la Configuració › «Pestanyes noves» o per pestanya a l'inspector. La configuració que ja existeix
  conserva la seva plantilla.
- **Per a altres usuaris, de la 0.29.0 a la 0.31.4** (decisions d'en David del 07 i el 08/11/2026 a `docs/especificacio.md`;
  passos, proves i el que queda per decidir a `docs/disseny.md`, secció 10). **La versió de GitHub és la 0.31.5** (09/11/2026, la va publicar en David); la 0.31.4, en David
  l'ha provada a l'app i en un usuari de macOS nou (09/11/2026, ho ha dit ell).
  - **0.29.0 (D-P4): consentiment previ** perquè l'app gestioni `restore_session` (D19). `preferencies.json` (versió 1, al costat
    de la configuració) el desa amb el valor original de l'ajust. Sense consentiment, l'app no toca ni llegeix Warp i no proposa
    obrir res; la pantalla («Accepta» o «Surt de l’app Warp Launch») surt a l'editor i a la Configuració. Una carpeta amb
    `configuracio.json` o `estat.json` compta com a acceptada (a qui ja feia servir l'app no li pregunta; decisió 1, es queda així). Només `ConsentimentRestauracio` crea el refresc (`GuardaTests`).
  - **0.29.1 (D-P5a):** en una configuració nova, les pestanyes on no corria Claude queden només terminal (amb la lectura d'un
    Mac de prova del 04/11/2026, una cinquena part amb Claude i la resta només terminal, en lloc de tres quartes parts amb Claude). Des de la 0.31.5, també en tornar a importar.
  - **0.29.2 i 0.29.3 (D-P12): Warp Stable a qualsevol carpeta.** On és ho diu macOS, només a `WarpLaunchObridor/TrobaWarp.swift`
    (l'única `urlForApplication`); si no, `/Applications`. Una còpia a la Paperera no compta. El binari surt del paquet
    (`CFBundleExecutable`). Amb només Warp Preview, o Preview obert i Stable no, l'app no obre res i ho diu.
  - **0.30.0 i 0.30.1: diagnòstic de només lectura.** `warp-launch diagnostica` i Configuració › General › «Diagnòstic» ›
    «Copia el diagnòstic»: 8 comprovacions dels formats de Warp i de Claude Code que l'app llegeix, en anglès i, si es vol,
    anonimitzat. No bloqueja res. `VersionsProvades` (Warp 0.2026.10.21, Claude Code 2.1.317 a 2.1.318) es posa al dia a mà.
  - **0.30.2: la Configuració en dues pestanyes,** «General» i «Pestanyes noves». Cadascuna fa l'alçada del contingut, com a
    molt 640 pt, i el que no hi cap es desplaça; en canviar de pestanya, la finestra creix o s'encongeix per baix. Mida fixa per
    pestanya, com a macOS (decisió 11).
  - **0.30.3 (decisions 2, 8, 9 i 12):** a la pantalla del permís, Retorn accepta i Escapada no fa res; tancar-hi la
    Configuració fa sortir de l'app, com tancar l'editor; «Comença en blanc» i després «Torna a importar-ho tot» és com una
    configuració nova (les pestanyes sense Claude, només terminal, també al CLI); a «Pestanyes
    noves», la primera secció no repeteix el títol. I tres textos: importar i el diagnòstic amb `--config`, i la versió de Claude
    Code un sol cop al diagnòstic.
  - **0.31.0 (decisió 3): deixar de fer servir l'app.** Configuració › General › «Restaura Warp i surt…» treu l'app dels ítems
    d'inici, torna `restore_session` com era (activat, el de sèrie, si el permís és `migrat`), retira el permís (`retirat` a
    `preferencies.json`, que ja no compta com a migrat) i surt; després, l'app no torna a tocar l'ajust. És la línia i el camí
    de la segona excepció de la regla 7 (`RefrescWarp`), però només amb el clic: mai sense l'OK d'en David, perquè deixa la
    restauració activada. README, «Desinstal·lar».
  - **0.31.1 (decisió 4): compta el Warp que corre,** també si és una altra còpia de Warp Stable (pels processos,
    `Lector.installacio()`). Sense cap Warp, ho diu i no proposa obrir res.
  - **0.31.2 (decisió A, ronda 4): sense la línia `restore_session`, l'app l'afegeix** a `settings.toml` (regla 7, segona
    excepció): just després de `[general]`; sense la taula, la taula; sense el fitxer, el crea només amb la línia, d'un sol cop i
    només si Warp no l'ha creat mentrestant. Sense `~/.warp`, no la crea, i el menú diu que Warp no s'ha obert mai. Tot el que és
    ambigu (dues `[general]`, `general` com a clau, CRLF, una marca d'ordre de bytes, textos de diverses línies, un enllaç…) es
    refusa sense tocar res. Sense la línia, el valor és el de sèrie (`true`): és el que desa `preferencies.json`, i «Restaura
    Warp i surt…» hi deixa `restore_session = true`. Ho diuen el diagnòstic, la pantalla del permís i l'script (`estat`:
    «activat (de sèrie, sense la línia)»). També: «Lliga amb Warp…» amb `--config` diu per què no hi ha finestres
    (`MotiuSenseFinestres`), i sense cap Warp ni la seva base l'app diu que no hi ha Warp també amb `--config`
    (`Lector.llegeixDeLApp`).
  - **0.31.3 (ronda 5).** Warp buida `settings.toml` i l'escriu sencer a cada canvi, i en arrencar, si el fitxer no hi és, hi passa
    una vegada els ajustos de les preferències de macOS (`docs/fets-verificats.md`, codi públic de Warp, llegit i no vist).
    - **Escriptura prudent:** si `settings.toml` ha canviat fa menys de 2 s, l'app no l'analitza ni hi escriu (`.mesTard`, no és
      cap error) i ho torna a provar: cada minut, o cada segon fins a 3 cops al final d'un refresc, abans d'engegar Warp i en sortir
      (`terminateLater`). Abans del `rename`, el `stat` i el contingut han de ser els de la lectura. El que acaba d'escriure l'app
      no compta com a recent.
    - **El fitxer nou, només amb Warp obert** (decisió d'en David): sense `settings.toml`, l'app el crea només quan el Warp que corre
      ja té algun terminal (els terminals arriben després de la migració; el `terminal-server` sol, no), i si no, espera
      (`.quanSObriWarp`). Mentrestant, la restauració de Warp és la de sèrie: el menú ho diu amb una nota, el diagnòstic diu com és
      Warp ara, i els fulls d'obrir, amb Warp tancat, que Warp pot restaurar les finestres d'abans. Afegir la línia o la taula a un
      fitxer que ja hi és, com a la 0.31.2.
    - **Warp Stable sense la seva base** (no s'ha obert mai en aquest usuari): importar, lligar i el CLI diuen «Warp encara no ha
      desat cap finestra en aquest usuari: obre'l un cop i torna-ho a provar.» en lloc de «no trobo la base de Warp», i el menú,
      els terminals. Amb Warp Preview obert, que cal obrir Warp Stable.
    - **Guardes:** els lectors de Claude ja no tenen ruta per defecte (una prova que se l'oblidi no compila); la carpeta de Warp, el
      diagnòstic i l'ajust no poden canviar permisos ni atributs, ni obrir, crear o escriure per altres camins (només el `fchmod`
      del fitxer que `FitxersLaunchWarp` acaba de crear); l'ajust té un sol `rename(`; i, a les proves, `Lector.init(` també ha de
      portar les dues rutes de prova.
  - **0.31.4 (ronda 6, set decisions d'en David del 08/11/2026).**
    - **Rellotge:** a `settings.toml`, «recent» vol dir de 2 s enrere a 2 s endavant; una data més enllà ja no bloqueja l'app.
    - **Si `settings.toml` no para de canviar** i fa més de 5 minuts seguits que l'ajust no es pot desactivar ni se'n pot saber
      el valor (comptats amb el Mac despert), el menú de la icona ho diu, amb el triangle (`RefrescWarp.avisNoParaDeCanviar`). Pot
      sortir amb l'ajust ja desactivat: mentre el fitxer canvia, l'app no ho sap.
    - **Sense `~/.warp`,** el menú ho diu com a nota, sense el triangle (`Pendent.warpMaiObert`, `notaWarpMaiObert`).
    - **Warp obert i sense la base:** «si Warp s'acaba d'obrir, torna-ho a provar d'aquí a uns segons» (`LecturaWarp.senseBase`).
    - **Ja era així, ara amb proves:** amb Warp tancat i sense `settings.toml`, els fulls d'obrir avisen que Warp restaurarà les
      finestres d'abans (`Obertura.textWarpTancat`); amb una carpeta de prova i sense la base, «Obre a Warp…» obre pels processos.
    - **Guardes:** `Lector`, `LectorWarp` i `LectorAjustosWarp` ja no tenen cap valor per defecte (l'app i el CLI hi posen les
      rutes de debò, `lectorsDeWarpDeDebo`; una prova que se n'oblidi una no compila), i a tot `Sources/` només dues crides
      canvien permisos o atributs de fitxers: el `fchmod` del fitxer acabat de crear a `EscripturaAtomica` i a `FitxersLaunchWarp`.
  - **0.31.5 (cinc decisions d'en David del 09/11/2026; publicada el mateix dia; proves 2, 3 i 5 de `docs/disseny.md`, secció 10, fetes a l'app amb Warp de debò el mateix dia).**
    - **La carpeta:** si Warp i Claude no coincideixen i Claude és viu, mana la de Claude, excepte si és `~` o no existeix. Avís a
      «Per revisar» (`Validacio.avisCarpetaDeClaude`): la carpeta de Warp només és a la memòria (`estat.json` no canvia de format),
      i després d'un reinici l'avís només surt si l'última carpeta de Claude no és la de la pestanya. «Lliga amb Warp…» compara
      totes dues.
    - **Warp a `~` i Claude viu en una carpeta que no existeix:** la pestanya es queda a `~` amb Claude desactivat i les opcions
      de la seva ordre, com les altres de `~`, amb una nota (`.claudeSenseCarpeta`). Només amb proves de dades fictícies.
    - **Tornar a importar:** les pestanyes sense Claude viu queden sempre «Només terminal» (revisa D11), també al CLI.
    - **`~/.warp/launch_configurations`:** «Obre» la crea si no hi és (regla 7, tercera excepció).
    - **Avís** als fulls d'obrir i al README: tancar Warp pot deixar a mitges les feines en segon pla de Claude.
  - **Guardes (08/11/2026, sense versió):** cap expressió de `GuardaTests` no fa servir `\b`, que no veia els noms amb mòdul
    (`Foundation.Process()`, `NSApp.terminate`); `Process` i `kill` compten com a paraula sencera, i `exec…` i `NSUser…Task` són
    prohibides; les proves no poden fer servir la carpeta d'inici de debò per cap camí; i `Lector(carpetaSessions:)` és
    obligatori. Després de la 0.31.2: la carpeta de Warp i el diagnòstic tampoc no poden esborrar, moure, crear ni enllaçar
    fitxers per cap altra crida (també `remove` de C); `copyfile`, `linkItem`, `createSymbolicLink` i `renamex_np` només a
    `AjustRestauracio.swift`, que no pot obrir `settings.toml` per escriure-hi directament; i els lectors de Claude de debò, només
    a l'app i al CLI (`lectorsDeClaudeDeDebo`).
- **0.32.6 (en David, 09/11/2026): la mateixa funció es diu igual als dos menús.** «Actualitza l'estat de Warp» (abans, «Torna a llegir Warp», només
  al menú de la icona) és també al menú Arxiu, i al peu del full d'importació: una sola vista (`ItemActualitzaWarp`), desactivada
  sense el permís, mentre ja es llegeix i, des de la 0.32.7, mentre s'obre res a Warp o s'aplica una actualització (`OrdreActualitzaWarp`). «Obre la finestra a Warp…» és «Obre a Warp…». El menú de la icona
  i la pantalla del permís diuen «Sobre l’app Warp Launch» i «Surt de l’app Warp Launch», com el menú que posa macOS. Guarda:
  `laMateixaOrdreEsDiuIgualAlsDosMenus`. Només proves i codi llegit: no s'ha vist a l'app.
  - **0.32.8: importar i lligar, amb la mateixa condició** (`Obertura.impedeixRefresc`), perquè també activen la restauració de Warp (D19). `Editor.potImportar` i
    `demanaImportar` (el menú Arxiu i l'estat buit), `FullImportacio.potLlegir` (els dos botons del full; si en obrir-se no pot llegir, ho diu) i `Lligam.potLligar`
    (l'actualització que s'aplica). Importar tampoc amb el full d'obrir o de lligar a la vista, i amb el full d'importar obert no es comença cap obertura (el menú de
    la icona ho deixava), ni el full d'iniciar sessió el trepitja. Guarda: `lesLecturesAmbFinestresPassenPerLaSevaCondicio`. Només proves i codi llegit: no s'ha vist a l'app.
- **Actualització automàtica amb Sparkle 2.10.1 (de la 0.32.0 a la 0.32.5, 09/11/2026): al codi, sense publicar.** Les 13 decisions
  de l'autor són a `docs/especificacio.md`; el disseny, els passos, les proves reals i com s'atura una versió dolenta, a
  `docs/disseny.md`, secció 11; els fets, a `docs/fets-verificats.md`, «Sparkle».
  - **L'autor ha decidit activar-la (09/11/2026, després de publicar la 0.31.5).** Vol dir fer el que falta, en l'ordre de sota: no treu l'OK de cada ronda
    (regla 4), i la clau i publicar només els fa ell (regles 3 i 12).
  - **De l'app de debò, res no s'ha vist funcionar.** Warp Launch no s'ha obert mai amb Sparkle: les proves del repo són amb falsos i carpetes temporals, i el que depèn de Sparkle i de macOS en aquesta app està llegit o suposat.
    **Amb una app de prova, les rondes A i B són fetes,** amb clau d'un sol ús i l'OK de l'autor. **A** (09/11/2026, signatura ad hoc, carpeta temporal, canal d'ordres en lloc de clics):
    cicle complet, sortir amb la versió a punt, sortida cancel·lada, un zip dolent, interruptor apagat sense cap petició, instal·lació fallida (`chflags uchg`), sense servidor i appcasts
    refusats. **B** (10/11/2026, «Warp Launch Dev», `/Applications`, clics reals de l'autor): s'actualitza **sense cap diàleg de macOS**, també amb «Instal·la i reinicia»; refusa un zip
    dolent i una altra clau. `docs/fets-verificats.md`, «Sparkle», seccions 15 i 16.
  - **0.32.9: el que va sortir de la ronda A.** «Mostra la finestra» (la finestra de baixada acabada no es pot tancar i l'app no té Dock), el reinici ajornat diu per què, l'intent es treu si l'app
    no surt, l'estat no promet el que no farà ni diu «comprovar» quan falla la baixada, i desmarcar la casella de Sparkle apaga l'interruptor. A la ronda B, amb l'app de prova, s'han vist
    «Mostra la finestra», els textos nous i la casella; el reinici ajornat i l'intent tret, no.
  - **Falta, en aquest ordre:** les rondes C a F (amb clau d'un sol ús i l'OK de l'autor per a cada una); la clau de signatura, que
    només crea l'autor, i `Recursos/Actualitzacions.plist` amb l'adreça i la part pública (pas 11; sense aquest fitxer, cap còpia
    s'actualitza); `auto_updates true` i `zap` a la recepta del tap (pas 12; sense, `publica.sh` refusa); publicar (l'autor); i la
    primera actualització real, també amb Homebrew. Fins llavors, no s'anuncia. La B ha sortit neta; si la E no ho surt, s'espera el
    Developer ID (decisió 11).
  - **Les còpies d'abans (0.31.5 o anteriors) necessiten una última actualització a mà:** no porten res per actualitzar-se ni per
    avisar-ne. Com a molt 7 instal·lacions (baixades dels zips, API de GitHub, 09/11/2026: 1 de la 0.31.5, 4 de la 0.31.4 i 2 de la 0.28.0).
  - **Com va:** l'únic `import Sparkle` és a `ServeiActualitzacions.swift`; la lògica, sense Sparkle i amb proves, a
    `PoliticaActualitzacions`, `IntentActualitzacio` i el model `Actualitzacions`. Mira un cop al dia, va encès de sèrie, té pestanya
    a la Configuració («Actualitzacions») i ítem al menú. Només amb el permís de la restauració acceptat o migrat, a `/Applications`,
    i amb l'adreça, que només hi posa `build-app.sh --amb-feed`. Es reinicia sola amb 2 minuts sense teclat ni ratolí i sense res de
    l'app en ús; Warp i Claude no es toquen. `actualitzacio.json` (l'intent i les fallades) és al costat de la configuració, i
    l'escriu l'app.
  - **Privacitat:** és la primera connexió a internet de l'app: GitHub veu l'adreça IP i la versió. A `Sources/` no hi ha cap crida
    de xarxa (guarda): la fa Sparkle.
- **Signatura:** `scripts/build-app.sh` signa amb el certificat «Warp Launch Dev» del clauer d'en David (D12).
  Per llegir les dades de Warp, cal donar a l'app el permís de Privacitat i seguretat › Arxius i carpetes.
- **Ordre de feina acordat:**
  1. Lectura de la configuració actual de Warp.
  2. Editor.
  3. Llançaments, pas a pas.
- **El prototip `espai` (Python) està desinstal·lat:** no hi ha LaunchAgent ni comanda. Des del 07/11/2026, `prototip/`
  ja no és al repo (en David): el codi del prototip és a l'historial, al commit 114c97d (`git show 114c97d:prototip/espai.py`).
  En David creu que **tot el que es va fer abans potser no val i s'ha de revisar**: el codi, les proves i els fets que se'n van treure.
- **L'app nova no pot dependre de res creat abans fora d'aquest repo**, com `espai`, `~/.config/espai-warp/`
  o les configuracions `espai-*.yaml`.

Llegeix, en aquest ordre:
- `docs/especificacio.md`: requisits, decisions preses i obertes, fases.
- `docs/fets-verificats.md`: què hem comprovat de Warp, de Claude Code i de l'entorn. No tornis a descobrir
  els fets datats; els marcats «(prototip)» s'han de tornar a verificar abans de basar-hi codi.
- `docs/antecedents.md`: què existeix ja, i per què fem l'app igualment.
- `docs/disseny.md`: el disseny i els passos de les fases 2 (l'editor) i 3 (els llançaments). Mana sobre la skill `mac-design`.

## Entorn i comandes

- Swift 6.4.2 de les **Command Line Tools**, en mode de llenguatge Swift 6. **Una sola dependència externa: Sparkle 2.10.1,**
  amb la versió exacta i només al target de l'app (regla 10). La resta, només frameworks de macOS: Foundation, SwiftUI, AppKit, SQLite3,
  UniformTypeIdentifiers, CoreTransferable, ServiceManagement i os (i CryptoKit, només a `scripts/verifica-signatura.swift`).
  La primera compilació d'un clon nou necessita internet, també només per al CLI.
  La compilació s'ha provat només a macOS 27.2; la versió mínima declarada és macOS 26.
- **Proves amb `swift-testing`** (`import Testing`), que fa servir les macros de TestingMacros. XCTest no
  està disponible amb les Command Line Tools.
- **Xcode 27.2 només fa falta per compilar la icona** (`scripts/icona-compila.sh` i `icona-revisa.sh`).
  - La llicència i la configuració inicial (`sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch`)
    es fan un sol cop i les fa en David; fetes el 03/11/2026 (`docs/fets-verificats.md`).
  - `xcode-select` apunta a les Command Line Tools: per fer servir Xcode, cal
    `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (els scripts ja el posen).
- **Signatura:** el projecte no fa servir cap certificat de desenvolupador d'Apple. `build-app.sh` signa amb «Warp Launch Dev», un certificat
  propi del clauer d'en David (D12); si no el troba (en un altre Mac), ad hoc.

```bash
swift build                              # compila tot (debug)
scripts/test.sh                          # proves; no facis servir `swift test` sol (vegeu sota)
.build/debug/warp-launch --versio        # CLI
.build/debug/warp-launch llegeix [--json]  # què hi ha obert a Warp i a Claude (només lectura)
.build/debug/warp-launch importa [--json]  # la configuració que sortiria de Warp, amb els avisos (no escriu res)
.build/debug/warp-launch configuracio valida  # errors i avisos de ~/.config/warp-launch (només lectura)
.build/debug/warp-launch obre <finestra> [--json] [--config <carpeta>]  # mode de prova: què s'obriria (no escriu ni obre res)
.build/debug/warp-launch obre <finestra> --obre [--config <carpeta>]   # obre de debò (regla 1: només amb l'OK d'en David)
.build/debug/warp-launch diagnostica [--json] [--anonimitza]  # si Warp i Claude Code tenen la forma que l'app llegeix (només lectura; no és a la regla 4: sobre l'estat real, amb l'OK d'en David)
/usr/bin/log show --last 10m --predicate 'subsystem == "cat.davide.warp-launch"'  # registre de l'app (arrossegar)
scripts/build-app.sh [release|debug]     # crea «build/Warp Launch.app» (release, signada amb «Warp Launch Dev» o ad hoc); no l'obre. --amb-feed només el passa publica.sh
scripts/instal·la.sh [--aplica]          # sense --aplica, diu què copiaria a /Applications; amb, copia (regla 3: només amb l'OK d'en David)
scripts/instal·la.sh --github [--aplica] [--versio x.y.z]  # igual, amb la versió publicada a GitHub (per a altres Macs; README.md)
GH_TOKEN=… scripts/publica.sh [--aplica]  # sense --aplica, compila i diu què publicaria; amb, signa el zip, crea la versió a GitHub i posa al dia la recepta de Homebrew (regles 3 i 12: --aplica només l'executa l'autor, al seu terminal)
scripts/warp-restauracio.sh estat         # si Warp desa les finestres (només lectura)
scripts/warp-restauracio.sh activa|desactiva [--aplica]  # regla 7: sense --aplica no escriu; amb, cal l'OK d'en David
scripts/genera-imatge.sh "<prompt>" <sortida.png> [1:1]   # imatge amb nano-banana (cal GEMINI_API_KEY)
```

- **Elements gràfics** (decisió d'en David, 03/11/2026):
  - La icona de l'app es dibuixa amb codi (`scripts/icona-dibuixa.swift`, en David, 06/11/2026); nano-banana (`scripts/genera-imatge.sh`) queda com a alternativa.
  - La icona de la barra de menú i els botons de l'editor són SF Symbols.
  - **Clau:** exporta `GEMINI_API_KEY` amb la teva clau abans d'executar l'script, sense mostrar-la ni escriure-la al repo.
  - Cada imatge es paga: genera només les que calguin.

- `swift test` sol falla de manera intermitent amb «plugin for module 'TestingMacros' not found».
  `scripts/test.sh` hi passa la ruta del connector.
- Els avisos de `ld` «search path '/Library/Developer/CommandLineTools/…' not found» són de SwiftPM amb
  les Command Line Tools i no afecten la compilació.

| Ruta | Què hi ha |
|---|---|
| `Sources/WarpLaunchCore/` | Lògica sense interfície: models, lectura de Warp i de Claude, configuració JSON |
| `Sources/WarpLaunchUI/` | Model de l'editor (`Editor`, `EstatWarp`) i vistes SwiftUI; no toca `NSApp` |
| `Sources/WarpLaunchObridor/` | L'única crida que obre res a Warp (`ObreWarp`) i l'única pregunta a macOS d'on és Warp (`TrobaWarp`); la fan servir l'app i el CLI, cap prova no en depèn |
| `Sources/WarpLaunchApp/` | App de barra de menú, prima: escenes, activació i Dock (executable `WarpLaunch`, `--config <carpeta>`); `ServeiActualitzacions.swift`, l'únic que importa Sparkle |
| `Sources/WarpLaunchCLI/` | Comanda `warp-launch`: només hi posa els valors reals; la lògica és a `OrdreCLI` (core), que es prova amb fixtures |
| `Tests/WarpLaunchCoreTests/` | Proves `swift-testing`, sempre amb dades fictícies; inclou la prova de guarda (`GuardaTests`) |
| `Tests/WarpLaunchUITests/` | Proves del model de l'editor, amb carpetes temporals |
| `Recursos/Info.plist` | Plantilla del bundle (`LSUIElement`; la versió surt de `VERSION`); `ca.lproj` per als menús en català |
| `Recursos/Actualitzacions.plist` | **Encara no hi és (pas 11; una guarda ho comprova).** L'adreça de les actualitzacions i la clau pública: només les porta la còpia que es publica |
| `scripts/` | `test.sh` (proves), `build-app.sh` (empaqueta i signa el `.app`), `instal·la.sh` (el copia a `/Applications`, també des de GitHub), `publica.sh` (publica la versió a GitHub i posa al dia la recepta de Homebrew), `verifica-signatura.swift` (comprova la signatura del zip amb la clau pública de l'app), `warp-restauracio.sh` (regla 7), `genera-imatge.sh` (nano-banana) i `icona-*` (icona; `icona-dibuixa.swift` en dibuixa les capes) |
| `.claude/skills/mac-design/` | Normes de disseny d'app de Mac (adaptada de BAMA, MIT); `docs/disseny.md` hi mana |
| `.claude/skills/app-icon/` | Com es fa la icona: dibuix amb codi (nano-banana, com a alternativa), Icon Composer i `actool` (adaptada de BAMA, MIT) |
| `.claude/settings.json` | Regles `deny` de Claude Code (vegeu sota) |
| `LICENSE` | Llicència MIT (© 2026 David Erra); les skills de BAMA porten la seva (`LICENSE-BAMA`), i la de Sparkle va dins de l'app (`LICENSE-Sparkle`) |

## Regles de seguretat (obligatòries)

L'app toca l'entorn de treball real d'en David. Cada Claude penja del procés de Warp, i un error obre
desenes de sessions o les tanca totes de cop.

**Sessions i finestres**

1. **No obris finestres de Warp ni sessions de Claude sense l'OK explícit d'en David, per a cada prova.**
   - Les proves de llançament es fan amb Warp i sessions reals, perquè en David ho vol així, però pas a pas.
     Abans de cada prova, digues-li quantes finestres i sessions s'obriran.
   - Sense OK no executis `open "warp://..."`, ni `claude` (excepte `--help` i `--version`), ni
     `claude agents` (pot engegar el supervisor).
   - Si executes el binari de Warp (`Warp.app/Contents/MacOS/stable`, `oz`), passa-hi sempre `--help` o
     una subcomanda. Sense arguments, obre l'app.
2. **No tanquis, reiniciïs ni forcis la sortida de Warp**, ni tanquis-ne pestanyes o finestres: es tancarien
   totes les sessions de Claude que hi corren. No matis mai cap procés de Claude. Si una prova demana
   reiniciar Warp o el Mac, ho fa en David.

**Instal·lació i execució**

3. **No registris cap arrencada automàtica** (LaunchAgent, `SMAppService`, ítems d'inici de sessió) ni copiïs
   l'app a `/Applications` sense l'OK d'en David. Abans, digues-li com es desfà.
   - **Des de la 0.27.0 (D3),** l'app té un interruptor a la Configuració («Obre Warp Launch en iniciar sessió») que l'afegeix
     als ítems d'inici. Només l'activa en David, a mà; tu no l'activis ni el provis sense el seu OK. Es desfà amb el mateix
     interruptor o a Configuració del Sistema › General › Ítems d’inici de sessió.
   - **No publiquis cap versió a GitHub** (`scripts/publica.sh --aplica`): l'executa només l'autor, al seu terminal (decisió 6 de
     Sparkle; regla 12). La instal·la qui faci la comanda del README, i també posa al dia la recepta de Homebrew del tap (la rep qui
     faci `brew upgrade`).
   - **Des de la primera 0.32.x, publicar arriba sol a tots els Macs en un dia i no es desfà.** Es para com diu `docs/disseny.md`,
     secció 11, apartat 7: `latest` torna a l'anterior, es reverteix la recepta i es publica una correcció amb una versió superior.
     Fins llavors (cap còpia no s'actualitza sola), es desfà en aquest ordre, perquè Homebrew no demani un zip que ja no hi és:
     `git revert <commit>` (el que diu l'script) en un clon del tap, i push; després, `gh release delete vX.Y.Z --repo
     David-Erra/warp-launch --cleanup-tag`.
   - Sparkle crea una tasca temporal de `launchd` a cada instal·lació (llegit a les seves fonts): no és un ítem d'inici ni un
     LaunchAgent permanent, i no l'ha de registrar cap codi nostre.
4. **No obris l'app** (`open "build/Warp Launch.app"`, `.build/*/WarpLaunch`) sense OK.
   - **Una prova d'actualització reinicia l'app:** l'OK ha de cobrir-ho, i has de dir quantes vegades. Cap ronda obre finestres de
     Warp ni sessions de Claude (`docs/disseny.md`, secció 11, apartat 8).
   - Del CLI, sense OK només pots executar ordres de lectura: `--versio`, `llegeix`, i a la fase 2 `importa` sense
     `--desa` i `configuracio valida` (OK d'en David, 03/11/2026).
   - Tota ordre que obri finestres o escrigui fora del repo ha de tenir un mode de prova, i ha de ser el
     comportament per defecte.
5. **El prototip ja no és al repo** (07/11/2026): és a l'historial, al commit 114c97d. Per entendre'l, llegeix-ne el codi
   (`git show 114c97d:prototip/espai.py`). No el recuperis per executar-lo, ni amb cap subcomanda: `instal·la` el tornaria a
   instal·lar, `desa` escriu l'estat i `obre` obre Warp.

**Fitxers**

6. **`~/.claude/` és només de lectura**: transcripcions, `sessions/` i configuració. L'única excepció és la
   memòria d'aquest projecte, que gestiona Claude Code. Els hooks de Claude per a l'app només es poden
   injectar en cada llançament amb `--settings`, mai escrivint a `~/.claude/settings.json`.
7. **Els fitxers de Warp són només de lectura.**
   - `warp.sqlite` s'obre sempre en només lectura (`SQLITE_OPEN_READONLY`, o `?mode=ro` des del
     terminal), perquè Warp l'escriu en calent.
   - No toquis `~/.warp/` (`settings.toml`, `tab_configs/`, launch configurations, incloses les
     `espai-*.yaml` del prototip), ni les preferències de Warp.
   - **Única excepció (en David, 05/11/2026):** la línia `restore_session` de `[general]` a `~/.warp/settings.toml`, per
     activar la restauració de sessió una estona i poder llegir les finestres i els títols de Warp.
     - Només amb `scripts/warp-restauracio.sh`, i només amb l'OK d'en David per a cada vegada. L'script només canvia la línia:
       si no hi és, no l'afegeix (`desactiva` falla).
     - Abans, digues-li què passa mentre és activada: si Warp es tanca, restaura les seves finestres, i, amb Settings Sync,
       l'ajust arriba a les altres instal·lacions.
     - En acabar, torna-la a desactivar i comprova-ho amb `estat`, passat 1 s (Warp podria tornar a posar el valor d'abans).
   - **Segona excepció (en David, 05/11/2026, D19; 08/11/2026, decisió A): l'app** pot canviar o afegir aquesta mateixa línia i,
     si no hi són, la taula `[general]` o el fitxer `settings.toml` (mai la carpeta `~/.warp`), sola i sense OK per a cada vegada,
     només amb la carpeta de debò i el permís acceptat o migrat (`AjustRestauracio`, `RefrescWarp`). Cap altre codi ni cap altra
     línia. **Sense el fitxer, l'app el crea només amb Warp obert** (en David, 08/11/2026, ronda 5; a la 0.31.3, quan el Warp que
     corre ja té algun terminal), perquè Warp hi hagi passat abans els seus ajustos antics; amb Warp tancat, espera que s'obri.
     Mentre l'app és en marxa, l'ajust que activis a mà es torna a desactivar en 60 s: per fer servir l'script, primer surt de
     l'app.
   - **Tercera excepció (en David, 09/11/2026): l'app** crea la carpeta `~/.warp/launch_configurations` en fer «Obre», si no hi
     és (`FitxersLaunchWarp.escriu`, un sol `mkdir`, un sol nivell). Mai `~/.warp`: si no hi és, com fins ara, no s'obre res.
     Res si el camí o `~/.warp` són un enllaç o un fitxer. Només amb la carpeta de debò i el permís acceptat o migrat
     (`ConsentimentRestauracio.potCrearCarpetaDeWarp`); el CLI no la crea.
   - Quan arribi la fase 3, l'app només escriurà els fitxers que generi ella, amb una marca pròpia, i amb l'OK d'en David.
8. **`~/.config/espai-warp/` és només de lectura.** Hi ha la configuració i l'historial del prototip.
9. **La configuració JSON de Warp Launch és d'en David** (a `~/.config/warp-launch/`). Edita-la només si t'ho
   demana, i fes-ne còpia abans. Les proves fan servir sempre una ruta temporal.

**Canvis**

10. **Res de dependències noves sense acordar-ho:** ni paquets SwiftPM, ni eines de Homebrew, ni llibreries fora de macOS.
    L'única acordada és Sparkle (fila del 07/11/2026, decisió 6), amb la versió exacta: pujar-la és un canvi més d'aquesta regla.
11. **Canvis de format amb migració.** La configuració porta un camp de versió. Si el format canvia, cal
    escriure una migració que no perdi dades i demanar l'OK abans. Amb les actualitzacions automàtiques, una migració arriba a
    tothom sense que ningú ho decideixi: cap canvi de format sense que la versió anterior en sàpiga llegir el resultat o recuperar
    la còpia.

**Clau de signatura de les actualitzacions**

12. **Cap agent no crea, llegeix ni fa servir la clau EdDSA de Sparkle.**
    - No executis `generate_keys` (sense arguments la crea; només `--help`), `sign_update` ni `generate_appcast` amb la clau real,
      ni `scripts/publica.sh --aplica` (decisió 6).
    - Tampoc cap ordre que llegeixi o busqui la seva entrada al clauer (`security find-generic-password`, `dump-keychain`…).
    - Les proves fan servir falsos, o una clau d'un sol ús en un fitxer temporal.
    - Si aquesta clau es perd sense còpia, cap instal·lació no es pot tornar a actualitzar sola (`docs/disseny.md`, secció 11, apartat 5).

**Sobre `.claude/settings.json`:** les regles `deny` es compleixen fins i tot amb
`--dangerously-skip-permissions`. Bloquegen dues coses:
- l'edició amb Edit/Write dels fitxers protegits (`~/.claude`, que no inclou la memòria; Warp; LaunchAgents;
  `espai-warp`; la configuració de Warp Launch, `~/.config/warp-launch/`);
- algunes ordres de Bash: `killall`, `pkill`, `osascript`, `launchctl bootstrap|load|enable|kickstart`,
  `claude agents`, les subcomandes d'`espai.py`, les eines de la clau de Sparkle, `publica.sh --aplica` i les ordres que llegeixen
  el clauer, `security find-generic-password` i `dump-keychain` (regla 12). La regla de `publica.sh` val per a tota l'ordre: un
  missatge o un text que porti tots dos trossos també queda bloquejat. Les de `security` comencen per l'ordre (amb `env`, `command`,
  `exec`, `PATH=` o una ruta al davant): parlar-ne en un `grep` passa, i `security find-identity`, que fa servir `build-app.sh`, també.
  Només afecten els agents, no l'autor al seu terminal. Tampoc no són un mur: una ordre indirecta (`bash -c`, una variable, un
  script) no hi coincideix, i la regla 12 s'ha de complir igualment.

**No cobreixen** l'escriptura amb altres ordres de Bash (`sed -i`, `cp`, redireccions) ni `open warp://`.
Aquestes regles s'han de complir igualment. `Edit(~/.warp/**)` es manté també amb l'excepció de la regla 7: l'únic camí
és l'script.

## Com treballar

- **Una prova per cada bug o comportament nou.** Les proves no llegeixen mai l'estat real de Warp ni de
  Claude: fan servir fixtures generats a la prova (una base SQLite de mostra, JSON de sessió falsos).
- **Commits petits a `main`, en català** (`feat: …`, `fix: …`, `docs: …`, `chore: …`).
  - Cada canvi funcional porta un bump de `VERSION` (semver) i de `WarpLaunch.versio`. Una prova comprova
    que coincideixen, i `build-app.sh` també.
  - Fes push a `origin` quan en David doni per bona una funcionalitat.
- **Les decisions obertes de `docs/especificacio.md` les pren en David.**
  - Planteja-les amb una recomanació, i no les donis per fetes.
  - Explica cada opció pel que passarà al seu Mac (què s'obre, què es trenca), no pel mecanisme.
- **Fets nous de Warp, de Claude Code o de l'entorn:** afegeix-los a `docs/fets-verificats.md` amb la data i
  com els has comprovat. Si un fet queda desmentit, corregeix-lo.
