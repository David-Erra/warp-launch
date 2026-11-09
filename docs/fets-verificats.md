# Fets verificats

Entorn: un Mac de prova (Apple Silicon) amb macOS 27.2, Warp 0.2026.10.21 (canal Stable), Claude Code 2.1.317 i Swift 6.4.2.
El 07/11/2026, Warp 0.2026.11.04 i Claude Code 2.1.319 (recerca d'antecedents; les proves d'abans són amb les versions anteriors).
L'app no necessita Accessibilitat, i les proves s'han fet sense donar-la a cap terminal (prototip).

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
  - **La carpeta nova també hauria de veure-la** (09/11/2026, codi llegit, commit `abb3fe33e004`, no vist en execució): Warp en
    arrencar només assegura `~/.warp` (`ensure_warp_watch_roots_exist`), no `launch_configurations`; vigila `~/.warp` de manera
    recursiva (`app/src/warp_managed_paths_watcher.rs`) i recarrega les launch configurations quan el canvi toca aquesta ruta
    (`app/src/user_config/native.rs`). Per això, una carpeta creada amb Warp obert hauria de funcionar.
- **Les launch configurations són *legacy*:** «new features are not being added». Es recomanen els
  **Tab Configs** (`~/.warp/tab_configs/*.toml`), però cada Tab Config és **una sola pestanya**. Per agrupar
  pestanyes en finestres, avui només serveixen les launch configurations (03/11/2026, documentació).
- **`tab_configs/startup_config.toml`** («New tab: …», `type = "agent"`) és el Tab Config de la pestanya nova, no un de fet a mà (03/11/2026, `ls`).

### Restauració de sessió i arrencada

- **La restauració no torna a executar cap comanda** (prototip), i sovint perd la carpeta.
  - Amb el prototip, quatre de cada cinc pestanyes havien quedat a `~`.
  - El 03/11/2026, una mica més de la meitat dels panes tenien `cwd` = HOME; en dos terços d'aquests, el darrer `blocks.pwd`
    era una altra carpeta.
