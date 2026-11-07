# Especificació — Warp Launch

## Visió

En iniciar sessió al Mac, en David recupera el seu espai de treball sense fer res: les mateixes finestres de
Warp, les mateixes pestanyes a les mateixes carpetes i, a cada pestanya, **la mateixa conversa de Claude
Code** on la va deixar. Com s'organitza tot això ho decideix ell des d'una app, sense haver de recordar
cap configuració.

## Requisits (en David, 03/11/2026)

Per a en David, **una finestra de Warp és un grup de sessions** (pestanyes). No s'ha de confondre amb els
*tab groups* de Warp.

| # | Requisit | Fase |
|---|---|---|
| R1 | Llegir la configuració actual de Warp: finestres, pestanyes de cada finestra, nom de cada pestanya, carpeta i comanda amb què s'ha iniciat Claude Code | 1 |
| R2 | Que la configuració inicial de l'app surti d'aquesta lectura | 1–2 |
| R3 | Editor: crear, editar i esborrar finestres i pestanyes (nombre de finestres i de sessions per finestra). Arrossegar pestanyes d'una finestra a una altra. *Proposta:* també reordenar-les dins de la mateixa finestra | 2 |
| R4 | Per pestanya: carpeta d'inici, model, esforç, ultracode sí/no, continuar la conversa (**activat per defecte**) i nom fix de la sessió. *Proposta:* també «Claude sí/no», per a pestanyes que només són terminal | 2 |
| R5 | Obrir totes les finestres i pestanyes, cadascuna amb la seva sessió de Claude activa | 3 |
| R6 | Arrencar sola en iniciar sessió al Mac, sense intervenció. Què obre i si demana confirmació es decideix a D3 | 3 |
| R7 | Substituir la restauració pròpia de Warp, que s'ha de desactivar perquè no dupliqui pestanyes | 3 |
| R8 | Fer servir el CLI de Warp. Avui no n'hi ha cap que ho permeti: vegeu D10 | 1–3 |
| R9 | No duplicar mai una pestanya o sessió que ja està oberta | 3 |
| R10 | No sobrecarregar el Mac en obrir desenes de sessions (uns 500 MB cadascuna: 64 sessions són uns 32 GB) | 3 |
| R11 | Instal·lada a Aplicacions (`/Applications`), perquè surti a Apps com qualsevol altra app | 2 |
| R12 | Obrir a mà, des de l'editor, una finestra amb totes les seves pestanyes i les seves sessions de Claude | 3 |

## Decisions preses (en David)

