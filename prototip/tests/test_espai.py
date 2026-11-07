"""Proves de regressió d'espai.py. Només biblioteca estàndard.

    python3 -m unittest discover -s prototip/tests -v   (des de l'arrel del repo)

Totes les proves treballen en un directori temporal: no llegeixen ni escriuen
~/.config/espai-warp, ~/.warp ni ~/.claude, i no obren Warp ni Claude.
"""
import importlib.util
import json
import os
import shutil
import tempfile
import time
import unittest

ARREL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def carrega_modul():
    spec = importlib.util.spec_from_file_location("espai", os.path.join(ARREL, "espai.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class Base(unittest.TestCase):
    def setUp(self):
        self.e = carrega_modul()
        self.tmp = tempfile.mkdtemp(prefix="espai-test-")
        e = self.e
        e.CFG = os.path.join(self.tmp, "espai.toml")
        e.ESTAT = os.path.join(self.tmp, "estat.json")
        e.LC_DIR = os.path.join(self.tmp, "lc")
        e.PROJ_DIR = os.path.join(self.tmp, "projects")
        os.makedirs(e.LC_DIR)
        os.makedirs(e.PROJ_DIR)
        self.D = e.canon(os.path.join(self.tmp, "repo"))
        os.makedirs(self.D)
        self.D = e.canon(self.D)
        self.D2 = os.path.join(self.tmp, "repo2")
        os.makedirs(self.D2)
        self.D2 = e.canon(self.D2)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def config(self, cos, args='"--effort ultracode"'):
        with open(self.e.CFG, "w", encoding="utf-8") as f:
            f.write(f"args = {args}\n{cos}")
        return self.e.llegeix_cfg()

    def transcripcio(self, d, sid, mtime=None):
        p = self.e.dir_projecte(d)
        os.makedirs(p, exist_ok=True)
        f = os.path.join(p, sid + ".jsonl")
        with open(f, "w") as fh:
            fh.write("{}\n")
        if mtime:
            os.utime(f, (mtime, mtime))

    def sessio(self, sid, pid, tab="", cwd=None, inici=1, interactiva=True):
        return {"pid": pid, "procStart": f"p{pid}", "sessionId": sid, "nom": sid,
                "dir": cwd or self.D, "inici": inici, "kind": "interactive" if interactiva else "bg",
                "interactiva": interactiva, "tab": tab, "argv": ["claude"]}

    def dues_pestanyes(self, extra=""):
        return self.config(f'''
[[finestra]]
nom = "A"
  [[finestra.pestanya]]
  titol = "Servidor"
  dir = "{self.D}"
  claude = false
  [[finestra.pestanya]]
  titol = "T0"
  dir = "{self.D}"
  [[finestra.pestanya]]
  titol = "T1"
  dir = "{self.D}"
{extra}''')


class Configuracio(Base):
    def test_idx_nomes_compta_pestanyes_amb_claude(self):
        cfg = self.dues_pestanyes()
        claus = [p["clau_tab"] for p in cfg["finestra"][0]["pestanya"]]
        self.assertEqual(claus, ["", f"{self.D}#0", f"{self.D}#1"])

    def test_args_buit_es_respecta(self):
        cfg = self.config(f'''
[[finestra]]
nom = "A"
  [[finestra.pestanya]]
  dir = "{self.D}"
  args = ""
''')
        self.assertEqual(self.e.args_pestanya(cfg, cfg["finestra"][0]["pestanya"][0]), [])

    def test_abans_text_i_color_invalid(self):
        cfg = self.config(f'''
[[finestra]]
nom = "A"
  [[finestra.pestanya]]
  dir = "{self.D}"
  abans = "git status"
  color = "Purple"
''')
        p = cfg["finestra"][0]["pestanya"][0]
        self.assertEqual(p["abans"], ["git status"])
        self.assertEqual(p["color"], "")

    def test_claus_repetides_i_reservades(self):
        cfg = self.config('[[finestra]]\nnom = "Tot"\n[[finestra]]\nnom = "X"\n[[finestra]]\nnom = "X"\n')
        self.assertEqual([f["clau"] for f in cfg["finestra"]], ["tot-2", "x", "x-2"])

    def test_toml_trencat_en_mode_tolerant(self):
        with open(self.e.CFG, "w") as f:
            f.write("[[finestra\n")
        cfg = self.e.llegeix_cfg(obligatori=False, tolerant=True)
        self.assertEqual(cfg["finestra"], [])

    def test_migracio_estat_v1(self):
        with open(self.e.ESTAT, "w") as f:
            json.dump({"dirs": {self.D: [{"sessionId": "A"}, {"sessionId": "B"}]}}, f)
        est = self.e.llegeix_estat()
        self.assertEqual(est["tabs"][f"{self.D}#1"]["sessionId"], "B")


class Associacio(Base):
    def test_marca_no_depen_de_l_ordre_d_inici(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        k0, k1 = f"{self.D}#0", f"{self.D}#1"
        self.e.actualitza_estat(cfg, est, [self.sessio("A", 1, k0, inici=2), self.sessio("B", 2, k1, inici=1)])
        self.assertEqual((est["tabs"][k0]["sessionId"], est["tabs"][k1]["sessionId"]), ("A", "B"))

    def test_pestanya_tancada_conserva_el_registre(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        k0, k1 = f"{self.D}#0", f"{self.D}#1"
        self.e.actualitza_estat(cfg, est, [self.sessio("A", 1, k0), self.sessio("B", 2, k1)])
        self.e.actualitza_estat(cfg, est, [self.sessio("B", 2, k1)])
        self.assertEqual(est["tabs"][k0]["sessionId"], "A")

    def test_clear_sense_marca_mateix_proces(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        k0, k1 = f"{self.D}#0", f"{self.D}#1"
        self.e.actualitza_estat(cfg, est, [self.sessio("A", 1, k0), self.sessio("B", 2, k1)])
        self.e.actualitza_estat(cfg, est, [self.sessio("B2", 2, "")])
        self.assertEqual((est["tabs"][k0]["sessionId"], est["tabs"][k1]["sessionId"]), ("A", "B2"))

    def test_cd_a_subcarpeta_va_a_la_pestanya_mare(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        sub = os.path.join(self.D, "treball", "x")
        os.makedirs(sub)
        orfes = self.e.actualitza_estat(cfg, est, [self.sessio("X", 7, "", cwd=self.e.canon(sub))])
        self.assertEqual(orfes, [])
        self.assertEqual(est["tabs"][f"{self.D}#0"]["sessionId"], "X")

    def test_mes_sessions_que_pestanyes_son_orfes(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        orfes = self.e.actualitza_estat(cfg, est, [self.sessio(s, i, "") for i, s in enumerate("XYZ", 1)])
        self.assertEqual(orfes, [self.D])

    def test_sessions_bg_no_s_assignen(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        self.e.actualitza_estat(cfg, est, [self.sessio("BG", 3, "", interactiva=False)])
        self.assertEqual(est["tabs"], {})


class Pla(Base):
    def test_viva_repren_recupera_nova(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        t0, t1 = cfg["finestra"][0]["pestanya"][1:]
        self.assertEqual(self.e.pla(cfg, est, [], t0)[0], "nova")
        self.transcripcio(self.D, "VELLA", mtime=time.time() - 100)
        self.assertEqual(self.e.pla(cfg, est, [], t0)[:3:2], ("recupera", "VELLA"))
        est["tabs"][t0["clau_tab"]] = {"sessionId": "A"}
        self.transcripcio(self.D, "A")
        self.assertEqual(self.e.pla(cfg, est, [], t0)[:3:2], ("repren", "A"))
        self.assertEqual(self.e.pla(cfg, est, [self.sessio("A", 1, t0["clau_tab"])], t0)[0], "viva")
        # T1 no pot recuperar la conversa que és de T0.
        self.assertEqual(self.e.pla(cfg, est, [], t1)[2], "VELLA")

    def test_no_recupera_una_sessio_viva_en_segon_pla(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        t0 = cfg["finestra"][0]["pestanya"][1]
        self.transcripcio(self.D, "BG")
        self.assertEqual(self.e.pla(cfg, est, [self.sessio("BG", 3, "", interactiva=False)], t0)[0], "nova")

    def test_transcripcio_d_una_altra_carpeta_no_compta(self):
        cfg, est = self.dues_pestanyes(), self.e.llegeix_estat()
        t0 = cfg["finestra"][0]["pestanya"][1]
        est["tabs"][t0["clau_tab"]] = {"sessionId": "ALTRA"}
        self.transcripcio(self.D2, "ALTRA")
        self.assertNotEqual(self.e.pla(cfg, est, [], t0)[0], "repren")


class Generacio(Base):
    def test_yaml_i_fitxers_aliens(self):
        cfg = self.dues_pestanyes()
        alie = os.path.join(self.e.LC_DIR, "espai-a.yaml")
        with open(alie, "w") as f:
            f.write("---\nname: meu\n")
        self.e.cmd_genera(type("A", (), {"silencios": True})())
        with open(alie) as f:
            self.assertEqual(f.read(), "---\nname: meu\n")
        with open(os.path.join(self.e.LC_DIR, "espai-tot.yaml")) as f:
            txt = f.read()
        self.assertTrue(txt.startswith(self.e.LC_MARCA))
        self.assertIn('name: "Espai · Tot"', txt)
        self.assertIn(f"export ESPAI_TAB='{self.D}#1'", txt)
        self.assertNotIn(f"'{self.D}#2'", txt)

    def test_esborra_nomes_els_seus_fitxers_obsolets(self):
        self.dues_pestanyes()
        vell = os.path.join(self.e.LC_DIR, "espai-vella.yaml")
        with open(vell, "w") as f:
            f.write(self.e.LC_MARCA + "\n---\nname: x\n")
        self.e.cmd_genera(type("A", (), {"silencios": True})())
        self.assertFalse(os.path.exists(vell))


class Arguments(Base):
    def test_filtra_args(self):
        keep, desc = self.e.filtra_args(["claude", "--dangerously-skip-permissions", "--continue", "--effort",
                                         "ultracode", "--remote-control", "Agent web", "fes la tasca X"])
        self.assertEqual(keep, ["--dangerously-skip-permissions", "--effort", "ultracode",
                                "--remote-control", "Agent web"])
        self.assertIn("fes la tasca X", desc)


if __name__ == "__main__":
    unittest.main()
