# Warp Launch

App de barra de menú per a macOS que llegeix, edita i torna a obrir les finestres i pestanyes de Warp,
cadascuna amb la seva sessió de Claude Code. Pot obrir-se sola en iniciar sessió i proposar-te obrir-ho tot amb un clic.

**Estat (09/11/2026, 0.31.4 al codi):** llegeix Warp, edita la configuració (finestres, pestanyes i com s'hi obre Claude),
obre una finestra o totes a Warp i, si ho actives, s'obre en iniciar sessió. L'última versió publicada és la 0.28.0: el que
aquí diu «des de la 0.29», «des de la 0.30» o «des de la 0.31» encara no s'ha publicat ni provat a l'app. Instruccions per a agents: [`CLAUDE.md`](CLAUDE.md).

## Instal·lar-la

Cal un Mac amb Apple Silicon (M1 o posterior) i macOS 26 o posterior, un compte d'administrador del Mac,
[Warp](https://www.warp.dev) Stable i [Claude Code](https://docs.claude.com/claude-code). No cal compilar res.
- **Warp Stable** a `/Applications` (des de la 0.29.2, a qualsevol carpeta: l'app pregunta a macOS on és; des de la 0.31.1, si
  tens una altra còpia oberta, compta la que és oberta). **Warp Preview no és compatible:** si només hi ha Preview, o Preview és
  obert i Stable no, l'app no obre res i ho diu. Sense cap Warp, tampoc.
- Provat el 05/11/2026 amb macOS 27.2, Warp 0.2026.10.21 i Claude Code 2.1.318. Llegeix formats interns de Warp i de Claude Code que
  no estan documentats, i una versió nova els pot trencar: el diagnòstic («Si alguna cosa falla», a sota) diu si encara quadren.

1. **L'eina de GitHub, `gh`** (només la primera vegada): `brew install gh`, o el paquet de https://cli.github.com.
   Després, entra a `gh` amb un compte de GitHub i comprova que és el que surt com a actiu:
   ```bash
   gh auth login
   gh auth status
   ```
2. **Instal·la-la** (o actualitza-la) amb una sola comanda, des de qualsevol carpeta:
   ```bash
   s="$(gh api -H 'Accept: application/vnd.github.raw' repos/David-Erra/warp-launch/contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica
   ```
   Si surt `gh: Not Found (HTTP 404)`, `gh` no troba el repo: revisa la comanda i el pas 1. No la facis amb `sudo`.
   Baixa l'última versió publicada, comprova que està signada amb el certificat d'en David («Warp Launch Dev») i la
   copia a `/Applications`. No l'obre, no la registra a l'inici de sessió i no toca cap configuració. Si l'app és oberta,
   s'atura i et demana que en surtis. Sense `--aplica`, només diu què faria; amb `--versio x.y.z` (per exemple,
   `--versio 0.28.0`), n'instal·la una de concreta. Al repo hi ha les versions des de la 0.28.0.
3. **Obre Warp Launch** des d'Aplicacions. Surt com una icona a la barra de menú (no al Dock).
   - **El primer cop, el teu permís** (des de la 0.29.0): l'app explica que ha de desactivar l'ajust de Warp «Restore windows,
     tabs, and panes on startup» (si tens Settings Sync, també als altres Macs) i que l'activarà uns segons quan li demanis que
     llegeixi les finestres de Warp. Si no acceptes («Surt de Warp Launch»), es tanca sense tocar res i t'ho torna a preguntar la
     propera vegada. Fins que acceptes, no llegeix ni obre res. Si ja la feies servir (hi ha `configuracio.json` o `estat.json` a
     `~/.config/warp-launch/`), no pregunta, llevat que hagis retirat el permís (vegeu «Desinstal·lar»).
   - **Permís per llegir les dades de Warp:** macOS no pregunta; la primera vegada, l'app no les pot llegir i surt un avís
     («Accés a les dades bloquejat», amb el botó «Gestiona»). Activa-ho a Configuració del Sistema › Privacitat i seguretat ›
     Arxius i carpetes › Warp Launch.app › «Dades compartides per l'app Warp i les apps afiliades», i torna a obrir l'app.
4. **Crea la configuració:** a l'editor, **Importa de Warp…** amb les finestres que vulguis ja obertes a Warp.
   Es desa a `~/.config/warp-launch/`. Les pestanyes on corria Claude conserven l'ordre amb què es va obrir. Les altres
   queden només terminal (des de la 0.29.1; abans hi obria `claude`): per obrir-hi Claude, marca «Obre Claude Code en aquesta
   pestanya» a l'inspector, amb les opcions de Configuració (⌘,) › «Pestanyes noves». Les de la carpeta d'inici o d'una carpeta
   que ja no existeix també queden sense Claude.
5. Si vols que s'obri sola en iniciar sessió: Configuració (⌘,) › General › **Obre Warp Launch en iniciar sessió**.
   Si a Warp tens activada «Start Warp at login», desactiva-la, perquè no s'obri pel seu compte (en un reinici, amb l'opció
   desactivada, Warp es va obrir igualment, i encara no se sap per què).

