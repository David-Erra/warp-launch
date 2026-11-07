# Antecedents: què existeix ja

Dues recerques, només de lectura (no s'ha provat cap eina):

- **03/11/2026:** cerques web, GitHub (`gh search`, `gh api`), documentació de Warp i de Claude Code, i el codi obert de
  `warpdotdev/warp`.
- **07/11/2026, revisió:** quatre fonts per separat. Les novetats de Warp (documentació, changelog i el Warp instal·lat,
  0.2026.11.04, llegit sense obrir-lo: només `oz --help`), el GitHub de Warp (issues, PR i el codi de `master` a `abb3fe33`, del 06/11/2026),
  Claude Code (documentació i changelog, 2.1.319) i les eines de tercers (`gh api`, README i codi).

Les estrelles i les dates són del dia de cada recerca.

## Les cinc funcions

El que fa Warp Launch, i amb què es compara cada candidat:

- **F1. Llegir** les finestres i pestanyes obertes a Warp, amb la carpeta i la sessió de Claude Code de cada pestanya.
- **F2. Editar** una configuració desada: finestres, pestanyes, carpeta, títol i com s'hi obre Claude (permisos, esforç,
  model, ultracode, reprendre la conversa).
- **F3. Obrir** les finestres a Warp, amb Claude a cada pestanya i la seva conversa represa.
- **F4. En iniciar sessió,** obrir-se sola i proposar d'obrir-ho tot amb un clic.
- **F5. La restauració de Warp:** deixar `restore_session` desactivada perquè Warp no dupliqui les pestanyes, i activar-la
  uns segons quan cal una foto de les finestres.

## Conclusió (07/11/2026)

**Ni Warp (0.2026.11.04), ni Claude Code (2.1.319), ni cap eina de tercers fan F1 a F5 junts amb Warp.** Per això fem
Warp Launch.

