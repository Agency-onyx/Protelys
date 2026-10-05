#!/usr/bin/env python3
"""
Alimentation des prospects depuis l'API Recherche d'Entreprises.

  python3 scripts/import_sirene.py 93048            # importe Montreuil
  python3 scripts/import_sirene.py 93048 93010 -n   # simulation, rien n'est écrit

Lit SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY dans l'environnement ou dans
.env.local. Ne dépend que de la bibliothèque standard de Python.

Règle de priorité :
  chaine : plus de 5 établissements ouverts dans le groupe (à éviter)
  A      : déclare au moins un salarié
  B      : a une enseigne
  C      : le reste
"""
import argparse, json, os, re, sys, time, urllib.parse, urllib.request
from collections import Counter

API = "https://recherche-entreprises.api.gouv.fr/search"
NAF = ["56.10A", "56.10C", "56.30Z", "56.21Z", "55.10Z", "10.71C"]
SEUIL_CHAINE = 5
INDICES = {"B": "bis", "BIS": "bis", "T": "ter", "TER": "ter", "Q": "quater", "QUATER": "quater"}


# ---------------------------------------------------------------- outils
def charger_env():
    racine = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    chemin = os.path.join(racine, ".env.local")
    if os.path.exists(chemin):
        for ligne in open(chemin, encoding="utf-8"):
            ligne = ligne.strip()
            if ligne and not ligne.startswith("#") and "=" in ligne:
                k, v = ligne.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))


def get_json(url, essais=5):
    for i in range(essais):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                time.sleep(2 * (i + 1))
                continue
            raise
        except urllib.error.URLError:
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"échec après {essais} essais : {url}")


def decouper_adresse(adresse, code_postal):
    """'12 BIS RUE DE PARIS 93100 MONTREUIL' -> (12, 'bis', 'RUE DE PARIS', None)"""
    a = re.sub(r"\s+", " ", (adresse or "").upper()).strip()
    if code_postal and f" {code_postal} " in f" {a} ":
        a = a[: f" {a} ".index(f" {code_postal} ")].strip()
    m = re.search(r"(?:^|\s)(\d{1,4})(?:\s?(BIS|TER|QUATER|B|T|Q))?\s+(\D.*)$", a)
    if not m:
        return None, None, a or "SANS VOIE", None
    complement = a[: m.start()].strip() or None
    numero = int(m.group(1))
    indice = INDICES.get(m.group(2)) if m.group(2) else None
    voie = m.group(3).strip()
    return numero, indice, voie, complement


