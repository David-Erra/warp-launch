---
name: app-icon
description: Icona de Warp Launch per a macOS 26. El dibuix es fa amb codi (scripts/icona-dibuixa.swift; nano-banana és l'alternativa), en capes d'un fitxer d'Icon Composer (Recursos/AppIcon.icon), es compila amb actool i es revisa amb ictool en tots els aspectes (clar, fosc, tenyit i transparent). Fes-la servir quan calgui crear o canviar la icona de l'app.
allowed-tools: Bash(scripts/genera-imatge.sh *) Bash(scripts/icona-compila.sh *) Bash(scripts/icona-revisa.sh *) Bash(swift scripts/icona-capa.swift *) Bash(swift scripts/icona-dibuixa.swift *) Read Edit Write
---

# Icona de l'app

Adaptada de la skill `app-icon` de BAMA ([daveebbelaar/bama](https://github.com/daveebbelaar/bama), commit
`639893c`, 01/11/2026, llicència MIT a [LICENSE-BAMA](LICENSE-BAMA)). Canvis respecte de l'original:

- El dibuix de cada capa es fa **amb codi**, amb `scripts/icona-dibuixa.swift` (decisió d'en David, 06/11/2026), no a mà en SVG.
  El 03/11/2026 s'havia previst amb **nano-banana**, que queda com a alternativa (pas 2).
- Rutes i scripts d'aquest repo. Els scripts `icona-compila.sh`, `icona-revisa.sh` i `icona-full.swift` adapten
  els de la plantilla `new-mac-app` de BAMA. `icona-capa.swift` és nou.
- Les eines d'Xcode es criden amb `DEVELOPER_DIR`, perquè `xcode-select` apunta a les Command Line Tools. La
  primera vegada, Xcode demana `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch`:
  ho executa en David.
- **S'ha tret el pas que instal·lava l'app, l'obria i reiniciava el Dock** (`build.sh --open`, `osascript`,
  `killall Dock`). Ho prohibeixen les regles 2–4 de `CLAUDE.md`.

La icona és un fitxer d'Icon Composer dins del repo: la carpeta `Recursos/AppIcon.icon/`, amb `icon.json` i les
capes a `Assets/`. **macOS hi afegeix el vidre, les llums, l'ombra, la forma arrodonida i els aspectes fosc,
tenyit i transparent: no els dibuixis mai.**

## Eines

| Ordre | Què fa |
|---|---|
| `scripts/genera-imatge.sh "<prompt>" <sortida.png>` | Imatge amb nano-banana. Cal `GEMINI_API_KEY` a l'entorn; cada imatge es paga. |
| `swift scripts/icona-dibuixa.swift [carpeta]` | Dibuixa les capes actuals (finestres en cascada) a `Recursos/AppIcon.icon/Assets/`. Sense cost. |
| `swift scripts/icona-capa.swift <entrada.png> <capa.png>` | Converteix una figura blanca sobre fons negre en una capa blanca amb transparència, de 1024 × 1024. Diu quina amplada ocupa la figura. |
| `scripts/icona-compila.sh` | Compila amb `actool` a `Recursos/Assets.car` (macOS 26) i `Recursos/AppIcon.icns` (reserva). |
| `scripts/icona-revisa.sh` | Dibuixa amb `ictool` una làmina a `build/icona-revisio.png`: clar, fosc, tenyit i transparent a 256 pt, i clar a 32 i 16 pt. |
| `scripts/build-app.sh` | Copia `Assets.car` i `AppIcon.icns` al `.app`. `Info.plist` porta `CFBundleIconName` = `AppIcon`. |

## El fitxer

```text
Recursos/AppIcon.icon/
  icon.json
  Assets/principal.png    1024 × 1024, la mateixa mida que la icona
  Assets/fons.png
```

```json
{
  "fill" : { "automatic-gradient" : "srgb:0.20000,0.42000,0.96000,1.00000" },
  "groups" : [
    {
      "layers" : [
        { "glass" : true, "image-name" : "principal.png", "name" : "principal" },
        { "glass" : true, "image-name" : "fons.png", "name" : "fons", "opacity" : 0.6 }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
```

- `fill` és el fons: `solid`, `automatic-gradient` (un color; el sistema hi posa un degradat suau) o
  `linear-gradient` amb dos colors. Els colors són `srgb:r,g,b,a` o `display-p3:r,g,b,a`.
- La primera capa de la llista és la de dalt.
- `shadow.kind`: `neutral`, `layer-color` o `none`.
- Un aspecte diferent per a cada mode va a `<clau>-specializations`. Per exemple, `fill-specializations` amb una
  entrada per a `dark`, o `image-name-specializations` amb un fitxer per a `dark`.
- Per canviar la mida de la figura sense tornar-la a generar: `"position": {"scale": 1.1, "translation-in-points": [0, 0]}`
  al grup.
- Capes en PNG o SVG. **Les capes en PDF no es dibuixen.**

## Què la fa semblar d'Apple

1. **Una sola idea:** un objecte que digui què fa l'app.
2. **Sense text,** ni lletres, ni captures de la interfície.
3. **El dibuix és propi.** No facis servir cap SF Symbol ni res que s'hi assembli: la llicència dels SF
   Symbols ho prohibeix a les icones d'app.
4. **No imitis el logotip de Warp, ni el de Claude, ni cap altra marca.**
5. **Dues o tres capes,** cadascuna una forma plana blanca. El vidre dona la profunditat. La forma principal va
   a dalt, i una de més suau al darrere.
6. **La figura principal ocupa entre el 45 i el 55 % de l'amplada.** Les parts primes desapareixen a 16 px.
7. **Formes plenes,** sense contorns.
8. **Un sol to de fons.** `automatic-gradient` gairebé sempre queda bé.
9. **Ha de ser diferent de les icones que té al costat al Dock:**
   `defaults read com.apple.dock persistent-apps | grep file-label`. El 03/11/2026 hi havia, entre d'altres, Warp,
   Claude, VS Code i les apps del sistema.

## Passos

1. **Tres conceptes,** una línia cadascun: l'objecte, el color de fons i les capes. En David en tria un.

   Comprova que cap no fa servir un SF Symbol, text ni el logotip de ningú.

2. **Dibuix amb codi (Warp Launch, des del 06/11/2026).** En David va triar dibuixar la icona amb codi quan nano-banana
   va deixar de tenir crèdit (402). Les capes actuals surten de `swift scripts/icona-dibuixa.swift` (CoreGraphics, sense
   cost): per canviar el dibuix, canvia'n la geometria (constants a dalt de l'script), torna'l a executar i segueix
   pel pas 3. Si mai es torna a fer amb nano-banana, aquest és el camí:

   **Genera cada capa amb nano-banana:** una crida per capa, a `build/icona/<capa>-original.png`. Per exemple:

   ```text
   A single flat solid white silhouette of <objecte>, centered on a pure black (#000000) square background.
   The shape is about half the width of the image. Flat 2D shape only: no gradients, no shading, no outlines,
   no texture, no text, no shadow, no 3D, no rounded square, no tile, no border.
   ```

   Després, converteix-la en capa:

   ```bash
   swift scripts/icona-capa.swift build/icona/principal-original.png Recursos/AppIcon.icon/Assets/principal.png
   # Recursos/AppIcon.icon/Assets/principal.png: figura del 52 % de l'amplada, centrada a (512, 508)
   ```

   - Comprova que la figura ocupa entre el 45 i el 55 % (la principal) i mira-la amb Read: no hi ha d'haver
     grisos estranys ni restes del fons.
   - Apunta el concepte i el prompt de cada capa a `docs/disseny.md` (secció 4, pas 12), perquè es pugui tornar a generar.
   - **Cada crida es paga:** torna a generar una capa només si cal canviar el dibuix.

3. **Escriu `icon.json`** amb les capes, i esborra les que no facis servir.

   Comprova que cada `image-name` té el seu fitxer a `Assets/`.

4. **Compila:** `scripts/icona-compila.sh`.

   Comprova que escriu `Recursos/Assets.car` i `Recursos/AppIcon.icns`. Si hi ha un error, corregeix el fitxer que diu.

5. **Revisa tots els aspectes:** `scripts/icona-revisa.sh` i llegeix `build/icona-revisio.png`.

   La figura s'ha de llegir en els quatre aspectes i encara s'ha de reconèixer a 16 pt. Si no, fes-la més gran,
   més gruixuda o més senzilla.

6. **Itera dues o tres vegades,** amb un sol canvi per ronda: la mida (`position.scale`), l'opacitat d'una capa
   o el color de fons.

7. **Empaqueta:** `scripts/build-app.sh`.
   - **No instal·lis l'app, no l'obris i no reiniciïs el Dock:** ho fa en David (regles 3 i 4).
   - Ensenya-li la làmina.
   - macOS guarda les icones en memòria cau. Si en David veu la icona antiga, és normal.

En David la pot retocar a mà amb Icon Composer, que ve amb Xcode. Després cal tornar a executar
`scripts/icona-compila.sh`.

## Trampes

- La carpeta s'ha de dir `AppIcon.icon`. Amb un altre nom, `actool` no escriu res i acaba igualment amb 0.
  `icona-compila.sh` ho comprova.
- **Si falta una capa,** `actool` falla i diu quina, però `ictool` acaba amb 0 i dibuixa un fons buit. Compila
  sempre abans de revisar.
- `xcrun ictool` és una altra eina. El d'Icon Composer és a
  `$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool`.
- La icona necessita `CFBundleIconName` = `AppIcon` a `Info.plist` i `Assets.car` a `Contents/Resources`.
  `AppIcon.icns` és per a les vistes antigues del Finder i per a macOS 15.
- `scripts/build-app.sh` només necessita les Command Line Tools: copia la icona ja compilada. Si
  `Recursos/AppIcon.icon` és més nova que `Recursos/Assets.car`, s'atura i demana tornar a compilar.

**Està acabada quan** `scripts/icona-compila.sh` funciona, la làmina mostra una figura clara en els quatre
aspectes i a 16 pt, no hi ha cap SF Symbol ni logotip d'altri, el dibuix (l'script o els prompts) és explicat a `docs/disseny.md`,
pas 12, i en David la dona per bona.