**Per actualitzar-la:** surt de l'app i torna a fer la comanda del pas 2.
**Per desinstal·lar-la:** vegeu «Desinstal·lar», a sota.

### Des del codi

Per compilar-la tu mateix (cal `xcode-select --install`):

```bash
git clone https://github.com/David-Erra/warp-launch.git && cd warp-launch
scripts/build-app.sh             # crea «build/Warp Launch.app»; no l'obre
scripts/instal·la.sh --aplica    # la copia a /Applications (sense --aplica, només diu què faria)
```

### Publicar una versió (en David)

Cal que el compte actiu de `gh` pugui escriure a `David-Erra/warp-launch` (`gh auth status`).
`scripts/publica.sh` compila la versió de `VERSION`, comprova la signatura «Warp Launch Dev» i diu què publicaria; amb
`--aplica`, la publica a GitHub (`vX.Y.Z`, amb `WarpLaunch-X.Y.Z.zip`), i és la que instal·la la comanda del pas 2.
Només publica el que hi ha a `origin/main`, sense canvis per fer commit, i una versió que encara no hi sigui.

## Desinstal·lar

1. **Configuració (⌘,) › General › «Deixar de fer servir Warp Launch» › Restaura Warp i surt…** (des de la 0.31.0). Abans de
   fer res, diu com quedarà l'ajust de Warp «Restore windows, tabs, and panes on startup»: com el tenies abans de Warp Launch;
   si ja la feies servir abans que demanés permís (0.29.0), activat, com ve de sèrie a Warp; i, si Warp Launch no l'ha canviat
   mai, com és. En confirmar, treu l'app dels ítems d'inici de sessió, torna l'ajust com ha dit, retira el permís i surt. Si un
   pas no es pot fer, ho diu i no fa els següents. Si la tornes a obrir, et torna a demanar permís. Si no li has donat mai el
   permís, aquest pas no cal: sense permís, Warp Launch no toca Warp.
2. Arrossega `/Applications/Warp Launch.app` a la Paperera.
3. Si no vols conservar la configuració, esborra `~/.config/warp-launch/`.

Amb una versió sense el botó (d'abans de la 0.31.0): desactiva l'interruptor de l'inici de sessió, surt de l'app i, si vols que
Warp torni a obrir les seves finestres en arrencar, torna a activar l'ajust a la configuració de Warp.

## Què has de saber

- **L'app gestiona la restauració de sessió de Warp** (`restore_session` a `~/.warp/settings.toml`), amb el teu permís del
  primer ús (pas 3): la deixa sempre
  desactivada, perquè és ella qui torna a obrir les finestres, amb Claude. Només l'activa uns segons quan demanes
  «Torna a llegir Warp», «Importa de Warp» o «Lliga amb Warp», per llegir-ne les finestres. Si tens Settings Sync, l'ajust arriba
  a les altres instal·lacions de Warp. Per deixar-la de fer servir, «Restaura Warp i surt…» torna l'ajust (vegeu «Desinstal·lar»).
  Si encara no tens `~/.warp/settings.toml` (per exemple, si no has canviat mai cap ajust de Warp), des de la 0.31.3 l'app només
  el crea quan Warp és obert amb alguna pestanya, perquè Warp hi pugui passar abans els seus ajustos; fins llavors, Warp fa
  servir la restauració de sèrie, activada, i el menú de la icona ho diu.
- **Res no s'obre sense el teu clic.** Obrir una finestra o totes passa sempre per un full que diu quantes
  pestanyes i sessions de Claude s'obriran.
- **Ordre de Claude per defecte:** a les configuracions noves, Claude s'obre sense saltar els permisos (`claude`, continuant
  la conversa). «Salta els permisos», l'esforç i «Ultracode» es trien a la Configuració (⌘,) › «Pestanyes noves», o per
  pestanya a l'inspector. Les pestanyes que ja tenien Claude obert en importar conserven l'ordre amb què es va obrir.