def nombre(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def priorite(unite, etab):
    ouverts = unite.get("nombre_etablissements_ouverts") or unite.get("nombre_etablissements") or 1
    if ouverts > SEUIL_CHAINE:
        return "chaine"
    tranche = etab.get("tranche_effectif_salarie")
    if etab.get("caractere_employeur") == "O" or (tranche and tranche not in ("NN", "00")):
        return "A"
    if etab.get("liste_enseignes") or etab.get("nom_commercial"):
        return "B"
    return "C"


# ---------------------------------------------------------------- collecte
def collecter(code_insee):
    vus = {}
    non_diffusibles = set()
    commune = None
    for naf in NAF:
        page, pages = 1, 1
        while page <= pages:
            q = urllib.parse.urlencode({
                "code_commune": code_insee, "activite_principale": naf,
                "etat_administratif": "A", "per_page": 25, "page": page,
            })
            d = get_json(f"{API}?{q}")
            pages = d.get("total_pages") or 0
            for u in d.get("results", []):
                for e in u.get("matching_etablissements") or []:
                    if e.get("commune") != code_insee or e.get("etat_administratif") != "A":
                        continue
                    if e.get("activite_principale") not in NAF:
                        continue
                    if "NON-DIFFUSIBLE" in (e.get("adresse") or "") or e.get("statut_diffusion_etablissement") == "P":
                        non_diffusibles.add(e["siret"])
                        continue
                    numero, indice, voie, complement = decouper_adresse(e.get("adresse"), e.get("code_postal"))
                    enseignes = e.get("liste_enseignes") or []
                    commune = commune or {"code_insee": code_insee, "nom": e.get("libelle_commune"),
                                          "code_postal": e.get("code_postal")}
                    vus[e["siret"]] = {
                        "siret": e["siret"], "siren": u["siren"],
                        "nom": u.get("nom_complet") or u.get("nom_raison_sociale") or "?",
                        "enseigne": (enseignes[0] if enseignes else None) or e.get("nom_commercial"),
                        "naf": e["activite_principale"],
                        "_voie": voie, "numero": numero, "indice_repetition": indice,
                        "complement_adresse": complement, "code_postal": e.get("code_postal"),
                        "priorite": priorite(u, e),
                        "tranche_effectif": e.get("tranche_effectif_salarie"),
                        "nb_etablissements_groupe": u.get("nombre_etablissements_ouverts"),
                        "latitude": nombre(e.get("latitude")),
                        "longitude": nombre(e.get("longitude")),
                    }
            page += 1
            time.sleep(0.16)   # l'API tolère 7 requêtes par seconde
    return commune, list(vus.values()), len(non_diffusibles)


# ---------------------------------------------------------------- écriture
class Supabase:
    def __init__(self):
        self.url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
        cle = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        self.h = {"apikey": cle, "Authorization": f"Bearer {cle}", "Content-Type": "application/json"}

    def appel(self, methode, chemin, corps=None, prefer=None):
        h = dict(self.h)
        if prefer:
            h["Prefer"] = prefer
        req = urllib.request.Request(self.url + chemin, method=methode, headers=h,
                                     data=json.dumps(corps).encode() if corps is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                txt = r.read()
                return json.loads(txt) if txt else None
        except urllib.error.HTTPError as e:
            sys.exit(f"Erreur Supabase {e.code} sur {chemin} : {e.read().decode()[:500]}")

    def upsert(self, table, lignes, conflit, retour=False):
        out = []
        for i in range(0, len(lignes), 500):
            r = self.appel("POST", f"/{table}?on_conflict={conflit}", lignes[i:i + 500],
                           prefer="resolution=merge-duplicates,return=" + ("representation" if retour else "minimal"))
            out += r or []
        return out


def ecrire(sb, commune, etabs):
    code = commune["code_insee"]
    dep = code[:3] if code.startswith("97") else code[:2]
    sb.upsert("communes", [{**commune, "departement": dep,
                            "importee_le": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}], "code_insee")
    voies = sorted({e["_voie"] for e in etabs})
    rues = sb.upsert("rues", [{"code_insee": code, "nom_voie": v} for v in voies], "code_insee,nom_voie", retour=True)
    id_rue = {r["nom_voie"]: r["id"] for r in rues}
    lignes = []
    for e in etabs:
        l = {k: v for k, v in e.items() if not k.startswith("_")}
        l["rue_id"] = id_rue[e["_voie"]]
        l["actif_sirene"] = True
        l["maj_sirene_le"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        lignes.append(l)
    sb.upsert("etablissements", lignes, "siret")
    fermes = sb.appel("POST", "/rpc/marquer_etablissements_inactifs",
                      {"p_code_insee": code, "p_sirets": [e["siret"] for e in etabs]})
    return len(voies), fermes


# ---------------------------------------------------------------- main
def main():
    p = argparse.ArgumentParser(description="Importe les prospects d'une ou plusieurs communes.")
    p.add_argument("communes", nargs="+", help="codes INSEE (ex. 93048 pour Montreuil)")
    p.add_argument("-n", "--simulation", action="store_true", help="n'écrit rien, affiche le bilan")
    a = p.parse_args()
    charger_env()
    sb = None if a.simulation else Supabase()
    for code in a.communes:
        commune, etabs, caches = collecter(code)
        if not etabs:
            print(f"{code} : aucun établissement trouvé")
            continue
        prio = Counter(e["priorite"] for e in etabs)
        a_visiter = sum(1 for e in etabs if e["priorite"] != "chaine")
        print(f"\n{commune['nom']} ({code}) : {len(etabs)} établissements, {a_visiter} à visiter")
        print("  priorités : " + ", ".join(f"{k} {prio[k]}" for k in ("A", "B", "C", "chaine")))
        top = Counter(e["_voie"] for e in etabs if e["priorite"] != "chaine").most_common(5)
        print("  rues les plus denses : " + ", ".join(f"{v} ({n})" for v, n in top))
        if caches:
            print(f"  {caches} établissements à adresse non diffusible, ignorés")
        sans_num = sum(1 for e in etabs if e["numero"] is None)
        if sans_num:
            print(f"  {sans_num} adresses sans numéro (placées en fin de rue)")
        if sb:
            nb_rues, fermes = ecrire(sb, commune, etabs)
            print(f"  écrit : {nb_rues} rues, {len(etabs)} établissements, {fermes or 0} fermés depuis le dernier import")


if __name__ == "__main__":
    main()
