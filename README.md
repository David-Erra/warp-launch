# Warp Launch

App de barra de menú per a macOS que llegeix, edita i torna a obrir les finestres i pestanyes de Warp,
cadascuna amb la seva sessió de Claude Code. Pot obrir-se sola en iniciar sessió i proposar-te obrir-ho tot amb un clic.

**Estat (09/11/2026):** llegeix Warp, edita la configuració (finestres, pestanyes i com s'hi obre Claude),
obre una finestra o totes a Warp i, si ho actives, s'obre en iniciar sessió. L'última versió publicada és la 0.31.5 (09/11/2026), i
s'instal·la amb Homebrew. El codi del repo és a la 0.32.9, amb actualització automàtica: l'autor ha decidit activar-la, però encara
**no s'ha publicat ni s'ha vist funcionar** (vegeu «Actualitzacions automàtiques»). Instruccions per a agents: [`CLAUDE.md`](CLAUDE.md).

## Instal·lar-la

Cal un Mac amb Apple Silicon (M1 o posterior) i macOS 26 o posterior, un compte d'administrador del Mac,
[Warp](https://www.warp.dev) Stable i [Claude Code](https://docs.claude.com/claude-code). No cal compilar res.
- **Warp Stable** a `/Applications` (des de la 0.29.2, a qualsevol carpeta: l'app pregunta a macOS on és; des de la 0.31.1, si
  tens una altra còpia oberta, compta la que és oberta). **Warp Preview no és compatible:** si només hi ha Preview, o Preview és
  obert i Stable no, l'app no obre res i ho diu. Sense cap Warp, tampoc.
- Provat el 05/11/2026 amb macOS 27.2, Warp 0.2026.10.21 i Claude Code 2.1.318. Llegeix formats interns de Warp i de Claude Code que
  no estan documentats, i una versió nova els pot trencar: el diagnòstic («Si alguna cosa falla», a sota) diu si encara quadren.

1. **Instal·la-la amb Homebrew.** Cal tenir [Homebrew](https://brew.sh). Si no el vols fer servir, vegeu «Sense Homebrew», a sota.
   ```bash
   brew install --cask david-erra/tap/warp-launch
   ```
   Afegeix el tap `David-Erra/homebrew-tap` i confia només en aquesta recepta. Baixa l'última versió publicada, en comprova
   el sha256, la copia a `/Applications` i li treu la marca de baixada d'internet, perquè encara no està notaritzada per Apple.
   No l'obre, no la registra a l'inici de sessió i no toca cap configuració.
2. **Obre Warp Launch** des d'Aplicacions. Surt com una icona a la barra de menú (no al Dock).
   - **El primer cop, el teu permís** (des de la 0.29.0): l'app explica que ha de desactivar l'ajust de Warp «Restore windows,
     tabs, and panes on startup» (si tens Settings Sync, també als altres Macs) i que l'activarà uns segons quan li demanis que
     llegeixi les finestres de Warp. Si no acceptes («Surt de l’app Warp Launch»), es tanca sense tocar res i t'ho torna a preguntar la
     propera vegada. Fins que acceptes, no llegeix ni obre res. Si ja la feies servir (hi ha `configuracio.json` o `estat.json` a
     `~/.config/warp-launch/`), no pregunta, llevat que hagis retirat el permís (vegeu «Desinstal·lar»). Des de la primera versió
     publicada amb actualitzacions automàtiques, aquesta pantalla també dirà que l'app es connecta a GitHub un cop al dia. Qui no la vegi ho sabrà per aquest README
     i per les notes de la versió.
   - **Permís per llegir les dades de Warp:** macOS no pregunta; la primera vegada, l'app no les pot llegir i surt un avís
     («Accés a les dades bloquejat», amb el botó «Gestiona»). Activa-ho a Configuració del Sistema › Privacitat i seguretat ›
     Arxius i carpetes › Warp Launch.app › «Dades compartides per l'app Warp i les apps afiliades», i torna a obrir l'app.
3. **Crea la configuració:** a l'editor, **Importa de Warp…** amb les finestres que vulguis ja obertes a Warp.
   Es desa a `~/.config/warp-launch/`. Les pestanyes on corria Claude conserven l'ordre amb què es va obrir. Les altres
   queden només terminal (des de la 0.29.1; abans hi obria `claude`): per obrir-hi Claude, marca «Obre Claude Code en aquesta
   pestanya» a l'inspector, amb les opcions de Configuració (⌘,) › «Pestanyes noves». Les de la carpeta d'inici o d'una carpeta
   que ja no existeix també queden sense Claude.
4. Si vols que s'obri sola en iniciar sessió: Configuració (⌘,) › General › **Obre Warp Launch en iniciar sessió**.
   Si a Warp tens activada «Start Warp at login», desactiva-la, perquè no s'obri pel seu compte (en un reinici, amb l'opció
   desactivada, Warp es va obrir igualment, i encara no se sap per què).

**Per actualitzar-la:** `brew upgrade --cask warp-launch`. Si l'app és oberta, Homebrew la tanca, hi posa la versió nova i
la torna a obrir. Avui és l'única manera; quan es publiqui la primera versió amb actualitzacions automàtiques, n'hi haurà prou de fer-ho una última vegada (vegeu
«Actualitzacions automàtiques»).
**Per desinstal·lar-la:** vegeu «Desinstal·lar», a sota.

### Sense Homebrew

Amb l'eina de GitHub, `gh`:

1. **Instal·la `gh`** (només la primera vegada), amb el paquet de https://cli.github.com.
   Després, entra a `gh` amb un compte de GitHub i comprova que és el que surt com a actiu:
   ```bash
   gh auth login
   gh auth status
   ```
2. **Instal·la Warp Launch** amb una sola comanda, des de qualsevol carpeta:
   ```bash
   s="$(gh api -H 'Accept: application/vnd.github.raw' repos/David-Erra/warp-launch/contents/scripts/instal%C2%B7la.sh)" && bash -c "$s" instal·la --github --aplica
   ```
   Si surt `gh: Not Found (HTTP 404)`, `gh` no troba el repo: revisa la comanda i el pas 1. No la facis amb `sudo`.
   Baixa l'última versió publicada, comprova que està signada amb el certificat d'en David («Warp Launch Dev») i la
   copia a `/Applications`. No l'obre, no la registra a l'inici de sessió i no toca cap configuració. Si l'app és oberta,
   s'atura i et demana que en surtis. Sense `--aplica`, només diu què faria; amb `--versio x.y.z` (per exemple,
   `--versio 0.28.0`), n'instal·la una de concreta. Al repo hi ha les versions des de la 0.28.0.
3. Continua amb «Obre Warp Launch» (el pas 2 de dalt).

**Per actualitzar-la:** surt de l'app i torna a fer la comanda anterior. Quan es publiqui la primera versió amb actualitzacions
automàtiques, n'hi haurà prou de fer-ho una última vegada (vegeu «Actualitzacions automàtiques»).

### Des del codi

Per compilar-la tu mateix (cal `xcode-select --install`):

```bash
git clone https://github.com/David-Erra/warp-launch.git && cd warp-launch
scripts/build-app.sh             # crea «build/Warp Launch.app»; no l'obre
scripts/instal·la.sh --aplica    # la copia a /Applications (sense --aplica, només diu què faria)
```

La primera compilació baixa Sparkle: cal internet, també si només compiles el CLI. Una còpia compilada així no s'actualitza mai sola.

### Publicar una versió (l'autor)

`--aplica` només l'executa l'autor, al seu terminal; cap agent. Cal `GH_TOKEN` d'un compte que pugui escriure a
`David-Erra/warp-launch` i a `David-Erra/homebrew-tap`, passat només a aquesta ordre.
`scripts/publica.sh` compila la versió de `VERSION` amb l'adreça de les actualitzacions (`build-app.sh --amb-feed`), comprova la
signatura «Warp Launch Dev» de l'app i de les peces de Sparkle i diu què publicaria i quin canvi faria a la recepta de Homebrew; amb
`--aplica`, signa el zip amb la clau del clauer, comprova la signatura amb la clau pública que porta l'app, la publica a GitHub
(`vX.Y.Z`, amb `WarpLaunch-X.Y.Z.zip` i `appcast.xml`) i posa al dia la versió i el sha256 de la recepta (`Casks/warp-launch.rb`
del tap). És la que instal·len `brew` i la comanda de «Sense Homebrew».
Només publica el que hi ha a `origin/main`, sense canvis per fer commit, i una versió que encara no hi sigui. Si la recepta no
es pot escriure, la versió no s'esborra, i l'script diu què cal canviar a mà.

**El d'ara (0.33.0) encara no es pot executar:** la recepta encara no té `auto_updates true`. L'adreça i la clau pública ja hi són
(`Recursos/Actualitzacions.plist`). La 0.31.5 es va publicar amb l'script d'aquella versió, sense actualitzacions automàtiques.
**Des de la primera versió amb actualitzacions automàtiques, publicar ja no es desfà:** la versió arriba sola a tots els Macs en un dia. Com
s'atura una versió dolenta: [`docs/disseny.md`](docs/disseny.md), secció 11, apartat 7.

## Actualitzacions automàtiques

**Encara no les porta cap còpia publicada.** El codi és al repo des de la 0.32.0, però l'última versió publicada és la 0.31.5.
**Només s'han vist funcionar amb versions de prova,** un servidor local i una clau d'un sol ús, al Mac de l'autor: amb una app de prova
(rondes A i B de [`docs/disseny.md`](docs/disseny.md), secció 11) i amb Warp Launch (ronda C, en part). S'actualitza sola sense cap diàleg de macOS, torna sense
cap finestra i conserva el permís d'Arxius i carpetes i l'inici de sessió. No s'ha provat en un altre usuari o un altre Mac, ni amb un reinici del Mac: l'autor ha
decidit no fer més proves (10/11/2026). L'adreça i la clau pública de l'autor ja són al repo (0.33.0); falta publicar-les, amb la recepta de Homebrew al dia, i després, la
primera actualització real. El que segueix diu com funcionaran.

- **Qui tingui la 0.31.5 o una d'anterior haurà d'actualitzar a mà una última vegada** («Per actualitzar-la», a dalt): aquelles
  versions no porten res per actualitzar-se ni per avisar-ne. Des de llavors, és automàtic.
- **Normalment no veuràs res.** Un cop al dia, l'app mira a GitHub si hi ha una versió nova. Si n'hi ha, la baixa (uns 5 MB), en
  comprova la signatura i es reinicia sola quan no fas servir ni el Mac (2 minuts sense teclat ni ratolí) ni l'app (cap finestra
  seva oberta, cap canvi recent, cap finestra de Warp obrint-se). La icona de la barra de menú desapareix un moment i torna.
  **Warp i les sessions de Claude no es tanquen ni es toquen.** Si surts de l'app amb una versió a punt, s'instal·la en sortir.
  Si apagues o reinicies el Mac, encara no se sap si s'instal·la llavors o a la propera sortida.