- **Si alguna cosa falla** (des de la 0.30.0): Configuració (⌘,) › General › «Diagnòstic» › **Copia el diagnòstic** copia un
  informe en anglès, sense el teu nom d'usuari ni els noms de les carpetes, per enganxar-lo en una issue de GitHub. Diu, per a 8
  comprovacions (els terminals de Warp, els fitxers de sessió, les transcripcions i `~/.claude.json` de Claude Code, les taules de
  `warp.sqlite`, les versions i la restauració de Warp), si encara tenen la forma que l'app llegeix. Només llegeix: no obre, no
  atura ni escriu res. Des del codi: `warp-launch diagnostica [--json] [--anonimitza]`.
- **Signatura:** les versions publicades porten el certificat «Warp Launch Dev» d'en David, sempre el mateix: macOS
  hauria de mantenir els permisos en actualitzar (deduït, encara no provat en un altre Mac). No és un certificat d'Apple:
  baixada amb el navegador, macOS no l'obriria. La comanda del pas 2 en comprova la signatura i li treu la marca de
  baixada d'internet. Compilada des del codi en un altre Mac, `build-app.sh`
  la signa ad hoc, i llavors, després de cada actualització, macOS pot tornar a demanar el permís d'Arxius i carpetes
  i el de l'inici de sessió.

## Desenvolupament

Swift 6.4 de les Command Line Tools. Sense dependències externes.

```bash
swift build                          # compila
scripts/test.sh                      # proves (swift-testing); `swift test` sol falla de manera intermitent
.build/debug/warp-launch --versio    # CLI
.build/debug/warp-launch llegeix     # finestres, pestanyes i sessions de Claude (afegeix --json per al detall)
.build/debug/warp-launch importa     # la configuració que sortiria de Warp (no escriu res)
.build/debug/warp-launch diagnostica # si Warp i Claude Code tenen la forma que l'app llegeix (--anonimitza, per a una issue)
```

## Documentació

- [`docs/especificacio.md`](docs/especificacio.md): requisits, decisions preses i obertes, fases.
- [`docs/disseny.md`](docs/disseny.md): disseny i passos de cada fase.
- [`docs/fets-verificats.md`](docs/fets-verificats.md): comportament comprovat de Warp, de Claude Code i de l'entorn.
- [`docs/antecedents.md`](docs/antecedents.md): eines semblants que existeixen i per què no ens serveixen.
- El prototip anterior en Python (`espai`), desinstal·lat, ja no és al repo: és a l'historial, al commit `114c97d`.

## Llicència

[MIT](LICENSE), © 2026 David Erra.

## Tercers

Les skills [`.claude/skills/mac-design/`](.claude/skills/mac-design/) i [`.claude/skills/app-icon/`](.claude/skills/app-icon/),
i `scripts/icona-compila.sh`, `scripts/icona-revisa.sh` i `scripts/icona-full.swift`, deriven de
[BAMA](https://github.com/daveebbelaar/bama) (MIT, © 2026 Dave Ebbelaar). La llicència és a `LICENSE-BAMA`, a cada skill.

Projecte independent: no està afiliat a Warp (Denver Technologies, Inc.) ni a Anthropic, ni l'avalen. Warp, Claude i
Claude Code són marques dels seus titulars.
