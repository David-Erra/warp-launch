#!/opt/homebrew/bin/python3
"""espai: obre les finestres de Warp i reprèn les sessions de Claude Code.

Font de veritat: ~/.config/espai-warp/espai.toml (finestres i pestanyes, editable a mà).
Estat automàtic: ~/.config/espai-warp/estat.json (quina conversa de Claude té cada pestanya).

Comandes:
  espai llista                 Mostra finestres, pestanyes i què passarà en obrir-les.
  espai obre [finestra ...]    Obre a Warp les finestres (totes si no en dius cap).
  espai desa                   Desa les sessions de Claude vives (ho fa launchd cada 5 min).
  espai genera                 Regenera les configuracions de Warp (paleta ⌃⌘L, «Espai · …»).
  espai importa-warp           Crea espai.toml a partir de les finestres actuals de Warp.
  espai instal·la              Instal·la la comanda i la tasca de desat automàtic.
  espai desinstal·la           Treu la tasca de desat automàtic i la comanda.
  espai engega --tab CLAU      (intern: el fa servir cada pestanya per arrencar Claude)

Cada pestanya amb Claude té una identitat «<carpeta>#<n>» (n = ordre entre les pestanyes
amb Claude de la mateixa carpeta). La pestanya l'exporta com a ESPAI_TAB, de manera que
tot `claude` que s'hi executi queda associat a la pestanya, encara que faci `cd` o `/clear`.

Només fa servir la biblioteca estàndard de Python (>= 3.11).
"""
import argparse
import ctypes
import datetime as dt
import fcntl
import glob
import json
import os
import re
import shlex
import sqlite3
import struct
import subprocess
import sys
import time
import tomllib
import unicodedata
import urllib.parse

HOME = os.path.expanduser("~")
CFG_DIR = os.path.join(HOME, ".config", "espai-warp")
CFG = os.path.join(CFG_DIR, "espai.toml")
ESTAT = os.path.join(CFG_DIR, "estat.json")
LC_DIR = os.path.join(HOME, ".warp", "launch_configurations")
TAB_CFG_DIR = os.path.join(HOME, ".warp", "tab_configs")
LC_PREFIX = "espai-"
LC_MARCA = "# generat per espai"
LC_RESERVATS = {"tot", "obre"}
SESS_DIR = os.path.join(HOME, ".claude", "sessions")
PROJ_DIR = os.path.join(HOME, ".claude", "projects")
WARP_DB = os.path.join(
    HOME,
    "Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite",
)
SELF = os.path.realpath(__file__)
BIN_LINK = os.path.join(HOME, ".local", "bin", "espai")
LA_LABEL = "cat.davide.espai-warp.desa"
LA_PLIST = os.path.join(HOME, "Library", "LaunchAgents", LA_LABEL + ".plist")
LOG = os.path.join(HOME, "Library", "Logs", "espai-warp.log")
ARGS_DEFECTE = "--dangerously-skip-permissions --effort ultracode"
COLORS = {"red", "green", "yellow", "blue", "magenta", "cyan"}
MB_PER_SESSIO = 450
AVIS_SESSIONS = 20
ENV_TAB = "ESPAI_TAB"

# Flags de `claude` que es conserven en importar una sessió viva. La resta
# (--continue, --resume, prompts posicionals...) es descarta: reobrir mai ha de
# tornar a enviar una tasca.
FLAGS_SOLS = {"--dangerously-skip-permissions", "--verbose", "--chrome", "--no-chrome", "--ide"}
FLAGS_VALOR = {"--effort", "--model", "--permission-mode", "--fallback-model", "--agent", "--settings"}
FLAGS_VALOR_OPCIONAL = {"--remote-control"}


# --------------------------------------------------------------------------- utilitats

def ara():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def curt(p):
    return "~" + p[len(HOME):] if p and p.startswith(HOME) else (p or "")


def canon(p):
    """Ruta absoluta canònica, sense symlinks i amb les majúscules reals del disc."""
    if not p:
        return ""
    p = os.path.realpath(os.path.expanduser(p))
    try:
        fd = os.open(p, os.O_RDONLY)
        try:
            r = fcntl.fcntl(fd, fcntl.F_GETPATH, bytes(1024))
            p = r.split(b"\0", 1)[0].decode()
        finally:
            os.close(fd)
    except OSError:
        pass
    return p


def escriu_atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def slug(s):
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "x"


def q(s):
    """Cadena entre cometes, vàlida alhora en TOML i en YAML."""
    return json.dumps(s, ensure_ascii=False)


def avis(msg):
    print(f"espai: {msg}", file=sys.stderr)


# --------------------------------------------------------------------------- processos i sessions de Claude

_libc = ctypes.CDLL("/usr/lib/libc.dylib", use_errno=True)