- **Va encès de sèrie.** Per apagar-ho: Configuració (⌘,) › «Actualitzacions» › «Actualitza automàticament». Apagat, l'app no es
  connecta sola, i una versió que ja fos a punt no la reinicia: s'instal·la quan en surts. A la mateixa pestanya hi ha «Comprova
  ara» i, al menú de la icona, «Comprova si hi ha actualitzacions…»; amb una versió a punt, tots dos diuen «Reinicia i actualitza».
- **Privacitat: és la primera connexió a internet de l'app.** Un cop al dia, i quan demanes de comprovar, una petició a GitHub i,
  si hi ha versió nova, la baixada. **GitHub veu la teva adreça IP i la versió de l'app.** No s'hi envia cap perfil del Mac ni
  cap dada de Warp o de Claude, i no se n'ha trobat cap altra connexió a les fonts de Sparkle (es comprovarà a les proves reals).
  Abans d'acceptar el permís del primer ús, no es connecta.
- **Només s'actualitzen les versions publicades, a Aplicacions.** Una còpia compilada des del codi, una altra carpeta, la còpia
  d'un altre usuari del Mac o una obertura amb `--config`, no; la pestanya «Actualitzacions» diu per què.
- **Si no es pot instal·lar,** la icona pot desaparèixer una vegada. Quan tornis a obrir l'app, la pestanya ho diu, i l'app no ho
  torna a intentar sola amb aquella versió.
