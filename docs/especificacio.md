# Especificació — Warp Launch

## Visió

En iniciar sessió al Mac, l'usuari recupera el seu espai de treball sense fer res: les mateixes finestres de
Warp, les mateixes pestanyes a les mateixes carpetes i, a cada pestanya, **la mateixa conversa de Claude
Code** on la va deixar. Com s'organitza tot això es decideix des d'una app, sense haver de recordar
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
| R10 | No sobrecarregar el Mac en obrir desenes de sessions (uns 500 MB cadascuna: 60 sessions són uns 30 GB) | 3 |
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
| 03/11/2026 | **Pestanyes sense Claude a la configuració inicial (D11):** s'hi activa Claude amb la plantilla `.habituals` (`--dangerously-skip-permissions`, ultracode i continuar). Les que són a `~` o a una carpeta que ja no existeix queden sense Claude fins que se n'arregli la carpeta. Les que ja tenen Claude conserven la comanda llegida. El mode de permisos és un camp de cada pestanya, que es pot canviar a l'editor. **Des de la 0.29.1, només en tornar a importar:** en una configuració nova, les pestanyes sense Claude queden només terminal (decisió 5 del 07/11/2026). **Des de la 0.30.3,** una configuració que encara no té cap pestanya també compta com a nova (decisió 9 de la fila del 08/11/2026). **Des de la 0.31.5, sempre:** també en tornar a importar (en David, 09/11/2026) |
| 07/11/2026 | **Plantilla de les configuracions noves (D11, revisada per en David):** per a una configuració nova (sense fitxer), la plantilla d'importar és la segura (`.perOmissio`): `claude` continuant la conversa, sense saltar els permisos ni ultracode. Les opcions es trien per pestanya (inspector) i a la plantilla (Configuració › «Pestanyes noves»). La configuració que ja existeix conserva la seva plantilla. Substitueix la plantilla `.habituals` de la decisió de dalt (0.28.0) |
| 09/11/2026 | **Cinc decisions de la 0.31.5 (en David).** <br>1. Si Warp i Claude no coincideixen en la carpeta d'una pestanya i Claude és viu, mana la de Claude, excepte si és `~` o no existeix. Avís a «Per revisar». «Lliga amb Warp…» compara totes dues carpetes. <br>2. Tornar a importar: les pestanyes sense Claude viu queden sempre «Només terminal» (revisa D11). <br>3. L'app crea `~/.warp/launch_configurations` en fer «Obre» si no hi és (regla 7): només aquesta carpeta i un sol nivell, res si el camí és un enllaç o un fitxer, i només amb la carpeta de debò i el permís. <br>4. Avís als fulls d'obrir i al README: tancar Warp pot deixar a mitges les feines en segon pla de Claude, i reobrir les pestanyes no les fa continuar. <br>5. Si Warp és a `~` i Claude és viu en una carpeta que ja no existeix, la pestanya es queda a `~` amb Claude desactivat i les opcions de la seva ordre, com les altres de `~` (precisa D11: «les que ja tenen Claude conserven la comanda llegida»): la conserven, però no s'engega a `~` |
| 04/11/2026 | **Com s'obre una finestra (D5):** amb una launch configuration temporal. Per obrir-la, l'app escriu un fitxer seu (`warp-launch-…yaml`, amb marca) a `~/.warp/launch_configurations/`, demana a Warp que l'obri (`warp://launch/<nom>`) i l'esborra. No en queda res a ⌃⌘L |
| 04/11/2026 | **Què vol dir «continuar» (D7):** cada pestanya reprèn la seva conversa exacta (`--resume <id>`). L'app recorda quina conversa té cada pestanya; si no ho sap, en comença una de nova (mai `--continue`, que podria agafar la d'una altra pestanya) |
| 05/11/2026 | **Els agents engeguen les feines en bypass (en David):** «Cal afegir-ho a l'app que els agents engeguin amb `--permission-mode bypassPermissions`». Les pestanyes en bypass fan que les feines noves del seu agent el portin; les que ja existeixen es desperten sense, per no fer còpies (`docs/disseny.md`, «Les feines de l'agent»). |
| 05/11/2026 | **Quina conversa es reprèn (D7, revisada):** sempre la més recent de la carpeta de la pestanya, amb `--resume <id>`, si no és viva ni la darrera d'una altra pestanya. Si no n'hi ha cap, la recordada; si tampoc, una de nova. Només compten les converses escrites al terminal (ni `claude -p`, ni Claude Desktop, ni les feines en segon pla) on Claude ha respost, i la més recent és la de l'últim missatge al terminal (0.22.2). Mai `--continue`, que no mira res d'això. Substitueix la decisió de sota |
| 04/11/2026 | **L'ordre que es mostra (D15):** fora `--continue` a l'inspector, «Copia l'ordre», la Configuració i el CLI. L'inspector diu a part quina conversa es reprendrà («reprèn 1b2c3d4e» o «nova»), i «Copia l'ordre» hi posa `--resume <id>` si el sap |
| 04/11/2026 | **Historial (D16):** les ordres que l'app fa escriure a Warp comencen amb un espai, perquè zsh no les desi (Warp obre zsh amb `HIST_IGNORE_SPACE`). Es comprova a la prova L2 |
| 04/11/2026 | **CLI (D17):** `warp-launch obre <finestra>` per defecte només mostra què obriria (mode de prova, regla 4). Amb una opció explícita, també obre la finestra; Claude no la fa servir mai sense l'OK d'en David. **05/11/2026:** amb l'app oberta, no fa res; si Warp és tancat, l'obre |
| 04/11/2026 | **Lectura periòdica (D18):** mentre l'app és en marxa, cada 60 s mira quina conversa té cada pestanya i ho desa a `estat.json` si ha canviat |
| 04/11/2026 | **Finestra ja oberta en part (D13):** abans diu quines pestanyes ja són obertes, i obre una finestra nova només amb les que falten |
| 07/11/2026 | **Per a altres usuaris (en David, 07/11/2026).** Vuit decisions per fer que l'app la pugui fer servir qualsevol: <br>1. **Signatura:** Developer ID d'Apple i notarització, en lloc de «Warp Launch Dev». Als Macs que ja la tenen instal·lada, el permís d'Arxius i carpetes i l'inici de sessió es tornen a activar un cop. <br>2. **Nom:** es manté «Warp Launch», amb l'avís de no afiliació. <br>3. **Idioma:** anglès i català, i els que porti Warp de sèrie (el 07/11/2026, la 0.2026.11.04 només ve en anglès: sense `.lproj` ni `CFBundleLocalizations`). Per defecte, el del sistema; a la Configuració es pot triar «el del sistema» o un idioma concret. El fitxer de configuració, el CLI, els documents i els commits no canvien. <br>4. **Restauració de Warp (D19):** igual per a tothom, però **amb el permís previ de l'usuari**. El primer cop, l'app explica per què ha de desactivar `restore_session` (i que Settings Sync ho porta als altres Macs). Si no hi està d'acord, l'app no es pot fer servir. <br>5. **Pestanyes sense Claude en importar** (configuració nova): només terminal, en lloc d'obrir-hi Claude. Les altres tres propostes (feines `--bg` sense bypass, bloquejar «Obre-ho tot» si no reconeix cap pestanya, avís de memòria), no. <br>6. **Actualitzacions amb Sparkle:** és la primera dependència externa, acordada per la regla 10. Serà la primera connexió a internet de l'app. <br>7. **Abast:** només Claude Code i Warp Stable. <br>8. **Excepcions limitades a la prova de guarda:** obrir la pàgina del permís a Configuració del Sistema, la xarxa de Sparkle i trobar Warp fora d'`/Applications`. Cadascuna en un sol fitxer, amb les adreces en una llista fixa, i una prova que demostri que fallen a qualsevol altre lloc. <br>També: es presenta com a «restaurar Warp i Claude després d'un reinici», i `prototip/` surt del repo. <br>**Fet (07/11/2026, sense provar a l'app):** la 4 a la 0.29.0; la 5 a la 0.29.1; trobar Warp fora d'`/Applications` (de la 8) i avisar de Warp Preview (de la 7) a la 0.29.2 i la 0.29.3; `prototip/` fora del repo (a l'historial, 114c97d); i, a més, un diagnòstic de només lectura (0.30.0). Detall, proves i el que queda per decidir: `docs/disseny.md`, secció 10. <br>**Precisades a la fila del 08/11/2026:** la 3, per la decisió 7 (al llançament, anglès i català), i la 4, per la decisió 1 (qui ja tenia configuració no veu la pantalla). **I a la de la ronda 4:** la 4, per la decisió A (el permís també cobreix afegir la línia si no hi és, i la pantalla ho diu). <br>**La 6 i la part de Sparkle de la 8 són al codi des de la 0.32.0, sense publicar i sense haver-les vist funcionar** (fila del 09/11/2026). De la 8, Sparkle no ha necessitat cap excepció de xarxa: a `Sources/` no n'hi ha cap crida, i un sol fitxer importa Sparkle. La pàgina del permís, encara no |
| 08/11/2026 | **Per a altres usuaris, el que quedava per decidir (en David: de l'1 al 7, rondes 1 i 2, 07/11/2026; del 8 al 12, ronda 3, 08/11/2026).** El codi les cita pel número («decisió 3», desinstal·lar; «decisió 4», les dues còpies): no són les vuit de la fila del 07/11/2026. <br>1. **Permís de la restauració, només als nous:** qui ja tenia configuració (`migrat`) no veu la pantalla. Com ja feia la 0.29.0. <br>2. **A la pantalla del permís, Retorn accepta** («Accepta», botó per defecte). Escapada no fa res, perquè «Surt de Warp Launch» tanca l'app. **0.30.3.** <br>3. **Desinstal·lar:** Configuració › General › «Restaura Warp i surt…» treu l'app dels ítems d'inici, torna `restore_session` com era (activat, el de sèrie, si no se sap), retira el permís i surt; el README explica com desinstal·lar-la. **0.31.0.** Substitueix el «Warp queda sense restauració fins que l'activi a mà» de D19. <br>4. **Dues còpies de Warp Stable, arreglat abans de convidar ningú:** compta el Warp obert, reconegut pels processos. **0.31.1**, amb el cas sense cap Warp: ho diu i no proposa obrir res. <br>5. **Warp Preview obert i Stable tancat:** no s'obre res, com ja feia la 0.29.2. <br>6. **L'historial del repo públic es queda com és.** <br>7. **Idiomes del llançament: anglès i català.** Per fer. <br>8. **Tancar la Configuració amb la pantalla del permís fa sortir de l'app,** com tancar l'editor. **0.30.3.** <br>9. **«Comença en blanc» i després «Torna a importar-ho tot de Warp»:** una configuració sense cap pestanya s'importa com una de nova (les pestanyes sense Claude, només terminal). **0.30.3**, també al CLI. <br>10. **Importar amb Warp tancat i sense configuració:** totes només terminal, com ja feia la 0.29.1. <br>11. **La Configuració, de mida fixa per pestanya,** com a macOS: com ja feia la 0.30.2. <br>12. **A «Pestanyes noves», la secció que es diu igual perd el títol.** **0.30.3.** <br>A més, a la 0.30.3, tres textos que enganyaven (el full d'importar i el diagnòstic amb una carpeta de prova, i la versió de Claude Code al diagnòstic). **Res de la 0.30.3 a la 0.31.1 no s'ha vist a l'app.** Detall: `docs/disseny.md`, secció 10. <br>**Precisada a la fila de la ronda 4 (08/11/2026):** la 3, per la decisió A (si no hi havia la línia, en desinstal·lar hi queda `restore_session = true`) |
| 08/11/2026 | **Per a altres usuaris, ronda 4 (en David, 08/11/2026).** El codi la cita per la lletra («decisió A»). <br>A. **Sense la línia `restore_session`, l'app l'afegeix.** Warp només escriu els ajustos que s'han canviat, i de sèrie l'ajust val `true`: on ningú no l'ha canviat mai, `settings.toml` no té la línia (deduït, no vist per a aquest ajust: `fets-verificats.md`). Fins a la 0.31.1, l'app ho refusava, i no podia fer D19 a cap usuari nou. Ara, amb el permís acceptat (o migrat) i la configuració de debò, hi afegeix `restore_session = false` a `[general]`; si no hi ha la taula `[general]`, l'afegeix; si no hi ha el fitxer, el crea només amb això. La carpeta de Warp (`~/.warp`), no la crea mai. És la mateixa excepció de la regla 7 (D19), escrivint la línia en lloc de canviar-la. Desinstal·lar la deixa a `true`, com ve de sèrie. Més endavant es comprovarà amb un usuari de macOS nou què escriu un Warp net. **0.31.2.** **Precisada per la ronda 5 (fila següent):** el fitxer nou, només amb Warp obert. <br>B. **Quatre decisions petites, totes com ja feia l'app:** <br>1. Un Warp obert des de la Paperera no compta (0.29.3 i 0.31.1). <br>2. `retirat` va a `preferencies.json` sense canviar-ne la versió (1) (0.31.0). <br>3. Si algú esborra només `preferencies.json` i deixa `configuracio.json`, la migració el torna a donar per acceptat (0.29.0; el README diu d'esborrar tota la carpeta). <br>4. Una configuració amb només finestres buides compta com a «sense pestanyes» (0.30.3). <br>A més, a la 0.31.2, dos textos amb una carpeta de prova: «Lliga amb Warp…» diu per què no hi ha finestres, i sense cap Warp l'app diu que no n'hi ha (abans, «no trobo la base de Warp»). **Res de la 0.31.2 no s'ha vist a l'app.** Detall: `docs/disseny.md`, secció 10 |
| 08/11/2026 | **Per a altres usuaris, ronda 5 (en David, 08/11/2026): `settings.toml` nou, només amb Warp obert.** Precisa la decisió A. Si `settings.toml` no hi és, Warp Launch el crea només amb Warp obert; amb Warp tancat, espera que s'obri. Afegir la línia o la taula a un fitxer que ja hi és, com a la 0.31.2, també amb Warp tancat. **Per què:** en arrencar, si el fitxer no existeix, Warp hi passa una sola vegada els ajustos de les preferències de macOS (la migració); si algú el crea abans, Warp se la salta i aquells ajustos deixen de comptar (`fets-verificats.md`, codi públic de Warp, llegit i no vist). **Fet a la 0.31.3:** «obert» vol dir que el Warp que corre ja té algun terminal, perquè Warp només els crea després de la migració. Mentrestant, la restauració de Warp és la de sèrie (activada), sense cap avís: el menú de la icona ho diu amb una nota, el diagnòstic diu com és Warp ara i, amb Warp tancat, els fulls d'obrir diuen que Warp pot restaurar les finestres d'abans. A la mateixa versió: l'app no escriu `settings.toml` si ha canviat fa menys de 2 s (Warp el podria estar escrivint), importar i lligar diuen que Warp encara no ha desat res quan no en troben la base, i més guardes. **Res de la 0.31.3 no s'ha vist a l'app.** Detall: `docs/disseny.md`, secció 10 |
| 08/11/2026 | **Per a altres usuaris, ronda 6 (en David, 08/11/2026): el que quedava de la 0.31.3, totes com recomanaven les revisions.** El codi les cita amb la data o amb la ronda («decisió 2 d'en David, 08/11/2026», «decisió 7 (ronda 6)»): no són les dotze de la fila del 08/11/2026. <br>1. **Warp tancat i sense `settings.toml`:** «Obre a Warp…» i «Obre-ho tot…» continuen avisant que Warp restaurarà les finestres d'abans, sense Claude. No es demana d'obrir Warp primer, perquè no ho evita. **Ja era així** (0.31.3); a la 0.31.4, el text és en un sol lloc i té prova. <br>2. **Rellotge que va enrere:** una data de modificació de `settings.toml` del futur no bloqueja l'app; compta com a recent només de 2 s enrere a 2 s endavant. **0.31.4.** <br>3. **Si fa més de 5 minuts que l'app no pot desactivar l'ajust perquè `settings.toml` no para de canviar** («més tard» seguit), ho avisa al menú de la icona. **0.31.4**, comptats amb el Mac despert, i també quan no se'n pot saber el valor. <br>4. **Warp obert i sense la base:** el text diu «si Warp s'acaba d'obrir, torna-ho a provar d'aquí a uns segons». **0.31.4.** <br>5. **«Warp encara no s'ha obert mai…»** (sense la carpeta de Warp) surt al menú com a nota, sense el triangle d'avís, perquè no hi ha res per restaurar. **0.31.4.** <br>6. **Amb una carpeta de prova i sense la base de Warp, «Obre a Warp…» pot obrir pels processos,** en lloc de fallar. **Ja era així** (0.31.3); a la 0.31.4, amb proves. <br>7. **Els lectors de Warp deixen de tenir la ruta de debò per defecte** (com els de Claude a la 0.31.3), i la protecció dels permisos i atributs de fitxers val per a tot `Sources/`. **0.31.4**, sense cap canvi visible. <br>**Res de la 0.31.4 no s'ha vist a l'app.** Detall: `docs/disseny.md`, secció 10 |
| 09/11/2026 | **Tap propi de Homebrew, abans de notaritzar (en David, 09/11/2026).** L'app s'instal·la amb `brew install --cask david-erra/tap/warp-launch`, des del repo públic `David-Erra/homebrew-tap`, sense esperar el Developer ID. Mentre no sigui notaritzada, la recepta li treu la marca de quarantena perquè macOS la deixi obrir. `scripts/publica.sh` posa al dia la recepta a cada versió publicada. No substitueix les decisions 1 (Developer ID i notarització) i 6 (Sparkle) de la fila del 07/11/2026: quan arribin, la recepta canvia. Detall: `docs/disseny.md`, secció 10, «Homebrew». <br>El mateix dia, la 0.31.4 és a GitHub, i en David l'ha provada a l'app i en un usuari de macOS nou (ho ha dit ell): els «Res de la 0.3x no s'ha vist a l'app» de les files anteriors són d'abans d'aquesta prova |
| 09/11/2026 | **Actualització automàtica amb Sparkle 2.10.1 (l'autor, 09/11/2026: totes les recomanacions).** Precisa la decisió 6 de la fila del 07/11/2026. El codi les cita com «decisió N de Sparkle»: no són les de les altres files. <br>1. **Només actualitzacions signades amb la clau EdDSA,** des de la primera versió (`SUVerifyUpdateBeforeExtraction`). <br>2. **No es reinicia mentre es fa servir el Mac:** 2 minuts sense teclat ni ratolí. <br>3. **Només les versions publicades s'actualitzen soles:** les compilacions locals, mai. <br>4. **«Comprova ara» també baixa la versió,** si la ronda A surt bé. <br>5. **Editor oblidat obert:** només un avís al menú, passats 7 dies. <br>6. **`publica.sh --aplica` l'executa l'autor al seu terminal:** cap agent no publica. <br>7. **La pantalla del permís diu que l'app es connecta.** <br>8. **Comprova cada 24 h.** <br>9. **Encès de sèrie,** avisat a les notes i al README. <br>10. **No es publica per etapes.** <br>11. **Si les rondes B o E no surten netes, s'espera el Developer ID.** <br>12. **Repo públic d'un sol ús per a la ronda F.** <br>13. **Regles `deny` per a `generate_keys`, `sign_update` i `publica.sh --aplica`.** <br>**Res d'això s'ha vist funcionar.** Disseny, passos, proves reals i el que falta comprovar: `docs/disseny.md`, secció 11; fets: `docs/fets-verificats.md`, «Sparkle». <br>**Estat (09/11/2026):** al codi, de la 0.32.0 a la 0.32.5, sense publicar. Compila i passa les proves amb falsos; cap app no s'ha obert. La 4 es confirma a la ronda A, i la 11 es decideix per les rondes B i E. Falten les rondes A a F, la clau de l'autor i `Recursos/Actualitzacions.plist` (pas 11), la recepta amb `auto_updates true` (pas 12), publicar i la primera actualització real. La 13 s'ha ampliat amb `generate_appcast`, que també signa amb el clauer i no s'hi anomenava: es pot treure. **Ampliació de l'autor (09/11/2026):** també hi ha regles `deny` per a les ordres que llegeixen el clauer, `security find-generic-password` i `dump-keychain`; `security find-identity` no s'hi inclou, perquè el fa servir `build-app.sh`. Les còpies d'abans (0.31.4 o anteriors) necessiten una última actualització a mà |
| 09/11/2026 | **Els dos menús, amb els mateixos noms (en David, 09/11/2026, 0.32.6).** «Fes que en el menu de l'app i en el menu contextual la mateixa funcio es digui igual.» «Torna a llegir Warp» passa a dir-se «Actualitza l'estat de Warp», i és també al menú Arxiu i al full d'importació. «Obre la finestra a Warp…» passa a «Obre a Warp…». El menú de la icona i la pantalla del permís diuen «Sobre l’app Warp Launch» i «Surt de l’app Warp Launch», els textos que macOS posa al menú de l'app. «Torna a importar-ho tot de Warp…» no canvia: és una altra funció, substitueix la configuració. |
| 03/11/2026 | **Elements gràfics:** la icona de l'app es genera amb nano-banana (API de Gemini), amb la skill `app-icon` de BAMA adaptada al repo (`.claude/skills/app-icon/`). La icona de la barra de menú i els botons de l'editor són SF Symbols. **06/11/2026:** la icona de l'app es dibuixa amb codi (`scripts/icona-dibuixa.swift`) |

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
  clic. Descartats: obrir-ho tot sense preguntar (desenes de Claude sols a cada inici de sessió) i només una notificació.
  - Warp pot obrir-se sol en iniciar sessió, o no: al reinici de prova es va obrir sol encara que no era als ítems d'inici de
    macOS i, segons en David, l'opció de Warp («Start Warp at login») era desactivada; no se sap per què (`fets-verificats.md`). L'app no l'espera: el
    full surt de seguida i, amb Warp tancat, diu que l'obrirà amb el clic (0.27.2).
  - S'activa amb un interruptor a la Configuració (regla 3). `docs/disseny.md`, secció 9 (0.27.0).
- **D4. Obertura escalonada. Decidit per en David (05/11/2026): totes de cop,** sense tandes ni pauses («Obre-ho tot», 0.25.0).
  Si una finestra no s'obre o no es reconeix, les altres continuen, i el resultat ho diu al final. Al full, una casella per
  finestra, totes marcades. Risc acceptat: desenes de Claude alhora (uns 0,5 GB per sessió), i les pestanyes només de terminal de finestres
  diferents a la mateixa carpeta es poden confondre.
- **D6. Què fer amb el que hi ha a Warp.**
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
  per actualitzar de forma periodica la informació.» Fets a `fets-verificats.md`. Fet a la 0.23.0, amb la regla 7 ampliada (OK d'en David, 05/11/2026). **Precisada per la decisió A
  (ronda 4, 08/11/2026):** si `settings.toml` no té la línia, l'app l'afegeix (i la taula `[general]` o el fitxer, si no hi
  són), amb la mateixa excepció de la regla 7 (0.31.2). **I per la ronda 5:** el fitxer, només amb Warp obert (0.31.3). Decidit:
  - **Quan l'app s'atura (decidit per en David, 05/11/2026): sempre desactivat,** també amb «Surt» i en apagar el Mac; només l'activen els
    refrescos de l'app. Canvia la frase inicial («amb l'aplicació parada, habilitat»), perquè si no Warp restauraria les finestres sense Claude.
    Si en David deixa de fer servir l'app, Warp queda sense restauració fins que l'activi a mà. **Des de la 0.31.0,** «Restaura Warp
    i surt…» la torna com era (decisió 3 de la fila del 08/11/2026); si no hi havia la línia, hi queda a `true` (decisió A, 0.31.2).
  - **Cada quant: només quan en David ho demana (en David, 06/11/2026, 0.27.3).** Abans (05/11/2026), cada 5 minuts. En un reinici, Warp va
    restaurar la foto sol, sense Claude: ara només es refresca amb «Actualitza l'estat de Warp», importar i lligar. Història: «cada 5 minuts», activat fins que Warp desi i com a màxim 30 s. Warp només desa si passa alguna cosa, i cada canvi va al núvol. A la
    prova de 60 s, va desar en menys de 5 s (`fets-verificats.md`).
  - **Què se'n fa (en David, 05/11/2026): «només guardar-ho, per si un dia la vull importar. La funció tornar a llegir Warp llegeix d'aquesta informació si Warp està parat, i
    llegeix de Warp si Warp està en marxa».** No s'ensenya sola, i obrir finestres no en depèn. Importar i lligar la fan servir igual.
  - **Activat a mà amb l'app en marxa (en David, 05/11/2026):** l'app el torna a desactivar en 60 s, cosa que també cobreix un valor antic del núvol de Warp.
  - **Si Warp no desa en 30 s (criteri de Claude, a revisar si cal):** la lectura es mostra amb un avís que diu quantes pestanyes i terminals hi ha, i en David decideix.
- **D20. Un nom fix per a cada sessió (`--name`).** El nom d'una sessió, que és la seva adreça, canvia a cada arrencada, i un agent que
  recordi el d'abans no arriba. L'opció ja existeix a la configuració (`nom`, que la importació només omple si la sessió venia de `-n`), i al Mac
  de prova cap pestanya no la fa servir. Recomanació: sí, amb el nom de la carpeta, però després de provar-ho en una pestanya.
  Fins ara, els missatges que fallen per un nom o un socket d'una arrencada anterior són pocs (`fets-verificats.md`).
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

1. **Lectura** (R1, R2, R8). **Feta: versió 0.2.0, 03/11/2026.** El que es va aprendre de la primera lectura real és a
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
   - L'app s'instal·la a Aplicacions, amb l'OK d'en David. Per desinstal·lar-la, des de la 0.31.0: Configuració › General ›
     «Restaura Warp i surt…», esborrar-la i, si es vol, `~/.config/warp-launch/` (README.md, «Desinstal·lar»).
   - **Disseny i passos: `docs/disseny.md`** (03/11/2026).
   - **Feta el 06/11/2026:** passos 1 a 12 (la icona, a la 0.26.1) i prova 8 (0.26.0); en David dona per bona la icona.
3. **Llançaments** (R5–R7, R9, R10, R12). Es fa pas a pas, amb proves reals i l'OK d'en David a cada pas.
   1. Obrir a mà una finestra des de l'editor (R12). **Passos fets (0.15.0 a 0.24.0, 04 i 05/11/2026);** falten proves reals
      (L2, L5 i la del CLI `--obre`) i l'OK d'en David. Pla, passos i proves (L1 a L5) a `docs/disseny.md`, secció 7.
   2. Obrir tota la configuració. **Feta: 0.25.0 (D4), provada el 06/11/2026 amb la 0.26.0.** `docs/disseny.md`, secció 8.
   3. Arrencar sola en iniciar sessió, i substituir la restauració de Warp. **0.27.0 (D3), ara 0.27.3:** la restauració la gestiona
      l'app (D6, D19). **R7 encara no està comprovat:** en un reinici de prova, Warp es va obrir sol i va restaurar les
      pestanyes sense Claude, tot i que `settings.toml` deia `false`. Es mira al pròxim reinici, amb la 0.27.3. `docs/disseny.md`, secció 9.

## Pendents

- **Actualització automàtica (Sparkle), abans d'anunciar-la:** les rondes A a F, amb l'OK de l'autor per a cada una; la clau de
  signatura, amb una còpia fora del Mac; `Recursos/Actualitzacions.plist`; `auto_updates true` i `zap` a la recepta; publicar; i la
  primera actualització real, també amb Homebrew. Després, treure del README que encara no és publicada. `docs/disseny.md`, secció 11.
- **Revisar tot el que es va fer abans:**
  - el codi i les proves del prototip (des del 07/11/2026, fora del repo: a l'historial, al commit 114c97d);
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