- **`general.restore_session`** («Whether to restore the previous session when Warp starts up»)
  (03/11/2026, `settings_schema.json` del bundle, `settings.toml` llegit sense modificar-lo, i
  `app/src/terminal/general_settings.rs`):
  - Per defecte és `true`: si `settings.toml` no la defineix, està activada.
  - **Que un usuari nou no té la línia és una deducció, no vista per a aquest ajust** (08/11/2026): al Mac de prova,
    `settings.toml` no tenia cap línia `login_item` (06/11/2026, «Ni `settings.toml` ni `AppAddedAsLoginItem`…», a sota), un
    ajust que val `true` de sèrie; d'aquí es dedueix que Warp només hi escriu els ajustos canviats. No s'ha vist amb un Warp
    net ni amb `restore_session`, i xoca amb el que recorda en David (l'opció de `login_item` sempre desactivada: si era així,
    Warp tampoc no l'hi va escriure). Sobre aquesta deducció, la 0.31.2 hi afegeix la línia si no hi és (decisió A). Es
    comprovarà amb un usuari de macOS nou (`docs/disseny.md`, secció 10, «Per provar en un usuari de macOS nou»).
  - **Com escriu Warp `settings.toml`** (08/11/2026, codi públic de `warpdotdev/warp` a `abb3fe33`, `master` del 06/11/2026, que
    potser no és la versió instal·lada; llegit, no vist):
    - Té tot el document a la memòria (`toml_edit`) i, a cada canvi, el torna a escriure sencer amb `std::fs::write`
      (`crates/warpui_extras/src/user_preferences/toml_backed.rs`, `flush`). **No és atòmic:** buida el fitxer i l'escriu. Qui el
      llegeixi en aquell moment el pot veure buit o a mitges. Abans, crea la carpeta si no hi és (`create_dir_all`).
    - Només escriu quan canvia un ajust: amb el fitxer absent, el document comença buit i no es desa res fins al primer canvi.
      Això reforça la deducció d'aquí sobre: un usuari nou que no ha canviat res no té `settings.toml`.
    - **Migració única** (`app/src/settings/init.rs`, `needs_settings_file_migration`): en arrencar, si `settings.toml` no
      existeix i a les preferències pròpies de Warp (a macOS, `NSUserDefaults`) no hi ha la marca de migració feta, hi passa els
      ajustos que tenia a les preferències de macOS i després hi posa la marca. Per a un usuari nou no hi passa res, però la
      marca s'hi escriu igualment. **Si algú crea `settings.toml` abans que aquesta migració s'hagi fet, Warp se la salta:** els
      ajustos d'un Warp antic (d'abans de `settings.toml`) deixarien de comptar. D'aquí la decisió de la ronda 5: l'app només
      crea el fitxer amb Warp obert (0.31.3).
  - **Quan fa Warp la migració, en arrencar** (08/11/2026, el mateix codi de `abb3fe33`; llegit, no vist):
    - A `app/src/lib.rs` (`run_internal`), Warp primer llegeix `settings.toml` (`init_public_user_preferences`, l. 1189),
      després crea el `terminal-server` (`PtySpawner::new`, l. 1221) i després fa la migració (`initialize_app` →
      `settings::init`, l. 1540). Les finestres, i els seus terminals, només arriben a `launch()`, després d'`initialize_app`.
      **Per tant, el `terminal-server` sol no diu que la migració ja s'ha fet; un terminal, sí.** És el criteri de la 0.31.3
      per crear `settings.toml` (`FontProcessos.warpHaAcabatDArrencar`), en lloc d'un temps d'espera.
    - El `terminal-server` és fill de l'app (`Command::spawn`, `crates/warp_terminal/src/local_tty/server/mod.rs`) i s'atura sol
      quan canvia de pare (`server/event_loop.rs`, l. 223): un d'orfe no és d'un Warp que corre.
    - Si el `terminal-server` no es pot fer servir, Warp obre els shells directament (`local_tty/spawner.rs`,
      `spawn_pty_directly`). Llavors l'app no en veuria cap terminal, i no crearia `settings.toml`. No s'ha vist mai.
  - **L'onboarding d'un usuari nou** (08/11/2026, especificació `specs/APP-3680/TECH.md` del mateix codi; llegida, no vista):
    en acabar-lo, Warp n'aplica els ajustos (`apply_agent_settings`, per exemple `DefaultSessionMode`) i, amb dos flags
    activats, pot escriure `~/.warp/tab_configs/startup_config.toml`. Si aplicar-los desa `settings.toml` (Warp desa cada canvi
    d'ajust), un usuari nou que l'acaba ja en tindria, i la deducció «un usuari nou no té `settings.toml`» només valdria abans
    de l'onboarding. Es mira en un usuari de macOS nou (`docs/disseny.md`, secció 10).
  - Se sincronitza al núvol (`SyncToCloud::Globally`) si Settings Sync és activat (es mira amb
    `defaults read dev.warp.Warp-Stable IsSettingsSyncEnabled`). Si es canvia, es propaga
    a les altres instal·lacions de Warp del compte.
- **Warp és un ítem d'inici de sessió:** `general.login_item` és `true` per defecte, i s'obre sol en iniciar
  sessió (03/11/2026, revisió del codi). Cal coordinar-ho amb l'arrencada de Warp Launch.
  - **Ni `settings.toml` ni `AppAddedAsLoginItem` diuen si Warp s'obrirà sol** (06/11/2026): després de treure Warp dels
    ítems d'inici de macOS, `settings.toml` no tenia cap línia `login_item`, i `defaults read dev.warp.Warp-Stable
    AppAddedAsLoginItem` continuava dient `1`. Per això Warp Launch no l'espera en iniciar sessió (0.27.2).
  - **Segons en David (07/11/2026), l'opció de Warp d'obrir-se en iniciar sessió sempre ha estat desactivada** (no s'ha mirat a
    la Configuració de Warp), i al reinici de prova del 06/11/2026 Warp es va obrir sol igualment: no se sap qui l'obre (vegeu
    «Primer reinici amb l'arrencada en iniciar sessió»).
  - **El nom de l'opció i quan es registra Warp** (07/11/2026, codi de `warpdotdev/warp` a `abb3fe33`, `master` del 06/11/2026,
    llegit amb `gh api`; recerca del 07/11/2026):
    - A la Configuració de Warp es diu **«Start Warp at login (requires macOS 13+)»**
      (`app/src/settings_view/features_page.rs`, l. 4900). És `general.login_item`, per defecte `true`
      (`app/src/terminal/general_settings.rs`, l. 40-52), i es registra amb `SMAppService.mainApp`.
    - **Warp no es torna a registrar si `AppAddedAsLoginItem` ja és `true`;** només ho fa quan s'activa l'opció de nou
      (`app/src/login_item/macos.rs`, l. 13-22). **Deduït del codi de `master`, no vist** (la 0.2026.11.04 no es pot lligar a
      cap commit): com que `AppAddedAsLoginItem` deia `1` al Mac de prova (06/11/2026), Warp no s'hi va poder tornar a afegir en
      arrencar, i la deducció «Warp s'hi torna a afegir quan arrenca» era falsa (ja ratllada a «Primer reinici…»). Qui va obrir
      Warp continua sense saber-se.
    - **Pista, no comprovada:** sense `login_item` a `settings.toml` (per defecte, `true`) i amb `AppAddedAsLoginItem` a `1`, i
      com que Warp només s'hi registra amb l'opció activa, alguna vegada hi va estar: potser pel valor per defecte en
      instal·lar-lo, o pel del núvol (Settings Sync, com potser `restore_session`, vegeu «Primer reinici…»). Xoca amb l'opció
      desactivada. Per esbrinar-ho en un reinici de prova, mirar abans l'interruptor a la Configuració de Warp,
      `AppAddedAsLoginItem` i si Warp surt a Ítems d'inici de sessió.
- **La documentació oficial de Warp diu que la restauració no reprèn Claude** (07/11/2026, guia
  [Migrate to Warp from Claude Code](https://docs.warp.dev/getting-started/migrate-to-warp/migrate-to-warp-from-claude-code.md)
  i [Session restoration](https://docs.warp.dev/terminal/sessions/session-restoration.md)): conserva les finestres, les pestanyes
  i els panes, però no els processos. «Session restoration preserves tabs and panes, but not running CLI processes — closing
  Warp ends Claude Code's session. Use Claude Code's built-in resume options (e.g., claude --resume)». Confirma el que el
  prototip havia vist (vegeu el primer punt d'aquesta secció).

### `warp.sqlite`

- **Warp llegeix `restore_session` en calent, i desa en menys de 5 s en activar-lo** (05/11/2026, prova de 60 s amb l'OK d'en David, `warp-restauracio.sh` i
  lectures amb `?mode=ro` cada 5 s). Warp obert tot el temps, sense reiniciar-lo. Abans, la base tenia una foto antiga, amb menys finestres i pestanyes
  de les obertes. Activat; menys de 5 s després ja hi havia totes les finestres i pestanyes obertes, i així fins al final. Desactivat uns 50 s després: l'ajust
  es manté `false` passats 2 s i més d'una hora després, i la foto queda igual. Amb la foto, cada terminal viu (`warp-launch llegeix --json`) té el seu pane a
  la base (`lower(hex(uuid))`), sense guions, i no n'hi sobra cap. Una mostra: no se sap quant triga si no hi ha cap activitat a Warp, i hi havia sessions en marxa.

- **Ruta:** `~/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite`, amb WAL.
- **Quan crea Warp la base** (08/11/2026, codi públic de `warpdotdev/warp` a `abb3fe33`, `master` del 06/11/2026; llegit, no
  vist):
  - **A cada arrencada de l'app, sigui quin sigui `restore_session`:** `initialize_app` (`app/src/lib.rs`, l. 1677) →
    `persistence::initialize` → `init_db` → `setup_database`, que la crea si no hi és. És just després de `settings::init` (la
    migració dels ajustos). Un Warp Stable sense base és, doncs, un Warp que no s'ha obert mai en aquest usuari o que tot just
    arrenca, llevat dels dos casos de sota. Com que no depèn de l'ajust, que el refresc no l'activi sense la base (0.31.3) no
    deixa ningú encallat.
  - **En tancar la sessió del compte de Warp,** `log_out` l'esborra (`persistence::remove`, `app/src/auth/mod.rs`), i la torna a
    crear en entrar-hi (`reconstruct`).
  - **Sense el Group Container** (segons un comentari del codi, a macOS sempre n'hi ha), la desa a
    `~/Library/Application Support/dev.warp.Warp-Stable/`. Una base antiga d'allà, Warp la mou al Group Container en arrencar,
    si al Group Container no n'hi ha cap (`migrate_old_sqlite_into_secure_container_if_needed`).
- **S'escriu en calent** (03/11/2026). Això corregeix el que constava abans, que només es reescrivia en sortir de Warp.
  - **Com s'ha comprovat:**
    - Warp corria des de feia hores (`ps -o lstart`).
    - En el moment de mirar-ho, `warp.sqlite` i el `-wal` tenien la data de pocs segons abans.
    - El pane d'aquesta sessió, obert hores després d'arrencar Warp, ja era a `terminal_panes`.
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
- **Contingut** (03/11/2026): totes les finestres i pestanyes obertes. Una de les pestanyes era de Settings
  (`pane_leaves.kind = 'settings'`); les altres eren de terminal, cadascuna amb un pane. La taula
  `tab_groups` era buida.
- **Esquema útil** (03/11/2026, `.schema`):
  - `windows(id, active_tab_index, …)`.
  - `tabs(id, window_id, custom_title, color, tab_group_id, pinned)`. `color` és text YAML
    (`---\nColor: blue\n`). No hi ha cap columna d'ordre.
  - **Els `id` de `windows` i `tabs` no són estables:** Warp els renumera cada vegada que desa (03/11/2026, prova 1).
    - Les finestres van de l'1 a la N, i les pestanyes tenen números consecutius dins de cada finestra
      (per exemple, finestra 1: 1–N; finestra 2: N+1–M…).
    - La finestra de la prova, la més nova, va sortir com a finestra 2, i les de darrere van córrer un lloc: la pestanya de
      Settings va canviar d'`id` i de número de finestra.
    - Al log, aquella finestra era `WindowId(7)`: els `id` de la base no coincideixen amb els que Warp fa
      servir mentre s'executa.
    - **Per identificar una pestanya, cal fer servir l'`uuid` del pane.**
    - **L'ordre de les pestanyes dins de la finestra és el dels `id`** (03/11/2026): en David ha comparat una finestra
      de 4 pestanyes amb `warp-launch llegeix`, i l'ordre de la pantalla és el mateix. Només s'ha comprovat en una finestra.
  - `pane_nodes`, i `pane_leaves(pane_node_id, kind, is_focused, custom_vertical_tabs_title)`. Cal filtrar per `kind = 'terminal'`.
  - `terminal_panes(id, kind, uuid BLOB UNIQUE, cwd, is_active, shell_launch_data, input_config,
    llm_model_override, active_profile_id, conversation_ids, active_conversation_id)`.
  - `tab_groups(window_id, name, color, collapsed, pinned)` són els grups de pestanyes de Warp. No s'han de
    confondre amb les finestres de Warp Launch, que són grups de sessions.
  - `blocks(…, pane_leaf_uuid, pwd, start_ts, …)`: historial de comandes de cada pane. `start_ts` és UTC.
    - `stylized_command` és un BLOB amb codis ANSI (`ESC[1m` i `ESC[0m`) al voltant de cada caràcter. Per
      cercar-hi, cal treure'ls: amb `LIKE '%claude%'` directe surten 0 resultats, i sense els codis, sí que en surten.
    - Només hi havia uns centenars de blocks, de menys d'un any. Warp no en guarda l'historial complet.
    - A la prova 1, el pane no hi tenia cap block, ni mentre `claude` s'executava ni després de tancar la
      finestra. Per tant, `blocks` no serveix per saber què va arrencar una pestanya.
- **`terminal_panes.cwd` no és canònic** (03/11/2026, comparat amb `fcntl(F_GETPATH)`).
  - Guarda la ruta tal com es va escriure, amb les majúscules i els symlinks. Per exemple, si el disc no distingeix
    majúscules i `/Users/prova/Documents/codi` és un symlink a `/Users/prova/codi`, hi pot haver `~/documents/codi/…` i
    `~/Codi/…`.
  - Claude, en canvi, guarda la ruta canònica. Una part dels `cwd` no coincidien amb la ruta canònica, i en una tercera part
    de les sessions el `cwd` del pane i el de Claude no coincidien literalment.
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
  - La majoria dels panes tenien blocks anteriors a l'última arrencada del Mac, lligats al seu UUID.
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
    per defecte és `true`, i `general.undo_close.grace_period`, de 60 s per defecte. A la prova, valien els per defecte.
  - El block de `claude` de la finestra de prova va acabar 60 s després de tancar-la.
  - Durant aquest minut, el procés i `~/.claude/sessions/<pid>.json` continuen existint, però el pane ja no
    és a `warp.sqlite`.

## Claude Code

- **Fitxer de sessió** (prototip; la revisió del 03/11/2026 hi va afegir que també l'escriuen els processos `bg`):
  - Cada procés de Claude, interactiu o `bg`, escriu `~/.claude/sessions/<pid>.json` amb `sessionId`, `cwd`,
    `name`, `kind` (`interactive` o `bg`; el 07/11/2026, també `daemon` i `daemon-worker`, vegeu «Per al diagnòstic»),
    `entrypoint`, `startedAt` i `procStart`.
  - `procStart` és l'hora d'inici en UTC i en format ctime, sense zona (03/11/2026, revisió). Per comparar-lo
    amb `ps -o lstart`, que dona l'hora local, cal convertir la zona.
  - **El fitxer s'esborra quan el procés acaba.** Després d'un reinici no en queda res.
  - Altres camps (03/11/2026, `jq` sobre els fitxers de les sessions vives):
    - `nameSource`: `derived` vol dir que el nom l'ha posat Claude.
    - `status`: `idle` o `busy`.
    - També hi ha `version`, `messagingSocketPath` i, en alguns, `bridgeSessionId`.
- **`cwd`:** no segueix els `cd` que Claude fa amb l'eina Bash; sí els canvis de carpeta de la sessió (vegeu «La carpeta de la
  pestanya i la de Claude»). Corregit el 09/11/2026: abans deia que seguia tots els `cd` (prototip).
- **`/clear` i `/resume`:** dins la sessió reescriuen el `sessionId` del mateix fitxer, amb el mateix pid (prototip).
- **On són les converses:** `~/.claude/projects/<cwd amb tot caràcter no alfanumèric → ->/<sessionId>.jsonl` (prototip).
  - **Confirmat el 04/11/2026** (`warp-launch llegeix --json` 0.16.0 i `os.path.exists`, només lectura): totes les
    sessions vives tenen la transcripció al projecte de la seva carpeta canònica, cap en un altre.
  - **Hi pot haver projectes que són symlinks** (03/11/2026, revisió; `ls -ld`, 04/11/2026): quan es mou la carpeta de
    repos, o un repo, el projecte de la ruta nova pot ser un enllaç al de l'antiga (per exemple,
    `-Users-<usuari>-codi-*` → `-Users-<usuari>-Documents-codi-*`, d'abans que la carpeta real passés de
    `~/Documents/codi` a `~/codi`).
  - **No s'han d'esborrar mai.**
  - L'app (0.16.0, `LectorTranscripcions`) mira primer el projecte de la carpeta seguint l'enllaç, i després els
    projectes que no són enllaços. Claude fa el nom en JavaScript (`[^a-zA-Z0-9]` → `-`, en unitats UTF-16) i, si
    passa de 200 caràcters, hi afegeix un hash (recerca del binari 2.1.318, 04/11/2026).
- **Confiança en una carpeta** (04/11/2026, `~/.claude.json` llegit amb Python, només aquest camp): es desa per carpeta,
  a `projects.<ruta>.hasTrustDialogAccepted`. Claude no desa mai la de la carpeta d'inici (recerca del binari).
- **`claude --resume [valor]`:**
  - Accepta un ID **o un nom** de sessió, o obre el selector (03/11/2026, `claude --help`).
  - Continua el mateix `sessionId` (prototip).
  - El prototip va veure que avisava «és d'un altre directori» si no s'executava des de la carpeta de la
    conversa. La documentació diu que funciona des de qualsevol carpeta: **està per verificar**.
  - **Es nega a reprendre una sessió que té un procés viu**, i ofereix enganxar-s'hi (prototip). **No sempre** (05/11/2026):
    - `claude --bg --resume <id>` d'una conversa viva en fa una còpia amb un altre id. Vist el 03/11/2026: amb la conversa
      viva, va néixer una feina amb un id nou (transcripció i `~/.claude/jobs`).
    - Llegit al codi minificat de 2.1.318, sense executar-ho: despertar una feina amb `respawn` es rebutja
      (`resume_session_live_elsewhere`), i `claude --resume` d'una feina viva surt amb error.
    - `disseny.md` diu que amb un procés interactiu no es nega i les transcripcions s'intercalen: no s'ha provat a propòsit, i
      no quadra amb això. R9 l'ha de garantir l'app igualment.
  - **`~/.claude/jobs/<id>/state.json` pot quedar antic** (05/11/2026): una feina deia `blocked` des de feia dies, però la seva
    transcripció tenia centenars de línies més de terminal, de després. Una feina adormida es pot reprendre en una pestanya.
- **`claude --continue`** (prototip): agafa la conversa més recent de la carpeta. Si aquesta està en segon
  pla (`kind: bg`), **es nega a arrencar**.
- **Les sessions en segon pla no sobreviuen a un reinici** (07/11/2026, documentació oficial,
  [agent view](https://code.claude.com/docs/en/agent-view.md), «Sessions show as failed or stopped after shutdown» i
  «Limitations»; Claude Code 2.1.319; no s'ha provat, regla 1):
  - Aguanten la son i les actualitzacions, però no un reinici: després surten «failed», si fa menys de 48 h que van
    avançar, o «stopped» («ended while the background service was off»), si en fa més. Cal obrir-les o respondre-hi una
    per una perquè es tornin a engegar amb la conversa desada.
  - El supervisor no s'engega en iniciar sessió: ho fa «the first time you background a session or open agent view».
- **Tancar Warp pot aturar una feina en segon pla** (anotat el 09/11/2026; observat una sola vegada, no reproduït i sense
  causa comprovada; regla 2): una feina va quedar a mitges en tancar Warp, i reobrir les pestanyes no la va fer continuar. Els
  fulls d'obrir i el README ho diuen amb «pot» (0.31.5).
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
    permisos, i el mode («plan», «acceptEdits») no té cap efecte. Si l'usuari té
    `skipDangerousModePermissionPrompt: true`, no surt cap avís. `--allow-dangerously-skip-permissions`
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
  sessió arrenca amb el model, l'esforç i el mode de la configuració de l'usuari.
- **Notificacions a Warp** (03/11/2026, `warp.log`).
  - Claude Code envia a Warp seqüències OSC 777 amb `title=warp://cli-agent` i un JSON amb `agent`, `event`
    (per exemple, `tool_complete`), `session_id` i `cwd`.
  - Warp les apunta al log. Està per veure si serveixen per lligar cada pane amb la seva sessió.
- **Arguments de cada procés:** `ps` perd les cometes. L'`argv` exacte i l'entorn d'un procés propi es
  llegeixen amb `sysctl(KERN_PROCARGS2)` (prototip; vegeu `argv_env_de` a `prototip/espai.py`, a l'historial: `git show 114c97d:prototip/espai.py`). L'entorn
  inclou `WARP_TERMINAL_SESSION_UUID`. La revisió del 03/11/2026 en va llegir l'entorn de 6 processos.
- **Memòria** (03/11/2026, revisió): cada sessió viva ocupava uns 500 MB de mitjana (de 350 a 800 MB). Desenes de
  sessions són desenes de GB (60 són uns 30 GB).

### La carpeta de la pestanya i la de Claude (09/11/2026, Claude Code 2.1.319)

- **Els `cd` de l'eina Bash no mouen la sessió** (provat, un Mac, 18 sessions amb el `cwd` de les entrades canviant dins del
  procés): `sessions/<pid>.json`, el procés i el fitxer de la transcripció es queden a la carpeta d'arrencada (0 de 54 carpetes
  visitades tenen la transcripció).
- **`/cd` i `EnterWorktree` sí** (llegit a la documentació i al binari minificat, sense cap cas observat): la transcripció passa al
  projecte de la carpeta nova, i `originalCwd`, que reescriu el fitxer de sessió, canvia.
- **`--resume <id>` no depèn de la carpeta** (llegit a la documentació oficial, [sessions](https://code.claude.com/docs/en/sessions#resume-by-session-id-or-name);
  no provat): cerca al projecte actual i als seus worktrees i després, des de la v2.1.223, a tots els altres. Només el troba
  fora si exactament un altre projecte té aquella transcripció; si no, `No conversation found`.
- **Amb `cd B && claude`, Warp es queda amb A** mentre Claude corre, si el shell no emet OSC 7 (llegit al codi de
  `warpdotdev/warp`, commit `abb3fe33e004`; **observat el 09/11/2026**, una pestanya amb Claude Code 2.1.319: Warp deia A i la sessió
  corria a B): Warp només actualitza la carpeta al `precmd`.
- **En aquell Mac, Warp i Claude coincidien a 74 de 74 pestanyes.** És la base de la decisió del
  09/11/2026 (mana la de Claude, excepte si és `~` o no existeix).

## Primera lectura real (03/11/2026, `warp-launch llegeix` 0.2.0)

- **Warp:** totes les pestanyes tenen títol, menys la d'aquesta sessió.
- **Claude:** totes les sessions interactives es lliguen amb la seva pestanya per `WARP_TERMINAL_SESSION_UUID`.
  La sessió `bg` es descarta.
  - Cap no porta `-n`: tots els noms són `derived`.
  - Moltes pestanyes no tenen Claude.
- **Carpetes:**
  - Les dels panes que eren a HOME es recuperen de l'historial (`blocks.pwd`).
  - Algunes són a HOME i no tenen historial: es queden a HOME.
  - **Algunes de l'historial ja no existeixen:** els repos s'havien mogut a una altra carpeta.

## Primera importació (04/11/2026, `warp-launch importa` 0.7.0, sense desar)

- A la 0.7.0, les pestanyes amb Claude viu es desen amb la seva ordre, i les altres amb carpeta, amb la de la plantilla (des
  de la 0.29.1, en una configuració nova, només terminal). Les que són a `~` o tenen una carpeta que no existeix queden sense
  Claude. El resultat és el que preveia el disseny amb la lectura del 03/11/2026.
- Les sessions que es van obrir sense `--continue` es desen amb continuar (R4).
- El nom de cada finestra és el de la carpeta pare de més de la meitat de les seves pestanyes (sense comptar les de `~`). Si
  no n'hi ha cap, o és la carpeta d'inici o l'arrel, és «Finestra N»; els repetits porten « 2», « 3»… (`Importador.nomDeFinestra`).
- **Warp no té noms de finestra** (04/11/2026, `.schema windows` de `warp.sqlite` amb `?mode=ro`): la taula
  `windows` només té la mida, la posició, la pestanya activa i l'estat dels panells. Els noms els posa la
  importació de Warp Launch (docs/disseny.md, «Importació (R2)»), i «Finestra N» vol dir la N-èsima de la lectura.
- A totes les sessions, la carpeta de Claude i la de la pestanya coincideixen. Cap sessió no porta primer missatge,
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
  - El CLI hi llegeix perquè macOS atribueix a Warp el que s'executa en una pestanya de Warp.
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
  - Resultat: l'app mostra «Warp: N finestres · N pestanyes · N sessions de Claude», amb les mateixes xifres que
    `warp-launch llegeix` en aquell moment.
  - Que el permís duri en recompilar (identitat del certificat) està per verificar a la propera versió.

## Prova L1: obrir una finestra a Warp (05/11/2026, 0.20.2)

L'app, empaquetada i signada, l'obre en David amb `--config /tmp/warp-launch-provaL1`. La configuració té 1 finestra,
«Prova L1», amb 1 pestanya, «L1 docs», a `…/warp-launch/docs`. Warp és el 0.2026.10.21.08.25.02. En David l'obre 4
vegades, cada vegada després de tancar la finestra anterior. La primera, només terminal;
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
- **D16 desmentit: l'espai del davant no treu la línia de l'historial.** Les 3 línies amb Claude surten a
  `~/.zsh_history` (`: <data>:0; WARP_LAUNCH_PESTANYA=… claude`): zsh no té `HIST_IGNORE_SPACE` per defecte, i Warp no
  l'activa (`zsh -ic setopt` no el mostra). Warp també les desa a la seva taula `commands` de `warp.sqlite` (3 files, sense codi de
  sortida).

## Tornar a obrir totes les finestres des de l'app (05/11/2026, 0.21.0)

En David tanca a mà totes les finestres de Warp i obre les de `/tmp/warp-launch-provaL3`, una configuració de prova gran, amb
«Obre a Warp…», una per una. No fa «Lliga amb Warp…» (el registre no en té cap línia). Comprovat amb el registre de l'app,
`estat.json`, `warp-launch llegeix`, `ps` i `~/.claude.json` (només lectura).
- **Warp obre totes les finestres i pestanyes.** Tots els llançaments queden `confirmat`, amb la finestra vista en 0,5 a
  1,2 s (1,2 s, la més gran, amb un fitxer d'uns quants KB). No queda cap fitxer temporal.
- **Cap conversa es reprèn des de l'app** (`0 reprenen` a tots els plans): sense lligar, `estat.json` no en recordava cap.
  Després, les pestanyes d'una de les finestres tenen una conversa amb transcripció, i les que eren vives abans de tancar
  tenen el mateix id: es van reprendre a mà, i `estat.json` les recull per la marca (`origen` `marca`). Reprendre amb
  `--resume` des de l'app encara no s'ha provat.
- **Claude no fa canòniques les rutes de la confiança: és un error de l'app, que sí que ho fa.** A la prova, la carpeta de
  repos té un enllaç (`~/Documents/codi` → `~/codi`). En una finestra, la majoria de les pestanyes no tenen cap clau
  `hasTrustDialogAccepted` amb la ruta real: unes només la tenen amb la ruta de l'enllaç, i les d'uns repos moguts no en
  tenen cap. Són exactament les pestanyes on Claude no ha arrencat: 6 minuts després no tenen `~/.claude/sessions/<pid>.json`,
  fan poc més de la meitat de memòria que les altres i han gastat menys d'1 s de CPU. Totes les altres pestanyes, amb la clau
  literal, sí que han arrencat. L'app només ha avisat de les que no en tenen cap (`LectorConfianca` fa canònica cada clau
  del fitxer). Que el que esperen és el diàleg de confiança es dedueix d'aquesta coincidència: encara s'ha de veure en una
  pestanya. **Corregit a la 0.21.1.** Quan en David contesta les preguntes, totes les carpetes d'aquella finestra passen a
  tenir la clau literal acceptada.
- **Memòria:** uns 290 MB de mitjana per procés de Claude, comptant-hi els aturats.

## Amb la restauració de sessió desactivada (05/11/2026, 0.22.0)

En David la desactiva a Settings de Warp (`restore_session = false` a `[general]` de `settings.toml`), perquè l'app la
substitueix (D6), i Warp torna a arrencar, ja sense restauració. Al codi públic, l'ajust es mira a cada desat, de manera que
reactivar-lo hauria de posar la base al dia de seguida. **No s'ha provat.**

- **Warp deixa de desar les finestres:** `warp.sqlite` queda congelat, i no diu què hi ha obert.
  - Al codi públic de Warp (`app/src/workspace/global_actions.rs`, `master` del 05/11/2026), `save_app` surt de seguida
    si `restore_session` és fals.
  - Comprovat uns minuts després: `windows` i `tabs` tenien les finestres i les pestanyes d'abans, i cap pane de la
    finestra que l'app va obrir just després d'arrencar, l'única que Warp tenia oberta. El registre mostrava més de 50
    `save_app` des de l'arrencada.
  - Només s'hi afegeixen les ordres (`commands`): les línies amb la marca d'aquella obertura, amb `pwd` i `session_id`.
    Per això el `-wal` té la data d'aquella obertura i ja no es mou.
  - Això corregeix «Warp desa la finestra nova a `warp.sqlite` de seguida» (prova L1): només amb la restauració activada.
- **Conseqüències que s'han vist a l'app 0.21.1:**
  - El bàner «No s'ha pogut reconèixer la finestra nova de «…» (s'ha vist Claude a N de N)», després d'esperar
    30 s (`senseConfirmar`), encara que Warp l'havia obert bé.
  - Amb la base d'abans, el pla deia que **totes les pestanyes ja eren obertes** i no n'obria cap: les de la foto, «oberta
    a Warp, sense Claude», i les de la finestra oberta, «tancada fa menys d'1 minut». Calculat amb les dades reals, sense
    obrir res.
- **En arrencar, Warp obre una finestra buida** (`open_from_restored`, `open_new`, «Opening window with id 0», un shell a
  la carpeta d'inici). En David la va tancar. L'app no la pot tancar (regla 2).
- **Què se'n pot saber sense la base** (05/11/2026, només lectura):
  - **Els processos, que és el que fa servir l'app:** cada terminal viu és un fill de `stable terminal-server`. El 05/11/2026,
    un `-zsh -g --no_rcs` per pestanya oberta. No cal cap permís, i és l'estat d'ara mateix.
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
  `grace_period` (60 s), i no `restore_session`; sense `undo_close` a `settings.toml`, valen els per defecte. **Encara no s'ha vist
  amb la restauració desactivada.**

## Si l'app activés i desactivés `restore_session` sola (05/11/2026, només codi públic)

Llegit del codi públic de Warp (`warpdotdev/warp`, `master` del 05/11/2026, que potser no és la versió instal·lada). **No s'ha
provat res al Mac:** l'ajust real continua a `false`.

- **Warp hauria de notar el canvi sense reiniciar-se.** `settings/init.rs` vigila `settings.toml`: `reload_from_disk` i
  `reload_all_public_settings`. I `save_app` (`workspace/global_actions.rs`) mira l'ajust a cada desat.
- **Warp només desa si passa alguna cosa.** `save_app` el criden: moure, redimensionar o tancar una finestra, canviar de finestra
  activa (`app_callbacks` a `lib.rs`), les accions de la finestra de Warp que ho demanen (`should_save_app_state_on_action`) i
  una pregunta a l'agent de Warp. **Cap temporitzador.** Si ningú no toca Warp mentre l'ajust és actiu, no es desa res.
  - Registre real (`warp.log`, una mostra de 23 minuts): de 2 a 32 `save_app` per minut, en 20 dels 23 minuts; i, just després, 5 minuts seguits sense cap.
- **Cada canvi va al núvol** si Settings Sync és activat (`is_settings_sync_enabled = true` a `settings.toml`). L'ajust és
  `SyncToCloud::Globally(RespectUserSyncSetting::Yes)`. En recarregar el fitxer, `load_value` emet el canvi, `register_setting_events` el passa a
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

- **En obrir l'app:** l'ajust passa a `true` 1 s després i torna a `false` 5 s més tard. Warp desa (el WAL canvia). Després,
  44 s seguits a `false`.
- **Refresc dels 5 min:** `true` durant 6 mostres (6 s), després `false`, i 156 s seguits a `false`. El WAL canvia.
- **La foto quadra:** tantes pestanyes i panes a la base com terminals vius als processos, tots amb Claude.
- **No s'obre ni es tanca cap finestra.**
- **El registre de l'app no diu res** si el refresc va bé: `Registre.refresc` només escriu avisos i errors.
- No s'ha provat: «Torna a llegir Warp» des del menú, ni Warp tancat, ni l'eco del núvol durant hores.

## Proves reals de la 0.26.0 (06/11/2026)

En David fa les proves 1 a 4 amb el paquet 0.26.0 (signat amb «Warp Launch Dev») i diu que totes funcionen. El registre de
l'app (`log show`, subsistema `cat.davide.warp-launch`) en recull dues obertures:
- **Reprendre una conversa des de l'app.** Pla: 1 pestanya a obrir, amb Claude, que reprèn la seva conversa; la resta de la
  finestra ja oberta; 1 avís. Fitxer de 568 bytes, confirmat en 0,6 s amb 1 sessió de Claude vista, i fitxer esborrat. És la
  primera vegada que l'app reprèn una conversa amb `--resume` (el 05/11/2026 no se'n va reprendre cap).
- **«Obre-ho tot a Warp…».** El pla troba 1 finestra per obrir (les altres ja eren obertes); s'obre amb 2 pestanyes i 2 sessions,
  confirmada en 0,6 s, fitxer de 978 bytes esborrat. Resum: «1 de 1 correctes».
- **Proves 3 (finestra oberta en part) i 4 (prova 8, l'editor):** correctes segons en David. El registre no en té cap altra
  obertura: la prova 8 no n'obre cap, i de la 3 no se'n va desar cap línia.

## Primer reinici amb l'arrencada en iniciar sessió (06/11/2026, 0.27.2)

Llegit al registre de l'app (`log show`, procés `WarpLaunch`), a `~/Library/Logs/warp.log.old.0` a `.old.2` i amb `ps`.
- **Abans d'apagar,** Warp fa `save_app`: la restauració era activada en aquell moment (el refresc de cada 5 minuts, D19).
- **Uns 35 s després d'arrencar el Mac,** Warp Launch s'obre sola (l'ítem d'inici funciona) i 2 s després prepara el full: totes les
  finestres per obrir, amb Warp ja obert.
- **Alhora, Warp s'obre sol** i restaura (`open_from_restored`) les finestres i els terminals de la foto, sense Claude (Warp només en
  restaura la carpeta). El 05/11/2026, amb la restauració desactivada, Warp havia obert una sola finestra buida. **La restauració, doncs,
  era activada en arrencar**, encara que `settings.toml` digui `false`. **Deduït, no vist:** el valor del núvol (amb Settings Sync activat), que a
  l'arrencada guanya si el fitxer no ha canviat des de l'última sincronització. `settings.toml` es torna a escriure 5 s després.
- **Qui va obrir Warp:** no l'app (no escriu res fins després del clic). Warp s'havia tret dels ítems d'inici. `settings.toml` no té
  `login_item`, que per defecte és `true`. ~~Deduït, no vist: Warp s'hi torna a afegir quan arrenca; s'ha de desactivar a la
  configuració de Warp.~~ **Desmentit el 07/11/2026:** segons en David, l'opció de Warp sempre ha estat desactivada, i segons el codi de Warp no es torna a
  registrar si `AppAddedAsLoginItem` ja és `true` (vegeu «Restauració de sessió i arrencada»). Tampoc no sembla l'opció de macOS de
  tornar a obrir les finestres (`defaults read com.apple.loginwindow TALLogoutSavesState` diu `0`, i el fitxer no havia canviat des d'abans del reinici), ni un LaunchAgent de Warp (no n'hi
  ha cap a `~/Library/LaunchAgents` ni a `/Library/LaunchAgents`). **No se sap qui el va obrir:** es mirarà en un altre reinici de prova.
- **En David tanca Warp** (l'app ho veu en fer clic i torna a demanar confirmació), i uns segons després l'app l'obre i obre totes les
  finestres, amb totes les pestanyes amb Claude, confirmades en 1,6 a 4,8 s.
- **Risc vist:** si hagués fet clic sense tancar Warp, l'app hauria obert totes les pestanyes una altra vegada, perquè no reconeix les
  que restaura Warp (sense Claude ni marca). **0.27.3:** el full diu quantes pestanyes no reconeix; la foto només es fa quan es demana.

## Ítems d'inici de macOS (06/11/2026, macOS 27.2)

- **El tauler es diu «Ítems d’inici de sessió»** (General › Ítems d’inici de sessió, i el títol del tauler), amb l'apòstrof
  tipogràfic: captura d'en David del 06/11/2026. `GeneralSettings.appex` també té la clau «Login Items & Extensions» = «Ítems
  d’inici de sessió i extensions», però no és el que surt (la revisió de la 0.27.0 s'hi va fiar; corregit a la 0.27.1).
- **`SMAppService.mainApp.register()` funciona amb el certificat «Warp Launch Dev»** (06/11/2026, 0.27.0, des de
  `/Applications`): en David activa l'interruptor i «Warp Launch.app» surt a «Obre en iniciar la sessió», amb la icona.
- **Per comprovar a la prova real (0.27.2):** si macOS envia `keyAELaunchedAsLogInItem` a una app registrada amb
  `SMAppService.mainApp`, i si el full surt de seguida en iniciar sessió.

## Les transcripcions de `~/.claude/projects` (05/11/2026)

Llegides amb Python, només lectura: tots els fitxers `.jsonl` de primer nivell, i els més recents de cada carpeta de la
configuració.

- **El primer missatge de l'usuari diu d'on ve la conversa** (`entrypoint`): `cli`, `sdk-cli` (`claude -p`) o
  `claude-desktop`. Tots els missatges en porten; uns pocs fitxers no en tenen cap, i fan 3 KB com a molt.
- **El primer missatge pot ser lluny del principi:** mediana d'1 KB, percentil 99 de 143 KB i màxim de 894 KB. Amb 256 KB,
  algunes converses reals semblaven buides.
- **La data del fitxer no és la de l'últim missatge.** Claude també l'escriu en tancar-se (`cost-state`, `mode`). De les tries
  comparades, en dues terceres parts es porten més d'1 dia, i en una quarta part, més de 3; en una, mesos.
  Això corregeix «ordena igual que el darrer `timestamp`», que només s'havia mirat a les 3 més recents de cada carpeta.
- **No totes són converses:** d'entre les més recents de cada carpeta, unes quantes no tenen cap resposta de Claude (només un
  `/clear`, o «cd ..»), i alguna, només una de `<synthetic>`.
- **Una conversa pot acabar com a feina en segon pla:** les seves línies porten `sessionKind: bg` (cap altre valor). N'hi ha que
  són feines de principi a fi. En una carpeta, la conversa més recent era una feina començada sobre una conversa antiga, posterior
  a la de la pestanya. Ordenar per l'últim missatge sense treure les línies de feina hauria triat la feina.
- **La conversa més recent de cada carpeta:** mediana de 5 MB, i n'hi ha de més de 200 MB. Cada pestanya de la configuració és
  a una carpeta diferent.
- **Una obertura d'una finestra ja en va reprendre algunes:** la majoria mantenen l'id, i una ja en té un altre (`--resume <a>`,
  sessió `<b>`). En obrir-ho tot, se'n reprèn una de 220 MB: s'obre. El temps no s'ha mesurat.

## Missatges entre sessions de Claude (05/11/2026, 2.1.318)

Mirat amb `ListAgents`, `~/.claude/sessions`, les transcripcions, el binari i dos avisos d'inactivitat sense text. Dos agents han
intentat desmentir-ho. **Un missatge real, amb l'OK d'en David:** de bypass a bypass, entra a la cua del receptor (un agent que
engega feines) i li passa al Claude 6 s després, sense retenir-lo. Les respostes tornen igual.

- **La regla** (descripció de `crossSessionInbound` al binari): sense valor, un missatge entra sol si l'emissor i el receptor són
  de la mateixa classe, bypass amb bypass o prompting amb prompting. Si no, queda retingut per a una persona, en les dues
  direccions, i caduca. `auto` és de la classe prompting. El valor `accept` treu la comprovació. Cap dels fitxers de configuració
  mirats no el té, i no hi ha `managed-settings`.
- **Cada sessió té socket** (`/tmp/cc-socks/<pid>.sock`). A la prova, l'agent i aquesta sessió eren interactius i en
  `bypassPermissions`, i hi havia una feina en `auto`.
- **Els dos avisos ho confirmen:** el de l'agent (bypass) arriba a Claude en aquesta sessió (bypass). El de la feina en `auto`
  només surt com a línia de sistema, per a la persona. Els dos passen per la mateixa decisió que un missatge (llegit al codi).
- **Els retinguts tenen una feina `--bg` pel mig** (historial de lliuraments a les transcripcions): entre dues sessions bypass, els
  missatges entren sols.
- **`claude --bg` sense flag de permisos arrenca en `auto`. En reprendre sense flag, un `auto` desat torna, i un bypass desat no** (funció
  `Ce` del binari, i feines reals): una conversa en bypass passa a `auto` en reprendre-la amb `--bg` sense flag, i torna a bypass quan
  l'app l'obre amb el flag. Una feina en `auto` no pot passar a bypass sense reiniciar-se (llegit). Algunes feines reals porten
  `--permission-mode bypassPermissions` a `respawnFlags`.
- **Amb el flag, funciona, vist:** `claude --bg --resume <id> --dangerously-skip-permissions`, amb `nohup`, fa una còpia amb un altre
  id, en `bypassPermissions` des d'aquell moment, amb el flag a `respawnFlags`.
- **Qualsevol opció en reprendre una feina aturada en fa una còpia** (`$n` del binari: `own-options`; un verificador n'ha executat el codi amb
  `state.json` reals i dona els dos casos vistos). La mateixa ordre, repetida, en fa una altra. Sense opcions, la desperta amb el mateix id:
  «woke session <id> with its saved options». Si no hi ha feina (`state.json`), l'opció no fa còpia: es queda el mateix id. Una viva sempre
  fa còpia. Un id curt, també (`unresolved`).
- **Com s'engeguen les feines:** a les ordres vistes, `--bg` va just després de `claude`, de vegades amb `cd … &&` o `nohup` al davant,
  i sovint amb `--resume`.
- **Les còpies són el problema de sota** (ho conclou un agent, i les dades ho aguanten): cada represa d'una conversa viva, o d'una feina
  amb opcions, fa una còpia nova sense pestanya. Els missatges van a la còpia, i la pestanya de la conversa original no en veu cap.
- **Què pot fer anar una feina en bypass** (llegit al binari; dos agents ho han intentat desmentir i n'han corregit dues coses; cap camí
  no s'ha provat de punta a punta):
  - **Cap variable ni `--settings` no fixa el mode**, i una ordre de shell no hereta res de la sessió mare (`rae` amb `"shell"`).
    `--inherit-permission-mode` només el fa servir `claude agents`.
  - **`permissions.defaultMode: bypassPermissions` a `~/.claude/settings.json`:** una feina nova, sí. Una represa amb `auto` desat, no: `Ce`
    posa `auto` al damunt. A més, afecta tots els `claude` sense flag del Mac, i un `defaultMode` d'un repo guanya.
  - **`CLAUDE_ENV_FILE`:** Claude llegeix el fitxer un cop per sessió i l'enganxa abans de cada ordre de Bash, també si el posa l'usuari
    (`Sts`); si no hi és, no diu res. Els ganxos de sessió fan servir un fitxer seu. És el que fa l'app des de la 0.22.3 (`EntornClaude`).
    La variable passaria al servei de feines i a totes les feines, com la marca de l'app (el 05/11, un `bg-spare` portava la de la pestanya
    d'un agent): per això el fitxer fa `unset`. Una feina no es pot reconèixer des del seu Bash: `Zo` treu `CLAUDE_CODE_SESSION_KIND` (llista
    `agt`). Si el servei l'engega la mateixa pestanya, sense passar pel Bash, la variable hi arriba igualment (llegit): una feina d'aquell
    servei tindria la funció.
    **Prova real (05/11/2026, 0.22.3, amb l'OK d'en David, 1 feina):** després de reobrir les finestres des de l'app, el procés de la pestanya
    porta la variable; al seu Bash ja no hi és (`unset`) i `claude` és la funció. `claude --bg -n <nom> "…"`, sense cap flag, crea una feina amb
    `respawnFlags` amb `--permission-mode bypassPermissions` i totes les línies `permission-mode` de la transcripció en `bypassPermissions`. Un
    `SendMessage` hi arriba en pocs segons amb `from-mode="bypass"`, sense retenir, i la resposta torna sola. No prova els casos que la funció no
    cobreix. A zsh, `which claude` escriu el text de la funció, com ja passa amb `pkill` o `find` a la instantània; `whence -p claude` dona la ruta.
  - **`CLAUDE_CODE_PROCESS_WRAPPER`:** no és de la pestanya sinó de tot el supervisor, que es retiraria; descartat.
- **`--resume` d'una conversa viva en fa una còpia amb un altre id**, i de la còpia en pot sortir una altra. `claude stop` fa caducar els
  missatges retinguts al receptor.
- **El nom canvia a cada arrencada:** el mateix agent surt amb un sufix diferent cada vegada (per exemple, `agent-63` i després `agent-b8`).
  El sufix és a l'atzar per procés (llegit), i el socket porta el pid: un missatge al nom o al socket d'una arrencada anterior falla. `--name`
  el fixa (llegit, i vist en feines; no en pestanyes). Al Mac de prova (05/11/2026), en fallen pocs per això (menys de
  l'1 % dels `SendMessage` de l'historial), i cap pestanya de la configuració no el fa servir.
- **Fins a la 0.22.2, Warp Launch no hi influïa:** les ordres de les pestanyes no porten res de missatgeria. La marca `WARP_LAUNCH_PESTANYA`
  s'hereta a les feines que surten del Bash d'una pestanya (la feina porta la de la pestanya de l'agent que l'engega), però `LectorSessions`
  només la llegeix a les interactives.

## Per al diagnòstic i per trobar Warp (07/11/2026, Warp 0.2026.11.04, Claude Code 2.1.319)

- **L'Info.plist de Warp** (`PlistBuddy` a `/Applications/Warp.app/Contents/Info.plist`): `CFBundleIdentifier`
  `dev.warp.Warp-Stable`, `CFBundleExecutable` `stable`, i `CFBundleShortVersionString` i `CFBundleVersion`
  `0.2026.11.04.08.17.01`. Des de la 0.29.2, l'app en treu el binari. L'identificador de Warp Preview (`dev.warp.Warp-Preview`)
  no s'ha verificat: no s'ha provat amb Warp Preview instal·lat.
- **El nom de procés de Claude Code és la seva versió** (`ps -o ucomm`): el `p_comm` del `claude` natiu és «2.1.319», no
  «claude». Per això el diagnòstic recorre tots els processos de l'usuari i no els busca pel nom.
- **El binari de Claude Code també corre com a `ugrep`** (`ps`, revisió del diagnòstic): quan Claude cerca, `argv[0]` és
  «ugrep». És fill del shell de l'eina Bash i hereta de la pestanya `WARP_TERMINAL_SESSION_UUID`.
- **Els tipus de sessió** (llegit als binaris 2.1.317, 2.1.318 i 2.1.319 de `~/.local/share/claude/versions`, sense executar-los;
  `grep -a` el torna a trobar a la 2.1.319): Claude Code accepta `kind` `["interactive","bg","daemon","daemon-worker"]`. Escriu
  `~/.claude/sessions/<pid>.json` amb `pid`, `sessionId`, `cwd`, `startedAt`, `procStart`, `version` i `kind` (el de
  `CLAUDE_CODE_SESSION_KIND`, o `interactive`), i l'esborra en sortir (`process.on("exit")`). Encara no s'ha vist amb un dimoni
  real que `claude daemon run` escrigui el de `kind` `daemon`.
- **A `~/.claude/sessions` també hi ha fitxers `<pid>.<sha256>.key`** (`ls`): claus de missatgeria, al costat dels `<pid>.json`.
  Els fitxers de sessió que hi havia eren tots `interactive` i de la 2.1.319.
- **`~/.claude.json`:** totes les entrades de `projects` porten la clau `hasTrustDialogAccepted`.

## La finestra de Configuració (07/11/2026, macOS 27.2)

Mesurat amb un programa a part, sense mostrar cap finestra, per a la 0.30.2 (`VistaConfiguracio.formulari`).
- **Un `Form` agrupat és una vista de desplaçament,** i la seva alçada ideal és la de tot el contingut. Amb
  `.frame(maxHeight: H)` entre el `Form` i `.fixedSize(horizontal: false, vertical: true)`, fa l'alçada del contingut, com a
  molt H, i el que no hi cap es desplaça a dins. Si el contingut és més curt, no hi ha res per desplaçar i macOS no hi posa cap
  barra. L'ordre dels modificadors compta: `fixedSize` demana l'alçada ideal al marc, i el marc la retalla a H.
- **Sense `frame(maxHeight:)`,** el `Form` amb `fixedSize` fa l'alçada de tot el contingut, encara que passi de la pantalla, i la
  finestra no es pot fer més baixa ni s'hi pot desplaçar (la Configuració fins a la 0.30.1).
- **Amb `.windowResizability(.contentSize)` a l'escena,** la finestra pren la mida del contingut (la mínima i la màxima són
  iguals) i canvia de mida sola quan el contingut canvia: en canviar de pestanya d'un `TabView`, o quan una pestanya creix.

## Swift: expressions regulars i crides de sistema (08/11/2026, Swift 6.4.2)

- **`\b` a les `Regex` de Swift** fa servir per defecte el límit de paraula d'Unicode (UAX #29), on un punt entre dues lletres no
  talla la paraula: `\bProcess\(` no troba `Foundation.Process()`, `\bNSApp\b` no troba `NSApp.terminate(nil)`, `\bestat\s*=`
  no troba `self.estat =` i `\bregister\b` no troba `SMAppService.mainApp.register()`. Amb `.wordBoundaryKind(.simple)`, sí.
  Per això les guardes no fan servir `\b`, sinó `(^|[^A-Za-z0-9_])` i `(?![A-Za-z0-9_])` (`docs/disseny.md`, «Prova de
  guarda»). Comprovat amb un programa compilat amb `swiftc`, a part del repo.
- **Crides que Swift no deixa fer a macOS** (`swiftc -typecheck`): `popen` i `system` («unavailable in Swift: Use posix_spawn
  APIs or NSTask instead»), i `fork()` i `vfork()` («Please use threads or posix_spawn*()»). En canvi, `execv` i la seva
  família, i `NSUserUnixTask`, compilen: per això la guarda del codi les prohibeix.
- **Crides que canvien els permisos o els atributs i que Swift sí que deixa fer** (08/11/2026, `swiftc -typecheck`): `chmodx_np`,
  `fchmodx_np`, les de les ACL (`acl_set_file`, `acl_set_fd`, `acl_set_fd_np`, `acl_set_link_np`, `acl_delete_def_file`),
  `CFURLSetResourcePropertyForKey` i `CFURLSetResourcePropertiesForKeys` compilen. Per això són a la guarda
  (`altresCanvienAtributs`, `docs/disseny.md`, «Prova de guarda»).
- **La marca d'ordre de bytes (BOM) d'un text UTF-8** (08/11/2026, programa compilat amb `swiftc`, a part del repo, amb
  `EF BB BF` i `[general]\n`): `String(data:encoding: .utf8)` la treu (10 bytes en UTF-8); `String(decoding:as: UTF8.self)` i
  `String(validating:as: UTF8.self)` la conserven (`U+FEFF` al principi, 13 bytes). Per això `AjustRestauracio` llegeix amb
  `String(validating:as:)`: amb la primera, en escriure el fitxer es perdia la marca (revisió de la 0.31.2).
- **`renamex_np` amb `RENAME_EXCL`** (08/11/2026, el mateix programa, en una carpeta temporal): sense res al destí, mou el
  fitxer i torna 0; amb un fitxer al destí, torna -1 amb `errno` `EEXIST` (17), i no toca ni el destí ni l'origen. És com
  `AjustRestauracio` crea `settings.toml` sense trepitjar el que Warp hagi creat mentrestant (0.31.2).

## Els menús del sistema en català (09/11/2026, macOS 27.2)

**LLEGIT, no vist a l'app:** taula `ca` de `/System/Library/Frameworks/SwiftUI.framework/Versions/A/Resources/MainMenu.loctable`
(convertida amb `plutil`). L'app declara només el català (`CFBundleLocalizations`).

- `File` → «Arxiu»; `About %@` → «Sobre l’app %@»; `Quit %@` → «Surt de l’app %@»; `Settings…` → «Configuració…». Amb l'apòstrof
  tipogràfic (’). `%@` és el nom de l'app, «Warp Launch» (`CFBundleName`).
- Per això, el menú de la icona i la pantalla del permís fan servir els mateixos textos des de la 0.32.6 (`WarpLaunch.ordreSobre` i
  `ordreSurt`; abans, «Quant a Warp Launch» i «Surt de Warp Launch»). Són fixos: si una altra versió de macOS canvia els seus, no
  coincidiran.
- Als fets d'abans de la 0.32.6, «Torna a llegir Warp» és l'actual «Actualitza l'estat de Warp».

## Homebrew (09/11/2026, Homebrew 7.0.12)

Llegit al codi de Homebrew (`git describe`: `7.0.12-217-g25ccd49b8c`; les rutes són de `Library/Homebrew`) i provat amb
`Casks/warp-launch.rb` en una carpeta temporal amb `--appdir`, sense tocar `/Applications`.
- **`postflight` està deprecat** (`cask/dsl.rb`: `odeprecated`, amb `postflight_steps` com a substitut). `postflight_steps` corre
  en una caixa de seguretat, que deixa escriure a `appdir` i al Caskroom (`cask/artifact/install_steps.rb`).
  Un pas `run` amb `{{appdir}}` pot treure la quarantena.
- **Taps que no són de confiança:** Homebrew en refusa les receptes (`brew trust`, `~/.homebrew/trust.json`; `trust.rb`).
  `brew install` amb el nom complet (`david-erra/tap/warp-launch`) afegeix el tap i confia sol en aquesta recepta, no en tot el tap
  (`cmd/install.rb`, `trust_fully_qualified_items!`). `brew audit` i `brew info`, amb el mateix nom, no hi confien sols.
- **La quarantena:** el zip baixat la porta, i després del pas de la recepta l'app en té 0 atributs (`com.apple.quarantine`).
- **`uninstall quit:`** també s'executa en actualitzar i, si ha tancat l'app, la torna a obrir amb `open -b`
  (`cask/artifact/abstract_uninstall.rb` i `cask/upgrade.rb`, `reopen_apps_after_upgrade`). Si l'app no era oberta, no fa res.
  **Això s'ha llegit al codi; no s'ha provat,** per no tancar l'app oberta.
- **`depends_on macos: :tahoe`** vol dir «com a mínim macOS 26» (`cask/dsl/depends_on.rb`, comparador `>=`; `macos_version.rb`,
  `tahoe: "26"`).
- **`auto_updates true`** (llegit, per quan hi hagi Sparkle; `cask/cask.rb` i `env_config.rb`): per defecte, `brew upgrade` només
  actualitza la recepta si la versió del paquet de l'app és més vella que la de la recepta.
- **Provat de debò:** instal·lació des de zero sense el tap, actualització de la 0.28.0 a la 0.31.4 i desinstal·lació, amb la
  recepta sense `quit`. **Sense provar:** obrir una app instal·lada amb Homebrew, i el pas de `quit` i reobrir.
- **`publica.sh` escriu la recepta al tap de debò (provat el 09/11/2026, amb la 0.31.5).** És la primera vegada: la recepta de la
  0.31.4 es va escriure en crear el tap. L'autor va executar l'script amb l'opció d'aplicar, al seu terminal, des del commit `4fdcbcb`,
  amb el `GH_TOKEN` només a aquella ordre, i va acabar bé (n'ha enganxat la sortida). Comprovat després, només llegint, amb
  `gh release view` i `gh api`:
  - La `v0.31.5` apunta a `4fdcbcb`, és la `latest` i porta només `WarpLaunch-0.31.5.zip` (3.734.199 bytes). Cap `appcast.xml`: aquesta
    versió no porta Sparkle.
  - El commit `cd8c304c41cec6236a9fbd80238354b2537ab1d9` és l'últim de `main` al tap, fet 1 s després de la versió (16:12:58 i 16:12:59
    UTC), amb el missatge que posa l'script. Només toca `Casks/warp-launch.rb`: 2 línies afegides i 2 tretes (`version` i `sha256`).
  - El sha256 de la recepta és el `digest` que dona GitHub del zip pujat: `e908f041934bc150abe8a53403cae5ebef3145a50dd4bca9a66f7c6d9a2b2718`.
  - **Val per a la 0.32.7 només en aquest tros:** la crida `gh api --method PUT` i el contingut que envia són idèntics (`diff` de les dues
    versions de l'script). El que el `publica.sh` de la 0.32.x hi afegeix abans i després (signar, `appcast.xml`, `--latest`, la
    comprovació final) no s'ha executat mai de debò.
  - **Sense provar de debò:** que GitHub refusi el `PUT` si la recepta ha canviat mentrestant, i què diu llavors l'script (només amb el
    `gh` fals de `ScriptPublicaTests`). No consta que `brew` hagi instal·lat la recepta de la 0.31.5; amb la de la 0.31.4, sí (a dalt).