- **Diversos usuaris del Mac:** si dos usuaris tenen la sessió i l'app obertes, l'actualització d'un no tanca la de l'altre
  (llegit al codi de Sparkle, sense provar).
- **Amb Homebrew:** si fas `brew upgrade` amb una versió ja a punt, surt de l'app abans, i no facis servir `--greedy`, que la
  reinstal·laria. `brew upgrade --cask warp-launch`, amb el nom, també reinstal·la una còpia que ja s'ha actualitzat sola. Sense provar.

## Desinstal·lar

1. **Configuració (⌘,) › General › «Deixar de fer servir Warp Launch» › Restaura Warp i surt…** (des de la 0.31.0). Abans de
   fer res, diu com quedarà l'ajust de Warp «Restore windows, tabs, and panes on startup»: com el tenies abans de Warp Launch;
   si ja la feies servir abans que demanés permís (0.29.0), activat, com ve de sèrie a Warp; i, si Warp Launch no l'ha canviat
   mai, com és. En confirmar, treu l'app dels ítems d'inici de sessió, torna l'ajust com ha dit, retira el permís i surt. Si un
   pas no es pot fer, ho diu i no fa els següents. Si la tornes a obrir, et torna a demanar permís. Si no li has donat mai el
   permís, aquest pas no cal: sense permís, Warp Launch no toca Warp.