- **Warp dona les peces, no el conjunt:** launch configurations amb `exec`, `warp://launch/<nom>`, Tab Configs,
  `restore_session` i `login_item`. L'app en fa servir les launch configurations amb `exec`, `warp://launch/<nom>` i
  `restore_session`; els Tab Configs i `login_item`, no (per obrir-se en iniciar sessió fa servir `SMAppService`). La seva guia oficial diu que la restauració no reprèn
  Claude i remet a `claude --resume`: «session restoration preserves tabs and panes, but not running CLI processes —
  closing Warp ends Claude Code's session. Use Claude Code's built-in resume options (e.g., claude --resume)»
  ([Migrate to Warp from Claude Code](https://docs.warp.dev/getting-started/migrate-to-warp/migrate-to-warp-from-claude-code.md)).
- **Claude Code:** les sessions en segon pla (agent view, `claude --bg`) són una llista desada de sessions de totes les
  carpetes, però no sobreviuen a un reinici (surten «failed» o «stopped», i cal reprendre-les una a una) i no són
  pestanyes de Warp.
- **L'eina més propera,** [warp-agent-session-restore](https://github.com/agentsdance/warp-agent-session-restore), que la
  recerca del 03/11 no va trobar, reprèn soles les sessions de Claude que eren vives. No té editor ni toca
  `restore_session`, i escriu hooks a `~/.claude/settings.json` (ho prohibeix la regla 6).
- **Risc:** si Warp implementa [#14960](https://github.com/warpdotdev/warp/issues/14960), reprendria Claude als panes que
  restaura, que és part de F3. No cobriria la configuració editable, triar què s'obre ni les opcions de llançament.

| | Warp 0.2026.11.04 | Claude Code 2.1.319 | warp-agent-session-restore 0.0.9 |
|---|---|---|---|
| F1 | En part: les pestanyes verticals mostren la carpeta i l'estat de Claude de cada pane, però només dins de Warp | En part: `claude agents --json` (segons la documentació), sense finestres ni pestanyes | En part: llegeix `warp.sqlite` i lliga cada sessió amb el seu pane |
| F2 | En part: desa una launch configuration sense ordres, que s'edita en YAML a mà | En part: la llista d'agent view, que no és cap fitxer per editar | No |
| F3 | En part: ordres fixes; no tria ni reprèn cap conversa | En part: després d'un reinici, una sessió cada vegada | En part: `claude --resume <id>`, només de les que eren vives |
| F4 | En part: `login_item` obre Warp, i la restauració torna les pestanyes sense Claude, sense cap full | No | En part: un LaunchAgent que restaura sense demanar res |
| F5 | En part: un sol interruptor, que es canvia a mà; res no l'activa uns segons per fer una foto | No s'hi aplica | No |

### Conclusió del 03/11/2026

**Cap eina cobreix el cas amb Warp:** llegir les finestres, editar-les, tornar-les a obrir i reprendre cada
conversa de Claude després d'un reinici. Per això fem Warp Launch.

- El més semblant amb Warp és [warp-claude-resume](https://github.com/supersistence/warp-claude-resume) (★2, MIT).
  No obre res: espera que Warp restauri la pestanya i hi ofereix `claude --resume <id>`.
- [cmux](https://github.com/manaflow-ai/cmux) (★28,7k, GPL-3.0) ho fa gairebé tot: restaura la disposició, la
  carpeta i la conversa de Claude. Però vol dir **deixar Warp**.

## Candidats revisats

Les files marcades «07/11» les afegeix la revisió del 07/11/2026. Totes ja existien el 03/11, menys potser Claude
Switchboard (datat el 04/11/2026), però aquella recerca les va passar per alt.

| Eina | ★ | Què fa | Per què no ens serveix |
|---|---|---|---|
| [warp-agent-session-restore](https://github.com/agentsdance/warp-agent-session-restore) (07/11) | 0 | Fa una foto cada 5 s de les sessions de Claude (i de Codex i Droid) que corren a Warp. Un LaunchAgent, quan veu que Warp s'ha tornat a obrir, les reprèn soles amb `claude --resume <id>` i els paràmetres d'abans, en Tab Configs o launch configurations (`restore --dry-run`) | Només reprèn les sessions que eren vives, sovint una minoria de les pestanyes. Sense editor, sense `restore_session` i sense confirmació; deixa les pestanyes que restaura Warp. Escriu hooks a `~/.claude/settings.json` (regla 6). Sense llicència; v0.0.9 del 20/10/2026. No comprovat: llegeix les taules de finestres de `warp.sqlite`, que Warp no escriu amb la restauració desactivada |
| [warp-claude-resume](https://github.com/supersistence/warp-claude-resume) | 2 | Ofereix `--resume` quan Warp restaura la pestanya (zsh) | No obre finestres ni té configuració |
| [zsh-warp-claude-tab](https://github.com/akexorcist/zsh-warp-claude-tab) | 1 | Obre una pestanya amb `warp://tab_config` | Una pestanya; sense reprendre la conversa |
| [Extensió de Warp per a Raycast](https://github.com/raycast/extensions/tree/main/extensions/warp) | – | Obre launch configurations i Tab Configs | No llegeix ni edita; sense Claude |
| [Claude Sessions per a Raycast](https://github.com/raycast/extensions/tree/main/extensions/claude-sessions) (07/11) | – | Obre una sessió de Claude a Warp amb `claude --continue` | Una sessió cada vegada, sense finestres ni configuració; `--continue` pot agafar la conversa d'una altra pestanya (D7) |
| [Terminal Kit d'Alfred](https://github.com/x-o-r-r-o/alfred-terminal-kit) (07/11) | 1 | Obre launch configurations i Tab Configs que ja existeixen, i el fitxer en un editor de text (⌥↩). MIT | No llegeix Warp ni té Claude |
| [claude-code-warp](https://github.com/warpdotdev/claude-code-warp), connector oficial de Warp (07/11) | 237 | Envia els hooks de Claude a Warp (OSC 777): notificacions, estat i `session_id` de cada pane. MIT | No reprèn cap sessió ni desa res per a després d'un reinici |
| [claude-sessions](https://github.com/DenverLifeSciences/claude-sessions) | 0 | Desa cada 5 min amb launchd (com el prototip) | iTerm i tmux, no Warp |
| [ghostty-claude-code-session-restore](https://github.com/AtAFork/ghostty-claude-code-session-restore) | 26 | Restaura amb launchd i AppleScript | Ghostty, i requereix Accessibilitat |
| [cmux](https://github.com/manaflow-ai/cmux) | 28,7k | Terminal amb restauració d'agents | Substitueix Warp |
| [Harp](https://github.com/dominikmartn/harp) (07/11) | 708 | Fork de Warp (AGPL-3.0, creat el 20/10/2026); conserva els grups i l'ordre entre reinicis amb tmux | Substitueix Warp, i no reprèn les converses després d'un reinici |
| [quil](https://github.com/artyomsv/quil) | 27 | Multiplexor amb `claude --resume` per pane | Les pestanyes serien de quil, no de Warp |
| [ccmanager](https://github.com/kbwo/ccmanager), [claude-squad](https://github.com/smtg-ai/claude-squad), [agent-deck](https://github.com/asheshgoplani/agent-deck) | 1,3k / 8,7k / 1,2k | Gestors de sessions sobre tmux o worktrees | No restauren converses després d'un reinici, o no ho documenten |
| [Claude Switchboard](https://github.com/akv2011/claude-switchboard), [claude-session-manager](https://github.com/drewburchfield/claude-session-manager) (07/11) | 2 / 1 | Tornen a obrir sessions de Claude | Switchboard, a pestanyes de VS Code; claude-session-manager només genera ordres per copiar i enganxar |
| Sessions en segon pla de Claude Code ([agent view](https://code.claude.com/docs/en/agent-view.md), `claude --bg`) (07/11) | – | Llista desada de sessions de totes les carpetes, amb el mode de permisos, el model, l'esforç i el nom; aguanta la son i les actualitzacions | No sobreviuen a un reinici: surten «failed» o «stopped» i cal reprendre-les una a una. El supervisor no s'engega en iniciar sessió, i no són pestanyes de Warp |
| [Claude Desktop](https://code.claude.com/docs/en/desktop.md), pestanya Code (07/11) | – | Diverses sessions en paral·lel, cadascuna a la seva carpeta; `claude --desktop --resume <id>` hi porta una sessió del terminal (2.1.285) | Vol dir deixar Warp (el terminal és un panell de Desktop), i la documentació no diu que reprengui les sessions després d'un reinici |
| tmux-resurrect, tmuxinator, tmuxp, Zellij, kitty, WezTerm | – | Restauren disposicions en el seu terminal | No són Warp; la conversa de Claude no es restaura |

Del 03 al 07/11/2026 no hi ha cap commit a warp-claude-resume (l'últim és del 29/10), zsh-warp-claude-tab (13/10),
l'extensió de Warp per a Raycast (19/10) ni warp-agent-session-restore (20/10), i a cmux cap no parla de Warp. Les eines
noves d'aquells dies per restaurar sessions de Claude són d'iTerm o de Windows Terminal (`gh api` i `gh search repos`,
07/11/2026).

## Què ofereix Warp oficialment

Al dia el 07/11/2026, amb el Warp 0.2026.11.04 i el codi de `master` a `abb3fe33`.

- **URI `warp://`** ([documentació](https://docs.warp.dev/terminal/more-features/uri-scheme/)): `action/new_window`, `action/new_tab`,
  `launch/<nom>` i `tab_config/<nom>`. No hi ha cap acció per executar una comanda ni per controlar una
  pestanya oberta: l'URI «does not target or control an already-open tab or pane». Des de la 2026.07.16 (#13103),
  `launch/<nom>` sí que executa les ordres de pestanya de la launch configuration.
- **Launch configurations:** *legacy*, «new features are not being added». «Save New Launch Configuration» desa les
  finestres, les pestanyes, la carpeta, el títol i el color, i des de la 2026.09.16 (#14624) també els grups de pestanyes;
  les ordres, mai (`commands: Vec::new()`, `app/src/launch_configs/launch_config.rs`). S'editen en YAML a mà.
  **Tab Configs:** una pestanya per fitxer; amb clic dret, «Save as new config» en desa la pestanya actual.
- **Restauració de sessió:** «Restore windows, tabs, and panes on startup» (`general.restore_session`, per defecte `true`).
  Torna les finestres, les pestanyes, els panes i els blocks recents, però no els processos: Claude Code no torna. És un
  sol interruptor, sense cap opció per restaurar només algunes pestanyes ni per tornar a engegar els agents
  ([documentació](https://docs.warp.dev/terminal/sessions/session-restoration.md) i `settings_schema.json` de la 0.2026.11.04).
- **Obrir-se en iniciar sessió:** «Start Warp at login (requires macOS 13+)» (`general.login_item`, per defecte `true`).
  Detall a `fets-verificats.md`.
- **Pestanyes verticals:** mostren, per a cada pane, la carpeta, la branca i l'estat de Claude Code, però només dins de
  Warp. No hi ha cap manera documentada de llegir-ho des de fora, i no donen l'id de la sessió.
- **CLI `oz` i `warp`:** són per a agents, i no controlen finestres ni pestanyes. `warp --resume` només reprèn converses
  del Warp Agent, no de Claude Code. Els `claude --resume` del codi i del binari són de les execucions de Claude Code al
  núvol de Warp (Oz), no de les pestanyes locals.
- **Warp Control (`warpctrl`):** només a les versions internes de Warp. El 07/11, igual: la 0.2026.11.04 porta la skill
  `warpctrl` però no l'executable, i `WarpControlCli` continua només a `DOGFOOD_FLAGS`. Detall a `fets-verificats.md`.
- **Remote Control:** publica una sessió de Claude viva per seguir-la des d'un altre dispositiu. No la manté després
  d'un reinici.
- **Novetats del 03 al 07/11/2026: cap que toqui F1 a F5.** La 0.2026.11.04 no té notes de versió (el changelog acaba a
  la 2026.10.22). Dels 58 commits de `master` del 20/10 al 06/11, cap toca la restauració local, les launch
  configurations, els Tab Configs, `warp://` ni `warpctrl`. Els de Claude són dels agents al núvol, llevat de #16723
  (05/11), que treu les ordres d'autenticació de Claude i Codex de la detecció de sessions.

## Què ofereix Claude Code (07/11/2026, 2.1.319)

- **Sessions en segon pla** (agent view, `claude --bg`): després d'un reinici surten «failed», si fa menys de 48 h que
  van avançar, o «stopped», si en fa més, i cal obrir-les o respondre-hi una per una. Segons la documentació,
  `claude respawn --all` només reinicia les «running»; no s'ha comprovat si també les aturades per un reinici. El
  supervisor s'engega «the first time you background a session or open agent view», no en iniciar sessió.
- **Enllaços `claude-cli://open`:** només porten la carpeta i un prompt sense enviar, sense `--resume`, i a macOS obren
  iTerm2, Ghostty, kitty, Alacritty, WezTerm o Terminal.app, no Warp.
- **2.1.318 (03/11) i 2.1.319 (06/11):** cap canvi per restaurar diverses sessions ni cap integració amb Warp.

## Peticions de funcionalitat que cal seguir

Al dia el 07/11/2026 (`gh issue view` i `gh pr view`).

- Warp:
  - [#14960](https://github.com/warpdotdev/warp/issues/14960), restaurar la sessió d'agent CLI d'un pane: oberta, amb
    l'última activitat el 22/10/2026 i sense resposta de Warp des del 25/09/2026.
    - Les PR que la implementaven es van tancar sense fusionar: [#14734](https://github.com/warpdotdev/warp/pull/14734)
      (25/08/2026), [#14956](https://github.com/warpdotdev/warp/pull/14956) (flag `AgentSessionResume`, tancada pel bot
      el 18/09/2026) i [#15973](https://github.com/warpdotdev/warp/pull/15973) (27/09/2026). El Warp 0.2026.11.04 no té
      el flag.
    - Un col·laborador extern té una implementació només per a Claude Code: desa el `session_id` de cada pane amb el
      connector `claude-code-warp` i, en restaurar, hi encua `claude --resume <id>` amb els flags d'abans. Espera
      l'etiqueta `ready-to-spec`.
  - [#9416](https://github.com/warpdotdev/warp/issues/9416): el 29/07/2026, un membre de Warp (l'assignat a #14960; no consta com a membre públic de
    l'organització) hi veu possible executar
    l'ordre de represa de cada agent («most agent CLIs support a command for resuming a conversation, and we could run
    that for the user»), sense comprometre-s'hi. Conservar els processos vius en reiniciar, en canvi, no ho veu factible.
  - [#3910](https://github.com/warpdotdev/warp/issues/3910), les pestanyes perden la carpeta en reiniciar
    (oberta des del 2023, `ready-to-implement`). Sense canvis des del 03/11.
  - [#2693](https://github.com/warpdotdev/warp/issues/2693), executar comandes en arrencar (oberta). Sense canvis des del 03/11.
  - [#15527](https://github.com/warpdotdev/warp/issues/15527), sincronitzar el nom de la sessió de Claude amb
    el títol de la pestanya (oberta, `ready-to-implement`). Sense canvis des del 03/11.
  - [#16757](https://github.com/warpdotdev/warp/issues/16757) (06/11/2026, oberta): mantenir la sessió d'agent CLI
    després de Ctrl+Z i `fg`. No toca la represa després d'un reinici.
- Claude Code:
  - [#43262](https://github.com/anthropics/claude-code/issues/43262), desar i restaurar un espai de treball amb diverses
    sessions: la va tancar el bot per inactivitat el 13/05/2026 (*not planned*), i després es va bloquejar. No es va
    tancar el 03/11/2026 (corregit el 07/11/2026). Cap issue nova la substitueix.
  - Relacionades, tancades *not planned*: [#48799](https://github.com/anthropics/claude-code/issues/48799) (persistència
    de sessions d'agent, 25/05/2026), [#91085](https://github.com/anthropics/claude-code/issues/91085) («Deep links
    cannot open Warp», 04/11/2026) i [#91525](https://github.com/anthropics/claude-code/issues/91525) (Desktop: un
    projecte amb diverses carpetes, 07/11/2026).

## Idees aprofitables

- `claude agents --json`: segons la documentació, és la manera suportada de llegir l'estat de les sessions
  des de fora (`cwd`, `kind`, `pid`, `sessionId` i `name` de totes les sessions vives). Cal provar-lo amb OK, perquè pot
  engegar el supervisor.
- `WARP_TERMINAL_SESSION_UUID` i `WARP_FOCUS_URL`: lliguen el procés de Claude amb el pane, i permeten
  enfocar una pestanya oberta en lloc de duplicar-la.
- Hook `SessionStart` de Claude Code: dona el `session_id` a l'instant. És el que fan servir
  warp-claude-resume, quil i cmux.
  - L'única manera de fer-lo servir sense tocar `~/.claude` és injectar-lo en cada llançament amb
    `--settings` (cal verificar-ho). No s'ha d'escriure a `~/.claude/settings.json`.