## Sparkle (09/11/2026, Sparkle 2.10.1)

Per a l'actualització automàtica (`docs/disseny.md`, secció 11). Marques: **PROVAT**, executat amb l'ordre i el resultat; **LLEGIT**, al codi o a la
documentació, amb fitxer i línia, sense veure-ho funcionar; **SUPOSAT**, deduït sense evidència directa.
`SP/` és el codi de Sparkle a l'etiqueta 2.10.1; `D/` és `documentation/` del web de Sparkle (`sparkle-project.github.io`, commit 6524f21, 31/10/2026).

Entorn: macOS 27.2 arm64, Swift 6.4.2 de les Command Line Tools, sense Xcode. **A les seccions 1 a 14, cap app amb interfície s'ha obert:** només eines de consola i `codesign`.
Les signatures de prova no han fet servir el clauer: una clau EdDSA d'un sol ús, generada amb CryptoKit i desada en un fitxer temporal.
**En aquelles seccions no s'ha vist mai funcionar:** la descàrrega i la instal·lació reals, el tancament i la reobertura de l'app, els avisos, l'efecte sobre el permís
d'Arxius i carpetes i sobre l'ítem d'inici, i signar amb «Warp Launch Dev». La secció 15 (ronda A) n'ha vist una part amb una app de prova; la resta continua sense veure's.


