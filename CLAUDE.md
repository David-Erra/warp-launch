# CLAUDE.md — Warp Launch

App personal de macOS d'en **David Erra** per **llegir, editar i tornar a obrir les finestres i pestanyes
de Warp, cadascuna amb la seva sessió de Claude Code**. Ha de poder fer-ho sola en iniciar sessió al Mac.
És una app nativa de barra de menú (SwiftUI). Comanda: `warp-launch`. Identificador: `cat.davide.warp-launch`.

**Idioma:** català (codi, comentaris, missatges, commits i documentació). **To:** directe, concís, amb xifres i fets.

## El problema (paraules d'en David, 03/11/2026)

> Faig servir Warp cada cop amb més intensitat i cada cop tinc més sessions. Quan paro l'ordinador
> i el torno a reiniciar és un problema, perquè he de tornar a obrir totes les finestres amb totes les
> sessions de Claude. Tampoc em satisfà com guarda la configuració Warp: he d'iniciar totes les
> sessions a mà i he de recordar tota la configuració.

Per a en David, **una finestra de Warp és un grup de sessions**; no ho confonguis amb els *tab groups* de Warp.
Gairebé cada pestanya té un agent Claude Code per repo (`claude --dangerously-skip-permissions --effort ultracode`).
El 03/11/2026 hi havia 7 finestres i 64 pestanyes de terminal, però només 14 sessions de Claude vives,
d'uns 500 MB cadascuna. Els requisits són a `docs/especificacio.md`.

## Estat (07/11/2026, 0.28.0)

- **Repo:** `David-Erra/warp-launch` a GitHub, públic, amb llicència MIT (`LICENSE`). Comença amb un sol commit inicial,
  sense l'historial anterior ni les versions d'abans de la 0.28.0. El `README.md` explica com instal·lar-la en un altre Mac.
  L'app instal·lada és a `/Applications` des de la 0.27.0.
- **Fase 1 (lectura) feta, versió 0.2.0.** `warp-launch llegeix [--json]` mostra les finestres, les pestanyes, la
  carpeta i la sessió de Claude de cada pestanya.
- **Fase 2 (editor) feta (06/11/2026; en David dona per bona la icona):** format v1 de la configuració, magatzem (desar i còpies), esquelet de
  l'app (pas 4, prova 1 feta el 04/11/2026), ordre de Claude (pas 5), importació i avisos (pas 6, al CLI:
  `warp-launch importa`), model de l'editor (pas 7) i barra lateral, llista i full d'importació (pas 8: l'app ja
  pot crear la configuració des de Warp; prova 2 feta el 04/11/2026), inspector (pas 9, prova 3) i copiar i enganxar
  pestanyes (pas 9b, proves 4 i 5), arrossegar i «Mou a ▸» (pas 10, prova 6), obrir la finestra arrossegant per
  deixar-hi les pestanyes en una posició (pas 10b, prova 7) i reordenar les finestres a la barra lateral (arrossegant-les,
  o «Mou amunt» i «Mou avall»; prova 7c feta el 04/11/2026), i menús, dreceres, menú de la icona i la plantilla a la
  Configuració, amb el seu Desfés (pas 11, provat a l'app el 04/11/2026). Del pas 12, el paquet és fet (0.26.0: `Info.plist` i `scripts/instal·la.sh`); la icona, dibuixada amb codi (`scripts/icona-dibuixa.swift`, decisió d'en David del 06/11/2026, perquè nano-banana no tenia crèdit), a la 0.26.1.
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
  les pestanyes ja obertes, per a L3 amb `/tmp/warp-launch-provaL3`. **El 05/11/2026, en David torna a obrir les 6
  finestres i 62 pestanyes des de l'app** (totes confirmades, però cap conversa represa, i 17 Claude aturats perquè l'app
  no avisava bé de la confiança; corregit a la 0.21.1). **La configuració real ja existeix:** `~/.config/warp-launch/`, còpia de L3 feta el
  05/11/2026 a petició d'en David (regla 9). «Obrir-ho tot» és la fase 3.2 (0.25.0) i obrir-se en iniciar sessió, la 3.3 (0.27.0).
- **0.22.1: cada pestanya reprèn sempre la conversa més recent de la seva carpeta** (D7, revisada per en David el 05/11/2026),
  si no és viva ni d'una altra pestanya. **0.22.2:** només compten les escrites al terminal on Claude ha respost, i la més recent
  és la de l'últim missatge al terminal, no la data del fitxer.