| Data | Decisió |
|---|---|
| 03/11/2026 | **Nom:** Warp Launch. Comanda `warp-launch`, identificador `cat.davide.warp-launch` |
| 03/11/2026 | **Interfície:** app nativa SwiftUI |
| 03/11/2026 | **Format de configuració:** JSON (sense dependències), amb camp de versió |
| 03/11/2026 | **Ultracode:** interruptor independent de l'esforç. Exemple: `--effort high --settings '{"ultracode":true}'`. Només funciona amb models que l'admeten i amb els dynamic workflows activats; l'editor n'ha d'avisar |
| 03/11/2026 | **Configuració inicial:** es llegeix de Warp (finestres i pestanyes obertes) i de les sessions de Claude vives |
| 03/11/2026 | **Prototip `espai`:** desinstal·lat. L'app no pot dependre de res creat abans fora del repo, i tot el que es va fer abans s'ha de revisar |
| 03/11/2026 | **Proves de llançament:** amb finestres i sessions reals, pas a pas, i amb OK per a cada prova |
| 03/11/2026 | **Ordre:** lectura → editor → llançaments |
| 03/11/2026 | **Configuració de l'app (D8):** a `~/.config/warp-launch/` |
| 03/11/2026 | **Disseny de l'editor (D14):** les normes de la skill `mac-design` de BAMA (MIT), copiades al repo sense els passos que instal·len, obren o tanquen l'app |
| 03/11/2026 | **Carpeta arreglada d'una pestanya sense Claude:** Claude no s'activa sol; l'editor mostra un botó «Activa Claude» |
| 03/11/2026 | **Icona:** finestres en cascada (la del davant blanca, les del darrere translúcides) sobre fons índigo |
| 03/11/2026 | **Pestanyes sense Claude a la configuració inicial (D11):** s'hi activa Claude amb les opcions habituals (`--dangerously-skip-permissions`, ultracode i continuar). Les que són a `~` o a una carpeta que ja no existeix queden sense Claude fins que se n'arregli la carpeta. Les que ja tenen Claude conserven la comanda llegida. El mode de permisos és un camp de cada pestanya, que es pot canviar a l'editor |
| 07/11/2026 | **Plantilla de les configuracions noves (D11, revisada per en David):** per a una configuració nova (sense fitxer), la plantilla d'importar és la segura (`.perOmissio`): `claude` continuant la conversa, sense saltar els permisos ni ultracode. Les opcions es trien per pestanya (inspector) i a la plantilla (Configuració › «Pestanyes noves»). La configuració que ja existeix conserva la seva plantilla. Substitueix les «opcions habituals» de la decisió de dalt (0.28.0) |
| 04/11/2026 | **Com s'obre una finestra (D5):** amb una launch configuration temporal. Per obrir-la, l'app escriu un fitxer seu (`warp-launch-…yaml`, amb marca) a `~/.warp/launch_configurations/`, demana a Warp que l'obri (`warp://launch/<nom>`) i l'esborra. No en queda res a ⌃⌘L |
| 04/11/2026 | **Què vol dir «continuar» (D7):** cada pestanya reprèn la seva conversa exacta (`--resume <id>`). L'app recorda quina conversa té cada pestanya; si no ho sap, en comença una de nova (mai `--continue`, que podria agafar la d'una altra pestanya) |
| 05/11/2026 | **Els agents engeguen les feines en bypass (en David):** «Cal afegir-ho a l'app que els agents engeguin amb `--permission-mode bypassPermissions`». Les pestanyes en bypass fan que les feines noves del seu agent el portin; les que ja existeixen es desperten sense, per no fer còpies (`docs/disseny.md`, «Les feines de l'agent»). |
| 05/11/2026 | **Quina conversa es reprèn (D7, revisada):** sempre la més recent de la carpeta de la pestanya, amb `--resume <id>`, si no és viva ni la darrera d'una altra pestanya. Si no n'hi ha cap, la recordada; si tampoc, una de nova. Només compten les converses escrites al terminal (ni `claude -p`, ni Claude Desktop, ni les feines en segon pla) on Claude ha respost, i la més recent és la de l'últim missatge al terminal (0.22.2). Mai `--continue`, que no mira res d'això. Substitueix la decisió de sota |
| 04/11/2026 | **L'ordre que es mostra (D15):** fora `--continue` a l'inspector, «Copia l'ordre», la Configuració i el CLI. L'inspector diu a part quina conversa es reprendrà («reprèn 1b2c3d4e» o «nova»), i «Copia l'ordre» hi posa `--resume <id>` si el sap |
| 04/11/2026 | **Historial (D16):** les ordres que l'app fa escriure a Warp comencen amb un espai, perquè zsh no les desi (Warp obre zsh amb `HIST_IGNORE_SPACE`). Es comprova a la prova L2 |
| 04/11/2026 | **CLI (D17):** `warp-launch obre <finestra>` per defecte només mostra què obriria (mode de prova, regla 4). Amb una opció explícita, també obre la finestra; Claude no la fa servir mai sense l'OK d'en David. **05/11/2026:** amb l'app oberta, no fa res; si Warp és tancat, l'obre |
| 04/11/2026 | **Lectura periòdica (D18):** mentre l'app és en marxa, cada 60 s mira quina conversa té cada pestanya i ho desa a `estat.json` si ha canviat |
| 04/11/2026 | **Finestra ja oberta en part (D13):** abans diu quines pestanyes ja són obertes, i obre una finestra nova només amb les que falten |
| 03/11/2026 | **Elements gràfics:** la icona de l'app es genera amb nano-banana (API de Gemini), amb la skill `app-icon` de BAMA adaptada al repo (`.claude/skills/app-icon/`). La icona de la barra de menú i els botons de l'editor són SF Symbols. **06/11/2026:** la icona de l'app es dibuixa amb codi (`scripts/icona-dibuixa.swift`), perquè nano-banana no tenia crèdit |

## Propostes tècniques (pendents de l'OK d'en David)

- **App de barra de menú, amb una finestra d'edició.**
  - Si s'obre des d'Apps o del Finder, mostra l'editor. Si no, només sortiria la icona de la barra de menú i
    semblaria que l'app no s'ha obert.
  - Mentre l'editor és obert, l'app surt al Dock i a ⌘⇥. Quan es tanca, només queda a la barra de menú.
  - Icona pròpia, perquè surti bé a Apps. Es pot fer amb `iconutil`, que ja és al sistema.