### 1. Versió, paquet i binaryTarget

- **PROVAT** (API de GitHub, `repos/sparkle-project/Sparkle/releases`): l'última estable és la **2.10.1**, del 25/10/2026 (commit
  `ab7d71291238df6e0492143b120c9b696a35f603`). Les anteriors: 2.10.0 (13/09/2026) i 2.9.6 (17/08/2026).
- **LLEGIT** (`SP/Package.swift`): URL del paquet `https://github.com/sparkle-project/Sparkle`; eines 5.5; macOS 12 com a mínim;
  `.binaryTarget` amb
  `https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip`, checksum
  `4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a`.
- **PROVAT** (API): el zip de SwiftPM fa 10.197.413 bytes; el `tar.xz` amb les eines, 16.346.336 (sha256 `1a856d2a…cf27`).
- **LLEGIT** (`D/security-and-reliability/index.md:14`): la 2.9.6 corregeix errors de seguretat. No s'ha d'anar per sota.

### 2. Compilar amb SwiftPM i les Command Line Tools

Paquet de prova: eines 6.0, macOS 26, `.package(url:…, exact: "2.10.1")`, un target amb Sparkle, un CLI sense Sparkle, una biblioteca
sense Sparkle i les seves proves.

- **PROVAT:** `swift build -c release` compila sense Xcode (1 min 35 s la primera vegada, amb la baixada).
- **PROVAT, on és el framework:** `<bin>/Sparkle.framework` (`<bin>` és `swift build -c release --show-bin-path`, que
  `build-app.sh:22` ja fa servir; en aquest entorn, `.build/out/Products/Release`), i a
  `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`.