- **0.22.3: les feines noves `claude --bg` dels agents van en bypass** (en David, 05/11/2026), si la pestanya hi va: la línia porta `CLAUDE_ENV_FILE`
  (`EntornClaude`, `entorn-claude.sh` a la carpeta de la configuració). Les que ja existeixen es desperten sense el paràmetre, per no fer còpies.
  Sense efecte a les pestanyes ja obertes. Prova real feta el 05/11/2026 amb 1 feina: va en bypass i els missatges hi arriben sols, en els dos sentits.
- **El 05/11/2026, en David desactiva la restauració de sessió de Warp** (D6: «aquesta app substitueix la funcionalitat»).
  Warp deixa de desar les finestres a `warp.sqlite`. **Des de la 0.22.0, l'app sap què hi ha obert pels processos** (els fills
  de `stable terminal-server`, `docs/disseny.md`, «Sense la base de Warp») i no llegeix la base si la restauració és
  desactivada; no en veu les finestres ni els títols. Per importar i lligar, des de la 0.23.0 en fa una foto (D19). Si Warp és tancat, «Obre» l'obre.
- **0.23.0 (D19): l'app gestiona `restore_session`.** Sempre desactivat, també en sortir. **Des de la 0.27.3, només quan en David ho demana** (abans, cada 5 min):
  amb Warp obert, l'activa fins que Warp desa (de 5 a 30 s) perquè la base tingui una foto de les finestres. El 06/11/2026, en reiniciar el Mac,
  Warp va restaurar la foto sol (62 pestanyes sense Claude). «Torna a llegir Warp», importar i lligar: amb Warp obert, refresquen i llegeixen; amb Warp tancat, l'última foto. Obrir
  finestres continua pels processos. Prova real feta el 05/11/2026: dos refrescs de 5 i 6 s, la foto quadra amb els 62 terminals.
- **0.24.0 (D17): `warp-launch obre <finestra> --obre`** obre la finestra pel mateix camí que el botó de l'app (`ExecucioObertura`, compartit).
  No fa res si l'app és oberta (tots dos escriurien `estat.json`), i si Warp és tancat, primer l'obre (en David, 05/11/2026). Sense prova real encara:
  **mai sense l'OK d'en David per a cada prova** (regla 1).
- **Fase 3.2, 0.25.0 (D4): «Obre-ho tot a Warp…»** (menú Fitxer i menú de la icona): un full amb una casella per finestra, totes
  marcades, i les obre totes de cop; si una falla, les altres continuen. **Provat el 06/11/2026 amb la 0.26.0**, amb la represa d'una conversa (prova 1), una finestra oberta en part (3) i la prova 8 (4): totes bé. `docs/disseny.md`, secció 8.
- **Fase 3.3, 0.27.0 (D3): obrir-se en iniciar sessió.** Un interruptor a la Configuració afegeix l'app als ítems d'inici de macOS
  (`SMAppService.mainApp`, només a `ServeiArrencada`; regla 3: només quan en David l'activa, i només amb l'app a `/Applications`). En
  iniciar sessió, mostra de seguida el full de «Obre-ho tot» (0.27.2: sense esperar Warp): no obre res sense el clic. **Primer reinici el 06/11/2026
  amb la 0.27.2:** l'app s'obre sola i prepara el full en 2 s, però Warp també s'obre sol i restaura 62 pestanyes sense Claude
  (`docs/fets-verificats.md`). D'aquí la 0.27.3: la foto només quan en David la demana, i el full avisa de les pestanyes que no
  reconeix. Falta un reinici amb la 0.27.3. L'opció de Warp que l'obre en iniciar sessió («Start Warp at login») sempre ha estat desactivada (en David, 07/11/2026):
  no se sap qui va obrir Warp. `docs/disseny.md`, secció 9.
- **0.28.0 (D11, revisada per en David el 07/11/2026): la plantilla segura.** Una configuració nova (sense fitxer) s'importa amb
  `claude` sense saltar els permisos ni ultracode (`.perOmissio`, continuant la conversa). «Salta els permisos», l'esforç i
  «Ultracode» es trien a la Configuració › «Pestanyes noves» o per pestanya a l'inspector. La configuració que ja existeix
  conserva la seva plantilla.
- **Signatura:** `scripts/build-app.sh` signa amb el certificat «Warp Launch Dev» del clauer d'en David (D12).
  L'app té permís a Privacitat i seguretat › Arxius i carpetes per llegir les dades de Warp.
- **Ordre de feina acordat:**
  1. Lectura de la configuració actual de Warp.
  2. Editor.
  3. Llançaments, pas a pas.
- **El prototip `espai` (Python) està desinstal·lat:** no hi ha LaunchAgent ni comanda. El codi és a
  `prototip/`. En David creu que **tot el que es va fer abans potser no val i s'ha de revisar**: el codi,
  les proves i els fets que se'n van treure.