- **macOS 26 o posterior.**
- **Construcció:**
  - SwiftPM, amb el core, l'app i la CLI separats.
  - Proves amb `swift-testing` (`scripts/test.sh`).
  - `scripts/build-app.sh` empaqueta el `.app`, signat ad hoc (des del 04/11/2026, amb el certificat «Warp Launch Dev», D12).
- **VERSION 0.1.0** per a l'esquelet de Warp Launch. Tindrà un versionat nou, separat del del prototip.

## Decisions obertes (les pren en David; porta-hi una recomanació)

- **D3. Arrencada en iniciar sessió. Decidit per en David (06/11/2026): el full, i un clic.** En iniciar sessió, l'app s'obre
  sola i mostra el full de «Obre-ho tot a Warp…» amb les finestres que falten, totes marcades; no obre res fins que s'hi fa
  clic. Descartats: obrir-ho tot sense preguntar (fins a 62 Claude sols a cada inici de sessió) i només una notificació.
  - Warp pot obrir-se sol en iniciar sessió, o no (el 06/11/2026 en David treu Warp dels ítems d'inici de macOS, però al
    reinici Warp s'obre igualment; el 07/11/2026 diu que l'opció de Warp sempre ha estat desactivada: no se sap qui l'obre, `fets-verificats.md`). L'app no l'espera: el
    full surt de seguida i, amb Warp tancat, diu que l'obrirà amb el clic (0.27.2).
  - S'activa amb un interruptor a la Configuració (regla 3). `docs/disseny.md`, secció 9 (0.27.0).
- **D4. Obertura escalonada. Decidit per en David (05/11/2026): totes de cop,** sense tandes ni pauses («Obre-ho tot», 0.25.0).
  Si una finestra no s'obre o no es reconeix, les altres continuen, i el resultat ho diu al final. Al full, una casella per
  finestra, totes marcades. Risc acceptat: fins a 62 Claude alhora (uns 31 GB), i les pestanyes només de terminal de finestres
  diferents a la mateixa carpeta es poden confondre.
- **D6. Què fer amb el que hi ha a Warp.**
  - Les 7 `espai-*.yaml` del prototip continuen sortint a ⌃⌘L, però estan trencades, perquè criden `espai`, que
    ja no hi és. També hi ha 21 launch configurations antigues i 21 Tab Configs fets a mà (més `startup_config.toml`).
  - **La restauració de Warp (`general.restore_session`): decidit per en David el 05/11/2026, desactivada a mà**, perquè
    «aquesta app substitueix la funcionalitat que he desactivat».
    - Se sincronitza al núvol: afecta totes les instal·lacions de Warp del compte.
    - Conseqüència: Warp ja no desa les finestres a `warp.sqlite` (fets-verificats), i l'app sap què hi ha obert pels
      processos. No en veu les finestres ni els títols; per importar i lligar, des de la 0.23.0 en fa una foto (D19).
    - Conseqüència: **una pestanya feta a mà a Warp que no sigui a la configuració no torna mai.** Queda obert com
      resoldre-ho (per exemple, que l'app avisi de les sessions de Claude vives que no són a la configuració).
    - **Es pot activar una estona (en David, 05/11/2026):** per llegir les finestres i els títols de Warp i tornar-la a
      desactivar. Claude ho pot fer amb `scripts/warp-restauracio.sh` i l'OK d'en David per a cada vegada (regla 7).
- **D19. Que l'app gestioni `restore_session` sola (en David, 05/11/2026).** «Amb l'aplicació en marxa, aquest ajustatge per
  defecte deshabilitat. Amb l'aplicació parada aquest ajustatge per defecte habilitat. L'aplicació l'habilita i el deshabilita
  per actualitzar de forma periodica la informació.» Fets a `fets-verificats.md`. Fet a la 0.23.0, amb la regla 7 ampliada (OK d'en David, 05/11/2026). Decidit:
  - **Quan l'app s'atura (decidit per en David, 05/11/2026): sempre desactivat,** també amb «Surt» i en apagar el Mac; només l'activen els
    refrescos de l'app. Canvia la frase inicial («amb l'aplicació parada, habilitat»), perquè si no Warp restauraria les finestres sense Claude.
    Si en David deixa de fer servir l'app, Warp queda sense restauració fins que l'activi a mà.
  - **Cada quant: només quan en David ho demana (en David, 06/11/2026, 0.27.3).** Abans (05/11/2026), cada 5 minuts. En reiniciar el
    Mac el 06/11/2026, Warp va restaurar la foto sol (6 finestres, 62 pestanyes, sense Claude): ara només es refresca amb «Torna a llegir
    Warp», importar i lligar. Història: «cada 5 minuts», activat fins que Warp desi i com a màxim 30 s. Warp només desa si passa alguna cosa, i cada canvi va al núvol. A la
    prova de 60 s, va desar en menys de 5 s (`fets-verificats.md`).
  - **Què se'n fa (en David, 05/11/2026): «només guardar-ho, per si un dia la vull importar. La funció tornar a llegir Warp llegeix d'aquesta informació si Warp està parat, i
    llegeix de Warp si Warp està en marxa».** No s'ensenya sola, i obrir finestres no en depèn. Importar i lligar la fan servir igual.
  - **Activat a mà amb l'app en marxa (en David, 05/11/2026):** l'app el torna a desactivar en 60 s, cosa que també cobreix un valor antic del núvol de Warp.
  - **Si Warp no desa en 30 s (criteri de Claude, a revisar si cal):** la lectura es mostra amb un avís que diu quantes pestanyes i terminals hi ha, i en David decideix.
  - **Altres instal·lacions de Warp (en David, 05/11/2026): cap, només aquest Mac.** Settings Sync no hi porta res a cap altre ordinador.
- **D20. Un nom fix per a cada sessió (`--name`).** El nom d'una sessió, que és la seva adreça, canvia a cada arrencada, i un agent que
  recordi el d'abans no arriba. L'opció ja existeix a la configuració (`nom`), i cap de les 62 pestanyes no la fa servir. Recomanació:
  sí, amb el nom de la carpeta, però després de provar-ho en una pestanya. Fins ara, poques fallades: 1 al novembre.
- **D9. Més control per pestanya.** Splits i panes, `--remote-control <nom>`, comandes prèvies, color.
- **D10. Com fem servir «el CLI de Warp»** (R8). Cap CLI de Warp no llista ni obre pestanyes: `oz` no ho fa,
  i `warpctrl` només és a les versions internes de Warp i no executa comandes (vegeu `fets-verificats.md`).
  - Recomanació: mentre no hi sigui, llegir els processos, o `warp.sqlite` (en només lectura) si Warp restaura la sessió, i
    obrir amb `warp://` (launch configurations).
  - Tornar-ho a mirar quan `warpctrl` arribi a Stable.
- **D12. Signatura i permís per llegir Warp.** A la prova 1 (04/11/2026), macOS 27 **va bloquejar** la lectura
  de les dades de Warp **sense preguntar**, i només va mostrar la notificació «Accés a les dades bloquejat»
  (fets-verificats, «Prova 1 de l'app»). El CLI hi pot llegir perquè macOS l'atribueix a Warp.
  - Opcions:
    1. **Permís només per a les dades de Warp:** a Configuració del Sistema › Privacitat i seguretat › Arxius i
       carpetes, activar l'accés de Warp Launch a les dades de Warp. Que hi surti l'interruptor no està verificat.
    2. **Accés complet al disc** per a Warp Launch: funciona segur, però l'app podria llegir tot el disc.
    3. **Certificat de signatura propi** (autosignat, al clauer d'en David, creat amb Accés a Claus): no fa res
       sol, però fa que el permís de l'opció 1 o la 2 no es perdi a cada compilació. Amb la signatura ad hoc,
       cada compilació és una app nova per a macOS i caldria tornar a donar el permís cada vegada.
  - Recomanació: la 3 i, un cop, la 1 (la 2 només si l'interruptor de la 1 no hi és). Es desfà esborrant el
    certificat a Accés a Claus, desactivant el permís i tornant `build-app.sh` a la signatura ad hoc.
  - **Decidit (en David, 04/11/2026): la 3 i la 1.** `scripts/build-app.sh` signa amb «Warp Launch Dev» si és al
    clauer (o amb `WARP_LAUNCH_IDENTITAT`), i si no, ad hoc amb un avís.

## Fases

1. **Lectura** (R1, R2, R8). **Feta: versió 0.2.0, 03/11/2026.** El resultat de la primera lectura real és a
   `fets-verificats.md`. La configuració inicial (R2) es crearà a partir d'aquesta lectura a la fase 2.
   - **Model de dades** a `WarpLaunchCore`, amb l'ordre `warp-launch llegeix [--json]`. Llegeix sempre en
     només lectura.
   - **Fonts:**
     - `warp.sqlite`: `windows`; `tabs` (títol i color); `pane_nodes` i `pane_leaves` (només
       `kind = 'terminal'`); `terminal_panes` (`uuid` i `cwd`); i `blocks.pwd`, de reserva quan el `cwd` és HOME.
       Els `id` de finestres i pestanyes canvien cada vegada que Warp desa: la clau és l'`uuid` del pane.
     - Sessions de Claude vives: `~/.claude/sessions/*.json`, més l'`argv` i l'entorn de cada procés.
       `WARP_TERMINAL_SESSION_UUID` lliga **només les sessions interactives** amb el seu pane; les `bg` hereten
       el del dimoni.
   - **Rutes:** abans de comparar-les, cal canonicalitzar-les totes (majúscules i symlinks).
2. **Editor** (R3, R4, R11).
   - Finestra SwiftUI per editar la configuració JSON, que es crea a partir de la lectura.
   - S'hi poden arrossegar pestanyes d'una finestra a una altra.
   - L'app s'instal·la a Aplicacions, amb l'OK d'en David. Per desinstal·lar-la cal desactivar l'interruptor de l'inici de
     sessió (0.27.0), esborrar-la, i també
     `~/.config/warp-launch/` i les preferències (llista completa a `disseny.md`).
   - **Disseny i passos: `docs/disseny.md`** (03/11/2026).
   - **Feta el 06/11/2026:** passos 1 a 12 (la icona, a la 0.26.1) i prova 8 (0.26.0); en David dona per bona la icona.
     L'app és a `/Applications` des de la 0.27.0.
3. **Llançaments** (R5–R7, R9, R10, R12). Es fa pas a pas, amb proves reals i l'OK d'en David a cada pas.
   1. Obrir a mà una finestra des de l'editor (R12). **Passos fets (0.15.0 a 0.24.0, 04 i 05/11/2026);** falten proves reals
      (L2, L5 i la del CLI `--obre`) i l'OK d'en David. Pla, passos i proves (L1 a L5) a `docs/disseny.md`, secció 7.
   2. Obrir tota la configuració. **Feta: 0.25.0 (D4), provada el 06/11/2026 amb la 0.26.0.** `docs/disseny.md`, secció 8.
   3. Arrencar sola en iniciar sessió, i substituir la restauració de Warp. **0.27.0 (D3), ara 0.27.3:** la restauració la gestiona
      l'app (D6, D19). **R7 encara no està comprovat:** al primer reinici (06/11/2026), Warp es va obrir sol i va restaurar 62
      pestanyes sense Claude, tot i que `settings.toml` deia `false`. Es mira al pròxim reinici, amb la 0.27.3. `docs/disseny.md`, secció 9.

## Pendents

- **Revisar tot el que es va fer abans:**
  - el codi i les proves del prototip (`prototip/`);
  - els fets marcats «(prototip)» a `fets-verificats.md`;
  - les configuracions de Warp que va generar.
- **Preguntes tècniques de la fase 1:**
  - Confirmar que l'`uuid` d'un pane es manté després d'un reinici (hi ha indicis forts). El reinici l'ha de
    fer en David.
  - Si `claude agents --json`, que la documentació presenta com la manera suportada de llegir l'estat de les
    sessions, és millor font que `~/.claude/sessions/`. Cal OK per provar-ho.
  - Si `claude --resume <id>` funciona des d'una altra carpeta. La documentació diu que sí; el prototip va
    veure que avisava.
  - Quins models admeten ultracode, perquè l'editor ho pugui validar.
  - ~~Si llegir el Group Container de Warp des de l'app fa sortir un avís de permisos de macOS.~~ **Resolt (04/11/2026):**
    no pregunta. macOS 27 denega l'accés i avisa un sol cop («Accés a les dades bloquejat», amb «Gestiona»); el permís es dona
    a mà a Privacitat i seguretat › Arxius i carpetes › Warp Launch.app (`fets-verificats.md`).
- **`--session-id <uuid>`:** permet crear una sessió nova amb un identificador triat per l'app. Pot ser la
  manera d'associar pestanya i conversa sense desar l'estat periòdicament.
- **Hook `SessionStart`:** dona el `session_id` a l'instant. Només es podria fer servir injectant-lo en cada
  llançament amb `--settings` (cal verificar-ho), mai escrivint a `~/.claude/settings.json`.
- **Pestanya d'un agent remot:** no té carpeta local (l'agent corre en un altre servidor). Potser ha de ser una pestanya amb `ssh`.