- **PROVAT, rpaths** (`otool -l`, `otool -L`): el binari enllaça `@rpath/Sparkle.framework/Versions/B/Sparkle`, però SwiftPM no hi posa
  `@executable_path/../Frameworks`. Segons el target, hi deixa `/usr/lib/swift` i `@loader_path`, o només `/usr/lib/swift`.
  Cal afegir-lo; les dues maneres funcionen:

  | Manera | Resultat |
  |---|---|
  | `install_name_tool -add_rpath @executable_path/../Frameworks` abans de signar | dyld carrega el framework des del bundle |
  | `linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]` | compila (paquet arrel) i dyld el carrega des del bundle |

  Fora del bundle, el binari amb només aquests rpaths falla: `Library not loaded: @rpath/Sparkle.framework…`, codi 134. Afecta qualsevol
  execució directa des de `.build`.
  **Recomanació:** `install_name_tool` a `build-app.sh`, on ja s'arma el bundle: no toca `Package.swift`.
- **PROVAT, altres targets:** el CLI no enllaça Sparkle (`otool -L`), i les proves de la biblioteca passen amb la ruta del connector
  (`-plugin-path`, com a `scripts/test.sh`).
- **PROVAT, xarxa** (amb `sandbox-exec … (deny network*)`):

  | Situació | Resultat |
  |---|---|
  | Amb `.build` | compila, codi 0 |
  | Sense `.build`, amb la memòria cau de SwiftPM | compila, codi 0 («from cache») |
  | Sense `.build` i sense memòria cau | falla, codi 1, **també si només es compila el CLI** |

  Avui el repo compila sense internet; amb Sparkle, la primera compilació d'un clon nou en necessitarà. Memòria cau: 9,7 MB
  d'artefactes i 49 MB de repositoris.
