# Disseny de la fase 2 — l'editor

Pla de la fase 2 (R2, R3, R4, R11; i el lloc de R12), del 03/11/2026. Surt de tres propostes (interfície,
format de configuració i arquitectura), de la lectura crítica de la skill `mac-design` i d'una crítica del pla
contra `CLAUDE.md`, l'especificació i el codi. Les preguntes obertes són al final; les decisions d'en David,
a `especificacio.md`.

Normes de disseny: `.claude/skills/mac-design/`. **Aquest document mana sobre la skill.**

## 1. Interfície

### Disposició

Una sola finestra d'editor (`Window` amb id `editor`): `NavigationSplitView` amb barra lateral i llista, més
`.inspector` a la dreta.

- **Barra lateral** (un nivell):
  - «Per revisar» (`exclamationmark.triangle`, amb el nombre), només si hi ha avisos: per exemple, pestanyes a `~` o
    amb una carpeta que ja no existeix.
  - «Finestres»: una fila per finestra de Warp (`macwindow` i el nombre de pestanyes).
- **Llista de pestanyes** (selecció múltiple). Cada fila: el nom, i a sota la carpeta abreujada o l'avís més greu.
  A la dreta, un resum: «Opus · Molt alt · Ultracode», o «Només terminal».
- **Inspector** (`Form` agrupat):
  - **Pestanya:** nom i carpeta (amb «Tria…»).
  - **Claude Code:** «Obre Claude Code en aquesta pestanya» (si està apagat, la resta queda desactivada), model,
    esforç, ultracode, continua la conversa, nom fix de la sessió, salta els permisos i mode de permisos.
    Les opcions que l'editor no entén surten en només lectura.
  - **Ordre:** la línia de comanda que s'executarà, seleccionable, amb «Copia l'ordre».
  - Amb diverses pestanyes seleccionades, només el bloc Claude, amb «Valors diversos».
  - Sense cap pestanya seleccionada, la finestra: nom, xifres i «Obre a Warp…» (desactivat fins a la fase 3).
- **Títol:** el nom de la finestra seleccionada. **Subtítol:** «12 pestanyes · 8 amb Claude · 2 avisos».
- **Estats buits** (`ContentUnavailableView`):
  - Sense configuració: «Importa de Warp…» i «Comença en blanc». No es llegeix ni s'escriu res fins al clic.
  - Finestra sense pestanyes: «Nova pestanya…» i, si n'hi ha al porta-retalls, «Enganxa les pestanyes». El panell
    no rep pestanyes arrossegades (no hi ha cap llista d'on treure-les, i una finestra buida no s'obre arrossegant):
    s'hi porten deixant-les anar a la seva fila de la barra lateral, o amb «Mou a ▸».
  - Cap finestra, i «Res per revisar».
- **Cap focus en obrir** l'editor ni els fulls (modificador propi; `.noInitialFocus()` és de la plantilla de BAMA).

### Arrossegar

- Es pot arrossegar una pestanya, o diverses, per reordenar-les dins de la finestra o per moure-les a una altra
  finestra deixant-les anar sobre la seva fila de la barra lateral (van al final).
  - **Les dades no sempre arriben a la fila** (prova 7b): la càrrega del proveïdor es cancel·la (NSItemProvider -1000,
    Cocoa 3072) i l'acció arriba amb 0 pestanyes. Llavors es mouen les de l'última pulsació, amb tres condicions:
    - quines: les files per a les quals SwiftUI demana el proveïdor (`.itemProvider` → `comencaArrossegament`), que en
      una pulsació són la fila premuda i cada fila arrossegada, en pocs ms (`Editor.pestanyesArrossegades`). No la
      selecció: amb ⇧ o ⌘, AppKit la canvia abans d'arrossegar i SwiftUI encara no ho sap (binari, revisió);
    - quan: es fixen mentre l'arrossegament passa per la fila (`onDropSessionUpdated` → `fixaPestanyesArrossegades`),
      perquè un clic entre deixar anar i l'acció (~0,3 s) no les canviï;
    - si: l'arrossegament és d'aquesta app (`DropSession.localSession`), en porta les mateixes
      (`itemsCount`) i no s'arrossega una finestra. Si no, no es mou res. A la llista no es fan servir: la seva acció
      no diu d'on ve l'arrossegament (i allà les dades arriben).
- **Reordenar les finestres** (0.13.0, demanat per en David): arrossegant-ne la fila a la barra lateral (`onMove` al
  `ForEach` de «Finestres», `Editor.reordenaFinestres` → `Configuracio.mouFinestres`), o amb «Mou amunt» i «Mou avall»
  al menú contextual de la fila. Cada moviment és un sol pas de Desfés («Mou la finestra»); la finestra que es veu,
  «Per revisar» i la selecció no canvien.
  - La barra lateral i la llista de pestanyes són totes dues `List` amb `onMove`: perquè les posicions de l'una no
    moguin res de l'altra, la fila d'una finestra porta un `.itemProvider` amb un `NSItemProvider` buit (no porta cap
    dada) que posa la marca `Editor.arrossegantFinestres`. `reordenaFinestres` només mou amb la marca; `reordena`
    (pestanyes) i obrir una finestra arrossegant, només sense. El `.itemProvider` d'una pestanya la treu.
- **Obrir una finestra arrossegant (pas 10b),** com les carpetes del Finder: aturar-se 0,5 s sobre la fila d'una altra
  finestra amb pestanyes (també des de «Per revisar») la mostra, i s'hi poden deixar anar en una posició concreta de
  la llista. La seva fila també les accepta (van al final). Passar-hi per sobre sense aturar-s'hi no obre res.
  - Una finestra buida no s'obre: només hi ha un lloc on posar-les (la seva fila), i a la prova 7, en obrir-la, la
    llista d'origen desapareixia de la pantalla i no s'acceptava res enlloc (la pestanya tornava al seu lloc).
  - Obrir no és cap pas de Desfés. Deixar-les anar sí, un de sol, que torna a la finestra i a la selecció d'abans
    d'obrir-la. Si es cancel·la (Esc, o es deixen fora), es queda la finestra oberta i no canvia res.
  - La `List` no ho fa sola (docs/fets-verificats.md): cada fila de finestra té `onDropSessionUpdated` (per fora de
    `dropDestination`), i `Molla` hi engega un `Timer` de 50 ms als modes comuns i `.eventTracking`. Quan han passat
    0,5 s, obre la finestra (`Editor.obreArrossegant`) si el cursor encara és dins de la fila (la `NSTableRowView`
    que la conté, a la pantalla) i el botó encara és premut (`NSEvent.pressedMouseButtons`). Una altra fila torna a
    començar el compte; sortir-ne, amollar o deixar-les anar l'atura.
  - **Esc a mig arrossegament (pas 11).** SwiftUI no avisa la fila, i el cursor hi continua: abans del pas 11, la
    finestra s'obria igualment. Ara hi ha dos senyals, sense comprovar a l'app (prova 8):
    - si la fila deixa de ser la destinació d'AppKit (`NSTableRowView.isTargetForDropOperation`) després d'haver-ho
      estat, no s'obre mentre duri. No s'atura: si a la vora de la fila AppKit proposa inserir entre files, en tornar
      al mig (destinació un altre cop, després de més de 0,1 s) el compte torna a començar;
    - si arriba un Esc a l'app (un monitor local de teclat, només mentre compta), s'atura.
    Si no arriba cap dels dos, fa el mateix que abans. Cada canvi de la molla va al registre (`.notice`): compta, és o
    deixa de ser la destinació, s'atura (amb el motiu) i obre.
    - A la prova del pas 11, en David diu que amb Esc ja no s'obre. Però el senyal d'AppKit no hi arriba mai
      («destinació vista false» als 7 comptes, també als 2 que obren), i el registre no té cap «s'atura (Esc)».
      Quin camí l'atura està per veure: es mira a la prova 8, amb el registre de la 0.14.1. **Pla B**, si a la prova 8 no arriba cap senyal: aturar
    la molla si fa més de 0,2 s que no arriba cap `dropConfiguration` (el registre en diu l'últim). No s'aplica ara:
    si SwiftUI no el crida amb el cursor quiet, la molla no obriria mai.
  - El retard és fix, el valor per defecte de macOS: la preferència del sistema (`com.apple.springing.delay`) no es
    llegeix, perquè la prova de guarda no deixa fer servir `UserDefaults` al codi de l'app. Des de la 0.32.0, Sparkle sí que hi desa
    les seves (l'interruptor i l'última comprovació).
  - **Les posicions de l'altra finestra no poden moure res.** La `List` recorda les files arrossegades per la posició
    que tenien (binari de SwiftUI): si la mateixa llista passés a mostrar una altra finestra, en deixar-les anar
    `onMove` rebria posicions de la primera i mouria pestanyes que en David no ha tocat (o l'app petaria). Per això:
    - cada cop que una finestra s'obre arrossegant, la llista de pestanyes és una altra (`.id(editor.generacioLlista)`):
      com que no és la d'on surt l'arrossegament, SwiftUI hi fa servir el camí d'inserir,
      `ForEach(...).dropDestination(for: PestanyaArrossegada.self) { arrossegades, index in }` (posat abans d'`onMove`),
      i `Editor.deixaAnar(_:a:index:)` mou pels id, a la posició de la llista que es veu. Un clic no canvia la llista;
    - i, a més, `Editor.reordena` no fa res mentre la finestra que es veu s'ha obert arrossegant (`abansDObrir`). Ho
      treu el `.itemProvider` de la fila (un arrossegament nou), qualsevol canvi, Desfés o carregar. Ho prova
      `unOnMoveDespresDObrirNoMouRes`.
  - El cursor porta «+» en deixar-les a la llista de la finestra oberta: SwiftUI hi demana copiar (camí d'inserir).
    L'editor sempre les mou.
- Com (pas 10, comprovat a l'SDK de les CLT de macOS 27.2 el 04/11/2026):
  - reordenar: `onMove` al `ForEach` de la llista d'una finestra. Les posicions són les de
    `move(fromOffsets:toOffset:)`, que són les de `Configuracio.mouPestanyes` (una prova ho compara en 186 casos);
  - cap a la barra lateral: `.itemProvider` a cada fila (conviu amb `onMove`, segons el binari de SwiftUI) i
    `dropDestination(for:action:)` amb `DropSession` a la fila de cada finestra, sense `isEnabled` (prova 7b).
    `dropConfiguration` decideix en cada arrossegament (`Editor.acceptaPestanyes`): `.move`, o `.forbidden` a la fila
    de la finestra que es veu, tret que s'hagi obert arrossegant; `deixaAnar` ho torna a comprovar. El cursor no hi
    porta el signe de prohibit (SwiftUI hi demana NSDragOperationNone);
  - `.dragConfiguration`: dins de l'app, copiar i moure (la destinació sempre demana moure); cap a una altra app, res.
    No està comprovat que SwiftUI l'apliqui a l'arrossegament d'una fila de `List` (l'SDK només en dona l'exemple
    amb `draggable` i `dragContainer`): és una barrera més, no l'única;
  - pla B, si a la prova 6 no es mouen totes les triades o `.itemProvider` trenca `onMove`: `dragContainer`,
    `draggable(containerItemID:)` i `dragContainerSelection` (macOS 26). `reorderable()` i `reorderContainer`
    són només de macOS 27.
- El contingut arrossegat és un tipus propi (`cat.davide.warp-launch.pestanyes`, el mateix del porta-retalls, declarat
  a `Info.plist` i conforme només a `public.data`), **mai text**:
  si es deixés anar a Warp, hi enganxaria `claude --dangerously-skip-permissions …` al prompt.
  - Amb visibilitat `.ownProcess` (a la fila, `NSItemProvider.registerDataRepresentation(…, visibility: .ownProcess)`):
    cap altra app no el veu. `PestanyaArrossegada` només el llegeix (`DataRepresentation(importedContentType:)`): no
    l'exporta mai, ni dins de l'app.
  - La finestra del JSON porta la marca de l'execució de l'app (`PestanyaArrossegada.aquestProces`): el que arriba
    d'una altra execució, que pot tenir els mateixos id, no mou res.
- Res no surt de l'app: ni cap al Finder, ni `ShareLink`. Ho vigila la prova de guarda (secció 3).
- Cada moviment és un sol pas de Desfés. Alternativa: «Mou a ▸», al menú contextual i a Pestanya › Mou a ▸.
- A «Per revisar» no es reordena (cada secció és una part d'una finestra), però sí que es pot deixar anar a una fila,
  obrir una finestra arrossegant i fer servir «Mou a ▸».

### Ordres

| Acció | Menú | Drecera | També |
|---|---|---|---|
| Nova finestra | Fitxer | ⌘N | fons de la barra lateral |
| Nova pestanya… (demana la carpeta) | Fitxer | ⌘T | `plus` a la barra d'eines, menú contextual |
| Duplica la pestanya / les pestanyes / la finestra (sense nom fix) | Fitxer | ⌘D | menú contextual |
| Canvia el nom | Fitxer | cap al menú; Retorn a la llista i a la barra lateral | menú contextual |
| Importa de Warp… / Torna a importar-ho tot de Warp… | Fitxer | — | estat buit; desactivada mentre s'obre res a Warp o s'aplica una actualització, i amb un full d'obrir o de lligar a la vista (0.32.8): el full activa uns segons la restauració (D19). Amb el full d'importar obert, no es pot començar cap obertura |
| Actualitza l'estat de Warp (0.32.6; abans, «Torna a llegir Warp») | Fitxer | — | menú de la icona i peu del full d'importació; desactivada sense el permís, mentre ja es llegeix i mentre s'obre res a Warp o s'aplica una actualització (0.32.7) |
| Mostra el fitxer al Finder (el fitxer, o la carpeta si encara no n'hi ha) | Fitxer | — | Configuració |
| Obre a Warp… | Fitxer | **cap** | desactivat fins a la fase 3, sempre amb confirmació |
| Tanca / Tanca-ho tot | Fitxer | ⌘W / ⌥⌘W | les del sistema |
| Desfés / Refés, amb el nom de l'acció | Edició | ⌘Z / ⇧⌘Z | — |
| Retalla / Copia / Enganxa (pestanyes) | Edició | ⌘X / ⌘C / ⌘V a la llista; ⌘V també a la barra lateral | menú contextual; «Enganxa les pestanyes» a la fila de la finestra i a la finestra buida |
| Elimina, sense confirmació | Edició | ⌫ | menú contextual |
| Barra lateral, inspector | Visualització | ⌃⌘S, ⌥⌘I | botó de l'inspector |
| Mou a ▸ («Cap altra finestra» si no n'hi ha) | Pestanya | — | menú contextual |
| Activa / Desactiva Claude | Pestanya | — | menú contextual |
| Copia l'ordre / Copia les ordres (text) | Pestanya | — | menú contextual i inspector |
| Mou amunt / Mou avall (finestra) | — | cap | menú contextual de la fila; o arrossegar-la |
| Configuració… / Surt de l’app Warp Launch (el text el posa macOS) | Warp Launch | ⌘, / ⌘Q | — |
| Comprova si hi ha actualitzacions… o, amb una versió a punt, Reinicia i actualitza a la X (0.32.2) | Warp Launch, després de «Sobre l’app Warp Launch» | cap | menú de la icona |

- **Una ordre que és a tots dos menús es diu igual** (en David, 09/11/2026, 0.32.6): «Actualitza l'estat de Warp», «Obre a Warp…», «Obre-ho tot a Warp…» i
  «Comprova si hi ha actualitzacions…»; i «Configuració…», «Sobre l’app Warp Launch» i «Surt de l’app Warp Launch», que al menú de l'app
  les posa macOS (`docs/fets-verificats.md`, «Els menús del sistema en català»). Ho comprova `laMateixaOrdreEsDiuIgualAlsDosMenus`. Aquí,
  «Fitxer» és el menú que macOS mostra en català com a «Arxiu».
- Una ordre que no s'aplica surt desactivada al menú i amagada al menú contextual. L'editor arriba als menús amb
  `FocusedValue`, i la columna que té el focus (`columnaEditor`: la barra lateral o la llista) decideix què fan
  Duplica i «Canvia el nom».
- Cap ordre que canvia la configuració s'aplica amb el full d'importació o el diàleg de carpetes oberts.
- ⌘D o «Mou a ▸» amb un nom a mig escriure: el nom i l'ordre són un sol pas de Desfés.
- ⌘S no fa res: l'app desa sola, i no hi ha cap «Desa». El grup del sistema `.saveItem` no es toca, perquè també
  porta «Tanca» i «Tanca-ho tot» (substituir-lo les treia, fins a la 0.13.0).

### Menú de la icona de la barra de menú

`MenuBarExtra` d'estil menú, amb un SF Symbol en mode plantilla, sempre visible.

1. «Mostra l'editor».
2. «Finestres»: una línia per finestra («empresa — 12 pestanyes, 8 amb Claude»). Obre l'editor amb aquella
   finestra seleccionada. **Lloc de R12:** a la fase 3, cada finestra serà un submenú amb «Obre a Warp…».
3. Què hi ha obert a Warp, i «Actualitza l'estat de Warp» (0.32.6; desactivada mentre ja es llegeix).
4. Si cal, els avisos: «La configuració té errors», «El fitxer ha canviat fora de l'app» o «No s'ha pogut desar».
   Cada un és un botó que obre l'editor, que diu què passa i com arreglar-ho. Les pestanyes amb avisos no hi surten
   (decisió d'en David, 04/11/2026). També «Configuració de prova: …» o «Sense configuració: …».
5. «Configuració…», «Comprova si hi ha actualitzacions…» (0.32.2; secció 11, 2.1; amb una versió a punt, «Reinicia i actualitza a la
   X»), «Sobre l’app Warp Launch» i «Surt de l’app Warp Launch» (**només** tanca Warp Launch; 0.32.6, amb els textos del menú de l'app).

Cada bloc és una `Section` sense títol (excepte «Finestres»), sense `Divider` solts: una `Section` amb títol seguida
d'un `Divider` feia dos separadors seguits.

### Dock i activació (R11)

- `LSUIElement`. Quan es mostra l'editor o la Configuració, l'app passa a `.regular` (Dock, ⌘⇥ i menú principal)
  i s'activa; quan s'amaguen totes dues, torna a `.accessory`.
- **Tancar l'editor l'amaga** (`orderOut`), no el destrueix. Dues raons:
  - BAMA va veure que tancar i tornar a obrir una `Window` de SwiftUI i després canviar l'estat bloquejava
    AppKit (fet de BAMA, no verificat aquí: es comprova a la prova 1);
  - la pila de Desfés és de la finestra, i amb `orderOut` no es perd. Si l'editor es destruís, una finestra
    esborrada amb ⌫ ja seria a disc al cap d'1 s i no es podria desfer.
- En arrencar, SwiftUI obre l'editor sol (és la primera escena). L'app passa a `.regular` a
  `applicationWillFinishLaunching`, abans que Launch Services l'activi: quan la vista de l'editor arriba a la
  finestra, encara no és visible (fets-verificats, «SwiftUI i AppKit»), i si s'esperava a veure-la, l'app es quedava
  sense Dock, sense ⌘⇥ i sense menú principal (revisió del pas 4).
- Obrir l'app des d'Apps o del Finder quan ja és oberta mostra l'editor (`applicationShouldHandleReopen`).
- `applicationShouldTerminateAfterLastWindowClosed` retorna `false`.
- `ca.lproj` al bundle, perquè els menús del sistema surtin en català.
- Sense menú del Dock, dreceres globals, notificacions ni `@AppStorage`. La selecció la guarda l'`Editor`.
- **Reobrir-se després d'una actualització automàtica (0.32.3, secció 11, 3.4):** sense editor, sense Dock i amagada, i el clic al Finder
  mostra l'editor encara que SwiftUI no l'hagi creat. Només amb l'intent de `actualitzacio.json`. **Vist a la ronda C, C4** (sense editor ni Dock, i el focus a l'app d'abans); el clic
  al Finder, no (C5).

### Avisos

Els calcula una funció pura del core (`Validacio`). Sempre amb icona i text, mai només color. Tres gravetats: **info**
(només a l'inspector), **avís** (triangle a la fila) i **error** (la pestanya no s'obriria com diu la configuració:
no hi ha ordre, o Claude s'aturaria). El CLI en mostra els avisos i els errors.

| Avís | Fila | Inspector |
|---|---|---|
| La carpeta no existeix | triangle i text | sota Carpeta, amb «Tria una carpeta…» |
| La carpeta és `~` | «Carpeta d'inici: probablement Warp l'ha perduda» | el mateix |
| Ultracode activat | — | «Comprova que el model l'admet i que tens els dynamic workflows activats» |
| Ultracode amb un esforç que no és «Molt alt» i `--settings` com a ruta de fitxer | triangle | no es pot generar l'ordre |
| «Salta els permisos» i un mode de permisos | triangle | «Amb "Salta els permisos", Claude no fa cas del mode» |
| Un mode de permisos que Claude no té (2.1.318: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`) | triangle | «Claude no arrencarà» |
| `--settings` que va de `{` a `}` però no és JSON vàlid (gramàtica estricta, com `JSON.parse`) | triangle | «Claude no arrencarà: els settings no són JSON vàlid» |
| Una opció que no és a la taula de Claude Code 2.1.318 | triangle | «Claude potser no l'entén»; si és d'una versió nova, cal posar al dia la taula. Si la segueix un text, l'avís diu que potser és el primer missatge |
| Les altres opcions porten una opció amb camp propi, o un text que no és de cap opció | triangle | no es pot generar l'ordre |
| Una opció d'un sol ús (`-w`, `--fork-session`, `--from-pr`, `--teleport`, `--rewind-files`…) | triangle | «es tornaria a fer a cada obertura» |
| Noms de finestra repetits (sense distingir majúscules) | triangle | text |
| Esforç desconegut | triangle | «Claude el deixa córrer i fa servir el de per defecte» (2.1.318 només avisa) |
| Claude apagat en una pestanya importada sense Claude, amb la carpeta ja vàlida | — | botó «Activa Claude» (no s'activa sol: decisió d'en David). La configuració no diu quines pestanyes són importades: surt a totes les que no tenen Claude i tenen una carpeta vàlida |

### Desviacions de mac-design

| Regla | Què fem | Per què |
|---|---|---|
| 7, 8 (entrades: panell de captura, drecera global) | Només la icona de la barra de menú i obrir des d'Apps | No és cap requisit, i una drecera global pot xocar amb Warp |
| 25 (UI optimista, sense confirmacions) | Editar: a l'instant, amb Desfés. Obrir Warp o Claude: sempre confirmació amb xifres | Obrir sessions no es pot desfer |
| 35, 74 (arrossegar cap a fora, `ShareLink`) | Només dins de l'app | No exportar carpetes ni opcions de permisos |
| 56 (revisar la captura) | Revisió visual feta per en David, o amb el seu OK | Regla 4 de CLAUDE.md |
| 75 (tornar a obrir les finestres en rellançar) | L'editor no s'obre sol (`restorationBehavior(.disabled)`) | A la fase 3, l'app arrencarà en iniciar sessió |
| 76 (TipKit) | Cap consell ni presentació | Una sola persona fa servir l'app |
| `InspectorCommands()`, ⌃⌘I (SKILL.md, toolbars.md) | Ordre pròpia «Mostra/Amaga l'inspector», amb ⌥⌘I (la de Pages, Keynote i Numbers) | A macOS 27.2, ⌃⌘I no feia res amb cap de les dues (proves 3 i 4); el clic al menú, sí |
| 68 (cada ordre també a la barra de menús) | «Mou amunt» i «Mou avall» de la finestra només al menú contextual i arrossegant | Un menú «Finestra» propi xocaria amb el del sistema, que en català es diu igual |

## 2. Configuració

### Fitxers (`~/.config/warp-launch/`)

- `configuracio.json`: la configuració. És d'en David.
- `estat.json`: el que l'app sap de Warp i de Claude (el pane i la sessió de cada pestanya). És de l'app.
- `preferencies.json` (0.29.0): el consentiment per gestionar la restauració de Warp i el `restore_session` d'abans del primer
  canvi de l'app. És de l'app (secció 10).
- `copies/configuracio-AAAAMMDD-HHMMSS-<motiu>[-N].json`: les 20 últimes còpies, amb els permisos del fitxer.
  Només compten els fitxers amb aquest nom exacte: la resta de `copies/` (fitxers, carpetes o enllaços d'en David)
  no es toca mai.

### Format v1

```json
{
  "versio" : 1,
  "generador" : "Warp Launch 0.7.0",
  "plantilla" : { "activat" : true, "continua" : true, "esforc" : "xhigh", "saltaPermisos" : true, "ultracode" : true },
  "finestres" : [ {
    "id" : "5C0E8A52-1F3B-4C9E-9A7D-0B6F2E4D8A11",
    "nom" : "empresa",
    "pestanyes" : [
      { "id" : "9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62", "titol" : "Botiga",
        "carpeta" : "/Users/prova/GitHub/empresa/botiga",
        "claude" : { "activat" : true, "continua" : true, "esforc" : "xhigh", "saltaPermisos" : true, "ultracode" : true } },
      { "id" : "7A8B9C0D-…", "titol" : "Web Host", "carpeta" : "/Users/prova",
        "claude" : { "activat" : false, "continua" : true, "esforc" : "xhigh", "saltaPermisos" : true, "ultracode" : true } }
    ] } ]
}
```

- **`id` propis** (UUID), perquè Warp renumera els seus cada vegada que desa.
- **Carpeta absoluta i canònica.** Si s'escriu `~/…` a mà, s'accepta i es normalitza.
- **Esforç i ultracode per separat.** `--effort ultracode` (i `"esforc": "ultracode"` escrit a mà) es desa com a
  `xhigh` més `ultracode`. Si `--settings` és JSON i porta `"ultracode": true`, la clau passa al camp `ultracode`.
  Un `false` s'hi queda si la pestanya no té ultracode: apaga el de la configuració de Claude de l'usuari.
- **Continuar:** només es desa la intenció (`continua`). Com es continua (D7) ho decideix qui llança, i per
  això D7 no ha canviat el format: es reprèn la conversa de la pestanya (`--resume <id>`) si l'app la sap, i si no,
  se'n comença una de nova. **Mai `--continue`** (D7), tampoc a l'ordre que es mostra i es copia (D15, 0.15.0).
- `controlRemot` té camp propi. La resta d'opcions que l'editor no entén van a `altres`, en ordre i literals.
  `-c`, `-r` i `--session-id` no es desen: són de la sessió, no de la pestanya. El primer missatge tampoc:
  s'enviaria de nou a cada obertura.
  - `altres` només porta opcions senceres, amb els seus valors. Si hi ha una opció amb camp propi o un text que
    no és de cap opció (un JSON editat a mà), no es pot generar l'ordre.
- Els textos fets només d'espais són com si no hi fossin.
- **Valors per defecte segurs** si el fitxer s'ha editat a mà:
  - si falta el bloc `claude`, la pestanya és només terminal (`activat: false`) i surt l'avís «Claude sense configurar»;
  - si el bloc és parcial: `saltaPermisos` false, `ultracode` false, `continua` true (R4);
  - **cap descodificació no dona `saltaPermisos: true` si el JSON no ho diu.** La `plantilla` només s'aplica
    quan l'app crea o importa una pestanya, i es copia (si després canvia, les pestanyes no canvien).
- Les claus buides no s'escriuen (excepte `controlRemot: ""`, que vol dir sense nom). JSON amb claus ordenades i
  sense escapar les barres, per poder-lo llegir i comparar. El que s'escriu ja és la forma canònica: tornar-lo a
  llegir i a escriure dona els mateixos bytes.
- **Una clau repetida dins d'un objecte és un error.** JSONSerialization i JSONDecoder es queden amb la primera, i
  `jq` o Python amb l'última: en David podria veure `"saltaPermisos": false` amb `jq` i l'app llegir-hi `true`.
- Només UTF-8 (amb BOM o sense). Una carpeta que no és absoluta, o que falta, dona un avís.
- Una `versio` més nova que la de l'app: l'editor obre en només lectura. Tot canvi de format puja la versió,
  porta una migració que no perd dades, i necessita l'OK d'en David (regla 11).

### Desar

- Desat automàtic 1 s després de l'últim canvi, i a l'instant en amagar l'editor o sortir.
- Escriptura atòmica, en aquest ordre (`MagatzemConfiguracio.desa`):
  1. Es torna a llegir el JSON nou per comprovar-lo.
  2. Si el fitxer és només de lectura (permisos o bloquejat al Finder), no es fa res.
  3. Fitxer temporal a la mateixa carpeta, amb els permisos del fitxer, i `fsync`.
  4. Còpia, si cal.
  5. `rename` sobre el fitxer (o sobre la destinació, si és un enllaç simbòlic, que es manté).
  6. Només llavors s'esborren les còpies que sobren: un desat que falla no esborra mai cap còpia.
- **Còpia** al primer desat de cada sessió de l'app, abans d'esborrar una finestra amb pestanyes i abans de tornar
  a importar. També (motiu `fora`) quan el fitxer del disc no és com l'escriuria l'app (editat a mà, amb claus
  desconegudes o sense id), perquè en desar se'n perdria alguna cosa. Si la còpia falla, no s'escriu. Si la còpia
  més recent ja té els mateixos bytes, no se'n fa cap altra (els reintents no omplen `copies/`).
- Un fitxer que no es pot llegir, o un enllaç trencat, és un error i no «no hi ha configuració»: si no, l'app en
  crearia una de nova al damunt.
- **Canvis fets fora de l'app:** abans de desar, es comparen els bytes del disc amb els últims que s'han llegit.
  Si no coincideixen, no s'escriu i surt un bàner: «El fitxer ha canviat fora de l'app» amb «Torna a carregar».
- Fitxer malmès: l'editor obre en només lectura i diu la línia i la columna.
- **Llegir no escriu mai res,** ni crea la carpeta.
- Si no es pot desar, ho diuen un bàner amb «Torna-ho a provar», el subtítol i el menú de la icona. Sortir amb
  canvis sense desar és l'únic cas que demana confirmació.

### Plantilla i Configuració (pas 11)

- La `plantilla` (les opcions de Claude de les pestanyes noves i de les importades sense sessió) es canvia a la
  Configuració (⌘,) › «Pestanyes noves»: les opcions, l'ordre que en surt amb els seus avisos i les «Altres opcions» (només
  lectura). El fitxer (carpeta, «Mostra al Finder», versió, i l'error de desat si n'hi ha) és a «General».
- **Dues pestanyes (0.30.2):** «General» (En iniciar sessió, Fitxer, Diagnòstic i, des de la 0.31.0, «Deixar de fer servir
  Warp Launch») i «Pestanyes noves» (la plantilla, l'Ordre i les Altres opcions; des de la 0.30.3, la primera secció no té
  títol, decisió 12 del 08/11/2026). Cada pestanya és un `Form` agrupat de 520 pt d'amplada, tan alt com el contingut i com a
  molt de 640 pt; el que no hi cap es desplaça a dins (`frame(maxHeight:)` i `fixedSize` vertical, amb
  `.windowResizability(.contentSize)`: `fets-verificats.md`). En canviar de pestanya, la finestra canvia d'alçada per baix, amb
  la vora de dalt i les pestanyes quietes (`windowResizeAnchor(.top)`). Mida fixa per pestanya, com a macOS (decisió 11 del
  08/11/2026). L'app no desa quina pestanya es veia. Fins a la 0.30.1, una sola pàgina feia l'alçada de tot el contingut, més
  que la pantalla, i el «Diagnòstic» del final no s'hi podia fer servir.
- **Dos Desfés que no es barregen.** El de la plantilla és el de la finestra de Configuració
  (`Editor.desferPlantilla`); el de l'editor només desfà finestres, pestanyes i selecció. ⌘Z a la Configuració no
  toca l'editor, ni al revés. Tornar a carregar els buida tots dos.
- El nom de sessió de la plantilla, si n'hi ha (escrit a mà), no es copia mai a cap pestanya: totes tindrien el
  mateix nom (decisió d'en David, 04/11/2026). La Configuració el mostra amb «(no s'aplica)», i l'ordre i els avisos
  que hi surten són els de les pestanyes noves, sense el nom (`perAPestanyaNova`).
- Sense configuració, la Configuració mostra la plantilla que tindrà la nova, la mateixa si s'importa de Warp que si es
  comença en blanc (`plantillaVisible`).
  Mentre es carrega o si el fitxer no es pot llegir, no en mostra cap: no se sap quina és.
- **Plantilla d'importar segura (0.28.0, D11 revisada per en David el 07/11/2026):** sense fitxer, la plantilla d'importar és
  `.perOmissio` (`claude` continuant la conversa, sense saltar els permisos ni ultracode), la mateixa que «Comença en blanc».
  Abans era `.habituals` (salta els permisos, «Molt alt» i ultracode), que ara només és a les proves. Les opcions es trien a la plantilla (Configuració ›
  «Pestanyes noves») o per pestanya a l'inspector. Una configuració que ja existeix conserva la seva plantilla.
- Si la plantilla canvia amb el full d'importació obert, no es pot confirmar fins a tornar a llegir Warp: si no,
  s'importaria amb una plantilla que el full no ha mostrat.
- Tancar la Configuració desa; mostrar-la mira si el fitxer ha canviat fora.

### Importació (R2)

Una funció pura (`Importador.importa`): rep la lectura de Warp, la carpeta d'inici, la plantilla i un generador d'id,
i no toca el disc.

- **Finestres:** en l'ordre de la lectura; les que no tenen cap pestanya de terminal no s'importen (nota). Nom: la carpeta pare que reuneix més de la meitat de les pestanyes
  (sense les de `~`), o «Finestra N». La carpeta d'inici i l'arrel no serveixen de nom. Els repetits (sense
  distingir majúscules) porten « 2», « 3»… Es poden canviar a l'editor.
- **Pestanyes:** només les de terminal, en l'ordre de la lectura (verificat per en David en una finestra).
  Títol: el de Warp; si és buit, l'últim component de la carpeta; si la carpeta és `~`, «Pestanya N». Pane
  principal: el primer amb Claude, o el primer. Una pestanya dividida en diversos panes dona una nota (D9).
- **Claude** (decisió d'en David, D11; la plantilla d'importar és la segura des de la 0.28.0, vegeu «Plantilla i Configuració»):
  - **amb sessió viva:** les opcions del seu argv, més `continua: true` (R4). El nom fix només si venia de `-n`;
  - **sense sessió:** **només terminal** (0.29.1, D-P5a, en David, 07/11/2026): la plantilla amb `activat: false`, origen
    `.nomesTerminal`. Des de la 0.31.5, també en tornar a importar (en David, 09/11/2026, revisa D11): abans, sobre una
    configuració amb alguna pestanya, s'hi obria Claude amb la plantilla. També al CLI;
  - **sense sessió, a `~` o amb una carpeta que no existeix:** la plantilla amb `activat: false` («Activa Claude» ja hi troba
    les opcions);
  - **sessió viva en una altra carpeta que la pestanya (0.31.5, en David, 09/11/2026):** mana la de Claude, amb una nota
    (`.carpetaDeLaSessio` si Warp era a `~`, `.carpetesDiferents` si no), excepte si la de Claude és `~` o no existeix: es queda la
    de Warp, amb `.carpetaDeClaudeNoServeix` (si aquesta és `~`, vegeu el cas de sota). Avís a «Per revisar» (`Validacio.avisCarpetaDeClaude`): amb la carpeta de Warp de
    l'última foto o de la importació (`EstatSessions`, només a la memòria: el format d'`estat.json` no canvia) i, sense, amb
    `carpetaSessio` (l'últim Claude). Si Warp és a `~`, sense avís: només la nota. «Lliga amb Warp…» i `potserJaOberta` comparen
    totes dues carpetes;
  - **Warp a `~` i sessió viva en una carpeta que no existeix (0.31.5, decisió del 09/11/2026):** no hi ha cap carpeta bona, i
    Claude s'engegaria a `~`. Es queda a `~` amb `activat: false` i les opcions de la seva ordre (no les de la plantilla), origen
    `.carpetaInici` i nota `.claudeSenseCarpeta`. El pane i la conversa continuen al vincle;
  - **altres sessions vives a `~` o en una carpeta que no existeix** (Warp i Claude a la mateixa, o Warp en una carpeta bona):
    Claude activat, amb la seva ordre (D11: «les que ja tenen Claude conserven la comanda llegida»), i l'avís de la carpeta.
    En aquella lectura, cap.
- **Notes** (el full i el CLI les mostren): primer missatge descartat, sessió que reprenia una conversa concreta
  (`--resume <id>`, `--session-id`), carpetes de la sessió i de la pestanya diferents, panes descartats,
  finestres sense pestanyes de terminal i sessions sense pestanya. Aquestes no s'importen, i la nota diu quina
  pestanya importada sense Claude viu és a la mateixa carpeta: potser és la seva (dins de tmux, per exemple) i no en porta les
  opcions.
- **Exemple** (xifres inventades): una lectura de 4 finestres i 30 pestanyes, 6 amb una sessió viva, 18 sense sessió en una
  carpeta que existeix i 6 a `~` o amb una carpeta que ja no hi és: «6 amb Claude, amb la seva ordre · 24 només terminal (18
  sense Claude obert)» (en una configuració nova des de la 0.29.1, i en tornar a importar des de la 0.31.5). El full de
  previsualització ho diu amb aquestes xifres.
- **Quan:** mai sola. «Importa de Warp…» mostra un full de previsualització, i el fitxer s'escriu en prémer
  «Crea». «Torna a importar-ho tot…» substitueix la configuració, amb còpia i Desfés.
- **CLI:** `warp-launch importa` mostra el resultat sense escriure res. `--desa` exigeix `--config <carpeta>`:
  la configuració real només es crea des de l'app. `--config` no pot ser la real, ni a través d'un enllaç, ni amb
  altres majúscules, ni una carpeta de dins; si la carpeta ja té configuració, no la trepitja.

## 3. Arquitectura

- **`WarpLaunchCore`** (structs i enums `Sendable`, sense AppKit):
  `Configuracio`, `Estat`, `OrdreClaude` (de la configuració a l'argv), `Importador`, `MagatzemConfiguracio`,
  `Validacio` (avisos), les operacions d'edició (afegeix, elimina, duplica, mou) i la lògica del CLI
  (`OrdreCLI.executa(args, lector:, magatzem:, sortida:) -> Int32`, perquè es pugui provar amb fixtures).
- **`WarpLaunchUI`** (library nova, `@MainActor`): `Editor` (`@Observable`: configuració, selecció, Desfés amb
  el nom de cada acció, desat diferit amb un rellotge injectat), les vistes i el tipus que s'arrossega.
  Rep el lector i el magatzem injectats.
- **`WarpLaunchApp`** (executable prim): escenes, `AppDelegate`, el coordinador d'activació (Dock) i
  l'argument `--config <carpeta>`. Aquí no hi ha proves.
- **`WarpLaunchCLI`:** només passa a `OrdreCLI` els valors reals.
- **Concurrència:** la lectura de Warp fora del fil principal (té un `busy_timeout` de 3 s). El JSON, petit, al
  fil principal.
- **El magatzem no té ruta per defecte:** l'app i el CLI hi passen `~/.config/warp-launch/` o el `--config`.

### Prova de guarda

Una prova llegeix el codi del repo (`#filePath`) i falla si:
- a `Sources/` hi ha `warp://`, `Process`, `NSWorkspace` (excepte `NSWorkspace.shared.activateFileViewerSelecting(`,
  «Mostra al Finder», que només pot ser a `Finder.swift`), `openURL`, `NSAppleScript`, `posix_spawn`, `system(`, la família
  `exec` (`execv`, `execvp`…), les `NSUser…Task`, `SMAppService`, `LaunchAgents`, `UserDefaults`, `@AppStorage`,
  `NSRunningApplication`, `forceTerminate`, `launchApplication`, `openApplication`, `kill` o `killpg` (regla 2: no tancar
  Warp ni Claude). `Process`, `kill` i `killpg` compten com a paraula sencera, també sense cridar (`Process.init()`, `let k =
  kill`; 08/11/2026);
- «Obre a Warp…» no és `.disabled(true)` o té drecera, o `Ordres.swift` substitueix `.saveItem` (es
  perdrien ⌘W i ⌥⌘W);
- a `Sources/` hi ha `ShareLink`, `ProxyRepresentation`, `FileRepresentation`, `CodableRepresentation`, `.onDrag`,
  `NSFilePromiseProvider`, `suggestedFileName`, `registerObject` o `.register(` (el que s'arrossega no surt de
  l'app); o `Arrossegar.swift` no té `visibility: .ownProcess` i `DataRepresentation(importedContentType:`, o hi surt
  `visibility: .all`, `exportedContentType` o `DataRepresentation(contentType:`;
- la fila d'una finestra de `VistaEditor.swift` té `isEnabled: editor.acceptaPestanyes`, o no decideix l'operació
  amb `dropConfiguration` (`PaquetTests.laFilaDeLaFinestraDecideixEnArrossegar`);
- a `Tests/` hi ha `ProcessosDelSistema`, `rutaPerDefecte`, `carpetaPerDefecte`, `.config/warp-launch`, la carpeta d'inici de debò per
  qualsevol camí (`homeDirectoryForCurrentUser`, `NSHomeDirectory`, `URL.homeDirectory`, `expandingTildeInPath`, `getenv(`,
  `environment["HOME"]`, `getpwuid`; 08/11/2026), `NSApp`, `NSApplication`, `NSWindow`, `NSHostingView`, `NSPasteboard` o
  `PortaRetallsSistema.enganxa/hiHaPestanyes/escriu` (el porta-retalls d'en David). Tampoc `AjustRestauracio(` sense una ruta
  de prova, ni `LectorTranscripcions(` o `LectorConfianca(` (també amb `.init(`) sense ruta. `Lector`, `LectorWarp` i
  `LectorAjustosWarp` ja no tenen cap valor per defecte (ronda 6, decisió 7): una prova que s'oblidi una ruta no compila, i
  les rutes de debò continuen prohibides a les proves (`rutaPerDefecte`, la carpeta d'inici).
- `Lector(carpetaSessions:)` i `LectorSessions(carpeta:processos:)` tornen a tenir un valor per defecte, o hi ha una línia de
  `Sources/` amb `carpetaPerDefecte`, `.claude/sessions` o `ProcessosDelSistema` fora de la llista fixa (l'app i el CLI hi
  posen `LectorSessions.carpetaPerDefecte`; 08/11/2026). Una prova que s'oblidés la carpeta no compila.
- a `Sources/`, una línia crea un `LectorTranscripcions` o un `LectorConfianca` de debò fora d'una llista fixa de 12 línies
  (`lectorsDeClaudeDeDebo`, 08/11/2026): les 4 de l'app i del CLI, que hi passen la ruta de debò, i, als fitxers dels dos
  lectors, la declaració de cada tipus, de cada `init` i de cada ruta per defecte. **Des del 08/11/2026, els dos `init` ja no
  tenen ruta per defecte** (`init(carpeta: URL)`, `init(ruta: URL)`): una prova que se l'oblidi no compila. Hi compten el nom
  (també amb `.init`, `.self` i el mòdul), un valor per defecte (també a la línia següent), les rutes per defecte, un àlies,
  una extensió (també partida en dues línies) o una altra declaració del tipus, qualsevol `init` nou als seus fitxers
  (`init()`, `init?(`, `init<T>(`), i, a tot `Sources/`, `.init(carpeta:` i `.init(ruta:` sense el nom del tipus (també amb
  `type(of:)` o amb els arguments a la línia següent).
- **Els lectors de Warp de debò (ronda 6, decisió 7; `elsLectorsDeWarpDeDeboNomesDeLAppIDelCLI`):** a `Sources/`, una línia crea
  un `LectorWarp`, un `LectorAjustosWarp` o un `Lector`, o en diu la ruta, fora d'una llista fixa de 20 línies
  (`lectorsDeWarpDeDebo`): les de l'app i del CLI, les del core que fan servir la ruta que els passen, les declaracions de cada
  tipus, de cada `init` i de cada ruta per defecte, i el `Lector` privat que llegeix JSON, que és un altre tipus. Cap paràmetre
  del `init` de `Lector` no pot tornar a tenir un valor per defecte (tampoc `inici`), i la carpeta d'inici de debò només pot
  sortir a les línies fixes de l'app, del CLI i de les rutes de debò. La lògica és la dels lectors de Claude (`lectorsDeDebo`,
  comuna), i hi compta també un espai davant del parèntesi (`LectorWarp (ruta: r)` compila igual).
- **`settings.toml` (0.31.2, decisió A; `nomesLAjustCreaElFitxerDeWarp`):** fora d'`AjustRestauracio.swift` hi ha alguna
  crida que posa un fitxer al seu lloc només si no n'hi ha cap, que l'enllaça o que hi copia un altre fitxer (`renamex_np`,
  `renameatx_np`, `RENAME_EXCL`, `RENAME_SWAP`, `link`, `symlink`, `linkat`, `clonefile`, `linkItem`, `createSymbolicLink`,
  `copyfile`) o el ganxo de les proves (`ganxoDeProva`), o hi ha `O_CREAT` fora d'`EscripturaAtomica.swift` i
  `FitxersLaunchWarp.swift`. També falla si l'ajust té més d'un `renamex_np` (el de `RENAME_EXCL`) o més d'un `copyfile` (el
  dels atributs estesos, de `settings.toml` al fitxer temporal), crea carpetes o obre res per escriure-hi directament
  (`escriuenDirectament`: `open(`, `.write(`, un `FileHandle` per escriure, `O_WRONLY`, `O_RDWR`, `O_APPEND`, `fopen`,
  `openat`, `creat(`, `truncate`). I si la ruta de debò de `settings.toml` surt fora de 5 línies fixes (el lector, l'app, el CLI i
  la seva ajuda). Una mostra demostra que cada línia falla a qualsevol altre fitxer, també als dos amb `O_CREAT`.
  **Des del 08/11/2026 (0.31.3 i després):** l'ajust només té un `rename(` (el de `substitueix`, just després de mirar que el
  fitxer encara és el que s'ha llegit, sense cap funció entremig) i un `removeItem` (el del fitxer temporal); no pot fer servir
  `renameat`, `unlink`, `unlinkat`, `rmdir`, `remove`, `removefile`, `trashItem` ni `mkdirat`, ni el `write` de C, ni cap de les
  crides que obren o creen fitxers o en canvien els permisos o els atributs (als punts de sota). La línia de l'app que el crea és
  fixa (`lAjustDeWarpNomesLEscriuLApp`): `potCrearElFitxer: { lector.warpHaAcabatDArrencar() }` i el rellotge de sèrie.
- **Obrir, crear o escriure per altres camins (08/11/2026):** el diagnòstic, la carpeta de Warp (`FitxersLaunchWarp`) i l'ajust
  no poden fer servir `openx_np`, `mkstemp` i la seva família, `mkdtemp`, `mkdirx_np`, `mkpath_np`, `mkpathat_np`, `mkfifo`,
  `mknod` ni `CFWriteStreamCreateWithFile` (`altresObrenOCreen`). El diagnòstic i l'ajust tampoc no poden fer servir el `write`
  de C (`write`, `pwrite`, `writev`, `pwritev`); la carpeta de Warp sí, per al fitxer que acaba de crear.
- **Permisos i atributs de fitxers, a tot `Sources/` (ronda 6, decisió 7; `nomesDuesCridesCanvienElsPermisosIElsAtributs`):** cap
  línia no pot canviar els permisos, el propietari, les marques, les dates, les ACL o els atributs estesos d'un fitxer, tampoc
  en un comentari (`altresCanvienAtributs`: les famílies `chmod`, `chown` i `chflags`, `chmodx_np`, `setAttributes`,
  `setResourceValue(s)`, `exchangedata`, `setxattr`, `removexattr`, `setattrlist`, `utimes` i les seves, `acl_set_…` i
  `CFURLSetResourceProperty…`). Hi ha dues úniques excepcions (`canvienAtributsPermesos`), cadascuna al seu fitxer i un sol cop,
  just després de l'`open` amb `O_EXCL` del fitxer que la mateixa funció acaba de crear, sense cap altra funció ni cap altre `fd`
  entremig: el `fchmod` d'`EscripturaAtomica.creaFitxerNou` i `fchmod(fd, 0o644)` a `FitxersLaunchWarp.swift`. L'ajust no en fa
  servir cap. Les que només llegeixen (`getxattr`, `getattrlist`, `attributesOfItem`, `resourceValues`) no hi compten.
- l'app no llegeix Warp amb `Lector.llegeixDeLApp` a les dues lectures de `WarpLaunchApp.swift`
  (`lAppLlegeixWarpAmbLaLecturaDeLApp`, 0.31.2).

- **Actualitzacions (de la 0.32.0 a la 0.32.3 i publicació):** secció 11, apartat 10. Cap excepció de xarxa: a `Sources/` no hi pot
  haver cap crida de xarxa, tampoc al servei; Sparkle les fa des del framework, i només `ServeiActualitzacions.swift` l'importa. Dues
  excepcions, només per als noms que imposa Sparkle: el delegat `updaterWillRelaunchApplication`, que porta `launchApplication` a dins, i la firma
  del delegat que avisa de la baixada.

Una altra prova comprova que cada expressió troba el que ha de trobar. Així les proves no poden llegir l'estat real,
ni tocar el porta-retalls, ni fer sortir el procés de proves al Dock. **Cap expressió no fa servir `\b`** (08/11/2026): a les
expressions regulars de Swift, el límit de paraula és el d'Unicode, i `Foundation.Process()` o `NSApp.terminate(nil)` hi són
una sola paraula (`fets-verificats.md`). Davant del nom va `(^|[^A-Za-z0-9_])` i darrere, `(?![A-Za-z0-9_])`, i una prova
falla si una línia que no és un comentari torna a fer servir `\b` (`capGuardaFaServirElLimitDeParaula`). Les guardes de la
fase 3.1 són a la secció 7 («Seguretat»), i les del consentiment, de trobar Warp, del diagnòstic i de deixar de fer servir l'app,
a la secció 10.

## 4. Passos

Cada `feat:` porta proves i el bump de `VERSION` i de `WarpLaunch.versio`. Es verifica amb `swift build`,
`scripts/test.sh` i, quan toca, `scripts/build-app.sh`. **Cap pas obre l'app, Warp ni Claude, si no diu «amb OK».**

1. **`docs:` / `chore:`** Aquest document, la skill `mac-design`, la regla `deny` per a `~/.config/warp-launch/`
   i els frameworks de macOS que es faran servir, a `CLAUDE.md`.
2. **0.3.0 — format v1.** `Configuracio` i les seves proves: anada i tornada, un fitxer «golden», valors per defecte
   segurs (`saltaPermisos` mai per omissió), `"esforc": "ultracode"`, id repetits o absents, claus desconegudes,
   versió més nova.
3. **0.4.0 — magatzem.** Escriptura atòmica, còpies (20; mai les d'altri), canvi extern, fitxer malmès, llegir no
   escriu. Sempre en una carpeta temporal.
4. **0.5.0 — esquelet de l'app.** Escenes, menú de la icona, editor amb la llista de finestres d'una configuració
   (i «Nova finestra», per poder canviar l'estat), activació, amagar en tancar, `ca.lproj`, `--config` i la prova
   de guarda. El menú de la icona diu quantes finestres i pestanyes té Warp (lectura en segon pla).
   - Fet (0.5.0). «Comença en blanc» crea la configuració amb la plantilla segura (sense saltar permisos), fins
     que en David la canviï a la Configuració (pas 11). «Importa de Warp…» surt desactivat fins al pas 6. El menú
     de la icona diu «Configuració de prova: …» quan l'app s'obre amb `--config`, i l'editor també (a l'estat buit
     i a sota de la barra lateral). Warp es llegeix en obrir l'app i amb «Actualitza l'estat de Warp», no cada vegada que
     es mostra l'editor.
   - Revisió (abans de la prova 1): un `--config` mal escrit (`--confg`, ruta relativa, sense carpeta, repetit)
     ja no torna a la configuració real: l'app s'obre sense cap configuració i diu per què. S'accepta
     `--config=<carpeta>`, i `~/` es resol amb la carpeta d'inici. Una carpeta no absoluta ja no fa una còpia a
     cada desat, i la còpia de sessió ja no es perd si el primer desat no canviava res.
   - **Prova 1 feta (04/11/2026):** totes les comprovacions bé, amb 0.5.1; 20 cicles sense bloqueig. Corregit
     pel camí: ⌘Z no feia res (l'editor ara fa servir el Desfés de la finestra), i macOS no deixava llegir Warp
     (D12: certificat propi i permís a Arxius i carpetes; l'error ara diu què cal fer). L'app llegeix Warp amb
     les mateixes xifres que el CLI. Falta veure que el permís duri en recompilar (a la propera versió).
   - **Prova 1, amb OK:** en David obre `build/Warp Launch.app` amb `--config` a una carpeta temporal. S'obren
     0 finestres de Warp i 0 sessions de Claude. Comprovacions: l'editor surt al davant; l'app és al Dock i a ⌘⇥,
     amb els menús en català; en amagar l'editor desapareix del Dock; 20 vegades obrir, afegir una finestra,
     amagar i tornar a obrir, sense bloqueig; obrir des del Finder mostra l'editor; ⌘, surt al davant; si macOS
     demana permís per llegir les dades de Warp; «Surt» només tanca Warp Launch.
5. **0.6.0 — ordre de Claude.** `OrdreClaude` i proves: per a cada combinació d'esforç, ultracode i `--settings`,
   llegir l'ordre generada torna la mateixa configuració; la de la plantilla `.habituals` de les proves dona les mateixes
   opcions.
   - Fet (0.6.0). `OrdreClaude.argv(_:represa:)` i `OrdreClaude.text(_:)`; `ClaudePestanya(_ opcions:)` per
     llegir-la de tornada (la farà servir la importació).
     - La plantilla `.habituals` de les proves donava exactament `claude --dangerously-skip-permissions --effort ultracode --continue`
       (0.6.0); des de la 0.15.0 (D15), sense `--continue`.
     - Ultracode: amb «Molt alt», l'àlies `--effort ultracode`; amb un altre esforç, `"ultracode": true` dins de
       `--settings` (s'afegeix al JSON que hi hagi). Error si `--settings` és un fitxer (per a Claude, tot el que
       no va de `{` a `}`), si no és un JSON vàlid o té claus repetides, o si ja hi ha `"ultracode"` amb un valor
       que no és booleà.
     - Continuar: només si la pestanya diu `continua`; `Represa.darrera` (`--continue`) o `.sessio(id o nom)`
       (`--resume`). Ho tria qui llança (D7).
     - **Canviat a la 0.15.0 (D7 i D15):** sense `Represa` ni `--continue`. `argv(_:repren:)` rep la conversa a totes
       les crides, sense valor per defecte: amb `continua` i una conversa, `--resume <id>`; si no, una de nova.
     - Un valor que comença per «-» va com a `--opcio=valor`. `--remote-control` sense nom va al final.
     - El text porta cometes simples on calen, també davant d'un «=» inicial (zsh), i una prova el fa llegir
       a zsh i a sh i comprova que en surt el mateix `argv`.
   - **Revisió** (dos revisors i un verificador per troballa; 9 troballes confirmades, 5 descartades):
     - `OpcionsClaude.analitza` llegeix com Claude Code: commander i la taula de les seves opcions
       (`TaulaOpcionsClaude`, de la 2.1.318).
       - Separa el primer missatge (`prompt`), que no es desa.
       - Entén les variàdiques, `-cw`, `-nBotiga` i `--`.
       - Marca les opcions desconegudes.
       - Comparat amb el `parseOptions` del binari en 20.000 ordres (docs/fets-verificats.md).
     - `--settings`: la regla JSON de Claude, i mana l'últim. `"ultracode"` només compta si és booleà, i un `false`
       explícit no es perd.
     - `altres` es comprova abans de generar l'ordre: opcions amb camp propi, textos i `--` hi donen error.
     - Textos fets només d'espais, fora; `--resume` amb una sessió feta d'espais, error.
     - **Queda per al pas 6:** l'avís de «Salta els permisos» amb un mode (Claude no fa cas del mode) i els altres
       avisos nous de la taula. També cal dir, a la importació, si s'ha descartat un primer missatge.
6. **0.7.0 — importació i avisos.** `Importador`, `Validacio`, `OrdreCLI` i `warp-launch importa`. Proves amb un
   escenari de la mateixa forma que una lectura real, sessió a `~`, sessions sense pestanya,
   codis de sortida, `--desa` sense `--config`.
   - La importació diu quan descarta el primer missatge d'una sessió.
   - Opcions d'un sol ús, com `-w` (un worktree nou), `--fork-session` o `--from-pr`: a cada obertura en farien
     un de nou. Avui cap sessió no en porta. Si n'apareix alguna, en David decideix si es descarten amb un avís.
   - Fet (0.7.0). `Importador.importa`, `Validacio.avisos`, `OrdreCLI.executa` (la lògica del CLI, provada amb una
     base de Warp de prova) i `warp-launch importa [--json] [--desa --config <carpeta>]` i
     `warp-launch configuracio valida [--config <carpeta>]`. Codis de sortida: 0, 1 (no s'ha pogut llegir o
     desar), 2 (la configuració, llegida o importada, té errors) i 64 (ús).
     - Amb una lectura real (04/11/2026): les pestanyes amb una sessió viva conserven la seva ordre, les altres reben la
       plantilla, i les de `~` o amb una carpeta que no existeix queden sense Claude i amb un avís; 0 errors i cap nota.
     - Les opcions d'un sol ús es queden a `altres` amb un avís; si se n'han de treure, ho decideix en David
       quan n'aparegui una.
     - L'app encara no importa: el full d'importació és del pas 8.
   - **Revisió** (un revisor; 4 troballes segures i 4 dubtoses, totes ateses):
     - `importa --desa --config` podia escriure la configuració real mentre no existeix (a través d'un enllaç a
       `~/.config` o de `/System/Volumes/Data`). Ara es fa canònic l'avantpassat que existeix, i es rebutgen `..`
       i els enllaços trencats.
     - `--settings` es valida amb la gramàtica estricta de JSON (`JSONEstricte`): `JSONSerialization` acceptava
       comes finals, que aturen Claude.
     - El text que segueix una opció desconeguda surt a l'avís: potser és un primer missatge.
     - La carpeta de la sessió només substitueix la de la pestanya si aquesta és a `~` (com deia el disseny).
     - Les notes de sessions sense pestanya diuen quina pestanya és a la mateixa carpeta; `importa` surt amb 2 si
       hi ha errors.
7. **0.8.0 — model de l'editor.** Operacions d'edició i `Editor`: fer, desfer i refer cada ordre amb el seu nom;
   N canvis fan un sol desat; error i reintent; canvi extern.
   - Fet (0.8.0). Operacions pures al core (`EdicioConfiguracio.swift`): afegir, eliminar, duplicar, canviar el
     nom, moure i canviar pestanyes. L'`Editor` hi afegeix:
     - la selecció de pestanyes (diverses), que es buida en canviar de finestra i segueix les pestanyes que es
       mouen a una altra finestra;
     - un pas de Desfés per ordre, amb el seu nom («Nova pestanya», «Elimina les pestanyes», «Mou la pestanya»,
       «Canvia l'esforç»…). Desfer torna la configuració **i la selecció** d'abans. Una ordre que no canvia res no
       en fa cap. Els canvis de text seguits d'un mateix camp (`agrupa`) en fan un de sol;
     - els avisos de la configuració, al dia a cada canvi;
     - les còpies: `esborrat` quan desapareix una finestra amb pestanyes (eliminar-la, o desfer-ne la creació) i
       `importacio` en tornar a importar, a més de la de sessió. Si el canvi es desfà abans de desar, no en cal;
     - el canvi extern: cada vegada que l'editor passa al davant, mira els bytes del fitxer. Sense canvis a l'app,
       el torna a carregar (i el Desfés d'abans es perd); amb canvis, no toca res i surt el bàner;
     - la importació: `previsualitza` (no escriu res), `crea(amb:)` quan no hi ha configuració (D11; la plantilla és
       la segura, `.perOmissio`, des de la 0.28.0; abans, `.habituals`) i `substitueix(amb:)` («Torna a importar»), amb
       còpia i Desfés, que conserva la plantilla.
   - Diferències amb el pas 4: «Nova finestra» va després de la seleccionada, no al final. Una pestanya nova a `~`
     queda sense Claude, com a la importació.
   - Les vistes que ho fan servir són dels passos 8 a 11.
   - Revisió (agent independent, 04/11/2026): 12 troballes, cap de greu; 11 arreglades, amb prova:
     - Les ordres (Duplica, Elimina) només actuen sobre les pestanyes seleccionades **que es veuen**. Si una part
       de la selecció es mou a una altra finestra, deixa d'estar seleccionada. Moure a una finestra que no hi és
       no fa res.
     - Les còpies es decideixen en desar, comparant amb el que hi ha al disc: un canvi desfet abans de desar no en
       demana cap, i la mateixa importació dues vegades en fa una.
     - «Torna a importar» conserva la plantilla d'ara, encara que hagi canviat després de previsualitzar.
     - L'agrupació de text es tanca en canviar la selecció, en canviar de Desfés i si una altra acció (un camp de
       text) s'hi ha posat entremig. La clau inclou les pestanyes.
     - En tornar a l'editor també es tornen a mirar les carpetes (avisos). El bàner «ha canviat fora» se'n va si el
       fitxer torna a ser el que era.
     - Una pestanya nova a `~` escrit d'una altra manera (`/Users/x/`) també queda sense Claude.
   - Queda obert: importar i desfer moltes vegades seguides gasta 2 còpies per cicle (`importacio` i `esborrat`),
     i al cap de 10 cicles les còpies d'abans de la sessió desapareixen. Només amb un ús molt insistent; si cal, el
     magatzem pot deixar de copiar el que ja és a qualsevol còpia, no només a l'última.
8. **0.9.0 — barra lateral i llista,** estats buits i full d'importació.
   - Fet (0.9.0).
     - **Barra lateral:** «Per revisar» amb el nombre (pestanyes amb un avís o un error a la fila; els d'informació
       no hi compten) i les finestres, amb `macwindow`, el nombre de pestanyes i un triangle si el nom és repetit.
       Menú contextual (Canvia el nom, Duplica, Elimina; al buit, Nova finestra), ⌫ i Retorn.
     - **Llista:** selecció múltiple. Cada fila diu el nom, la carpeta (o l'avís més greu, amb icona i text) i el
       resum de Claude («Molt alt · Ultracode», «Només terminal»). Menú contextual (Canvia el nom, Duplica,
       Activa o Desactiva Claude, Elimina; al buit, Nova pestanya…), ⌫ i Retorn (canvia el nom). A «Per revisar»,
       per finestres; una pestanya arreglada s'hi queda fins que se'n tria una altra.
     - **Nova pestanya…** (`plus` a la barra d'eines): el diàleg de carpetes s'obre a la carpeta que conté la de
       l'última pestanya seleccionada. Una finestra nova obre el nom per escriure'l.
     - **Títol i subtítol:** el nom de la finestra i, per exemple, «12 pestanyes · 12 amb Claude · 2 avisos»; si no es pot
       desar, ho diu.
     - **Estats buits:** sense configuració (Importa de Warp…, Comença en blanc), cap finestra, finestra sense
       pestanyes (Nova pestanya…), «Res per revisar» i «Tria una finestra».
     - **Full d'importació** (estat buit i Fitxer › «Importa de Warp…» o «Torna a importar-ho tot de Warp…»): torna a
       llegir Warp i diu les xifres (amb l'exemple de la secció 2 i `.habituals`, d'abans de la 0.28.0: «4 finestres ·
       30 pestanyes», «24 amb Claude: 6 amb l'ordre de la seva sessió i 18 amb la plantilla», «6 només terminal: 4 a la
       carpeta d'inici i 2 amb una carpeta que ja no existeix», «18 salten els permisos»), l'ordre de la plantilla, quantes
       pestanyes sortiran a «Per revisar», les finestres i les notes. No escriu res fins a «Crea» o «Substitueix».
   - Les ordres de la barra de menús (⌘T, ⌘D, Canvia el nom…) són del pas 11.
   - **Revisió** (flux de 3 revisors i 3 verificadors, 04/11/2026): 17 troballes, 12 confirmades (10 de diferents),
     cap de greu; totes arreglades, amb prova:
     - El nom que s'escriu en una fila és a l'editor (`textDelNom`), i es desa si es comença el d'una altra fila, si
       es crea una finestra, si l'editor s'amaga o si se surt de l'app. Si la fila desapareix (desfer, tornar a
       importar, tornar a carregar), el camp es tanca.
     - La barra lateral sempre té una fila triada: un clic al buit ja no la desmarca (abans, ⌫ hauria eliminat una
       finestra que no semblava seleccionada).
     - Eliminar la finestra recordada des de «Per revisar» ja no buida la selecció de la llista.
     - Si el full s'obre mentre l'app ja llegeix Warp i la lectura falla, el full en diu el motiu (abans: «no s'ha
       pogut llegir Warp»).
     - Els avisos del fitxer editat a mà (`AvisFormat`, com «sense bloc «claude»») surten en un bàner, amb
       «Mostra-les» i «D'acord». El full d'importació mostra també els avisos de la lectura, com el CLI.
     - Textos en singular («1 salta els permisos», «1 pestanya sortirà a «Per revisar»», «Substitueix el que hi ha
       ara (1 finestra i 1 pestanya)»). Sense finestres, la llista diu «Cap finestra» amb «Nova finestra».
     - La prova de guarda també rebutja `Lector(inici:)` a les proves (llegiria Warp i Claude de debò).
   - Descartades pels verificadors: el títol «Pestanyes que no tenien Claude obert» (D11: totes reben la
     plantilla), què compta «N avisos» al subtítol (les files marcades) i el «cap focus en obrir», que es
     comprova a la prova 2.
   - **Prova 2, amb OK:** en David obre l'app amb `--config` a una carpeta temporal, importa de Warp i en revisa
     les pantalles en clar i en fosc. S'obren 0 finestres de Warp i 0 sessions de Claude: només es llegeix Warp.
   - **Prova 2 feta (04/11/2026, 0.9.0, `--config /tmp/warp-launch-prova2`):** l'estat buit, el full
     d'importació, la barra lateral i la llista després de «Crea», i l'edició (Retorn, Escapada, ⌫ i ⌘Z, menú
     contextual, clic al buit) funcionen. El mode fosc no s'ha mirat («no és important»). Warp havia canviat des de
     la lectura del pas 6 (finestres, pestanyes i sessions vives), i el full ho mostrava amb les xifres noves.
9. **0.10.0 — inspector,** amb els camps de R4, la vista de l'ordre i l'edició de diverses pestanyes.
   Amb «Salta els permisos» activat, el mode de permisos queda desactivat (Claude no en fa cas).
   Cada camp de text passa `agrupa` amb el nom del camp, i crida `acabaAgrupacio()` en perdre el focus.
   - **Fet (0.10.0, 04/11/2026).** Model a `EditorInspector.swift` (què es mostra, opcions, «Valors diversos», avisos
     per camp, on s'obre «Tria…») i vista a `VistaInspector.swift`:
     - Una pestanya: nom (buit = el de la carpeta) i carpeta (s'escriu amb `~`, i «Tria…» s'obre a la carpeta pare o a
       la més propera que existeixi); el bloc de Claude; les opcions que l'editor no canvia (`--settings`,
       `--remote-control` i les desconegudes), en només lectura; i l'ordre, seleccionable, amb «Copia l'ordre».
     - Diverses pestanyes: només el bloc de Claude, sense el nom fix de la sessió (dues sessions amb el mateix nom es
       confondrien). Els desplegables diuen «Valors diversos», i les caselles es veuen mixtes. Cada canvi és un sol
       pas de Desfés per a totes.
     - Cap pestanya: el nom i les xifres de la finestra, i «Obre a Warp…» desactivat fins a la fase 3.
     - El model ofereix els àlies (Fable, Opus, Sonnet, Haiku) i el valor que ja hi hagi (un id complet es conserva).
       Un id nou només es pot escriure al fitxer.
     - «Activa Claude» és la casella «Obre Claude Code en aquesta pestanya» (l'avís «Claude és apagat» no surt a
       l'inspector). Amb «Salta els permisos» i un mode, el desplegable queda desactivat i surt «Treu el mode de
       permisos».
     - Cada canvi de Claude deixa la pestanya normalitzada, com el fitxer i l'ordre. Conseqüència: un
       `--settings '{"ultracode":false}'` importat se'n va en activar l'ultracode, i no torna en desactivar-lo
       (avui cap pestanya en té).
     - Avançat del pas 11: «Copia l'ordre» al menú contextual (amagat si no hi ha cap ordre), el botó de
       l'inspector a la seva barra (sobre la columna) i l'ordre de l'inspector (ara ⌥⌘I: pas 9b). ⌘C copiava les
       ordres com a text fins a la 0.11.0, que el fa servir per a les pestanyes.
   - **Revisió** (flux de 3 revisors i 3 verificadors, 04/11/2026): 20 troballes, 18 confirmades (13 de diferents),
     cap de greu; totes arreglades, amb prova si són del model:
     - L'agrupació de text es tanca també en canviar de finestra o de «Per revisar», si el camp desapareix (una altra
       selecció, amagar l'inspector) i en amagar l'editor.
     - Un camp que torna a com era abans del pas (escriure i esborrar, o ⌘Z dins del camp) treu el pas, sense deixar
       cap Refés. El nom de la finestra que se'n surt buit torna al d'abans (no a la primera lletra).
     - Caselles en lloc d'interruptors: NSSwitch no té estat mixt.
     - `.inspector` sobre el `NavigationSplitView`, i cada botó sobre la seva columna (mac-design).
     - ⌘C i «Copia l'ordre» desactivats o amagats quan no hi ha cap ordre (també si l'ordre no es pot generar).
     - Un model escrit «Opus» és l'àlies (abans sortia dues vegades). «Per revisar» buit diu «Res per revisar» també a
       l'inspector. «Altres opcions» les mostra normalitzades, com l'ordre.
   - **Prova 3 feta (04/11/2026, 0.10.0, `--config /tmp/warp-launch-prova2`):** l'inspector, l'ordre que canvia,
     «Tria…» a «Per revisar», diverses pestanyes, el Desfés (⌘Z dins del camp, i un desplegable amb el cursor en
     un camp) i cap focus en obrir funcionen. Dues coses no: ⌃⌘I no amagava l'inspector, i ⌘C (les ordres com a
     text) «no ens serveix per copiar i enganxar pestanyes en l'editor. I vull que serveixi» (pas 9b).
9b. **0.11.0 — copiar, retallar i enganxar pestanyes, i l'ordre de l'inspector** (demanat a la prova 3).
   - **Fet (0.11.0, 04/11/2026).** ⌘C, ⌘X i ⌘V a la llista (⌘V també a la barra lateral, a la finestra triada), i
     «Retalla», «Copia» i «Enganxa» al menú contextual. «Enganxa les pestanyes» també a la fila de la finestra i a
     la finestra buida (on no hi ha cap llista que rebi ⌘V).
     - El porta-retalls porta un tipus propi, `cat.davide.warp-launch.pestanyes` (JSON del format v1 amb una
       finestra, `PortaRetalls`), conforme només a `public.data`: enganxat a VS Code o a Warp, no hi surt res
       (decisió d'en David, 04/11/2026: «Que no surti res»).
     - Enganxa després de l'última pestanya triada, o al final. Una copiada entra com «Duplica» (id nou, sense nom
       fix); una retallada torna amb el seu id (és un moviment). Un nom fix que ja fa servir una altra pestanya no
       s'enganxa. Cada acció és un pas de Desfés.
     - Edició › Enganxa i «Enganxa» només miren els tipus del porta-retalls; el contingut es llegeix en enganxar.
     - L'inspector té una ordre pròpia a Visualització, abans de «Mostra la barra lateral», amb ⌥⌘I.
   - **Prova 4 (04/11/2026, 0.11.0 sense els arranjaments de la revisió):** ⌘C/⌘X/⌘V entre finestres, el menú
     Edició, enganxar fora de l'app (no hi surt res) i ⌘C/⌘V als camps de text funcionen. ⌃⌘I, ni amb l'ordre
     pròpia: el botó i el clic al menú sí. Per això ⌥⌘I.
   - **Revisió** (flux de 3 revisors i 3 verificadors, 04/11/2026): 13 troballes, 8 confirmades; totes arreglades,
     i 3 de descartades que reforcen la seguretat: el nom fix repetit en enganxar d'una altra configuració,
     «Enganxa» a la finestra buida i a la fila, només els tipus en validar, l'ordre de l'inspector al costat de la
     barra lateral i amb el títol correcte, aquesta documentació, la prova de text de l'ordre de l'inspector, la
     prova que el tipus no és text, la prova de guarda (les proves no toquen el porta-retalls) i la prova de la
     versió més nova.
   - **Prova 5 feta (04/11/2026, 0.11.0):** ⌥⌘I, ⌃⌘S (barra lateral) i «Enganxa les pestanyes» a una finestra
     nova funcionen. En David hi troba a faltar arrossegar pestanyes (reordenar-les i canviar-les de finestra):
     és el pas 10.
10. **0.12.0 — arrossegar i «Mou a».** Amb el tipus del porta-retalls. Demanat a la prova 5.
   - **Fet (0.12.0, 04/11/2026).** Vegeu «Arrossegar» (secció 1). Abans de programar-lo, 4 agents van comprovar a
     l'SDK i al binari de SwiftUI de macOS 27.2 com fer-ho, i el van compilar i provar fora del repo.
     - Reordenar: una o diverses pestanyes, un sol pas («Mou la pestanya/les pestanyes»); les mogudes queden triades.
     - Deixar-les a la fila d'una altra finestra, o «Mou a ▸»: van al final. Si es mou tota la selecció, l'editor la
       segueix (pas 7); una fila no triada es mou sense canviar de finestra ni de selecció. A la fila de la finestra
       que es veu no passa res. A «Per revisar», les que ja eren a la finestra de destinació es queden on són.
     - «Mou a ▸» al menú contextual, amb les altres finestres; amagat si no n'hi ha cap. Si dues finestres es diuen
       igual, porten el resum («a — 3 pestanyes · 3 amb Claude»).
     - Un nom a mig escriure es desa en el mateix pas que el moviment (i que «Nova finestra»): amb el Desfés de la
       finestra, que agrupa per esdeveniment, s'hi ajuntaria igualment.
   - **Revisió** (flux de 3 revisors i verificadors, 04/11/2026): 20 troballes, 14 confirmades (10 de diferents),
     totes arreglades: el nom a mig escriure (un sol pas), les que ja eren a la finestra a «Per revisar», «Mou a ▸»
     sobre una fila no triada, els noms repetits a «Mou a ▸», la guarda (cada expressió provada, `.onDrag` amb
     clausura) i la documentació (estat buit, `.dragConfiguration`, la prova de guarda i la numeració de les proves).
   - **Prova 6, amb OK:** en David obre l'app amb `--config /tmp/warp-launch-prova2`. S'obren 0 finestres de Warp i
     0 sessions de Claude.
     - Reordenar 1 i 3 pestanyes no contigües; deixar-les a la fila d'una altra finestra (també amb ⌥ premut: no s'hi
       ha de copiar res); omplir una finestra buida; «Mou a ▸»; «Per revisar».
     - Després de cada moviment, ⌘Z i ⇧⌘Z fan un sol pas, i Edició diu «Desfés Mou la pestanya/les pestanyes».
     - Arrossegar-les cap a una pestanya de Warp **sense Claude** (mai una amb una sessió viva), el Finder, TextEdit
       i Notes: no hi ha d'entrar res. Si no n'entra res, no se sap quina barrera ho ha aturat
       (`.dragConfiguration`, la llista o `.ownProcess`): només es dona per fet que no en surt res.
   - **Prova 6 feta (04/11/2026, 0.12.0):** reordenar i desfer funcionen; «Mou a ▸» i omplir una finestra buida, també.
     En David arrossega fins a la fila d'una altra finestra, però «la finestra no canvia i no puc deixar la pestanya en
     un lloc de l'altra finestra»: és el pas 10b.
10b. **0.13.0 — obrir la finestra arrossegant i deixar-les en una posició; reordenar les finestres.** Demanat a les
   proves 6 i 7b. Fet.
   - Vegeu «Arrossegar» (secció 1). Abans de programar-lo, 3 agents i un pla van comprovar al binari de SwiftUI i
     d'AppKit de macOS 27.2 què fa la `List` si canvia de dades a mig arrossegament (docs/fets-verificats.md), i el
     pla es va compilar i provar fora del repo (302 proves).
   - **Prova 7, amb OK:** en David obre l'app amb `--config /tmp/warp-launch-prova2`. S'obren 0 finestres de Warp i
     0 sessions de Claude. Les comprovacions són a la llista del pla (aturar-s'hi i deixar-les entre dues pestanyes,
     passar-hi per sobre sense aturar-s'hi, Esc i deixar-les fora després d'obrir, A → B → A, finestra buida, «Per
     revisar», la fila de la finestra oberta, reordenar com a la prova 6, ⌘Z i ⇧⌘Z, i que l'app no peti).
   - **Prova 7 feta (04/11/2026, 0.13.0 abans de la revisió):** obrir i deixar-les entre dues pestanyes (1 i 3 no
     contigües), passar-hi per sobre sense aturar-s'hi, Esc, A → B → A, «Per revisar» i reordenar funcionen. La
     finestra buida, no: s'obria, però la pestanya no entrava ni al panell ni a la fila i tornava al seu lloc. Ara una
     finestra buida no s'obre arrossegant (vegeu «Arrossegar»).
   - **Prova 7b (04/11/2026):** a la fila d'una finestra nova (buida) la pestanya tampoc no s'hi queda, ni amb el
     nom desat (Retorn) ni sense. A la fila de la finestra triada en obrir l'app, sí. El cursor no surt prohibit a la
     fila de la finestra que es veu. El registre del sistema diu per què: la fila rep l'acció amb 0 pestanyes perquè
     la càrrega del proveïdor es cancel·la (-1000/3072). Ara es mouen les desades en començar a arrossegar (vegeu
     «Arrossegar»). En David també demana **reordenar les finestres** a la barra lateral: fet a la 0.13.0.
   - **Revisió** (fluxos de 3 revisors i verificadors, 04/11/2026): 7 troballes confirmades del pas 10b (Esc abans de
     0,5 s, el focus de la llista nova, la selecció a la fila de la finestra oberta, proves i documentació) i 9 de la
     prova 7b (la causa de les 0 pestanyes, el registre, el cursor, proves de reordenar finestres i documentació).
   - **Prova 7c, amb OK:** en David obre l'app amb `--config /tmp/warp-launch-prova2`. S'obren 0 finestres de Warp i
     0 sessions de Claude. Abans, si cal, el registre en directe (`Registre.swift`).
     - ⌘N i deixar una pestanya, i després dues de triades, a la fila de la finestra nova: s'hi queden, i ⌘Z les torna.
     - Arrossegar una finestra amunt i avall a la barra lateral; «Mou amunt» i «Mou avall»; ⌘Z.
     - Arrossegar una pestanya entre dues finestres de la barra lateral: no s'ha de moure cap finestra. Arrossegar una
       finestra sobre la llista de pestanyes: no s'ha de moure cap pestanya.
     - Obrir una finestra arrossegant i deixar-les a la llista: després, ↓ mou la selecció (el focus és a la llista).
   - **Prova 7c feta (04/11/2026, 0.13.0):** els quatre punts funcionen. Al registre, dues pestanyes deixades a la fila
     d'una finestra (una de nova i una d'oberta arrossegant) hi entren pel camí sense dades: «sense dades, local true,
     1 elements, 1 fixades», i es mouen. La de dues pestanyes triades no hi surt.
   - **Confirmat per en David (04/11/2026):** prémer Esc a mig arrossegament abans de 0,5 s, sense amollar el botó,
     obria igualment la finestra de sota (no movia res). Arranjament al pas 11 (vegeu «Arrossegar»), sense comprovar a
     l'app: es mira a la prova 8.
11. **0.14.0 — menús, dreceres, menú de la icona i Configuració** (la plantilla). Fet.
    - La plantilla es canvia des de la finestra de Configuració, que té el seu Desfés: `canviaPlantilla` el registra
      en aquell, no en el de l'editor (vegeu «Plantilla i Configuració», secció 2).
    - Les ordres de «Ordres» (secció 1): Fitxer, el menú Pestanya i Edició › Elimina desactivat sense res a eliminar.
      ⌘W i ⌥⌘W tornen a ser-hi.
    - El menú de la icona, amb els avisos com a botons. L'Esc a mig arrossegament (pas 10b).
    - Abans de programar-lo, un flux de recerca (el binari de SwiftUI i d'AppKit de macOS 27.2) i un pla.
    - **Revisió** (flux de 3 revisors i 3 verificadors, 04/11/2026): 8 troballes, 4 confirmades o plausibles, totes
      arreglades: l'ordre de la Configuració sense el nom de sessió, cap plantilla amb el fitxer malmès, la molla que
      no s'atura per sempre en perdre la destinació (a la vora de la fila) i un bloc mal posat a fets-verificats.
    - **Prova del pas 11 feta (04/11/2026, 0.14.0):** en David obre l'app amb `--config /tmp/warp-launch-prova2`.
      S'obren 0 finestres de Warp i 0 sessions de Claude. Funcionen els cinc punts:
      1. Fitxer: ⌘T, ⌘D a la llista i a la barra lateral, «Canvia el nom» i ⌘W.
      2. Pestanya: Mou a ▸, Activa i Desactiva Claude, Copia l'ordre.
      3. Configuració: canviar l'esforç i ⌘Z allà; ⌘Z a l'editor no la toca; ⌘T fa servir la plantilla nova.
      4. Menú de la icona, sense separadors doblats.
      5. Arrossegar: Esc abans de 0,5 s no obre res; aturar-s'hi al mig i a les vores obre; dues pestanyes a una fila.
    - Al registre de la prova hi ha 2 obertures als 0,5 s i una pestanya deixada a la fila d'una finestra oberta
      arrossegant (pel camí sense dades, «1 elements, 1 fixades»), però cap Esc ni cap fila amb dues, i en David
      confirma que les va provar a la mateixa sessió: **el registre desat no guarda totes les línies.** A la prova 8,
      el registre en directe (`/usr/bin/log stream`), obert abans. En sortir d'una fila deia «fila cap»: corregit a
      la 0.14.1.
12. **0.26.0 — icona i paquet per a Aplicacions** (era la 0.15.0; en David va triar fer abans la fase 3.1). Icona (prevista amb nano-banana; dibuixada amb codi a la 0.26.1, vegeu sota): finestres en cascada sobre fons índigo,
    `Info.plist` complet, `scripts/instal·la.sh` (copia a `/Applications`; si l'app és oberta, s'atura sense
    tancar-la; diu com es desinstal·la).
    - **Paquet fet (0.26.0, 05/11/2026):**
      - `Info.plist` amb la categoria (eines de desenvolupament), el copyright i `CFBundleInfoDictionaryVersion`.
      - `scripts/instal·la.sh`: per defecte, mode de prova (diu què copiaria); amb `--aplica`, copia l'app a
        `/Applications` (regla 3: només amb l'OK d'en David).
        - Abans de copiar, comprova l'identificador i la signatura.
        - Si l'app és oberta, s'atura sense tancar-la.
        - No toca una «Warp Launch.app» d'una altra app.
        - Fa una còpia al costat i després la canvia, perquè si falla, la d'abans continua al seu lloc.
        - No obre ni registra res, i en acabar diu com es desinstal·la.
        - `WARP_LAUNCH_ORIGEN` i `WARP_LAUNCH_DESTI` per a les proves (`ScriptInstallaTests`, sempre en carpetes temporals).
    - **Altres Macs (06/11/2026; decisió d'en David: compilada, des de GitHub):**
      - `scripts/publica.sh`: compila, comprova la signatura «Warp Launch Dev» (el requisit amb el certificat, `certificate leaf`)
        i publica la versió de `VERSION` a `David-Erra/warp-launch` com a `vX.Y.Z`, amb `WarpLaunch-X.Y.Z.zip` (`ditto`). Per
        defecte, mode de prova; amb `--aplica`, regla 3 (OK cada vegada). Només des d'origin/main sense canvis, i una versió nova.
      - `scripts/instal·la.sh --github`: la baixa amb `gh release download` (l'última, o `--versio`), només a Apple Silicon i
        macOS 26, i només si porta el certificat d'en David. Després, el mateix camí de sempre (identificador, app oberta,
        canvi atòmic) i li treu `com.apple.quarantine`, perquè no és signada per Apple. Es fa servir sense el repo:
        `s="$(gh api … contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica` (README.md). No
        `bash <(…)`: si gh falla, bash executaria el JSON de l'error. Cal un compte d'administrador del Mac (sense sudo: gh hi
        perdria la sessió).
      - Revisió (3 revisors i 15 verificacions, 06/11/2026): 15 troballes confirmades, corregides amb prova: la comanda executava
        l'error de gh; un compte que no és administrador fallava amb un «Permission denied» sense explicació; `--versio v0.27.3`;
        una etiqueta que queda sense versió; les notes quan no es troba l'anterior; un requisit trencat es confonia amb una app
        d'algú altre; la prova de la marca de baixada no la comprovava. Queda: qualsevol que pugui escriure al repo pot canviar
        l'script que s'executa (el certificat només protegeix d'una compilació equivocada).
      - Proves: `ScriptPublicaTests` (repo de git temporal amb un origin nu, `build-app.sh` i `gh` falsos) i les de `--github`
        a `ScriptInstallaTests`.
    - **Icona: feta el 06/11/2026, dibuixada amb codi** (decisió d'en David). `swift scripts/icona-dibuixa.swift` escriu les dues capes de `Recursos/AppIcon.icon/Assets/`:
      - `principal.png`, la finestra del davant (51 % de l'amplada), amb la barra de títol (tres punts buits i una franja
        buida sota). Sense els punts semblava una targeta de crèdit;
      - `fons.png`, dues finestres al darrere, amunt i a l'esquerra, separades per una franja buida (opacitat 0,55).
      - Fons índigo (`automatic-gradient`, srgb 0,29 / 0,25 / 0,75). Revisada amb `scripts/icona-revisa.sh`: es llegeix en
        clar, fosc, tenyit i transparent, i a 16 pt encara es veuen les finestres en cascada. En David la dona per bona el 06/11/2026.
    - **Prova 8, amb OK,** amb configuració temporal: ⌘Z i ⇧⌘Z, les dreceres, el menú de la icona i la Configuració
      del pas 11 (la plantilla, i ⌘Z a la Configuració, que no ha de desfer res a l'editor), clar i fosc, i mida
      mínima. Es fa després del pas 12 (decisió d'en David, 04/11/2026). D'arrossegar, amb el registre
      (`Registre.swift`) obert:
      - Esc a mig arrossegament, abans de 0,5 s i sense amollar: no s'ha d'obrir res. El registre diu quin senyal hi
        ha arribat;
      - sense Esc, aturar-se 0,5 s al mig de la fila d'una altra finestra, i també a la vora de dalt i de baix, encara
        l'obre, i s'hi poden deixar les pestanyes en una posició (com a la prova 7c).
    - **Després, cadascun amb el seu OK:** crear la configuració real i instal·lar a
      `/Applications`. Es desfà desactivant l'interruptor de l'inici de sessió (0.27.0) i esborrant l'app, `~/.config/warp-launch/`,
      `~/Library/Preferences/cat.davide.warp-launch.plist`,
      `~/Library/Saved Application State/cat.davide.warp-launch.savedState` i, si n'hi ha, el permís
      (`tccutil reset All cat.davide.warp-launch`).
13. **`docs:` fase 2 feta.** **Feta el 06/11/2026:** passos 1 a 12 (la icona, a la 0.26.1) i prova 8 (0.26.0); en David dona per
    bona la icona.

### Fora de la fase 2 (es mira després de la prova 8)

Color de pestanya (D9), seguir un symlink de la configuració, diàleg de conflicte amb dues opcions, arrossegar
carpetes des del Finder, dreceres ⌃⌘1–9 i ⌥⌘↑↓, cerca, copiar en deixar anar amb ⌥, fusionar una importació
pestanya a pestanya, `configuracio mostra|ruta`, captures de pantalla automàtiques.

## 5. Riscos

| Risc | Com es detecta | Què fem |
|---|---|---|
| macOS demana permís per llegir les dades de Warp, i el torna a demanar a cada compilació (signatura ad hoc) | Prova 1 | Llegir només quan cal; si es repeteix, D12 (certificat autosignat) |
| L'app de barra de menú no surt al davant, no té menú principal o es bloqueja en tornar a obrir l'editor | Prova 1 | `.regular` abans de mostrar i activar després; de reserva, una `NSWindow` pròpia |
| Arrossegar falla sense error si el tipus no és a `Info.plist` | Una prova llegeix l'`Info.plist` del repo | Només es pot provar amb el `.app` |
| La llista canvia de finestra a mig arrossegament: `onMove` amb posicions de l'altra finestra, o l'app peta | Proves del model (`unOnMoveDespresDObrirNoMouRes`); la llista, només a la prova 7 | `.id` a la llista i `reordena` bloquejat després d'obrir; si peta, la variant sense `onMove` |
| La fila d'una finestra no s'obre arrossegant (la `List` no fa *spring loading*) | Prova 7 | `Molla`, a mà; si falla, «Mou a ▸» i deixar-les a la fila |
| Les dades arrossegades no arriben a la fila (càrrega cancel·lada) i es mouen pestanyes que no s'han arrossegat | Proves del model (`DadesQueNoArribenTests`, amb els casos de ⇧, d'un clic després i d'una altra app); a l'app, prova 7c i el registre | Les files del proveïdor, fixades en passar per la fila, només amb sessió local i el mateix nombre; si falla, el pla B (`dragContainer`) |
| Les posicions de la barra lateral mouen pestanyes, o les de la llista mouen finestres | Proves del model (`lesDuesLlistesNoEsBarregen`); prova 7c | La marca `arrossegantFinestres` |
| El desat automàtic trepitja una edició a mà | Proves del canvi extern | Comparar bytes, bàner i còpies |
| Una prova o el codi obre alguna cosa o llegeix l'estat real | Prova de guarda | Magatzem sense ruta per defecte; lector injectat |
| Dues còpies de l'app (`build/` i `/Applications`) | `lsregister -dump` | Després d'instal·lar, obrir només la d'Aplicacions |
| Una versió dolenta arriba sola a tots els Macs en un dia (des de la primera versió publicada amb Sparkle, la 0.33.0 o posterior) | Rondes A, B i C (en part) abans de publicar; la D, la E i la F no es fan (10/11/2026); la Porta 3 | Secció 11, apartat 7: `latest` a l'anterior, revertir la recepta i publicar una correcció superior |
| Claude Code canvia les seves opcions (canvia gairebé cada dia) i la taula de la 2.1.318 queda antiga | Avís d'opció desconeguda a la importació | Tornar a llegir les definicions del binari i comparar-ho amb el `parseOptions` del binari (docs/fets-verificats.md) |

## 6. Respostes d'en David (03/11/2026)

1. **`warp-launch importa` (sense desar) i `configuracio valida` sense demanar OK:** sí (regla 4 de `CLAUDE.md`).
2. **Carpeta arreglada d'una pestanya importada sense Claude:** Claude no s'activa sol, sinó amb el botó «Activa Claude».
3. **Ordre de les pestanyes:** el de `warp-launch llegeix` és el de la pantalla (comprovat en una finestra).
4. **Icona:** finestres en cascada sobre fons índigo (pas 12).

Del pas 11 (04/11/2026):

5. **Menú de la icona:** no diu quantes pestanyes no s'obririen; els avisos de les pestanyes són a l'editor.
6. **Nom de sessió de la plantilla:** no es copia mai a les pestanyes noves ni a les importades.
7. **Prova 8:** després del pas 12.

## 7. Fase 3.1: obrir una finestra a Warp (R12)

Pla del 04/11/2026, fet amb la recerca del codi de Warp (master `abeaf2a`; instal·lat: 0.2026.10.21, amb la
0.2026.11.03 ja baixada), del binari de Claude Code 2.1.318 i del repo a la 0.14.1. «Codi» vol dir llegit al codi o al
binari, encara no provat en execució: cada prova real (L1 a L5) en confirma una part.

**Decisions d'en David** (`docs/especificacio.md`): D5 (fitxer temporal), D7 (`--resume` de la conversa de cada
pestanya; si no se sap, una de nova, mai `--continue`), D13 (només les pestanyes que falten), D15 (fora `--continue`
de l'ordre que es mostra), D16 (un espai al davant, fora de l'historial), D17 (el CLI mostra per defecte; amb una opció
explícita, també obre) i D18 (lectura cada 60 s).

### Què triem quan la recerca no coincideix

1. **`--resume <id>` des d'una altra carpeta:** el missatge «different directory» només surt al selector
   (`onSelect`); `--resume <id>` busca a tots els projectes (binari: `N1e` → `TQ` → `Per` → `W6e`). Fins a L4, una
   carpeta diferent és un avís, no un bloqueig.
2. **`--resume` d'una conversa viva:** Claude només s'hi nega si la té un procés no interactiu. Si és interactiu, no
   diu res i les dues pestanyes s'intercalen a la mateixa transcripció. **R9 l'ha de garantir l'app** sempre, abans
   d'obrir. No es prova mai a propòsit. Els fets del 05/11/2026 no hi quadren del tot (vegeu `fets-verificats.md`, «`claude
   --resume`»).
3. **`cwd` amb `~` o buit:** Warp expandeix `~`, i amb una carpeta buida obre la seva per defecte i hi executa l'exec
   (`launch_config.rs:270-276`, `pane_group/mod.rs:1390`). L'app només escriu rutes absolutes que existeixen.
4. **Pane recordat que hi és però sense Claude:** compta com a pestanya oberta («oberta sense Claude»): R9 parla de
   pestanyes.
5. **Conversa nova:** `claude` sense id (no `--session-id`, no provat). La marca dona el `sessionId` en uns 2 s.

### Flux

1. «Obre a Warp…» (menú Fitxer, barra d'eines de la llista, menú contextual de la finestra a la barra
   lateral, inspector sense pestanyes triades, submenú de la finestra al menú de la icona) només crida
   `editor.demanaObertura(finestra)`. Desactivat si la configuració no és oberta, si la finestra no
   té pestanyes, si ja hi ha una obertura en curs o si `estat.json` és d'una versió més nova.
2. L'app desa la configuració; si no pot, no obre.
3. Comprova si Warp és obert. Si no, el full ho diu, i «Obre» l'obrirà abans (0.22.0; vegeu «Sense la base de Warp»).
4. Lectura nova: Warp, les sessions (també les no interactives), `estat.json`, les transcripcions i la confiança.
5. `PlaObertura.calcula` (pura) dona el pla, i el full de confirmació el mostra amb xifres.
6. «Obre N pestanyes» torna a llegir i recalcula. Si el pla ha canviat, no obre: torna a mostrar el full («Warp ha
   canviat»).
7. Desa el llançament `pendent` a `estat.json`, escriu el YAML (`O_EXCL`) i crida `ObreWarp.obre(url)`.
8. Cada 0,5 s, fins a 30 s des que `obre` torna (i com a mínim una lectura), llegeix Warp i les sessions i busca
   la finestra nova i les marques (`ConfirmacioObertura`). El que veu s'acumula (`Confirmacio.afegeix`).
9. En quant veu la finestra o una marca, esborra el YAML (Warp ja l'ha copiat a memòria, `uri/mod.rs:227-250`), però
   continua llegint fins que ha vist la finestra **i** el Claude de cada pestanya que n'ha de tenir, o fins als 30 s:
   una marca sola no confirma la finestra, i les pestanyes de terminal només es lliguen per la finestra. Als 30 s
   sense res, l'esborra igualment.
10. Desa a `estat.json` el resultat (`confirmat` si s'ha vist la finestra; si no, `senseConfirmar`), el pane de cada
    pestanya (de la finestra, per ordre, o de la marca, que mana), la sessió de cada marca i, sense la base, el shell de cada
    pestanya de terminal (0.34.0, vegeu «Sense la base de Warp», «Els límits»). Bàner: «S'ha obert
    «empresa» a Warp: 9 pestanyes, 6 amb Claude», amb «Claude encara no ha arrencat a «Botiga»: mira-ho a Warp» si en
    falta algun; «No s'ha pogut reconèixer la finestra nova… (s'ha vist Claude a 2 de 6 pestanyes)» si només s'han
    vist marques; i «No s'ha pogut confirmar…» si no s'ha vist res.
11. Si s'ha vist la finestra però no el Claude d'alguna pestanya que reprèn una conversa, la conversa queda «en curs»
    (en memòria) fins que una lectura en vegi el Claude amb la marca, o 10 min. Mentrestant, una altra pestanya que
    recordi la mateixa conversa compta com a oberta («una altra pestanya acaba de reprendre la seva conversa»), R9. La
    pestanya que la reprèn no en queda afectada: si es torna a obrir, la reprèn (si en comencés una de nova, la
    perdria).
12. Si l'app surt a mig obrir (⌘Q, o es tanca la sessió de macOS), `applicationShouldTerminate` crida
    `Obertura.enSortir`: esborra el YAML i desa el que ja s'ha vist (`confirmat` i els panes, si s'ha vist la finestra;
    si no, `senseConfirmar`).

### Fitxer temporal (0.15.0, fet)

- **Carpeta:** `~/.warp/launch_configurations/`, l'única que llegeix Warp, també amb `--config`. Si no hi és, l'app la crea en
  fer «Obre» (0.31.5, regla 7, tercera excepció): un sol nivell, mai `~/.warp`, res si el camí o `~/.warp` són un enllaç o un fitxer, i
  només amb la configuració de debò i el permís, mirat just abans d'escriure. El CLI no la crea.
- **Nom:** `warp-launch-<llançament>.yaml`, amb un UUID nou en minúscules. `name:` és el nom sense `.yaml`, i l'URL,
  `warp://launch/warp-launch-<llançament>`: sense punts ni res a codificar, no pot coincidir amb cap configuració d'en
  David ni activar el reintent sense extensió de Warp (`uri/mod.rs:746-811`).
- **Marca:** primera línia `# warp-launch: temporal <llançament>`.
- **Camps:** els obligatoris i `title` (buit: el nom de la carpeta). Sense `color`, `active_*`, `is_focused`,
  `pane_mode` ni `tab_groups`.
- **Escalars:** entre cometes dobles; només s'escapen `\` i `"`. Els caràcters de control C0, DEL i C1, U+2028,
  U+2029, U+FEFF, U+FFFE i U+FFFF són un error, i la pestanya queda exclosa. Si falta un camp o un tipus és erroni,
  Warp descarta tot el fitxer sense avisar (`util.rs:74-110`): per això el generador és propi i té una prova golden.
  El 04/11/2026, PyYAML i el Psych de Ruby llegeixen el golden igual; yaml-rust (el de Warp), a L1.
- **Ordre de cada pestanya:** amb Claude, una sola exec: ` WARP_LAUNCH_PESTANYA=<id pestanya> ` (amb l'espai del
  davant, D16) seguit de `OrdreClaude.text(argv)`. Mai `export` ni `--continue`. Una pestanya de terminal no porta
  `commands`.
- **Les feines de l'agent (0.22.3, en David, 05/11/2026):** una pestanya en bypass (`saltaPermisos` o `modePermisos: bypassPermissions`) porta
  també `CLAUDE_ENV_FILE=<carpeta de la configuració>/entorn-claude.sh`. El fitxer defineix una funció `claude` que afegeix
  `--permission-mode bypassPermissions` si l'ordre comença amb `--bg` o `--background`; si l'agent en posa un altre, mana el seu. L'app l'escriu
  abans d'obrir, i si no pot, no obre. Afegir el paràmetre a la línia de la pestanya no canviaria res: ja va en bypass, i les feines no l'hereten.
  - **Una feina que ja existeix no el porta:** `--resume <id complet>` amb el seu `state.json` es desperta amb el mateix id i les opcions desades.
    Amb el paràmetre, Claude en faria una còpia, i les còpies són el problema de sota. Una feina d'abans de la 0.22.3 amb `auto` desat continua en `auto`.
  - **Una feina viva, en reprendre-la, fa una còpia en `auto`:** el camí bo és enviar-li un missatge, no reprendre-la.
  - **No arriba** a `nohup claude --bg`, a un script, a `bash -c` ni a `claude -n x --bg`: la feina aniria en `auto`, com abans. Per arribar-hi caldria
    un `claude` propi al `PATH`: es va descartar perquè un error podria fer que es cridés a si mateix. Tampoc arriba a les feines que engegui una feina.
  - **No té efecte a les pestanyes obertes:** la variable només es llegeix en arrencar. Tampoc en un `claude` que en David obri a mà.

```yaml
# warp-launch: temporal 3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b
name: "warp-launch-3f2a9c1e-0b7d-4e8f-9a6b-5c4d3e2f1a0b"
windows:
  - tabs:
      - title: "Botiga"
        layout:
          cwd: "/Users/prova/GitHub/empresa/botiga"
          commands:
            - exec: " WARP_LAUNCH_PESTANYA=9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62 claude --dangerously-skip-permissions --effort high --settings '{\"ultracode\":true}' --resume 1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
      - title: "Web Host"
        layout:
          cwd: "/Users/prova/GitHub/web host"
```

**Quan s'esborra:** en veure la finestra nova o una marca; als 30 s sense res; si `obre` falla; en sortir de l'app a
mig obrir; en arrencar l'app (els llançaments `pendent` d'`estat.json` no esborrats, i qualsevol `warp-launch-*.yaml`
amb la marca de més de 2 min; aquests últims, també si `estat.json` no es pot fer servir). Només si el nom
és propi, `lstat` diu fitxer normal, és a la carpeta injectada, la primera línia és la marca i la mida és la que
es va escriure. Mentre existeix, Warp el pot mostrar a ⌃⌘L (watcher amb 500 ms de debounce): a L1 es mira que desaparegui.

### `estat.json` (versió 1, de l'app)

- A la carpeta de la configuració (amb `--config`, la de prova). No s'escriu si no hi ha configuració; no el crea mai
  una lectura ni el CLI. Escriptura atòmica, sense còpies. Si és d'una versió més nova, es llegeix i l'app no obre res.

```json
{
  "versio": 1,
  "generador": "Warp Launch 0.17.0",
  "pestanyes": {
    "9F4B2C7E-6D1A-4E8B-B3C5-2A7D9E0F1B62": {
      "pane": "c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6",
      "sessio": "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d",
      "carpetaSessio": "/Users/prova/GitHub/empresa/botiga",
      "origen": "marca",
      "vista": "2026-11-04T12:00:00Z"
    }
  },
  "llancaments": [
    { "id": "3f2a9c1e-…", "fitxer": "warp-launch-3f2a9c1e-….yaml", "mida": 812, "creat": "…",
      "finestra": "5C0E8A52-…", "pestanyes": ["9F4B2C7E-…"], "estat": "confirmat", "esborrat": true, "segons": 0.8 }
  ]
}
```

- **`origen`:** `importacio` (el pane, i la sessió si era viva), `llancament` (pane de la finestra confirmada, o shell),
  `marca` (sessió amb la marca), `pane` (sessió vista al pane recordat).
- **`shell` (0.34.0, opcional; aprovat per en David l'11/11/2026):** `{"pid": 12345, "inici": {"segons": 1793750000,
  "microsegons": 123456}}`, el shell que un llançament confirmat va obrir per a una pestanya només de terminal (vegeu «Sense
  la base de Warp», «Els límits»). La versió continua sent 1 (regla 11): la 0.33.0 el llegeix sense error, perquè `JSONDecoder`
  no mira les claus que no coneix (`ShellDeLEstatTests`, amb una còpia de les seves estructures); si el torna a desar, el perd,
  i la pestanya torna a ser com abans. Sense shell, el JSON és el d'abans. Les lectures de cada minut, importar, «Lliga» i
  el Desfés no el toquen.
- **`llancaments`:** els 20 últims; per a les proves i per avisar si l'últim no es va confirmar.
- **Pestanyes que ja no són a la configuració:** l'entrada es guarda 30 dies (`vista`), perquè el Desfés no perdi la
  conversa.
- **Quan s'escriu:** en crear la configuració o tornar a importar (es lliguen per pane **totes** les pestanyes; en
  tornar a importar, s'hereta la `sessio` del mateix pane); abans d'escriure el YAML i després de confirmar; a cada
  lectura si ha canviat alguna sessió (en arrencar, «Actualitza l'estat de Warp», cada 60 s amb D18, i abans d'obrir).
- **Regles (`ActualitzaEstat.amb`):** una sessió viva amb la marca M dona a la pestanya M el pane i la sessió; una
  sessió interactiva al pane P dona la sessió a la pestanya del pane P (així es recullen `/clear` i `/resume` fets a
  mà); si la marca és d'una entrada que ja no és a la configuració (s'ha tornat a importar), es posen al dia l'entrada
  i la pestanya del pane P; si Claude surt, la `sessio` es manté; dues pestanyes amb el mateix pane: el conserva la més
  recent.

### Pestanyes ja obertes (D13, R9): no s'obren, i el full diu per què

| # | Condició (la primera que es compleix) | Text al full |
|---|---|---|
| 1 | Un `claude` viu porta `WARP_LAUNCH_PESTANYA` igual a l'id de la pestanya | «oberta a Warp (Claude)»; si és dins de Warp amb un pane que ja no hi és, «tancada fa menys d'1 min» |
| 2 | El pane recordat és a `warp.sqlite` | «oberta a Warp» o «oberta a Warp, sense Claude» |
| 3 | La `sessio` recordada és d'una sessió viva | «oberta a «empresa 2 › X»», «… fora de Warp», «… en segon pla», «… a Warp» (sense pane conegut), o «tancada fa menys d'1 min: espera i torna-ho a provar» (dins de Warp amb un pane que ja no hi és: el desfer tancar de 60 s) |
| 4 | Una altra pestanya acaba de reprendre la `sessio` recordada i el seu Claude encara no s'ha vist (flux, 11) | «una altra pestanya acaba de reprendre la seva conversa» |

- **Avisos que no bloquegen:** una pestanya sense lligam a la mateixa carpeta que una d'oberta («potser ja és oberta a
  «empresa › Botiga»»; la carpeta no prova res: en una lectura real del 03/11/2026, més de la meitat dels panes eren a `~`); l'últim llançament de la finestra
  va quedar sense confirmar o pendent fa menys de 10 min («mira Warp abans»), o va fallar («va fallar: si Warp n'ha
  obert res, mira-ho abans»).
- **«Tancada fa menys d'1 min» atura la finestra** (`Pla.motiuEspera`): si s'obrissin les altres pestanyes, la finestra
  quedaria partida en dues. El full ho diu i «Obre» queda desactivat; el CLI ho diu amb ⏳. **Només si Warp restaura la
  sessió:** sense la base no es pot saber, i és un avís (vegeu «Sense la base de Warp»).
- **Error acceptat:** després d'un reinici l'uuid del pane potser canvia i la regla 2 falla (fase 3.3).
- **Excloses (error al full):** la carpeta no existeix; l'ordre no es pot generar; un caràcter que el YAML no admet; un
  error de `Validacio`.

### Lligar amb Warp (0.21.0)

Una configuració feta a mà, o creada abans de la 0.17.0 (com `prova2`, de la 0.14.0), no té lligams a `estat.json`:
l'app no sap quines pestanyes ja són obertes, i en obrir una finestra les tornaria a obrir totes (el 05/11/2026, en una
prova real, una finestra hauria tornat a obrir totes les pestanyes, cadascuna amb una sessió nova). Tornar a importar-la no serveix: es perdrien els canvis fets a
mà. **«Lliga amb Warp…»** (menú Fitxer) llegeix Warp i, per a cada pestanya sense lligam, proposa la pestanya de Warp
on ja és oberta (`LligamWarp`). Només desa amb «Lliga» al full; no canvia la configuració, ni obre o tanca res.

- **Ja lligada** (no es toca, i la seva pestanya de Warp no s'ofereix a cap altra): el seu pane és a Warp, o un Claude
  viu porta la seva marca.
- **Criteris, de més segur a menys:** la conversa recordada, viva en un pane (es lliga aquell pane, encara que la
  pestanya estigui dividida); el títol i la carpeta; només el títol; només la carpeta (mai la d'inici). Els títols es
  comparen sense espais als extrems ni majúscules. Cada pestanya es veu com a la importació: a la configuració, sense
  títol, el nom de la carpeta (com el fitxer de Warp); a Warp, sense títol, el nom de la carpeta, i amb el pane a la
  d'inici, la carpeta del seu Claude.
- **On:** per a cada criteri, de més segur a menys, primer a la finestra de Warp de cada finestra de la configuració
  (la que en té més pestanyes pel títol, comptant les ja lligades; si n'hi ha dues d'iguals, la carpeta desempata; si
  encara, cap) i després a totes. La carpeta sola no lliga fora de la seva finestra, i un criteri feble a la finestra
  no lliga una clau que comparteix una pendent d'una altra finestra.
- **Només si és inequívoc:** si N pestanyes de la configuració i N de Warp comparteixen la clau, s'aparellen per
  ordre; si no en són tantes com tantes, cap.
- **El full:** les xifres (quantes per cada criteri, quantes amb Claude obert, les ja lligades i les de Warp que no
  són de la configuració), cada finestra amb quantes de quantes i en quina finestra de Warp, les que s'han de
  comprovar (només pel títol o per la carpeta), que es poden desmarcar, i les que no tenen parella.
- **Què desa** (`ActualitzaEstat.lliga`, `origen` `importacio`: sense canvi de format): el pane; la conversa del
  Claude viu del pane o, si no n'hi ha, la que la pestanya ja recordava (o la de l'entrada que tenia el pane). Un
  pane, una pestanya: si una altra entrada el tenia, el perd.
- **El full d'obrir** ho recorda: si hi ha pestanyes «potser ja obertes», diu que es cancel·li i es lligui abans.
- **Límit:** de les pestanyes on Claude ja no corre, no se'n sap la conversa (la base de Warp no la desa: el
  05/11/2026, només 1 bloc de centenars contenia «--resume»), i en obrir-les en començaran una de nova.
- **Comprovat amb una configuració de prova gran** (05/11/2026, `prova2` i `llegeix --json`, sense obrir l'app): totes
  les pestanyes es lliguen, unes tres quartes parts pel títol i la carpeta i la resta només pel títol (a Warp, la carpeta
  d'inici o la d'abans d'arreglar-la); cada finestra de `prova2` cau sencera en una sola de Warp.

### Conversa de les que s'obren (D7)

**Decisió d'en David del 05/11/2026: sempre la més recent de la carpeta** (0.22.1). Abans, cada pestanya reprenia només la
conversa recordada; el 05/11/2026, en una prova real, totes les pestanyes per obrir n'haurien començat una de nova, perquè les
recordades eren d'una obertura anterior i no tenien missatges.

| `continua` | Hi ha una conversa recent a la carpeta | Conversa recordada | Resultat |
|---|---|---|---|
| no | — | — | Conversa nova |
| sí | sí | — | `--resume <la més recent>`; info «reprèn la conversa més recent de la carpeta (fa 3 dies)», si no és la recordada |
| sí | no | cap | Conversa nova; info «no se'n sap la conversa» |
| sí | no | al projecte de la carpeta | `--resume <id>` |
| sí | no | en un sol projecte, que no és el de la carpeta | `--resume <id>`; avís «la conversa és de <carpeta>; Claude la reprendrà aquí» (L4) |
| sí | no | enlloc | Conversa nova; info «la conversa no tenia cap missatge» (si no, Claude sortiria amb 1) |
| sí | no | en 2 o més projectes, cap del qual és el de la pestanya | Conversa nova; avís |

- **Quines compten** (`LectorTranscripcions.recents`, 0.22.2): `<uuid>.jsonl` al projecte de la carpeta, el primer missatge de les
  quals és de l'usuari i ve del terminal (`entrypoint: cli`, o cap a les versions antigues), i on Claude ha respost. No compten
  `claude -p` (`sdk-cli`), Claude Desktop, que potser encara la té oberta, les que no tenen cap resposta, ni les feines en
  segon pla de principi a fi.
- **Quina és la més recent:** la de l'últim missatge al terminal, buscat des del final. No és la data del fitxer, perquè Claude
  també l'escriu en tancar-se, i les línies d'una feina (`sessionKind`) no compten. Si no surt en els últims 4 MiB, la del
  fitxer. Una feina es llegeix sencera: 71 ms en una carpeta amb una feina de 10 MB; en la pitjor carpeta d'una configuració gran, 73 ms.
- **Quines no s'agafen:** les vives (R9), en una pestanya, fora de Warp o en segon pla, i la d'un Claude aturat a preguntar si
  confies en la carpeta, que encara no té sessió però sí `--resume` als arguments (`LecturaWarp.conversesArrencant`; un d'obert a
  mà, sense marca, no es veu); la darrera vista en una altra pestanya de la configuració (a la mateixa carpeta, cadascuna es queda la seva); la que una altra pestanya acaba de reprendre; i la ja
  represa en aquest llançament. Llavors s'agafa la següent.
- **L'inspector i «Copia l'ordre»** diuen la mateixa conversa que el full, amb les vives de l'última lectura de Warp. Guarden les
  converses de cada carpeta fins a la lectura següent (60 s com a molt), perquè l'inspector les demana a cada redibuix. No saben
  què acaba de reprendre una altra pestanya; el full, sí.
- **Comprovat amb dades reals** (05/11/2026, només lectura): totes les pestanyes per obrir reprenen, cap de nova; el càlcul
  triga 100 ms com a molt per finestra. Algunes converses passen de 200 MB: encara s'ha de veure quant
  triguen a reprendre's, quanta memòria fan servir i si Claude hi fa alguna pregunta.
- **Mai `--continue`; mai el mateix id en dues pestanyes del mateix llançament, ni un id que una altra pestanya acaba de
  reprendre** (regla 4 de «ja obertes»). Si la recordada es repeteix: la segona, nova, amb avís.
- **Projecte d'una carpeta:** `~/.claude/projects/<carpeta amb tot el que no és [A-Za-z0-9] canviat per ->`, seguint
  l'enllaç (hi pot haver projectes que són enllaços a un altre, per exemple si la carpeta dels repos s'ha mogut). Més de 200 caràcters: Claude hi
  posa un hash, i es busca a tots els projectes que no són enllaços, com Claude (`W6e`).
- **`--fork-session` a `altres`:** a més de l'avís d'opció d'un sol ús, «crearà una còpia».
- **Confiança:** si `~/.claude.json` no té `hasTrustDialogAccepted` per a la carpeta o una carpeta pare, avís «Claude
  preguntarà si confies en la carpeta: la pestanya esperarà una tecla». A la carpeta d'inici no es desa mai. Fitxer
  il·legible: cap avís.

### El full de confirmació

- **Xifres:** «S'obrirà 1 finestra nova de Warp amb 9 pestanyes: 6 amb Claude (4 reprenen la seva conversa, 2 en
  comencen una de nova) i 3 només terminal · unes 3 GB · ja obertes: 14 · no s'obriran: 1». 0,5 GB per sessió (el
  03/11/2026, una mitjana d'uns 500 MB). Més de 10 sessions: «totes s'engegaran alhora».
- **Contingut:** llistes per grup amb el motiu de cada pestanya, la versió de Warp i el YAML en un desplegable.
- **Botons:** «Cancel·la» (Esc) i «Obre 9 pestanyes», sense drecera i sense ser el botó per defecte. Si no n'hi ha cap
  per obrir: «Totes les pestanyes ja són obertes», amb «D'acord».

### Seguretat

**Prova de guarda:**
- Sparkle (0.32.0) reobre l'app des del framework, no des de `Sources/`: aquí no hi ha cap excepció (secció 11, apartat 10).
- `warp://` només en una línia, `URL(string: "warp://launch/" + nom)` a `WarpLaunchCore/LaunchConfigWarp.swift`
  (0.15.0, fet). `URLLlancament` té l'`init` intern: fora del core no se'n pot fer cap.
- `NSWorkspace`: `activateFileViewerSelecting(` a `Finder.swift`, i un sol `NSWorkspace.shared.open(`, a l'obridor
  (`ObreWarp`), que rep un `URLLlancament`, obre amb el Warp Stable trobat (fins a la 0.29.1, `/Applications/Warp.app`) després
  de comprovar que el bundle és `dev.warp.Warp-Stable`, i descarta el valor que retorna (`NSRunningApplication` continua
  prohibit). Amb D17 el fa servir també el CLI: l'obridor va en un mòdul que comparteixen tots dos, i continua sent una sola
  crida. Des de la 0.29.2, al mateix mòdul hi ha l'única pregunta a macOS d'on és Warp (`TrobaWarp`, secció 10).
- `launch_configurations` només a `WarpLaunchCore/FitxersLaunchWarp.swift`, i `removeItem`/`unlink` només dins
  d'`esborra`. Des del 08/11/2026, aquest fitxer tampoc no pot esborrar, moure, crear, sobreescriure ni enllaçar res per cap
  altra crida (`prohibidesCarpetaWarp`: també `createFile`, `.write(toFile:`, un `FileHandle` per escriure, `O_RDWR`,
  `O_APPEND` i les llistes `altresEsborrenOMouen` i `altresCreenOSobreescriuen`, amb `rmdir`, `unlinkat`, `renameat`,
  `renamex_np`, `mkdirat`, `trashItem`, `removefile`, `remove` de C, `fopen`, `openat`, `creat(`, `truncate`, `copyfile`,
  `linkItem` i `createSymbolicLink`), i només hi ha les dues crides a `open` d'ara: la que crea el fitxer amb `O_EXCL` i la que
  en llegeix la marca (`obrenAFitxersLaunchWarp`).
- `.confirma(` només a `WarpLaunchUI/FullObertura.swift`. Els botons «Obre…» només criden `demanaObertura(`, sense
  `keyboardShortcut` (substitueix `obreAWarpEsDesactivatISenseDrecera`).
- Es mantenen les altres prohibicions (`Process(`, `openURL`, `NSRunningApplication`, `kill(`…). Warp obert: `sysctl`.
- A `Tests/`, a més: `NSWorkspace`, `openURL`, `ObreWarp`, `FitxersLaunchWarp.real`, `\.warp/`,
  `launch_configurations`, `\.claude\.json` i `\.claude/projects` (`Process(` només al helper de zsh).
- Cap `argv` de `PlaObertura` no porta `--continue` ni `-c`, i el YAML no porta mai `export`.

**CLI (D17):** `warp-launch obre <nom o número de finestra> [--config <carpeta>] [--json]`.
- **Per defecte, mode de prova:** llegeix la configuració, `estat.json`, Warp, les sessions, les transcripcions i la
  confiança; mostra el pla, el nom del fitxer, l'URL i el YAML exactes; la primera línia diu «Mode de prova: no s'ha
  escrit ni obert res». No escriu res, tampoc `estat.json`. Codis de sortida 0, 1, 2 i 64.
- **Amb una opció explícita (`--obre`),** fa el mateix que el full de confirmació: torna a calcular el pla, escriu,
  obre, confirma i esborra, i diu el resultat. Si no hi ha res per obrir, no fa res. **Claude no
  la fa servir mai sense l'OK d'en David per a cada prova** (regla 1).

**Què no fa mai:** tancar, reiniciar o forçar la sortida de Warp ni tancar-ne pestanyes o finestres; matar Claude o
enviar-li senyals; obrir res sense confirmació (el full o `--obre`), tampoc Warp; obrir dues finestres alhora;
escriure o esborrar a `~/.warp/` res que no sigui un `warp-launch-<uuid>.yaml` propi amb la marca (o, amb el permís, la
línia `restore_session` de `settings.toml`: des de la 0.23.0, canviar-la, D19; des de la 0.31.2, afegir-la, secció 10); escriure a
`~/.claude/` o `~/.claude.json` (només en llegeix `sessions/`, el nom dels `projects/*/<id>.jsonl` i
`projects.*.hasTrustDialogAccepted`); fer servir `--continue` o reprendre una conversa viva.

### Passos

Com a la fase 2: cada `feat:` porta proves, el bump de `VERSION` i `WarpLaunch.versio`, i passa `swift build` i
`scripts/test.sh`. Fixtures sempre generats a la prova. **Cap pas obre res fins a la prova L1.**

1. **0.15.0 — l'ordre i el fitxer temporal (core, pur).** Fet (04/11/2026). `argv(_:repren:)` sense `Represa` ni
   `--continue` (D15), `liniaExec` (D16), `YAMLWarp.escalar`, `LaunchConfigWarp` (`genera`, `comprova`, `marca`,
   `esNomPropi`, `FitxerLaunch`, `URLLlancament`). Proves: golden, escalars, errors per camp, i zsh llegint la línia
   del YAML.
2. **0.16.0 — llegir el que cal per obrir (core).** Fet (04/11/2026). `SessioClaude.marca` (de
   `WARP_LAUNCH_PESTANYA`, validat amb `UUID(uuidString:)`); `LecturaWarp.sessionsNoInteractives` i `warpObert`;
   `FontProcessos.pids(nom:)` amb `sysctl KERN_PROC_UID` i `warpObert()` (l'app d'Aplicacions sense arguments);
   `LectorTranscripcions` (`.aLaCarpeta | .altres([String]) | .enlloc`) i `LectorConfianca`. `warp-launch llegeix`
   diu si Warp és obert, les sessions en segon pla i la marca de cada sessió.
3. **0.17.0 — `estat.json` i lligams.** Fet (04/11/2026). `EstatApp`, `ActualitzaEstat.amb` i `.vincula`,
   `MagatzemEstat` (l'escriptura atòmica passa a `EscripturaAtomica`), `Importacio.vincles`, `EstatSessions` (cada
   lectura de Warp, també la de cada 60 s, D18), i l'inspector amb «Conversa: reprèn 1b2c3d4e» o «nova»; «Copia
   l'ordre» amb `--resume <id>` si se sap (D15).
   - **Canvis sobre el pla:** l'entrada d'una pestanya esborrada porta `foraDesDe` (es treu als 30 dies), perquè
     `vista` només canvia quan canvia el lligam (si no, s'escriuria cada minut). Les dates van a segons sencers. Dues
     pestanyes amb el mateix pane només es resolen entre les de la configuració: les esborrades conserven el seu, i
     un Desfés de «Torna a importar» les torna amb el pane. Un `estat.json` malmès bloqueja com una versió més nova:
     l'app no el trepitja i no obrirà res; l'inspector no diu el temps («fa 2 h»), que no se sap sense llegir la
     transcripció.
4. **0.18.0 — el pla, la confirmació i `warp-launch obre` en mode de prova.** Fet (04/11/2026). `PlaObertura`,
   `ConfirmacioObertura` (una finestra amb tots els panes nous, el mateix nombre de pestanyes i els mateixos títols i
   carpetes en ordre; o una sessió amb la marca començada després de `desDe` − 5 s) i l'ordre del CLI.
   - **Canvis sobre el pla:** els avisos de la validació (gravetat «avís») també surten al full, com l'opció d'un sol
     ús al costat de «--fork-session». «Potser ja és oberta» no es mira a la carpeta d'inici. La confirmació no
     descarta una finestra si Warp no ha desat el títol o si la carpeta encara és la d'inici (la shell no l'ha dit):
     L1 dirà què escriu Warp; amb dues finestres que encaixen, no se'n tria cap. El CLI posa al dia els lligams amb
     la lectura només en memòria, com faria l'app abans de calcular; mostra el nom del fitxer, no la ruta (arriba amb
     `FitxersLaunchWarp`, a la 0.23.0); `--obre` dona un error d'ús fins a la 0.24.0. Codis: 0, 1 (no es pot llegir
     la configuració, Warp o `estat.json`), 2 (alguna pestanya no s'obriria) i 64.
5. **0.19.0 — escriure i esborrar el fitxer temporal (core).** Fet (04/11/2026). `FitxersLaunchWarp` (`escriu` amb
   `O_EXCL`, 0644 i `fsync`; `esborra` amb totes les comprovacions; `neteja`) i les regles noves de la guarda.
   - **Detalls:** no crea mai la carpeta de Warp (si no hi és, error; des de la 0.31.5, «Obre» de l'app la crea, secció «Fitxer temporal»). `escriu` també porta `O_NOFOLLOW`, i si falla a
     mig escriure, treu el fitxer només si és el mateix inode que acaba de crear. `neteja(llancaments:ara:)` torna el
     resultat per llançament, per posar-lo al dia a `estat.json`; als fitxers propis que no hi són no els pot mirar la
     mida, només la marca i l'edat (`mtime`). La guarda: `launch_configurations` només en aquest fitxer, un sol
     `unlink(`, cap `removeItem`, `rename`, `createDirectory`, `O_TRUNC` ni `.write(to:`; i a les proves, cap ruta
     de debò de Warp ni de Claude. `warp-launch obre` encara mostra el nom del fitxer i no la ruta (la 0.24.0).
6. **0.20.0 — l'app obre.** Fet (04/11/2026); provat a Warp a L1 (05/11/2026). `Obertura` (`.cap`, `.preparant`,
   `.confirmant`, `.obrint`, `.fet`, `.error`; una sola alhora; registre `obertura` sense noms ni carpetes),
   `FullObertura`, les ordres, el submenú del menú de la icona, el bàner i l'obridor. Proves amb un llançador fals.
   **Abans de L1, una revisió amb revisors i verificadors.** Feta el 04/11/2026 (4 revisors i 4 verificadors): 25
   troballes, 16 confirmades (10 de diferents), corregides a la **0.20.1**:
   - L'espera s'acabava amb la primera marca, i les pestanyes de terminal quedaven sense pane: a L3 o L4 s'haurien
     tornat a obrir. Ara la marca esborra el fitxer, però s'espera la finestra i el Claude de cada pestanya; la marca
     també reconeix la finestra on és, encara que els títols no coincideixin.
   - Una finestra feta a mà (sense títol i a l'inici) es podia prendre per la nostra: ara cal un títol o una carpeta
     que coincideixi.
   - Una pestanya amb marca tancada fa menys d'1 minut es donava per oberta i la finestra es partia: ara és «tancada
     fa poc», i la finestra no s'obre fins que passi.
   - Després de «Torna a importar», la marca antiga s'enduia el `/clear`: ara arriba també a la pestanya del pane.
   - Dues obertures seguides podien reprendre la mateixa conversa abans que se'n vegi el Claude: ara queda «en curs»
     10 min.
   - Sortir a mig obrir deixava el YAML a Warp fins a la pròxima arrencada: ara s'esborra en sortir. En arrencar amb
     un `estat.json` que no es pot fer servir, els fitxers propis vells també s'esborren.
   - Els 30 s compten des que `obre` torna; un llançament amb error també avisa; un llançament nou que no es pot desar
     no queda a la memòria; `.preparant` porta l'id de la petició (dues finestres amb el mateix nom).
   - **Segona revisió (05/11/2026, 2 revisors i 2 verificadors), 0.20.2:** 6 troballes confirmades. La conversa «en
     curs» feia començar una conversa nova a la mateixa pestanya i n'oblidava la de debò, i no es treia en veure el
     Claude: ara només afecta les altres pestanyes (compten com a obertes), només si s'ha vist la finestra, i es treu
     en veure el Claude. `enSortir` desa la finestra i els panes ja vistos. Una sessió dins de Warp sense pane conegut
     ja no atura la finestra (podria ser per hores). Un llançament amb error té un avís propi. El bàner i els avisos
     diuen el nom de la carpeta d'una pestanya sense títol.
   - **Com ha quedat:** els estats són `.cap`, `.preparant`, `.confirmant`, `.obrint` (comprovant, obrint, esperant)
     i `.noEsPot` (abans d'escriure res, al full amb «D'acord»); el resultat d'obrir (`.fet` o error) és un bàner a
     dalt de la llista. L'obridor és un mòdul propi, `WarpLaunchObridor` (`ObreWarp`), que només connecta l'app; el
     llegirà també el CLI a la 0.24.0. L'id del llançament es tria en preparar el full: el YAML de «Detalls» és
     exactament el que s'escriurà, i si en confirmar el fitxer o les pestanyes per obrir no són iguals, es torna al
     full («Warp ha canviat»). Les sessions amb la marca les recull cada lectura (`EstatWarp.enLlegir`); en
     confirmar, l'app hi afegeix el pane de cada pestanya de la finestra nova (`ActualitzaEstat.ambPanes`). En
     arrencar, `netejaEnArrencar` esborra els fitxers propis que hagin quedat. Guarda: una sola crida a
     `NSWorkspace.shared.open(`, a `ObreWarp`; `ObreWarp.obre(` i `FitxersLaunchWarp.real` només a l'app; i els botons
     «Obre…» només demanen el full, sense drecera.
6b. **0.21.0 — «Lliga amb Warp…».** Fet (05/11/2026). En David vol fer L3 amb una còpia de `prova2`, que no té
   lligams: `LligamWarp`, `ActualitzaEstat.lliga`, `Lligam` i `FullLligam`, l'ordre al menú Fitxer i l'avís al full
   d'obrir (vegeu «Lligar amb Warp»). **Revisió** (3 revisors i 3 verificadors): 3 troballes confirmades, corregides
   abans de desar. Un criteri feble a la finestra podia prendre la pestanya que coincidia del tot amb una altra
   finestra de la configuració; la conversa d'una pestanya dividida lligava el primer pane; i les pestanyes de Warp no
   es veien com a la importació (sense títol, o amb el pane a la carpeta d'inici).
6f. **0.22.3 — les feines dels agents, en bypass.** Fet (05/11/2026). Vegeu «Les feines de l'agent» a l'ordre de cada pestanya. Amb una configuració gran de prova
   i Warp buit, calculat sense escriure res: totes les línies porten la variable i reprenen, cap exclosa ni cap conversa repetida; la línia més llarga fa uns 260 bytes. Prova real feta el
   05/11/2026 amb la 0.22.3: una feina nova engegada des d'una pestanya surt en bypass (`fets-verificats.md`).
6e. **0.22.2 — correccions de la revisió de la 0.22.1 i l'script.** Fet (05/11/2026). 2 revisors i 4 verificadors: 3 confirmades, 1
   refutada i 5 sense verificar. Set corregides; la vuitena, el text de la regla 7, depèn de D19. Comparat amb dades reals, només en canvia una pestanya, que deixa de reprendre una
   conversa buida. **L'script fa una sola lectura**, es nega amb `WARP_SETTINGS` buit i ja no crea res a `~/.warp/`.
6d. **0.22.1 — la conversa més recent de la carpeta (D7, revisada).** Fet (05/11/2026). Vegeu «Conversa de les que s'obren».
6c. **0.22.0 — saber què hi ha obert sense la base de Warp, i obrir Warp si és tancat.** Fet (05/11/2026). En David desactiva
   la restauració de sessió i Warp deixa de desar les finestres (vegeu «Sense la base de Warp»). `LectorAjustosWarp` i
   `FontProcessos.terminalsDeWarp`; `LecturaWarp.terminals` i `warpDesaFinestres`; el pla i la confirmació amb els
   terminals; `Confirmacio.vista`; `ObreWarp.engega`, `Fase.engegant` i `Proposta.warpTancat`; la importació i «Lliga» ho
   refusen. Una guarda deixa `openApplication` només a l'obridor. **Abans del commit, una revisió amb 3 revisors i 6
   verificadors** (05/11/2026): 15 problemes diferents, 13 corregits amb la seva prova. Els més importants: el full
   no avisava que la finestra es pot partir, el bàner fals tornava amb una pestanya a la carpeta d'inici, els terminals
   acabaven l'espera amb la restauració activada (es perdien panes), Warp s'engegava sense avisar si es tancava amb el full
   obert, i el full quedava blocat si `openApplication` no tornava. Els 2 que queden: la pestanya de terminal que no es
   reconeix (vegeu «Els límits») i reactivar la restauració, sense provar.
6g. **0.23.0 — l'app gestiona `restore_session` (D19).** Vegeu «Sense la base de Warp». Prova real feta el 05/11/2026: dos refrescs de 5 i 6 s, la foto quadra amb tots els terminals vius (`docs/fets-verificats.md`).
6h. **0.34.0 — les pestanyes de terminal, pel shell** (aprovat per en David l'11/11/2026). Fet (11/11/2026), sense prova real.
   `FontProcessos.inici` (`p_starttime` amb `KERN_PROC_PID`; el d'un shell coincidia amb el `lstart` de `ps`, 11/11/2026),
   `TerminalViu.inici`, `VincleEstat.shell`, `ConfirmacioObertura.shells`, `ActualitzaEstat.ambPanes` amb els shells,
   `OnOberta.shellViu` i `Peticio.carpetesDAltres` («Obre-ho tot»). Proves: el format i la lectura amb la 0.33.0
   (`ShellDeLEstatTests`), cada dubte que no desa res, el pid reutilitzat, l'app (obrir, tornar a obrir, sortir a mig obrir,
   «Obre-ho tot») i el CLI (`--obre`). «Lliga amb Warp…» no en desa: de la foto de Warp no se sap quin shell és cada pane (un
   shell sense fills no porta el pane). Vegeu «Els límits».
7. **0.24.0 — el CLI obre amb `--obre` (D17).** Fet (05/11/2026), sense prova real. Els passos d'obrir després de la confirmació
   (desar el llançament, escriure el fitxer, obrir, esperar la finestra, esborrar i lligar) passen d'`Obertura` a
   `ExecucioObertura` (core), que fan servir l'app i el CLI; també l'espera de l'arrencada de Warp. El CLI depèn de
   `WarpLaunchObridor`. Decisions d'en David (05/11/2026): **amb l'app oberta, `--obre` no fa res** (tots dos escriurien
   `estat.json`: es busca un procés `WarpLaunch`), i **si Warp és tancat, l'obre**, n'espera l'arrencada i torna a calcular;
   si el que s'obriria ha canviat, no obre res (no hi ha full per tornar a confirmar). Sense `--json`. Codi 1 si no s'ha vist
   tot obert. La guarda: `ExecucioObertura` és l'única que escriu el fitxer i crida l'obridor; el CLI només l'arriba a cridar
   amb `--obre`, i només hi crea `MagatzemEstat`.
   Revisió (3 revisors i 3 verificadors, 05/11/2026): 7 defectes confirmats, corregits. Al CLI: amb `--obre` no admet
   `--warp` ni `--sessions` (el pla sortiria d'una base de prova i s'obriria al Warp de debò); el pla i l'espera de Warp
   surten de seguida, no en acabar; **Ctrl-C** a mig obrir esborra el fitxer temporal i desa el llançament; si Warp s'ha
   obert, els errors no diuen «no s'ha obert res»; i sense res per obrir, el text no diu «ja obertes» si n'hi ha d'excloses.
   A l'app, el registre torna a dir per què no s'ha pogut esborrar el fitxer, i «escrit … obre» surt quan toca.
8. **`docs:` fase 3.1 feta,** després de L5 i de l'OK d'en David, i llavors el push.

El pas 12 de la fase 2 (icona) passa a la 0.26.0 (la icona, finalment, a la 0.26.1); la prova 8 continua anant després.

## 8. Fase 3.2: obrir-ho tot (0.25.0, D4)

«Obre-ho tot a Warp…» (menú Fitxer i menú de la icona) demana un sol full per tornar a obrir totes les finestres que falten.
Decisions d'en David (05/11/2026): **totes de cop**; si una falla, **les altres continuen** i el resum ho diu; **una casella per
finestra**, totes marcades.

- **Model:** `Obertura` (extensió a `ObreTot.swift`). Estats `preparantTot`, `confirmantTot(PropostaTot)` i `obrintTot`. Una
  sola obertura alhora, d'una finestra o de totes.
- **El pla:** llegeix Warp un cop (`llegeixPerObrir`) i calcula cada finestra amb pestanyes en ordre (`planifica`). Les
  converses que reprèn una finestra passen a `EntradaObertura.jaRepreses` de les següents: dues pestanyes no reprenen mai la
  mateixa conversa (R9). Una finestra es pot marcar si té pestanyes per obrir, no ha d'esperar i el fitxer es pot generar.
- **«Obre N finestres»** (`confirmaIObreTot`, sense drecera ni botó per defecte): torna a llegir i a calcular amb els mateixos
  ids; si alguna marcada ha canviat, torna al full. Si Warp és tancat, l'obre un cop. Després, una tasca per finestra amb
  `ExecucioObertura` (com una sola), totes alhora i amb una lectura de Warp compartida (0,4 s). `enSortir` esborra tots els
  fitxers en curs.
- **Pestanyes sense marca** (només de terminal, o abans que arrenqui Claude): es reconeixen per la carpeta. Amb diverses
  finestres alhora, el terminal que pren una finestra no compta per a cap altra fins que acaben totes, i un terminal reconegut
  només per la carpeta no fa esborrar el fitxer (`Confirmacio.segura`). Límit: si dues finestres en tenen a la mateixa carpeta,
  l'app encara pot lligar-ne una a la finestra de l'altra (cap Claude no queda repetit). Per això, des de la 0.34.0, el shell
  d'una pestanya de terminal no es desa si una altra finestra que s'obre alhora té alguna pestanya a la mateixa carpeta
  (`Peticio.carpetesDAltres`): si es desés el de l'altra, en tancar aquella finestra la pestanya semblaria oberta i no es
  tornaria a obrir.
- **En marcar o desmarcar,** es tornen a calcular els plans amb la mateixa lectura i els mateixos llançaments: les converses
  d'una finestra desmarcada queden lliures per a les altres.
- **Revisió** (3 revisors i 3 verificadors, 05/11/2026): 5 defectes confirmats, corregits (els dos d'aquí dalt; la finestra buida
  de Warp es diu un sol cop; el resum diu quantes pestanyes van amb Claude; i la prova de «totes de cop» ara ho comprova).
- **Prova real feta el 06/11/2026 amb la 0.26.0:** 1 finestra, 2 pestanyes i 2 sessions, confirmada en 0,6 s (`docs/fets-verificats.md`).

### La foto de les finestres (0.23.0, D19)

`RefrescWarp` (UI, sense res de debò: la connexió és a l'app) i `AjustRestauracio` (core, les comprovacions de `warp-restauracio.sh`; des de la 0.31.2, també afegeix la línia si no hi és, cosa que l'script no fa mai, secció 10). Només amb la carpeta `.real` i, des de la 0.29.0, amb el consentiment de `preferencies.json` (secció 10).

- **L'ajust sempre és `false`:** `vigila()` en arrencar i cada 60 s; `tanca()` en sortir i abans d'engegar Warp.
- **Quan en David ho demana** («Actualitza l'estat de Warp», importar i lligar; fins a la 0.27.3, també cada 5 min), **amb Warp obert:** posa `true`, cada segon llegeix la base i acaba quan **quadra amb els terminals vius** (tants panes com terminals, i tots els coneguts hi
  són) i ha canviat, o quadra i han passat 5 s. Màxim 30 s, o si Warp es tanca. Warp no té temporitzador: si no passa res, no desa, i per això no n'hi ha prou amb esperar un canvi.
- **Lectures:** les de cada minut i les d'obrir, sempre `.mai` (processos), també durant un refresc o si l'ajust ha quedat activat: així la base antiga no canvia res a mitja obertura. `EstatWarp.llegeixAmbFinestres`, per a «Actualitza l'estat de Warp», importar i lligar: Warp obert, refresca; Warp
  tancat, `.sempre` sense escriure res. Sense poder llegir la base, no s'activa res. Si no quadra o Warp és tancat, l'avís (`avisFoto`) surt als fulls d'importar i de lligar i al menú, que a la lectura següent torna als terminals.
- **Sortir:** `atura()`: desactiva i, mentre una alerta pot aturar la sortida, cap cicle torna a activar. Si es cancel·la, `repren()`.
- **Riscos que queden:** si l'app mor a mig refresc o Warp es reinicia molt de pressa dins d'un refresc (de 5 a 30 s), Warp arrencaria amb l'ajust activat i restauraria les finestres. No s'ha mesurat quan llegeix l'ajust en arrencar: cal revisar-ho a la fase 3.3.
- **La foto és la base de Warp:** es manté encara que Warp es reiniciï amb l'ajust desactivat (05/11/2026: encara hi havia les finestres i les pestanyes d'abans). No hi ha cap fitxer nou.

### Sense la base de Warp (0.22.0)

Amb `general.restore_session = false`, Warp no desa les finestres i `warp.sqlite` és d'abans (fets-verificats). `Lector` ni
la llegeix: `finestres` és buit i `warpDesaFinestres` és `false`. Si la restauració és activa, tot és com abans.

**D'on surt què hi ha obert:** dels terminals vius (`TerminalViu`): els fills de `stable terminal-server`, amb la carpeta del
shell i, dels seus fills, el pane i la marca.

| Ordre | Si… | La pestanya és |
|---|---|---|
| 1 | Una sessió viva porta la seva marca | «oberta a Warp, amb Claude» |
| 2 | Un procés viu porta la seva marca, sense sessió (Claude arrenca o s'ha aturat a preguntar) | «oberta a Warp, amb Claude» |
| 3 | Un procés viu porta el pane recordat | «oberta a Warp», amb Claude o sense |
| 4 | El shell recordat és viu: el mateix pid i la mateixa hora d'inici (0.34.0, una pestanya de terminal) | «oberta a Warp», amb Claude o sense |
| 5 | La seva conversa és viva | «la seva conversa és oberta a Warp», fora de Warp o en segon pla |
| 6 | A la seva carpeta, que no és la d'inici, hi ha un terminal sense Claude que no és el shell recordat de cap pestanya, o un Claude sense marca en un pane que cap pestanya recorda | **s'obre, amb un avís** |

La regla 6 només avisa: pot ser una pestanya on Claude n'ha sortit, un Claude obert a mà o un terminal qualsevol, i no se'n pot
saber el títol. Una pestanya de més es veu i es tanca; una que no s'obre perquè «ja és oberta» no es trobaria enlloc, que és el
que va passar.

**La confirmació:** un terminal nou per pestanya (`Confirmacio.vista`), que no hi fos abans d'obrir: el que porta la marca, o,
mentre Claude no ha arrencat, el de la seva carpeta (un per pestanya; la d'inici, llevat que l'app acabi d'engegar Warp, perquè
hi ha la finestra buida). Un Claude aturat a preguntar es veu pel procés: la finestra es confirma, i el bàner diu que encara no
ha arrencat. **Amb la restauració activada, els terminals no compten:** mana la base, com abans. Un shell restaurat tard
semblaria nou, i sense la finestra no se sabrien els panes de les pestanyes de terminal. Des de la 0.34.0, la confirmació
també dona el shell de cada pestanya de terminal (`ConfirmacioObertura.shells`), que es desa a `estat.json` en acabar (o en
sortir de l'app a mig obrir): vegeu «Els límits».

**Una finestra acabada de tancar:** els processos no distingeixen una pestanya oberta d'una que Warp manté 60 s per poder-la
desfer. Per això no es pot bloquejar (`motiuEspera` és sempre `nil`): una finestra oberta a la qual falta una pestanya es veu
igual, i s'ha de poder obrir (D13). Si hi ha pestanyes vives, el full diu «si les acabes de tancar, espera 1 minut» i, si
n'obriria només una part, que la finestra quedarà partida (`.potserTancadaFaPoc`).

**Els límits, que es queden:**
- No se sap en quina finestra és cada terminal.
- Una pestanya tancada a mà semblarà oberta 1 minut, i durant aquest minut la finestra es pot partir (el full ho avisa).
- No es pot importar ni lligar res de Warp, i una pestanya feta a mà que no sigui a la configuració no l'obre mai ningú.
- **Una pestanya de terminal es reconeix pel seu shell** (0.34.0, aprovat per en David l'11/11/2026). Un shell sense fills no
  porta ni marca ni pane, i fins a la 0.33.0 cada «Obre» en feia una altra. Ara, en confirmar el llançament, l'app desa a
  `estat.json` el pid i l'hora d'inici del shell (`VincleEstat.shell`, de `p_starttime`); mentre és viu amb el mateix pid i la
  mateixa hora, la pestanya és oberta (regla 4 de la taula). El pid sol no val: es reutilitza.
  - **Quin shell és de quina pestanya:** un shell nou de la finestra (no hi era abans d'obrir), sense marca ni Claude, a la
    carpeta de la pestanya. Dues pestanyes de terminal de la finestra a la mateixa carpeta són intercanviables: cada shell a una.
  - **Si hi ha dubte, no es desa res,** i la pestanya es torna a obrir com abans (amb un avís, llevat que sigui a la carpeta
    d'inici): un shell de més o de menys a la carpeta (una pestanya oberta a mà durant l'espera); una pestanya amb Claude a la
    mateixa carpeta que encara no porta la marca; una altra finestra que s'obre alhora («Obre-ho tot») amb alguna pestanya a
    la mateixa carpeta; la carpeta d'inici, si l'app acaba d'engegar Warp; o un shell nou del qual no se sap la carpeta o l'hora.
  - **Quan es torna a obrir igualment:** si Warp o el Mac s'han reiniciat (el shell ja no hi és); si la pestanya es va obrir
    abans de la 0.34.0, amb «Lliga amb Warp…» o important (la foto de Warp no diu quin shell és cada pane); amb la restauració
    activada (mana la base); i si la 0.33.0 ha tornat a desar `estat.json` (el camp es perd).
  - Una pestanya on Claude n'ha sortit també es torna a obrir, però una sola vegada (la còpia ja porta la marca), i és el que es
    vol: recupera la conversa.
- Si es torna a activar la restauració, la base torna a manar: no s'ha provat quant triga Warp a posar-la al dia.

**Warp tancat.** Abans, «Obre Warp primer». Ara el full ho diu i el botó «Obre» l'obre (`ObreWarp.engega`), n'espera l'arrencada
(fins a 30 s, i 2 s de marge), i torna a calcular el pla: si Warp ha restaurat alguna pestanya, torna al full («Warp ha canviat»).
Només després escriu el fitxer. Demanar el full no obre res. Si Warp no restaura la sessió, obre també una finestra buida, que
l'app no pot tancar: ho diuen el full i el bàner.
- **El full es queda obert i Warp es tanca:** «Obre» no l'engega, torna al full, i ho diu. El segon «Obre» l'engega.
- **`openApplication` no s'espera** (un diàleg del sistema el podria aturar, i «Cancel·la» està desactivat): corre apart, i el
  límit és el dels 30 s.
- **Warp restaura la sessió i totes les pestanyes hi són:** el full no diu «ja obertes», sinó que Warp és tancat i les
  restaurarà, sense Claude, i no ofereix obrir res.

### Proves reals (cadascuna amb l'OK d'en David)

**Abans de cada prova:** la versió de Warp (`PlistBuddy … CFBundleShortVersionString`); `ls
~/.warp/launch_configurations | grep warp-launch` ha de sortir buit; el registre en directe (`/usr/bin/log stream
--level debug --style compact --predicate 'subsystem == "cat.davide.warp-launch"'`); Claude compila amb
`scripts/build-app.sh` i en David obre l'app. De Warp, només en David tanca res, i a mà.

- **L1. Una pestanya de terminal.** `--config /tmp/warp-launch-provaL1`: 1 finestra «Prova L1» amb 1 pestanya a
  `…/warp-launch/docs`, Claude desactivat. **S'obren 1 finestra de Warp, 1 pestanya i 0 sessions de Claude.** Es mira:
  el full; la finestra nova al davant; si macOS demana permisos; el temps fins a «confirmat» (registre i `warp.log`);
  que el fitxer desaparegui i ⌃⌘L no el mostri; `estat.json` amb el pane; i que tornar a obrir digui «Totes les
  pestanyes ja són obertes» (**amb la restauració desactivada, fins a la 0.33.0 no ho podia dir:** una pestanya de terminal no
  es reconeixia, i tornar a obrir en feia una altra; des de la 0.34.0, la reconeix pel shell, sense provar a Warp). Es desfà:
  en David tanca la finestra; `rm -r /tmp/warp-launch-provaL1`.
  **Feta el 05/11/2026 amb la 0.20.2** (4 obertures, 3 amb Claude; resultats a `docs/fets-verificats.md`). Warp accepta
  el fitxer i l'app confirma en 0,6 s. Desmenteix D16: la línia surt a `~/.zsh_history` i a `commands`. En David
  troba a faltar «Obre a Warp…» a l'editor: la 0.20.3 l'afegeix a la barra d'eines de la llista i al menú contextual
  de la finestra.
- **L2. Una conversa nova.** `--config /tmp/warp-launch-provaL2`: «L2 Claude» a l'arrel del repo (esforç «Alt»,
  ultracode i continuar, sense conversa: `--settings '{"ultracode":true}'`, amb `\"` al YAML) i «L2 terminal» a
  `docs/`. **S'obren 1 finestra, 2 pestanyes i 1 sessió de Claude nova (unes 0,5 GB).** Es mira: l'`argv` exacte i la
  marca (`llegeix --json`); `estat.json`; l'ordre dels panes; que la línia no surti a `~/.zsh_history` ni a `commands`
  (D16); que no surti el diàleg de confiança; el títol. En David escriu «prova L2» a Claude. La finestra queda oberta.
- **L3 amb una configuració gran** (canviada el 05/11/2026: en David la vol fer amb `prova2`, abans que L2).
  `--config /tmp/warp-launch-provaL3`, una còpia de `prova2` (desenes de pestanyes). (a) «Lliga amb Warp…»: el full ha
  de lligar-les totes (vegeu «Lligar amb Warp») i dir quantes tenen Claude obert; «Lliga». (b) «Obre a Warp…» a cada
  finestra: «Totes les pestanyes ja són obertes». **(a) i (b) no obren res.** (c) En David tanca a mà una pestanya amb
  Claude viu (no la de la sessió de Claude que fa la prova), espera 1 min i fa «Obre a Warp…» a la seva finestra: «1 reprèn
  la seva conversa», la resta ja obertes. **S'obren 1 finestra, 1 pestanya i 1 sessió de Claude (la mateixa
  conversa).** Es mira: el mateix `sessionId`, cap diàleg ni «different directory», i `estat.json`. Es desfà: en David
  tanca la finestra nova si vol; `rm -r /tmp/warp-launch-provaL3` (`prova2` no es toca).
  **El 05/11/2026, en David fa una altra cosa:** tanca totes les finestres i les torna a obrir des de l'app, sense
  lligar: totes confirmades, però cap conversa represa, i la majoria dels Claude d'una finestra aturats a la pregunta de confiança
  (`docs/fets-verificats.md`). (a), (b) i (c) queden per fer. **Corregit a la 0.21.1:** l'avís de confiança compara les
  rutes del fitxer tal com són, sense fer-les canòniques (només n'avisava d'una part), i `LecturaPerObrirTests` ho comprova.
- **L3 original, reprendre la conversa** (configuració de L2). (a) Amb la finestra oberta: «Totes ja obertes». (b) En David
  tanca la finestra i espera 1 min; «1 reprèn la seva conversa, 1 terminal». **S'obren 1 finestra, 2 pestanyes i 1
  sessió de Claude (la mateixa conversa).** Es mira: el mateix `sessionId`, «prova L2» a la conversa, cap diàleg ni
  «different directory», i el porta-retalls intacte. (c, opcional) `/clear` i «Actualitza l'estat de Warp»: id nou a
  `estat.json`. Es desfà: en David tanca la finestra; `rm -r /tmp/warp-launch-provaL2`.
- **L4. Una finestra oberta en part (D13).** 3 pestanyes (una amb Claude, dues de terminal). **Primer: 1 finestra, 3
  pestanyes i 1 sessió.** En David tanca una pestanya de terminal i espera 1 min; «2 ja obertes, 1 falta». **Segon: 1
  finestra amb 1 pestanya i 0 sessions.** **Amb la restauració desactivada, fins a la 0.33.0 sortia una altra cosa:** una
  pestanya de terminal no es reconeixia, així que eren «1 ja oberta, 2 a obrir»: **1 finestra amb 2 pestanyes i 0 sessions**,
  i una d'aquestes era una còpia de la que seguia oberta. Des de la 0.34.0, la que segueix oberta es reconeix pel shell, si se'n
  va desar en obrir-la (sense provar a Warp). Opcional, amb un altre OK: `--resume` des d'una altra carpeta (**1
  finestra, 1 pestanya, 1 sessió represa**).
- **L5. Una finestra real.** Abans, amb el seu OK, «Importa de Warp…» crea la configuració real. En David tanca a mà
  una finestra petita i espera 1 min. **S'obren 1 finestra, N pestanyes i fins a N sessions (el full diu el nombre
  exacte).** Es mira: que cada conversa es reprengui, els diàlegs de converses llargues, el temps i la memòria.
- **CLI `--obre` (0.24.0):** la seva pròpia prova, amb OK, com L1.
- **Estat (06/11/2026):**
  - **L1:** feta el 05/11/2026.
  - **L3 amb una configuració gran:** (a) i (b) no s'han fet. El 05/11/2026, en lloc de lligar, en David torna a obrir totes les
    finestres de `provaL3` (Claude aturats per la confiança, corregit a la 0.21.1). La (c), el 06/11/2026 amb la 0.26.0: 1 pestanya
    que reprèn la seva conversa, la resta de la finestra ja oberta, confirmada en 0,6 s.
  - **L4:** una finestra oberta en part, el 06/11/2026 amb la 0.26.0, correcta segons en David (el registre no en té cap línia).
  - **Una configuració gran, sencera:** el 06/11/2026, després d'un reinici, totes les pestanyes es tornen a obrir amb el seu Claude.
    No està comprovat si cada pestanya va reprendre la seva conversa.
  - **Sense fer:** L2, la L3 original, L5 tal com és escrita i la del CLI `--obre`.

### Preguntes obertes i on es resolen

| Pregunta | Prova |
|---|---|
| Warp troba un fitxer escrit just abans, sense esperar el watcher; yaml-rust llegeix els escalars com PyYAML | L1 |
| Quant triga de `open` a la finestra a `warp.sqlite` (d'aquí, els 30 s); esborrar el fitxer no hi afecta | L1 |
| La finestra és nova i al davant; macOS no demana permisos | L1 |
| ⌃⌘L deixa de mostrar el fitxer quan s'esborra | L1 |
| La marca arriba a `KERN_PROCARGS2`, i `'{"ultracode":true}'` arriba intacte | L2 |
| L'espai del davant evita `~/.zsh_history` i `commands` (D16); si no, es diu i es treu | L2 |
| Els panes nous surten a `warp.sqlite` en l'ordre del YAML | L2 i L5 |
| `--resume <id>` manté l'id, sense diàlegs i sense tocar el porta-retalls | L3 |
| `sessions/<pid>.json` s'esborra quan el procés acaba; `/clear` canvia l'id amb el mateix pid | L3 |
| D13 amb una pestanya tancada; confirmació d'una finestra d'1 pestanya | L4 |
| `--resume` des d'una altra carpeta | L4 (opcional) |
| Diàlegs en reprendre converses llargues | L5 |
| 15 pestanyes o més alhora | 3.2 (D4) |
| Warp tancat; l'uuid del pane després d'un reinici | 3.3 (el reinici el fa en David) |
| Reprendre una conversa `bg` viva; dues pestanyes amb el mateix id | No es proven: l'app no ho permet |

### Riscos

| Risc | Què fem |
|---|---|
| El fitxer s'esborra abans que Warp el llegeixi | S'esborra només en confirmar o als 30 s; L1 mesura el temps |
| Un YAML que Warp descarta sense avisar | Generador propi amb golden; L1 i `warp.log` |
| Una conversa oberta en dues pestanyes alhora (s'intercalen) | Regles de «ja oberta»; mai el mateix id dues vegades |
| L'actualització de Warp ja baixada canvia el comportament | Mirar la versió abans de cada prova |
| Les launch configurations són *legacy* a Warp i poden desaparèixer | Es mira a cada actualització de Warp; si deixen de funcionar, es torna a plantejar D5 amb en David |

## 9. Fase 3.3: obrir-se en iniciar sessió (0.27.0, D3)

**Decisió d'en David (06/11/2026):** en iniciar sessió, l'app s'obre sola i mostra el full de «Obre-ho tot a Warp…», amb totes
les finestres que falten marcades; **no obre res fins que hi fa clic.**

- **L'interruptor:** «Obre Warp Launch en iniciar sessió», a la Configuració (secció «En iniciar sessió»). És l'únic camí que
  afegeix l'app als ítems d'inici de macOS (regla 3): l'app no s'hi afegeix mai sola.
  - Fa servir `SMAppService.mainApp` (`ServeiArrencada`, l'únic fitxer amb `SMAppService`): és la mateixa llista que
    Configuració del Sistema › General › Ítems d’inici de sessió, i es desfà amb l'interruptor o des d'allà.
  - Descartat un agent de `launchd` (`SMAppService.agent`): diria segur que l'arrencada és la de l'inici de sessió, però
    desactivar-lo amb l'app en marxa la tancaria, potser a mig obrir.
  - Només amb la configuració de debò, i només amb l'app a `/Applications` (els ítems d'inici apunten al fitxer de l'app;
    des de `build/`, cada compilació el canviaria). Si no, l'interruptor diu per què. Desactivar sempre es pot.
  - Si macOS no l'obrirà sola (falta aprovar-la, o s'ha desactivat a Configuració del Sistema), la secció ho diu, amb
    «Mostra Ítems d’inici de sessió…», i no compta com a activada per mostrar el full.
- **Com sap que és l'inici de sessió** (`InicDeSessio`): l'app és als ítems d'inici i, a més, macOS diu que l'ha obert com a
  element d'inici (`keyAELaunchedAsLogInItem`), o el Mac s'ha encès fa menys de 10 minuts (comptant les estones en repòs). Pendent d'aprovar a Configuració del
  Sistema no compta. No està comprovat que macOS ho
  digui amb `SMAppService.mainApp`: per això també compta el temps. Obrir l'app a mà just després d'encendre el Mac també
  mostra el full, que no obre res sense el clic. **Des de la 0.32.3,** la reobertura després d'una actualització no compta com a inici de
  sessió (`reobertaPerActualitzacio`, secció 11, 3.4), encara que sigui dins dels 10 minuts.
- **Què fa** (`Obertura.enIniciarSessio`): prepara de seguida el full de «Obre-ho tot». Si Warp és tancat, el full ho diu i
  l'obrirà amb el clic; si Warp s'obre sol abans del clic, el clic ho torna a mirar i no l'engega dues vegades.
  - Fins a la 0.27.1 esperava Warp fins a 2 minuts, per si Warp també era als ítems d'inici. L'app no pot saber si Warp
    s'obrirà sol (`settings.toml` no té `login_item`, i `AppAddedAsLoginItem` continua dient `true` després de treure Warp dels
    ítems d'inici), així que des de la 0.27.2 ja no espera (en David, 06/11/2026).
  - Si no falta cap finestra, no hi ha full, i l'editor (que SwiftUI obre sol en arrencar) s'amaga, llevat que s'hi hagi fet
    algun canvi o hi hagi un full.
  - Si mentrestant en David ha obert un altre full o una altra obertura, no la trepitja ni amaga res.
  - Si la configuració o `estat.json` no es poden fer servir, l'editor es queda al davant amb el motiu.
- **Revisió** (3 revisors i 9 verificacions, 06/11/2026): 9 troballes confirmades, totes corregides. Les principals: l'editor
  podia amagar un full que en David feia servir; l'esdeveniment d'element d'inici es llegia massa d'hora (només és viu a
  `applicationDidFinishLaunching`); «pendent d'aprovar» comptava com a activada; el temps no comptava les estones en repòs
  (ara `CLOCK_MONOTONIC`); el nom del tauler és «Ítems d’inici de sessió» (corregit a la 0.27.1 amb la captura d'en David);
  i les guardes eren fàcils de saltar.
- **Prova real (amb l'OK d'en David):** copiar l'app a `/Applications`, activar l'interruptor, i reiniciar el Mac (el reinici el
  fa en David). Es mira: que l'app s'obri sola, quant triga el full, si macOS demana aprovació, i el registre
  (`en iniciar sessió`). Es desfà amb l'interruptor.
  - **Reinici de prova (06/11/2026, 0.27.2):** l'app s'obre sola i prepara el full, amb totes les finestres, en 2 s, però Warp
    també s'obre sol i restaura les pestanyes sense Claude. Amb Warp tancat a mà, el clic torna a obrir totes les pestanyes amb el
    seu Claude. Detall a `docs/fets-verificats.md`, «Primer reinici amb l'arrencada en iniciar sessió». Canvis de la 0.27.3: la foto
    de Warp (D19) només quan en David la demana, i el full diu quantes pestanyes de Warp no reconeix (`PropostaTot.terminalsDesconeguts`).
  - **Falta:** un reinici amb la 0.27.3 (al reinici de prova, l'opció de Warp que l'obre en iniciar sessió, «Start Warp at login»,
    era desactivada segons en David, 07/11/2026: qui va obrir Warp no se sap). Es mira: si Warp s'obre sol i qui l'obre, que no restauri res, i el registre. No dirà si macOS envia `keyAELaunchedAsLogInItem`: l'app no ho
    registra, i amb el Mac encès fa menys de 10 minuts el full surt igualment.

## 10. Per a altres usuaris (del 07 al 09/11/2026, de la 0.29.0 a la 0.31.5)

Les vuit decisions d'en David del 07/11/2026 són a `especificacio.md` («Per a altres usuaris»). El codi i els commits les
anomenen D-P4 (la 4, el consentiment), D-P5a (la 5, importar) i D-P12 (trobar Warp, de la 8). El diagnòstic (pla A4) no surt
de cap decisió. Les dotze decisions que resolen el que aquí quedava per decidir són a la fila del 08/11/2026 d'`especificacio.md`;
el codi les cita pel número («decisió 3», «decisió 4»…). Les de la ronda 4 (08/11/2026), a la fila següent, per la lletra
(«decisió A», la línia que falta; B1 a B4, quatre que es queden com eren). La de la ronda 5 (08/11/2026, el fitxer nou només
amb Warp obert), a la fila de després. Les set de la ronda 6 (08/11/2026, 0.31.4), a l'última: el codi les cita amb la data o
amb la ronda («decisió 3 d'en David, 08/11/2026», «decisió 7 (ronda 6)»), i aquí, «ronda 6, decisió 3». Cada pas va tenir una
revisió, amb correccions.
**Des de l'11/11/2026, l'última versió de GitHub és la 0.33.0** (la primera amb actualització automàtica, secció 11). **Abans, la 0.31.5** (09/11/2026; què s'hi ha provat, a «0.31.5: les cinc decisions»). **La 0.31.4, també publicada, en David l'ha provada a l'app i en un usuari de macOS nou** (09/11/2026, ho ha dit ell).
«Per provar a l'app» i «Per provar en un usuari de macOS nou», al final, i els apartats «A l'app» de cada pas queden com a guia:
no s'ha anotat punt per punt què s'hi ha vist. Tornar-hi és sempre amb l'OK d'en David (regla 4).

### Consentiment de la restauració (0.29.0, D-P4)

- **`preferencies.json`** (versió 1, al costat de la configuració, escriptura atòmica): el consentiment (`senseTriar`,
  `acceptat` amb la data, `migrat` o, des de la 0.31.0, `retirat` amb la data) i el `restore_session` d'abans del primer canvi
  de l'app, desat un sol cop i només amb el permís (el torna «Restaura Warp i surt…», 0.31.0). Un fitxer d'una versió més nova,
  mal fet o un enllaç trencat no se sobreescriu: la pantalla només deixa sortir, amb l'error i la ruta. `configuracio.json` no
  canvia (regla 11).
- **Migració:** una carpeta amb `configuracio.json` o `estat.json` i sense `preferencies.json` compta com a acceptada, sense
  preguntar ni escriure res. Qui ja tenia una configuració no veu la pantalla (decisió 1: el permís, només als nous); el fitxer
  s'escriu el primer cop que l'app canvia l'ajust, amb el valor d'aquell moment (si l'app ja el gestionava, `false`, no el
  d'abans de D19). Un `retirat` no torna a comptar mai com a migrat.
- **Sense consentiment, l'app no toca Warp:** ni `RefrescWarp` ni `AjustRestauracio` (tampoc en sortir), ni llegeix Warp, ni
  neteja els seus fitxers temporals, ni proposa obrir res (una finestra, «Obre-ho tot», el full d'inici de sessió). El menú de la
  icona només té «Mostra Warp Launch» i «Surt».
- **La pantalla** (`VistaConsentiment`, a l'editor i a la Configuració) diu per què cal i què canvia (l'ajust «Restore windows,
  tabs, and panes on startup», Settings Sync i els segons en què l'app l'activa quan es demana llegir Warp). «Accepta» o «Surt de
  Warp Launch». **Des de la 0.30.3, «Accepta» és el botó per defecte** (decisió 2): Retorn el prem, si es pot acceptar. Escapada
  no fa res: a macOS vol dir «Cancel·la» i tornar on eres, i aquí «Surt» tanca l'app (per sortir hi ha ⌘Q i tancar la finestra).
  Sortir, o tancar l'editor o, des de la 0.30.3, la Configuració (decisió 8; tots dos ho pregunten a
  `ConsentimentRestauracio.continuaEnTancarFinestra`), tanca l'app sense desar res, i la propera vegada ho torna a preguntar. Amb
  el permís acceptat, o sense carpeta, la finestra es tanca i l'app continua. Amb una carpeta de prova (`--config`) també surt, i
  diu que l'app no tocarà l'ajust. En iniciar sessió, primer la pantalla i després el full de «Obre-ho tot». **Des de la
  0.31.2** (decisió A), «Què canvia» diu també que Warp Launch desa l'ajust al fitxer d'ajustos de Warp encara que no l'hagis
  canviat mai. **Des de la 0.32.2** (decisió 7 de Sparkle), també diu que l'app mira a GitHub un cop al dia i que es pot apagar. Abans
  d'acceptar, Sparkle no s'engega.
- **Guarda:** el refresc només el crea `ConsentimentRestauracio`, un cop i amb el consentiment acceptat; l'entorn de l'ajust,
  només l'app i amb `.real`. La revisió hi va afegir cada línia amb `creaEntornRefresc`, les assignacions de l'estat (5 des de la
  0.31.0), `accepta(` només des del botó i del model, i `.acceptat(`, `.migrat`, `.retirat(` (0.31.0) i `.restauracio =` només a
  `Preferencies.swift`: tres camins que la primera guarda no veia ara fallen. Des de la 0.30.3, «Accepta» porta `.defaultAction`,
  és l'única drecera del fitxer i no s'hi pot enganxar Escapada (`elPermisSAcceptaAmbRetornINoAmbEscapada`).
- **Proves:** `PreferenciesTests` (13), `ConsentimentRestauracioTests` (8, amb un ajust fals que sense consentiment no rep cap
  `posa`) i 2 a `OberturaTests`.
- **A l'app, amb `--config` i una carpeta nova:** surt la pantalla; «Surt de l’app Warp Launch» i tancar l'editor tanquen l'app sense
  crear `preferencies.json`; «Accepta» el crea i passa a l'editor (barra d'eines i mida); amb `{"versio": 9}`, l'error amb la
  ruta. Amb la configuració real, no pregunta res.
- **Decidit (08/11/2026):** la migració també val per a qui ja feia servir la 0.28.0 (decisió 1); Retorn accepta (decisió 2) i
  tancar la Configuració amb la pantalla fa sortir de l'app (decisió 8), tots dos a la 0.30.3. A la ronda 4: `retirat` es queda
  a la versió 1 de `preferencies.json` (B2), i esborrar només `preferencies.json` i deixar `configuracio.json` torna a comptar
  com a migrat (B3; el README diu d'esborrar tota la carpeta).

### Importar una configuració nova (0.29.1, D-P5a, i 0.30.3)

- Les pestanyes on no corria Claude queden només terminal, a l'app («Crea») i a `warp-launch importa` sense configuració real
  (secció 2, «Importació (R2)»). Des de la 0.31.5, també en tornar a importar.
- El full i el CLI ho diuen amb xifres (per exemple, «4 només terminal: 2 sense Claude obert, 1 a la carpeta d'inici i 1 amb una carpeta que
  ja no existeix»), i el full explica com s'hi activa Claude a l'inspector i amb quina ordre. La revisió va corregir tres textos
  que encara deien que hi entraria Claude (l'avís de la foto amb Warp tancat, la nota d'una sessió sense pestanya i la
  Configuració › «Pestanyes noves» sense configuració).
- **Proves:** a `ImportadorTests`, `FullImportacioTests`, `OrdreCLITests` i `EditorTests` (configuració nova contra tornar a
  importar: només difereixen les pestanyes sense Claude obert).
- **A l'app, amb `--config` i una carpeta nova:** el full «Importa de Warp», i que després de «Crea», «Obre Claude Code en
  aquesta pestanya» hi posi `claude`.
- **Una configuració sense cap pestanya (0.30.3, decisió 9):** «Comença en blanc» i després «Torna a importar-ho tot de Warp»
  és com una importació nova: les pestanyes sense Claude obert queden només terminal, amb la plantilla de la configuració. El
  full continua sent el de substituir, amb còpia i Desfés. Una configuració amb només finestres buides també compta com a sense
  pestanyes (B4, ronda 4: es queda així). Proves a `ImportadorTests`, `EditorTests` i `OrdreCLITests`. Des de la 0.31.5, la
  distinció ja no existeix: tota importació deixa només terminal les pestanyes sense Claude viu.
- **Amb una carpeta de prova (0.30.3):** sense refresc no hi ha finestres per importar, i el full «Importa de Warp» ho explica:
  amb `--config` l'app no toca l'ajust ni pot demanar a Warp que desi les finestres, i amb la configuració de debò, sí. El CLI
  diu que ell no toca l'ajust i que l'app, amb la configuració de debò, sí. **Des de la 0.31.2,** «Lliga amb Warp…», que té la
  mateixa causa, ho diu amb el mateix text, i hi afegeix que amb la configuració de debò l'app sí que pot demanar a Warp que
  desi les finestres. El motiu és un sol tipus per als dos fulls (`MotiuSenseFinestres`, a `EstatWarp.swift`: `.deProva` i
  `.senseWarp`), i cada full hi afegeix què es pot fer; el d'importar diu el mateix que a la 0.31.1. `Lligam` rep si hi ha
  refresc (`ambRefresc`).
- **Decidit (08/11/2026):** amb Warp tancat i sense configuració (la primera importació després d'un reinici, de l'última foto),
  cap sessió no és viva i totes queden només terminal, com ara (decisió 10). **Per decidir:** `importa` amb la configuració real
  malmesa fa servir la plantilla segura. Risc de D4: moltes
  més pestanyes només terminal (en una lectura real, més del triple), que es poden confondre si dues finestres en tenen a la
  mateixa carpeta.

### Warp Stable a qualsevol carpeta, i Warp Preview (0.29.2 i 0.29.3, D-P12; 0.31.1, decisió 4)

- **On és Warp:** ho diu macOS (`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`), en una sola línia de
  `WarpLaunchObridor/TrobaWarp.swift`, on cap prova no arriba. El core en rep el resultat (`InstallacioWarp.troba(aplicacions:cerca:)`,
  amb una `cerca` falsa a les proves). Si macOS no en sap res, o diu una carpeta on ja no és o un paquet que no és Warp,
  `/Applications/Warp.app`, com fins ara. Una còpia a la Paperera (`.Trash` o `.Trashes`) no compta (0.29.3).
- **El binari** surt del paquet (`CFBundleExecutable`): és el que compta com a Warp obert, el del seu `terminal-server`
  (`warpObert(executable:)`, `terminalsDeWarp(executable:)`) i el que obre `ObreWarp`. `executableWarp` ja no existeix. Es mira a
  cada lectura (des de la 0.31.1, `Lector.installacio()`).
- **El Warp que corre (0.31.1, decisió 4: les dues còpies, arreglat abans de convidar ningú).** Si corre una còpia de Warp
  Stable que no és la que diu macOS (una segona còpia, o una que macOS executa des d'una carpeta temporal, App Translocation),
  compta aquella: per a «és obert», els terminals, el diagnòstic, la versió del full i on s'obren les finestres. Es reconeix pels
  processos, pel mateix camí que `warpObert`: l'app sense arguments, dins de `<paquet>.app/Contents/MacOS/`, d'un paquet
  `dev.warp.Warp-Stable` amb aquell binari (`InstallacioWarp.ambLaCopiaOberta`, només des de `Lector.installacio()`). La
  Paperera no compta. Si no en corre cap, la que diu macOS; amb totes dues obertes, també; amb dues obertes i cap de macOS, la de
  pid més baix. `ObreWarp.obre` i `engega` ja no tenen cap Warp per defecte: l'app i el CLI hi passen `lector.installacio()`.
- **Sense cap Warp (0.31.1):** la lectura ho diu (`WarpPreview.capWarp`: «No s'ha trobat Warp en aquest Mac: cal Warp Stable.»),
  com amb Warp Preview: ni una finestra, ni «Obre-ho tot», ni el full d'inici de sessió proposen obrir res; `llegeix` ho mostra
  amb ⚠, `obre` amb ✗ i el codi 1, i `obre --obre` falla sense escriure res. Si tampoc no hi ha la base de Warp, el CLI ho diu
  igual, en lloc de «no trobo la base de Warp» (revisió). `capWarp` és dins de `WarpPreview` per no canviar el JSON de
  `llegeix --json`.
- **Guarda de la 0.31.1:** `TrobaWarp.delSistema` només a l'app i al CLI (abans també a `ObreWarp`); les línies exactes
  d'`ObreWarp.obre(` i `ObreWarp.engega(` amb `warp: lector.installacio()`; ningú no fa servir `lector.warp`; i `AppWarp.delBinari`
  només a la font de processos, la de debò i la falsa de les proves, que només llegeix dins de les seves carpetes temporals: una
  prova no pot llegir l'Info.plist del Warp de debò (`lesProvesNoLlegeixenElWarpDeDebo`).
- **Warp Preview** (`dev.warp.Warp-Preview`) no és compatible. Si només hi ha Preview, o és obert i Stable no
  (`LecturaWarp.warpPreview`: `.nomesPreview` o `.obert`), no s'obre res, tampoc Warp Stable: «Warp Preview encara no és compatible:
  cal Warp Stable.» (una finestra, «Obre-ho tot» i l'inici de sessió). `obre --obre` falla sense escriure res; `llegeix` ho
  mostra amb ⚠ i `obre`, amb ✗ i el codi 1, també en mode de prova. `warpPreview` és un codi a `llegeix --json` («obert» o
  «nomesPreview») i un text a `obre --json`. Amb tots dos oberts, Stable, sense dir res.
- **Guarda (l'excepció de la decisió 8):** `urlForApplication` només a `TrobaWarp.swift` i amb `$0` (falla en 8 fitxers més, o
  amb una altra crida o un altre identificador); els dos identificadors, només a `AppWarp.swift` i amb el text exacte. Les proves
  no poden esmentar `TrobaWarp` ni `urlForApplication`, ni cridar `troba` sense una carpeta temporal. `NSWorkspace.shared.open` i
  `openApplication` continuen només a `ObreWarp.swift`.
- **Proves:** `AppWarpTests` (13, amb la Paperera), la guarda, `OrdreCLITests` i `OberturaTests` (una finestra i «Obre-ho tot»
  amb Preview). Al Mac de prova, només amb `--versio` i `llegeix`: troba el Warp d'`/Applications` per macOS, obert, i en llegeix els
  terminals.
- **Per provar:** Warp a `~/Applications` (el mou en David) i Warp Preview (l'identificador no s'ha verificat amb un Preview
  instal·lat).
- **Sense cap Warp ni la seva base (0.31.2):** l'app llegeix amb `Lector.llegeixDeLApp` a les dues lectures (la de cada minut i
  la que refresca la foto). Si la base no hi és i tampoc no hi ha cap Warp Stable (`Lector.senseWarpStable()`), llegeix els
  processos (`.mai`), i la lectura diu `.capWarp` (o `.nomesPreview`). Abans, amb una carpeta de prova sempre, i amb la de debò
  en importar i lligar (que refresquen amb `.sempre`), deia «No s'ha pogut llegir Warp: no trobo la base de Warp». Ara, en tots
  dos casos, «Obre» i «Obre-ho tot» diuen «No s'ha trobat Warp en aquest Mac: cal Warp Stable.», el menú diu «Warp: 0
  terminals · 0 sessions de Claude», importar i lligar diuen aquest motiu (`MotiuSenseFinestres.senseWarp`; importar hi afegeix
  que no hi ha res per importar), i el refresc no diu que és una foto antiga si no n'hi ha cap (`RefrescWarp.avisant`). Amb Warp
  Stable sense base, o sense Warp però amb la base, com abans. El CLI no canvia: falla, i fa servir `senseWarpStable()` per dir
  per què. Les pestanyes d'`estat.json` en surten avisades com amb Warp tancat; no s'esborra cap lligam.
- **Warp Stable sense la seva base (0.31.3):** un Warp Stable que encara no s'ha obert mai en aquest usuari no té base (Warp la
  crea a cada arrencada, `fets-verificats.md`). La lectura de l'app ja no falla amb «no trobo la base de Warp»: llegeix els
  processos i ho marca (`LecturaWarp.warpSenseBase`, opcional al JSON). El text és a `LecturaWarp.senseBase(warpObert:)`, igual
  a l'app i al CLI: «Warp encara no ha desat cap finestra en aquest usuari: obre'l un cop i torna-ho a provar.» o, amb Warp obert,
  «… si Warp s'acaba d'obrir, torna-ho a provar d'aquí a uns segons.» (0.31.4, ronda 6, decisió 4: segons el codi, Warp obert i
  sense la base només passa en els primers instants de l'arrencada, després de tancar la sessió del compte de Warp, fins que s'hi
  torna a entrar, o si Warp no pot fer servir el Group Container; en els dos últims casos, tornar-ho a provar no ajuda). No parla
  de la restauració, que de sèrie és activada.
  - Importar (`MotiuSenseFinestres.senseBase`, abans de `.deProva`) hi afegeix «Si no, tria «Comença en blanc»…» o «La
    configuració no canvia.»; lligar, que les pestanyes amb Claude que obre l'app es lliguen soles, i no desa res.
  - El menú diu «Warp: N terminals · M sessions de Claude», sense error, també cada minut amb una carpeta de prova.
  - El refresc, sense la base, no activa l'ajust (`RefrescWarp.cicle`, com quan la lectura fallava).
  - `llegeix`, `importa` i `obre` diuen el mateix text, amb el codi 1. Amb `--warp` i una base que no hi és, l'error de sempre.
  - **Amb Warp Preview obert** i Stable sense la base, importar, lligar i el CLI diuen el text de Preview del full d'obrir
    («… Ara és obert Warp Preview, i Warp Stable no: obre Warp Stable i torna-ho a provar.»), i lligar no diu que les
    pestanyes es lliguen soles (amb Preview, l'app no obre res).
  - **Amb una carpeta de prova i sense la base,** «Obre a Warp…» proposa obrir pels processos, com amb la configuració de debò
    (abans, «No s'ha pogut llegir Warp»). Confirmat per la ronda 6 (decisió 6); a la 0.31.4, amb proves d'«Obre a Warp…» (Warp
    obert i tancat) i d'«Obre-ho tot…» a `OberturaTests`.
  - Proves a `AppWarpTests`, `OrdreCLITests`, `EditorTests`, `LligamTests` i `RefrescWarpTests`.
- **Decidit (en David):** amb Preview obert i Stable tancat, l'app no obre res i demana obrir Stable a mà, com ara (decisió 5);
  les dues còpies, fet a la 0.31.1 (decisió 4). **Ronda 4 (B1):** un Warp que corre des de la Paperera no compta, com ara: l'app
  el veu tancat i n'obriria l'instal·lat (dos Warp) o, si no n'hi ha cap més, diu «No s'ha trobat Warp» amb un Warp a la vista.
- **Per decidir:**
  - Dues còpies amb el binari amb un nom diferent de `stable` i del de la còpia de macOS: la que corre no es reconeix (avui Warp
    sempre fa servir `stable`; recomanació: deixar-ho).
  - El CLI `obre` continua fallant sense la base, encara que l'app hi pugui obrir pels processos (ja hi era).
  - Sense Warp però amb la base d'un Warp desinstal·lat, importar i lligar fan servir aquella foto vella mentre «Obre» diu que
    no hi ha Warp. Amb la carpeta de debò ho avisa («Warp és tancat: és la foto…»); amb una de prova, no. Va com abans.
- **Sense comprovar:** que obrir el fitxer amb la ruta d'un Warp traslladat (App Translocation) el lliuri al Warp que ja corre.

### Diagnòstic (0.30.0 i 0.30.1, pla A4)

- **Per què:** que un canvi de format de Warp o de Claude Code es vegi, en lloc de fallar en silenci. No bloqueja res (en David
  no ha acceptat aturar «Obre-ho tot»), no executa cap programa i no escriu res.
- **Vuit comprovacions** (`Diagnostic`, amb un `EntornDiagnostic` que les proves substitueixen), cadascuna bé, avís o error, amb
  el detall en anglès: terminals de Warp; fitxers de sessió (`claude` sense fitxer vàlid, il·legibles, `kind` desconegut);
  transcripcions; `~/.claude.json` (`projects`, `hasTrustDialogAccepted`); taules i columnes de `warp.sqlite` (`LectorWarp.esquema`,
  `PRAGMA table_info` en només lectura, només si Warp desa la base); versions de Warp (Info.plist) i de Claude Code (fitxers de
  sessió dels processos vius), comparades amb `VersionsProvades` (Warp 0.2026.10.21, Claude Code de la 2.1.317 a la 2.1.318; fora,
  avís «no provada»); i `restore_session` amb el consentiment.
- **CLI:** `warp-launch diagnostica [--json] [--anonimitza]`; codi 1 si alguna dona error, 64 si l'ús és incorrecte.
  `--anonimitza` treu el nom d'usuari, la carpeta d'inici i els noms de carpeta, també dins dels errors, i en deixa la forma
  (`~/Codi-Prova` → `~/Aaaa-Aaaaa`); es queden els noms que l'app llegeix (`.claude`, `sessions`, `Warp.app`…).
- **App:** Configuració › General › «Diagnòstic» (a la pestanya «General» des de la 0.30.2): «Copia el diagnòstic»
  (anonimitzat) i, al seu menú, «Copia el diagnòstic complet»; al costat, què s'ha copiat («Copiat (anonimitzat): 6 bé, 2
  avisos, 0 errors.»). Llegeix fora del fil principal amb el mateix `Lector` (`CopiaDiagnostic`). Només es veu amb el consentiment acceptat.
- **Revisió (0.30.1):** `daemon` és un `kind` conegut; el binari de Claude que corre com a `ugrep` no compta; un `claude` sense
  fitxer en una carpeta on Claude no confia (espera la pregunta de confiança) és una nota, no un error; un fitxer d'un procés viu
  que l'app no veu com a `claude` és un avís; l'anonimització treu també les rutes relatives.
- **Textos (0.30.3):** amb una carpeta de prova, la comprovació de `restore_session` diu «With a test configuration folder
  (--config), Warp Launch doesn't turn it off», en lloc de prometre desactivar-lo en un minut (`EntornDiagnostic.configuracioDeProva`:
  l'app hi passa el seu valor; el CLI llegeix la de debò). La versió de Claude Code surt un sol cop, com la de Warp; si se'n
  barregen de provades i no provades, cada no provada porta «not tested with Warp Launch». Des de la 0.31.0, també diu quan es
  va retirar el permís.
- **`restore_session` sense la línia (0.31.2, decisió A):** la comprovació llegeix `settings.toml` com l'app
  (`AjustRestauracio.llegeix` i l'anàlisi, estàtiques i de només lectura), i no pel seu compte. Sense la línia, diu «Warp uses
  its default, on» i que Warp Launch hi afegeix `restore_session = false` a `[general]`: en menys d'un minut, amb el permís;
  només amb la carpeta de debò, si és una de prova; quan gestioni l'ajust, si encara no hi ha permís. Sense el fitxer, que el
  crea només amb la línia; sense `~/.warp`, que Warp no s'ha obert mai en aquest usuari i que Warp Launch no la crea. Si l'app
  refusa el fitxer (un enllaç, un text que no és UTF-8, una carpeta de Warp que és un fitxer, o una forma on no s'hi pot afegir
  la línia), és un error, amb el motiu en català (anonimitzat, si es demana) i com fer que l'app el pugui gestionar. **Canvi de
  la revisió, per confirmar:** amb un `settings.toml` que és un enllaç, és un error encara que hi hagi la línia, i no en diu el
  valor (l'app, amb un enllaç, no el llegeix).
- **Sense `settings.toml` (0.31.3, ronda 5):** diu que Warp encara no hi ha desat cap ajust, que Warp Launch el crearà només amb
  Warp obert i amb un terminal (i per què: la migració de Warp), i com és Warp ara, pels processos: «Warp is closed now.»,
  «Warp is open now, with no terminal yet.» o «Warp is open now, with a terminal.». Sense `~/.warp`, que Warp no té cap finestra
  per restaurar. En tots dos casos ja no diu «after a restart, it restores its own windows», i continua sent un avís.
- **Guarda:** `Diagnostic.swift` no conté cap de 23 maneres d'escriure, d'executar o de tocar el porta-retalls (des del
  08/11/2026, tampoc `mkdir(` ni les d'`altresEsborrenOMouen` i `altresCreenOSobreescriuen`, com a la carpeta de Warp, secció 7);
  `CopiaDiagnostic` només a l'app (a les proves, amb un porta-retalls fals); a les proves, `LectorTranscripcions` i
  `LectorConfianca` amb una ruta de prova. Aquestes guardes veuen els noms amb mòdul (`(^|[^A-Za-z0-9_])`, no `\b`).
- **Proves:** 28 al core (27 a `DiagnosticTests`, cada comprovació amb un fixture bo i un de trencat, l'anonimització i que no
  canvia cap fitxer; 1 a la guarda) i 1 a la UI (`CopiaDiagnosticTests`). La 0.31.2 n'hi suma 2 a `DiagnosticTests`.
- **Per provar (amb l'OK d'en David):** `warp-launch diagnostica` sobre l'estat real, que no és a la regla 4 (amb Warp
  0.2026.11.04 i Claude Code 2.1.319, més noves que `VersionsProvades`, s'esperen 2 avisos de «no provada»), i el botó a la Configuració.
- **Pendents:** `VersionsProvades` es posa al dia a mà després de cada prova real amb una versió nova. No s'ha vist amb un dimoni
  real que `claude daemon run` escrigui el fitxer de `kind` `daemon`. Els motius d'`AjustRestauracio` i `Preferencies` surten en
  català dins de l'informe fins a la traducció. Les guardes antigues que no veien els noms amb mòdul, i el `Lector(` de les proves
  sense `carpetaSessions`, es van arreglar el 08/11/2026 (vegeu «Guardes», a sota).

### Deixar de fer servir l'app (0.31.0, decisió 3)

- **On:** al final de Configuració › General, la secció «Deixar de fer servir Warp Launch»: la fila «Torna a deixar Warp com
  era», que diu com quedarà l'ajust, i el botó vermell «Restaura Warp i surt…». La confirmació diu què passarà (també Settings
  Sync, si l'ajust es torna a activar), i «Cancel·la» és el botó per defecte.
- **Què fa** (`Desinstallacio.confirma`), en ordre; si un pas falla, ho diu a la secció i no fa els següents:
  1. treu l'app dels ítems d'inici, si hi és (`ArrencadaSessio.treuDelsItemsDInici`, que va a `ServeiArrencada`);
  2. torna `restore_session` com era: el valor desat, si se sap; amb `migrat`, activat, el de sèrie de Warp (el text ho diu
     abans); si l'app no l'ha canviat mai, no hi toca. Si no hi havia la línia (0.31.2, decisió A), el valor desat és el de
     sèrie, `true`: la línia que l'app hi va afegir es queda, amb `true`. Si ara no hi és (ni el fitxer, ni la carpeta de Warp),
     ja és activat, i no s'escriu res;
  3. retira el permís (`retirat`, amb la data; el valor original desat s'esborra);
  4. surt de l'app.

  Abans de cap pas, comprova que `preferencies.json` encara diu el que ha mostrat la confirmació (revisió).
- **Després,** l'app no torna a tocar l'ajust: ni la vigilància de cada minut, ni un refresc a mitges (s'atura), ni sortir. Si
  l'ajust no es pot posar, no canvia res; si el permís no es pot desar, l'ajust torna a quedar desactivat (i, si tampoc no es pot,
  ho diu). La propera vegada, l'app torna a preguntar, encara que hi hagi `configuracio.json`. La configuració no s'esborra.
- **Només** amb la configuració de debò i el permís acceptat o migrat; si no, el botó és desactivat i el peu diu per què.
- **Guarda:** cada pas és una excepció en un sol fitxer, i una prova demostra que la mateixa línia falla a qualsevol altre:
  posar l'ajust a un valor que no és el d'un refresc, només `RefrescWarp.swift`; retirar el permís, només
  `ConsentimentRestauracio.swift`; tot plegat, i treure l'app dels ítems d'inici fora de l'interruptor, només
  `Desinstallacio.swift`; confirmar, només el botó de `VistaConfiguracio.swift` (`deixarDeFerServirLAppNomesDesDelBoto`,
  `laRetiradaNomesValAlSeuFitxer`).
- **Proves:** `DesinstallacioTests` (12; 17 des de la 0.31.2, amb els casos sense la línia, sense el fitxer i sense la
  carpeta de Warp), i més a `PreferenciesTests`, `RefrescWarpTests`, `ArrencadaSessioTests`, `DiagnosticTests` i la guarda.
  README.md, «Desinstal·lar».
- **Decidit:** `settings.toml` sense la línia, a la 0.31.2 (decisió A, a sota); `retirat` es queda a la versió 1 (B2: la 0.29
  i la 0.30, no publicades, el llegirien com un error i no tocarien res; la 0.28.0 no llegeix el fitxer); esborrar només
  `preferencies.json` torna a comptar com a migrat (B3).
- **Per decidir:**
  - Cas rar: si la sortida es cancel·la perquè la configuració no s'ha pogut desar, la pantalla «Has deixat de fer servir Warp
    Launch» tapa l'editor i només deixa sortir sense desar.
  - La confirmació parla de Settings Sync encara que, si la línia no hi és (perquè l'app no l'ha pogut afegir), no s'escrigui
    res.

### Sense la línia `restore_session` (0.31.2, decisió A; 0.31.3, ronda 5; 0.31.4, ronda 6)

**Per què.** Warp només escriu a `settings.toml` els ajustos que s'han canviat, i de sèrie `restore_session` val `true`
(`fets-verificats.md`; deduït, no vist per a aquest ajust). Qui no l'ha canviat mai no té la línia, i potser ni el fitxer. Fins
a la 0.31.1, `AjustRestauracio` ho refusava («hi surt 0 vegades»), i l'app no podia fer D19 a cap usuari nou: l'avís hi era
sempre, Warp restaurava les pestanyes sense Claude i, amb `migrat`, «Restaura Warp i surt…» fallava cada vegada.

**Què fa `AjustRestauracio`** (l'únic que escriu `settings.toml`, la segona excepció de la regla 7), sense cap aparició de
`restore_session`:
- **`valor()`** torna `true`, el de sèrie (`Preferencies.restauracioDeSerie`), també sense el fitxer i sense `~/.warp`. És el
  valor original que desa `preferencies.json`. Sense `~/.warp` no refusa, perquè «Restaura Warp i surt…» el llegeix abans de
  posar-lo (`posaRestauracio`) i ha de poder acabar.
- **`posa(true)`** no escriu res i torna que no ha canviat res.
- **`posa(false)`** hi escriu `restore_session = false`:
  - just després de l'única capçalera `[general]` (amb la tolerància d'espais d'`analitza`, perquè després la pugui llegir);
  - sense cap `[general]` però amb subtaules (`[general.x]`), la taula just abans de la primera: al final, segons la feina,
    només seria vàlid a TOML 1.0 (no s'ha verificat), i no se sap quin lector fa servir Warp;
  - sense cap de les dues, la taula al final, amb una línia en blanc abans; un fitxer buit queda només amb la taula i la línia;
  - sense el fitxer, el crea només amb això, amb 0644, i **des de la 0.31.3, només amb Warp obert i amb algun terminal**
    (ronda 5, a sota): el prepara a la carpeta temporal (al mateix volum) i el posa al seu lloc amb `renamex_np` i
    `RENAME_EXCL`, que falla si Warp l'ha creat mentrestant. Crear-lo directament amb `O_CREAT` no serviria (Warp vigila la
    carpeta i en podria llegir un de buit o a mitges), i un enllaç dur deixaria un segon nom;
  - sense la carpeta de Warp, refusa («Warp encara no s'ha obert mai en aquest usuari»; `Refusat.warpMaiObert`) i no la crea.
    El menú de la icona diu `RefrescWarp.notaWarpMaiObert`: «Warp encara no s'ha obert mai en aquest usuari: no té la seva
    carpeta d'ajustos, ni cap finestra per restaurar. Quan Warp la creï i sigui obert amb alguna pestanya, Warp Launch en
    desactivarà la restauració de sessió en menys d'un minut.» Des de la 0.31.4 (ronda 6, decisió 5) és una nota, amb la icona
    d'informació i sense el triangle, perquè no hi ha res per restaurar (`Pendent.warpMaiObert`): un sol intent per vigilància,
    i al registre és una nota i no un error. Si no es pot retirar el permís, el missatge diu el mateix que sense `settings.toml`.
    Quan apareix la carpeta, la nota marxa; si encara no hi ha el fitxer, en surt la de la 0.31.3 (a sota) fins que es pot crear.
- **Refusa sense tocar res** tot el que podria definir `general` d'una manera que no sap llegir (una segona taula `[general]`
  faria el fitxer invàlid, i Warp no en llegiria cap ajust): dues capçaleres `[general]`; `general` com a clau a qualsevol
  taula (`general = {…}`, `general.x = …`, entre cometes); la capçalera entre cometes, amb un comentari darrere o com a llista
  de taules (`[[general]]`); seqüències d'escapament a la clau; CRLF; un fitxer no buit sense salt de línia final; una marca
  d'ordre de bytes (BOM); textos de diverses línies (`"""` o `'''`); i un enllaç, també trencat.
- **Salvaguardes d'escriptura,** les d'abans: el fitxer ha de ser encara el que s'ha llegit, el temporal és al mateix volum, i
  es mantenen els permisos i els atributs estesos. La lectura és amb `String(validating:as:)`: `String(data:encoding:)` treia
  la marca d'ordre de bytes, i en canviar la línia es perdia (`fets-verificats.md`). Des de la 0.31.3, també l'escriptura
  prudent (a sota).

**Escriptura prudent (0.31.3).** Warp buida `settings.toml` i l'escriu sencer a cada canvi d'un ajust (`fets-verificats.md`,
«Com escriu Warp `settings.toml`»): una lectura en aquell moment el pot veure buit o a mitges, i escriure a partir d'aquí en
perdria els altres ajustos.
- **Si ha canviat fa menys de 2 s** (`segonsRecent`, per la data de modificació presa després de llegir-lo; també buit), no se
  n'analitza res ni s'hi escriu res: `posa` torna `.mesTard` i `valor()`, `nil`. Des de la 0.31.4 (ronda 6, decisió 2), «recent»
  vol dir de 2 s enrere a 2 s endavant: abans, qualsevol data del futur hi comptava, i un rellotge que anava enrere bloquejava
  l'app, sense avís, fins que l'hora tornava a passar aquella data. No és cap error
  (`Refusat`), sinó «torna-ho a provar més tard». Un fitxer buit amb una data antiga és buit de debò, i s'hi escriu la taula.
- **Just abans del `rename`,** a més del contingut, la mida, la data i l'inode han de ser els de la lectura; si no, `.mesTard`.
  Si Warp crea el fitxer mentrestant (`EEXIST`), també. Abans, tots dos casos eren un error.
- **El que acaba d'escriure l'app no compta com a recent:** l'ajust recorda el fitxer que ha posat (el mateix `stat` i el
  mateix contingut). Sense això, el final d'un refresc i la sortida no podrien tornar a desactivar l'ajust abans de 2 s. Si
  després hi escriu Warp, encara que sigui el mateix text, ja no és seu.
- **El rellotge s'injecta** (`rellotge:`): les proves no esperen mai, i l'app fa servir el de sèrie (guarda).
- **`Preferencies.posaRestauracio`,** amb `nil`, torna `.mesTard` sense desar res: no es desa com a valor d'abans el d'un
  fitxer buit o a mitges.
- **`RefrescWarp`:** la vigilància de cada minut no fa res, i ho torna a provar al minut següent (`desactivacioPendent`). Si fa
  més de 5 minuts seguits (0.31.4, ronda 6, decisió 3), el menú de la icona ho diu, amb el triangle (`avisNoParaDeCanviar`): «El
  fitxer d'ajustos de Warp no para de canviar, i Warp Launch no hi pot desactivar la restauració de sessió. Ho continua provant
  cada minut.» Com que la vigilància és de cada minut, surt entre els 5 i els 6. Compten tant les vegades que no s'hi pot escriure
  com les que no se'n sap el valor (`Pendent.acabaDeCanviar`; si no se sap, no s'hi escriu res). Es compta amb el Mac despert
  (`segonsDespert`, `systemUptime`): un Mac que dorm no avisa a la primera, i un rellotge que va enrere no ho endarrereix. Si
  entremig s'ha pogut, el compte torna a començar, i quan es pot desactivar, l'avís marxa.
  Al final d'un refresc, abans d'engegar Warp (`tancaEsperant`) i en sortir de l'app, ho torna a provar cada segon, fins a 3
  cops (`acabaDeDesactivar`, `segonsTornaAProvar`); en sortir, l'app respon `terminateLater` i surt quan acaba. Si l'activació
  d'un refresc és «més tard», no activa res: llegeix el que hi ha, i la lectura diu si la foto pot ser antiga.
- **«Restaura Warp i surt…»,** si és «més tard», no surt i diu «… acaba de canviar (torna-ho a provar d'aquí a uns segons)». Si,
  en desfer, l'ajust queda pendent de desactivar, el missatge ja no diu que torna a estar desactivat.

**El fitxer nou, només amb Warp obert (0.31.3, ronda 5).** En arrencar, si `settings.toml` no hi és, Warp hi passa una sola
vegada els ajustos de les preferències de macOS; si el fitxer ja hi és, se la salta, i aquells ajustos deixen de comptar
(`fets-verificats.md`). Per això en David va decidir que l'app només el crea amb Warp obert.
- **`AjustRestauracio`** rep `potCrearElFitxer` (per omissió, «no») i el pregunta dins de `crea`: després de llegir que el fitxer
  no hi és i de comprovar la carpeta i el volum, just abans de preparar-lo; mai si el fitxer ja hi és. Si no es pot, torna
  `.quanSObriWarp`, que no és cap error. Afegir la línia o la taula a un fitxer que ja hi és no en depèn: també amb Warp tancat.
- **Què vol dir «obert»** (`FontProcessos.warpHaAcabatDArrencar`, que l'app hi passa per `Lector.warpHaAcabatDArrencar`): l'app
  de Warp sense arguments, un `terminal-server` fill seu i almenys un terminal d'aquest `terminal-server`. Warp crea el
  `terminal-server` abans de la migració, i els terminals, després (`fets-verificats.md`): el `terminal-server` sol no serveix.
  Warp obert sense cap finestra no compta, però tampoc no té res per restaurar. Un primer intent, 30 s des que Warp s'havia
  obert (per l'hora d'arrencada del procés), es va substituir per aquest criteri: un rellotge no diu si Warp ja ha fet la
  migració.
- **`RefrescWarp`:** queda pendent sense avís (`Pendent.quanSObriWarp`), i la vigilància de cada minut el crea quan es pot; no es
  torna a provar cada segon, que no serviria. El menú de la icona hi posa una nota, amb la icona d'informació i no la d'avís
  (`notaSenseFitxer`; `pendent` s'observa): «Warp encara no té fitxer d'ajustos. Quan Warp sigui obert amb alguna pestanya, Warp
  Launch hi desactivarà la restauració de sessió en menys d'un minut.»
- **Amb Warp tancat,** ni la vigilància, ni sortir de l'app, ni engegar Warp no creen el fitxer: Warp arrenca amb la
  restauració de sèrie, activada, i pot tornar a obrir les finestres d'abans, sense Claude. Els fulls d'«Obre a Warp…» i
  «Obre-ho tot…» ho diuen («Warp també restaurarà les finestres d'abans, sense Claude.», en lloc de «Warp obre també una
  finestra buida»; `RefrescWarp.warpRestauraEnArrencar`; el text és a `Obertura.textWarpTancat` des de la 0.31.4), i el resultat
  no parla de cap finestra buida. No es demana d'obrir Warp primer, perquè no ho evita (ronda 6, decisió 1).
- **«Restaura Warp i surt…»** sense el fitxer no escriu res si ha de posar `true` (ja ho és). Si ha de posar `false` (el valor
  d'abans) i ara no es pot crear, no surt i diu que cal obrir Warp i tornar-ho a provar (`QuanSObriWarp`).
- **`scripts/warp-restauracio.sh`** no crea mai el fitxer, tampoc si Warp l'esborra mentre l'script el canvia (prova nova a
  `ScriptRestauracioTests`).

**Els altres llocs:**
- `LectorAjustosWarp`, `EstatWarp` i `warpDesaFinestres` ja comptaven la línia que falta com a activada; no canvien.
- El diagnòstic (comprovació g) i la pantalla del permís ho diuen (a dalt, «Diagnòstic» i «Consentiment de la restauració»).
- **`scripts/warp-restauracio.sh`** no l'afegeix mai. Sense la línia o sense el fitxer, `estat` diu «restore_session: activat
  (de sèrie, sense la línia)» (o «sense el fitxer»), amb el codi 0; `activa` diu que ja és activat, amb 0 (abans, sense el
  fitxer, 1); `desactiva` surt amb un error clar i el codi 1. Cap escriptura nova. `WARP_SETTINGS` buida es refusa d'entrada.

**Guarda** (secció 3, «Prova de guarda»): les crides que creen, enllacen o copien un fitxer d'un sol cop, i el ganxo de les
proves, només a `AjustRestauracio.swift`; `O_CREAT`, només on ja era; l'ajust no crea carpetes ni obre res per escriure-hi
directament; i la ruta de debò de `settings.toml`, en 5 línies fixes. Des de la 0.31.3: un sol `rename(`, cap altra manera
d'esborrar, de crear o de canviar atributs, i la línia de l'app fixa, amb `potCrearElFitxer` i el rellotge de sèrie.

**Proves:** `AjustRestauracioTests` (d'11 a 22 proves, algunes amb diversos casos), `ScriptRestauracioTests`,
`DiagnosticTests`, `RefrescWarpTests` i `DesinstallacioTests` (amb l'ajust de debò sobre un `settings.toml` d'una carpeta
temporal, connectat com a l'app), i la guarda. La revisió va corregir dues proves que feien servir `/dev` com a carpeta
temporal i passaven també sense la comprovació del volum: ara miren l'error exacte. Cada salvaguarda es va treure una per una,
i alguna prova falla. **0.31.3:** `AjustRestauracioTests` passa a 33 (els 2 s, el `stat` abans del `rename`, el fitxer propi,
crear-lo només quan es pot i afegir-hi la línia també amb Warp tancat), `RefrescWarpTests` a 36, `DesinstallacioTests` a 27
(amb `SenseLiniaTests`, l'ajust de debò sobre un fitxer temporal: ni la vigilància ni sortir no el creen amb Warp tancat o
sense terminals), `AppWarpTests` a 25 (quan ha acabat d'arrencar Warp), `OberturaTests` a 60 (els dos fulls sense el fitxer) i
`PreferenciesTests` a 20. Les mutacions de les dues revisions (sense els 2 s, sense el `stat`, sense el fitxer propi, crear
sempre, comptar només el `terminal-server`, no mirar-ne el pare, sense els reintents, i més) fan fallar alguna prova.
**0.31.4 (ronda 6):** `AjustRestauracioTests` es queda a 33 (la finestra de «recent», a 1,9 s i 2,1 s a banda i banda),
`RefrescWarpTests` passa a 43, `DesinstallacioTests` a 28 i `OberturaTests` a 62. Les mutacions (sense `abs`, 10 s cap endavant,
el compte que comença a cada vegada o que no es reinicia, `>=` en lloc de `>`, no comptar si no se sap el valor, sense el `catch` de
`warpMaiObert`, refusar `warpSenseBase` en obrir) fan fallar alguna prova.

**Per confirmar (en David):**
- Amb `[general.x]` sola, la taula s'afegeix abans de la primera subtaula, no al final.
- Sense `~/.warp`, `valor()` torna `true` (no refusa), perquè la desinstal·lació no falli; qui refusa és `posa(false)`.
- Es refusen una clau `general` a qualsevol taula, els textos de diverses línies i la marca d'ordre de bytes, encara que hi
  hagi falsos positius: en aquests casos, l'app no desactiva la restauració, i el diagnòstic ho diu com a error.
- Amb l'script, `activa` sense el fitxer ara surt amb 0.
- Amb un `settings.toml` que és un enllaç, el diagnòstic diu error encara que hi hagi la línia (a dalt, «Diagnòstic»).
- L'avís dels 5 minuts (ronda 6, decisió 3) pot sortir encara que l'ajust ja fos desactivat: mentre el fitxer canvia, l'app no
  ho pot saber. El text no diu que Warp restaurarà res.

**Riscos i el que no se sap:**
- **Com escriu Warp `settings.toml`: resolt al codi** (llegit, no vist): el buida i l'escriu sencer. La 0.31.3 no hi escriu si
  ha canviat fa menys de 2 s, i abans del `rename` en compara el `stat` i el contingut. Queda un interval de microsegons entre
  l'última comparació i el `rename`: si Warp hi escriu just llavors, no es veu. Sense un bloqueig de Warp no es pot tancar.
- **Quin lector de TOML fa servir Warp:** no s'ha verificat.
- Amb la línia, l'anàlisi no refusa els textos de diverses línies (afegir-la, sí): un text fet a propòsit podria fer creure que
  la línia és a `[general]` sense ser-ho. Ja hi era abans; no s'ha endurit perquè, si un fitxer real en té, l'app deixaria de
  poder desactivar la restauració.
- **Mentre no hi ha el fitxer, la restauració de Warp és activada** (la de sèrie), sense avís al menú (només la nota i el
  diagnòstic): si l'usuari obre Warp abans que l'app hagi pogut crear el fitxer, Warp restaura les seves finestres, sense
  Claude. També quan és l'app qui engega Warp. És la conseqüència acceptada de la ronda 5.
- **El criteri del terminal surt del codi de `master`** (llegit, no vist a la versió instal·lada): es comprova en un usuari de
  macOS nou. Si el `terminal-server` falla i Warp obre els shells directament, l'app no veu cap terminal i no crea mai el
  fitxer (`fets-verificats.md`).
- **L'onboarding d'un usuari nou** potser ja escriu `settings.toml` (`fets-verificats.md`): llavors l'app només hi afegiria la
  línia, i la nota de Warp mai obert podria no ser certa un cop s'ha obert Warp. Es mira en un usuari de macOS nou.
- Petits: «en menys d'un minut» és, de fet, 60 s més el que triga la lectura; sense `~/.warp` o sense el fitxer, el registre
  de l'app anota una nota cada minut (sense el fitxer, «l'ajust era activat fora d'un refresc: es desactiva»); amb la
  configuració de debò en un Mac sense Warp, l'app no crea res (no hi ha `~/.warp`, ni cap Warp obert).

**Per decidir (0.31.3, en David):**
- Si l'app no pot desactivar l'ajust per un altre motiu (hi ha un avís al menú), el full amb Warp tancat encara parla de la
  finestra buida (ja hi era). Es podria fer servir el mateix criteri.
- Cas rar: si no es pot retirar el permís i `settings.toml` acabava de canviar, el missatge diu «ha quedat activat» encara que
  «Restaura Warp i surt…» no l'hagués activat.
- `scripts/warp-restauracio.sh` no té l'escriptura prudent (s'executa a mà, amb l'OK d'en David), i el diagnòstic llegeix sense
  la regla dels 2 s (no escriu res, però mentre Warp escriu pot donar un resultat equivocat).

### Guardes (08/11/2026, sense versió)

Dos forats de `GuardaTests`, tancats sense canviar el que fa l'app (secció 3, «Prova de guarda»):
- **Els noms amb mòdul:** cap expressió no fa servir `\b`, que no veia `Foundation.Process()`, `Darwin.kill(`,
  `NSApp.terminate(nil)`, `self.estat =` ni `SMAppService.mainApp.register()` (la guarda dels ítems d'inici rebia una llista buida
  i la donava per bona). La revisió hi va afegir `Process` i `kill` com a paraula sencera, la família `exec` i les `NSUser…Task`
  al codi, i, a les proves, la carpeta d'inici de debò per qualsevol camí (`iniciDeDebo`).
- **La carpeta de les sessions:** `Lector(carpetaSessions:)` i `LectorSessions(carpeta:processos:)` ja no tenen valor per
  defecte; l'app i el CLI hi posen el de sempre. Qualsevol `carpetaPerDefecte` de `Sources/` és en una llista fixa.
- **Després de la 0.31.2 (segona ronda, sense canviar el que fa l'app):**
  - **La carpeta de Warp i el diagnòstic** tampoc no poden esborrar, moure, crear, sobreescriure ni enllaçar per cap altra crida
    (`altresEsborrenOMouen` i `altresCreenOSobreescriuen`; la llista, a la secció 7, «Seguretat»). `remove` de C es distingeix
    de `llista.remove(at:)` pel punt davant: un mètode sempre en té un, i la funció no en porta cap o porta el mòdul
    (`Darwin.remove(`).
  - **`settings.toml`:** `copyfile`, `linkItem` i `createSymbolicLink`, com `link`, `symlink` i `clonefile`, només a
    `AjustRestauracio.swift`, que tampoc no pot obrir `settings.toml` per escriure-hi directament (`escriuenDirectament`): si
    l'app s'aturés a mig escriure, el deixaria a mitges.
  - **Els lectors de Claude de debò** (`~/.claude/projects` i `~/.claude.json`) només els creen l'app i el CLI
    (`lectorsDeClaudeDeDebo`), també amb `.init()` o amb les rutes per defecte; a les proves, mai sense ruta.
  - Cada arreglament té la seva mostra, i es va comprovar que la guarda d'abans passava amb una línia dolenta al fitxer real.
- **Tercera ronda (08/11/2026, després de la 0.31.3; l'app fa el mateix):**
  - **Els lectors de Claude ja no tenen ruta per defecte** (`LectorTranscripcions.init(carpeta:)`, `LectorConfianca.init(ruta:)`):
    l'app i el CLI hi posen la de debò, i l'app en crea un de cada, al costat del `Lector`, per al diagnòstic, per obrir a Warp i
    per a la conversa de cada pestanya. Una prova que se l'oblidi no compila. La guarda fixa les declaracions dels `init` i dels
    tipus, i, sense dir el nom del tipus, `.init(carpeta:` i `.init(ruta:` a tot `Sources/` (la revisió hi va trobar un forat:
    `confianca: .init()` amb una extensió partida en dues línies compilava i passava).
  - **Permisos i atributs, i altres maneres d'obrir, crear o escriure** a la carpeta de Warp, al diagnòstic i a l'ajust
    (`altresCanvienAtributs`, `altresObrenOCreen`, el `write` de C), amb l'única excepció del `fchmod` de `FitxersLaunchWarp`,
    al seu lloc. A l'ajust, un sol `rename(` i cap altra manera d'esborrar ni de moure (secció 3).
  - **A les proves, `Lector.init(`** i un `.init(` sense el nom del tipus amb una etiqueta del `Lector` havien de portar les dues
    rutes de prova, perquè `Lector`, `LectorWarp` i `LectorAjustosWarp` encara tenien les de Warp de debò per defecte. Des de la
    quarta ronda, no les tenen, i aquestes guardes ja no hi són.
  - Cada forat es va provar amb el canvi dolent de debò (a `Sources/` o en un fitxer de prova temporal): compilava, la guarda
    d'abans passava i la nova falla.
- **Quarta ronda (ronda 6, decisió 7; 0.31.4, l'app fa el mateix):**
  - **Els lectors de Warp ja no tenen cap valor per defecte** (`LectorWarp(ruta:)`, `LectorAjustosWarp(ruta:)` i tots els paràmetres
    de `Lector`, també `inici`): l'app i el CLI hi escriuen les rutes de debò, les mateixes d'abans, i una prova que se n'oblidi
    una no compila. Les expressions de les proves que això fa innecessàries s'han tret. La guarda (`lectorsDeWarpDeDebo`, secció 3)
    és la dels lectors de Claude (`lectorsDeDebo`, comuna).
  - **Permisos i atributs de fitxers, a tot `Sources/`** (`canvienAtributsForaDeLloc`, secció 3): només dues crides a `fchmod`.
  - La revisió hi va trobar un forat: `LectorWarp (ruta: r)`, amb un espai davant del parèntesi, compilava i la guarda no el veia,
    tampoc per als de Claude. Ara hi compta.
  - Cada guarda nova o canviada falla amb les mostres dolentes i amb mutacions temporals de `Sources/`.
- **Per decidir:**
  - Límits que queden: `lectorsDeDebo` (les guardes dels lectors de Claude i de Warp) mira les línies una per una, i no veu un
    valor per defecte amb una línia en blanc pel mig; `carpeta` i `ruta` dels lectors de Claude, i `ruta` i `rutaWarp` dels de
    Warp, són `public var` (`var t = x; t.carpeta = …`; tancar-ho demanaria fer-les `let`, però cap camí no arriba a la ruta de
    debò sense escriure un nom que ja és prohibit o fixat); unes quantes crides poc habituals que escriuen (`fdopen` i `fwrite`, `CFWriteStreamOpen`) no hi són, però abans
    necessiten una crida que les guardes ja paren. Avui no n'hi ha cap cas.
  - A les proves, la ruta escrita `.claude/sessions` no és prohibida (`DiagnosticTests` la fa servir en una carpeta temporal). Les
    guardes de les proves que prohibeixen crear els lectors de Claude sense ruta (`lectorTranscripcions`, `lectorConfianca`) es
    queden, encara que ara no compilaria, per no afluixar res; les equivalents de Warp ja s'han tret (quarta ronda).
  - Valors per defecte que queden i no són rutes de Warp ni de Claude: `AjustRestauracio(carpetaTemporal:)`, la carpeta temporal
    del sistema; `sistema:` a `EntornCLI` i `EntornDiagnostic`, la versió de macOS; i `carpetaExisteix:` a `EntornCLI`, `Editor` i
    `Obertura`, que només mira al disc les rutes que li passen.

### Per provar a l'app (de la 0.30.3 a la 0.31.4)

Cada prova, amb l'OK d'en David. En David ha provat la 0.31.4 a l'app el 09/11/2026 (ho ha dit ell), sense anotar punt per
punt què s'hi ha vist: la llista queda com a guia. Si no es diu el contrari, amb `--config` i una carpeta nova buida. Del 14 al 18, el 20 i el 21, amb la configuració de debò i Warp obert, i abans i després de cada pas,
`scripts/warp-restauracio.sh estat` (només llegeix).
1. **Retorn i Escapada (0.30.3):** a la pantalla del permís, Escapada no fa res; Retorn accepta, crea `preferencies.json` i
   passa a l'editor. A la Configuració (⌘,), igual: si Escapada la tanqués, l'app sortiria (les proves no ho poden veure).
2. **Tancar la Configuració (0.30.3),** amb una altra carpeta nova: amb la pantalla del permís, l'app surt i no hi ha
   `preferencies.json`; amb el permís acceptat, l'app continua.
3. **Importar amb la carpeta de prova (0.30.3):** amb la restauració desactivada, «Importa de Warp…» diu per què no hi ha
   finestres i acaba amb «Comença en blanc»; després de «Comença en blanc», «Torna a importar-ho tot de Warp…» diu el mateix i
   acaba amb «La configuració no canvia.». La decisió 9 no es pot veure amb una carpeta de prova (cap finestra per importar): la
   cobreixen les proves.
4. **Pestanyes noves (0.30.3):** la primera secció no té títol, i el peu hi és.
5. **Diagnòstic (0.30.3):** Configuració › General › «Copia el diagnòstic complet»: amb una versió de Claude Code fora de les
   provades, la línia la diu un sol cop.
6. **Deixar de fer servir l'app (0.31.0):** amb una carpeta de prova amb el permís, el botó és desactivat i el peu diu per què;
   la pestanya General no passa de 640 pt i el peu es veu sencer. Amb la configuració de debò, només mirar: la fila diu com
   quedarà l'ajust, la confirmació surt un sol cop i ho repeteix (amb Settings Sync), i Retorn i Escapada la cancel·len. Provar-ho
   de debò deixa `restore_session` activat (si Warp es reinicia, restaura les pestanyes sense Claude): es comprova amb
   `scripts/warp-restauracio.sh estat` i a `preferencies.json` («retirat»), i es desfà tornant a obrir l'app i acceptant (i, si
   hi era, tornant a activar l'interruptor de l'inici de sessió).
7. **Dues còpies de Warp (0.31.1):** en David tanca Warp (es tancarien els Claude que hi corren, regla 2), en fa una còpia a
   Descàrregues i obre aquella. «Actualitza l'estat de Warp» diu que Warp és obert, amb els seus terminals; «Obre a Warp…» d'una finestra
   d'1 pestanya sense Claude l'obre en aquella còpia, amb un sol Warp al Monitor d'Activitat i la seva versió al full. El mateix
   amb un Warp baixat (amb la quarantena) obert des de Descàrregues sense moure'l (App Translocation). En acabar, esborrar la
   còpia: si no, macOS la podria triar més endavant.
8. **Sense cap Warp (0.31.1),** en un Mac sense Warp (un usuari de macOS nou en un Mac amb Warp a `/Applications` no serveix:
   també el veu): «Obre a Warp…» i «Obre-ho tot a Warp…» diuen «No s'ha trobat Warp en aquest Mac: cal Warp Stable.» sense
   proposar obrir res; `llegeix` i `obre <finestra>` diuen el mateix i surten amb 1. Amb la 0.31.2, el mateix també amb
   `--config`; importar diu aquest text i «No hi ha res per importar…», lligar només aquest text, el menú «Warp: 0 terminals ·
   0 sessions de Claude», i enlloc no surt «no trobo la base de Warp». No es mou ni s'esborra el Warp que corre (regla 2).
9. **Guardes (08/11/2026):** l'app passa al lector la mateixa carpeta de sessions que abans; la llista continua marcant les
   pestanyes amb una sessió de Claude.
10. **Lligar amb una carpeta de prova (0.31.2),** amb una configuració amb pestanyes, Warp obert i la restauració desactivada:
    Fitxer › «Lliga amb Warp…» diu «Warp no desa les finestres… Amb una configuració de prova (--config), l'app no toca aquest
    ajust i no pot demanar a Warp que les desi. Amb la configuració de debò, sí: …», i «No s'ha desat res.» (cap `estat.json`
    nou). «Torna a importar-ho tot de Warp…» diu el mateix motiu, seguit de «La configuració no canvia.», com a la 0.31.1.
11. **La pantalla del permís (0.31.2):** la frase nova de «Què canvia» es veu sencera dins dels 560 pt.
12. **Al Mac d'en David, res no canvia (0.31.2):** `settings.toml` ja té la línia. `scripts/warp-restauracio.sh estat` (només
    llegeix) continua dient `restore_session = false (línia N)`, el menú no té cap avís nou, i Configuració › «Copia el
    diagnòstic complet» diu, a la comprovació g, «restore_session = false (Warp doesn't restore its own windows).», com abans.
13. **Guardes de després de la 0.31.2:** res a veure a l'app; només canvien les proves.
14. **Al Mac d'en David, res no canvia (0.31.3):** `estat` continua dient `restore_session = false (línia N)`, el menú no té cap
    avís ni cap nota nova, i la comprovació g del diagnòstic diu el mateix que al punt 12.
15. **«Actualitza l'estat de Warp» i, abans d'1 o 2 s, ⌘Q:** l'app surt de seguida, o com a molt en 3 s, i `estat` diu `false` (el
    que acaba d'escriure l'app no la bloqueja).
16. **Canviar un ajust a Warp (per exemple, el tema) i, en menys de 2 s, «Actualitza l'estat de Warp»:** cap avís al menú (com a molt,
    el de la foto antiga); el registre (`/usr/bin/log show --last 5m --predicate 'subsystem == "cat.davide.warp-launch"'`) diu
    «aquest refresc no activa l'ajust»; `estat` diu `false` i el tema nou s'ha conservat. Passats uns segons, torna a anar bé.
17. **Canviar un ajust a Warp i, en menys de 2 s, ⌘Q a Warp Launch:** l'app pot trigar fins a 3 s a sortir; després, `estat`
    diu `false` i el tema nou s'ha conservat. Si no surt en uns segons, és el camí nou de `terminateLater`.
18. **Amb Warp tancat (el tanca en David, regla 2), «Obre a Warp…»:** Warp s'obre com sempre (com a molt, 3 s més tard), sense
    restaurar les seves finestres, i `estat` diu `false`. El full continua dient «En arrencar, Warp obre també una finestra
    buida…», perquè hi ha `settings.toml`.
19. **Els lectors de Claude (guardes de després de la 0.31.3):** «Copia el diagnòstic» dona el mateix per a Claude Code,
    l'inspector mostra la mateixa conversa a reprendre, i el full d'«Obre a Warp…» la mateixa conversa i el mateix avís de
    confiança que abans. Cancel·lar sense obrir res.
20. **Els lectors de Warp (0.31.4, ronda 6, decisió 7; sense efecte visible):** el menú de la icona i «Actualitza l'estat de Warp»
    mostren les mateixes finestres i pestanyes que abans, i Configuració › General › «Copia el diagnòstic» surt igual, amb les
    rutes de Warp i de Claude correctes. `warp-launch llegeix` (només lectura) dona el mateix que abans.
21. **Al Mac d'en David, res no canvia (0.31.4):** `estat` continua dient `restore_session = false (línia N)`, i el menú no té
    cap avís ni cap nota nova. Les decisions 1, 2 i 6 de la ronda 6 no canvien res visible (la 2 demanaria tocar el rellotge del
    Mac): les cobreixen les proves. La 3, la 4 i la 5 es veuen en un usuari de macOS nou (a sota).

### Per provar en un usuari de macOS nou (0.31.2, decisió A; 0.31.3, ronda 5; 0.31.4, ronda 6)

En David ho ha provat amb la 0.31.4 el 09/11/2026 (ho ha dit ell), sense anotar pas per pas què s'hi ha vist: la llista queda
com a guia. Cada pas, amb l'OK d'en David, i amb un usuari de macOS que no ha obert mai Warp. Serveix també per comprovar el que s'ha llegit
al codi de Warp i no s'ha vist (`fets-verificats.md`): què escriu un Warp net (també l'onboarding), quan crea la base i que la
migració es fa abans del primer terminal. L'ordre compta.
1. **Warp instal·lat, sense obrir-lo:** Warp Stable a `/Applications` (un Mac on ja hi és serveix: tots els usuaris el veuen),
   sense obrir-lo mai en aquest usuari.
2. **No hi ha res de Warp:** `ls -la ~/.warp ~/.warp/settings.toml` diu que no hi són.
3. **Obrir Warp Launch amb la configuració de debò i acceptar el permís, amb Warp tancat: no ha de crear res.** Uns minuts
   després, encara no hi ha `~/.warp` ni `settings.toml`. A l'app:
   - el menú de la icona diu la nota de Warp mai obert («Warp encara no s'ha obert mai…», amb la icona d'informació i sense el
     triangle; ronda 6, decisió 5) i «Warp: 0 terminals · 0 sessions de Claude», també passat un minut;
   - Configuració › «Copia el diagnòstic complet», comprovació g: «… doesn't exist: Warp hasn't been opened yet for this user,
     and has no windows to restore», i que Warp Launch no crea la carpeta;
   - «Importa de Warp…» diu «Warp encara no ha desat cap finestra en aquest usuari: obre'l un cop i torna-ho a provar. Si no,
     tria «Comença en blanc» i afegeix-hi les pestanyes.», sense «No s'ha pogut llegir Warp»; «Lliga amb Warp…» (després de
     «Comença en blanc» i una pestanya), el mateix text i «No s'ha desat res.»;
   - al CLI (amb l'OK d'en David), `warp-launch llegeix` i `warp-launch importa` diuen el mateix text i surten amb 1.
4. **Obrir Warp amb una pestanya,** sense tocar-ne la restauració, i passar l'onboarding si en surt. De seguida, abans que
   passi un minut: mirar si hi ha `warp.sqlite` (segons el codi, des de l'arrencada) i si Warp ha creat `~/.warp`,
   `settings.toml` o `tab_configs/startup_config.toml` pel seu compte, i copiar què hi ha escrit. Si encara no hi ha `warp.sqlite`,
   «Importa de Warp…» diu «Warp encara no ha desat cap finestra en aquest usuari: si Warp s'acaba d'obrir, torna-ho a provar d'aquí a
   uns segons.» (ronda 6, decisió 4). En menys d'un minut, la nota de Warp mai obert marxa. Mentre no hi ha `settings.toml`,
   el menú diu la nota «Warp encara no té fitxer d'ajustos…» (icona d'informació, sense avís), i la comprovació g, «Warp is open
   now, with a terminal.» (o «with no terminal yet», si encara no n'hi ha cap).
5. **En menys d'un minut, `settings.toml` hi és amb la línia:** `scripts/warp-restauracio.sh estat` diu `restore_session = false
   (línia N)`. Si Warp no l'havia creat, només hi ha `[general]` i la línia; si l'havia creat, hi ha la línia (o la taula) nova
   i tota la resta del que hi havia escrit Warp, igual que al pas 4. La nota del menú marxa. A Settings de Warp, «Restore
   windows, tabs, and panes on startup» surt desactivat sense reiniciar Warp (Warp llegeix l'ajust en calent,
   `fets-verificats.md`, 05/11/2026), i la resta d'ajustos no canvien. Si Warp hi havia escrit subtaules `[general.x]`, textos de
   diverses línies o una marca d'ordre de bytes, l'app no hi afegeix la línia, i el diagnòstic ho diu com a error.
6. **«Restaura Warp i surt…»:** `estat` diu `restore_session = true` (la línia es queda), `preferencies.json` diu «retirat», i
   l'app es tanca sense cap error.
7. **Opcional, el full d'obrir sense `settings.toml`:** si al pas 4 Warp crea `~/.warp` però no `settings.toml`, i en David el
   tanca abans del minut, el full d'«Obre a Warp…» d'una finestra petita de prova (abans, dir quantes pestanyes i quants Claude
   obriria) diu «Warp és tancat: l'app l'obrirà abans. Warp també restaurarà les finestres d'abans, sense Claude.», sense la
   frase de la finestra buida; el mateix amb «Obre-ho tot…». No cal confirmar-lo.
8. **Opcional, amb Warp Preview:** amb Preview obert i un Warp Stable que encara no s'ha obert en aquell usuari, importar i
   lligar diuen «Warp Preview encara no és compatible: cal Warp Stable. Ara és obert Warp Preview, i Warp Stable no: obre Warp
   Stable i torna-ho a provar.», i `warp-launch llegeix` també, amb el codi 1.
9. **Si `settings.toml` no para de canviar (0.31.4, ronda 6, decisió 3),** només en aquest usuari de prova (regla 7: mai a
   l'usuari d'en David), amb Warp obert i el permís acceptat (després del pas 6, tornar a obrir Warp Launch i acceptar): en un
   terminal, `while true; do touch ~/.warp/settings.toml; sleep 1; done`. Entre els 5 i els 6 minuts, el menú de la icona diu «El
   fitxer d'ajustos de Warp no para de canviar…», amb el triangle. No cal clicar «Actualitza l'estat de Warp». Atura el bucle: en menys
   d'un minut l'avís marxa, i `scripts/warp-restauracio.sh estat` diu `restore_session = false (línia N)`.

### Homebrew (09/11/2026)

Decisió: `especificacio.md`, fila del 09/11/2026. El que s'ha llegit i provat de Homebrew: `fets-verificats.md`, «Homebrew».

- **El tap:** el repo públic `David-Erra/homebrew-tap`, amb `Casks/warp-launch.rb`, `README.md` i `LICENSE`. S'instal·la amb
  `brew install --cask david-erra/tap/warp-launch`, s'actualitza amb `brew upgrade --cask warp-launch` i es treu amb
  `brew uninstall --cask warp-launch`.
- **La recepta:**
  - El zip de la versió de GitHub, amb `#{version}` a la URL (`v#{version}/WarpLaunch-#{version}.zip`). Apple Silicon i, com a
    mínim, macOS 26.
  - Després de copiar l'app, un pas de `postflight_steps` li treu la quarantena (`xattr -dr com.apple.quarantine`): no és
    notaritzada i, sense això, macOS no la deixaria obrir.
  - `uninstall quit:` tanca l'app si és oberta, en actualitzar i en desinstal·lar.
  - `zap` només esborra les preferències i l'estat de les finestres que desa macOS, mai `~/.config/warp-launch`.
  - L'avís de la recepta diu de fer «Restaura Warp i surt…» abans de desinstal·lar: Homebrew no ho pot fer per l'usuari.
- **Com s'actualitza:** a cada versió publicada, `scripts/publica.sh` (regla 3).
  - Abans de compilar, llegeix la recepta del tap amb un sol GET (el contingut i el sha del blob). Refusa publicar si no s'hi
    arriba, si el sha de git del que ha descodificat no és el que diu GitHub, si no té exactament una línia `  version "X.Y.Z"`,
    una `  sha256 "…"` i la `  url` amb `#{version}`, si ja va per davant de `VERSION`, o si falten `git config user.name` o
    `user.email`.
  - El mode de prova diu la versió i el sha256 d'abans i de després, i no escriu res.
  - Amb `--aplica`, després de `gh release create`, un `gh api --method PUT` amb el sha del blob llegit: si la recepta ha canviat
    mentrestant, GitHub refusa l'escriptura. Només canvien les dues línies, i el sha256 és el del zip pujat. Si la recepta ja diu
    això mateix, no escriu res.
  - Si l'escriptura falla, la versió no s'esborra: l'script diu les dues línies per canviar a mà i surt amb el codi 2.
  - Es desfà en aquest ordre, perquè Homebrew no demani un zip que ja no hi és: `git revert <commit>` en un clon del tap, i push;
    després, `gh release delete vX.Y.Z --repo David-Erra/warp-launch --cleanup-tag`.
  - `GH_TOKEN` d'un compte que pugui escriure al repo i al tap, només per a aquesta ordre; la compilació no el veu. Proves:
    `ScriptPublicaTests`, amb un `gh` fals.
- **Provat de debò (09/11/2026, amb la 0.31.5):** en David va executar l'script al seu terminal, i el `PUT` va escriure la recepta (commit `cd8c304` del tap: només
  les dues línies, i el sha256 és el `digest` que GitHub dona del zip). És la primera que ha escrit l'script: la de la 0.31.4 es va escriure en crear el tap. La crida del
  `PUT` i el contingut que envia no han canviat a la 0.32.7. `fets-verificats.md`, «Homebrew».
- **Què falta:**
  - **Contra GitHub de debò, encara sense provar:** un `PUT` refusat perquè la recepta ha canviat mentrestant (només amb el `gh` fals), i tot el que el `publica.sh` de la
    0.32.x hi afegeix abans i després (signar, `appcast.xml`, `--latest`, la comprovació final).
  - **Quan hi hagi notarització** (decisió 1 de la fila del 07/11/2026): treure de la recepta el pas de la quarantena, i les
    frases que l'expliquen al README d'aquí i al del tap.
  - **Amb Sparkle** (decisió 6 de la mateixa fila; a la recepta des de l'11/11/2026, commit `d9581af` del tap, pas 12 de la secció 11; `publica.sh` refusa sense): `auto_updates true` a la recepta. Així, `brew upgrade` només l'actualitza si la
    versió del paquet és més vella que la de la recepta, i no hi passa pel damunt quan Sparkle ja l'ha posada al dia (llegit a
    `cask/cask.rb` i `env_config.rb` de Homebrew).
  - **Sense provar:** obrir una app instal·lada amb Homebrew, i el pas de tancar-la i tornar-la a obrir en actualitzar.

### 0.31.5: les cinc decisions del 09/11/2026 (publicada el mateix dia)

**Vist a l'app amb Warp de debò el 09/11/2026 (un Mac): les proves 2, 3 i 5 de sota, aquesta només al full d'una finestra.** La resta és
provada amb dades fictícies (`scripts/test.sh`) o llegida al codi de Warp i a la documentació de Claude Code. Decisions: `especificacio.md`, fila del 09/11/2026. Fets:
`fets-verificats.md`, «La carpeta de la pestanya i la de Claude». Sense canvi de format: `estat.json` i `configuracio.json` són com a la 0.31.4.

- **Provat (dades fictícies):**
  - La carpeta que guanya, en cada combinació de Claude a `~`, inexistent o existent.
  - Warp a `~` i Claude en una carpeta que no existeix: `~`, sense Claude, amb les opcions de la seva ordre i la nota. També: les opcions passen pel JSON
    i tornen en activar-la, sense ordre de Claude mentre és desactivada (`OrdreClaude.argv`, no el pla d'obertura sencer); `~` amb barra final o per un enllaç, des de la
    lectura; les xifres del full i de «Torna a importar»; i que una sessió sense pestanya no la proposi com a seva.
  - L'avís a «Per revisar», que no surt a les pestanyes només terminal i no se'n va amb una foto de Warp sense cap Claude.
  - «Lliga amb Warp…» amb les dues carpetes, sense desfer empats i sense donar el mateix pane a dues pestanyes.
  - El pla d'obertura amb la carpeta del Claude del terminal.
  - Tornar a importar, a l'app i al CLI, i el text del full.
  - Crear la carpeta: un sol nivell, res si el camí o `~/.warp` són un enllaç o un fitxer, i només amb el permís acceptat o migrat.
  - L'avís de les feines als dos fulls, i `GuardaTests`.
- **Només llegit:**
  - `/cd` i `EnterWorktree` mouen la sessió.
  - Warp hauria de veure la carpeta `launch_configurations` creada amb ell obert.
  - Tancar Warp pot aturar les feines: observat una vegada, sense reproduir.
- **Limitació de l'avís:** la carpeta de Warp només és a la memòria de l'app. Després de reiniciar-la, l'avís només surt si l'última
  carpeta de Claude (`carpetaSessio`) no és la de la pestanya; una pestanya ja a la carpeta de Claude no avisa fins a la foto
  següent. Fer-lo del tot permanent demanaria un camp nou a `estat.json` (regla 11).
- **Les configuracions ja importades no canvien soles:** cal corregir la carpeta a l'inspector o tornar a importar-ho tot.

**Per provar a l'app** (cada prova, amb l'OK d'en David; regles 1 i 4). Amb carpetes temporals A i B. Amb una carpeta de configuració de
prova, l'app només llegeix les finestres si `restore_session` és activat: cal sortir de l'app instal·lada i activar-lo amb l'script (regla 7).
**Fetes el 09/11/2026:** la 2 (carpeta B, avís, i «Obre a Warp…» a B amb la mateixa conversa), la 3 (després d'un `/exit`, 70 amb Claude i 1
només terminal) i la 5 (al full d'una finestra). **Falten:** la 1, la 4, la 6 i l'avís a «Obre-ho tot».

1. Lectura, 0 finestres i 0 sessions: al Mac on es va veure el problema, per a cada pestanya on Warp i Claude difereixen, si el
   shell pare de Claude és a la carpeta de Claude (`warp-launch importa`, `lsof -a -d cwd -p <pid>`).
2. La carpeta, 1 finestra, 1 pestanya i 1 sessió de Claude: en David obre una pestanya a A i hi escriu `cd B && claude`, amb un missatge.
   Importar a una carpeta de configuració de prova ha de donar B i l'avís a «Per revisar». En David tanca la pestanya (regla 2), i
   «Obre a Warp…» l'ha d'obrir a B amb la mateixa conversa.
3. Tornar a importar, 0 finestres: les pestanyes sense Claude viu queden «Només terminal», i el full ho diu.
4. La carpeta de Warp, 1 finestra i 1 pestanya sense Claude: sense `~/.warp/launch_configurations`, amb Warp obert i la
   configuració de debò, «Obre a Warp…» la crea i Warp obre la finestra.
5. Els dos fulls d'obrir mostren l'avís de les feines en segon pla.
6. Warp a `~` i Claude sense carpeta, 1 finestra, 1 pestanya i 1 sessió de Claude: en David obre una pestanya a `~`, hi escriu
   `cd C && claude` (C, una carpeta temporal) i esborra C. Importar a una carpeta de configuració de prova ha de donar `~`, Claude
   desactivat amb les opcions de la seva ordre, i la nota.

### Resum

- Proves: de 443 a 627 al core i de 232 a 331 a la UI, totes bé (a la 0.31.1, 534 i 275; a la 0.31.2, 552 i 284; a la 0.31.3, 571
  i 313; a la 0.31.4, 573 i 323).
  `prototip/` surt del repo (és a l'historial, 114c97d).
- De les versions del lot, són publicades la 0.31.4 i la 0.31.5 (09/11/2026), i s'instal·len també amb Homebrew.
- De les vuit decisions del 07/11/2026, falten la signatura amb Developer ID (1), l'idioma (3; al llançament, anglès i català,
  decisió 7 del 08/11/2026), publicar Sparkle (6: al codi des de la 0.32.0 i publicat amb la 0.33.0 l'11/11/2026, secció 11) i l'excepció de la guarda per a la pàgina
  del permís (8). De les
  dotze de la fila del 08/11/2026, totes les que tocaven el codi són fetes (0.30.3, 0.31.0 i 0.31.1), menys l'idioma. De la
  ronda 4, la A és feta (0.31.2) i les quatre de B es queden com eren. La de la ronda 5, a la 0.31.3. De les set de la ronda 6, la
  2, la 3, la 4, la 5 i la 7, a la 0.31.4; la 1 i la 6 ja eren així.

## 11. Actualització automàtica amb Sparkle 2.10.1 (disseny del 09/11/2026)

Sobre la 0.31.4 (commit 7180f73). **Al codi des de la 0.32.0 (passos 0 a 10 de la secció 9), publicada amb la 0.33.0 (11/11/2026):** l'adreça i la clau són al repo des de la 0.33.0 (pas 11), i les còpies d'abans (0.31.5 o anteriors, la 0.31.5 publicada després de fer aquest disseny) necessiten una última actualització a mà.
**Vist funcionar només amb versions de prova,** un servidor local i una clau d'un sol ús: una app de prova a les rondes A i B, i la Warp Launch de debò, en part, a la C (apartat 8). Res amb
l'adreça i la clau de debò.

Dins d'aquesta secció, les remissions («secció 5», «2.3», «decisió 1») són internes. Les decisions numerades 1 a 13 són les de la taula de sota; el codi les cita
com «decisió N de Sparkle». Etiquetes: **[P]** provat, amb l'ordre i el resultat; **[L]** llegit, amb fitxer:línia; **[S]** suposat, i cada [S] diu on es comprova.
`SP/` és el codi de Sparkle a l'etiqueta 2.10.1 (commit ab7d712); `HB/`, `Library/Homebrew` de Homebrew 7.0.12. Rutes sense prefix: el repo, amb les línies de la 0.31.4.
Els fets, a `docs/fets-verificats.md`, «Sparkle».

**Fet (09/11/2026): els passos 0 a 10** (secció 9): els 1 a 4 i el 9, sense versió, i els 5 a 8, de la 0.32.0 a la 0.32.3, amb dues revisions (0.32.4 i 0.32.5).
- **Provat:** només amb falsos i carpetes temporals (`scripts/test.sh`), la compilació i el paquet (`otool`, `codesign --verify --deep --strict`).
- **Rondes:** la A (09/11/2026) i la B (10/11/2026, neta), amb una app de prova; la C, en part (10/11/2026), amb la Warp Launch de debò; la D, la E i la F no es fan (apartat 8;
  `docs/fets-verificats.md`, «Sparkle», seccions 15 a 17). La resta del que depèn de Sparkle i de macOS continua llegit o suposat (etiquetes [L] i [S]).
- **Fet (11/11/2026): el pas 11, a la 0.33.0.** L'autor ha creat la clau l'11/11/2026, amb còpia fora del Mac (ho diu ell), i n'ha passat la part pública.
  `Recursos/Actualitzacions.plist` porta `SUFeedURL` i `SUPublicEDKey`; la guarda 4 (apartat 10) en fixa tots dos valors. `build-app.sh release --amb-feed`, sense publicar [P]:
  el paquet porta les dues claus iguals que el fitxer i passa `codesign --verify --deep --strict` amb el requisit, a l'app i a les tres peces de Sparkle; després s'ha esborrat,
  perquè `instal·la.sh` no el copiï. Una compilació sense l'opció no porta cap de les dues [P].
- **Fet (11/11/2026): el pas 12 i la Porta 2.** Pujats `main` i la recepta (tap, `d9581af`); l'autor ha publicat la 0.33.0 (recepta, `7600cdf`). Comprovat des de fora [P]: l'adreça de l'app dona la 0.33.0,
  el zip quadra amb la mida de l'appcast i el sha256 de la recepta, la signatura amb la clau pública, i l'app de dins porta l'adreça i la clau i passa `codesign` (`docs/fets-verificats.md`, «Sparkle», 18).
- **Falta:** la primera actualització real (Porta 3), amb la versió següent.
- **Decisió de l'autor (09/11/2026, després de publicar la 0.31.5): endavant amb l'activació.** És fer el que falta, en aquest ordre: no treu l'OK de cada ronda ni el de la recepta, i la clau i publicar només els fa ell.
- **Decisió de l'autor (10/11/2026, de nit, durant la C): no fer més proves** («Anem al grà i deixa de fer proves inutils»). La C es queda sense C7 ni C10, i la D, la E i la F
  no es fan: es passa a activar. La decisió 11 ja no pot passar (la B va sortir neta i la E no es fa), ni la 12 (el repo de la ronda F).

El codi s'aparta del que hi ha a sota en això:
- `Actualitzacions.Entorn` té tres camps més: `darreraComprovacio` (l'estat inicial), `models` (la `SituacioApp.Models`, que omplirà el servei) i `rellotge` (les hores). `comprova`, `rep`,
  `reinicia` i `vigila` reben `ara`, els segons amb el Mac despert.
- `SituacioApp` separa `Models` (el que diuen els models de l'app) del temps en marxa, la inactivitat i la instal·lació fallida.
- `enclosureValid` és més estricte: també refusa que la resta de l'adreça surti de la carpeta del feed (`..`, `%`, `?`, `#`, trossos buits).
- `cicleAcabat` també treu de `.baixant`, i un error de baixada també: si no, «Baixant…» es podria quedar per sempre. Un error d'una comprovació sola no amaga una versió ja `.trobada`.
- `.aplicant` que caduca sense bloc (camí de la finestra, `postposada`) torna a `.trobada`.
- `Actualitzacions.Entorn` també té `baixaSola` i `restauraBaixaSola` (0.32.9): la casella de la finestra de Sparkle, a 2.1.
- Si no es pot escriure l'intent en un reinici automàtic, compta com un intent (pausa d'1 h). El botó diu l'error (`errorPreparant`).
- **Pestanya pròpia «Actualitzacions»** (pas 7), no una secció de «General»: amb la secció, «General» faria 738 pt, més dels 640 de la norma (mesurat amb un programa a part, sense finestres).
- Una finestra minimitzada de l'app compta com a oberta (0.32.5), i `posaAlDavant` mostra l'app si era amagada (una precaució: no s'ha vist que sense això falli).
- El diagnòstic anonimitzat diu la carpeta d'una còpia fora d'Aplicacions entre «», perquè l'anonimitzador en redueixi el nom (0.32.4).
- `publica.sh`, a més del que diu l'apartat 4: amb el repo de debò, refusa les variables de prova de signar i de comprovar; després de publicar, també mira que GitHub tingui el zip; si `gh` falla però la versió ja és pública, ho diu i surt amb el codi 2.
- Les regles `deny` i la guarda 11 també cobreixen `generate_appcast`, que signa amb el clauer (ampliació de la decisió 13, que es pot treure). Les ordres que llegeixen el clauer (`security find-generic-password` i `dump-keychain`) les cobreixen la guarda 11 als scripts i, des del 09/11/2026 (decisió de l'autor), les regles `deny` als agents; `security find-identity` no, perquè el fa servir `build-app.sh`.

**Decisions anteriors** (`docs/especificacio.md`, fila del 07/11/2026, 6 i 8): Sparkle 2 com a dependència acordada (regla 10), clau EdDSA, appcast a GitHub, framework signat
i, a `GuardaTests`, excepcions limitades: un fitxer, adreces en una llista fixa i una prova que les limiti.

### Què veurà l'usuari

- **Normalment, res.** Un cop al dia, l'app mira a GitHub si hi ha una versió nova. Si n'hi ha, la baixa (uns 5 MB) i, quan ningú no fa servir el Mac ni l'app, es reinicia:
  la icona de la barra de menú desapareix un moment i torna. Warp i les sessions de Claude no es tanquen ni es toquen.
- **Si estàs treballant, espera.** No es reinicia mentre escrius o mous el ratolí, amb l'editor o la Configuració oberts, amb canvis recents o mentre obre finestres de Warp. Si surts de
  l'app o apagues el Mac, la versió nova ja hi és la propera vegada.
- **A Configuració › «Actualitzacions»:** la versió que tens, si és l'última, «Comprova ara», «Reinicia i actualitza» quan n'hi ha una a punt, i un interruptor
  «Actualitza automàticament» per apagar-ho. Apagat, l'app no es connecta sola.
- **Al menú de la icona:** «Comprova si hi ha actualitzacions…» o, si n'hi ha una a punt, «Reinicia i actualitza a la X».
- **Si no s'ha pogut instal·lar,** la icona pot desaparèixer una vegada. Quan tornis a obrir l'app, la secció diu què ha passat, i no ho torna a intentar sola amb aquella versió.
- **Qui ja té la 0.31.5 o anterior ha d'actualitzar a mà una última vegada** (`brew upgrade --cask warp-launch` o l'ordre del README): aquelles versions no porten res per actualitzar-se. Des de llavors, és automàtic.
- **Privacitat:** GitHub veu l'adreça IP i la versió de l'app. És la primera connexió a internet de l'app.

### Què ha de fer o decidir l'autor

#### Fer (ningú més no ho pot fer)

1. **Crear la clau de signatura** al seu terminal, un sol cop, i fer-ne una còpia fora del Mac el mateix dia (secció 5). Passar la part pública. **Fet l'11/11/2026,** amb la còpia (ho diu l'autor).
2. **Comprovar que el certificat «Warp Launch Dev» té còpia** fora del Mac. **Fet l'11/11/2026:** l'ha exportat (ho diu l'autor).
3. **Donar l'OK de cada ronda de prova** (secció 8): sortir de l'app, mirar el que diu i acceptar els diàlegs de macOS. La ronda D és un reinici, i la fa ell. La ronda E es fa en un usuari de macOS nou. **Fet fins a la C; la D i la E no es fan (10/11/2026).**
4. **OK per a la recepta de Homebrew** (afegir `auto_updates true`) **i per a cada publicació**. **La recepta, pujada l'11/11/2026; la 0.33.0, publicada per l'autor el mateix dia.**
5. **Passar el seu Mac a la primera versió publicada amb Sparkle (la 0.33.0 o posterior) a mà**, i mirar la primera actualització real. **Fet l'11/11/2026 a les 16:29** (`instal·la.sh --github --aplica`, amb el seu OK): la 0.33.0, amb l'adreça i la signatura bona. La primera actualització real, amb la 0.34.

#### Decisions (09/11/2026: l'autor accepta totes les recomanacions)

| # | Decisió | Si dius sí, al teu Mac i als altres | Si dius no | Recomanació |
|---|---|---|---|---|
| 1 | Acceptar només actualitzacions signades amb la clau | Encara que algú robi el certificat i pugui escriure al repo, no pot enviar codi als Macs. Si perds la clau (sense còpia), tothom ha de reinstal·lar a mà fins que hi hagi Developer ID | Qui tingui el certificat i el repo pot enviar codi a tots els Macs, sense la clau. Si perds la clau, encara podries continuar amb el certificat | **Sí**, des de la primera versió. Només val si cada còpia ja ho porta: no es pot activar després per a les que ja corren |
| 2 | No reiniciar mentre es fa servir el Mac (2 min sense teclat ni ratolí) | S'aplica quan t'aixeques. Mai a mig escriure a Warp | S'aplica un parell de minuts després d'estar a punt, encara que escriguis: Warp pot perdre el teclat | **Sí** |
| 3 | Només les versions publicades s'actualitzen soles | Les que compiles tu no es tocaran mai, i la secció dirà per què | Una compilació teva a Aplicacions es pot substituir sola, mentre la proves | **Sí** |
| 4 | «Comprova ara» també baixa la versió si en troba | Un sol botó, en català, sense finestres de Sparkle | Dos passos, i una finestra de Sparkle mig en anglès | **Sí, si la ronda A surt bé** |
| 5 | Editor oblidat obert en un altre escriptori | Cap canvi: espera, i el menú avisa passats 7 dies | L'app es reiniciaria igual passats 7 dies, i tancaria l'editor | **Només l'avís** |
| 6 | Qui executa `publica.sh --aplica` | El fas tu al teu terminal; cap agent no pot publicar | Un agent, amb el teu OK; surt el diàleg del clauer igualment | **Tu** |
| 7 | La pantalla del permís diu que l'app es connecta | Una frase més als usuaris nous: «Un cop al dia, l'app mira a GitHub si hi ha una versió nova i s'hi actualitza sola. Ho pots apagar a la Configuració.» | Només al README. `migrat` no veu la pantalla en cap cas: per a ells, el README i les notes | **Sí** |
| 8 | Cada quant comprova | Un cop cada 24 h: una correcció pot trigar fins a un dia | Més sovint, mínim 1 h | **24 h** |
| 9 | Encès de sèrie | Qui es passa a la 0.32.x queda amb les actualitzacions automàtiques sense que li ho hagi demanat ningú | Ningú no s'actualitzaria sol fins que ho activés: no compleix el que has demanat | **Encès**, avisat a les notes i al README |
| 10 | Publicar per etapes | Una versió dolenta triga més a arribar a tothom | Arriba a tothom en 24 h | **No, de moment:** com a molt 5 instal·lacions |
| 11 | Si les rondes B o E no surten netes | Publicar sense actualització automàtica fins que hi hagi Developer ID: l'app continua igual que avui | Publicar igualment: l'usuari veuria diàlegs de macOS o una app que no torna | **Esperar el Developer ID** |
| 12 | Repo públic d'un sol ús per a la ronda F (secció 8) | Un repo temporal amb dues versions falses, 5 minuts, i s'esborra | Es publica sense saber si el fre funciona | **Sí** |
| 13 | `deny` a `.claude/settings.json` per a `generate_keys`, `sign_update` i `publica.sh --aplica` | Cap agent no les pot executar | Només la regla escrita | **Sí** |

### 1. El disseny, en una taula

| Pregunta | Decisió |
|---|---|
| Comprovar | Un cop al dia, sense preguntar (`SUEnableAutomaticChecks`, `SUScheduledCheckInterval` 86.400) |
| Baixar i preparar | Sola (`SUAutomaticallyUpdate`) |
| Instal·lar | Reinici sol quan ningú no fa servir ni el Mac ni l'app (2.2). Si no, en sortir |
| Warp i Claude | Mai no es toquen: Sparkle només tanca les instàncies de la ruta de Warp Launch [L: `SP/Sparkle/InstallerProgress/InstallerProgressAppController.m:375-385`] |
| Finestres de Sparkle | Cap sense demanar-ho. Totes les actualitzacions programades passen per la secció (`standardUserDriverShouldHandleShowingScheduledUpdate` sempre `false`) |
| Signatura | **EdDSA obligatòria abans d'extreure** (`SUVerifyUpdateBeforeExtraction`, decisió 1). Sense `SURequireSignedFeed` |
| Appcast | Un `appcast.xml` d'un sol element, actiu de cada versió: `https://github.com/David-Erra/warp-launch/releases/latest/download/appcast.xml` |
| Feed a l'app | Només amb `build-app.sh --amb-feed`, que només passa `publica.sh` (decisió 3) |
| Codi | Un sol fitxer importa Sparkle: `Sources/WarpLaunchApp/ServeiActualitzacions.swift`. La lògica, sense Sparkle i amb proves |
| Primera versió | 0.32.x. Es publica una sola 0.32.x, i només després de la Porta 1. **Al final, la 0.33.0 o posterior:** el pas 11 va pujar la versió, i no s'ha publicat cap 0.32.x |

### 2. Comportament

#### 2.1 La secció «Actualitzacions»

**Fet: una pestanya pròpia de la Configuració** (vegeu l'alçada, a sota), no una secció de «General». El disseny era: a Configuració › General, entre `seccioArrencada` i `seccioFitxer` (`Sources/WarpLaunchUI/VistaConfiguracio.swift:88`). La fila «Versió» es mou aquí (`:240`).

Files: «Versió» (sempre), Estat, «Actualitza automàticament» (`.mini`), «Comprova ara», i el peu: «Un cop al dia, l'app mira a GitHub si hi ha una versió nova i s'hi
actualitza sola quan no la fas servir. GitHub veu la teva adreça IP i la versió de l'app. Warp i Claude no es tanquen.»

| Estat | Text | Botó |
|---|---|---|
| `.inicial(ultima)` | «Última comprovació: fa X» o «Encara no s'ha comprovat». **Cap afirmació** | «Comprova ara» |
| `.comprovant` | «Comprovant…» | Desactivat |
| `.alDia(quan)` | «Tens l'última versió. Comprovat avui a les 10:42.» **Només després d'un `updaterDidNotFindUpdate` d'aquesta sessió** | «Comprova ara» |
| `.trobada(v)` | «Hi ha la v.» | «Actualitza ara» (la finestra de Sparkle) |
| `.baixant(v)` | «Baixant la v…» | Cap |
| `.baixant(v)` després d'«Actualitza ara» | «L'actualització a la v continua a la seva finestra.» Tant si baixa com si ja espera el clic: el model no ho sap | «Mostra la finestra» (0.32.9) |
| Reinici ajornat des de la finestra | «La v s'instal·larà quan l'app es pugui reiniciar.», i «Ara no: <motiu>» (`textAvis`, mana sobre la fallada anterior) | Cap: el botó de la finestra ja no respon (0.32.9) |
| `.aPunt(v)` | «La v és a punt: s'aplicarà sola quan no facis servir l'app.» Sense reinici sol (interruptor apagat, versió que ha fallat, 3 intents): «La v és a punt: s'instal·larà quan surtis de l'app, o amb «Reinicia i actualitza».» (0.32.9) | «Reinicia i actualitza» |
| `.aPunt` amb motiu | El mateix, i «Ara no: <motiu>» (2.2) | Desactivat si el motiu val també per a «demanat» |
| `.aplicant(v)` | «S'està actualitzant…» | Cap |
| `.error(msg, quan)` | «No s'ha pogut comprovar: msg.» Substitueix «Tens l'última versió» | «Comprova ara» |
| `.errorBaixant(v, quan)` | Ha fallat després de trobar-la (baixar, signatura, preparar): «No s'ha pogut baixar o preparar la v.» El detall, al registre: Sparkle el dona en anglès (0.32.9) | «Comprova ara» |
| Fallada anterior (2.3) | «La v no s'ha pogut instal·lar sola. Prova «Reinicia i actualitza», o reinstal·la-la.» | Segons l'estat |
| `.noDisponible(motiu)` | Només el motiu al peu (2.4) | Tot desactivat |

Mecanismes:

- **«Comprova ara»:** només si `canCheckForUpdates && !sessionInProgress`, perquè la crida no fa res si hi ha una sessió en marxa [L: `SP/Sparkle/SPUUpdater.m:760-762`].
  - Interruptor encès: `checkForUpdatesInBackground()`. És el mateix camí de cada 24 h: troba, baixa i queda a punt, sense finestres (`SPUUpdater.m:603-640`, `SPUAutomaticUpdateDriver`). Amb la decisió 4.
    La capçalera avisa que fora de l'arrencada «could interfere» [L: `SPUUpdater.h:119-121`], però les altres comprovacions fan el mateix amb el temporitzador (`SPUUpdater.m:787-789`, i `:875-899` en acabar). Es prova a la ronda A.
    **Si surt malament:** `checkForUpdateInformation()` i «Actualitza ara», com amb l'interruptor apagat.
  - Interruptor apagat: `checkForUpdateInformation()` no baixa res [L: `SPUUpdater.h:140-154`]. Amb versió: `.trobada`.
- **«Actualitza ara»:** `checkForUpdates()`. Si ja s'està mostrant una actualització, la porta al davant [L: `SPUUpdater.m:695-705`].
- **«Mostra la finestra» (0.32.9):** la mateixa crida, al botó i al menú. Fa falta perquè la finestra de baixada acabada no es pot tancar [L: `SPUStandardUserDriver.m:514`] i l'app no té Dock.
  El model només recorda que l'ha obert «Actualitza ara» (fins a `.cicleAcabat`): sense res nou al disc, i sense haver de saber què hi diu la finestra.
- **Reinici ajornat des de la finestra (0.32.9):** Sparkle gasta el clic [L: `SPUStandardUserDriver.m:521-527`] i no es pot reactivar el botó sense canviar l'actualitzador estàndard: la Configuració i el menú diuen per què s'espera, i `vigila` el fa quan es pot. El botó de la finestra es continua veient actiu.
- **«Reinicia i actualitza»:** crida el bloc de `willInstallUpdateOnQuit` (2.2).
- **L'interruptor** canvia només `automaticallyChecksForUpdates`: Sparkle ho desa a les seves preferències, i la baixada automàtica en depèn [L: `SPUUpdaterSettings.m:229-234,316,327`]. Apagat amb una versió a punt: no es reinicia sola, però s'instal·la en sortir [L: `SPUUpdaterDelegate.h:421-440`]. El peu ho diu.
- **La casella de la finestra de Sparkle (0.32.9):** una altra preferència, `SUAutomaticallyUpdate` [L: `SUUpdateAlert.xib:119`], que només es veu amb l'interruptor encès (`SUUpdateAlert.m:385`): per exemple, si s'encén amb una versió ja trobada. Desmarcar-la **apaga l'interruptor** i torna a posar la baixada sola, perquè en tornar-lo a encendre funcioni (`Actualitzacions.canviEntorn`). Una sola preferència a l'app.

**Vist a la ronda B, amb l'app de prova** [P: `docs/fets-verificats.md`, «Sparkle», secció 16]: els textos de `.errorBaixant`, de `.aPunt` sense reinici sol i de `.baixant` després d'«Actualitza ara»;
«Mostra la finestra», que la porta al davant; «Instal·la i reinicia», que reobre l'app amb `reobertura=demanada`; la casella, que apaga l'interruptor; i, amb l'interruptor apagat i una versió a punt,
la instal·lació en sortir, sense reobrir-la. **No s'ha vist:** el reinici ajornat des de la finestra.

**Menú de la icona** (`Sources/WarpLaunchApp/WarpLaunchApp.swift:413-425`, entre «Configuració…» i «Sobre l’app»): «Comprova si hi ha actualitzacions…» porta l'app al davant, obre la Configuració a «General» i comprova; amb una versió a punt, «Reinicia i actualitza a la v»; passats 7 dies a punt, «… (fa N dies)» (decisió 5). Fins que s'accepta el permís, només els dos ítems de sempre (`:329-340`).

**Menú de l'app:** el mateix, amb `CommandGroup(after: .appInfo)`, al target de l'app.

**`TabView`** passa a `selection` lligada a una propietat del model (`@State` no compila amb les Command Line Tools [P: fets anteriors, `plugin for module 'SwiftUIMacros' not found`]).

**Alçada:** el màxim és 640 pt (`VistaConfiguracio.swift:57`). Es mesura amb el programa de la 0.30.2. Si passa, tercera pestanya «Actualitzacions»; `PestanyaConfiguracioTests` n'admet de 2 a 6. **Mesurat: 738 pt. Tercera pestanya.**

**Les finestres de Sparkle** només surten amb «Actualitza ara» (interruptor apagat, o el cas rar de `.trobada`), en català parcial (26 claus de 82 [P]). S'accepta. **«Install on Quit» no surt en aquesta finestra** [P: ronda A; la de baixada acabada només té «Instal·la i reinicia»]: només a l'alerta d'una actualització ja preparada [L: `SP/Sparkle/SUUpdateAlert.m:462-468`], on es tradueix «Reinicia el programa més tard».

#### 2.2 Quan es reinicia sola

`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` torna `true` i es guarda el bloc. Conseqüències [L: `SPUUpdaterDelegate.h:421-440`]: el cicle s'atura, no hi ha més comprovacions fins que s'instal·la (ni l'avís dels 7 dies); el bloc instal·la i reobre sense interfície, i es pot cridar més d'un cop; i en tancar l'app s'instal·la igualment.

`PoliticaActualitzacions.motiuEspera(_:demanat:)` (funció pura, `nil` = es pot). En aquest ordre:

| Motiu | D'on surt | Automàtic | Demanat |
|---|---|---|---|
| `errorEnDesar` | `Editor.errorDesat` (`Editor.swift:56`): sortir obriria una alerta modal | espera | espera |
| `nomAMigEscriure` | `Editor.nomEnEdicio` (`:61`) | espera | espera |
| `obrint` | `Obertura.estat != .cap` amb `.preparant`, `.obrint`, `.preparantTot`, `.obrintTot` (`Obertura.swift:97-109`) | espera | espera |
| `fullObert` | `Obertura.mostraFull`, `Lligam.mostraFull`, `Desinstallacio.confirmant`, `Editor.demanaImportacio`, `demanaNovaPestanya`, `attachedSheet` | espera | espera |
| `conversesEnCurs` | `Obertura.teConversesEnCurs` **(nou, per data: 3.2)** | espera | espera |
| `refrescant` | `RefrescWarp.refrescant` **(nou:** `enCurs != nil`, `RefrescWarp.swift:145`**)** | espera | espera |
| `ajustPerDesactivar` | `RefrescWarp.pendent == .acabaDeCanviar` (`:111`) | espera | espera |
| `finestraVisible` | Editor, Configuració, «Sobre l’app» o Sparkle (`Activacio`) | espera | no |
| `canvisSenseDesar` | `Editor.canvisSenseDesar` (es desen en sortir) | espera | no |
| `desfesRecent` | `undoManager.canUndo` o `desferPlantilla.canUndo`, i l'últim canvi fa menys d'1 h: es perdria ⌘Z | espera | no |
| `acabaDArrencar` | Menys de 5 min en marxa: no barrejar-se amb l'inici de sessió | espera | no |
| `macEnUs` | Menys de 120 s sense teclat ni ratolí | espera | no |
| `installacioFallida` | 2.3 | espera sempre | no |

`.quanSObriWarp` no bloqueja: pot durar dies i no es perd res.

**La inactivitat** és necessària, no una millora: en reobrir, Sparkle fa `openURL:` sense opcions i busca ser l'app del davant [L: `InstallerProgressAppController.m:408-412`]. És `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`: **[P]** retorna valor i no demana cap permís des d'una eina de consola; compila amb només `import AppKit`, en mode Swift 6. **[P]** també dins de l'app de prova: puja sense tocar res (ronda A) i baixa a 0 en moure el ratolí (ronda B).
Mantingut amb la decisió 2. Si es rebutja, `macEnUs` es treu i només queden els altres motius.

**El temps:**

- `Actualitzacions.vigila(ara:)` es crida des de `llegeixPeriodicament` (`WarpLaunchApp.swift:215-221`), cada minut. **Cap temporitzador nou.** `ara` és `systemUptime`: el Mac adormit no compta.
- Automàtic: **60 s seguits sense cap motiu** (`quietud`), és a dir, dues crides de `vigila`. Un motiu reinicia el compte. Amb `macEnUs`: uns 3 o 4 minuts sense tocar el Mac.
- Demanat: de seguida. Amb motiu, el botó queda desactivat i diu per què: res «per fer després».
- Després del bloc, `.aplicant` (i «Obre» desactivat). Passats 60 s amb l'app viva, s'ha cancel·lat: torna a `.aPunt`, treu l'intent (0.32.9: si no, una arrencada sense instal·lar comptaria com a fallada), `intents += 1`, i pausa d'1 h. Com a molt, 3 intents per arrencada; després, només en sortir o amb el botó.
- Si en un portàtil el Mac s'adorm abans d'arribar-hi, queda a punt fins que surtis o premis el botó. El menú ho diu (decisió 5).
- Una sola línia al registre per canvi d'estat.
- `shouldPostponeRelaunchForUpdate` només ajorna el camí de la finestra de Sparkle: si hi ha motiu, guarda el bloc i torna `true`, i `vigila` el crida quan es pugui. Una sola vegada [L: `SPUInstallerDriver.m:521-535`]. **Mai** `updaterShouldRelaunchApplication`: amb `false`, avorta [L: `:503-519`].

**Després de reobrir-se** (automàtica): cap finestra, política `.accessory` i `NSApp.hide(nil)` a `applicationDidFinishLaunching`, perquè el focus torni a l'app d'abans **[P: ronda C, C4]**.

#### 2.3 Quan la instal·lació falla després de sortir

Si l'última etapa falla, `Autoupdate` acaba amb error i no reobre res [L: `SP/Autoupdate/AppInstaller.m:804-805,821-823`]. L'app no pot avisar: ja no corre. Només es pot evitar que es repeteixi.

Abans de cada crida al bloc, el model desa un **intent** a `actualitzacio.json`, a la carpeta de la configuració, al costat de `estat.json` (`EstatApp.swift:7`: el fitxer és de l'app, no de l'usuari). Sobreviu a la purga de `~/Library/Caches` (que podria ser justament la causa), i amb `--config` no es llegeix mai.

```json
{"versio":1,"pendent":{"objectiu":"0.32.1","tipus":"automatica","hora":"2026-11-09T10:42:00Z"},"fallades":0,"versioFallada":null}
```

En arrencar, només amb `.real` (`IntentActualitzacio.enArrencar`), i llegint-lo una sola vegada:

| Cas | Efecte |
|---|---|
| Sense fitxer o sense `pendent` | Res |
| Versió actual ≥ `objectiu` | Èxit: `reobertura` = `tipus` si l'hora és de 5 s enrere a 300 s i posterior a l'encesa del Mac (si no, `nil`: amb un reinici entremig, és l'inici de sessió). `pendent` fora, `fallades = 0` |
| Versió actual < `objectiu` | Fallada: `reobertura = nil`, `fallades + 1`, `versioFallada = objectiu`, `pendent` fora |
| Fitxer mal format, o `versio` més nova | Com si no hi fos, i ho apunta al registre. No bloqueja res |
| Versió actual ≥ `versioFallada`, amb pendent o sense (s'hi ha arribat en sortir, amb Homebrew o a mà) | `fallades = 0` i `versioFallada` fora. Si no, amb dues fallades no es tornaria a reiniciar sola mai més |

Automàtic bloquejat (`installacioFallida`) si el candidat és `versioFallada` o si `fallades >= 2`. **Així, la icona desapareix com a molt una vegada per versió, i dues en total** si cada versió falla. «Reinicia i actualitza» sempre es pot. Si desar l'intent falla, no es crida el bloc.

**Comparació de versions:** tres enters (funció pura). Ara no n'hi ha cap al codi [P: `grep`].

**Si s'ha cancel·lat i després es fa «Surt»:** Sparkle reobre igualment (`_shouldRelaunch` continua cert [L: `AppInstaller.m:663,821`]), amb l'editor si l'hora és vella, i amb la pantalla del permís si s'ha fet «Restaura Warp i surt…». Calen tres coses rares (una alerta en desar, cancel·lar-la, i després sortir), i no fa cap mal: es documenta i no es programa.

#### 2.4 Quan no s'actualitza mai

`PoliticaActualitzacions.motiuNoDisponible(...)`. Amb motiu, **no es crea el servei**, ni controlador ni connexió. Els booleans els calcula `ServeiActualitzacions` amb `Bundle.main`.

| Cas | Com se sap | Text |
|---|---|---|
| `--config` | `ArgumentsApp.deProva` | «Amb una configuració de prova, l'app no s'actualitza.» |
| Arguments incorrectes | `.incorrecta` (`potContinuar` hi és cert: no n'hi ha prou amb el permís) | «Sense configuració, l'app no s'actualitza.» |
| Binari fora d'un `.app` | `bundlePath` sense `.app`, sense identificador [P] | «Només s'actualitza l'app instal·lada.» |
| Fora de `/Applications/`, o traslladada per macOS | El criteri de `ServeiArrencada.swift:24` | «Per actualitzar-se sola, l'app ha de ser a Aplicacions. Ara és a …» |
| Sense feed | `SUFeedURL` absent: no s'ha compilat amb `--amb-feed` | «Aquesta còpia no és una versió publicada i no s'actualitza sola.» |
| No pot escriure, o el paquet és d'un altre usuari | `isWritableFile` sobre l'app i la carpeta, i `ownerAccountID == getuid()` | «Aquesta còpia la va instal·lar un altre usuari del Mac: l'ha d'actualitzar ell.» |
| Sparkle no respon com cal | `responds(to:)` o codis d'error (3.3) | «Aquesta versió de l'actualitzador no és compatible.» |

La comprovació del propietari cobreix el que Sparkle també prova: poder canviar propietari i grup [L: `SP/InstallerLauncher/SUInstallerLauncher.m:340-375`]. Si no, Sparkle demana autorització, no arriba al delegat i obre una finestra [L: `SUInstallerLauncher.m:471`, `SPUUpdater.m:803`, `SPUAutomaticUpdateDriver.m:150`].

**Abans del permís, res:** `startingUpdater: false`, i `start()` a `consentiment.enContinuar` (`WarpLaunchApp.swift:257-269`, a `applicationDidFinishLaunching`). Així continua sent cert «Si surts, no es desa res» (`ConsentimentRestauracio.swift:97-98`). `mayPerform` refusa si el permís s'ha retirat, i val per a tots els camins [L: `SPUUpdater.m:847`]. Amb `retirat`, no s'engega.

#### 2.5 Privacitat

Un GET a GitHub amb `User-Agent: Warp Launch/0.32.0 Sparkle/2.10.1` [L: `SP/Sparkle/SPUUpdater.h:330-331`]. Sense perfil del sistema (`SUEnableSystemProfiling` absent: guarda). GitHub veu l'adreça IP. **[S]** cap altra connexió: no se n'ha trobat cap a les fonts llegides.

### 3. Arquitectura

| Fitxer | Què hi ha | Sparkle |
|---|---|---|
| `Sources/WarpLaunchCore/PoliticaActualitzacions.swift` | `motiuNoDisponible`, `motiuEspera`, `SituacioApp`, constants, `enclosureValid`, `esErrorVisible`, comparar versions | No |
| `Sources/WarpLaunchCore/IntentActualitzacio.swift` | El tipus, `MagatzemIntent` (`EscripturaAtomica`), `enArrencar` | No |
| `Sources/WarpLaunchCore/InicDeSessio.swift` | Paràmetre obligatori `reobertaPerActualitzacio` | No |
| `Sources/WarpLaunchUI/Actualitzacions.swift` | Model `@Observable`: estats, `vigila`, intents, textos | No |
| `Sources/WarpLaunchUI/VistaConfiguracio.swift` | La secció i `TabView(selection:)` | No |
| `Sources/WarpLaunchApp/ServeiActualitzacions.swift` | **L'únic `import Sparkle`.** Controlador, delegats, `Actualitzacions.Entorn` | Sí |
| `Sources/WarpLaunchApp/WarpLaunchApp.swift` | Crear, engegar, `vigila`, menús, reobertura | No |
| `Recursos/Actualitzacions.plist` (nou) | L'únic lloc amb les dues adreces: `SUFeedURL`, `SUPublicEDKey` | No |
| `scripts/verifica-signatura.swift` (nou) | Comprova la signatura amb CryptoKit i la clau pública de l'app | No |

#### 3.1 Constants

`quietud` 60, `inactivitatMinima` 120, `minimEnMarxa` 300, `tempsAplicant` 60, `pausaEntreIntents` 3.600, `maximIntents` 3, `limitDesfes` 3.600, `margeReobertura` 300, `diesAvis` 7, `tempsComprovant` 180, `carpetaAplicacions` `"/Applications/"`. Totes `static let` a `PoliticaActualitzacions`.

#### 3.2 Canvis als models

- `Obertura.teConversesEnCurs`: **amb la data**, com `conversesRecents()` (`Obertura.swift:527`): `conversesEnCurs.contains { abs(ara.timeIntervalSince($0.value.desDe)) < PlaObertura.tempsDarrerLlancament }` (en valor absolut, perquè un rellotge que va enrere no el deixi cert fins que torni a arribar a aquella hora). Si no, una pestanya on Claude no arriba mai bloquejaria per sempre, perquè `enLlegir` només esborra si veu el Claude (`:368-376`).
- `RefrescWarp.refrescant`: `enCurs != nil`.
- `Editor.darrerCanvi: Date?`: a `canvia(...)` (`Editor.swift:1005`) i `canviaPlantilla` (`:952`).
- `Obertura.aplicantActualitzacio: () -> Bool` (per defecte `{ false }`, l'assigna `Aplicacio`) i `potObrir` / `potObrirTot` la miren. Tapa el clic a «Obre» entre el bloc i la sortida, que ja no es torna a preguntar [L: `SPUInstallerDriver.m:522-527`].

#### 3.3 El servei

`@MainActor`, `NSObject`, `SPUUpdaterDelegate`, `SPUStandardUserDriverDelegate`, amb `@preconcurrency import Sparkle`. **[P]** totes les crides d'aquí compilen amb les Command Line Tools, en Swift 6, i els 11 `responds(to:)` donen `true` (paquet de prova amb Sparkle 2.10.1, executat, secció 12).

```swift
public struct Entorn {                                        // al model; l'omple el servei
    public var comprovaIBaixa: @MainActor () -> Void          // checkForUpdatesInBackground
    public var nomesMira: @MainActor () -> Void               // checkForUpdateInformation
    public var actualitzaAra: @MainActor () -> Void           // checkForUpdates
    public var potComprovar: @MainActor () -> Bool            // canCheckForUpdates && !sessionInProgress
    public var automatiques: @MainActor () -> Bool
    public var posaAutomatiques: @MainActor (Bool) -> Void
    public var segonsInactiu: @MainActor () -> TimeInterval   // CGEventSource
}
public enum Esdeveniment {
    case trobada(String), alDia, baixant(String), cicleAcabat
    case aPunt(String, aplica: @MainActor () -> Void)
    case postposada(String, aplica: @MainActor () -> Void)   // amb la versió: també en aquest camí, l'intent s'escriu abans de cridar
    case error(String, demanat: Bool)
}
```

- `try controlador.updater.start()`, **no** `controlador.startUpdater()`, que en fallar obre una alerta modal [L: `SP/Sparkle/SPUStandardUpdaterController.m:96-99`].
- **Abans d'engegar**, `responds(to: #selector(SPUUpdaterDelegate.…))` dels mètodes dels quals depèn la seguretat: `willInstallUpdateOnQuit`, `shouldPostponeRelaunch`, `updaterWillRelaunchApplication`, `mayPerform`, `shouldProceedWithUpdate`, `didAbortWithError`, `standardUserDriverShouldHandleShowingScheduledUpdate`. Un mètode opcional mal escrit compila, només amb un avís, i Sparkle no el crida; `#selector` no compilaria si Sparkle canviés el nom [P: prova prèvia]. I que `SUError.noUpdateError.rawValue == 1001` i `.installationCanceledError == 4007`. Si falla, `.noDisponible` i no engega.
- `updater(_:shouldProceedWithUpdate:updateCheck:)` **llança** si `isInformationOnlyUpdate`, `isCriticalUpdate`, `isMajorUpgrade`, `fileURL == nil` o `!enclosureValid`. Es crida abans de `deferInformationalUpdate` [L: `SPUBasicUpdateDriver.m:150-158`]; amb error, no mostra res ni torna a començar [L: `SPUAutomaticUpdateDriver.m:150-155`]. L'appcast no va signat, i aquests camps podrien obrir finestres i enllaços [L: `SPUAutomaticUpdateDriver.m:82-96`].
- `enclosureValid(feed:enclosure:)`, pura: carpeta del feed, canviant `/releases/latest/download` per `/releases/download`; l'enclosure hi ha de començar. Amb el feed real i el local (rondes).
- `didAbortWithError`: només si `esErrorVisible(codi:)`, és a dir, ni `SUNoUpdateError` (1001) ni `SUInstallationCanceledError` (4007). Sparkle hi passa sempre el 1001 quan no hi ha res de nou [L: `SPUBasicUpdateDriver.m:257-276`, `SPUUpdater.m:798-804`].
- `didFinishUpdateCycleFor` envia `.cicleAcabat`: si encara és `.comprovant` o `.baixant`, torna a `.inicial`. Des de la 0.32.9, també oblida la finestra i el reinici ajornat. A més, `vigila` hi posa un límit de 180 s a `.comprovant`.
- `standardUserDriverShouldHandleShowingScheduledUpdate` torna **sempre `false`**, i `standardUserDriverWillHandleShowingUpdate(handle: false, …)` envia `.trobada(versio)`. És l'exemple de `documentation/gentle-reminders`. Mai cap finestra sense demanar-la. `supportsGentleScheduledUpdateReminders = true`.
- `updaterWillRelaunchApplication`: només per al camí de la finestra de Sparkle sense ajornar (escriu un intent `demanada` i passa a `.aplicant`, 0.32.9, perquè també caduqui si l'app no surt). Sparkle només el crida el primer cop [L: `SPUInstallerDriver.m:551-554`]: per això, al camí del bloc i al de la postposada l'intent l'escriu el model cada vegada. **Sparkle també el crida al camí del bloc** [L: `SPUCoreBasedUpdateDriver.m:322-335`]: si el model ja és `.aplicant`, no s'ha de tocar l'intent, o un reinici sol quedaria com a `demanada` i obriria l'editor.
- KVO de `canCheckForUpdates`, `sessionInProgress` i `lastUpdateCheckDate` [P], i, des de la 0.32.9, `automaticallyDownloadsUpdates` (la casella de la finestra de Sparkle) [L: `SPUUpdater.m:1064-1067`, `SPUUpdaterSettings.m:65-77`].
- Sense `feedURLString`, `setFeedURL`, `sendsSystemProfile`, `allowedChannels` ni `startUpdater()`.
- Retenir els delegats: són febles [L: `SPUStandardUpdaterController.h`].

#### 3.4 La reobertura

Sparkle la reobre sense arguments [L: `InstallerProgressAppController.m:408`], SwiftUI obriria l'editor (`Activacio.swift:64-69`), i en els primers 10 minuts del Mac tornaria a sortir el full d'«Obre-ho tot» (`InicDeSessio.swift:15-17`).

- `Aplicacio.init` (només `.real`): `IntentActualitzacio.enArrencar` → `reobertura: Tipus?`.
- `InicDeSessio.es(..., reobertaPerActualitzacio: reobertura != nil)`: amb marca, `false`.
- `.automatica`: `.defaultLaunchBehavior(.suppressed)` a l'escena de l'editor [P: compila, i a la ronda C, C4], `Activacio.enArrencar` posa `.accessory`, i `NSApp.hide(nil)`.
- `.demanada`: com sempre, l'editor s'obre i serveix de confirmació.
- **Forat:** amb l'editor suprimit, `applicationShouldHandleReopen` (`WarpLaunchApp.swift:276-279`) no fa res, perquè `mostraEditor(obre: {})` necessita `openWindow`. Es captura des de l'etiqueta del `MenuBarExtra`, i es passa a `Aplicacio`. **[S]: no s'ha vist (a C5, l'autor va sortir de l'app abans del clic).** Si no funciona, es renuncia a `.suppressed` i es fa `amagaEditorSiNoSHaFetServir` (`Activacio.swift:107-111`), ja provat; la finestra es veuria un instant.

**`applicationShouldTerminate` no canvia:** desa, atura el refresc i fa servir `.terminateLater`; Sparkle l'espera sense límit de temps [L: `InstallerProgressAppController.m:335-357`]. Si surt `restore_session` activat, `vigila` el desactiva en reobrir-se. Sense reobertura (2.3), fins que s'obri, com avui.

#### 3.5 Diagnòstic

`EntornDiagnostic.actualitzacions: (() -> String)?` (`nil` al CLI: «no aplica»). Diu si el servei està actiu, el motiu si no, l'estat, `fallades` i `versioFallada`. Afegir `actualitzacio.json` a `Diagnostic.coneguts` (`Diagnostic.swift:808`).

### 4. Paquet, scripts i recepta

#### `Package.swift`

- `:14-15`: `dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")]`.
- `:24`: `.product(name: "Sparkle", package: "Sparkle")`, només a `WarpLaunchApp`.
- `:4`: el comentari.
- **`Package.resolved` al repo:** sense, l'arbre queda brut i `publica.sh:46` refusa.
- Un clon nou necessita xarxa la primera vegada, també només per al CLI [P]. Va al README.

#### `Recursos/Info.plist`

Per a tothom, sense efecte si no hi ha feed: `SUEnableAutomaticChecks` `true`, `SUAutomaticallyUpdate` `true`, `SUScheduledCheckInterval` 86.400 i `SUVerifyUpdateBeforeExtraction` `true` (decisió 1).

**Per què la 1 importa:** si la signatura de codi coincideix, la clau pública que mana és la de l'app nova [L: `SP/Sparkle/SUUpdateValidator.m:351-373`]. Amb el certificat i el repo n'hi ha prou. Amb la clau activada, l'EdDSA és obligatòria abans d'extreure [L: `SP/Autoupdate/AppInstaller.m:277-292`]; el certificat només hi valdria amb Team ID [L: `SUCodeSigningVerifier.m:323-363`], i un certificat propi no en té; el pas a Developer ID continua passant amb la mateixa clau [L: `SUUpdateValidator.m:165-200`]. Es llegeix de l'app que corre (`_host`): per això, ha d'anar a la primera.

#### `scripts/build-app.sh`

Ús: `scripts/build-app.sh [release|debug] [--amb-feed]`.

| Línia | Canvi |
|---|---|
| `:11` | Interpretar els dos arguments; qualsevol altre, codi 64 |
| `:21` | `swift build -c "$CONFIG" --product WarpLaunch -Xlinker -rpath -Xlinker @executable_path/../Frameworks` [P: `otool -l`] |
| `:25` | També `$APP/Contents/Frameworks` |
| `:26` | `ditto "$BIN/Sparkle.framework" "$FW"` i `rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"` (només amb sandbox; 0,3 MB) |
| `:31` | `cp -X .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/LICENSE-Sparkle"` [P] |
| `:45-47` | Detectar el certificat abans de l'`Info.plist` |
| `:27` | Amb `--amb-feed`: `PlistBuddy -c "Merge Recursos/Actualitzacions.plist"` [P]. Sense el certificat, sense el fitxer o amb `WARP_LAUNCH_IDENTITAT` definit: error |
| `:48`, `:52` | Signar de dins cap a fora: `Versions/B/Autoupdate`, `Versions/B/Updater.app`, framework, app. Sense `--options runtime` fins al Developer ID. `--force` sempre |
| `:54` | `codesign --verify --deep --strict "$APP"` [P] |
| Nova | `otool -l` ha de tenir `@executable_path/../Frameworks`; si no, error |

`.build/debug/WarpLaunch` pot deixar d'arrencar sol: sense el flag, un binari amb Sparkle no porta cap rpath que el trobi [P: `otool -l` del paquet de prova, d'un sol target]. Regla 4: no s'obre. Es mira amb `otool -l` al pas 5. Si no té `@loader_path`, s'anota al `CLAUDE.md`: per veure l'app, `build-app.sh debug`.

Les guardes de `GuardaTests:2204-2216` (`cp -X LICENSE` abans del primer `codesign --force`, i les cadenes de signatura) s'han de reescriure.

#### `scripts/verifica-signatura.swift` (nou) [P]

```swift
import CryptoKit
import Foundation
let a = CommandLine.arguments
guard a.count == 4, let pub = Data(base64Encoded: a[1]), let sig = Data(base64Encoded: a[2]),
      let clau = try? Curve25519.Signing.PublicKey(rawRepresentation: pub),
      let dades = FileManager.default.contents(atPath: a[3]) else { fputs("arguments\n", stderr); exit(64) }
exit(clau.isValidSignature(sig, for: dades) ? 0 : 1)
```

**[P]** `swift verifica-signatura.swift <pública> <signatura> <zip>` amb la clau d'un sol ús i el zip de prova: bona 0, un byte canviat 1, una altra clau 1, entrada mal formada 64.

No toca el clauer, comprova amb una eina independent de Sparkle i ho fa **amb la clau que porta l'app**. Això fa innecessari `generate_keys -p`: un sol diàleg del clauer per publicació, i `generate_keys` no surt a cap script.

#### `scripts/publica.sh`

1. **Abans de compilar:** `compta_linies '^  auto_updates true$'` ha de ser 1 (al costat de `:105-109`). L'última de `gh release view --json tagName` ha de ser anterior a `VERSION`, amb la comparació de `:119`.
2. **Compilar** amb `scripts/build-app.sh release --amb-feed` (`:125`).
3. **Comprovacions:** framework present; `CFBundleVersion` = `VERSION` (si no, tothom es tornaria a actualitzar cada dia); `SUFeedURL` i `SUPublicEDKey` iguals que a `Recursos/Actualitzacions.plist`; `codesign --verify --deep --strict -R=…` (`:131`) i un bucle amb el mateix `-R` sobre `Versions/B/Autoupdate`, `Versions/B/Updater.app` i el framework, perquè `--deep` no mira qui signa a dins [P: codi 0 amb el framework ad hoc; codi 3 amb `-R`].
4. **Mode de prova:** no toca el clauer. `build/appcast-prova-$VERSIO.xml`, amb `SENSE-SIGNAR`, i diu què publicaria.
5. **Avís:** si `git diff --name-only $BASE..$COMMIT` toca `Package.resolved`, `ServeiActualitzacions.swift` o `build-app.sh`: «Aquesta versió canvia l'actualitzador (…). Si l'espatlla, les còpies que la rebin no s'arreglaran soles: com s'atura, …» No bloqueja (des de l'11/11/2026, només informa: vegeu la regla de l'apartat 7).
6. **Amb `--aplica`, abans de `gh release create`** (`env -u GH_TOKEN -u GITHUB_TOKEN`; eines amb `WARP_LAUNCH_SIGN_UPDATE` i `WARP_LAUNCH_VERIFICA`, per a les proves):
   - `sign_update "$ZIP"`, sortida exacta `sparkle:edSignature="<88>" length="<N>"`, amb `N` = la mida del zip [P].
   - `verifica-signatura.swift` amb `SUPublicEDKey` del paquet compilat. Si no passa: «la clau d'aquest clauer no és la que porten les apps». No es publica res.
   - `build/appcast.xml`, plantilla d'un element amb `sparkle:version`, `shortVersionString`, `minimumSystemVersion` 26.0, `hardwareRequirements` arm64, `enclosure` amb `v$VERSIO`, `length`, `type` i `sparkle:edSignature` [P: forma de `generate_appcast`], i `xmllint --noout` [P]. Sense `generate_appcast`, que escriu a `~/Library/Caches` i toca el clauer.
7. `gh release create "$ETIQUETA" "$ZIP" "$APPCAST" --repo … --latest …` (`:196`). El zip continua sent el `$4` del `gh` fals. Tots dos en una sola ordre: `latest` no canvia fins que hi són [L: `cli/cli`, `draftWhileUploading`].
8. **Després:** `gh release view --json tagName,assets`: l'última ha de ser aquesta i portar `appcast.xml`. Si no, codi 2 i avís.
9. **Missatges** (`:162-178`, `:203`, `:228`): publicar **ja no es desfà** (secció 7). A les notes, que l'app s'actualitzarà sola, com apagar-ho i que la primera vegada és manual.

#### `scripts/instal·la.sh`

`--deep` a `:109`, `:125` i `:154`. El patró `WarpLaunch-*.zip` de `:83` no agafa `appcast.xml`. Text de desinstal·lació (`:181-187`): `~/Library/Caches/cat.davide.warp-launch` i `~/Library/HTTPStorages/cat.davide.warp-launch`.

#### Recepta (`David-Erra/homebrew-tap`, fora d'aquest repo)

```ruby
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe
```

- **Abans de `depends_on`:** és l'ordre que exigeix `brew style` [L: `HB/rubocops/cask/constants/stanza.rb:35-38`]. La recepta actual [P: `gh api`, només lectura] té els dos `depends_on` seguits.
- `zap`: afegir `~/Library/Caches/cat.davide.warp-launch` [L: `SPULocalCacheDirectory.m:49-54`] i `~/Library/HTTPStorages/cat.davide.warp-launch` [S: C9].
- El primer `brew upgrade` des de la 0.31.5 actualitza, perquè el paquet és més vell que la recepta, i no ho trepitja després [L: `HB/cask/cask.rb:489-494`].
- `brew style` i `brew audit` amb el nom complet.
- **Ha d'anar abans de la primera publicació:** `publica.sh` la refusaria.

### 5. La clau EdDSA

**On viu:** al clauer d'inici de sessió, contrasenya genèrica, servei `https://sparkle-project.org`, compte `ed25519` [L: `SP/generate_keys/main.swift:13-30,105-126`].

**Crear-la (un sol cop, l'autor, al seu terminal):**

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys   # imprimeix la pública; la privada no surt
```

Si ja n'hi ha una, torna a mostrar aquella [L]. La pública va a `Recursos/Actualitzacions.plist`, que pot anar al repo.

**Còpia (el mateix dia, abans de publicar):**

```bash
umask 077; .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/fora-del-repo/warp-launch.ed25519
```

A un gestor de contrasenyes o a una imatge xifrada, **almenys una fora d'aquest Mac**. Esborrar el fitxer. Per comprovar la còpia: `sign_update -f <còpia> -p <un zip>` i `verifica-signatura.swift` amb la pública.

**Perquè no acabi al repo:**

- `publica.sh` no rep mai la clau: `sign_update` la llegeix del clauer.
- Cap `-s`, `--ed-key-file` ni `-x` als scripts (guarda). `generate_keys` no surt a cap script.
- `.gitignore`, a «Secrets i claus»: `*.ed25519` i `*-privada-sparkle*`.
- Cap agent no crea ni llegeix aquesta clau (regla nova). `generate_keys` sense arguments la crea; `--help` és l'única forma permesa.
- En publicar, «Permet», no «Permet sempre»: cada publicació és una decisió.
- També el certificat: amb la decisió 1, sol ja no basta, però continua signant l'app. `build-app.sh:44` diu «Permet sempre»: si es rebutja la decisió 1, s'ha de treure.

**Si es perd o es filtra:**

| Passa | Amb la decisió 1 | Què es fa |
|---|---|---|
| Es perd la clau, però hi ha còpia | Res | S'importa amb `generate_keys -f` |
| Es perd la clau i la còpia | Cap còpia no s'actualitza més, ni amb el mateix certificat. Només amb un disc d'imatge amb Developer ID [L: `SP/…/customization/index.md:40`] | Reinstal·lar a mà |
| Es filtra la clau | Qui la tingui i pugui canviar l'appcast (compte de GitHub) pot enviar codi | Publicar de seguida una versió signada amb la clau vella que porti una clau pública nova [L: la clau nova només es valida amb la política bàsica, `SUUpdateValidator.m:165-200`; no provat], i revisar el compte. Qui s'actualitzi ja només accepta la nova |
| Pas a Developer ID | Passa, amb la mateixa clau [L: `SUUpdateValidator.m:165-200`] | **Mai clau i certificat alhora.** Es perd el permís d'Arxius i carpetes un cop (decisió 1 del 07/11). Instal·lador pel camí antic [L: `SUPlainInstaller.m:349-376`]: una ronda com la B abans |

### 6. Qui ja la té instal·lada

Cap versió publicada porta Sparkle ni cap codi de xarxa [P: `grep`], de manera que **ni es pot avisar des de l'app**. «Per a tothom» val a partir de la primera versió publicada amb Sparkle (la 0.33.0 o posterior).

| Té | Via | Un sol cop |
|---|---|---|
| 0.31.4 o 0.31.5 | Homebrew | `brew upgrade --cask warp-launch` |
| 0.31.5, 0.31.4 o 0.28.0 | L'ordre amb `gh` | Sortir de l'app i tornar a fer l'ordre del README |

Són com a molt 7 instal·lacions [P: `download_count`, API de GitHub, 09/11/2026, després de publicar la 0.31.5: 1 + 4 + 2 baixades; quan es va fer aquest disseny, 3 + 2]. S'avisa a les notes i al README, on també es diu que les actualitzacions van encès de sèrie.

### 7. Aturar una versió dolenta

Va a `docs/disseny.md`. El fre no s'ha comprovat: la ronda F no es fa (decisió de l'autor, 10/11/2026).

1. `gh release edit <anterior> --latest --repo David-Erra/warp-launch`. No esborra res, i `latest/download` torna a apuntar a l'anterior. La redirecció no es desa en memòria cau (`cache-control: no-cache`) [P].
2. Revertir la recepta (`git revert` al tap).
3. Publicar una correcció amb versió superior: Sparkle refusa versions més velles [L: `SUPlainInstaller.m:327-343`].
4. No tornar a pujar un fitxer amb el mateix nom a la mateixa etiqueta: el CDN el serveix amb memòria cau (`age: 6777`) [P].

**Què passa a cada Mac:**

| Té | Passa |
|---|---|
| Encara no l'ha baixada | No la baixa |
| Baixada i a punt | La instal·larà: el cicle és aturat [L: `SPUUpdaterDelegate.h:421-440`]. L'endemà rep la correcció |
| Ja instal·lada | Queda igual fins a la correcció |
| Torna enrere a mà | No puja sol mentre `latest` sigui l'anterior |
| La versió dolenta trenca l'arrencada o Sparkle | Cap camí automàtic: `brew` o l'ordre del README |

**Regla (revisada per l'autor l'11/11/2026):** un canvi de Sparkle, de `ServeiActualitzacions` o de `build-app.sh` no demana cap ronda de proves (decisió del 10/11/2026: no se'n fan més). `publica.sh` ho avisa només com a informació: si una versió trenca l'actualitzador, les còpies que la rebin no es poden arreglar soles (última fila de la taula). Abans, la regla demanava les rondes A i C.

**Homebrew i Sparkle alhora:** amb una versió a punt i `brew upgrade`, `uninstall quit:` tanca l'app i `Autoupdate` canvia el paquet mentre Homebrew el mou. **Sense provar.** No es perd res. Una línia al README: si ho fas amb Homebrew, tanca l'app abans, i no facis servir `--greedy`, que reinstal·la.

### 8. Les proves reals, sense publicar res

Regles 1, 3 i 4: cada ronda, només amb l'OK de l'autor, que sabrà quantes coses s'obren. **Cap ronda obre finestres de Warp ni sessions de Claude**, ni tanca Warp.

**Rondes A i B: una app mínima, no la de debò.** La Warp Launch de debò amb un altre identificador continuaria fent servir `~/.config/warp-launch` i tocant `restore_session`. L'app mínima (carpeta temporal, fora del repo): `cat.exemple.prova-sparkle`, Package amb dependències als targets `Core` i `UI` d'un clon, una còpia de `ServeiActualitzacions.swift`, un `MenuBarExtra` amb tres botons i la carpeta de l'intent en temporal. Muntatge com el de `build-app.sh`, amb `SUFeedURL` local i la clau d'un sol ús.

**Preparació de la ronda C (compilar, sense obrir res):**

1. Clon temporal. Al clon, i només al clon:
   - `VERSION` i `Sources/WarpLaunchCore/Versio.swift` a **0.31.90** i, per a la segona compilació, **0.31.91**. `build-app.sh:16-19` refusa si no coincideixen. Per sota de 0.32.0: cap versió de prova no queda per davant d'una de real.
   - `PoliticaActualitzacions`: `minimEnMarxa` 30, `inactivitatMinima` 20, per escurçar els cicles (uns 6 min, si no). Una versió amb els valors de debò a C2.
   - `Recursos/Actualitzacions.plist`: `SUFeedURL` = `http://127.0.0.1:48917/appcast.xml` (ATS ho deixa passar [P]), i la clau d'un sol ús.
2. `scripts/build-app.sh release --amb-feed` per a totes dues. Zip de la 0.31.91, `sign_update -f <clau temporal>`, appcast amb la plantilla de `publica.sh`.
3. `lsof -nP -iTCP:48917 -sTCP:LISTEN` buit, i `python3 -I -m http.server --bind 127.0.0.1 48917` des d'una carpeta amb només l'appcast i el zip.
4. Entre cicles: `defaults delete <id> SULastCheckTime` (si no, la propera comprovació automàtica és d'aquí a 24 h [L: `SPUUpdater.m:555-588`]) i tornar a instal·lar la 0.31.90 amb `instal·la.sh --aplica`, amb l'app tancada.

| Ronda | Què | S'obre | On | L'autor |
|---|---|---|---|---|
| **A** | App mínima, ad hoc | 1 app de prova | Temporal | OK, i mirar la icona |
| **B** | App mínima, «Warp Launch Dev» | 1 app de prova | `/Applications` (nom diferent) | OK, i «Permet» a `codesign` |
| **C** | Warp Launch del clon | Warp Launch | `/Applications` (substitueix la seva) | OK, surt abans |
| **D** | Reinici amb una versió a punt | Warp Launch en iniciar sessió | | **Reinicia ell** (regla 2) |
| **E** | Usuari de macOS nou, sense el certificat | Warp Launch | `/Applications`, de l'usuari nou | Canvia d'usuari |
| **F** | El fre (secció 7) | Res | Repo públic d'un sol ús | OK i token |

**Ronda A: funciona el cicle?**

| Pas | Acció | Ha de passar |
|---|---|---|
| A1 | «Comprova» amb l'appcast igual que la versió | «Tens l'última versió»; cap error (1001 filtrat) |
| A2 | «Comprova» amb una versió nova (decisió 4) | Baixa i queda a punt, sense finestres. L'estat passa per `.baixant` i `.aPunt`. Registre |
| A3 | Es crida el bloc | Es tanca, s'instal·la i es torna a obrir. `plutil -extract CFBundleVersion raw`, `codesign --verify --deep --strict` |
| A4 | Amb la vella: surt amb la versió a punt | S'instal·la i **no** es reobre |
| A5 | `.terminateCancel` un cop, més de 60 s, i el bloc de nou | Torna a funcionar. Mirar l'hora de `actualitzacio.json` |
| A6 | Zip amb un bit canviat | Refusat, abans d'extreure |
| A7 | Interruptor apagat, `SULastCheckTime` esborrat, arrencar i 2 min | Cap GET al `server.log` |
| A8 | `chflags uchg` a l'app i cridar el bloc | Surt, no torna, `Failed to finalize installation` al registre **[S: que `uchg` faci fallar]**. Reobrir-la: no es reinicia sola, i la secció ho diu |
| A9 | Aturar el servidor, «Comprova ara»; rearrencar | Error, i cap «Tens l'última versió». Rearrencada: `.inicial` |
| A10 | Appcast amb `sparkle:informationalUpdate`, critical, o enclosure a un altre domini | Refusat, cap finestra |
| A11 | Interruptor apagat: «Comprova», «Actualitza ara», baixada sencera (la finestra acaba amb «Instal·la i reinicia», sense «Install on Quit»; vegeu 2.1) i sortir de l'app. «Comprova» a mitja baixada | Cap «Comprovant…» eternament. Sense finestres noves |
| A12 | `secondsSinceLastEventType` dins de l'app | Valor correcte, cap diàleg |

**Ronda B: deixa macOS actualitzar una app amb un certificat propi?** A1, A3 i A6, a `/Applications`. Afegir la prova de la decisió 1: una versió signada amb el mateix certificat, amb **una altra clau pública** i el zip signat amb aquesta altra clau: amb la clau activada, refusada [L]. Només val juntament amb la ronda E.

| Resultat | Vol dir |
|---|---|
| S'actualitza sense cap diàleg | El pla val (mira la ronda E) |
| Diàleg de Gestió d'apps o de Gatekeeper | No és silenciosa: decisió 11 |
| Falla en substituir | Sparkle ha d'esperar el Developer ID |

**Feta el 10/11/2026, neta** (`docs/fets-verificats.md`, «Sparkle», secció 16). L'app de prova, signada amb «Warp Launch Dev» a `/Applications`, amb clics reals de l'autor: 6 obertures (B5,
dues vegades) i 2 reinicis de Sparkle. **S'actualitza sense cap diàleg de macOS** (B2; i B5, pel camí de la finestra fins a «Instal·la i reinicia»), s'instal·la en sortir sense reobrir-se
(primer intent de B5), i refusa abans d'extreure el zip amb un bit canviat (B3) i la versió amb una altra clau (B4). Segons la taula, el pla val, però només juntament amb la ronda E, que no es fa (10/11/2026).
**No ha cobert:** el reinici ajornat des de la finestra (l'app de prova no el pot provocar), el reinici sol (C2), res amb Developer ID, un usuari sense el certificat (E) ni l'app de debò.
**La següent és la C.**

**Ronda C: la Warp Launch de debò.** Abans: `scripts/warp-restauracio.sh estat` i anotar «Obre Warp Launch en iniciar sessió».

| Pas | Ha de passar |
|---|---|
| C1 | La versió, la pestanya «Actualitzacions» i els textos; l'alçada de cada pestanya, com a molt 640 pt |
| C2 | Comprova, baixa i s'aplica sola amb l'editor tancat i sense tocar el Mac (amb els valors de debò, un cop) |
| C3 | La 0.31.91 a `/Applications`, `codesign --verify --deep --strict` amb el requisit de `publica.sh` |
| C4 | **Cap** finestra, ni Dock, ni full d'«Obre-ho tot», també dins dels primers 10 min. Amb TextEdit al davant i `lsappinfo front` cada 0,2 s a un fitxer: acaba amb TextEdit al davant |
| C5 | Obrir l'app des del Finder després d'una reobertura silenciosa mostra l'editor |
| C6 | Es conserva el permís d'Arxius i carpetes (llegeix Warp sense l'avís) i l'ítem d'inici |
| C7 | Amb l'editor obert, en un altre escriptori, o movent el ratolí, no es reinicia; amb un full, tampoc. Dues instal·lacions de la 0.31.90 |
| C8 | Warp intacte: mateix nombre de terminals (`warp-launch llegeix`), `restore_session` a `false` |
| C9 | Què hi ha a `~/Library/Caches/<id>` i `~/Library/HTTPStorages/<id>` |
| C10 | `--config` (`build/`): la secció diu el motiu, i `lsof` no hi veu cap connexió |

**Feta en part el 10/11/2026** (`docs/fets-verificats.md`, «Sparkle», secció 17), amb versions de prova del codi de la 0.32.9 en lloc de la Warp Launch de l'autor, que s'hi va tornar
a posar l'11/11. **Sí:** C1; C2 (comprova sola, baixa i s'aplica sola 186 s després de tancar l'editor, i amb l'editor obert, cap reinici); C3; C4 (torna sense finestra, sense Dock
ni el full, i TextEdit al davant); C6 (el permís d'Arxius i carpetes i l'ítem d'inici, després de dues actualitzacions); C8 (Warp intacte, `restore_session = false`) i C9 (16 MB a
`Caches` i 56 KB a `HTTPStorages`, les dues carpetes del `zap`). **No:** C5 (l'autor va sortir de l'app abans del clic al Finder: va ser una arrencada normal), C7 i C10, per
decisió de l'autor. Cap dels resultats vistos no demana canviar el codi.

**Les rondes D, E i F no es fan** (decisió de l'autor del 10/11/2026, a l'estat d'aquesta secció). El que havien de mirar queda llegit o suposat. A sota, el pla, tal com era.

**Ronda D (l'autor):** amb una versió a punt i l'editor obert, reiniciar el Mac. En iniciar sessió, l'app ja és nova, o s'instal·la a la propera sortida; cap bloqueig en apagar-se. Si no s'instal·la, no és greu, i el README ho dirà.

**Ronda E: els altres Macs.** Un usuari de macOS nou, administrador, sense el certificat, amb la Warp Launch d'aquest usuari esborrada i la còpia posada **per aquell usuari** amb `ditto -x -k` des de `/Users/Shared` (si no, «un altre usuari»). El servidor de la ronda C serveix l'appcast: `127.0.0.1` és el mateix. Mirar: A1, A3, A6, el permís d'Arxius i carpetes, la reobertura i, amb tots dos usuaris connectats i l'app oberta als dos, què passa a l'altra instància (Sparkle no la tanca [L: `InstallerProgressAppController.m:300`]).
Homebrew no entra aquí: un altre usuari no pot escriure al `brew` del primer [S]. El camí amb Homebrew és el mateix paquet i propietari, i es mira a la Porta 3.

**Ronda F: el fre.** En un repo públic d'un sol ús, amb l'OK:

```bash
gh release create v1 appcast.xml …; gh release create v2 appcast.xml …
curl -sIL https://github.com/<compte>/<repo>/releases/latest/download/appcast.xml   # ha de portar a v2
gh release edit v1 --latest                                                          # ha de portar a v1
gh release create v3 appcast.xml …                                                   # ha de portar a v3
```

**Neteja:** esborrar el clon, el repo de prova i les carpetes temporals; aturar el servidor; `defaults delete cat.exemple.prova-sparkle`; esborrar `~/Library/Caches/cat.exemple.prova-sparkle` i `~/Library/Caches/cat.davide.warp-launch`; les claus `SU*` de `cat.davide.warp-launch`; tornar a posar la Warp Launch publicada (`scripts/instal·la.sh --github --versio 0.31.5 --aplica`, o Homebrew); treure l'app de prova i l'usuari nou. L'OK inclou aquest pas (regla 3).

### 9. Passos, en commits petits

`scripts/test.sh` ha de passar a cada pas. Cada guarda, al pas que porta el que guarda. Els passos 1 a 4 no canvien res visible: sense versió, com les guardes del 08/11/2026.

| # | Commit | Proves i guardes | Versió |
|---|---|---|---|
| 0 | `docs:` fets de Sparkle a `fets-verificats.md`, secció a `disseny.md`, fila a `especificacio.md` | | Cap |
| 1 | `chore:` `PoliticaActualitzacions` | Cada motiu, automàtic i demanat; ordre; cada cas de `motiuNoDisponible`; `enclosureValid` (feed real i local, altre domini, altra ruta); `esErrorVisible` (1001, 4007, altres); comparar versions (0.31.9 < 0.31.10, 0.31.4 < 1.0.0) | Cap |
| 2 | `chore:` `Obertura.teConversesEnCurs`, `aplicantActualitzacio`, `RefrescWarp.refrescant`, `Editor.darrerCanvi` | **Conversa sense Claude i `ara = desDe + 601`, sense cridar `conversesRecents()`: fals.** Cert durant; fals abans i després. `potObrir` fals amb `.aplicant` | Cap |
| 3 | `chore:` `IntentActualitzacio` i `InicDeSessio.es(reobertaPerActualitzacio:)` (l'app hi passa `false`) | Cada fila de 2.3; hora del futur, caducada; fitxer mal format; un sol cop; `fallades`; `InicDeSessio` amb marca: `false`, també dins dels 600 s. Noms a `Diagnostic.coneguts` | Cap |
| 4 | `chore:` model `Actualitzacions` | Amb `Entorn` fals: tots els estats; `.inicial` no afirma res; un error substitueix «al dia»; `vigila` amb quietud de 60 s; un motiu reinicia el compte; `demanat` sense quietud; 3 intents i 1 h; `.aplicant` caduca als 60 s; no aplica amb l'interruptor apagat; `.comprovant` caduca als 180 s; `cicleAcabat`; postposada; **escriu l'intent abans de cada crida, també al reintent**; si no pot escriure, no crida; `installacioFallida` | Cap |
| 5 | `feat:` Sparkle 2.10.1 al paquet i a l'app: `Package.swift`, `Package.resolved`, `.gitignore`, `Info.plist`, `build-app.sh` (rpath, framework, llicència, signar, `--deep`, `--amb-feed`), `--deep` a `publica.sh` i `instal·la.sh`, `ServeiActualitzacions` mínim (crea el controlador sense engegar-lo) | Guardes: Package, Info.plist, `SU[A-Z]` i `import Sparkle`, **i inversa: `Recursos/Actualitzacions.plist` no hi és**. `ScriptInstallaTests` amb framework fals, i amb el framework sense signar (ha de fallar). `otool` i `codesign --deep`. `otool -l .build/debug/WarpLaunch` | **0.32.0** |
| 6 | `feat:` el servei complet: delegats, `responds(to:)`, `enContinuar`, `vigila`, inactivitat, diagnòstic | Guardes: prohibits al servei, xarxa a `Sources/`, accions | 0.32.1 |
| 7 | `feat:` la secció, els menús, `selection`, «Comprova ara» | Textos del model; `CommandGroup` a l'app. Alçada, amb el programa de la 0.30.2 | 0.32.2 |
| 8 | `feat:` la reobertura: `.suppressed`, `.accessory`, `hide`, `openWindow`, intent amb `.real` | Guarda: l'intent només amb `.real`; el comportament, a C4 i C5 | 0.32.3 |
| 9 | `chore:` `publica.sh` i `verifica-signatura.swift` | `ScriptPublicaTests`: `sign_update` i `verifica` falsos; el mode de prova no els crida; l'appcast porta versió, URL, mida i signatura; refusa clau diferent, sortida mal formada, mida diferent, sense feed, recepta sense `auto_updates`, `latest` per davant; si signar falla, cap `gh release create`. El `gh` fals rep el zip a `$4`; `laPublica` compara l'ordre exacta amb `--latest` | Cap |
| 10 | `docs:` README i `CLAUDE.md` (secció 11) | | Cap |
| — | **Porta 1: rondes A a F, amb l'OK.** El que surti es corregeix amb commits i versions 0.32.x. **Fetes la A, la B i la C en part; la D, la E i la F no es fan (10/11/2026)** | | |
| 11 | `feat:` `Recursos/Actualitzacions.plist` amb la clau real i el feed (l'autor ha fet la secció 5). **Fet l'11/11/2026** | Guarda inversa canviada: exactament dues claus, `SUFeedURL` exacte, `SUPublicEDKey` exacta (32 bytes). També: `build-app.sh` només llegeix el fitxer a la branca de `--amb-feed`, no copia res més de `Recursos` que la seva llista, i cap altre script no l'esmenta | **0.33.0** |
| 12 | Tap: `auto_updates true` i `zap` (amb l'OK) | `brew style`, `brew audit` | |
| — | **Porta 2:** `publica.sh` en mode de prova, i `--aplica` (decisió 6). Es publica la 0.33.0 (o la que hi hagi llavors) | | |
| — | **Porta 3, primera actualització real:** l'autor passa a aquesta versió a mà; es publica una versió mínima; comprovar que s'actualitza sola amb el feed i la clau de debò. També amb Homebrew. Fins llavors, no s'anuncia | | |

### 10. Guardes noves (`GuardaTests`)

Sense `\b` (`capGuardaFaServirElLimitDeParaula`). Cadascuna amb una línia de mostra per fitxer, com `laRetiradaNomesValAlSeuFitxer` (`:743-760`). **També miren els comentaris**: el fitxer nou no pot esmentar les paraules prohibides (`prohibidesCodi`, `:228-237`).

| # | Què | Pas |
|---|---|---|
| 1 | `import Sparkle`, `SPU[A-Z]` i `SU[A-Z]`, només al servei. Avui no n'hi ha cap a `Sources/` [P: `grep`] | 5 |
| 2 | `Package.swift`: una sola `.package(url:` amb la URL i `exact: "2.10.1"`; `.product(name: "Sparkle"` només a `WarpLaunchApp`. `Tests/` no enllaça Sparkle | 5 |
| 3 | `Recursos/Info.plist`: les quatre claus de la secció 4; `SUEnableSystemProfiling`, `SUFeedURL`, `SUPublicEDKey` i `SUEnableInstallerLauncherService` absents | 5 |
| 4 | Fins al pas 11, `Recursos/Actualitzacions.plist` absent. Després (0.33.0), la forma exacta, amb l'adreça i la clau fixades (`lesAdrecesDeLActualitzacioSonLesDeDebo`) | 5 i 11 |
| 5 | `build-app.sh`: el Merge només dins de la branca de `--amb-feed`, i `publica.sh` és l'únic que el passa. Des de la 0.33.0, la variable del fitxer (`$FEED` o `${FEED}`) només surt a la comprovació, al missatge i al Merge, i cap línia no escriu `SUFeedURL` ni `SUPublicEDKey` pel seu compte | 5, 9 i 11 |
| 6 | Xarxa, a tot `Sources/`, sense excepcions: `URLSession`, `URLRequest`, `NSURLConnection`, `import Network`, `NWConnection`, `NWPathMonitor`, `CFNetwork`, `WKWebView`, `https?://` | 6 |
| 7 | Prohibits al servei: `feedURLString`, `setFeedURL`, `sendsSystemProfile`, `allowedChannels`, `startUpdater()` | 6 |
| 8 | `checkForUpdates`, `checkForUpdatesInBackground` i `checkForUpdateInformation`, només al servei; el bloc, només es crida des d'`Actualitzacions` | 6 i 7 |
| 9 | `secondsSinceLastEventType`, només al servei | 6 |
| 10 | Intent només amb `.real` | 8 |
| 11 | `scripts/`: `generate_keys` enlloc; `sign_update` només a `publica.sh`, i a la seva línia cap `-s`, `-f` ni `--ed-key-file` | 9 |

**Línies que estan fixades i s'han de vigilar en tocar l'app:** `ServeiArrencada.swift:18` (`GuardaTests:649,668`), `if case .real = arguments.carpeta {\n arrencada = …` (`:653`), `creaEntornRefresc` i `var refresc` (`:444-469`), la línia de `Desinstallacio(` (`:725-727`), `enTancarConfiguracio` i `enAmagar` (`:1919-1926`).

### 11. Documents

| Lloc | Canvi |
|---|---|
| `CLAUDE.md` | «Sense dependències externes» i llista de frameworks; estat; comandes; taula de rutes; `.build/debug/WarpLaunch`, si cal |
| `CLAUDE.md`, regla 3 | Publicar arriba sol a tots els Macs en un dia i no es desfà: secció 7. Sparkle crea una tasca temporal de `launchd` a cada instal·lació [L: `SUInstallerLauncher.m:278-285`], que no és un ítem d'inici |
| `CLAUDE.md`, nova | Cap agent no crea ni llegeix la clau EdDSA, ni executa `sign_update`, ni `publica.sh --aplica` (decisió 6) |
| `CLAUDE.md`, regla 4 | Una prova d'actualització reinicia l'app |
| `CLAUDE.md`, regla 10 | Sparkle, acordat, amb versió exacta |
| `CLAUDE.md`, regla 11 | Una migració arriba a tothom sense que ningú ho decideixi: cap canvi de format sense que la versió anterior en sàpiga llegir el resultat o recuperar la còpia |
| `README.md:45-46`, `:70` | Com s'actualitza, i «Per actualitzar-la» |
| `README.md:26`, `:30-32`, `:65`, `:107-132` | Connexió a internet: «GitHub veu la teva adreça IP i la versió de l'app». Encès de sèrie. Dues línies: Homebrew (secció 7) i diversos usuaris del Mac |
| `README.md:127-132` | «Signatura», amb EdDSA |
| `README.md:136`, `:159-163` | Dependències, «Tercers», llicència de Sparkle; «Desinstal·lar» |
| `Package.swift:4`, `WarpLaunchApp.swift:7-10`, `VistaConfiguracio.swift:5-6`, `Molla.swift:17`, `docs/disseny.md:88` | Comentaris: «no fa servir les preferències»: el codi propi no; Sparkle sí |
| `docs/especificacio.md` | Fila nova; les decisions 6 i 8 passen a fetes; pendents (`:172`) |
| `docs/disseny.md` | Secció nova amb això (rondes i secció 7). `:128`, `:158-172`, `:174-190`, `:396-474`, `:846`, `:1129`, `:1476-1480`, `:1531-1543`, `:2114-2119`, `:2127-2128` |
| `docs/fets-verificats.md` | Secció «Sparkle»; `:774-777` quan es provi |
| Tap | Recepta i el seu `README.md` |

### 12. Comprovat i per comprovar

**Provat per a aquest document (res obert, cap clauer, cap escriptura al repo ni a GitHub):**

| Què | Ordre | Resultat |
|---|---|---|
| Totes les crides i delegats de la secció 3.3 | `swift build -c release` d'un paquet de prova amb Sparkle 2.10.1, Swift 6, Command Line Tools | Compila |
| `responds(to:)` | Executar-lo (sense `NSApplication`) | 11 `true`, codi 0 |
| Inactivitat amb `import AppKit` | El mateix | `true`; sense diàleg |
| Verificar la signatura | `swift verifica-signatura.swift` | 0, 1, 1, 64 |
| Recepta | `gh api … Casks/warp-launch.rb`, lectura | Sense `auto_updates` |
| Sense flag, cap rpath al binari d'un sol target | `otool -l` | Cap `LC_RPATH` |

**Per comprovar:**

| Fet | Estat | Com | Si surt malament |
|---|---|---|---|
| macOS deixa `Autoupdate` substituir una app amb certificat propi, sense Team ID | [P] a B i C, al Mac de l'autor; la E no es fa | B, E | Decisió 11 |
| Gatekeeper no bloqueja la versió nova sense notaritzar | [P] a B i C, sense quarantena i cap diàleg; la E no es fa | B, E | Igual |
| «Comprova ara» amb `checkForUpdatesInBackground` no fa nosa | [P] a l'app de prova (A2, B2) | A2 | `checkForUpdateInformation` i «Actualitza ara» |
| `latest` torna a l'anterior | [S]; la F no es fa | F | Una versió superior; 1 dia de retard |
| Permís d'Arxius i carpetes i ítem d'inici | [P] a C6, al Mac de l'autor; la E no es fa | C6, E | README, fins al Developer ID |
| `.suppressed` i `openWindow` capturat | `.suppressed` [P] a C4; `openWindow` [S]: C5 no ho va veure | C4, C5 | `amagaEditorSiNoSHaFetServir` |
| L'app no es queda el focus (`NSApp.hide`) | [P] a C4 | C4 | Pujar `inactivitatMinima` |
| `secondsSinceLastEventType` dins de l'app | [P] a l'app de prova: puja (A12) i baixa en moure el ratolí (B) | A12, B | Treure `macEnUs`: decisió 2 |
| Instal·lar durant un reinici o un tancament de sessió | No se sap: la D no es fa | D | README: a la propera sortida |
| Altres usuaris amb sessió oberta | [S]; la E no es fa | E | README |
| Homebrew i Sparkle alhora | Sense provar | Porta 3 | README |
| Developer ID futur | [L] | Una ronda com la B | |

## 12. Multidioma (0.35)

La 1.0.0 surt en 10 llengües: ca, en, es, fr, de, it, pt-BR, ja, zh-Hans i ko, triades per l'autor (11/11/2026). Per defecte, la
del Mac; a la Configuració, un selector. La infraestructura (F1) és a la 0.34.1, sense cap canvi visible amb el Mac en català (en
una altra llengua, els menús de macOS passen a l'anglès: vegeu «La llengua de reserva»). De F1 a F6, al codi de la 0.35.0; falta
F7, la revisió visual de l'autor.

**Format.** `.lproj/Localizable.strings` i `Localizable.stringsdict` (plurals). `.xcstrings` no: compilar-lo demana
`xcstringstool`, que és d'Xcode, i el projecte es compila amb les Command Line Tools.

**On viuen.** Un sol recurs, `Sources/WarpLaunchCore/Textos/<llengua>.lproj/` (`resources: [.process("Textos")]`,
`defaultLocalization: "en"`), per a la UI, l'app, el CLI i les proves. La clau és el text en català, i `ca.lproj` els té tots
(clau = valor). SwiftPM en fa `WarpLaunch_WarpLaunchCore.bundle`, amb `Contents/Resources/<llengua>.lproj`.

**`t(_:)`** (`Idioma.swift`, l'únic fitxer que coneix el bundle). Rep un `String.LocalizationValue`: `t("Obre a Warp…")`,
`t("Obre \(nom) a Warp")` (clau «Obre %@ a Warp»), `t("\(n) finestres")` (clau «%lld finestres», amb el plural al
`.stringsdict`). A SwiftUI, `Text(t("…"))`, que no torna a traduir.
- Un enter s'escriu amb els milers de la llengua («1.000», «1,000»): un PID, un port o una versió s'interpolen com a text
  (`\(String(pid))`). Un `Double` surt amb 6 decimals: s'ha de formatar abans. Amb valors, un `%` del text va a la clau com a
  `%%`. Només s'hi poden interpolar textos, nombres i els tipus que accepta `LocalizationValue`.

**La cerca del bundle.** No es fa servir l'accessor de SwiftPM (`module`): si no troba el bundle, atura el programa, i un binari
copiat sol no el porta. `Idioma` el busca a `Bundle.main.resourceURL` (l'app: `Contents/Resources`, on el copia
`build-app.sh`), al costat de l'executable (el CLI, també per un enllaç), a `Bundle.main.bundleURL` i al costat del codi (les
proves: el `.xctest`). Si no el troba, `t` torna la clau, en català.

**La tria de la llengua.** Un bundle que no és el principal seguiria la llengua del principal, i el CLI i les proves, sense
`Info.plist`, sortirien sempre en anglès. Per això `Idioma` tria la llengua (`Bundle.preferredLocalizations(from:forPreferences:)`
amb les `.lproj` del bundle) i llegeix dins de la `.lproj` triada, com a bundle propi, amb el `locale` d'aquella llengua a cada
consulta: sense, els plurals i les xifres seguirien la regió del Mac («0 fenêtres» en lloc de «0 fenêtre»). Equivalències de
macOS: pt-PT → pt-BR, zh-CN → zh-Hans, es-MX → es; zh-TW, no. Per ordre: `Idioma.$fixada` (un `@TaskLocal` de producció, per
sobre de tot: el diagnòstic, en anglès), `Idioma.$deProva` (un altre, només a les proves), la variable `WARP_LAUNCH_IDIOMA` i
`Locale.preferredLanguages` (el Mac, o l'app amb el selector). La del procés no canvia mentre corre, com els menús de macOS.

**Les proves, en català.** `scripts/test.sh` exporta `WARP_LAUNCH_IDIOMA=ca`, i `IdiomaTests.lesProvesSonEnCatala` ho comprova:
amb `swift test` sol, falla. Per provar una altra llengua: `Idioma.$deProva.withValue("en") { … }`.

**La llengua de reserva: l'anglès** (decisió de l'autor). Si cap de les llengües preferides no té textos, `en`. A
`Recursos/Info.plist`, `CFBundleDevelopmentRegion = en` (abans, `ca`: amb el Mac en alemany, els menús de macOS sortien en
català). `CFBundleLocalizations` la posa `build-app.sh`, amb les `.lproj` dels textos i de `Recursos`.

**Guardes (`GuardaTests`, per a qualsevol nombre de `.lproj`):** les carpetes són de les 10 llengües, amb ca i en i els dos
fitxers; cada llengua té exactament les claus del català, també les del `.stringsdict`, sense claus repetides; els especificadors
coincideixen amb els del català (per posició, `%2$@` inclòs; una forma d'un plural pot no dir el nombre); cada plural té `other`, i
`one` fora de ja, zh-Hans i ko; cap valor buit; al català, valor = clau; i només `Idioma.swift` demana textos a un bundle. Des de
F2, també que cada `t("…")` del codi és al català (`cadaTextDelCodiEsAlCatala`): llegeix les crides com el compilador (els
escapaments, els textos de diverses línies sense el sagnat del final, el `%` doblat si hi ha valors) i, com que el tipus d'una
interpolació no surt del codi, n'hi ha prou que hi sigui una de les combinacions de `%@`, `%lld`, `%llu`, `%d` i `%lf`. Una mostra
en comprova la lectura (`laGuardaDelsTextosDelCodiFaLesClausComElCompilador`). Des de F3, a la interfície (`WarpLaunchUI` i
`WarpLaunchApp`) cap text no s'escriu directament (`capTextNoEsEscritDirectamentALaInterficie`, vegeu «F3»). Des de F4, els textos
de les ordres del menú de macOS són els de SwiftUI en cada llengua (`lesOrdresDelMenuDeMacOSEsDiuenIgualEnCadaLlengua`), cada
`.lproj` de `Recursos` és d'una llengua dels textos, i `UserDefaults` només és a `ServeiIdioma`, per a `AppleLanguages` (vegeu
«F4»).

**Fases:**

| Fase | Què | Versió |
|---|---|---|
| F1 | La infraestructura: `Idioma`, el bundle, les guardes, `test.sh`, `build-app.sh` i `Info.plist` | 0.34.1 |
| F2 | Els textos del Core (`WarpLaunchCore`: el CLI, els avisos, els errors…) amb `t`, i la guarda de F1 activada | 0.34.2 |
| F3 | Els de la UI i l'app (`Text`, `Button`, menús…), i el diagnòstic sencer en anglès | 0.34.3 |
| F4 | L'anglès complet, el selector a la Configuració (amb l'excepció per a `AppleLanguages`) i els `InfoPlist.strings` | 0.34.4 |
| F5 | Les 8 llengües restants, amb els noms de macOS 27 | 0.35.0 |
| F6 | Les amplades: una prova que mesura els textos amb `NSFont`; les comes i els parèntesis de cada llengua; una pseudolocalització | 0.35.0 |
| F7 | La revisió visual de l'autor | |

**Per a F2 i F3:** la guarda de les claus demana que `en.lproj` tingui totes les del català des del primer text: cada clau nova
hi va alhora. Fins a F4, qui no tingui el Mac en català veuria l'app barrejada, i des de F1 ja hi veu els menús de macOS en
anglès. Una variable local que es digui `t` (`{ t in … }`) amaga la funció dins del seu bloc.

**F2 (0.34.2): els textos del Core.** 341 claus noves (313 textos i 28 plurals) als dos `.lproj`, de 27 fitxers de
`WarpLaunchCore`: el CLI (`OrdreCLI`, `Informe`, `InformeObertura`, l'ajuda inclosa), el pla i el resultat d'obrir (`PlaObertura`,
`ExecucioObertura`, `LaunchConfigWarp`, `FitxersLaunchWarp`, `OrdreClaude`, `YAMLWarp`, `AppWarp`), la lectura i l'ajust de Warp
(`AjustRestauracio`, `LectorWarp`, `LectorSessions`, `Lector`, `LecturaWarp`), la configuració (`Configuracio`, `Validacio`,
`Importador`, els magatzems, `EstatApp`, `Preferencies`, `EdicioConfiguracio`), les actualitzacions (`PoliticaActualitzacions`) i
els noms de les ordres que també surten als textos (`WarpLaunch.ordreActualitzaEstat`, `ordreSobre`, `ordreSurt`). Els textos
del Core que només fa servir la UI, també (els motius de les actualitzacions, els noms dels esforços i dels modes de permisos).
Amb el Mac en una llengua que no sigui el català, el CLI ja surt en anglès, i l'app, barrejada fins a F3.
- **Frases senceres.** Cap tros enganxat amb `+`: cada variant és un text sencer (amb Claude o sense, `partiria` o no), i els
  `Plural.compta` i els `== 1 ?` del Core són plurals del `.stringsdict`, amb una variable per a cada xifra que fa canviar les
  paraules (en català o en anglès); les altres xifres, `%lld` sense plural. Una de sola es queda amb `== 1 ?`: la nota de la
  importació «a la mateixa carpeta hi ha «A», que queda / «A», «B», que queden només terminal», on el nombre no surt al text.
  `Plural.compta` es queda per a la UI (F3) i el diagnòstic.
- **Les cometes, les llistes i els decimals segueixen la llengua.** Un valor entre cometes que es compon a part és `t("«\(x)»")`
  («“%@”» en anglès); una enumeració, `Idioma.llista` (`ListFormatter`: «A, B i C», «A, B, and C»); els GB, amb el separador
  decimal de la llengua (`String(format:locale:)`). Un pid, un número de finestra, de pestanya o de línia i una versió, com a text.
- **Cap text en un `static let`:** es calcularia un sol cop, en la llengua del primer que el demana (a les proves, potser una altra
  que la del bloc de `Idioma.$deProva`). Els que en tenien un són `static var` calculades (`LecturaWarp.senseFinestres`,
  `WarpPreview.noCompatible`, `ExecucioObertura.finestraBuida`…).
- **El català, igual que abans,** excepte el singular quan la xifra és 1, que abans sortia en plural: «Warp: 1 finestra, 1
  pestanya de terminal» i «Finestra 2 · 1 pestanya» (`llegeix`), «1 recuperada de l'historial, 1 que ja no existeix»,
  «1 pestanya desada» (`avisFinestresAntigues`), «a 1 de 1 pestanya» (la finestra nova que no es reconeix) i «fa 1 byte». Tres
  proves han canviat per això (`LectorTests.carpetaQueJaNoExisteix`, `FotoFinestresTests.noQuadraSiLaBaseEsAntiga` i
  `OberturaTests.laMarcaAbansQueLaFinestra`). L'ajuda del CLI surt idèntica.
- **Proves en anglès:** `TextosEnAnglesTests` (un error, un avís amb plural, un pid, l'ajuda, `Idioma.llista`) i, a
  `OrdreCLITests`, el pla d'`obre` i `configuracio valida`, amb un error d'ús.

**Es queda en català o en anglès a propòsit:**
- el diagnòstic (`Diagnostic.swift`, en anglès per a les issues de GitHub), amb `PoliticaActualitzacions.NoDisponible.diagnostic` i
  `Actualitzacions.textDiagnostic`; des de F3, també els motius que pren del Core (`Idioma.fixada`, vegeu «F3»);
- `TaulaOpcionsClaude` i els noms d'opcions i de modes de Claude (`--settings`, `bypassPermissions`), també entre parèntesis al
  costat del nom traduït;
- el registre (`Registre`, `os.Logger`) i els motius per al registre (`IntentActualitzacio.Lectura.ignorat`), i les
  `precondition`;
- el que s'escriu en fitxers o el que llegeixen Warp o Claude: la marca `# warp-launch: temporal`, `entorn-claude.sh`, el YAML, les
  claus i els valors del JSON (també el del CLI amb `--json`: `"prova"`, `"repren"`), les variables d'entorn, el SQL i les rutes;
  el nom intern de la finestra del porta-retalls («Porta-retalls»);
- al CLI, les ordres, les opcions i el que s'hi escriu (`llegeix`, `--config`, `<warp.sqlite>`), el prefix `warp-launch:` dels
  errors, i «pid» i «URL:» davant del valor;
- els noms propis (Warp, Warp Launch, Claude Code, Opus…): a la interfície, amb `Text(verbatim:)` («Claude Code» de l'inspector,
  «Warp» del full d'obrir) o amb una constant (`ClaudePestanya.nomUltracode`, `Desinstallacio.nomAjustDeWarp`, l'ajust de Warp
  «Restore windows, tabs, and panes on startup», que es diu com el diu Warp, entre les cometes de la llengua).

Els noms per defecte es tradueixen («Finestra 3», «Pestanya 2», «Pestanya nova», «Finestra nova», «X còpia»): queden desats en la
llengua amb què es creen.

**F3 (0.34.3): els textos de la interfície.** 374 claus noves (346 textos i 28 plurals) als dos `.lproj`, de 27 fitxers de
`WarpLaunchUI` i `WarpLaunchApp` (i moltes que ja eren del Core, com «Obre a Warp…» o «%lld amb Claude (%@)»): el menú de la icona, l'alerta de sortir sense desar i els serveis (`WarpLaunchApp`,
`ServeiActualitzacions`, `ArrencadaSessio`); el model de l'editor (`Editor`, `EditorInspector`, `EditorOrdres`, `EditorPlantilla`:
el títol i el subtítol, l'inspector buit, les opcions, i tots els noms de Desfés); les vistes de l'editor i els menús
(`VistaEditor`, `VistaInspector`, `Ordres`); la Configuració, les actualitzacions i el permís (`VistaConfiguracio`,
`Actualitzacions`, `CopiaDiagnostic`, `Desinstallacio`, `ConsentimentRestauracio`, `VistaConsentiment`, `RefrescWarp`); i els fulls
(`FullObertura`, `Obertura`, `ObreTot`, `FullLligam`, `Lligam`, `FullImportacio`, `VistaImportacio`, `EstatWarp`,
`EstatSessions`). Amb el Mac en una llengua que no sigui el català, l'app ja surt sencera en anglès (fins a F5, les 8 llengües
restants també).
- **Com:** `Text(t("…"))`, `Button(t("…"))`, `Label(t("…"), systemImage:)`, `.help(t("…"))`, els noms de Desfés
  (`canvia(t("…"))`) i els textos del model. Amb un `String`, SwiftUI no torna a traduir. Els termes de macOS, en anglès
  («Settings…», «Login Items», «Move Up», «Move To», «Rename», «Multiple Values», «Quit Without Saving»); els menús que posa
  macOS no es dupliquen.
- **Frases senceres:** cap tros enganxat ni cap `Plural.compta` a la UI (ara només el fa servir el diagnòstic): «3 pestanyes ·
  3 amb Claude · 2 avisos», «Ara no: \(motiu.text)» (el motiu del Core a dins), «No s'ha pogut desactivar…: \(darrer)…», els
  tres errors de retirar el permís, «Substitueix el que hi ha ara (2 finestres i 4 pestanyes). Ara hi ha 3 pestanyes amb Claude
  i en quedarà 1: …» (quatre plurals en una clau), «Última comprovació: fa 3 dies», «2 de 3 · finestres 1, 2 i 4 de Warp». Les
  frases que s'afegeixen darrere d'una altra («motiu. Si no, tria…») són senceres totes dues. Les enumeracions, amb
  `Idioma.llista`.
- **Les dates i l'hora** de l'última comprovació, amb `Date.FormatStyle` en la llengua dels textos (en català, «dd/MM/yyyy» i
  «HH:mm», com abans; en anglès, «MM/dd/yyyy» i «09:45 AM»). Les tres escenes porten `.environment(\.locale, Idioma.locale)`.
- **Cap text en un `static let`** (`textPeuBase`, `textActualitzacions`, `titolConfirmacio`, `ErrorRetirada.haCanviat`, les notes de
  `RefrescWarp`, `warpRestaurara`, `textFeinesEnSegonPla`, `motiuNoEsPotLlegir`): `static var` calculades.
- **Un interruptor i el seu pas de Desfés** compartien la clau: «Salta els permisos» era «Skip permissions» als dos llocs (en
  anglès, «Undo Skip permissions»). Des de F4, no (vegeu «F4»).
- **El català, igual que abans,** excepte el singular amb 1, que abans no hi era: «En llegir el fitxer s'ha corregit 1 cosa»,
  «S'obrirà 1 finestra nova», «S'ha obert 1 finestra», «S'ha lligat 1 pestanya», «1 pestanya sense lligam potser ja és oberta a
  Warp: si ho és, …» i «Warp ja té 1 pestanya que l'app no reconeix (potser l'ha restaurat Warp…). Si obres, quedarà repetida:
  tanca-la…». Cap prova de la UI no ha canviat.
- **El diagnòstic, sencer en anglès** (decisió de l'autor): `Diagnostic.executa` compon l'informe dins d'`Idioma.$fixada` en
  anglès, i els motius del Core (els errors de `preferencies.json` i de `settings.toml`) hi surten en anglès, amb «(reason: …)» en
  lloc de «reason, in Catalan: «…»». L'anonimitzador també treu les rutes entre “”. Han canviat quatre proves de
  `DiagnosticTests`, que miraven el motiu en català o les rutes entre «» (`senseLaLiniaDiuElValorDeSerieIQueLAppLAfegeix`,
  `siLAppNoPotLlegirElFitxerEsUnError` i les dues de `lInformeAnonimitzat…`); `laFormaDelsNoms` també mira les “”, i n'hi ha una
  de nova (`elMotiuDelCoreSurtEnAngles`).
- **La guarda nova** (`capTextNoEsEscritDirectamentALaInterficie`): cap literal amb lletres que no passi per `t("…")` al títol
  (el primer argument, sense etiqueta) de les vistes de text (`Text`, `Button`, `Label`, `Section`, `Toggle`, `Picker`, `Menu`,
  `LabeledContent`, `TextField`, `DisclosureGroup`, `ContentUnavailableView`, `CommandMenu`, `Tab`, `Window`…, i `CampText` i
  `BotoCopia`), dels modificadors (`.help`, `.navigationTitle`, `.fileDialogMessage`, `.confirmationDialog`, `.alert`,
  `.accessibilityLabel`, `.addButton`…), dels arguments `value:`, `titol:`, `withTitle:`, `message:`, `prompt:`, `title:` i
  `description:`, ni del que s'assigna a `messageText` o `informativeText`. `Text(verbatim:)`, els comentaris, el que és dins d'un
  text i els literals sense lletres (`"\(a)\n\(b)"`) no hi compten. Amb la seva mostra
  (`laGuardaDelsTextosDeLaInterficieVeuElQueHaDeVeure`).
- **Guardes adaptades** al codi nou, amb el mateix que protegeixen: `laMateixaOrdreEsDiuIgualAlsDosMenus` i
  `elsBotonsDObrirNomesDemanenElFull` llegeixen el títol de `Button(t("…"))`; `Button(t("Accepta")) { consentiment.accepta() }`
  (dues), `Button(t("Restaura Warp i surt"), role: .destructive)`, `case .pestanyesNoves: t("Pestanyes noves")` i el peu de la
  plantilla, `LabeledContent(t("Versió")` i `Button(t("Mostra la finestra"))`. El motiu de l'app fora d'Aplicacions és a
  `ArrencadaSessio.motiuForaDAplicacions`: `ServeiArrencada` no importa el Core i la línia de `register()` no es mou.
- **Proves en anglès:** el subtítol amb plurals i els noms de Desfés (`elSubtitolIElNomDeDesfesEnAngles`), l'estat, el motiu
  d'esperar, l'ítem del menú i la data de les actualitzacions (`elTextDEsperaEnAngles`) i la pantalla del permís
  (`laPantallaDelPermisEnAngles`).

**F4 (0.34.4): el selector, l'anglès revisat i els menús de macOS.**
- **El selector** (decisió de l'autor): Configuració › General › «Idioma», després d'«En iniciar sessió». Un `Picker` («Idioma de
  l'app») amb «El del sistema (català)» (el nom, en la llengua de l'app, de la llengua que surt amb les preferències del Mac), un
  separador i les llengües de `Textos/*.lproj`, cadascuna amb el nom en ella mateixa i la primera lletra en majúscula
  (`Idioma.nomPropi`: «Català», «English», «Português (Brasil)», «简体中文»), per ordre alfabètic del nom. Una llengua nova hi
  surt sola. La tria es desa a `AppleLanguages` del domini de l'app (`[codi]`, o sense la clau per a la del sistema), que macOS
  llegeix en obrir l'app; si hi és, es marca (amb una regió, `en-GB`, o una llengua sense textos, la que surt). Si la tria canvia
  la llengua que es veu, la nota «L'idioma canviarà la propera vegada que obris l'app.»: l'app no es reinicia sola. La del Mac es
  llegeix al domini global, perquè `Locale.preferredLanguages` ja porta la de l'app. També amb una configuració de prova: la
  llengua és de l'app, no de la configuració. Sense identificador de paquet (l'executable sol), la secció no surt.
- **El model** (`SelectorIdioma`, a `WarpLaunchUI`): les opcions, què es desa i quina es marca, amb un entorn fals
  (`SelectorIdiomaTests`: sense la preferència, amb `en`, `en-GB` o `de`, desar i esborrar, la nota, les 10 llengües en ordre i
  l'anglès). Les preferències de debò, només a `ServeiIdioma` (`WarpLaunchApp`).
- **L'excepció de la guarda** (aprovada per l'autor): `UserDefaults`, prohibit a tot `Sources`, només a `ServeiIdioma.swift`, i
  només amb les quatre línies fixades (llegir la de l'app i la del Mac, desar-la i esborrar-la), amb `clau = "AppleLanguages"`
  com a únic text del fitxer; `CFPreferences`, prohibit a tot arreu. La mostra demostra que la guarda falla amb `UserDefaults` en
  un altre fitxer (també en un comentari) i, al servei, amb una altra clau, una altra variable, una altra crida, la mateixa dues
  vegades, `CFPreferences` o `@AppStorage` (`nomesElServeiDIdiomaFaServirLesPreferencies`).
- **El pas de Desfés d'un interruptor ja no comparteix la clau amb l'etiqueta:** és una ordre, com «Activa Claude» i «Activa
  l'ultracode»: «Activa «Salta els permisos»» i «Desactiva «Continua la conversa»» (en anglès, «Undo Turn On Skip Permissions»).
  Les etiquetes no canvien. Les claus «No saltis els permisos» i «No continuïs la conversa» ja no hi són.
- **L'anglès, revisat sencer.** Termes de macOS 27, llegits a les seves taules (`LoginItems.appex`,
  `SecurityPrivacyExtension.appex`, `TCC.framework`): «Login Items & Extensions» (el tauler, al botó, al peu i als errors) i «login
  items» (la llista, en minúscula); «Settings…», «About Warp Launch», «Quit Warp Launch» i «File», els del menú de SwiftUI.
  Majúscules a cada paraula als ítems de menú, als botons, als títols i a les capçaleres («Will Open (3)», «Already Open (3): won't
  open», «To Review (3)», «Others (3)», «Why It's Needed», «Warnings While Reading», «Claude Code in 3 Tabs»); només la primera a
  les etiquetes, als interruptors, a les descripcions i a les ajudes. Coherència: «Claude sessions» (no «Claudes»), «click» (no
  «press»), «in Finder», i les ajudes diuen què fa el control. Es queden, revisades: «Needs Review», «Link with Warp…» (curt i
  coherent amb «linked» i «unlinked»; el full explica què fa) i «Start from Scratch». `TextosEnAnglesTests.elsTermesDeMacOSIElsDeLApp`
  en fixa una mostra.
- **`Recursos/en.lproj/InfoPlist.strings`,** com el català: el nom del paquet als menús que posa macOS. La guarda mira que cada
  `.lproj` de `Recursos` sigui d'una llengua dels textos i digui «Warp Launch».
- **Els menús de macOS, en cada llengua** (`lesOrdresDelMenuDeMacOSEsDiuenIgualEnCadaLlengua`): «Sobre» i «Surt» (menú de la icona
  i pantalla del permís), «Configuració…» i «Arxiu ›» de l'avís del full d'obrir diuen exactament el que diu `MainMenu.loctable` de
  SwiftUI per a cada llengua dels textos (`pt_BR`, `zh_CN`). Sense la taula (una altra versió de macOS), els valors fixos del català
  i de l'anglès, que, amb la taula, han de ser els seus. `laMateixaOrdreEsDiuIgualAlsDosMenus` també ho mira en anglès.
- **El README, en anglès** (`README.md`), traduït sencer amb els noms de la interfície en anglès i les dates sense ambigüitat
  («November 11, 2026»); el català, a `README.ca.md`, i a dalt de cadascun l'enllaç a l'altre. La guarda de les feines en segon
  pla mira la frase a tots dos, i `elReadmeEsEnAnglesIEnCatala`, els enllaços i que tinguin les mateixes seccions.

**Per a F5 i després:** els textos del Core que la UI compara o en què busca (`.contains`) han de ser les claus, no el text
traduït: avui no n'hi ha cap.

**F5 (a la 0.35.0): les 8 llengües restants.** es, fr, de, it, pt-BR, ja, zh-Hans i ko, cadascuna amb els 666 textos i els 57
plurals del català d'aleshores, i el seu `Recursos/<llengua>.lproj/InfoPlist.strings`. Els plurals, amb les categories de CLDR: `one` i
`other` en alemany; `one`, `many` i `other` en castellà, francès, italià i portuguès (en francès i en portuguès, el 0 va amb `one`);
i només `other` en japonès, xinès i coreà. Les frases on la llengua canvia l'ordre fan servir posicions (`%2$#@p@`, `%1$lld`).
- **Els noms de macOS són els de les taules del sistema de macOS 27,** llegits en cada llengua: el menú de SwiftUI
  (`MainMenu.loctable`: «Über „%@“», «Acerca de %@», «%@について», «设置…», l'«Arxiu» de cada llengua: «Ablage», «Archivo»,
  «ファイル»), Configuració del Sistema i els seus taulers (`LoginItems.appex`, `GeneralSettings.appex`,
  `SecurityPrivacyExtension.appex`: «Anmeldeobjekte & Erweiterungen», «Ouverture et extensions», «ログイン項目と機能拡張»,
  «登录项与扩展»), el Desfés de Foundation (`Undo.loctable`), AppKit («Mehrere Werte», «複数の値») i el Finder («Papierkorb»,
  «Corbeille»). La guarda dels menús (`lesOrdresDelMenuDeMacOSEsDiuenIgualEnCadaLlengua`) compara cada llengua amb
  `MainMenu.loctable` (`pt_BR`, `zh_CN`).
- **El català** diu «Ítems d’inici de sessió i extensions», com macOS 15 i posteriors (`LoginItems.appex`; abans, «Ítems d’inici
  de sessió»).
- **Decisions de l'agent integrador, totes com macOS:** en francès, l'espai que no es parteix (U+00A0) davant de «:», «;», «?» i
  «!», dins de «« »» i entre una xifra i la unitat (abans, en alguns llocs, l'espai fi, U+202F); en japonès, les cometes
  “” (abans, 「」); en alemany, el tracte de «du», el de macOS 27 (`LoginItems.appex`, TCC, AppKit).
- Com macOS en cada llengua: en portuguès del Brasil, majúscula a cada paraula als menús, als botons i als títols («Abrir Tudo no
  Warp…»); en italià, una pestanya és un «pannello», com al Terminal i al Safari; en coreà, el registre formal (-습니다).

**F6 (0.35.0): les amplades, les comes i la pseudollengua.**
- **La prova** (`AmpladesTests`, a les proves de la UI): en cada llengua (`Idioma.$deProva`), mesura amb `NSFont.systemFont` i
  CoreText (amb les lletres de reserva del japonès, el xinès i el coreà: «ウインドウ12 のコピー» fa 128,3 pt, i a SwiftUI, 128,5) els
  textos dels llocs d'amplada fixa, i els compara amb l'espai que hi ha. No obre l'app ni crea cap vista. Si un no hi cap, diu la
  llengua, el lloc, la clau (en català), el text traduït, el que fa i el que hi ha: «de: Inspector, mode de permisos, clau «Mode de
  permisos»: «Berechtigungsmodus» fa 128.8 pt al costat d'un desplegable de 333.2 pt, i en una fila de 280.0 pt n'hi caben 123.2
  en una línia». Tres regles: una línia (les peces d'una fila, sense partir-se ni encongir-se), fins a `n` línies (el detall d'una
  fila, un subtítol, una nota) i l'etiqueta d'un `Picker` amb un desplegable que no hi cap. `lesReglesDeMesura` les prova.
- **Les mides de SwiftUI** (`Mides`), mesurades el 12/11/2026 a macOS 27.2 amb un programa a part que dibuixa les vistes sense
  mostrar cap finestra (els marcs amb `onGeometryChange` i, per a les etiquetes, l'amplada on passen a dues línies): un `Form`
  agrupat deixa 30 pt per banda (a l'inspector, 20); entre l'etiqueta i un botó o un menú, 12 pt (i un valor de text, 20,5; un
  desplegable, 24); un botó fa el text i 24,5 pt; un botó amb menú, 48,5; un desplegable, l'opció més ampla i 48; una casella,
  23,5; un interruptor petit, 48,5; un camp de text deixa a l'etiqueta la meitat de la fila. Amb un desplegable que no hi cap,
  SwiftUI l'encongeix (en talla l'opció triada) i l'etiqueta fa una línia fins al 44 % de la fila (es parteix a 108, 117, 126,5,
  145, 173 i 207 pt en files de 240, 260, 280, 320, 380 i 460). Les capçaleres de secció, en 13 pt seminegreta; els subtítols i els
  peus, en 11.
- **Els llocs** (99, la taula és a la prova, i cada amplada surt de la seva vista: `VistaConfiguracio.amplada`,
  `VistaEditor.inspectorMinim`, `FullObertura.amplada`…):
  - la Configuració (520 pt): les capçaleres; els interruptors; l'avís dels ítems d'inici (fins a dues línies) i el seu botó;
    «Idioma de l'app» amb les 10 llengües i la del sistema; «Informe per a una issue a GitHub» i el subtítol de «Copiat (…)» amb
    «Copia el diagnòstic»; «Torna a deixar Warp com era» amb «Restaura Warp i surt…»; «Estat» amb el botó més ample de les
    actualitzacions («Reinicia i actualitza»); i, a «Pestanyes noves», els tres desplegables sencers, també «Sense cap permís
    (bypassPermissions)»;
  - l'inspector, a l'amplada mínima: les capçaleres, les caselles («Obre Claude Code en aquesta pestanya»), els botons («Treu el
    mode de permisos»), les etiquetes dels camps de text, «Model» i «Esforç» amb «Valors diversos», sencers, i «Mode de permisos»
    en una línia;
  - els fulls d'obrir i de lligar (600 pt) i d'importar (560): les capçaleres («Sense parella (12): s'obriran si n'obres la
    finestra»), els `DisclosureGroup`, el detall de cada pestanya a la dreta (fins a dues línies) i els botons del peu
    («Actualitza l'estat de Warp», «Cancel·la» i «Substitueix»); i la pantalla del permís (560): el títol, en una línia, i els botons;
  - la barra lateral (180 pt): «Per revisar» amb una insígnia de dues xifres, la capçalera i «Prova: …» (`lineLimit(1)`); els noms
    que posa l'app («Finestra nova», «Finestra 3»), a l'amplada ideal (220): a la mínima, es tallen com qualsevol nom llarg;
  - la fila d'una pestanya (`lineLimit(1)`), amb la finestra a la mida per defecte (900 pt): el nom («Pestanya nova»,
    «warp-launch») i el resum de Claude («Sonnet · Molt alt · Ultracode»), sense tallar-se.
  - No s'hi mesuren, i la prova diu per què: els noms de l'usuari i el de les còpies («X còpia»), la línia de sota de la fila d'una
    pestanya (la carpeta o l'avís, en 11 pt: es talla pel mig, i l'avís sencer és a l'ajuda i a l'inspector), les notes i els peus
    que ja fan diverses línies, i els menús.
- **Què no hi cabia, i com s'ha arreglat** (el català i l'anglès, igual que abans):
  - en totes les llengües, també en català, a l'inspector de 280 pt: «Obre Claude Code en aquesta pestanya» (en català, 263,5 pt de
    240) i «Mode de permisos» al costat del desplegable (112,2 de 108). Disseny: l'inspector, de 320 pt com a mínim;
  - en totes, a la Configuració, l'avís dels ítems d'inici amb el botó al costat (289 pt en català): l'avís feia tres línies i el
    botó quedava tallat. Disseny: el botó, a sota;
  - alemany: «Berechtigungsmodus» (128,8 pt de 123,2 a l'inspector; i a «Pestanyes noves», amb «Berechtigungen umgehen
    (bypassPermissions)», 486 de 460) passa a «Berechtigungen»; el títol del permís, «Warp Launch muss eine Einstellung von Warp
    deaktivieren» (472 de 454), a «… eine Warp-Einstellung deaktivieren»;
  - francès: «Mode d’autorisations» (126,9) passa a «Mode d’autorisation», i les altres tres frases del mode, igual;
  - italià: «Modalità dei permessi» (132,8) passa a «Modalità permessi», i les altres tres, igual;
  - portuguès del Brasil: «Modo de permissões» (126,4) passa a «Modo de permissão», i les altres tres, igual;
  - castellà, japonès, xinès i coreà: res, amb l'inspector de 320 (a 280, el castellà i l'italià tampoc no hi cabien a «Nom de la
    sessió»).
- **Els canvis de disseny** (cap amplada no creix més de 40 pt):
  - l'inspector, de 280 a 320 pt com a mínim (`VistaEditor.inspectorMinim`). És la seva amplada ideal, que no canvia: s'obre igual,
    però ja no es pot fer més estret;
  - la finestra de l'editor, de 640 a 680 pt com a mínim (`VistaEditor.ampladaMinima`): amb la barra lateral (180) i l'inspector
    (320), la llista conserva els 180 pt d'abans;
  - a la Configuració, sense el permís de macOS per als ítems d'inici, l'avís i, a sota, el botó «Mostra Ítems d’inici de sessió i
    extensions…» (un `VStack`), en lloc d'una fila.
- **Les comes i els parèntesis de cada llengua** (`SeparadorsTests`):
  - «6 amb Claude (4 reprenen la seva conversa, 2 en comencen una de nova)» (`XifresObertura.text`): la coma era `", "` al codi, i
    en japonès i en xinès hi sortia una coma occidental. Ara és una frase sencera (clau nova, amb dos plurals), amb «、» en japonès
    i «，» en xinès;
  - les enumeracions que s'unien amb `", "`, amb `Idioma.llista`: els terminals de la mateixa carpeta d'una sessió sense pestanya
    (`NotaImportacio`), les opcions de Claude i els modes de permisos que existeixen (`Validacio`), els números de les finestres que
    es diuen igual (`warp-launch obre`) i, a `warp-launch llegeix`, els tipus de sessions en segon pla i les notes d'un pane. En
    català, ««A» i «B»» en lloc de ««A», «B»»: quatre proves han canviat;
  - el «; » d'aquesta nota i el parèntesi de «24 només terminal (18 sense Claude obert)», dins de la frase (claus noves): en francès,
    amb U+00A0 davant del «;»; en japonès, «。» i el «（）» sense l'espai d'abans;
  - el nom d'un mode amb el de Claude («Sense cap permís (bypassPermissions)») i, al CLI, una ruta amb les seves notes: «%@ (%@)»,
    amb «（）» en japonès i en xinès, i sense l'espai en coreà;
  - dues frases seguides, amb `Idioma.frases`: un espai, excepte en japonès i en xinès, que no en posen (18 llocs, abans `" "`);
  - es queden: « · », que macOS fa servir igual en totes les llengües (35 textos de `FindMy.app` i els de Mail, Books, Podcasts i
    Maps, amb « · » també en japonès, xinès i coreà, a les taules de macOS 27.2), «›» entre la finestra i la pestanya, i «ruta:
    error» als errors del CLI.
- **La pseudollengua** (`PseudollenguaTests`): una llengua falsa feta del català, en un paquet de textos temporal: cada text entre
  ⟦…⟧, un 40 % més llarg, i amb totes les lletres i els signes «,;:()«»“”» canviats per uns altres que s'hi assemblen; els
  especificadors, igual. S'activa amb un `@TaskLocal` (`Idioma.textosDeProva`, només a les proves; les llistes, amb les del
  japonès). Amb aquesta llengua, 23 frases del Core no han de tenir cap lletra llatina ni cap d'aquests signes fora del que ve dels
  valors i dels noms propis: el que no passa per `t(_:)` es veu. Amb el codi d'abans, hauria trobat la coma de `XifresObertura`, el
  «; » i les comes de la nota de la importació i el parèntesi de `nomMode`. La guarda `nomesLesProvesCanvienLaLlenguaOElsTextos`:
  al codi, només el diagnòstic fixa la llengua.
- Ara, 667 textos i 58 plurals.

**Per a F7, la revisió de l'autor a l'app** (cada llengua, amb el selector de la Configuració, i l'app tornada a obrir):
- en alemany, francès, italià i portuguès, l'inspector a l'amplada mínima: «Mode de permisos» en una línia al costat del
  desplegable (que talla «Sense cap permís (bypassPermissions)» si és el triat), i la casella «Obre Claude Code en aquesta pestanya»;
- en alemany, Configuració › Pestanyes noves («Berechtigungen» amb el desplegable sencer) i la pantalla del permís (el títol);
- en japonès i en xinès, el full d'obrir amb converses que es reprenen i noves («、», «，»), el full d'importar i les notes;
- en francès, la barra lateral a 180 pt («Nouvelle fenêtre» amb insígnia es talla, i a 220 no);
- en qualsevol llengua, la finestra de l'editor a la seva mida mínima (680 pt) amb l'inspector obert, i, si es pot provocar,
  l'avís dels ítems d'inici sense el permís de macOS (el botó, a sota). Les mides de la prova són d'un programa a part: si a la
  pantalla alguna cosa no quadra, es corregeix `Mides`.
