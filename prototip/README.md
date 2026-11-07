# Prototip `espai` (retirat)

Primera versió, en Python amb només la biblioteca estàndard. Va estar en ús fins al 03/11/2026, quan es
va desinstal·lar amb `espai desinstal·la`: es van treure el LaunchAgent `cat.davide.espai-warp.desa` i la
comanda `~/.local/bin/espai`.

- **No és font de veritat ni cal mantenir-lo.** Queda com a referència fins que es revisi què se'n pot
  aprofitar per a Warp Launch.
- **Què va quedar en desinstal·lar-lo** (no s'ha de tocar):
  - `~/.config/espai-warp/`: `espai.toml` i `estat.json`, amb l'últim desat de 13 sessions, i les seves còpies.
  - Les 7 configuracions `~/.warp/launch_configurations/espai-*.yaml`. Ara estan trencades, perquè criden
    `espai`, que ja no hi és.
- **Proves:** `python3 -m unittest discover -s prototip/tests`, des de l'arrel del repo.
  - **No executis `espai.py` amb cap subcomanda.** `instal·la` el tornaria a instal·lar, `desa` escriuria
    l'estat i `obre` obriria Warp.
- **Versió:** el prototip va arribar a la 0.1.0. Warp Launch comença un versionat propi (`VERSION`).