- **PROVAT:** `Package.resolved` fixa la revisió. Al repo avui no n'hi ha (`git ls-files`) i `.gitignore` no l'exclou: **s'ha de fer commit**.

### 3. Muntar i signar l'app

- **PROVAT:** un `.app` mínim amb `Contents/Frameworks/Sparkle.framework` (copiat amb `ditto`) i signat de dins cap a fora, sense `--deep`,
  passa `codesign --verify --strict` i `--strict --deep`. Ordre: `Installer.xpc`, `Downloader.xpc` (`--preserve-metadata=entitlements`),
  `Autoupdate`, `Updater.app`, el framework, l'executable i l'app.
- **LLEGIT:** és l'ordre de `D/sandboxing/index.md:75-94`.
- **PROVAT, com ve signat:** `flags=0x10002(adhoc,runtime)`, sense Team ID, entitlements buits a `Downloader` i `Updater`.
- **PROVAT, mides** (`du`): framework tal com ve, 2,9 MB. Amb XPC, 2.836 KB; sense XPC, 2.512 KB. El zip de l'app de prova
  (sense XPC, amb executables petits): 1.002.251 bytes. La 0.31.4 fa 3.714.522 bytes comprimida.
- **LLEGIT, XPC:** només calen en apps amb sandbox (`D/sandboxing/index.md:100-140`, `D/customization/index.md:48,53-56`,
  `SP/Sparkle/SPUUpdater.m:232-252`). Warp Launch no en té (cap `entitlements` al repo). Treure-les estalvia 0,3 MB i dos passos de signatura.
  Cal treure `Versions/B/XPCServices` **i** l'enllaç `XPCServices`, i tornar a signar el framework.
- **PROVAT, casos negatius** — `--verify --strict` sol **no veu** dos errors que `--deep` sí:

  | Cas | `--strict` | `--strict --deep` |
  |---|---|---|
  | XPC trets, framework sense tornar a signar | codi 0 | codi 1, «a sealed resource is missing or invalid» |
  | `Autoupdate` tornat a signar, framework no | codi 0 | codi 1, «nested code is modified or invalid» |
  | `Info.plist` del framework alterat | codi 1 | codi 1 |
  | Enllaç `XPCServices` penjat | codi 0 | codi 0 |
  | Només l'app signada, framework tal com ve | codi 0 | codi 0 |

  **Conseqüència:** `build-app.sh:54` i `publica.sh:131` verifiquen sense `--deep` i no ho veurien.
- **SUPOSAT:** el mateix ordre val amb «Warp Launch Dev» (aquí, només ad hoc, per no tocar el clauer).

### 4. App sense notaritzar i amb certificat propi

- **LLEGIT, la regla** (`SP/Sparkle/SUUpdateValidator.m:296-303`, `:373`): una actualització s'accepta si la clau EdDSA (la vella i la
  nova iguals i vàlides) **o** la identitat de codi (igual i vàlida) passen.
- **LLEGIT:** la signatura EdDSA es comprova amb la clau pública de l'app **vella** (`:338-341`). Una signatura corrupta es refusa (`:364`).
- **LLEGIT:** identitat: `SecCodeCopyDesignatedRequirement` de la vella i `SecStaticCodeCheckValidityWithErrors` a la nova
  (`SP/Autoupdate/SUCodeSigningVerifier.m:26-137`, `SUUpdateValidator.m:344-345`). Ad hoc compta com a signada (`SUCodeSigningVerifier.m:248-270`, `:285`).
- **LLEGIT:** no es pot perdre la clau EdDSA ni la signatura de codi entre versions, i «adhoc signing can be used at minimum» (`SUUpdateValidator.m:271-294`, `:285`).
- **LLEGIT:** **Sparkle no comprova notarització ni Gatekeeper** (cap `spctl`; a `SUPlainInstaller.m:349` només un comentari).
- **LLEGIT, quarantena:** Sparkle la treu de tot el paquet (`SP/Autoupdate/SUPlainInstaller.m:48-53`, `SP/Sparkle/SUFileManager.m:120-160`); si falla, continua.
  `gktool scan` tampoc no és fatal (`SUPlainInstaller.m:94-124`).
- **LLEGIT:** refusa versions més velles (`SUPlainInstaller.m:327-343`), i si l'app corre traslladada per macOS, avorta (`SP/Sparkle/SPUBasicUpdateDriver.m:77-78`).
- **PROVAT:** el zip fet com a `publica.sh:140` no porta quarantena en extreure'l (`xattr`), manté 8 enllaços simbòlics i passa
  `--strict --deep`.
- **SUPOSAT:** una app sense quarantena i sense notaritzar s'obre sense avisos, com amb Homebrew (`docs/especificacio.md:62`). No s'ha obert.

### 5. De «Warp Launch Dev» a Developer ID

- **LLEGIT:** amb la mateixa clau EdDSA, el canvi d'identitat passa (`SUUpdateValidator.m:299,373`; `D/index.md:127`: «either your Apple code
  signing certificate or your EdDSA keys (but not both)»).
- **LLEGIT:** si canvien totes dues, es refusa (`:379-416`).
- **LLEGIT:** el Team ID nou és diferent del d'`Autoupdate` vell (cap), i llavors no hi ha substitució atòmica ni `gktool`: passa pel camí antic
  (`SUPlainInstaller.m:349-365,371-376,247-314`), amb un comentari que avisa d'avisos de Privacitat i seguretat.
- **LLEGIT:** l'alternativa per Developer ID només és amb `SUVerifyUpdateBeforeExtraction` (`SUUpdateValidator.m:76-95`, `SUCodeSigningVerifier.m:323-363`), i necessita un Team ID vell.
  No aplica.
- **LLEGIT:** rotar la clau amb el mateix certificat passaria per `:345,351-358`. No s'ha provat.
- **SUPOSAT:** un cop signada amb Developer ID, cal tornar a signar el framework amb la mateixa identitat, per la validació de biblioteques amb
  «hardened runtime» (`D/index.md:55`).

### 6. Actualitzacions silencioses

| Clau de l'`Info.plist` | Efecte | Evidència (LLEGIT) |
|---|---|---|
| `SUEnableAutomaticChecks` | Qualsevol valor: **no pregunta**. Sense la clau, pregunta al segon llançament | `SP/Sparkle/SPUUpdater.m:405-409,415-416`, `D/customization/index.md:12,24` |
| `SUAutomaticallyUpdate` | `YES`: baixa i prepara sola. Sense la clau, `NO` | `SP/Sparkle/SPUUpdaterSettings.m:326-329`, `D/customization/index.md:26` |
| `SUAllowsAutomaticUpdates` | Sense la clau, segueix les comprovacions automàtiques; `NO` ho prohibeix | `SPUUpdaterSettings.m:302-318`, `D/customization/index.md:28` |
| `SUScheduledCheckInterval` | 86.400 s per defecte, mínim 3.600 | `D/customization/index.md:25`, `SPUUpdaterSettings.m:377-430` |

Després de la baixada silenciosa (LLEGIT):

- Hi ha excepcions que demanen l'atenció de l'usuari: informativa, major, signatura fallida (`SP/Sparkle/SPUAutomaticUpdateDriver.m:82-85`).
- Si necessita autorització, no s'instal·la sola (`SPUAutomaticUpdateDriver.m:150`, `D/customization/index.md:26`).
- L'instal·lador **espera que l'app es tanqui**. En tancar-se, instal·la i **no la torna a obrir** (`SP/Autoupdate/AppInstaller.m:399-417,765-831`, `:821`).
- Passats 7 dies sense tancar, se li mostra a l'usuari (`SUScheduledImpatientCheckInterval`: `SPUUpdater.m:528-537`, `D/gentle-reminders/index.md:22`).

Delegats (LLEGIT):

- `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` (`SPUAutomaticUpdateDriver.m:104-129`, capçalera `SPUUpdaterDelegate.h:421-440`): si torna
  `true`, l'app decideix quan. **El bloc instal·la i torna a obrir l'app.** Es pot cridar més d'un cop des de la 2.3. L'actualització s'instal·la igualment en tancar.
- El camí del bloc: `SPUCoreBasedUpdateDriver.m:316-317` → `SPUInstallerDriver.m:509-561` → `AppInstaller.m:654-680,749-763` → `SP/Sparkle/InstallerProgress/InstallerProgressAppController.m:375-385`.
- `updaterShouldRelaunchApplication` amb `false` **avorta la instal·lació** (`SPUInstallerDriver.m:503-519`). No s'ha de fer servir per ajornar.
- `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` ajorna, una sola vegada (`SPUInstallerDriver.m:521-535`, capçalera `:342-356`).

Com tanca l'app (LLEGIT):

- `Updater.app` envia un Apple Event de sortida: `[runningApplication terminate]`, amb el comentari «gives the application or user a chance to delay or cancel»
  (`InstallerProgressAppController.m:375-385`). A les fonts de Sparkle no hi ha cap `NSApp terminate:`.
- Espera `isTerminated` amb KVO, **sense temps límit** (`:335-357`), i llavors reobre (`:387-421`).
- Per tant, passa per `applicationShouldTerminate` (`Sources/WarpLaunchApp/WarpLaunchApp.swift:283-317`). **`.terminateLater` es respecta** i
  `.terminateCancel` deixa l'actualització preparada. Tancar Warp Launch no toca Warp.

**Per a Warp Launch** (LLEGIT del repo, comportament no provat):

- Una app de barra de menú gairebé no es tanca: sense el bloc, l'actualització pot quedar esperant fins a 7 dies. Cal cridar-lo en un moment segur (sense
  fulls oberts ni obertures en marxa).
- La reobertura, si és als primers 600 s des de l'arrencada i amb l'ítem d'inici registrat, compta com a inici de sessió per a `InicDeSessio.es`
  (`Sources/WarpLaunchCore/InicDeSessio.swift`, `marge = 600`) i mostraria el full «Obre-ho tot». Cal una condició (ajornar-la o distingir-ho).

