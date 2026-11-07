---
name: mac-design
description: Normes de disseny perquè l'editor de Warp Launch sembli una app nativa de macOS 26 (SwiftUI) — principis d'Apple, Liquid Glass, barra lateral, inspector, barra d'eines, menús, teclat, tipografia, color, mode fosc i arrossegar. Fes-la servir quan dissenyis, construeixis o revisis una finestra, una barra lateral, un inspector, una barra d'eines, un menú o la Configuració de l'app.
---

# Disseny d'app de Mac

Adaptada de la skill `mac-design` de BAMA ([daveebbelaar/bama](https://github.com/daveebbelaar/bama), commit
`639893c`, 01/11/2026, llicència MIT a [LICENSE-BAMA](LICENSE-BAMA)). Els fitxers de referència són els originals
en anglès, amb una nota a dalt que diu què s'ha tret o canviat. Les decisions pròpies de Warp Launch són a
**`docs/disseny.md`**, i manen sobre aquesta skill.

**Què s'ha tret de l'original,** perquè ho prohibeix `CLAUDE.md` o perquè no hi és:
- `scripts/hig.sh` (baixava les HIG de la xarxa i escrivia a `~/Library/Caches`). Si cal el text d'Apple, demana'l.
- El «snapshot mode», el «self-test» i qualsevol pas que obri l'app, en faci captures o la tanqui. **La revisió
  visual la fa en David, o es fa amb el seu OK per a cada prova** (regla 4).
- Les referències a la plantilla `new-mac-app` i a les altres skills de BAMA (`design-system`, `ux-design`,
  `layout-grid`, `design-kit`, `swift-swiftui`): aquí no hi són.
- A `patterns.md`: drecera global, panell de captura, Services, arrossegar cap al Finder, notificacions,
  `@AppStorage` i SQLite compartida.

Fitxers:
- [design-rules.md](design-rules.md): les 80 regles amb fonts, per revisar.
- [patterns.md](patterns.md): codi SwiftUI per adaptar (no copiar a cegues: no tenim plantilla ni SwiftData).
- [toolbars.md](toolbars.md): quin botó va a cada columna.
- [menus.md](menus.md): ordre i noms dels menús, menús contextuals.
- [settings.md](settings.md): la finestra de Configuració.

## Els vuit principis d'Apple

Fes-los servir per revisar cada pantalla (HIG, Design principles, 2026):

1. **Propòsit:** cada funció costa temps, atenció i confiança. Treu el que no s'ho guanya.
2. **Agència:** la persona tria el camí. Desfés perdona els errors.
3. **Responsabilitat:** dades privades, permisos quan calen.
4. **Familiaritat:** el que s'assembla funciona igual. Peces i símbols estàndard.
5. **Flexibilitat:** teclat, ratolí i canvis de mida funcionen.
6. **Simplicitat:** simple no és mínim. La jerarquia surt de l'ordre, l'espai i el contrast.
7. **Ofici:** resposta immediata, vores alineades, disposicions que aguanten el canvi de mida.
8. **Plaer:** la suma dels altres set, cap a una sola sensació. Mai decoració afegida al final.

Cada pantalla respon: on soc?, què puc fer?, on puc anar?

## Warp Launch: l'arquetip

**Extra de barra de menú + finestra d'editor + Configuració.** L'app és `LSUIElement`: viu a la barra de menú, i
només surt al Dock i a ⌘⇥ mentre l'editor o la Configuració són oberts. Les entrades són la icona de la barra de
menú i obrir l'app des d'Apps o del Finder (R11). **Res de dreceres globals, panells flotants ni menú del Dock.**

La sensació que busquem: **tranquil·litat i control.** Tot el que obre Warp o Claude es confirma amb xifres; tot
el que només edita la configuració es fa a l'instant i es desfà amb ⌘Z.

## Disposició

- `NavigationSplitView`: barra lateral (finestres de Warp), llista (pestanyes) i `.inspector` (propietats).
- Accions globals a la barra d'eines, sobre la columna on actuen ([toolbars.md](toolbars.md)).
- Pàgina buida: un `ContentUnavailableView` amb la primera acció.
- Espais en múltiples de 4 pt: 20 pt de marge de finestra, 8 pt entre controls relacionats, 20 pt entre grups.
  `.controlSize` per a zones denses, mai alçades fixes.

## Liquid Glass

- El vidre és de la capa de navegació i control (barres, barra lateral, popovers). El contingut (files) no en porta.
- Mai vidre sobre vidre. Les peces estàndard ja porten vidre: treu els fons propis darrere de barres i fulls.

## Barra d'eines i menús

- Com a màxim tres grups, separats amb `ToolbarSpacer`. SF Symbols monocroms, cada un amb títol i `.help`.
- `SidebarCommands()`, `ToolbarCommands()` i `InspectorCommands()` a `.commands`.
- Cada botó de la barra d'eines també és a la barra de menús. Ordre i noms: [menus.md](menus.md).
- Les dreceres estàndard mantenen el significat: ⌘C, V, X, Z, W, Q, N i coma.
- Les ordres que no s'apliquen surten desactivades al menú (visibles), i amagades al menú contextual.
- El títol de la finestra diu el contingut (la finestra de Warp seleccionada), no el nom de l'app.

## Finestres que s'obren tranquil·les

- Cap focus en obrir una finestra o un full: ni anell, ni cursor, ni text seleccionat. La llista de la barra
  lateral pot tenir el focus (es veu com a fila seleccionada).
- Fulls i Configuració s'ajusten al contingut, i només es desplacen si són més alts que unes 640 pt.

## Primer el teclat

- Retorn és l'acció per defecte, Escapada cancel·la, Suprimeix esborra, les fletxes es mouen.
- Un element nou rep el focus perquè es pugui escriure de seguida.

## Color, tipus i mode fosc

- Text `.primary`, `.secondary`, `.tertiary`. Fons del sistema. Cap blanc, negre o gris fix.
- Un sol color d'accent. Un color d'estat sempre va amb icona o paraula.
- Estils de text de macOS: cos de 13 pt, res per sota de 10 pt.
- `Label` per a icona i text, SF Symbols per a totes les icones.

## Interacció

- `.contextMenu` a tot el que es pot fer servir. Amaga el que no s'aplica i no mostra dreceres.
- Controls de Mac de 22 a 28 pt d'alt, no 44.
- **Arrossegar només dins de l'app,** amb un tipus `Transferable` i un UTType propis (mai text pla: es podria
  enganxar al prompt d'un terminal de Warp). Sempre amb l'alternativa «Mou a ▸» al menú.
- Desfés per a tota acció destructiva o de grup.
- Configuració a l'escena `Settings`, amb ⌘,.
- Respecta «Redueix el moviment» i «Redueix la transparència». Etiqueta els botons que només tenen icona.

## Revisió

Llista per a en David, o per a un agent amb el seu OK explícit, amb l'app oberta en clar i en fosc: cada
pàgina, el menú de la icona, cada full i la Configuració. Busca anells de focus, text seleccionat, barres de
desplaçament sense res a desplaçar i franges buides sota contingut curt.

Està fet quan totes les regles de [design-rules.md](design-rules.md) es compleixen, o tenen un comentari que
diu per què no (o la desviació és a `docs/disseny.md`).