2. Si la vas instal·lar amb Homebrew, `brew uninstall --cask warp-launch`. Si no, arrossega `/Applications/Warp Launch.app` a
   la Paperera.
3. Si no vols conservar la configuració, esborra `~/.config/warp-launch/`.
4. Amb una versió que porti actualització automàtica, si no vols que en quedi res: `~/Library/Caches/cat.davide.warp-launch`,
   `~/Library/HTTPStorages/cat.davide.warp-launch` i `~/Library/Preferences/cat.davide.warp-launch.plist` (hi ha l'interruptor i
   la data de l'última comprovació).

Amb una versió sense el botó (d'abans de la 0.31.0): desactiva l'interruptor de l'inici de sessió, surt de l'app i, si vols que
Warp torni a obrir les seves finestres en arrencar, torna a activar l'ajust a la configuració de Warp.

## Què has de saber

- **L'app gestiona la restauració de sessió de Warp** (`restore_session` a `~/.warp/settings.toml`), amb el teu permís del
  primer ús (pas 2): la deixa sempre
  desactivada, perquè és ella qui torna a obrir les finestres, amb Claude. Només l'activa uns segons quan demanes
  «Actualitza l'estat de Warp», «Importa de Warp» o «Lliga amb Warp», per llegir-ne les finestres. Si tens Settings Sync, l'ajust arriba
  a les altres instal·lacions de Warp. Per deixar-la de fer servir, «Restaura Warp i surt…» torna l'ajust (vegeu «Desinstal·lar»).
  Si encara no tens `~/.warp/settings.toml` (per exemple, si no has canviat mai cap ajust de Warp), des de la 0.31.3 l'app només
  el crea quan Warp és obert amb alguna pestanya, perquè Warp hi pugui passar abans els seus ajustos; fins llavors, Warp fa
  servir la restauració de sèrie, activada, i el menú de la icona ho diu.
- **Res no s'obre sense el teu clic.** Obrir una finestra o totes passa sempre per un full que diu quantes
  pestanyes i sessions de Claude s'obriran.
- **Les feines en segon pla de Claude:** tancar Warp pot deixar-les a mitges, i reobrir les pestanyes no les fa continuar.
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
  baixada amb el navegador, macOS no l'obriria. La recepta de Homebrew en comprova el sha256 i li treu la marca de baixada
  d'internet; la comanda de «Sense Homebrew» en comprova la signatura i també la hi treu. Compilada des del codi en un altre
  Mac, `build-app.sh` la signa ad hoc, i llavors, després de cada actualització, macOS pot tornar a demanar el permís d'Arxius i
  carpetes i el de l'inici de sessió. Les actualitzacions automàtiques, quan es publiquin, només s'acceptaran si el zip porta la
  signatura EdDSA de la clau de l'autor, comprovada abans d'extreure'l: amb el certificat sol no n'hi ha prou. Es dedueix, i
  encara no s'ha provat, que macOS deixarà substituir l'app sense cap diàleg i n'hi mantindrà els permisos.

## Desenvolupament

Swift 6.4 de les Command Line Tools. Una sola dependència externa: [Sparkle](https://sparkle-project.org) 2.10.1, amb la versió
exacta i només a l'app, no al CLI.

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

L'app porta [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.1 per actualitzar-se. La seva llicència va dins de l'app, a
`Contents/Resources/LICENSE-Sparkle`.

Projecte independent: no està afiliat a Warp (Denver Technologies, Inc.) ni a Anthropic, ni l'avalen. Warp, Claude i
Claude Code són marques dels seus titulars.
