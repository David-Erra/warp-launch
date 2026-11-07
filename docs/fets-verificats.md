# Fets verificats

Entorn: Mac d'en David amb macOS 27.2, Warp 0.2026.10.21 (canal Stable), Claude Code 2.1.317 i Swift 6.4.2. El 07/11/2026,
Warp 0.2026.11.04 i Claude Code 2.1.319 (recerca d'antecedents; les proves d'abans són amb les versions anteriors).

**Llegenda:**
- «(03/11/2026, …)»: comprovat per a Warp Launch, amb el mètode indicat.
- «(prototip)»: es va comprovar en fer el prototip `espai` i **no s'ha tornat a verificar**. En David vol
  que tot el que es va fer abans es revisi: torna-ho a comprovar abans de basar-hi codi.

Si en descobreixes un de nou, afegeix-lo amb la data i com l'has comprovat. Si un fet queda desmentit,
corregeix-lo i deixa'n constància.

## Warp

### Obrir des de fora

- **Launch configuration:** `open "warp://launch/<name>"` (prototip).
  - `<name>` és el camp `name:` del YAML, codificat per a URL; per exemple, `Espai%20%C2%B7%20Tot`.
  - **No funciona amb ruta** (`warp://launch//Users/...` dona «couldn't turn launch link into path») **ni
    amb el nom del fitxer** (dona «couldn't find a matching file path»). Es va comprovar amb `~/Library/Logs/warp.log`.
- **Altres URI:** `action/new_window?path=`, `action/new_tab?path=`, `tab_config/<nom>[?new_window=true]`
  (03/11/2026, documentació).
  - Cap d'aquestes URI executa una comanda.
  - `tab_config/` busca pel nom del fitxer, mentre que `launch/` busca pel `name:`.
- **Sense Accessibilitat** (prototip): `osascript` no pot enviar pulsacions (error 1002) i
  `warp://action/new_tab` no injecta comandes. L'única manera d'executar una comanda en una pestanya nova
  és una launch configuration (o un Tab Config).
- **Una launch configuration pot arrencar `claude` sol en obrir la pestanya** (03/11/2026, prova 1, amb l'OK d'en David).
  - Es va crear `~/.warp/launch_configurations/warp-launch-prova.yaml`: 1 finestra, 1 pestanya, amb
    `exec: WARP_LAUNCH_PROVA=1 claude -n warp-launch-prova`.
    - Warp el va detectar sense reiniciar, i `open "warp://launch/warp-launch-prova"` va obrir la finestra.
  - Claude es va engegar 2 s després, com a sessió `interactive`, a la carpeta (`cwd`) de la configuració.
    Cadena de processos: `claude` ← `-zsh -g --no_rcs` ← `stable terminal-server`.
  - Les variables posades a `exec` (`VAR=1 claude …`) arriben al procés, i serveixen per marcar les sessions
    que obre l'app.
  - El `WARP_TERMINAL_SESSION_UUID` del procés coincidia amb l'`uuid` del pane nou a `terminal_panes`. El `cwd`
    del pane era el de la configuració.
  - Warp va mostrar el `title` de la configuració a la capçalera del panell de pestanyes, i el nom de `-n` a la
    pestanya (captura d'en David).
  - Després de la prova es va esborrar el fitxer.
  - 12 de les 21 configuracions antigues d'en David ja feien servir aquest mecanisme (`exec: claude …`).

### Launch configurations i Tab Configs

- **Format YAML** (prototip):
  - `name`, `windows[].tabs[]`.
  - Cada tab porta `title`, `color` (red/green/yellow/blue/magenta/cyan) i `layout.cwd`. El `cwd` ha de
    ser absolut: `~` o buit fan que la configuració no surti a la llista.
  - `layout.commands[].exec`: Warp encadena les comandes amb `&&`.
  - Es poden fer splits amb `split_direction` i `panes`.
  - Admet diverses finestres en una sola configuració.
- **Fitxers:** Warp vigila `~/.warp/launch_configurations/` i detecta els fitxers nous sense reiniciar
  (prototip). Només carrega `.yaml` i `.yml` (03/11/2026, `CONFIG_FILE_SUFFIXES` a
  `app/src/user_config/util.rs` de `warpdotdev/warp`).
- **Les launch configurations són *legacy*:** «new features are not being added». Es recomanen els
  **Tab Configs** (`~/.warp/tab_configs/*.toml`), però cada Tab Config és **una sola pestanya**. Per agrupar
  pestanyes en finestres, avui només serveixen les launch configurations (03/11/2026, documentació).
- **Inventari** (03/11/2026, `ls`):
  - `launch_configurations/`: 29 fitxers. Són 28 launch configurations (21 d'antigues i 7 `espai-*.yaml`
    del prototip, amb la marca `# generat per espai`) i una còpia `.bak` que Warp no carrega.
  - `tab_configs/`: 22 `.toml`, que són 21 Tab Configs fets a mà més `startup_config.toml`
    («New tab: …», `type = "agent"`).

### Restauració de sessió i arrencada

- **La restauració no torna a executar cap comanda** (prototip), i sovint perd la carpeta.
  - Amb el prototip, 50 de 62 pestanyes havien quedat a `~`.
  - El 03/11/2026, 34 de 64 panes tenien `cwd` = HOME; en 23 d'aquests, el darrer `blocks.pwd` era una altra carpeta.
- **`general.restore_session`** («Whether to restore the previous session when Warp starts up»)
  (03/11/2026, `settings_schema.json` del bundle, `settings.toml` llegit sense modificar-lo, i
  `app/src/terminal/general_settings.rs`):
  - Per defecte és `true`, i el `settings.toml` d'en David no la defineix: està activada.
  - Se sincronitza al núvol (`SyncToCloud::Globally`), i en David té Settings Sync activat
    (`IsSettingsSyncEnabled = true` a `defaults read dev.warp.Warp-Stable`). Si es canvia, es propaga
    a les altres instal·lacions de Warp del compte.
- **Warp és un ítem d'inici de sessió:** `general.login_item` és `true` per defecte, i s'obre sol en iniciar
  sessió (03/11/2026, revisió del codi). Cal coordinar-ho amb l'arrencada de Warp Launch.
  - **El 06/11/2026, en David treu Warp dels ítems d'inici.** `settings.toml` no té cap línia `login_item`, i
    `defaults read dev.warp.Warp-Stable AppAddedAsLoginItem` continua dient `1`: cap dels dos diu si Warp s'obrirà sol.
    Per això Warp Launch no l'espera en iniciar sessió (0.27.2).
  - **El 07/11/2026, en David diu que l'opció de Warp d'obrir-se en iniciar sessió sempre ha estat desactivada.** Qui va obrir
    Warp en el primer reinici, doncs, no se sap (vegeu «Primer reinici amb l'arrencada en iniciar sessió»).
  - **El nom de l'opció i quan es registra Warp** (07/11/2026, codi de `warpdotdev/warp` a `abb3fe33`, `master` del 06/11/2026,
    llegit amb `gh api`; recerca del 07/11/2026):
    - A la Configuració de Warp es diu **«Start Warp at login (requires macOS 13+)»**
      (`app/src/settings_view/features_page.rs`, l. 4900). És `general.login_item`, per defecte `true`
      (`app/src/terminal/general_settings.rs`, l. 40-52), i es registra amb `SMAppService.mainApp`.
    - **Warp no es torna a registrar si `AppAddedAsLoginItem` ja és `true`;** només ho fa quan s'activa l'opció de nou
      (`app/src/login_item/macos.rs`, l. 13-22). **Deduït del codi de `master`, no vist** (la 0.2026.11.04 no es pot lligar a
      cap commit): com que `AppAddedAsLoginItem` deia `1` el 06/11/2026, Warp no s'hi va poder tornar a afegir en arrencar,
      i la deducció «Warp s'hi torna a afegir quan arrenca» era falsa (ja ratllada a «Primer reinici…»). Qui va obrir Warp
      continua sense saber-se.
    - **Pista, no comprovada:** `settings.toml` no té `login_item` (per defecte, `true`) i `AppAddedAsLoginItem` és `1`, i
      Warp només s'hi registra amb l'opció activa: alguna vegada hi va estar, potser pel valor per defecte en instal·lar-lo o
      pel del núvol (Settings Sync, com `restore_session` el 06/11). Xoca amb «sempre ha estat desactivada». Abans del pròxim
      reinici, mirar l'interruptor a la Configuració de Warp, `AppAddedAsLoginItem` i si Warp surt a Ítems d'inici de sessió.
- **La documentació oficial de Warp diu que la restauració no reprèn Claude** (07/11/2026, guia
  [Migrate to Warp from Claude Code](https://docs.warp.dev/getting-started/migrate-to-warp/migrate-to-warp-from-claude-code.md)
  i [Session restoration](https://docs.warp.dev/terminal/sessions/session-restoration.md)): conserva les finestres, les pestanyes
  i els panes, però no els processos. «Session restoration preserves tabs and panes, but not running CLI processes — closing
  Warp ends Claude Code's session. Use Claude Code's built-in resume options (e.g., claude --resume)». Confirma el que el
  prototip havia vist (vegeu el primer punt d'aquesta secció).

### `warp.sqlite`

- **Warp llegeix `restore_session` en calent, i desa en menys de 5 s en activar-lo** (05/11/2026, prova de 60 s amb l'OK d'en David, `warp-restauracio.sh` i
  lectures amb `?mode=ro` cada 5 s). Warp obert tot el temps, sense reiniciar-lo. Abans, a les 16:06:57Z, la base tenia una foto antiga: 5 finestres i 57 pestanyes.
  Activat poc després; a les 16:07:02Z ja hi havia les 6 finestres i 62 pestanyes obertes, i així fins al final. Desactivat a les 16:07:5xZ: l'ajust es manté
  `false` passats 2 s i més d'una hora després, i la foto queda igual. Amb la foto, els 62 terminals vius (`warp-launch llegeix --json`) tenen els mateixos 62 panes que la base (`lower(hex(uuid))`), sense guions. Una mostra: no se sap quant triga si no hi ha cap activitat a Warp, i hi havia sessions en marxa.

- **Ruta:** `~/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite`, amb WAL.
- **S'escriu en calent** (03/11/2026). Això corregeix el que constava abans, que només es reescrivia en sortir de Warp.
  - **Com s'ha comprovat:**
    - Warp corria des de les 14:23:06 (`ps -o lstart`).
    - A les 18:33, `warp.sqlite` tenia data de les 18:32:48 i el `-wal`, de les 18:33:09.
    - El pane d'aquesta sessió, obert després de les 18:00, ja era a `terminal_panes`.
    - Llegit amb `sqlite3 "file:...?mode=ro"`.
  - **Desa gairebé a cada acció** (03/11/2026, `warp.log`).
    - `workspace:save_app` va sortir 26 vegades en un minut i mig: en obrir una finestra, canviar de finestra
      o prémer ⌘.
    - La finestra de la prova 1 ja era a la base 15 s després d'obrir-la, i en va desaparèixer en tancar-la.
- **L'SQLite de macOS conserva `-wal` i `-shm`** quan es tanca l'última connexió (WAL persistent; comprovat el
  03/11/2026 amb `sqlite3` 3.54.0). Amb Warp tancat, aquests fitxers continuen al disc.
- **Una base WAL sense `-shm` no es pot obrir en només lectura:** dona «unable to open database file».
  - Sense `-shm` no hi escriu ningú, i `warp-launch` la llegeix amb `?immutable=1`.
  - Ho comprova la prova `llegeixUnaBaseWALSenseFitxersAuxiliars`, del 03/11/2026.
- **Contingut** (03/11/2026): 7 finestres i 65 pestanyes. Una de les pestanyes és de Settings
  (`pane_leaves.kind = 'settings'`); les altres 64 són de terminal, cadascuna amb un pane. La taula
  `tab_groups` és buida.
- **Esquema útil** (03/11/2026, `.schema`):
  - `windows(id, active_tab_index, …)`.
  - `tabs(id, window_id, custom_title, color, tab_group_id, pinned)`. `color` és text YAML
    (`---\nColor: blue\n`). No hi ha cap columna d'ordre.
  - **Els `id` de `windows` i `tabs` no són estables:** Warp els renumera cada vegada que desa (03/11/2026, prova 1).
    - Les finestres van de l'1 a la N, i les pestanyes tenen números consecutius dins de cada finestra
      (finestra 1: 1–23; finestra 2: 24–40…).
    - La finestra de la prova, la més nova, va sortir com a finestra 2. La pestanya de Settings va passar de
      la 55 (finestra 4) a la 47 (finestra 5).
    - Al log, aquella finestra era `WindowId(7)`: els `id` de la base no coincideixen amb els que Warp fa
      servir mentre s'executa.
    - **Per identificar una pestanya, cal fer servir l'`uuid` del pane.**
    - **L'ordre de les pestanyes dins de la finestra és el dels `id`** (03/11/2026): en David ha comparat una finestra
      de 4 pestanyes amb `warp-launch llegeix`, i l'ordre de la pantalla és el mateix. Només s'ha comprovat en una finestra.
  - `pane_nodes`, i `pane_leaves(pane_node_id, kind, is_focused, custom_vertical_tabs_title)`. Cal filtrar per `kind = 'terminal'`.
  - `terminal_panes(id, kind, uuid BLOB UNIQUE, cwd, is_active, shell_launch_data, input_config,
    llm_model_override, active_profile_id, conversation_ids, active_conversation_id)`.
  - `tab_groups(window_id, name, color, collapsed, pinned)` són els grups de pestanyes de Warp. No s'han de
    confondre amb les «finestres = grups de sessions» d'en David.
  - `blocks(…, pane_leaf_uuid, pwd, start_ts, …)`: historial de comandes de cada pane. `start_ts` és UTC.
    - `stylized_command` és un BLOB amb codis ANSI (`ESC[1m` i `ESC[0m`) al voltant de cada caràcter. Per
      cercar-hi, cal treure'ls: amb `LIKE '%claude%'` directe surten 0 resultats, i sense els codis, 175.
    - Només hi ha 624 blocks, del 26/12/2025 al 03/11/2026. Warp no en guarda l'historial complet.
    - A la prova 1, el pane no hi tenia cap block, ni mentre `claude` s'executava ni després de tancar la
      finestra. Per tant, `blocks` no serveix per saber què va arrencar una pestanya.
- **`terminal_panes.cwd` no és canònic** (03/11/2026, comparat amb `fcntl(F_GETPATH)`).
  - Guarda la ruta tal com es va escriure, amb les majúscules i els symlinks: `~/documents/github/…`,
    `~/Github/…`. El disc no distingeix majúscules, i `~/Documents/GitHub` és un symlink a `~/GitHub`.
  - Claude, en canvi, guarda la ruta canònica. 12 de 64 `cwd` no coincidien amb la ruta canònica, i en 5 de
    14 sessions el `cwd` del pane i el de Claude no coincidien literalment.
  - **Abans de comparar rutes, cal canonicalitzar-les totes dues.**

### Identitat de pane

- Cada shell de Warp rep `WARP_TERMINAL_SESSION_UUID` (32 xifres hexadecimals) i
  `WARP_FOCUS_URL=warp://session/<uuid>`. `WARP_TERMINAL_SESSION_UUID` coincideix amb
  `lower(hex(terminal_panes.uuid))` (03/11/2026, comprovat amb aquesta sessió).
- **Les sessions `kind: bg` no serveixen per identificar el pane** (03/11/2026, entorn dels processos i
  cadena de pares):
  - El dimoni de Claude (`claude daemon run`, fill de launchd) i les seves reserves (`claude bg-spare`)
    hereten l'UUID del pane on es va engegar el dimoni.
  - Per lligar una sessió amb el seu pane, cal filtrar `kind == interactive` amb ascendent
    `stable terminal-server`.
- **Probablement es manté després de reiniciar el Mac** (03/11/2026, indicis):
  - El Mac va arrencar a les 14:22:42.
  - 53 dels 64 panes actuals tenen blocks anteriors a l'arrencada, lligats al seu UUID.
  - Falta confirmar-ho amb un reinici, que ha de fer en David.

### CLI i control

- **`oz`** (`Warp.app/Contents/Resources/bin/oz`) és un script de 3 línies que fa `exec -a "$0"` del binari
  `stable` (03/11/2026).
  - Té ordres per a agents, núvol, MCP, `dump-settings-schema`, etc. **Cap ordre de finestres ni pestanyes.**
  - **Sense arguments, el binari `stable` obre l'app.** Per això sempre se li passa `--help` o una subcomanda.
- **Warp Control (`warpctrl`) existeix, però no es pot fer servir a Stable** (03/11/2026, cadenes del binari i
  codi de `warpdotdev/warp`).
  - **Què hi ha al binari:**
    - El parser `local_control::ControlArgs`, amb ordres diferents per a cada grup. Per exemple: `tab` té
      `list`, `inspect`, `create`, `activate`, `move`, `close`, `rename` i `color`; `window` té `list`,
      `inspect`, `create`, `focus` i `close`; `session` té `list`, `inspect`, `activate` i `reopen-closed`.
    - Altres grups: `pane`, `input`, `setting`, `theme`, `action`, `capability`, `surface`, etc.
    - La pàgina Settings › Scripting i l'acció «Install Warp Control CLI», que crearia un symlink a
      `/usr/local/bin` amb permís d'administrador.
  - **Per què no es pot activar: hi ha una doble porta.**
    - El flag `WarpControlCli` només és a `DOGFOOD_FLAGS` (`crates/warp_features/src/lib.rs`), i
      `PREVIEW_FLAGS` és buit.
    - La feature de Cargo `warp_control_cli` no és a `default` d'`app/Cargo.toml`.
    - Segons `specs/warp-control-cli/PRODUCT.md`, Scripting està desactivat per defecte a Stable i Preview,
      es desa al Keychain i només es pot canviar des de Settings.
    - S'ha consultat la branca `master` del 03/11/2026: no hi ha cap tag de la 0.2026.10.21.
  - **Encara que s'activés, no ens serviria:**
    - `input insert`/`replace` **mai executen** el text.
    - `tab create` no accepta ni carpeta ni comanda.
    - `tab list` només retorna IDs i índexs, sense títol ni carpeta (`app/src/local_control/handlers/metadata.rs`).
  - Cridar `stable` com a `warpctrl` (amb `exec -a` o amb un symlink) no activa el parser de control.

### Processos

- **Dos processos** (03/11/2026; tornat a mirar amb `ps` el 04/11/2026): l'app
  (`/Applications/Warp.app/Contents/MacOS/stable` sense arguments) i `stable terminal-server --parent-pid=<app>`.
  `warp-launch llegeix` 0.16.0 ho fa servir per dir «Warp és obert» (`sysctl KERN_PROC_UID` i `KERN_PROCARGS2`). Els shells pengen del segon, i cada `claude` interactiu és fill
  d'un d'aquests shells. **Si es tanca Warp, totes les sessions moren.**
- **Tancar una finestra o una pestanya no mata Claude a l'instant** (03/11/2026, prova 1 i `warp.log`).
  - Warp manté el shell viu mentre es pot desfer el tancament. Ho controlen `general.undo_close.enabled`, que
    per defecte és `true`, i `general.undo_close.grace_period`, de 60 s per defecte. En David no els té definits.
  - La finestra de prova es va tancar a les 18:40:52Z, i el block de `claude` va acabar a les 18:41:52Z.
  - Durant aquest minut, el procés i `~/.claude/sessions/<pid>.json` continuen existint, però el pane ja no
    és a `warp.sqlite`.

## Claude Code

- **Fitxer de sessió** (prototip; la revisió del 03/11/2026 hi va afegir que també l'escriuen els processos `bg`):
  - Cada procés de Claude, interactiu o `bg`, escriu `~/.claude/sessions/<pid>.json` amb `sessionId`, `cwd`,
    `name`, `kind` (`interactive` o `bg`), `entrypoint`, `startedAt` i `procStart`.
  - `procStart` és l'hora d'inici en UTC i en format ctime, sense zona (03/11/2026, revisió). Per comparar-lo
    amb `ps -o lstart`, que dona l'hora local, cal convertir la zona.
  - **El fitxer s'esborra quan el procés acaba.** Després d'un reinici no en queda res.
  - Altres camps (03/11/2026, `jq` sobre els 14 fitxers):
    - `nameSource`: `derived` vol dir que el nom l'ha posat Claude.
    - `status`: `idle` o `busy`.
    - També hi ha `version`, `messagingSocketPath` i, en 3 de 14, `bridgeSessionId`.
- **`cwd`:** segueix els `cd` de la sessió; no és necessàriament la carpeta on es va obrir (prototip).
- **`/clear` i `/resume`:** dins la sessió reescriuen el `sessionId` del mateix fitxer, amb el mateix pid (prototip).
- **On són les converses:** `~/.claude/projects/<cwd amb tot caràcter no alfanumèric → ->/<sessionId>.jsonl` (prototip).
  - **Confirmat el 04/11/2026** (`warp-launch llegeix --json` 0.16.0 i `os.path.exists`, només lectura): les 9
    sessions vives tenen la transcripció al projecte de la seva carpeta canònica, cap en un altre.
  - Hi ha 157 symlinks (03/11/2026, revisió; 959 entrades el 04/11/2026). 144 van de `-Users-<usuari>-GitHub-*` a
    `-Users-<usuari>-Documents-GitHub-*` (projectes d'abans, quan la carpeta real era `~/Documents/GitHub`), i 13
    de `…-planta-*` a `…-empresa-*` (repos moguts). Ara `~/GitHub` és la carpeta real i
    `~/Documents/GitHub → ~/GitHub` (`ls -ld`, 04/11/2026).
  - **No s'han d'esborrar mai.**
  - L'app (0.16.0, `LectorTranscripcions`) mira primer el projecte de la carpeta seguint l'enllaç, i després els
    projectes que no són enllaços. Claude fa el nom en JavaScript (`[^a-zA-Z0-9]` → `-`, en unitats UTF-16) i, si
    passa de 200 caràcters, hi afegeix un hash (recerca del binari 2.1.318, 04/11/2026).
- **Confiança en una carpeta** (04/11/2026, `~/.claude.json` llegit amb Python, només aquest camp): 143 projectes,
  124 amb `hasTrustDialogAccepted: true`; el fitxer fa 417 KB. Claude no desa mai la de la carpeta d'inici (recerca
  del binari).
- **`claude --resume [valor]`:**
  - Accepta un ID **o un nom** de sessió, o obre el selector (03/11/2026, `claude --help`).
  - Continua el mateix `sessionId` (prototip).
  - El prototip va veure que avisava «és d'un altre directori» si no s'executava des de la carpeta de la
    conversa. La documentació diu que funciona des de qualsevol carpeta: **està per verificar**.
  - **Es nega a reprendre una sessió que té un procés viu**, i ofereix enganxar-s'hi (prototip). **No sempre** (05/11/2026):
    - `claude --bg --resume <id>` d'una conversa viva en fa una còpia amb un altre id. Vist el 03/11 a les 16:01:33Z: amb
      `c932506d` viva, va néixer `2f6b949c` (transcripció i `~/.claude/jobs`).
    - Llegit al codi minificat de 2.1.318, sense executar-ho: despertar una feina amb `respawn` es rebutja
      (`resume_session_live_elsewhere`), i `claude --resume` d'una feina viva surt amb error.
    - `disseny.md` diu que amb un procés interactiu no es nega i les transcripcions s'intercalen: no s'ha provat a propòsit, i
      no quadra amb això. R9 l'ha de garantir l'app igualment.
  - **`~/.claude/jobs/<id>/state.json` pot quedar antic** (05/11/2026): `2769a218` diu `blocked` des del 30-31/10, però la seva
    transcripció té 286 línies més de terminal, del 01/11 al 03/11. Una feina adormida es pot reprendre en una pestanya.
- **`claude --continue`** (prototip): agafa la conversa més recent de la carpeta. Si aquesta està en segon
  pla (`kind: bg`), **es nega a arrencar**.
- **Les sessions en segon pla no sobreviuen a un reinici** (07/11/2026, documentació oficial,
  [agent view](https://code.claude.com/docs/en/agent-view.md), «Sessions show as failed or stopped after shutdown» i
  «Limitations»; Claude Code 2.1.319; no s'ha provat, regla 1):
  - Aguanten la son i les actualitzacions, però no un reinici: després surten «failed», si fa menys de 48 h que van
    avançar, o «stopped» («ended while the background service was off»), si en fa més. Cal obrir-les o respondre-hi una
    per una perquè es tornin a engegar amb la conversa desada.
  - El supervisor no s'engega en iniciar sessió: ho fa «the first time you background a session or open agent view». El
    07/11/2026 no hi ha cap LaunchAgent de Claude a `~/Library/LaunchAgents` ni cap `claude daemon` en marxa (`ls` i `ps`).
- **Opcions d'arrencada** (03/11/2026, `claude --help` i cadenes del binari 2.1.317):
  - `--effort <level>`: la llista oficial és `low`, `medium`, `high`, `xhigh` i `max`.
  - **`--effort ultracode` és un àlies:** equival a esforç `xhigh` més ultracode activat. Al binari hi ha
    `{ultracode:"xhigh"}`, i ultracode està actiu si `settings.ultracode===true` o si l'esforç és «ultracode».
  - **Ultracode independent de l'esforç:** amb la clau de settings `ultracode: true`
    («standing dynamic-workflow orchestration at any effort level»), via `--settings '{"ultracode":true}'`.
    - Va per sessió, i els canvis interactius no la desen.
    - **Requereix que els dynamic workflows estiguin activats i un model que admeti ultracode.** Si no, Claude
      avisa («Ultracode isn't available on …», «Ultracode needs dynamic workflows enabled»).
  - `--model <àlies o nom>`: per exemple, `fable`, `opus` o `sonnet`.
  - `-n, --name <nom>`: nom visible de la sessió (caixa del prompt, selector de `/resume` i títol del terminal).
  - `--session-id <uuid>`: fa servir un ID de conversa triat per qui la crea.
  - `--remote-control [nom]`, `--permission-mode`, `--dangerously-skip-permissions`, `--add-dir` i `--settings`.
- **Com llegeix Claude Code la línia d'ordres** (04/11/2026, binari 2.1.318 llegit amb Python sense executar-lo;
  dues revisions independents de l'ordre del pas 5 hi van arribar també):
  - El programa principal té **131 opcions** a la funció que el construeix, més `-v, --version`. Són a
    `TaulaOpcionsClaude.definicions`, copiades tal com hi són. N'hi ha d'amagades que `--help` no mostra
    (`--rc [name]`, `--teleport [session]`, `--cloud`…).
  - Fa servir **commander**, sense `allowUnknownOption`. Una opció desconeguda atura Claude amb un error.
    `parseOptions`, copiat del binari, fa això:
    - `<valor>` pren l'argument següent sempre, encara que comenci per «-». `[valor]` només el pren si no comença
      per «-». `<valors...>` (`--add-dir`, `--allowedTools`, `--mcp-config`…) s'empassa els següents fins al
      primer que comença per «-»: a `--add-dir /a revisa`, «revisa» és una carpeta.
    - `-cw` és `-c -w`, i `-nBotiga` és `-n Botiga`. `--opcio=valor` només val per a opcions amb valor, i no activa
      la variàdica.
    - El que no és de cap opció, i tot el que ve després de `--`, és el primer missatge (`[prompt]`). Amb
      `--continue`, s'envia com un missatge nou.
    - Si una opció es repeteix, mana l'última. També amb `--settings`: Claude només fa servir l'últim.
  - **`--settings`** (`loadSettingsFromFlag`): sense espais als extrems, si comença per `{` i acaba per `}` és
    JSON, i un JSON no vàlid atura Claude («Invalid JSON provided to --settings»). Si no, és la ruta d'un fitxer,
    també `[1]` o `{malmès`. `JSON.parse` es queda amb l'última clau repetida.
  - **`ultracode`** a settings només compta si és el booleà `true`. Un altre valor (`1`, `"sí"`) és com si no hi
    fos. Un `false` a `--settings` apaga el `true` de la configuració de l'usuari, perquè `--settings` hi passa
    al davant. L'esforç `ultracode` l'activa igualment.
  - **`--dangerously-skip-permissions` sempre guanya a `--permission-mode`.** Amb tots dos, la sessió salta els
    permisos, i el mode («plan», «acceptEdits») no té cap efecte. En David té
    `skipDangerousModePermissionPrompt: true`, i per tant no surt cap avís. `--allow-dangerously-skip-permissions`
    permet arrencar en un altre mode i passar a saltar els permisos amb Maj+Tab.
  - **Comprovació:** amb node, el `parseOptions` copiat del binari i `OpcionsClaude.analitza` llegeixen igual
    20.000 ordres a l'atzar, i les 13.052 ordres que en genera `OrdreClaude`. Ho fan igual els camps, el primer
    missatge i l'efecte de la resta d'opcions. Amb tres errors introduïts al parser, la comparació en troba 181,
    937 i 1.981 diferències. No és una prova del repo: necessita el binari de Claude i node.
- **Valors que Claude Code 2.1.318 no accepta** (04/11/2026, `claude --help` i el binari llegit sense executar-lo):
  - `--permission-mode` té `choices`: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk` i `plan`.
    Amb un altre valor, commander atura Claude amb un error.
  - `--effort` amb un valor desconegut **no** atura Claude: avisa («Unknown --effort value '…' — ignoring it and
    using the default effort») i fa servir l'esforç per defecte. Abans de comparar, treu els espais i passa a
    minúscules.
- **Valors per defecte** (03/11/2026, captura de la prova 1): sense `--effort` ni `--permission-mode`, la
  sessió va arrencar amb Opus 5.5, esforç `medium` i «auto mode», que són els valors de la configuració d'en David.
- **Notificacions a Warp** (03/11/2026, `warp.log`).
  - Claude Code envia a Warp seqüències OSC 777 amb `title=warp://cli-agent` i un JSON amb `agent`, `event`
    (per exemple, `tool_complete`), `session_id` i `cwd`.
  - Warp les apunta al log. Està per veure si serveixen per lligar cada pane amb la seva sessió.
- **Arguments de cada procés:** `ps` perd les cometes. L'`argv` exacte i l'entorn d'un procés propi es
  llegeixen amb `sysctl(KERN_PROCARGS2)` (prototip; vegeu `argv_env_de` a `prototip/espai.py`, a l'historial: `git show 114c97d:prototip/espai.py`). L'entorn
  inclou `WARP_TERMINAL_SESSION_UUID`. La revisió del 03/11/2026 en va llegir l'entorn de 6 processos.
- **Memòria** (03/11/2026, revisió): 14 sessions vives ocupaven 6,94 GB, una mitjana de 508 MB (de 354 a
  794 MB). Amb 64 sessions serien uns 32 GB. El Mac té 64 GB.

## Primera lectura real (03/11/2026, `warp-launch llegeix` 0.2.0)

- **Warp:** 7 finestres i 64 pestanyes de terminal. 64 de les 65 pestanyes tenen títol; la que no en té és
  la d'aquesta sessió.
- **Claude:** 13 sessions interactives, totes lligades amb la seva pestanya per `WARP_TERMINAL_SESSION_UUID`.
  La sessió `bg` es descarta.
  - Les 13 porten `--dangerously-skip-permissions --effort ultracode`, i 10 també `--continue`.
  - Cap no porta `-n`: tots els noms són `derived`.
  - 51 pestanyes no tenen Claude.
- **Carpetes:**
  - 23 s'han recuperat de l'historial, perquè el pane era a HOME.
  - 11 són a HOME i no tenen historial. Una és d'un agent que corre en un servidor remot.
  - **5 ja no existeixen:** l'historial apunta a `~/documents/github/empresa/web-*`, i els repos ara són a
    `~/GitHub/empresa-web/`.

## Primera importació (04/11/2026, `warp-launch importa` 0.7.0, sense desar)

- 7 finestres, 64 pestanyes: 48 amb Claude (13 de la seva ordre i 35 de la plantilla) i 16 sense (11 a `~` i 5
  amb una carpeta que no existeix). Són les xifres que preveia el disseny amb la lectura del 03/11/2026.
- Les 48 donen la mateixa ordre: `claude --dangerously-skip-permissions --effort ultracode --continue`. Les 3
  sessions que es van obrir sense `--continue` es desen amb continuar (R4).
- Noms de finestra: «empresa», «empresa 2», «Finestra 3», «personal», «Finestra 5» (cap carpeta pare no hi
  reuneix més de la meitat), «planta» i «Projectes».
- **Warp no té noms de finestra** (04/11/2026, `.schema windows` de `warp.sqlite` amb `?mode=ro`): la taula
  `windows` només té la mida, la posició, la pestanya activa i l'estat dels panells. Els noms els posa la
  importació de Warp Launch (docs/disseny.md, «Importació (R2)»), i «Finestra N» vol dir la N-èsima de la lectura.
- A les 13 sessions, la carpeta de Claude i la de la pestanya coincideixen. Cap sessió no porta primer missatge,
  `--resume <id>`, opcions d'un sol ús ni opcions desconegudes, i cap pestanya no està dividida.

## Prova 1 de l'app (04/11/2026, 0.5.0, l'obre en David amb `--config /tmp/warp-launch-prova1`)

App compilada en release i signada ad hoc, oberta amb `open "build/Warp Launch.app" --args --config …`. S'han
obert 0 finestres de Warp i 0 sessions de Claude.
- **Va bé:**
  - l'editor surt al davant i diu «Configuració de prova: /tmp/warp-launch-prova1», tant a l'estat buit com al
    menú de la icona i a la Configuració;
  - en arrencar, l'app és al Dock i a ⌘⇥, amb els menús en català (amb `.regular` a
    `applicationWillFinishLaunching`);
  - «Comença en blanc» i ⌘N («Finestra nova», «Finestra nova 2»);
  - en tancar l'editor, l'app desapareix del Dock;
  - 20 cicles de mostrar l'editor, ⌘N i tancar, sense cap bloqueig. El bloqueig que BAMA va veure no surt amb el
    patró d'amagar (`orderOut`);
  - amb l'app oberta, obrir-la des del Finder mostra l'editor;
  - ⌘, obre la Configuració al davant;
  - «Surt de Warp Launch» només tanca l'app: Warp i les sessions de Claude continuen igual.
- **No va:**
  - **⌘Z no feia res:** el menú consultava el Desfés de la finestra i l'editor registrava en el seu (vegeu «El
    Desfés d'una `Window` de SwiftUI»). **Corregit a 0.5.1 i provat:** «Desfés Nova finestra», ⌘Z i ⇧⌘Z
    funcionen, també després d'amagar i tornar a mostrar l'editor;
  - **l'app no pot llegir `warp.sqlite`**: el menú diu «Warp: no s'ha pogut llegir (error de SQLite:
    authorization denied)», i **macOS no ha mostrat cap diàleg de permís**. El CLI, executat dins de Warp, sí
    que la llegeix (vegeu «Primera lectura real»). Desmenteix la suposició que macOS demanaria permís.
- **Per què macOS no deixa llegir Warp** (04/11/2026; log unificat del procés de l'app, notes de versió de
  macOS 27 i desassemblat de `tccd`):
  - Notes de macOS 27 (161835690): l'accés als contenidors i Group Containers d'apps d'**un altre equip de
    desenvolupament** ja no pregunta: es denega per defecte i es gestiona a Privacitat i seguretat. A macOS 15
    encara hi havia diàleg.
  - Les dades són de Warp (equip 2BBY89MBSN, grup `2BBY89MBSN.dev.warp`). Warp Launch no té equip (ad hoc).
  - Log: TCC mira l'Accés complet al disc (no en té), després `kTCCServiceSystemPolicyAppDataDetailed`: «does not
    allow prompting for unentitled binaries; returning denied». Desa el bloqueig i mostra la notificació «Accés a
    les dades bloquejat. S'ha impedit que l'app Warp Launch accedeixi a les dades d'altres apps», amb el botó
    «Gestiona». Els intents següents es bloquegen sense cap notificació.
  - `open()` torna EPERM, i la SQLite d'Apple el dona com a `SQLITE_AUTH` (23), «authorization denied». Un fitxer
    amb permisos 000 (EACCES) dona el 14, «unable to open database file». Des de 0.5.1, l'app ho diu clar.
  - El CLI hi llegeix perquè macOS atribueix a Warp el que s'executa en una pestanya de Warp; Warp, a més, té
    Accés complet al disc (des del 01/11/2026).
  - La identitat de l'app ad hoc és el seu cdhash (`codesign -d -r-`): un permís donat a una compilació no val
    per a la següent (deducció, no provada).
  - A macOS 27, les apps no poden llegir la base de permisos de l'usuari (notes de versió, 90775556).
  - Decisió: D12 a `docs/especificacio.md` (certificat propi i permís només per a les dades de Warp).
- **Com es dona el permís (04/11/2026, 0.5.1 signada amb «Warp Launch Dev», ho fa en David; log de `tccd`):**
  - El permís és a Configuració del Sistema › Privacitat i seguretat › **Arxius i carpetes › Warp Launch.app ›
    «Dades compartides per l'app Warp i les apps afiliades»**.
  - L'entrada queda lligada a la identitat de la **primera** compilació que la va crear (aquí, l'ad hoc del
    03/11, `cdhash H"44b7…"`). Activar-la no serveix per a una app signada d'una altra manera: `tccd` diu «Failed
    to match existing code requirement» i «finegrained permission already exists», i no en crea cap de nova ni
    mostra cap notificació.
  - Per passar a una altra identitat, cal treure Warp Launch.app de la llista amb «−». El següent accés crea una
    entrada nova (denegada) per a la identitat actual, i llavors s'activa.
  - Un cop activat, s'aplica sense tornar a obrir l'app: «Torna a llegir Warp» ja llegeix.
  - Resultat: l'app mostra «Warp: 7 finestres · 64 pestanyes · 13 sessions de Claude», les mateixes xifres que
    `warp-launch llegeix` en aquell moment.
  - Que el permís duri en recompilar (identitat del certificat) està per verificar a la propera versió.

## Prova L1: obrir una finestra a Warp (05/11/2026, 0.20.2)

L'app, empaquetada i signada, l'obre en David amb `--config /tmp/warp-launch-provaL1`. La configuració té 1 finestra,
«Prova L1», amb 1 pestanya, «L1 docs», a `…/warp-launch/docs`. Warp és el 0.2026.10.21.08.25.02. En David l'obre 4
vegades (00:42, 00:43, 01:28 i 01:29), cada vegada després de tancar la finestra anterior. La primera, només terminal;
a partir de la segona activa Claude a la pestanya (`claude` sense opcions). Cada obertura és 1 finestra i 1 pestanya, i
de la segona a la quarta, 1 sessió de Claude nova. Comprovat amb el registre de l'app, `estat.json`, `warp-launch
llegeix`, la carpeta de launch configurations (llegida cada 0,2 s) i `warp.sqlite` (només lectura).
- **Warp accepta el fitxer que genera l'app** (yaml-rust): obre les 4 finestres. El YAML fa 248 bytes sense Claude i
  356 amb.
- **El fitxer temporal** apareix a la carpeta 0,08 s després d'escriure'l i en desapareix 0,7 s més tard (esborrat
  per l'app en veure la finestra).
- **Warp desa la finestra nova a `warp.sqlite` de seguida** (només amb la restauració de sessió activada; vegeu «Amb la
  restauració de sessió desactivada»)**:** les 4 vegades, l'app la veu a la primera lectura, 0,6 s
  després que `NSWorkspace.open` torni.
- **Warp desa el títol del fitxer com a títol de la pestanya** («L1 docs») **i la carpeta del `cwd`**, que `llegeix`
  dona del pane (no de l'historial). Vist a la 4a finestra, que queda oberta.
- **La marca funciona:** el `claude` de la pestanya porta `WARP_LAUNCH_PESTANYA` (`llegeix`: «pestanya afeb890d»), i la
  seva sessió surt entre 1,1 i 1,7 s després d'escriure el fitxer. `estat.json` lliga la pestanya al pane i a la
  conversa (origen `marca`).
- **Sense cap missatge, Claude no escriu la transcripció:** no hi ha `~/.claude/projects/…-warp-launch-docs/`. Per
  això, en tornar a obrir, el pla no la reprèn i en comença una de nova (D7, «enlloc»).
- **D16 desmentit: l'espai del davant no treu la línia de l'historial.** Les 3 línies amb Claude són a
  `~/.zsh_history` (`: <data>:0; WARP_LAUNCH_PESTANYA=… claude`): el zsh d'en David no té `HIST_IGNORE_SPACE` (`zsh -ic
  setopt` no el mostra). Warp també les desa a la seva taula `commands` de `warp.sqlite` (3 files, sense codi de
  sortida).

## Tornar a obrir totes les finestres des de l'app (05/11/2026, 0.21.0)

En David tanca a mà totes les finestres de Warp i n'obre les 6 de `/tmp/warp-launch-provaL3` amb «Obre a Warp…», una per
una, de 10:14 a 10:20. No fa «Lliga amb Warp…» (el registre no en té cap línia). Comprovat amb el registre de l'app,
`estat.json`, `warp-launch llegeix`, `ps` i `~/.claude.json` (només lectura).
- **Warp obre les 6 finestres i les 62 pestanyes.** Els 6 llançaments queden `confirmat`, amb la finestra vista en 0,5 a
  1,2 s (1,2 s, la de 22 pestanyes, amb un fitxer de 6.785 bytes). No queda cap fitxer temporal.
- **Cap conversa es reprèn des de l'app** (`0 reprenen` als 6 plans): sense lligar, `estat.json` no en recordava cap.
  Després, les 6 pestanyes de «Principal» tenen una conversa amb transcripció, i les 5 que eren vives abans de tancar
  tenen el mateix id: es van reprendre a mà, i `estat.json` les recull per la marca (`origen` `marca`). Reprendre amb
  `--resume` des de l'app encara no s'ha provat.
- **Claude no fa canòniques les rutes de la confiança: és un error de l'app, que sí que ho fa.** `~/Documents/GitHub` és
  un enllaç a `~/GitHub`. 17 de les 22 pestanyes de «Varis» no tenen cap clau `hasTrustDialogAccepted` amb la ruta
  `~/GitHub/…`: 12 només la tenen amb `~/Documents/GitHub/…`, i les 5 de `~/GitHub/empresa-web/` no en tenen cap. Són
  exactament les 17 on Claude no ha arrencat: 6 minuts després no tenen `~/.claude/sessions/<pid>.json`, fan uns 195 MB
  (les altres, uns 350 MB) i han gastat menys d'1 s de CPU. Les altres 45 pestanyes, totes amb la clau literal, sí que
  han arrencat. L'app només ha avisat de 5 (`LectorConfianca` fa canònica cada clau del fitxer). Que el que esperen és
  el diàleg de confiança es dedueix d'aquesta coincidència: encara s'ha de veure en una pestanya. **Corregit a la 0.21.1.**
  A les 10:50, les 22 carpetes de «Varis» ja tenen la clau literal acceptada: en David ha contestat les preguntes.
- **Memòria:** 62 processos de Claude, 17,6 GB en total (291 MB de mitjana, amb les 17 aturades), en un Mac de 64 GB.
- **Warp s'obre sol en iniciar sessió:** `AppAddedAsLoginItem = true` (`defaults read dev.warp.Warp-Stable`).

## Amb la restauració de sessió desactivada (05/11/2026, 0.22.0)

En David la desactiva a Settings de Warp a les 10:41:36 (`restore_session = false` a `[general]` de `settings.toml`), perquè
l'app la substitueix (D6). El primer Warp que arrenca sense restauració és el de les 10:42:03. Al codi públic, l'ajust es mira
a cada desat, de manera que reactivar-lo hauria de posar la base al dia de seguida. **No s'ha provat.**

- **Warp deixa de desar les finestres:** `warp.sqlite` queda congelat, i no diu què hi ha obert.
  - Al codi públic de Warp (`app/src/workspace/global_actions.rs`, `master` del 05/11/2026), `save_app` surt de seguida
    si `restore_session` és fals.
  - Comprovat a les 10:49: `windows` i `tabs` tenien les 5 finestres i les 57 pestanyes d'abans, i cap dels 6 panes de
    «Principal», oberta a les 10:42:09. Warp només tenia aquesta finestra. El registre mostrava més de 50 `save_app` des
    de l'arrencada.
  - Només s'hi afegeixen les ordres (`commands`): les 6 línies amb la marca, a les 09:42:10Z, amb `pwd` i `session_id`.
    Per això el `-wal` és de les 10:42:10 i ja no es mou.
  - Això corregeix «Warp desa la finestra nova a `warp.sqlite` de seguida» (prova L1): només amb la restauració activada.
- **Conseqüències que s'han vist a l'app 0.21.1:**
  - El bàner «No s'ha pogut reconèixer la finestra nova de «Principal» (s'ha vist Claude a 6 de 6)», després d'esperar
    30 s (`senseConfirmar`), encara que Warp l'havia obert bé.
  - Amb la base d'abans, el pla deia que **les 62 pestanyes ja eren obertes** i no n'obria cap: 56 «oberta a Warp, sense
    Claude» i les 6 de «Principal», «tancada fa menys d'1 minut». Calculat amb les dades reals, sense obrir res.
- **En arrencar, Warp obre una finestra buida** (`open_from_restored`, `open_new`, «Opening window with id 0», un shell a
  la carpeta d'inici). En David la va tancar a les 10:42:15. L'app no la pot tancar (regla 2).
- **Què se'n pot saber sense la base** (05/11/2026, només lectura):
  - **Els processos, que és el que fa servir l'app:** cada terminal viu és un fill de `stable terminal-server`. El 05/11/2026,
    6 `-zsh -g --no_rcs`, un per pestanya de «Principal». No cal cap permís, i és l'estat d'ara mateix.
  - **Del shell** se'n sap el pid, el tty i la carpeta de treball (`proc_pidinfo`, `PROC_PIDVNODEPATHINFO`). **El seu entorn
    surt buit** a `KERN_PROCARGS2`: Warp l'hi posa després d'arrencar, i el pane no es pot llegir del shell.
  - **Dels fills del shell**, sí: un `claude` porta `WARP_TERMINAL_SESSION_UUID`, `WARP_LAUNCH_PESTANYA` i
    `WARP_FOCUS_URL` (`warp://session/<pane>`). I el porta encara que s'hagi aturat a preguntar si confies en la carpeta,
    quan encara no ha escrit `~/.claude/sessions/<pid>.json`.
  - **No se'n sap:** en quina finestra és cada terminal, el títol de la pestanya, ni el pane d'un shell sense fills.
  - **Altres fonts mirades:** el CLI de Warp (`stable --help`) no llista res. Accessibilitat necessita permís (`AXIsProcessTrusted`
    fals; `kAXErrorAPIDisabled`), i no s'ha provat amb permís. `CGWindowList` dona les finestres i la mida, sense títols. El
    registre (`warp.log`) diu «Opening window with id N», «Successfully spawned child zsh process with pid P» i
    «WindowId(N) will close», però és un format intern que pot canviar.
- **Una pestanya tancada a mà continua semblant oberta 1 minut:** Warp manté el shell 60 s per poder-la desfer. Abans es
  detectava perquè el pane ja no era a la base. Deduït dels fets de «Processos» i del codi públic de Warp (`master` del
  05/11/2026, que potser no és la versió instal·lada): `UndoCloseStack.push_item` només mira `undo_close.enabled` i el
  `grace_period` (60 s), i no `restore_session`; el `settings.toml` d'en David no defineix `undo_close`. **Encara no s'ha vist
  amb la restauració desactivada.**

## Si l'app activés i desactivés `restore_session` sola (05/11/2026, només codi públic)

Llegit del codi públic de Warp (`warpdotdev/warp`, `master` del 05/11/2026, que potser no és la versió instal·lada). **No s'ha
provat res al Mac:** l'ajust real continua a `false`.

- **Warp hauria de notar el canvi sense reiniciar-se.** `settings/init.rs` vigila `settings.toml`: `reload_from_disk` i
  `reload_all_public_settings`. I `save_app` (`workspace/global_actions.rs`) mira l'ajust a cada desat.
- **Warp només desa si passa alguna cosa.** `save_app` el criden: moure, redimensionar o tancar una finestra, canviar de finestra
  activa (`app_callbacks` a `lib.rs`), les accions de la finestra de Warp que ho demanen (`should_save_app_state_on_action`) i
  una pregunta a l'agent de Warp. **Cap temporitzador.** Si en David no toca Warp mentre l'ajust és actiu, no es desa res.
  - Registre real (`warp.log`, 10:37 a 10:59): de 2 a 32 `save_app` per minut, en 20 dels 23 minuts. De 11:00 a 11:05, cap.
- **Cada canvi va al núvol.** L'ajust és `SyncToCloud::Globally(RespectUserSyncSetting::Yes)`, i al `settings.toml` real
  `is_settings_sync_enabled = true`. En recarregar el fitxer, `load_value` emet el canvi, `register_setting_events` el passa a
  `LocalPreferencesUpdated`, i `cloud_preferences_syncer` el puja amb 500 ms d'espera (`PREFERENCES_DEBOUNCE_PERIOD`). Si el valor
  torna a ser el mateix abans dels 500 ms, no puja res.
- **El núvol pot escriure l'ajust.** `maybe_sync_cloud_pref_to_local` aplica el valor del núvol i el desa al fitxer si és diferent
  del local. No sabem si Warp rep el seu propi canvi de tornada: si arribés tard, podria deixar l'ajust activat. Cal mirar-ho.
- **En arrencar,** Warp compara el fitxer amb el hash de l'última sincronització (`SettingsFileLastSyncedHash`). Si difereix,
  guanya el fitxer. Si és igual, guanya el núvol. L'ajust només es mira per restaurar a l'arrencada (`settings/init.rs:150`,
  `root_view.rs:777`): el que compta és el valor que hi hagi quan Warp arrenca.

## Prova real de la 0.23.0: l'app refresca la foto (05/11/2026)

En David surt de l'app i demana empaquetar-la i obrir-la. Mostreig de `warp-restauracio.sh estat` cada segon, mida i data de
`warp.sqlite-wal`, comptatge de `warp.sqlite` en només lectura (`?mode=ro`) i `warp-launch llegeix`.

- **En obrir l'app (22:05:00):** l'ajust passa a `true` a les 22:05:01 i torna a `false` a les 22:05:06. Warp desa (el WAL canvia
  a les 22:05). Després, 44 s seguits a `false`.
- **Refresc dels 5 min (22:10:19):** `true` durant 6 mostres, `false` a les 22:10:25, i 156 s seguits a `false`. El WAL canvia a les 22:10.
- **La foto quadra:** 6 finestres, 62 pestanyes i 62 panes a la base; 62 terminals vius als processos, tots amb Claude.
- **No s'obre ni es tanca cap finestra.**
- **El registre de l'app no diu res** si el refresc va bé: `Registre.refresc` només escriu avisos i errors.
- No s'ha provat: «Torna a llegir Warp» des del menú, ni Warp tancat, ni l'eco del núvol durant hores.

## Proves reals de la 0.26.0 (06/11/2026)

En David fa les proves 1 a 4 amb el paquet 0.26.0 (signat amb «Warp Launch Dev») i diu que totes funcionen. El registre de
l'app (`log show`, subsistema `cat.davide.warp-launch`) en recull dues obertures:
- **Reprendre una conversa des de l'app (11:24).** Pla: 1 pestanya a obrir, amb Claude, que reprèn la seva conversa; 21 ja
  obertes; 1 avís. Fitxer de 568 bytes, confirmat en 0,6 s amb 1 sessió de Claude vista, i fitxer esborrat. És la primera
  vegada que l'app reprèn una conversa amb `--resume` (el 05/11/2026 no se'n va reprendre cap).
- **«Obre-ho tot a Warp…» (11:26).** El pla troba 1 finestra de 6 per obrir; s'obre amb 2 pestanyes i 2 sessions, confirmada en
  0,6 s, fitxer de 978 bytes esborrat. Resum: «1 de 1 correctes».
- **Proves 3 (finestra oberta en part) i 4 (prova 8, l'editor):** correctes segons en David. El registre no en té cap altra
  obertura: la prova 8 no n'obre cap, i de la 3 no se'n va desar cap línia.

## Primer reinici amb l'arrencada en iniciar sessió (06/11/2026, 0.27.2)

Llegit al registre de l'app (`log show`, procés `WarpLaunch`), a `~/Library/Logs/warp.log.old.0` a `.old.2` i amb `ps`.
- **12:04:24:** abans d'apagar, Warp fa `save_app`: la restauració era activada en aquell moment (el refresc de cada 5 minuts, D19).
- **12:06:21** el Mac arrenca; **12:06:56** Warp Launch s'obre sola (l'ítem d'inici funciona) i **12:06:58** prepara el full: «6 finestres
  de 6», amb Warp ja obert.
- **12:06:58, Warp s'obre sol** i restaura (`open_from_restored`): 6 finestres i 62 terminals, sense Claude (Warp només en restaura la
  carpeta). El 05/11/2026, amb la restauració desactivada, Warp havia obert una sola finestra buida. **La restauració, doncs, era
  activada en arrencar**, encara que `settings.toml` digui `false`. **Deduït, no vist:** el valor del núvol (Settings Sync), que a
  l'arrencada guanya si el fitxer no ha canviat des de l'última sincronització. `settings.toml` es torna a escriure a les 12:07:03.
- **Qui va obrir Warp:** no l'app (no escriu res fins a les 12:08:05, després del clic). En David diu que havia tret Warp dels ítems
  d'inici. `settings.toml` no té `login_item`, que per defecte és `true`. ~~Deduït, no vist: Warp s'hi torna a afegir quan arrenca;
  s'ha de desactivar a la configuració de Warp.~~ **Desmentit el 07/11/2026:** en David diu que l'opció de Warp sempre ha estat
  desactivada, i segons el codi de Warp no es torna a registrar si `AppAddedAsLoginItem` ja és `true` (vegeu «Restauració
  de sessió i arrencada»). Tampoc no sembla l'opció de macOS de tornar a obrir les finestres: `defaults read com.apple.loginwindow
  TALLogoutSavesState` diu `0`, i el fitxer no ha canviat des de l'01/11/2026. No hi ha cap LaunchAgent de Warp
  (`~/Library/LaunchAgents`, `/Library/LaunchAgents`). **No se sap qui el va obrir:** es mirarà al pròxim reinici.
- **En David tanca Warp** (12:07:52, l'app ho veu en fer clic i torna a demanar confirmació) i a les 12:08:05 l'app l'obre i obre les 6
  finestres: 62 pestanyes, totes amb Claude, confirmades en 1,6 a 4,8 s.
- **Risc vist:** si hagués fet clic sense tancar Warp, l'app hauria obert les 62 pestanyes una altra vegada, perquè no reconeix les que
  restaura Warp (sense Claude ni marca). **0.27.3:** el full diu quantes pestanyes no reconeix; la foto només es fa quan en David ho demana.

## Ítems d'inici de macOS (06/11/2026, macOS 27.2)

- **El tauler es diu «Ítems d’inici de sessió»** (General › Ítems d’inici de sessió, i el títol del tauler), amb l'apòstrof
  tipogràfic: captura d'en David del 06/11/2026. `GeneralSettings.appex` també té la clau «Login Items & Extensions» = «Ítems
  d’inici de sessió i extensions», però no és el que surt (la revisió de la 0.27.0 s'hi va fiar; corregit a la 0.27.1).
- **`SMAppService.mainApp.register()` funciona amb el certificat «Warp Launch Dev»** (06/11/2026, 0.27.0, des de
  `/Applications`): en David activa l'interruptor i «Warp Launch.app» surt a «Obre en iniciar la sessió», amb la icona.
- **Per comprovar a la prova real (0.27.2):** si macOS envia `keyAELaunchedAsLogInItem` a una app registrada amb
  `SMAppService.mainApp`, i si el full surt de seguida en iniciar sessió.

## Les transcripcions de `~/.claude/projects` (05/11/2026)

Llegides amb Python, només lectura: 1.954 fitxers `.jsonl` de primer nivell, i els més recents de les 62 carpetes de la
configuració.

- **El primer missatge de l'usuari diu d'on ve la conversa** (`entrypoint`): 1.156 `cli`, 776 `sdk-cli` (`claude -p`) i 6
  `claude-desktop`. Tots els missatges en porten; 16 fitxers no en tenen cap, i fan 3 KB com a molt.
- **El primer missatge pot ser lluny del principi:** mediana d'1 KB, percentil 99 de 143 KB i màxim de 894 KB. Amb 256 KB, 7
  converses reals semblaven buides.
- **La data del fitxer no és la de l'últim missatge.** Claude també l'escriu en tancar-se (`cost-state`, `mode`). De 59 tries, en
  38 es porten més d'1 dia, i en 16 més de 3. En una, el fitxer és de fa 4 dies i l'últim missatge, de l'01/08.
  Això corregeix «ordena igual que el darrer `timestamp`», que només s'havia mirat a les 3 més recents de cada carpeta.
- **No totes són converses:** de les 202 més recents de les 62 carpetes, 13 no tenen cap resposta de Claude (només un `/clear`, o
  «cd ..»), i 1 d'aquestes, només una de `<synthetic>`.
- **Una conversa pot acabar com a feina en segon pla:** les seves línies porten `sessionKind: bg` (18.892 a les 62 carpetes, cap
  altre valor). 7 són feines de principi a fi. En una carpeta, `729da814` és una feina del 28/10 sobre una conversa del 12/10, i la de
  la pestanya, `fb311c16`, és del 24/10. Ordenar per l'últim missatge sense treure les línies de feina hauria triat la feina.
- **La conversa més recent de cada carpeta:** 1.581 MB en total, mediana de 5 MB. Les més grans fan 222, 220, 208 i 204 MB.
  Les 62 pestanyes són a 62 carpetes diferents. La més vella és de fa 24 dies.
- **L'obertura de «Principal» de les 10:42 ja en va reprendre 6:** 5 mantenen l'id, i la sisena ja en té un altre (pid 49882:
  `--resume 57be83a4`, sessió `89bc5fd1`). El 05/11, en obrir-ho tot, en David reprèn `c932506d` (220 MB): s'obre. El temps no s'ha mesurat.

## Missatges entre sessions de Claude (05/11/2026, 2.1.318)

Mirat amb `ListAgents`, `~/.claude/sessions`, les transcripcions, el binari i dos avisos d'inactivitat sense text. Dos agents han
intentat desmentir-ho. **Un missatge real, amb l'OK d'en David:** de bypass a bypass, entra a la cua del líder (l'agent coordinador
d'un repo, que engega feines) a les 13:29:56Z i li passa al Claude a les 13:30:02Z, sense retenir-lo. Les seves tres respostes tornen igual.

- **La regla** (descripció de `crossSessionInbound` al binari): sense valor, un missatge entra sol si l'emissor i el receptor són
  de la mateixa classe, bypass amb bypass o prompting amb prompting. Si no, queda retingut per a una persona, en les dues
  direccions, i caduca. `auto` és de la classe prompting. El valor `accept` treu la comprovació. Cap dels 17 fitxers de configuració
  mirats no el té, i no hi ha `managed-settings`.
- **Estat a les 13:10:** 63 sessions, totes amb socket (`/tmp/cc-socks/<pid>.sock`). Les 62 interactives, totes obertes per l'app,
  són `bypassPermissions`. L'única fora és la feina `038157f7`, en `auto`.
- **Els dos avisos ho confirmen:** el de `coordinador-b8` (bypass) arriba a Claude en aquesta sessió (bypass). El de la feina en `auto`
  només surt com a línia de sistema, per a la persona. Els dos passen per la mateixa decisió que un missatge (llegit al codi).
- **Historial:** des de l'01/10, 9.171 lliuraments: 9.169 de bypass a bypass i 2 de prompting aprovats a mà. L'últim, el 03/11 a les
  09:42:37Z. Des de llavors, només 4 intents, cap entre dues sessions bypass: 1 per un nom mort, i 3 retinguts. Tots 7 retinguts
  des del 02/11 tenen una feina `--bg` pel mig: 5 caducats i 2 aprovats a mà. 5 els va retenir el líder, que és bypass.
- **`claude --bg` sense flag de permisos arrenca en `auto`. En reprendre sense flag, un `auto` desat torna, i un bypass desat no** (funció
  `Ce` del binari, i 7 feines reals): `c932506d` passa a `auto` el 03/11 a les 15:31Z, amb una ordre així del líder, i torna a bypass quan
  l'app l'obre amb el flag. Una feina en `auto` no pot passar a bypass sense reiniciar-se (llegit). 4 feines tenen
  `--permission-mode bypassPermissions` a `respawnFlags`.
- **Amb el flag, funciona, vist:** el líder engega `claude --bg --resume 038157f7 --dangerously-skip-permissions` amb `nohup` a les
  13:09:35Z. Surt la còpia `e1433ba3`, en `bypassPermissions` des d'aquell moment, amb el flag a `respawnFlags`. Ho fa pel seu compte: al
  seu transcript no hi ha cap instrucció d'en David sobre el mode de les feines.
- **Qualsevol opció en reprendre una feina aturada en fa una còpia** (`$n` del binari: `own-options`; un verificador n'ha executat el codi amb
  els `state.json` reals i dona els dos casos reals). A les 13:47Z, la mateixa ordre surt com a `cdf27fe3`. Sense opcions, a les 10:33Z:
  «woke session 2f6b949c with its saved options». Si no hi ha feina (`state.json`), l'opció no fa còpia: es queda el mateix id. Una viva sempre
  fa còpia. Un id curt, també (`unresolved`).
- **Qui engega feines:** des de l'01/10, 12 ordres, totes del líder: 10 sense flag i 2 amb. Totes amb `--bg` just després de `claude`; 10
  amb `cd … &&` al davant i 2 amb `nohup`; 7 amb `--resume`. El `CLAUDE.md` del seu repo és l'únic que deia com engegar-les (sense ampliar permisos); en David el canvia el mateix dia.
- **Les còpies són el problema de sota** (el líder, 05/11, 13:53Z, i les xifres ho aguanten): `c932506d` → `2f6b949c` → `038157f7` → `e1433ba3` i
  `cdf27fe3`. Els seus missatges anaven a còpies sense pestanya, i en David, a la pestanya de `c932506d`, no en veia cap.
- **Què pot fer anar una feina en bypass** (llegit al binari; dos agents ho han intentat desmentir i n'han corregit dues coses; cap camí
  no s'ha provat de punta a punta):
  - **Cap variable ni `--settings` no fixa el mode**, i una ordre de shell no hereta res de la sessió mare (`rae` amb `"shell"`).
    `--inherit-permission-mode` només el fa servir `claude agents`.
  - **`permissions.defaultMode: bypassPermissions` a `~/.claude/settings.json`:** una feina nova, sí. Una represa amb `auto` desat, no: `Ce`
    posa `auto` al damunt. A més, afecta tots els `claude` sense flag del Mac, i un `defaultMode` d'un repo guanya (ara no n'hi ha cap).
  - **`CLAUDE_ENV_FILE`:** Claude llegeix el fitxer un cop per sessió i l'enganxa abans de cada ordre de Bash, també si el posa l'usuari
    (`Sts`); si no hi és, no diu res. Els ganxos de sessió fan servir un fitxer seu. És el que fa l'app des de la 0.22.3 (`EntornClaude`).
    La variable passaria al servei de feines i a totes les feines, com la marca de l'app (el 05/11, un `bg-spare` portava la del líder): per
    això el fitxer fa `unset`. Una feina no es pot reconèixer des del seu Bash: `Zo` treu `CLAUDE_CODE_SESSION_KIND` (llista `agt`). Si el servei
    l'engega la mateixa pestanya, sense passar pel Bash, la variable hi arriba igualment (llegit): una feina d'aquell servei tindria la funció.
    **Prova real (05/11/2026, 14:46Z, 0.22.3, amb l'OK d'en David, 1 feina):** després de reobrir les finestres des de l'app, el procés de la pestanya
    porta la variable; al seu Bash ja no hi és (`unset`) i `claude` és la funció. `claude --bg -n warp-launch-prova-feina "…"`, sense cap flag, crea `6b18e0b0`:
    `respawnFlags` amb `--permission-mode bypassPermissions` i totes les línies `permission-mode` de la transcripció en `bypassPermissions`. Un `SendMessage`
    enviat a les 14:47:3x hi és a les 14:47:36Z amb `from-mode="bypass"`, sense retenir, i la resposta torna sola. No prova els casos que la funció no cobreix.
    A zsh, `which claude` escriu el text de la funció, com ja passa amb `pkill` o `find` a la instantània; `whence -p claude` dona la ruta.
  - **`CLAUDE_CODE_PROCESS_WRAPPER`:** no és de la pestanya sinó de tot el supervisor, que es retiraria; descartat.
- **`--resume` d'una conversa viva en fa una còpia amb un altre id** (`c932506d` → `2f6b949c` → `038157f7`). `claude stop` fa caducar els
  missatges retinguts al receptor.
- **El nom canvia a cada arrencada:** el líder ha estat `coordinador-63`, `coordinador-c6` i `coordinador-b8`. El sufix és a l'atzar per procés
  (llegit), i el socket porta el pid. Dels 9.408 `SendMessage` des de l'01/10, 15 han fallat per nom i 12 per socket; al novembre, només
  1. `--name` el fixa (llegit, i vist en feines; no en pestanyes). A la configuració, 0 de 62 pestanyes el fan servir.
- **Fins a la 0.22.2, Warp Launch no hi influïa:** les 62 ordres només tenen dues formes, sense res de missatgeria. La marca `WARP_LAUNCH_PESTANYA` s'hereta
  a les feines que surten del Bash d'una pestanya (la feina porta la del líder), però `LectorSessions` només la llegeix a les interactives.
- **El tall del 03/11 va ser un panic del Mac** a les 13:10:11Z (`.contents.panic`: «watchdog timeout», «100% of segments limit (BAD)
  with 76 swapfiles»), abans de crear-se `espai` (16:41Z) i aquest repo (17:04Z). Hi ha un segon reinici a les 14:22 local, amb el botó.
  No se sap quin procés va omplir la memòria: l'informe no porta la llista de processos.
- **Memòria amb les 62 obertes** (05/11, 13:34): 69 processos de Claude, 20,8 GB de 64 GB; `memory_pressure` diu 73% lliure, sense swap.

## Foundation i JSON (03/11/2026, macOS 27.2)

- **Claus repetides:** `JSONSerialization` i `JSONDecoder` es queden amb la **primera** aparició, sense error ni avís.
  `jq`, `python3 -m json` i `plutil -convert json` es queden amb l'**última**. Comprovat amb `{"a": true, "a": false}`
  per la revisió del format v1. `KeyedDecodingContainer.allKeys` tampoc no mostra els duplicats.
- `JSONEncoder` amb `.sortedKeys` ordena per bytes: `modePermisos` va abans de `model`.
- **`JSONSerialization` no és `JSON.parse`** (04/11/2026, revisió del pas 6, comparat amb node en 36 casos):
  accepta comes finals (`{"a":1,}`, `[1,]`), que `JSON.parse` rebutja; i rebutja `1e400` i una meitat de parell
  sola (`"\ud800"`), que `JSON.parse` accepta. La resta de casos coincideixen (zeros inicials, `NaN`, `.5`, claus
  sense cometes, caràcters de control, escapaments). Per això `--settings` es valida amb `JSONEstricte`.
- **`F_GETPATH` només normalitza el que existeix** (04/11/2026): d'una carpeta que existeix, torna la ruta amb
  els enllaços resolts, les majúscules del disc i sense `/System/Volumes/Data`. D'una que no existeix,
  `Rutes.canonica` torna la ruta tal com és: per comparar-la, cal fer canònic l'avantpassat que existeix.
- `NSJSONSerializationErrorIndex` és l'índex en bytes UTF-8, sense el BOM.
- `URL.resolvingSymlinksInPath()` no resol un enllaç trencat: torna la ruta de l'enllaç tal qual, i un `rename`
  hi posaria un fitxer normal al damunt. `attributesOfItem` no segueix els enllaços (dona els permisos de l'enllaç).
  Comprovat per la revisió del magatzem (pas 3).
- Un fitxer bloquejat al Finder (`chflags uchg`): `FileManager.isWritableFile` dona `false` i `rename` al damunt
  dona `EPERM`. Comprovat al scratchpad.
- **zsh i les cometes** (04/11/2026, `OrdreClaudeTests.elTextEsLlegeixIgualAZshIASh`, amb `zsh -f` i `/bin/sh`):
  una paraula sense cometes que comença per `=` es converteix en la ruta de l'ordre (`=ls` → `/bin/ls`, l'opció
  `EQUALS` de zsh, activa per defecte). Sense cometes al `=` inicial, la prova falla; amb cometes, zsh i sh tornen
  exactament el mateix `argv`, també amb `'`, `"`, `$`, `` ` ``, `!`, `~`, `*`, `{a,b}`, `#`, `^`, salts de línia i accents.

## Entorn de desenvolupament (03/11/2026)

- **Màquina:** Apple M4 Max, 64 GB, macOS 27.2.
- **Swift i Xcode:**
  - Swift 6.4.2 de les Command Line Tools (`xcode-select -p` → `/Library/Developer/CommandLineTools`).
  - Xcode 27.2 és a `/Applications`. En David n'ha acceptat la llicència el 03/11/2026, amb la ruta completa.
  - **Configuració inicial d'Xcode:** abans de fer-la, `xcodebuild -checkFirstLaunchStatus` acabava amb 69 i
    `actool` fallava amb «A required plugin failed to load. Please ensure system content is up-to-date — try
    running 'xcodebuild -runFirstLaunch'». En David va executar
    `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch` el 03/11/2026, i ara
    l'estat és 0.
  - **`sudo xcodebuild -license accept` no serveix** mentre `xcode-select` apunti a les Command Line Tools: dona
    «tool 'xcodebuild' requires Xcode, but active developer directory … is a command line tools instance»
    (03/11/2026, executat per en David).
  - S'ha de fer amb la ruta completa: `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license accept`.
    Aquest binari respon a `-version` sense llicència.
  - Després es pot fer servir amb `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, o per defecte
    amb `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Això segon afecta tots els projectes del Mac.
- **La icona es compila i es revisa amb Xcode 27.2** (03/11/2026, amb una icona de prova d'una capa PNG):
  - `actool` escriu `Assets.car` (1,7 MB) i `AppIcon.icns` (42 kB).
  - L'`ictool` d'Icon Composer dibuixa els aspectes Default, Dark, TintedDark i ClearLight.
  - Si falta una capa, `actool` acaba amb error: «The layer "principal" references an image named
    "principal.png" that does not exist».
- **Què funciona amb les Command Line Tools** (comprovat amb un paquet de prova): SwiftUI i `import SQLite3`
  compilen, i `swift-testing` (`import Testing`) funciona. **`import XCTest` no**: «unable to resolve module dependency».
- **Macros amb les Command Line Tools** (03/11/2026, en compilar el pas 4): hi ha els connectors
  `libObservationMacros`, `libSwiftMacros` i `libTestingMacros` (`…/usr/lib/swift/host/plugins/`), però **no els
  de SwiftUI**: `@Entry` falla amb «plugin for module 'SwiftUIMacros' not found». `@Observable` funciona. Per
  tant, res de `@Entry` ni `#Preview`: les claus d'entorn i de focus s'escriuen a mà.
  - **`@State` també és una macro** (`SwiftUIMacros.StateMacro`, 04/11/2026, pas 8): falla igual, amb un `Bool`, un
    `String` o una classe. La propietat es declara amb el tipus, sense l'atribut: `private var x = State(initialValue:
    false)`, i es fa servir `x.wrappedValue` i `x.projectedValue` (el `Binding`). `@FocusState` i `@Bindable` sí
    que compilen. A la prova 2 (04/11/2026) el full d'importació i «+» (Nova pestanya…) han funcionat en pantalla.
- `UndoManager` amb `groupsByEvent = false` i un grup explícit per canvi: desfer i refer funcionen sense bucle
  d'esdeveniments (proves de l'editor, 03/11/2026).
- **SwiftUI i AppKit (macOS 27.2, 03/11/2026):** la vista d'un `NSViewRepresentable` dins d'una `Window` arriba a
  la finestra (`viewDidMoveToWindow`) **abans** que la finestra sigui visible (`isVisible == false`), tant en
  arrencar com amb `openWindow`.
  - En arrencar, `AppKitWindowController.windowDidLoad` crida `sizeAndPlaceWindow`, que fa `setContentSize:` (de la
    mida ideal a la de `defaultSize`) i hi insereix la vista. Després ve `makeKeyAndOrderFront:`.
  - AppKit, a `_reallyDoOrderWindowAboveOrBelow:`, fa `displayIfNeeded` abans de `_setVisible:`.
  - SwiftUI posa el seu delegat (`setDelegate:`) abans de dimensionar la finestra, i no crida mai
    `setActivationPolicy:` ni `activate`.
  - Com es va comprovar: revisió del pas 4, desassemblant el SwiftUI del sistema amb lldb, i amb un programa que
    crea la finestra amb la política `.prohibited` i sense mostrar-la. **No s'ha obert cap finestra.**
- **El Desfés d'una `Window` de SwiftUI és el de la finestra, i el delegat no el pot canviar** (04/11/2026, dues
  investigacions independents després de la prova 1; desassemblat d'AppKit i SwiftUI amb lldb i rèpliques sense
  finestres visibles):
  - En preparar la vista (`NSHostingView.updateEnvironment` → `NSView.inferredGraphTraits`), SwiftUI demana
    `undoManager` a la finestra abans que l'app hi pugui posar el seu delegat. AppKit en crea un i el desa.
  - `-[NSWindow _getUndoManager:]` torna el desat **abans** de preguntar `windowWillReturnUndoManager:` al delegat,
    així que un delegat posat després no es consulta mai.
  - Edició › Desfés és `undo:` sense destinatari: arriba a `-[NSWindow undo:]`, que fa servir aquest UndoManager.
    `@Environment(\.undoManager)` també és aquest. SwiftUI no en té cap de propi.
  - Un `TextField` fa servir un UndoManager propi mentre s'hi escriu (i després passa al de la finestra). Un
    `TextEditor` (NSTextView) registra al de la finestra sense obrir cap grup: si aquest tingués
    `groupsByEvent = false`, l'app petaria a la primera tecla (`NSInternalInconsistencyException`).
  - Per això l'editor fa servir el Desfés de la finestra (0.5.1), sense tocar-ne `groupsByEvent`.
  - Conseqüència (04/11/2026, revisió del pas 10, programes de prova fora del repo, sense finestres): amb
    `groupsByEvent = true`, `beginUndoGrouping()` al nivell 0 obre també el grup de l'esdeveniment (`groupingLevel`
    2 després del begin, 1 després de l'end). Dos passos explícits dins del mateix esdeveniment («Canvia el nom» i
    «Mou la pestanya») es desfan amb un sol ⌘Z, mentre que a les proves (`groupsByEvent = false`) són dos. Per això
    una ordre que tanca el camp del nom hi posa el nom dins del seu propi pas (`prenNomPendent`).
  - **Arrossegar a una `List` (04/11/2026, SDK de les CLT de macOS 27.2, sense obrir cap app):**
    - `onMove`: la destinació és la de `move(fromOffsets:toOffset:)`, és a dir la posició abans de treure les que es
      mouen (doc de SwiftUICore). Igual que `Configuracio.mouPestanyes`: una còpia de la lògica i `Array.move` donen
      el mateix en 200.000 casos aleatoris (agent de recerca) i en 186 casos a la prova `reordenarFaElMateixQueMove`.
    - A macOS, `List` és un `NSOutlineView` (`OutlineListCoordinator`, amb `moveCells(fromRows: Set<…>)`). El que
      escriu `onMove` a l'arrossegament és `com.apple.SwiftUI.listReorder`, que no és text ni un UTI declarat
      (cadenes del binari, lldb).
    - `ListOutlineItem.itemProvider` llegeix el trait de `.itemProvider(_:)` i, si la fila també es pot moure, els
      uneix (`NSPasteboardWritingUnion`): pot reordenar i portar el tipus propi alhora (binari; **cal veure-ho a la
      prova 6**, com que s'arrosseguin totes les triades).
    - `TransferRepresentation.visibility(.ownProcess)`: «visible only within the app that's the source of the item».
      Amb aquest tipus, `exportedContentTypes(visibility: .all)` és buit. La visibilitat és només d'exportació: no
      impedeix llegir. `importedContentTypes()` no en té, i `loadTransferable` carrega igual amb `.ownProcess` que
      sense, d'un proveïdor `.ownProcess`, d'un `.all` i d'un `NSItemProvider(item:typeIdentifier:)` (programes sense
      finestres i `dyld_info -imports` de SwiftUI, 04/11/2026). Des de la 0.13.0, `PestanyaArrossegada` només importa
      (`DataRepresentation(importedContentType:)`): no exporta res (prova `elQueSArrossegaNomesEsDadesDAquestaApp`).
      La barrera és el proveïdor de la fila (`registerDataRepresentation(…, visibility: .ownProcess)`).
    - `DragConfiguration`, per defecte a macOS: «drag-to-copy to destinations both within the application and to
      other apps». `OperationsOutsideApp` s'ha de crear amb `init(allowCopy:allowMove:allowDelete:)`.
    - `reorderable()`, `reorderContainer`, `ReorderDifference` i `DropSession.reorderDestination` són només de macOS
      27 (amb el mínim a macOS 26, `swiftc -typecheck` dona «only available in macOS 27.0»).
    - Exemples de la doc que no compilen amb la interfície: `.index(in:)` (`reorderDestination`), `.ended(at:with:)`
      i `draggedItemIDs(type:)` (`onDragSessionUpdated`; la interfície té `.ended(DropOperation)` i
      `draggedItemIDs(for:)`), i l'ordre dels arguments de `DynamicViewContent.dropDestination` (és `([T], Int)`).
  - **Arrossegar entre finestres a la mateixa `List` (04/11/2026, pas 10b, després de la prova 6).** Mètode: lldb sobre
    programes de línia d'ordres sense finestres (aturats a `main`) amb el SwiftUI i l'AppKit de la shared cache de
    macOS 27.2, el runtime d'Objective-C i l'SDK de les CLT. **No s'ha obert cap app:** el que diu la llista en pantalla
    és per a la prova 7.
    - **La `List` no obre una fila en aturar-s'hi arrossegant** (prova 6: «la finestra no canvia»).
      `springLoadingBehavior(_:)` compila a la fila, però només el llegeixen `Button`, les pestanyes de `TabView` i
      l'`NSSpringLoadingDestination` de `NSHostingView`; cap símbol de `List` (`OutlineListCoordinator`,
      `SwiftUIOutlineListView`). L'`NSOutlineView` només ho fa per desplegar (`_scheduleAutoExpandTimerForItem:dragInfo:`).
    - Classes (runtime, `objc_copyClassNamesForImage`): la llista és `SwiftUI.SwiftUIOutlineListView` → `NSOutlineView`;
      cada fila, `SwiftUI.ListTableRowView` → `NSTableRowView`; cada cel·la, `SwiftUI.ListTableCellView` →
      `NSTableCellView`.
    - **Deixar anar a la mateixa `List`:** `outlineView(_:validateDrop:…)` registra «outlineView validateDrop target %s
      dragCanReadSynthesizedList %{bool}d emptyLocalDraggingItems %{bool}d» i només valida un reordenament
      (`validateReorder`, i torna `.move`, 0x10) si el porta-retalls té `com.apple.SwiftUI.listReorder` **i** la
      llista és la d'on surt l'arrossegament (`itemsBeingDragged` no buit; `cbz w21` i `cbz x22` a +8376 i +8380). Si
      no, passa al camí d'inserir (`ViewTraitCollection.insertInteraction`, el de `ForEach.dropDestination`), que torna
      `canReadItemWithDataConformingToTypes:` com a operació: 1, `NSDragOperationCopy` (el cursor porta «+»).
    - `itemsBeingDragged` es desa a `draggingSession(_:willBeginAt:forItems:)` i es buida a `…endedAt…`: no canvia si
      canvien les dades. `moveCells` troba cada fila per la posició desada (`ListOutlineItem.indexPath` →
      `ViewListTree.child(at:)`), en llegeix `DynamicViewContentOffsetTraitKey` i crida l'`onMove`; si la posició ja no
      existeix, `visitItem` acaba en `_assertionFailure` («TableViewListCore_Mac2.swift», línia 5556). Per tant, si la
      mateixa llista passa a mostrar una altra finestra, deixar-les anar mouria les pestanyes d'aquella posició o faria
      petar l'app. Una `List` amb una altra identitat (`.id`) té un altre coordinador i va pel camí d'inserir.
    - `ForEach(...).dropDestination(for:action:)` és `([T], Int)` (primer els elements) i està fet sobre `onInsert`:
      carrega cada `NSItemProvider` amb `loadTransferable` i crida l'acció a la cua principal, després de deixar anar.
      Posat abans d'`onMove`, el compilador no pot triar el de `View` (sense posició): `.onMove` no hi compilaria.
    - `NSDraggingSession` reté l'origen: `_source` és una ivar forta (layout d'ARC `52 21 16`, runtime). Si SwiftUI treu
      la llista d'on surt l'arrossegament, l'`NSOutlineView` continua viu fins que s'acaba; `delegate` i `dataSource`
      són `weak` (`NSOutlineView.h`).
    - `DropSession` (swiftdoc): `location`, «Location of drop in the local coordinate space»; `size`, «Size of the drop
      destination view». `onDropSessionUpdated` (macOS 26): «called when the closest drop session in the child view
      hierarchy becomes active», és a dir, per fora de `dropDestination`. Dins d'una `List`, `.active` només arriba quan
      canvia la zona on es deixarien anar, i no hi ha `.exiting` quan el cursor surt de tota la llista (SwiftUI no
      implementa `outlineView:draggingExited:`; binari, no s'ha vist en pantalla).
    - Bucle d'execució (programa sense finestres): una `Task` del `MainActor` amb `Task.sleep` de 0,5 s no es desperta
      en 3 s mentre el bucle corre en `.eventTracking` si aquest mode no és als comuns; un `Timer` afegit a
      `.eventTracking` salta als 0,505 s. Durant un arrossegament, AppKit fa servir
      `-[NSCoreDragManager _dragUntilMouseUp:modifiers:]`; quin mode fa servir no s'ha comprovat.
    - `NSEvent.pressedMouseButtons` és l'estat del ratolí en aquell moment, «not suitable for tracking» (`NSEvent.h`):
      serveix per mirar si el botó encara és premut quan salta un rellotge.
    - Al Mac d'en David, `defaults read -g com.apple.springing.delay` és 0.5 i `com.apple.springing.enabled`, 1
      (Accessibilitat › Control del punter).
  - **Arrossegar quan la llista d'origen desapareix** (04/11/2026, prova 7 d'en David, 0.13.0): obrir arrossegant
    una finestra buida canviava la `List` de pestanyes per un `ContentUnavailableView`. Llavors no s'acceptava la
    pestanya ni al panell (amb `dropDestination`) ni a la fila de la barra lateral, i en deixar-la anar tornava volant
    al seu lloc. Amb una finestra amb pestanyes (una `List` nova amb `.id`) i des de «Per revisar» (una altra `List`),
    sí que s'acceptava. La causa no s'ha comprovat; la 0.13.0 ja no obre les finestres buides arrossegant.
  - **La fila d'una finestra nova no acceptava pestanyes** (04/11/2026, prova 7b d'en David, 0.13.0): ni sense
    obrir-la, mentre que la d'una finestra amb pestanyes sí. La finestra nova estava triada quan es va crear (⌘N), i
    la seva fila tenia `dropDestination(for:isEnabled:)` amb `isEnabled` fals (la finestra que es veu). Hipòtesi: la
    `List` es queda els tipus acceptats de quan configura la cel·la (`ListOutlineItem.acceptedDropTypes` a
    `outlineView(_:configureCell:for:)`, al binari) i no els torna a mirar quan `isEnabled` canvia. La 0.13.0 treu
    `isEnabled` i ho decideix a `dropConfiguration` (`.move` o `.forbidden`, que l'SDK descriu com «The drop activity
    is not allowed at this time or location»).
    - **Resultat (prova 7b, amb el registre de l'app i el del sistema):** sense `isEnabled`, continua igual. La fila
      rep l'acció de deixar anar, però amb 0 pestanyes, i sense cridar la clausura d'importació. El registre del
      sistema (`/usr/bin/log show`, procés `WarpLaunch`, 18:47:36 i 18:47:43, i a les execucions de les 16:18, 17:47,
      18:06, 18:13 i 18:24) diu per què: `NSItemProvider` «Finished loading data representation for type identifier
      'cat.davide.warp-launch.pestanyes' with error» `NSItemProviderErrorDomain` -1000, amb `NSCocoaErrorDomain` 3072
      (cancel·lat) a sota, i després `com.apple.Transferable` «Error loading». La destinació no rep el proveïdor de
      l'origen: `DropInfo_Mac.itemProviders(for:)` en fa de nous amb el porta-retalls de l'arrossegament, que l'origen
      omple de manera diferida (`PasteboardWriter.make(from:)`, `PasteboardDataProvider`; binari, lldb). Per què es
      cancel·la, i per què a la fila de la finestra triada en obrir l'app no, no s'ha trobat.
    - La hipòtesi de la visibilitat (`.ownProcess`) també és falsa (vegeu més amunt). La d'`isEnabled`, no es pot
      descartar ni confirmar: no era la causa de les 0 pestanyes.
    - Per això, quan l'acció arriba sense dades, la 0.13.0 mou les pestanyes de l'última pulsació, fixades en passar
      per la fila, si la sessió és local i en porta les mateixes (docs/disseny.md, «Arrossegar»). Fets del binari de
      macOS 27.2 (lldb, revisió del 04/11/2026), que ho justifiquen:
      - en una `List`, SwiftUI crida la clausura de `.itemProvider` a `tableView(_:canDragRows:at:)` (la primera fila
        candidata, en prémer, encara que no s'arrossegui), a `tableView(_:shouldDelayFirstResponder:forRow:)` (un
        control de la fila) i a `outlineView(_:pasteboardWriterForItem:)`, un cop per fila arrossegada. No la crida
        per a la imatge de l'arrossegament ni en tornar a dibuixar;
      - `-[NSTableView mouseDown:]` arrossega `isRowSelected(clic) ? selectedRowIndexes : [clic]`. Sense modificadors,
        abans de canviar la selecció; amb ⇧ o ⌘ sobre una fila no triada, després de canviar-la. L'avís del canvi
        (`_enableSelectionPostingAndPost`) surt després dels proveïdors, i SwiftUI només actualitza la selecció a
        `outlineViewSelectionDidChange`: quan es demanen els proveïdors, la selecció de SwiftUI és la d'abans;
      - el tipus `.ownProcess` d'un proveïdor surt al porta-retalls de l'arrossegament (`PasteboardWriter.make(from:)`
        no filtra per visibilitat): una altra execució de l'app el pot validar. `DropSession.localSession` és nil
        per a un arrossegament que ve d'un altre lloc (SDK);
      - l'error -1000/3072 arriba entre 305 i 307 ms després de deixar anar (6 mesures del registre del sistema).
    - **Confirmat a la prova 7c** (04/11/2026, registre de l'app, 19:54:52 i 19:54:57): a la fila d'una finestra, la
      càrrega es torna a cancel·lar (-1000), i l'acció arriba amb `localSession` no nil i `itemsCount` 1 per a una
      pestanya arrossegada. Les fixades són 1 i es mouen. Amb dues pestanyes, no surt al registre.
    - `.forbidden` no mostra el cursor de prohibit (prova 7b): SwiftUI el tradueix a NSDragOperationNone (a la `List`,
      `handleDropInto` dona nil), i `-[NSDragDestination _setLastDragDestinationOperation:]` només posa
      `operationNotAllowedCursor` amb un bit privat (0x80000000); amb None hi posa la fletxa (binari, lldb). La fila
      de la finestra que es veu no accepta res igualment.
    - Les línies `.info` i `.debug` d'un `Logger` no es desen: després de la prova, `log show` no les torna. Les de
      deixar anar van a `.notice`. A les eines de Claude, `log` és l'ordre de zsh («too many arguments»): cal
      `/usr/bin/log`.
  - **⌃⌘I no arriba a l'ordre de l'inspector** (04/11/2026, macOS 27.2, proves 3 i 4 d'en David): ni amb
    `InspectorCommands()` ni amb una ordre pròpia amb `.keyboardShortcut("i", modifiers: [.control, .command])`.
    L'ítem surt al menú Visualització amb ⌃⌘I i actiu, i el clic hi funciona, com el botó de la barra d'eines. No hi
    ha cap drecera del sistema (`com.apple.symbolichotkeys`) ni cap app de dreceres que la faci servir. La causa no
    s'ha trobat (⌃I és el caràcter de tabulació). A la prova 5, ⌥⌘I (ordre pròpia) i ⌃⌘S (`SidebarCommands()`)
    sí que funcionen: no fallen totes les dreceres amb ⌃, només ⌃⌘I.
  - **Un interruptor (`NSSwitch`) no té estat mixt** (04/11/2026, `NSSwitch.h` de l'SDK: «If the state property is set
    to any other value, it is interpreted as on»). Un `Toggle(sources:)` amb valors diversos només es veu mixt com a
    casella (`.toggleStyle(.checkbox)`); en un `Form` agrupat, el `Toggle` per defecte és un interruptor.
- **Menús, Desfés de la Configuració i arrossegar, per al pas 11** (04/11/2026, macOS 27.2; lldb sobre programes de
  línia d'ordres sense finestres visibles, bolcat del menú principal amb la política `.prohibited` i un
  `NSHostingMenu` en lloc del `MenuBarExtra`). **No s'ha obert cap finestra.**
  - `CommandGroup(replacing: .saveItem) {}` treu Fitxer › Tanca (⌘W) i Tanca-ho tot (⌥⌘W): en una app sense
    documents, aquest grup només té aquestes dues. Fins a la 0.13.0, l'editor no es podia tancar amb ⌘W.
  - Cada finestra de SwiftUI té el seu Desfés. `SwiftUI.AppKitWindow` (la classe de les finestres de `Window` i de
    `Settings`) sobreescriu `_getUndoManager:`: primer el del document, després l'`UndoManagerKey` de l'entorn de
    l'escena i, si no n'hi ha, el de `NSWindow`. Cap classe implementa `windowWillReturnUndoManager:`. La
    Configuració té el seu `AppKitWindowController`, i per tant un Desfés diferent del de l'editor.
  - Els menús de `Commands` no canvien quan canvia un `@Observable`: s'actualitzen quan el delegat del menú
    (`AppKitMainMenuItem`) rep `menuNeedsUpdate:`, en obrir-lo o en buscar una drecera (NSMenu.h:311-313).
  - Al menú de la icona, `Section("…")` dona una capçalera i hi afegeix separadors; un `Divider` darrere fa dos
    separadors seguits. `Text` i `Label` són ítems desactivats.
  - **Esc a mig arrossegament:** `OutlineListCoordinator` (la `List` de SwiftUI) només envia `.exiting` a la fila des
    de `validateDrop`, i no implementa `outlineView:draggingExited:`. Després d'Esc, la fila no rep cap fase, i el
    rellotge de la molla obria la finestra. AppKit sí que treu la marca de destinació de la fila en sortir
    (`-[NSOutlineView draggingExited:]` → `setTargetForDropOperation:`; `NSTableRowView.isTargetForDropOperation` és
    públic, NSTableRowView.h:51).
  - Arrossegar és asíncron per defecte (`NSDragAsync`, `CoreDragStartDraggingAsync`). No s'ha comprovat si Esc arriba
    a l'app com a `keyDown`: es mira a la prova 8, amb el registre.
  - **La fila d'una `List` de SwiftUI no és mai la destinació d'AppKit** mentre s'hi arrossega (04/11/2026, prova del
    pas 11 amb la 0.14.0, registre de l'app): «destinació vista false» als 7 comptes de la molla, també als 2 que
    obren la finestra als 0,5 s. `isTargetForDropOperation` no hi serveix: o SwiftUI no marca la fila, o la molla no
    troba la `NSTableRowView` (el registre no ho distingeix).
- **Compilació:**
  - El sistema per defecte de `swift build` és `swiftbuild`.
  - **`swift test` falla de manera intermitent** amb «external macro implementation type
    'TestingMacros.TestDeclarationMacro' could not be found… plugin for module 'TestingMacros' not found».
    - El compilador no rep el connector `…/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`, tot
      i que existeix.
    - Freqüència: 2 fallades en 7 intents meus; la revisió en va tenir 7 de 13 partint de zero. Un cop falla,
      sol continuar fallant.
    - Solució: `-Xswiftc -plugin-path -Xswiftc <toolchain>/usr/lib/swift/host/plugins/testing`, que és el que
      fa `scripts/test.sh` (3 de 3 meus i 5 de 5 de la revisió).
    - `--build-system native` no serveix: dona «no such module Testing».
  - Els avisos de `ld` «search path '/Library/Developer/CommandLineTools/Developer/…' not found» són
    inofensius.
- **Signatura:** fins al 03/11/2026 no hi havia cap identitat de signatura (`security find-identity -p
  codesigning` → 0), i l'app es signava ad hoc (`codesign --sign -`).
  - Amb la signatura ad hoc, la identitat del `.app` és el seu cdhash, que canvia a cada compilació.
  - Per això macOS pot tornar a demanar els permisos (TCC) a cada compilació. Per exemple, el d'accedir a
    dades d'altres apps quan l'app llegeixi el Group Container de Warp. **Corregit a la prova 1 (04/11/2026):
    macOS 27 no demana res, denega l'accés sense preguntar** (vegeu «Prova 1 de l'app» i D12).
  - **Certificat propi (04/11/2026, D12, amb l'OK d'en David):**
    - «Warp Launch Dev», autosignat, només per signar codi (`extendedKeyUsage = codeSigning`, `CA:false`),
      vàlid fins al 01/11/2036. Empremta SHA-1: `C1EC55B1CB87C881A2C48A4F5256B10EBC12BCC6`.
    - Creat amb el LibreSSL de macOS (`/usr/bin/openssl` 3.3.6; el de Homebrew és OpenSSL 4) i importat al clauer
      d'inici de sessió amb `security import … -T /usr/bin/codesign`. Amb això, `codesign` el fa servir sense
      cap diàleg.
    - `find-identity` el mostra com a `CSSMERR_TP_NOT_TRUSTED` (no és de confiança), i `codesign` hi signa
      igualment.
    - La identitat de l'app passa a ser `identifier "cat.davide.warp-launch" and certificate leaf =
      H"c1ec55b1…"`, que no canvia en recompilar. Que el permís de TCC es mantingui entre compilacions està
      per verificar.
- **nano-banana (API d'imatges de Gemini)** (03/11/2026, `scripts/genera-imatge.sh --models` amb la clau d'en
  David). Models d'imatge disponibles:
  - `gemini-2.5-flash-image` (Nano Banana).
  - `gemini-3-pro-image` i `-preview` (Nano Banana Pro).
  - `gemini-3.1-flash-image` i `-preview` (Nano Banana 2).
  - `gemini-3.1-flash-lite-image` (Nano Banana 2 Lite).
  - `jq` és del sistema (`/usr/bin/jq`).
- **Altres eines:** `gh` 2.102, amb dos comptes (un de la feina, que és l'actiu, i `David-Erra`; per publicar, el token
  de `David-Erra` només per a aquella ordre: `GH_TOKEN="$(gh auth token -u David-Erra)"`), Homebrew 7.0, `uv`, Node 25 i Deno 2.6. No hi ha Rust.

## Mac d'en David

- **Repos:** agrupats en unes quantes carpetes pare, sobretot a `~/GitHub` (d'aquí surten els noms de finestra de la importació).
- **Python:** el de Homebrew, `/opt/homebrew/bin/python3`, 3.14.7 (03/11/2026).
- **Accessibilitat:** no està concedida a cap terminal (prototip).