### 7. App de barra de menú (`LSUIElement`)

- **LLEGIT:** Sparkle la considera «en segon pla» si la política és `.accessory` (`SP/Sparkle/SUApplicationInfo.m:17-20`). L'app hi va quan no té finestres
  (`Sources/WarpLaunchApp/Activacio.swift:124-125`).
- **LLEGIT:** sense recordatoris suaus, Sparkle deixa un avís al registre (`SP/Sparkle/SPUStandardUserDriver.m:161-172`) i porta la finestra al davant
  (`:129-135,203-207`). Cal implementar `supportsGentleScheduledUpdateReminders`, `standardUserDriverShouldHandleShowingScheduledUpdate`, etc.
  (`SPUStandardUserDriverDelegate.h:92-102,134`; `D/gentle-reminders/index.md:20-22,64-130`).
- **LLEGIT:** si l'ha demanat l'usuari, enfoca la finestra (`SPUStandardUserDriver.m:185-191,488-490,552-556`).
- **SUPOSAT:** la finestra de Sparkle i el canvi de política de `Activacio.swift` conviuen. Cal veure-ho a l'app.

### 8. API amb SwiftUI i Swift 6

- **PROVAT:** compila en mode Swift 6, sense avisos, un `MenuBarExtra` amb `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate:, userDriverDelegate:)`,
  un `@Observable` que observa `canCheckForUpdates` i `lastUpdateCheckDate` per KVO, i un delegat `@MainActor`.
- **PROVAT, concurrència:** sense `@MainActor SPUStandardUserDriverDelegate`, error «crosses into main actor-isolated code». Aquest protocol no és `NS_SWIFT_UI_ACTOR`
  (`SPUStandardUserDriverDelegate.h:31`); `SPUUpdaterDelegate`, `SPUUpdater` i `SPUStandardUpdaterController`, sí.
- **PROVAT:** `standardUserDriverDidReceiveUserAttention(forUpdate:)` és el nom en Swift. `@State` no compila amb les Command Line Tools (`plugin for module 'SwiftUIMacros' not found`, fet ja conegut del repo).
- **LLEGIT:** els delegats són febles: cal retenir-los (`SPUStandardUpdaterController.h`). Exemple oficial: `D/programmatic-setup/index.md:40-98`. KVO: `SPUUpdater.h:167`, `SPUUpdater.m:495-499`.
- **LLEGIT, «ja la tens al dia»:** `SPUBasicUpdateDriver.m:193-232`, `SPUNoUpdateFoundInfo.m:61`, alerta a `SPUStandardUserDriver.m:616-655`.
- **PROVAT, català:** `ca.lproj/Sparkle.strings` té 26 claus, per 82 de `Base` (`es`: 44). El que no hi és surt en anglès (`SULocalizations.h:20`). Amb `CFBundleLocalizations` només `ca`,
  el framework tria `["ca"]` amb `AppleLanguages` en, es, fr, de i ca, i tradueix «You’re up to date!» com a «Ja esteu al dia!». «Checking for updates…» queda en anglès.
  «Install on Quit» es tradueix «Reinicia el programa més tard» (`ca.lproj:38`), que no és el que fa.

### 9. Appcast a GitHub

- **PROVAT** (`curl` i `URLSession`): `…/releases/latest/download/appcast.xml` fa 302 (`cache-control: no-cache`) a `/releases/download/v0.31.4/appcast.xml`, que avui és 404
  (la 0.31.4 no en porta). Un fitxer existent: 302, 302 i `release-assets.githubusercontent.com` 200, `application/octet-stream`, amb memòria cau CDN (`age: 6777`, `x-cache: HIT`).
- **LLEGIT:** Sparkle fa servir `URLSession` per defecte, que segueix redireccions (`SP/Downloader/SPUDownloader.m:83-84`), només accepta http/https (`:75-76`) i ignora la memòria cau local (`SP/Sparkle/SPUDownloadDriver.m:125-129`).
- **LLEGIT:** `gh release create` amb fitxers fa esborrany, puja i publica (`cli/cli`, `pkg/cmd/release/create/create.go`, `draftWhileUploading`). Si `appcast.xml` i el zip van a la mateixa ordre, `latest` només canvia amb tots dos a dalt.
  Una versió publicada **sense** `appcast.xml` deixa tothom amb un 404 fins a la següent: `publica.sh` ho ha de refusar.
- **LLEGIT, camps** (`SP/Sparkle/SUAppcastItem.m`): `sparkle:version` (`:473-500`), `enclosure url` (`:597-632`), `length` (`:606-611`), `sparkle:edSignature` (`:635`), `sparkle:minimumSystemVersion` (`:644`), `sparkle:hardwareRequirements` (`:649`), `sparkle:shortVersionString` (`:737-743`), `sparkle:releaseNotesLink` (`:818`).
- **PROVAT, `generate_appcast`** amb clau de fitxer i `--download-url-prefix`: sobre una carpeta amb un zip, codi 0, un `<item>` amb versió, versió curta, `minimumSystemVersion 26.0` i `hardwareRequirements arm64` (trets del paquet), `enclosure` amb URL, `length` i `edSignature`. Cap `.delta` amb un sol zip.
  Escriu una memòria cau a `~/Library/Caches/Sparkle_generate_appcast` (`generate_appcast/main.swift:74`); aquí redirigida amb `CFFIXED_USER_HOME`, i la real no s'ha creat.
- **Recomanació:** `generate_appcast` amb una carpeta temporal que només tingui el zip nou, i `--download-url-prefix …/releases/download/vX.Y.Z/`. Fa menys feina i no s'ha de mantenir la plantilla XML.
- **PROVAT, zip:** és el mateix `ditto -c -k --sequesterRsrc --keepParent` de `publica.sh:140` (`D/publishing/index.md:14-22`).
- **PROVAT, signatura:** `sign_update -f <fitxer>` dona `sparkle:edSignature="…" length="1002251"`. `--verify` passa (codi 0), CryptoKit ho confirma de manera independent, i amb un bit canviat falla («failed to pass signing verification», codi 1).
- **PROVAT, comparació de versions** (`SUStandardVersionComparator`): 0.31.4 < 0.32.0, 0.31.4 < 0.31.10, 0.31.9 < 0.31.10, 0.31.4 < 1.0.0, 0.31 = 0.31.0. **`0.31.4-beta` = 0.31.4** (el guió atura la lectura, `SUStandardVersionComparator.m:114-116`); `0.31.4b1` és menor que 0.31.4.
  Compara `CFBundleVersion` (`D/index.md:148`), que `Recursos/Info.plist` treu de `VERSION`.

### 10. Eines i clau EdDSA

- **PROVAT:** són a `.build/artifacts/sparkle/Sparkle/bin/` (i al `tar.xz`): `generate_appcast`, `generate_keys`, `sign_update`, `BinaryDelta`. Només s'ha fet `--help` de `generate_keys`: **sense arguments, crea la clau**.
- **LLEGIT:** es desa al clauer d'inici de sessió, «generic password», servei `https://sparkle-project.org`, compte `ed25519`, el valor és la llavor de 32 bytes en base64 (`generate_keys/main.swift:13-30,105-126`, `common_cli/Secret.swift:19-47`).
- **LLEGIT:** `-x fitxer` l'exporta (no sobreescriu, `:220-222`), `-f fitxer` la importa, `-p` mostra la pública (`:161-170,206-260`).
- **LLEGIT:** `sign_update` i `generate_appcast` fan servir el fitxer si s'indica i, si no, el clauer (`sign_update/main.swift:97,177-181`, `generate_appcast/main.swift:19-38,83`).
- **LLEGIT, si es perd:** `D/index.md:111`. Amb la clau perduda i el mateix certificat, encara es podria canviar la clau (`SUUpdateValidator.m:345,351-358`).
- **SUPOSAT** (de `:373-416`): sense la clau **ni** el certificat, les instal·lacions existents no es poden actualitzar mai més soles. Cal una còpia fora del Mac.

### 11. Prova de punta a punta sense publicar