- **L'app nova no pot dependre de res creat abans fora d'aquest repo**, com `espai`, `~/.config/espai-warp/`
  o les configuracions `espai-*.yaml`.

Llegeix, en aquest ordre:
- `docs/especificacio.md`: requisits, decisions preses i obertes, fases.
- `docs/fets-verificats.md`: què hem comprovat de Warp, de Claude Code i de l'entorn. No tornis a descobrir
  els fets datats; els marcats «(prototip)» s'han de tornar a verificar abans de basar-hi codi.
- `docs/antecedents.md`: què existeix ja, i per què fem l'app igualment.
- `docs/disseny.md`: el disseny i els passos de les fases 2 (l'editor) i 3 (els llançaments). Mana sobre la skill `mac-design`.

## Entorn i comandes

- Swift 6.4.2 de les **Command Line Tools**, en mode de llenguatge Swift 6. **Sense dependències externes**
  (només frameworks de macOS: Foundation, SwiftUI, AppKit, SQLite3, UniformTypeIdentifiers, CoreTransferable, ServiceManagement i os).
  La compilació s'ha provat només a macOS 27.2; la versió mínima declarada és macOS 26.
- **Proves amb `swift-testing`** (`import Testing`), que fa servir les macros de TestingMacros. XCTest no
  està disponible amb les Command Line Tools.
- **Xcode 27.2 només fa falta per compilar la icona** (`scripts/icona-compila.sh` i `icona-revisa.sh`).
  - Llicència acceptada i configuració inicial (`-runFirstLaunch`) feta el 03/11/2026.
  - `xcode-select` apunta a les Command Line Tools: per fer servir Xcode, cal
    `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (els scripts ja el posen).
- **Signatura:** no hi ha cap certificat de desenvolupador d'Apple. `build-app.sh` signa amb «Warp Launch Dev», un certificat
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
/usr/bin/log show --last 10m --predicate 'subsystem == "cat.davide.warp-launch"'  # registre de l'app (arrossegar)
scripts/build-app.sh                     # crea «build/Warp Launch.app» (release, signada amb «Warp Launch Dev» o ad hoc); no l'obre
scripts/instal·la.sh [--aplica]          # sense --aplica, diu què copiaria a /Applications; amb, copia (regla 3: només amb l'OK d'en David)
scripts/instal·la.sh --github [--aplica] [--versio x.y.z]  # igual, amb la versió publicada a GitHub (per a altres Macs; README.md)
scripts/publica.sh [--aplica]            # sense --aplica, compila i diu què publicaria; amb, crea la versió a GitHub (regla 3: OK cada vegada)
scripts/warp-restauracio.sh estat         # si Warp desa les finestres (només lectura)
scripts/warp-restauracio.sh activa|desactiva [--aplica]  # regla 7: sense --aplica no escriu; amb, cal l'OK d'en David
scripts/genera-imatge.sh "<prompt>" <sortida.png> [1:1]   # imatge amb nano-banana (cal GEMINI_API_KEY)
python3 -m unittest discover -s prototip/tests   # proves del prototip (només referència)
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
| `Sources/WarpLaunchApp/` | App de barra de menú, prima: escenes, activació i Dock (executable `WarpLaunch`, `--config <carpeta>`) |
| `Sources/WarpLaunchCLI/` | Comanda `warp-launch`: només hi posa els valors reals; la lògica és a `OrdreCLI` (core), que es prova amb fixtures |
| `Tests/WarpLaunchCoreTests/` | Proves `swift-testing`, sempre amb dades fictícies; inclou la prova de guarda (`GuardaTests`) |
| `Tests/WarpLaunchUITests/` | Proves del model de l'editor, amb carpetes temporals |
| `Recursos/Info.plist` | Plantilla del bundle (`LSUIElement`; la versió surt de `VERSION`); `ca.lproj` per als menús en català |
| `scripts/` | `test.sh` (proves), `build-app.sh` (empaqueta i signa el `.app`), `instal·la.sh` (el copia a `/Applications`, també des de GitHub), `publica.sh` (publica la versió a GitHub), `warp-restauracio.sh` (regla 7), `genera-imatge.sh` (nano-banana) i `icona-*` (icona; `icona-dibuixa.swift` en dibuixa les capes) |
| `.claude/skills/mac-design/` | Normes de disseny d'app de Mac (adaptada de BAMA, MIT); `docs/disseny.md` hi mana |
| `.claude/skills/app-icon/` | Com es fa la icona: dibuix amb codi (nano-banana, com a alternativa), Icon Composer i `actool` (adaptada de BAMA, MIT) |
| `prototip/` | `espai.py` i les seves proves: referència per revisar, **no és font de veritat** |
| `.claude/settings.json` | Regles `deny` de Claude Code (vegeu sota) |
| `LICENSE` | Llicència MIT (© 2026 David Erra); les skills de BAMA porten la seva (`LICENSE-BAMA`) |

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
   - **No publiquis cap versió a GitHub** (`scripts/publica.sh --aplica`) sense l'OK d'en David, cada vegada: la instal·la qui faci
     la comanda del README. Es desfà amb `gh release delete vX.Y.Z --repo David-Erra/warp-launch --cleanup-tag`.
4. **No obris l'app** (`open "build/Warp Launch.app"`, `.build/*/WarpLaunch`) sense OK.
   - Del CLI, sense OK només pots executar ordres de lectura: `--versio`, `llegeix`, i a la fase 2 `importa` sense
     `--desa` i `configuracio valida` (OK d'en David, 03/11/2026).
   - Tota ordre que obri finestres o escrigui fora del repo ha de tenir un mode de prova, i ha de ser el
     comportament per defecte.
5. **Del prototip només pots executar les proves** (`python3 -m unittest discover -s prototip/tests`).
   No executis `prototip/espai.py` amb cap subcomanda: `instal·la` el tornaria a instal·lar, `desa` escriu
   l'estat i `obre` obre Warp. Per entendre'l, llegeix-ne el codi.

**Fitxers**

6. **`~/.claude/` és només de lectura**: transcripcions, `sessions/` i configuració. L'única excepció és la
   memòria d'aquest projecte, que gestiona Claude Code. Els hooks de Claude per a l'app només es poden
   injectar en cada llançament amb `--settings`, mai escrivint a `~/.claude/settings.json`.
7. **Els fitxers de Warp són només de lectura.**
   - `warp.sqlite` s'obre sempre en només lectura (`SQLITE_OPEN_READONLY`, o `?mode=ro` des del
     terminal), perquè Warp l'escriu en calent.
   - No toquis `~/.warp/` (`settings.toml`, `tab_configs/`, launch configurations, incloses les 7
     `espai-*.yaml`), ni les preferències de Warp.
   - **Única excepció (en David, 05/11/2026):** la línia `restore_session` de `[general]` a `~/.warp/settings.toml`, per
     activar la restauració de sessió una estona i poder llegir les finestres i els títols de Warp.
     - Només amb `scripts/warp-restauracio.sh`, i només amb l'OK d'en David per a cada vegada.
     - Abans, digues-li què passa mentre és activada: si Warp es tanca, restaura les seves finestres, i Settings Sync porta
       l'ajust a les altres instal·lacions.
     - En acabar, torna-la a desactivar i comprova-ho amb `estat`, passat 1 s (Warp podria tornar a posar el valor d'abans).
   - **Segona excepció (en David, 05/11/2026, D19): l'app** pot canviar aquesta mateixa línia, sola i sense OK per a cada vegada, només amb la carpeta
     de debò (`AjustRestauracio`, `RefrescWarp`). Cap altre codi ni cap altra línia. Mentre l'app és en marxa, l'ajust que activis a mà es torna a desactivar en 60 s:
     per fer servir l'script, primer surt de l'app.
   - Quan arribi la fase 3, l'app només escriurà els fitxers que generi ella, amb una marca pròpia, i amb l'OK d'en David.
8. **`~/.config/espai-warp/` és només de lectura.** Hi ha la configuració i l'historial del prototip.
9. **La configuració JSON de Warp Launch és d'en David** (a `~/.config/warp-launch/`). Edita-la només si t'ho
   demana, i fes-ne còpia abans. Les proves fan servir sempre una ruta temporal.

**Canvis**

10. **Res de dependències noves sense acordar-ho:** ni paquets SwiftPM, ni eines de Homebrew, ni llibreries fora de macOS.
11. **Canvis de format amb migració.** La configuració porta un camp de versió. Si el format canvia, cal
    escriure una migració que no perdi dades i demanar l'OK abans.

**Sobre `.claude/settings.json`:** les regles `deny` es compleixen fins i tot amb
`--dangerously-skip-permissions`. Bloquegen dues coses:
- l'edició amb Edit/Write dels fitxers protegits (`~/.claude`, que no inclou la memòria; Warp; LaunchAgents;
  `espai-warp`; la configuració de Warp Launch, `~/.config/warp-launch/`);
- algunes ordres de Bash: `killall`, `pkill`, `osascript`, `launchctl bootstrap|load|enable|kickstart`,
  `claude agents` i les subcomandes d'`espai.py`.

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