def argv_env_de(pid):
    """(argv, env) exactes d'un procés propi via KERN_PROCARGS2; (None, {}) si no es pot."""
    mib = (ctypes.c_int * 3)(1, 49, pid)
    mida = ctypes.c_size_t(0)
    if _libc.sysctl(mib, 3, None, ctypes.byref(mida), None, 0) != 0:
        return None, {}
    buf = ctypes.create_string_buffer(mida.value)
    if _libc.sysctl(mib, 3, buf, ctypes.byref(mida), None, 0) != 0:
        return None, {}
    raw = buf.raw[: mida.value]
    argc = struct.unpack("<i", raw[:4])[0]
    resta = raw[4:]
    i = resta.find(b"\0")
    if i < 0:
        return None, {}
    while i < len(resta) and resta[i] == 0:
        i += 1
    parts = resta[i:].split(b"\0")
    argv = [a.decode("utf-8", "replace") for a in parts[:argc]]
    env = {}
    for e in parts[argc:]:
        if not e:
            break
        k, _, v = e.decode("utf-8", "replace").partition("=")
        env[k] = v
    return argv, env


def viu(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def sessions_vives():
    """Totes les sessions de Claude Code amb el procés viu (interactives i en segon pla)."""
    out = []
    for f in glob.glob(os.path.join(SESS_DIR, "*.json")):
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        pid = d.get("pid")
        if not isinstance(pid, int) or not viu(pid) or not d.get("sessionId"):
            continue
        argv, env = argv_env_de(pid)
        if not argv or "claude" not in os.path.basename(argv[0]):
            continue  # pid reutilitzat per un altre procés
        out.append({
            "pid": pid,
            "procStart": d.get("procStart", ""),
            "sessionId": d["sessionId"],
            "nom": d.get("name", ""),
            "dir": canon(d.get("cwd", "")),
            "inici": d.get("startedAt", 0),
            "kind": d.get("kind", ""),
            "interactiva": d.get("kind") == "interactive" and d.get("entrypoint", "cli") == "cli",
            "tab": env.get(ENV_TAB, ""),
            "argv": argv,
        })
    out.sort(key=lambda s: (s["dir"], s["inici"]))
    return out


def filtra_args(argv):
    """Conserva només els flags coneguts; retorna (args, descartats)."""
    toks, descartats, i = argv[1:], [], 0
    keep = []
    while i < len(toks):
        t = toks[i]
        nom, igual, _ = t.partition("=")
        if t in FLAGS_SOLS:
            keep.append(t)
        elif nom in FLAGS_VALOR and igual:
            keep.append(t)
        elif t in FLAGS_VALOR:
            if i + 1 < len(toks):
                keep += [t, toks[i + 1]]
                i += 1
        elif nom in FLAGS_VALOR_OPCIONAL:
            keep.append(t)
            if not igual and i + 1 < len(toks) and not toks[i + 1].startswith("-"):
                keep.append(toks[i + 1])
                i += 1
        elif t in ("--resume", "-r", "--session-id"):
            if i + 1 < len(toks) and not toks[i + 1].startswith("-"):
                i += 1
            descartats.append(t)
        else:
            descartats.append(t)
        i += 1
    return keep, descartats


def dir_projecte(d):
    return os.path.join(PROJ_DIR, re.sub(r"[^A-Za-z0-9]", "-", d))


def transcripcio(session_id, d):
    """La conversa existeix al projecte d'aquesta carpeta (si no, --resume no la troba des d'aquí)."""
    return bool(session_id) and os.path.exists(os.path.join(dir_projecte(d), session_id + ".jsonl"))


def conversa_lliure(d, ocupades):
    """La conversa més recent de la carpeta que no és de cap altra pestanya ni està oberta."""
    fitxers = glob.glob(os.path.join(dir_projecte(d), "*.jsonl"))
    for f in sorted(fitxers, key=lambda x: os.path.getmtime(x), reverse=True):
        sid = os.path.basename(f)[:-6]
        if sid not in ocupades:
            return sid
    return ""


# --------------------------------------------------------------------------- configuració i estat

def llegeix_cfg(obligatori=True, tolerant=False):
    """Llegeix i valida espai.toml. tolerant=True: davant d'un error, avisa i retorna una config buida."""
    if not os.path.exists(CFG):
        if obligatori:
            sys.exit(f"No hi ha {curt(CFG)}. Crea'l amb: espai importa-warp")
        return None
    try:
        with open(CFG, "rb") as f:
            cfg = tomllib.load(f)
        return valida_cfg(cfg)
    except (tomllib.TOMLDecodeError, TypeError, ValueError, AttributeError) as e:
        if tolerant:
            avis(f"{curt(CFG)} té un error ({e}); faig servir els valors per defecte.")
            return {"args": ARGS_DEFECTE, "finestra": []}
        sys.exit(f"{curt(CFG)} té un error: {e}")


def valida_cfg(cfg):
    if not isinstance(cfg.get("args", ARGS_DEFECTE), str):
        raise ValueError("`args` ha de ser text")
    cfg.setdefault("args", ARGS_DEFECTE)
    finestres = cfg.setdefault("finestra", [])
    if not isinstance(finestres, list):
        raise ValueError("cal [[finestra]]")
    claus_vistes, per_dir = set(), {}
    for n, fin in enumerate(finestres):
        if not isinstance(fin, dict):
            raise ValueError(f"finestra {n + 1} mal formada")
        fin["nom"] = str(fin.get("nom") or f"Finestra {n + 1}")
        clau = slug(fin.get("clau") or fin["nom"])
        base, k = clau, 2
        while clau in claus_vistes or clau in LC_RESERVATS:
            clau = f"{base}-{k}"
            k += 1
        if clau != slug(fin.get("clau") or fin["nom"]):
            avis(f"la finestra «{fin['nom']}» passa a tenir la clau «{clau}» (repetida o reservada).")
        claus_vistes.add(clau)
        fin["clau"] = clau
        pest = fin.setdefault("pestanya", [])
        if not isinstance(pest, list):
            raise ValueError(f"finestra «{fin['nom']}»: cal [[finestra.pestanya]]")
        for p in pest:
            if not isinstance(p, dict):
                raise ValueError(f"finestra «{fin['nom']}»: pestanya mal formada")
            p["titol"] = str(p.get("titol", ""))
            p["dir"] = canon(p["dir"]) if isinstance(p.get("dir"), str) and p["dir"] else ""
            p["claude"] = bool(p.get("claude", bool(p["dir"])))
            if "args" in p and not isinstance(p["args"], str):
                raise ValueError(f"«{p['titol']}»: `args` ha de ser text")
            ab = p.get("abans", [])
            ab = [ab] if isinstance(ab, str) else ab
            if not isinstance(ab, list) or not all(isinstance(x, str) for x in ab):
                raise ValueError(f"«{p['titol']}»: `abans` ha de ser una llista de comandes")
            p["abans"] = ab
            color = str(p.get("color", "")).lower()
            if color and color not in COLORS:
                avis(f"«{p['titol']}»: color «{color}» no vàlid ({', '.join(sorted(COLORS))}); l'ignoro.")
                color = ""
            p["color"] = color
            p["clau_tab"] = ""
            if p["claude"] and p["dir"]:
                idx = per_dir.get(p["dir"], 0)
                per_dir[p["dir"]] = idx + 1
                p["clau_tab"] = f"{p['dir']}#{idx}"
    return cfg


def pestanyes_claude(cfg):
    return [p for f in cfg["finestra"] for p in f["pestanya"] if p["clau_tab"]]


def llegeix_estat():
    try:
        with open(ESTAT, encoding="utf-8") as f:
            e = json.load(f)
    except (OSError, ValueError):
        e = {}
    if not isinstance(e, dict):
        e = {}
    tabs = e.get("tabs") if isinstance(e.get("tabs"), dict) else {}
    # Migració del format 1 (llista per carpeta).
    for d, recs in (e.get("dirs") or {}).items():
        for i, r in enumerate(recs or []):
            tabs.setdefault(f"{d}#{i}", r)
    return {"versio": 2, "actualitzat": e.get("actualitzat", ""), "tabs": tabs,
            "orfes": e.get("orfes") if isinstance(e.get("orfes"), dict) else {}}


def desa_estat(estat):
    estat["actualitzat"] = ara()
    escriu_atomic(ESTAT, json.dumps(estat, ensure_ascii=False, indent=1) + "\n")


def es_viva(rec, vives):
    if not rec:
        return None
    for s in vives:
        if s["sessionId"] == rec.get("sessionId"):
            return s
        if s["pid"] == rec.get("pid") and s["procStart"] and s["procStart"] == rec.get("procStart"):
            return s
    return None


def registre(s):
    return {"sessionId": s["sessionId"], "nom": s["nom"], "pid": s["pid"],
            "procStart": s["procStart"], "inici": s["inici"], "cwd": s["dir"], "vist": ara()}


def actualitza_estat(cfg, estat, vives):
    """Associa cada sessió viva a la seva pestanya. Mai esborra el registre d'una pestanya tancada.

    Retorna les carpetes amb sessions que no encaixen a cap pestanya.
    """
    tabs = pestanyes_claude(cfg) if cfg else []
    claus = {p["clau_tab"] for p in tabs}
    dirs_tab = sorted({p["dir"] for p in tabs}, key=len, reverse=True)
    assignades = set()
    sense_marca = []
    for s in (s for s in vives if s["interactiva"]):
        if s["tab"] in claus:
            estat["tabs"][s["tab"]] = registre(s)
            assignades.add(s["tab"])
        else:
            sense_marca.append(s)
    orfes = {}
    for s in sense_marca:
        # Carpeta de la pestanya: la configurada més llarga que conté el cwd (Claude pot haver fet cd).
        d = next((t for t in dirs_tab if s["dir"] == t or s["dir"].startswith(t + os.sep)), None)
        cand = [p["clau_tab"] for p in tabs if p["dir"] == d and p["clau_tab"] not in assignades]
        tria = None
        for k in cand:  # 1) la mateixa sessió o el mateix procés (després d'un /clear)
            r = estat["tabs"].get(k) or {}
            if r.get("sessionId") == s["sessionId"] or (
                    r.get("pid") == s["pid"] and s["procStart"] and r.get("procStart") == s["procStart"]):
                tria = k
                break
        if tria is None:  # 2) una pestanya encara sense cap conversa
            tria = next((k for k in cand if k not in estat["tabs"]), None)
        if tria is None:
            orfes.setdefault(s["dir"], []).append(registre(s))
            continue
        estat["tabs"][tria] = registre(s)
        assignades.add(tria)
    estat["orfes"] = orfes
    return sorted(orfes)


def args_pestanya(cfg, p):
    return shlex.split(p["args"] if "args" in p else cfg.get("args", ARGS_DEFECTE))


def pla(cfg, estat, vives, p):
    """Què farà la pestanya en obrir-se: (codi, detall, sessionId)."""
    if not p["dir"]:
        return "sense-dir", "sense carpeta: obrirà un terminal a ~", ""
    if not os.path.isdir(p["dir"]):
        return "no-existeix", "la carpeta no existeix", ""
    if not p["clau_tab"]:
        return "terminal", "terminal (sense Claude)", ""
    rec = estat["tabs"].get(p["clau_tab"])
    s = es_viva(rec, vives)
    if s:
        return "viva", f"oberta ara ({s['nom']})", s["sessionId"]
    if rec and transcripcio(rec.get("sessionId"), p["dir"]):
        return "repren", f"reprendrà {rec['sessionId'][:8]} ({rec.get('nom', '')})", rec["sessionId"]
    ocupades = {r.get("sessionId") for k, r in estat["tabs"].items() if k != p["clau_tab"]}
    ocupades |= {v["sessionId"] for v in vives}
    sid = conversa_lliure(p["dir"], ocupades)
    if sid:
        return "recupera", f"reprendrà {sid[:8]} (l'última conversa lliure de la carpeta)", sid
    return "nova", "sessió nova", ""


def busca_pestanya(cfg, clau_tab):
    return next((p for p in pestanyes_claude(cfg) if p["clau_tab"] == clau_tab), None)


# --------------------------------------------------------------------------- desa

def cmd_desa(a):
    vives = sessions_vives()
    estat = llegeix_estat()
    cfg = llegeix_cfg(obligatori=False, tolerant=True)
    orfes = actualitza_estat(cfg, estat, vives)
    desa_estat(estat)
    n = sum(1 for s in vives if s["interactiva"])
    if not a.silencios:
        print(f"Desades {n} sessions de Claude vives ({curt(ESTAT)}).")
        if orfes:
            print("Sessions en carpetes que no tenen pestanya lliure a espai.toml:")
            for d in orfes:
                print(f"  {curt(d)}")
            if not a.afegeix:
                print("Afegeix-les amb: espai desa --afegeix")
    if a.afegeix and cfg and orfes:
        bloc = ["", "[[finestra]]", f"nom = {q('Noves')}",
                f"clau = {q('noves-' + dt.datetime.now().strftime('%Y%m%d-%H%M'))}"]
        for d in orfes:
            for _ in estat["orfes"][d]:
                bloc += ["", "  [[finestra.pestanya]]", f"  titol = {q(os.path.basename(d))}",
                         f"  dir = {q(curt(d))}", "  claude = true"]
        with open(CFG, "a", encoding="utf-8") as f:
            f.write("\n".join(bloc) + "\n")
        cfg = llegeix_cfg()
        actualitza_estat(cfg, estat, vives)
        desa_estat(estat)
        cmd_genera(argparse.Namespace(silencios=True))
        print(f"Afegida la finestra «Noves» a {curt(CFG)}.")
    return 0


# --------------------------------------------------------------------------- genera / obre

def exec_engega(p):
    clau = shlex.quote(p["clau_tab"])
    return f"export {ENV_TAB}={clau} && {shlex.quote(BIN_LINK)} engega --tab {clau}"


def yaml_finestres(nom_cfg, finestres):
    L = [LC_MARCA + f": edita {curt(CFG)} i executa `espai genera`", "---", f"name: {q(nom_cfg)}", "windows:"]
    for fin in finestres:
        L.append("  - tabs:")
        for p in fin["pestanya"]:
            ok = bool(p["dir"]) and os.path.isdir(p["dir"])
            L.append(f"      - title: {q(p['titol'] or os.path.basename(p['dir']) or 'terminal')}")
            if p["color"]:
                L.append(f"        color: {q(p['color'])}")
            L.append("        layout:")
            L.append(f"          cwd: {q(p['dir'] if ok else HOME)}")
            cmds = (list(p["abans"]) + ([exec_engega(p)] if p["clau_tab"] else [])) if ok else []
            if cmds:
                L.append("          commands:")
                L += [f"            - exec: {q(c)}" for c in cmds]
    return "\n".join(L) + "\n"


def es_nostre(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.readline().startswith(LC_MARCA)
    except OSError:
        return False


def cmd_genera(a):
    cfg = llegeix_cfg()
    os.makedirs(LC_DIR, exist_ok=True)
    fets = {f"{LC_PREFIX}tot.yaml": yaml_finestres("Espai · Tot", cfg["finestra"])}
    for fin in cfg["finestra"]:
        fets[f"{LC_PREFIX}{fin['clau']}.yaml"] = yaml_finestres(f"Espai · {fin['nom']}", [fin])
    escrits = 0
    for nom, txt in fets.items():
        path = os.path.join(LC_DIR, nom)
        if os.path.exists(path) and not es_nostre(path):
            avis(f"no sobreescric {curt(path)}: no l'ha generat espai.")
            continue
        escriu_atomic(path, txt)
        escrits += 1
    # Esborra només fitxers generats per espai que ja no corresponen a cap finestra.
    for f in glob.glob(os.path.join(LC_DIR, LC_PREFIX + "*.yaml")):
        if os.path.basename(f) not in fets and es_nostre(f):
            os.remove(f)
    if not getattr(a, "silencios", False):
        print(f"Generades {escrits} configuracions a {curt(LC_DIR)} (paleta de Warp ⌃⌘L, «Espai · …»).")
    return 0


def obre_uri(nom_cfg):
    """Warp obre una launch configuration pel camp `name` (no per la ruta del fitxer)."""
    uri = "warp://launch/" + urllib.parse.quote(nom_cfg, safe="")
    subprocess.run(["open", uri], check=True)


def cmd_obre(a):
    cfg = llegeix_cfg()
    vives, estat = sessions_vives(), llegeix_estat()
    actualitza_estat(cfg, estat, vives)  # estat fresc: no depèn del desat de cada 5 min
    if not a.prova:
        desa_estat(estat)
        cmd_genera(argparse.Namespace(silencios=True))
    claus = [slug(c) for c in a.finestres]
    triades = [f for f in cfg["finestra"] if not claus or f["clau"] in claus or slug(f["nom"]) in claus]
    if claus and not triades:
        sys.exit("No conec cap d'aquestes finestres. Mira les claus amb: espai llista")
    sel, saltades, n_claude = [], 0, 0
    for fin in triades:
        pest = []
        for p in fin["pestanya"]:
            codi = pla(cfg, estat, vives, p)[0]
            if codi == "viva" and not a.inclou_vives:
                saltades += 1
                continue
            pest.append(p)
            n_claude += codi in ("repren", "recupera", "nova")
        if pest:
            sel.append({**fin, "pestanya": pest})
    if not sel:
        print(f"Res per obrir: les {saltades} pestanyes ja tenen la sessió oberta.")
        return 0
    nom_cfg = "Espai · Obertura " + dt.datetime.now().strftime("%H%M%S")
    txt = yaml_finestres(nom_cfg, sel)
    if a.prova:
        print(txt)
        print(f"(prova) Obriria {len(sel)} finestres, {sum(len(f['pestanya']) for f in sel)} pestanyes, "
              f"{n_claude} amb Claude; {saltades} ja eren obertes.")
        return 0
    if n_claude > AVIS_SESSIONS and not a.si:
        print(f"Obriré {n_claude} sessions de Claude (~{n_claude * MB_PER_SESSIO // 1024} GB de memòria).")
        if not sys.stdin.isatty():
            print("Sense terminal interactiu no puc demanar confirmació: afegeix --si, o obre per finestres.")
            return 1
        if input("Continuo? [s/N] ").strip().lower() not in ("s", "si", "sí", "y"):
            print("Cancel·lat. Pots obrir-les per finestres: espai obre <clau>")
            return 1
    path = os.path.join(LC_DIR, f"{LC_PREFIX}obre.yaml")
    escriu_atomic(path, txt)
    time.sleep(1)  # Warp vigila la carpeta; li deixem llegir el fitxer nou
    obre_uri(nom_cfg)
    time.sleep(4)
    if es_nostre(path):
        os.remove(path)  # que no quedi a la paleta de Warp una obertura antiga
    print(f"Obertes {len(sel)} finestres, {sum(len(f['pestanya']) for f in sel)} pestanyes "
          f"({n_claude} amb Claude)" + (f"; {saltades} ja eren obertes" if saltades else "") + ".")
    return 0


# --------------------------------------------------------------------------- engega (dins de cada pestanya)

def cmd_engega(a):
    clau = a.tab or os.environ.get(ENV_TAB, "")
    if a.dir:  # compatibilitat amb configuracions generades per la primera versió
        clau = f"{canon(a.dir)}#{a.idx}"
    d = clau.rsplit("#", 1)[0]
    cfg = llegeix_cfg(obligatori=False, tolerant=True) or {"args": ARGS_DEFECTE, "finestra": []}
    p = busca_pestanya(cfg, clau) or {"dir": d, "clau_tab": clau, "claude": True, "titol": ""}
    vives, estat = sessions_vives(), llegeix_estat()
    codi, detall, sid = pla(cfg, estat, vives, p)
    if codi in ("viva", "sense-dir", "no-existeix", "terminal"):
        print(f"espai: {detall}. Et deixo al terminal.")
        return 0
    cmd = ["claude"] + (["--resume", sid] if sid else []) + args_pestanya(cfg, p)
    os.environ[ENV_TAB] = clau
    os.chdir(d)
    print(f"espai: {detall}\n▶ {shlex.join(cmd)}")
    sys.stdout.flush()
    if os.environ.get("ESPAI_PROVA"):
        return 0
    try:
        os.execvp(cmd[0], cmd)
    except OSError as e:
        print(f"espai: no puc executar claude ({e}).")
        return 1


# --------------------------------------------------------------------------- llista

ICONES = {"viva": "🟢", "repren": "↻ ", "recupera": "↻ ", "nova": "＋", "terminal": "· ",
          "sense-dir": "⚠️", "no-existeix": "⚠️"}


def cmd_llista(a):
    cfg = llegeix_cfg()
    vives, estat = sessions_vives(), llegeix_estat()
    actualitza_estat(cfg, estat, vives)
    tot = 0
    for fin in cfg["finestra"]:
        print(f"\n■ {fin['nom']}  (espai obre {fin['clau']})")
        for p in fin["pestanya"]:
            codi, detall, _ = pla(cfg, estat, vives, p)
            print(f"  {ICONES.get(codi, '  ')} {p['titol'][:34]:34} {curt(p['dir'])[:52]:52} {detall}")
            tot += 1
    n = sum(1 for s in vives if s["interactiva"])
    print(f"\n{tot} pestanyes · {n} sessions vives · últim desat automàtic: {estat.get('actualitzat') or 'mai'}")
    print("🟢 oberta ara · ↻ es reprendrà · ＋ sessió nova · · terminal · ⚠️ revisa espai.toml")
    return 0


# --------------------------------------------------------------------------- importa-warp

PREFIXOS = {"cpy", "it", "op", "ot", "rh", "fin", "mkt", "per", "ana", "app", "ai"}


def tokens(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return [t for t in re.split(r"[^a-z0-9]+", s) if t]


def repos_candidats():
    out = []
    for arrel in (os.path.join(HOME, "GitHub"), os.path.join(HOME, "GitHub-Personal")):
        for d in glob.glob(os.path.join(arrel, "*")) + glob.glob(os.path.join(arrel, "*", "*")):
            if os.path.isdir(os.path.join(d, ".git")):
                out.append(canon(d))
    return sorted(set(out))


def titols_coneguts():
    """Títol de pestanya → carpeta, segons tab configs i launch configs de Warp."""
    m = {}
    for f in glob.glob(os.path.join(TAB_CFG_DIR, "*.toml")):
        try:
            with open(f, "rb") as fh:
                d = tomllib.load(fh)
            dirp = next((p.get("directory") for p in d.get("panes", []) if p.get("directory")), None)
            if dirp:
                for t in (d.get("title"), d.get("name")):
                    if t:
                        m[t.lower()] = canon(dirp)
        except (OSError, ValueError):
            pass
    for f in glob.glob(os.path.join(LC_DIR, "*.yaml")):
        try:
            txt = open(f, encoding="utf-8").read()
        except OSError:
            continue
        if txt.startswith(LC_MARCA):
            continue
        for t, c in re.findall(r"title:\s*\"?([^\"\n]+?)\"?\s*\n\s*layout:\s*\n\s*cwd:\s*\"?([^\"\n]+)", txt):
            m.setdefault(t.strip().lower(), canon(c.strip()))
    return m


def coincideix(x, rt):
    return any(x == y or (len(x) > 4 and y.startswith(x)) or (len(y) >= 3 and x.startswith(y)) for y in rt)


def resol_titol(titol, repos, coneguts, historial=()):
    """Carpeta per al títol d'una pestanya: (dir, font). L'historial de Warp desfà empats."""
    if titol.lower() in coneguts and os.path.isdir(coneguts[titol.lower()]):
        return coneguts[titol.lower()], "config de Warp"
    tt = [t for t in tokens(titol) if t not in PREFIXOS]
    if not tt:
        return "", ""
    millors = []
    for r in repos:
        rt = set(tokens(os.path.basename(r)))
        if all(coincideix(x, rt) for x in tt):
            millors.append((len(rt - set(tt)), r))
    millors.sort()
    if len(millors) == 1 or (len(millors) > 1 and millors[0][0] < millors[1][0]):
        return millors[0][1], "nom del repo"
    for h in historial:
        if any(h == r for _, r in millors):
            return h, "nom del repo + historial de Warp"
    return "", ("ambigu: " + ", ".join(curt(r) for _, r in millors[:3])) if millors else ""


def historial_tab(con, tab_id):
    """Carpetes (repos git) on s'han executat comandes en aquesta pestanya, de més a menys usada."""
    try:
        files = con.execute(
            """select b.pwd, count(*) c from blocks b
                 join terminal_panes tp on tp.uuid = b.pane_leaf_uuid
                 join pane_nodes n on n.id = tp.id
                where n.tab_id = ? and b.pwd is not null group by b.pwd order by c desc""", (tab_id,)).fetchall()
    except sqlite3.Error:
        return []
    out = []
    for pwd, _ in files:
        c = canon(pwd)
        if c and os.path.isdir(os.path.join(c, ".git")) and c not in out:
            out.append(c)
    return out


def cmd_importa_warp(a):
    if os.path.exists(CFG) and not a.forca:
        sys.exit(f"{curt(CFG)} ja existeix. Fes servir --força per sobreescriure'l (se'n desa còpia).")
    if not os.path.exists(WARP_DB):
        sys.exit("No trobo la base de dades de Warp.")
    con = sqlite3.connect(f"file:{urllib.parse.quote(WARP_DB)}?mode=ro", uri=True)
    files = con.execute(
        """select t.window_id, t.id, coalesce(t.custom_title,''), coalesce(t.color,''),
                  (select tp.cwd from pane_nodes n join terminal_panes tp on tp.id = n.id
                    where n.tab_id = t.id and n.is_leaf = 1 order by n.id limit 1)
             from tabs t order by t.window_id, t.id""").fetchall()
    hist = {tab: historial_tab(con, tab) for _w, tab, *_ in files}
    con.close()
    vives = sessions_vives()
    args_viu = {}
    for s in vives:
        if s["interactiva"]:
            args_viu.setdefault(s["dir"], shlex.join(filtra_args(s["argv"])[0]))
    repos, coneguts = repos_candidats(), titols_coneguts()
    finestres, pendents = {}, 0
    for win, tab, titol, color, cwd in files:
        d, font = "", ""
        if cwd and canon(cwd) != canon(HOME):
            d, font = canon(cwd), "carpeta de la pestanya"
        elif titol:
            d, font = resol_titol(titol, repos, coneguts, hist.get(tab, []))
        pendents += 0 if d else 1
        finestres.setdefault(win, []).append({"titol": titol, "dir": d, "font": font, "color": color.lower()})

    L = ["# Espai de treball de Warp + Claude Code.",
         "# Edita'l lliurement i després executa `espai genera` (o directament `espai obre`).",
         "#   claude = true  → la pestanya reprèn la seva conversa de Claude",
         "#   args           → flags de claude per a la pestanya (si no, els de dalt)",
         "#   abans          → comandes abans de Claude, p. ex. [\"git pull --ff-only || true\"]",
         "#   color          → red | green | yellow | blue | magenta | cyan",
         "",
         f"args = {q(ARGS_DEFECTE)}"]
    for n, (win, pest) in enumerate(finestres.items(), 1):
        L += ["", "[[finestra]]", f"nom = {q(f'Finestra {n}')}", f"clau = {q(f'f{n}')}"]
        for p in pest:
            L += ["", "  [[finestra.pestanya]]", f"  titol = {q(p['titol'])}"]
            if p["dir"]:
                L.append(f"  dir = {q(curt(p['dir']))}  # {p['font']}")
                L.append("  claude = true")
                av = args_viu.get(p["dir"])
                if av is not None and av != ARGS_DEFECTE:
                    L.append(f"  args = {q(av)}")
            else:
                L.append(f"  dir = \"\"  # PENDENT{': ' + p['font'] if p['font'] else ': no he trobat la carpeta'}")
                L.append("  claude = false")
            if p["color"] in ("red", "green", "yellow", "blue", "magenta", "cyan"):
                L.append(f"  color = {q(p['color'])}")
    if os.path.exists(CFG):
        os.replace(CFG, CFG + ".bak-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    escriu_atomic(CFG, "\n".join(L) + "\n")
    print(f"Creat {curt(CFG)}: {len(finestres)} finestres, {len(files)} pestanyes, {pendents} sense carpeta (PENDENT).")
    return 0



# --------------------------------------------------------------------------- instal·la / desinstal·la

def _carregat():
    return subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/{LA_LABEL}"],
                          capture_output=True).returncode == 0


def cmd_instal_la(a):
    os.makedirs(os.path.dirname(BIN_LINK), exist_ok=True)
    os.chmod(SELF, 0o755)
    if os.path.islink(BIN_LINK) or os.path.exists(BIN_LINK):
        if os.path.realpath(BIN_LINK) != SELF:
            sys.exit(f"{curt(BIN_LINK)} ja existeix i no és d'espai.")
    else:
        os.symlink(SELF, BIN_LINK)
    plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{LA_LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>{BIN_LINK}</string><string>desa</string><string>--silencios</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>StandardOutPath</key><string>{LOG}</string>
  <key>StandardErrorPath</key><string>{LOG}</string>
</dict>
</plist>
"""
    escriu_atomic(LA_PLIST, plist)
    dom = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", dom, LA_PLIST], capture_output=True)
    for _ in range(20):
        if not _carregat():
            break
        time.sleep(0.2)
    for _ in range(5):
        if subprocess.run(["launchctl", "bootstrap", dom, LA_PLIST], capture_output=True).returncode == 0:
            break
        time.sleep(0.5)
    if not _carregat():
        sys.exit(f"No he pogut carregar {LA_LABEL}. Prova: launchctl bootstrap {dom} {LA_PLIST}")
    print(f"Instal·lat: comanda {curt(BIN_LINK)} i desat automàtic cada 5 min ({LA_LABEL}).")
    print("Recomanat: a Warp, Settings > Features > Session, desactiva «Restore windows, tabs and panes")
    print("on startup», perquè Warp no torni a obrir les seves pestanyes a més de les d'espai.")
    return 0


def cmd_desinstal_la(a):
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", LA_PLIST], capture_output=True)
    if os.path.exists(LA_PLIST):
        os.remove(LA_PLIST)
    if os.path.islink(BIN_LINK) and os.path.realpath(BIN_LINK) == SELF:
        os.remove(BIN_LINK)
    print("Desinstal·lat. La configuració i l'estat es conserven a " + curt(CFG_DIR) + ".")
    return 0


# --------------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(prog="espai", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("llista", help="mostra finestres i pestanyes")
    o = sub.add_parser("obre", help="obre finestres a Warp")
    o.add_argument("finestres", nargs="*", help="claus de finestra (totes si no se n'indica cap)")
    o.add_argument("--inclou-vives", action="store_true", help="obre també les pestanyes amb la sessió ja oberta")
    o.add_argument("--si", action="store_true", help="no demanar confirmació")
    o.add_argument("--prova", action="store_true", help="mostra què obriria, sense escriure ni obrir res")
    d = sub.add_parser("desa", help="desa les sessions de Claude vives")
    d.add_argument("--silencios", action="store_true")
    d.add_argument("--afegeix", action="store_true", help="afegeix a espai.toml les carpetes noves")
    sub.add_parser("genera", help="regenera les configuracions de Warp")
    i = sub.add_parser("importa-warp", help="crea espai.toml a partir de Warp")
    i.add_argument("--força", "--forca", dest="forca", action="store_true")
    sub.add_parser("instal·la", aliases=["instal-la", "instala"], help="instal·la comanda i desat automàtic")
    sub.add_parser("desinstal·la", aliases=["desinstal-la", "desinstala"], help="treu el desat automàtic")
    e = sub.add_parser("engega", help=argparse.SUPPRESS)
    e.add_argument("--tab", default="")
    e.add_argument("--dir", default="")
    e.add_argument("--idx", type=int, default=0)
    a = ap.parse_args(argv)
    fn = {
        "llista": cmd_llista, "obre": cmd_obre, "desa": cmd_desa, "genera": cmd_genera,
        "importa-warp": cmd_importa_warp, "engega": cmd_engega,
        "instal·la": cmd_instal_la, "instal-la": cmd_instal_la, "instala": cmd_instal_la,
        "desinstal·la": cmd_desinstal_la, "desinstal-la": cmd_desinstal_la, "desinstala": cmd_desinstal_la,
    }[a.cmd]
    return fn(a) or 0


if __name__ == "__main__":
    sys.exit(main())