- **PROVAT, ATS** (eina de consola dins d'un bundle sense `NSAppTransportSecurity`, sessió `URLSession`, macOS 27.2):

  | URL | Resultat |
  |---|---|
  | `http://127.0.0.1:<port>/appcast.xml` | HTTP 200 |
  | `http://localhost:<port>/appcast.xml` | HTTP 200 |
  | `http://example.com/` | `NSURLErrorDomain -1022` (ATS) |

  Per tant, **no cal cap excepció d'ATS** per a un servidor local. Sparkle només deixa un avís al registre si no hi ha `https` (`SPUUpdater.m:284-313`).
- **LLEGIT:** `file://` es refusa (`SPUDownloader.m:75-76`, `SUAppcastItem.m:625-632`).
- **LLEGIT:** `D/index.md:168-178` explica el procediment; `SPUUpdater.m:179-181` permet canviar l'adreça amb `defaults write`, amb un avís, però una app de prova a part és més net.
- **PROVAT, peces ja fetes:** dues versions (0.31.4 i 0.32.0), zip, signatura amb la clau de prova, appcast i servidor local (`python3 -I -m http.server --bind 127.0.0.1 <port>`). Comproveu abans que el port és lliure (`lsof -nP -iTCP:<port> -sTCP:LISTEN`).

El camí menys invasiu (**no executat: obre una app i cal OK, regla 1 i 4**):

1. Una app de prova **a part**, amb identificador propi (`cat.exemple.prova-sparkle`), a una carpeta temporal, amb clau de prova. Obre **1 app, 0 finestres de Warp, 0 sessions de Claude**.
2. Compilar la 0.31.4 i la 0.32.0; `SUFeedURL` a `http://127.0.0.1:<port>/appcast.xml`. Generar l'appcast amb `--download-url-prefix http://127.0.0.1:<port>/`.
3. Obrir la 0.31.4 i prémer «Comprova…». Mirar el registre (`/usr/bin/log show --last 5m --predicate 'process == "ProvaApp" OR process == "Autoupdate"'`).
4. Comprovar: `CFBundleVersion` = 0.32.0, `codesign --verify --strict --deep`, i que torna a obrir.
5. Repetir amb el bloc immediat, amb `.terminateLater` i amb l'appcast amb un bit canviat (ha de refusar).
6. Repetir **amb «Warp Launch Dev»**, per veure la identitat de debò.
7. Neteja: esborrar la carpeta, `defaults delete cat.exemple.prova-sparkle` i `~/Library/Caches/cat.exemple.prova-sparkle` (Sparkle hi escriu fora de la carpeta temporal).

Per veure el permís d'Arxius i carpetes i l'ítem d'inici, caldrà una actualització real de l'app, en un Mac on es pugui repetir.

### 12. Privacitat

- **LLEGIT:** un GET a `SUFeedURL` amb `User-Agent` `$(BundleDisplayName)/$(BundleDisplayVersion) Sparkle/$(SparkleDisplayVersion)` (`SPUUpdater.h:330-331`) i `Accept: application/rss+xml,*/*;q=0.1`; sense paràmetres si no s'envia el perfil (`SPUUpdater.m:1249-1277`).
- **LLEGIT:** el perfil (versió de macOS, CPU, model, idioma, RAM, nom i versió de l'app: `SP/Sparkle/SUSystemProfiler.m:20-30,47-163`), com a molt un cop per setmana (`SPUUpdater.m:1251-1262`), **només si `SUSendProfileInfo`** és actiu (`SPUUpdaterSettings.m:349-352`). `SUEnableSystemProfiling` només mostra l'opció al primer avís (`SUUpdatePermissionPrompt.m:78`, `D/system-profiling/index.md:8-32`).
- GitHub rep l'adreça IP de cada comprovació. **SUPOSAT** que no hi ha res més: cap altra connexió trobada a les fonts llegides.
- `docs/especificacio.md:57` (decisió 6): és la primera connexió a internet de l'app.

### 13. Riscos a macOS 26 i 27

- **App Management** (LLEGIT): el missatge d'error és només per a actualitzadors externs (`SPUInstallerDriver.m:105-129`, `:108`); `SUPlainInstaller.m:349-352`. Amb el mateix Team ID no hauria d'aparèixer. **SUPOSAT** amb «Warp Launch Dev» (sense Team ID).
- **Arxius i carpetes** (LLEGIT del repo, `build-app.sh:43`): depèn de la identitat de la signatura. **SUPOSAT:** amb «Warp Launch Dev», es conserva en actualitzar. Amb Developer ID, es perd un cop (`docs/especificacio.md:57`, decisió 1).
- **`SMAppService.mainApp`** (SUPOSAT): Sparkle substitueix a la mateixa ruta i l'ítem es manté. No provat.
- **App d'un altre usuari o usuari sense administrador** (LLEGIT): `SUInstallerLauncher.m:340-375` comprova si es pot escriure a l'app i a la carpeta; si no, necessita autorització (`:161,173`), i la silenciosa queda ajornada (`:469-472`). `instal·la.sh:54-56` demana un compte d'administrador per instal·lar; un altre usuari sense permís no s'actualitzarà sol.
- **Instal·ladors** (LLEGIT): `SUInstallerLauncher.m:278-285`, tasca temporal de `launchd` (`SMJobSubmit`), etiqueta `<id>-sparkle-updater`. No és un LaunchAgent permanent.
- **Altres usuaris amb sessió oberta** (LLEGIT): `InstallerProgressAppController.m:300`.
- **macOS 27** (SUPOSAT): Sparkle es compila amb l'SDK 26.5; aquí s'ha carregat i s'ha comparat versions, sense instal·lar res.
- **Homebrew:** `auto_updates true` (`docs/disseny.md:2116-2118`), perquè `brew upgrade` no hi passi pel damunt.

---

### 14. En implementar-ho (09/11/2026, de la 0.32.0 a la 0.32.5)

**Res d'això no diu que funcioni a l'app:** no se n'ha obert cap.

- **PROVAT** (`swift build` i `otool -l .build/debug/WarpLaunch`, 0.32.5): els rpaths són `/usr/lib/swift`, `@loader_path` i la carpeta `PackageFrameworks` de `.build`, amb
  `Sparkle.framework` al costat del binari. El binari no s'ha executat (regla 4): que arrenqui és **SUPOSAT**.
- **PROVAT** (un programa a part, sense finestres): amb la secció, «General» faria 738 pt, més dels 640 de la norma.
- **PROVAT** (`xmllint --noout`): `--` dins d'un comentari d'un `Info.plist` no és XML vàlid. Els lectors d'Apple el deixen passar.
- **PROVAT** (`build-app.sh release --amb-feed`, amb adreça i clau falses, i un fitxer fals esborrat després): la còpia porta les dues claus i passa `codesign` amb el
  requisit a l'app i a les tres peces de Sparkle. Sense l'opció, no porta `SUFeedURL`.
- **PROVAT** (`scripts/verifica-signatura.swift`, des de l'arrel del repo, amb una clau d'un sol ús en memòria): 0 amb la bona, 1 amb una altra.
- **LLEGIT, sense provar:** el `sign_update` real amb la clau del clauer; que `gh release create` publiqui els dos fitxers de cop i mogui `latest` només amb tots dos; que
  Sparkle accepti l'appcast a l'app; que Claude Code apliqui les regles `deny` com les simula la guarda.

### 15. Ronda A: Sparkle de debò, amb una app de prova (09/11/2026)

**Què s'ha executat:** `cat.exemple.prova-sparkle`, una app de barra de menú feta per a la prova, amb el model, la política i el servei del commit `379689e`, Sparkle 2.10.1 i
**signatura ad hoc**, en una **carpeta temporal**, contra un servidor local i amb una clau EdDSA d'un sol ús (CryptoKit). Amb l'OK d'en David. **No és l'app de debò:** Warp Launch
no s'ha obert, i Warp i Claude no s'han tocat. Disseny de la ronda: `docs/disseny.md`, secció 11, apartat 8.

**Com s'ha mirat:** el registre de l'app de prova (una línia per canvi: estat, versió del binari i del paquet, i l'intent), el registre de peticions del servidor, `plutil` i
`pgrep` en acabar, i un canal d'ordres dins de l'app de prova: «clicar» és `performClick` sobre l'`NSButton` i «tancar», `performClose` sobre la finestra.

- **PROVAT, el cicle complet (A2 i A3):** amb l'interruptor encès, «Comprova» baixa la versió i la deixa a punt sense cap finestra; «Reinicia i actualitza» tanca l'app i aquesta
  torna sola amb el binari i el paquet a la 1.0.1. Del «Baixant» al binari nou, 3 s, amb un zip local.
- **PROVAT, sortir amb la versió a punt (A4):** en sortir, la 1.0.1 s'instal·la i l'app no torna (`plutil` i `pgrep`, passats 15 s).
- **PROVAT, sortida cancel·lada (A5):** amb la sortida cancel·lada des de dins de l'app, es queda a «S'està actualitzant…» 65 s; passats els 60 s del límit torna a «a punt», i el
  segon intent instal·la i torna amb la 1.0.1. **Bug vist aquí, corregit a la 0.32.9:** l'intent quedava escrit (`laSortidaCancellaLIntent`, només amb falsos).
- **PROVAT, zip amb un bit canviat (A6):** refusat abans d'extreure; el paquet continua a la 1.0.0. Sense cap finestra. El text era «No s'ha pogut comprovar: The update is improperly signed…»
  (corregit a la 0.32.9; a sota, per què).
- **PROVAT, interruptor apagat (A7):** 0 peticions en 2 minuts (`SULastCheckTime` esborrat i el registre del servidor buidat abans de comptar). El control amb l'interruptor encès, sí que en fa.
- **PROVAT, instal·lació fallida (A8):** **es confirma el supòsit [S] de `chflags uchg`** al paquet, posat després de quedar a punt: «Reinicia i actualitza» tanca l'app, la instal·lació falla i
  l'app no torna. El paquet continua a la 1.0.0. En tornar-la a obrir a mà, `fallades=1 versioFallada=1.0.1`, i la secció ho diu.
- **PROVAT, cap reinici sol després d'una fallada (A8b):** més de 8 minuts seguits amb la mateixa versió a punt i el Mac sense tocar (`CGEventSource` diu més de 8.000 s d'inactivitat):
  `espera=«Ara no: aquesta versió no s'ha pogut instal·lar sola»`, i l'app no surt.
- **PROVAT, sense servidor (A9):** «No s'ha pogut comprovar: Hi ha hagut un error obtenint la informació d'actualització…», i ja no diu «Tens l'última versió». Després de reobrir-la, no afirma res.
- **PROVAT, appcasts refusats (A10):** informativa, crítica i zip en un altre domini: «la versió publicada no té la forma esperada», cap finestra i cap `.zip` al registre del servidor.
- **PROVAT, la finestra de baixada acabada (A11):** es titula «Actualitzant Warp Launch» i **només té el botó «Instal·la i reinicia»**; `performClose` no la tanca (8 s després hi continua).
  [L: `SP/Sparkle/SPUStandardUserDriver.m:514`, `closable:NO`; `SUStatusController.m:59-60`.] **Bug vist aquí, corregit a la 0.32.9:** el model es quedava a «Baixant la 1.0.1…», sense
  botó ni menú per tornar-hi (la llista de botons del canal inclou els amagats: «Recorda-m'ho més tard» i la casella hi surten amb l'interruptor apagat, i l'alerta els amaga, `SUUpdateAlert.m:385,477`).

**NO s'ha vist a la ronda A:**

- **Cap clic real:** tot, amb el canal d'ordres de dins de l'app de prova.
- **El botó «Instal·la i reinicia»:** no s'ha premut mai. Ni el clic ni l'ajornament s'han vist: el que en diu la 0.32.9 és llegit i provat amb falsos.
- **Que la inactivitat baixi en moure el ratolí:** només s'ha vist pujar (A12, sense tocar res).
- **Cap dels diàlegs mirant la pantalla:** només els títols i els botons que dona el canal, i el que hi ha a les fonts.
- **La signatura amb certificat propi a `/Applications`:** és la ronda B.
- **L'app de debò,** ni cap dels canvis de la 0.32.9 fora de les proves.

**LLEGIT, per als canvis de la 0.32.9** (`docs/disseny.md`, secció 11, 2.1):

- **Tornar a la finestra:** `checkForUpdates()` amb una actualització a la vista la porta al davant, i activa l'app si cal (`SP/Sparkle/SPUUpdater.m:697-699`, `SPUStandardUserDriver.m:466-492`).
  `showingUpdate` queda a `YES` des de la primera alerta (`SPUUserInitiatedUpdateDriver.m:92-93`, `SPUUIBasedUpdateDriver.m:323-325`).
- **El clic es gasta:** «Instal·la i reinicia» crida el gestor i el deixa a `nil` (`SPUStandardUserDriver.m:521-527`); si el delegat ajorna, no torna a fer res (`SPUInstallerDriver.m:522-535`).
- **La casella «Descarrega i instal·la les actualitzacions automàticament en el futur»** està lligada a `automaticallyDownloadsUpdates` (`SUUpdateAlert.xib:119`), que desa `SUAutomaticallyUpdate`
  (`SPUUpdaterSettings.m:330-339`). **Només es veu amb l'interruptor encès:** l'alerta l'amaga si `allowsAutomaticUpdates` és fals (`SUUpdateAlert.m:385`), i sense `SUAllowsAutomaticUpdates`
  aquest valor és el de les comprovacions automàtiques (`SPUUpdaterSettings.m:314-317`). Amb `SUAllowsAutomaticUpdates` a fals, l'amagaria, però la baixada sola tampoc funcionaria (`:326-329`).
- **Errors que arriben a `updater:didAbortWithError:`** (`SPUUpdater.m:801-805`): tots menys `SUInstallationAuthorizeLaterError`. Els de comprovar venen en català si Sparkle el porta («An error occurred in
  retrieving update information», `ca.lproj:20`); els de baixar, signar i instal·lar, en anglès (`Base.lproj/Sparkle.strings:62,71,77,170`; `SPUInstallerDriver.m:98-104`, que amaga el `SUValidationError` dins d'un `SUInstallationError`).

### Què impedeix o canvia el plantejament

1. **Qui té la 0.31.5 o anterior no té Sparkle.** Han de fer una última actualització manual (Homebrew o l'script) per arribar a la primera versió amb Sparkle.
2. **Si es canvia la clau EdDSA i la signatura alhora, es perden les actualitzacions.** El pas a Developer ID ha de mantenir la clau; **una versió publicada amb signatura ad hoc** trencaria la identitat: `publica.sh:131` ja ho refusa amb un requisit, i s'ha de mantenir.
3. **Instal·lar en tancar no n'hi ha prou** en una app de barra de menú: cal el bloc immediat en un moment segur.
4. **`build-app.sh` i `publica.sh` han de canviar:** copiar el framework, l'rpath, signar de dins cap a fora i `--deep` a la verificació.
5. **La reobertura en els primers 600 s** es confon amb un inici de sessió (`InicDeSessio.es`).
6. **El català és parcial** i «Install on Quit» diu una cosa que no fa.
7. **Clon nou sense xarxa:** ja no compilarà, tampoc el CLI sol.

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

- **Màquina:** Apple Silicon, macOS 27.2.
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
    - Al Mac de prova, `defaults read -g com.apple.springing.delay` és 0.5 i `com.apple.springing.enabled`, 1
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
      sistema (`/usr/bin/log show`, procés `WarpLaunch`, a 6 execucions de l'app, dues vegades a la de la prova) diu per
      què: `NSItemProvider` «Finished loading data representation for type identifier
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
    - **Confirmat a la prova 7c** (04/11/2026, registre de l'app, dos intents): a la fila d'una finestra, la
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
    - Creat amb el LibreSSL de macOS (`/usr/bin/openssl` 3.3.6) i importat al clauer
      d'inici de sessió amb `security import … -T /usr/bin/codesign`. Amb això, `codesign` el fa servir sense
      cap diàleg.
    - `find-identity` el mostra com a `CSSMERR_TP_NOT_TRUSTED` (no és de confiança), i `codesign` hi signa
      igualment.
    - La identitat de l'app passa a ser `identifier "cat.davide.warp-launch" and certificate leaf =
      H"c1ec55b1…"`, que no canvia en recompilar. Que el permís de TCC es mantingui entre compilacions està
      per verificar.
- **nano-banana (API d'imatges de Gemini)** (03/11/2026, `scripts/genera-imatge.sh --models` amb una clau de
  l'API). Models d'imatge disponibles:
  - `gemini-2.5-flash-image` (Nano Banana).
  - `gemini-3-pro-image` i `-preview` (Nano Banana Pro).
  - `gemini-3.1-flash-image` i `-preview` (Nano Banana 2).
  - `gemini-3.1-flash-lite-image` (Nano Banana 2 Lite).
  - `jq` és del sistema (`/usr/bin/jq`).
- **`gh`** (2.102): el fan servir `scripts/publica.sh` i `scripts/instal·la.sh --github`. Per publicar, cal un token que pugui
  escriure al repo (`GH_TOKEN`).
