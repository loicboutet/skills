#!/usr/bin/env python3
"""Score d'une CHARTE (mode creation) : couverture + tracabilite.

Usage: charte_score.py <candidate_dir> [<candidate_dir> ...]
Attend <candidate_dir>/charte/{tailwind.config.js,style_guide.html[,design_tokens.md]}

Deux mesures independantes :
  - COUVERTURE /24 : ce qu'une charte doit couvrir pour qu'un projet reel tienne
    (couleurs et declinaisons, echelle typo, rythme, rayons, bordures, elevation,
    etats, densite de tableau, variantes de badge...). Miroir du gate de couverture
    du mode extraction.
  - TRACABILITE % : part des tokens definis dans tailwind.config.js qui portent une
    ligne valide dans design_tokens.md (origine dans une liste fermee + justification).
"""
import sys, os, json, re

ORIGINES = ["brief", "contraste", "metier", "métier", "systeme", "système",
            "accessibilite", "accessibilité", "convention"]


# --------------------------------------------------------------------------- utils
def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def strip_comments(js):
    js = re.sub(r"/\*.*?\*/", " ", js, flags=re.S)
    js = re.sub(r"(?m)//.*$", " ", js)
    return js


def block(js, key):
    """Extrait le contenu {...} de `key:` par appariement d'accolades."""
    m = re.search(r"\b" + re.escape(key) + r"\s*:\s*\{", js)
    if not m:
        return None
    i = m.end() - 1
    depth = 0
    for j in range(i, len(js)):
        if js[j] == "{":
            depth += 1
        elif js[j] == "}":
            depth -= 1
            if depth == 0:
                return js[i + 1:j]
    return None


def leaves(body, prefix=""):
    """Aplati un objet JS simple en {chemin.pointe: valeur}."""
    out = {}
    if body is None:
        return out
    i = 0
    n = len(body)
    while i < n:
        m = re.compile(r"""["']?([A-Za-z0-9_$-]+)["']?\s*:\s*""").search(body, i)
        if not m:
            break
        key = m.group(1)
        j = m.end()
        while j < n and body[j] in " \t\n":
            j += 1
        if j >= n:
            break
        path = f"{prefix}{key}"
        if body[j] == "{":
            depth = 0
            k = j
            while k < n:
                if body[k] == "{":
                    depth += 1
                elif body[k] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            out.update(leaves(body[j + 1:k], path + "."))
            i = k + 1
        elif body[j] == "[":
            depth = 0
            k = j
            while k < n:
                if body[k] == "[":
                    depth += 1
                elif body[k] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            out[path] = body[j:k + 1]
            i = k + 1
        else:
            k = j
            depth = 0
            while k < n and not (body[k] in ",\n" and depth == 0):
                if body[k] in "([{":
                    depth += 1
                elif body[k] in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                k += 1
            out[path] = body[j:k].strip()
            i = k + 1
    return out


def sections(html):
    """Decoupe le style guide en sections (titre -> markup jusqu'au titre suivant)."""
    parts = []
    for m in re.finditer(r"<h[1-4][^>]*>(.*?)</h[1-4]>", html, flags=re.S | re.I):
        parts.append((m.start(), re.sub(r"<[^>]+>", " ", m.group(1)).strip().lower()))
    out = []
    for idx, (pos, title) in enumerate(parts):
        end = parts[idx + 1][0] if idx + 1 < len(parts) else len(html)
        out.append((title, html[pos:end]))
    return out


def sec(html, *words):
    """Concatene les sections dont le titre contient un des mots."""
    hit = [body for title, body in sections(html) if any(w in title for w in words)]
    return "\n".join(hit)


def has(txt, *pats):
    return all(re.search(p, txt, flags=re.I) for p in pats)


def any_of(txt, *pats):
    return any(re.search(p, txt, flags=re.I) for p in pats)


def count_of(txt, pat):
    return len(re.findall(pat, txt, flags=re.I))


# --------------------------------------------------------------------------- couverture
def coverage(tw, sg, dt):
    js = strip_comments(tw)
    colors = leaves(block(js, "colors"))
    fsizes = leaves(block(js, "fontSize"))
    ffam = leaves(block(js, "fontFamily"))
    fweight = leaves(block(js, "fontWeight"))
    spacing = leaves(block(js, "spacing"))
    radius = leaves(block(js, "borderRadius"))
    bwidth = leaves(block(js, "borderWidth"))
    shadow = leaves(block(js, "boxShadow"))
    lh = leaves(block(js, "lineHeight"))
    all_txt = sg + "\n" + dt

    # familles de couleur = premier segment des chemins a >= 2 niveaux
    fams = {}
    for path in colors:
        seg = path.split(".")
        if len(seg) >= 2:
            fams.setdefault(seg[0], set()).add(".".join(seg[1:]))
    hexes = [v for v in colors.values() if re.search(r"#[0-9a-f]{3,8}", str(v), re.I)]

    # Neutralite mesuree sur la VALEUR, jamais sur le nom : une charte creee nomme ses
    # neutres d'apres le metier (ciment, platre, calque, craie), un nom ne dit rien.
    def rgb(v):
        m = re.search(r"#([0-9a-f]{6})\b", str(v), re.I)
        if m:
            h = m.group(1)
            return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
        m = re.search(r"#([0-9a-f]{3})\b", str(v), re.I)
        if m:
            return tuple(int(c * 2, 16) for c in m.group(1))
        return None

    def chroma(v):
        c = rgb(v)
        return None if not c else max(c) - min(c)

    def light(v):
        c = rgb(v)
        return None if not c else (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])

    fam_vals = {}
    for path, v in colors.items():
        seg = path.split(".")
        if len(seg) >= 2:
            fam_vals.setdefault(seg[0], []).append(v)

    def fam_is_neutral(k):
        chs = [chroma(v) for v in fam_vals.get(k, []) if chroma(v) is not None]
        return bool(chs) and sum(1 for c in chs if c <= 34) >= max(1, len(chs) * 0.6)

    neutral_fam = max((len(v) for k, v in fams.items() if fam_is_neutral(k)), default=0)
    non_neutral_fams = [k for k in fams if not fam_is_neutral(k)]
    clairs = [v for v in colors.values() if (light(v) or 0) >= 216]
    etats_kw = {
        "succes": r"succ[eè]s|success|valide|ok\b|vert-ok|positif",
        "alerte": r"alerte|warning|attention|avert|vigil",
        "erreur": r"erreur|error|danger|destructive|critique|alarme",
        "info":   r"\binfo\b|information|neutre-info|conseil",
    }
    color_names = " ".join(colors.keys())
    etats_nommes = [k for k, p in etats_kw.items() if re.search(p, color_names, re.I)]
    # Correctif 08/2026 (meme principe que la neutralite) : on mesure l'USAGE, pas le NOM.
    # Une charte creee nomme ses etats d'apres le metier (`ouvert/veille/ferme`,
    # `varech/rouille/fermeture`) : chercher "succes|alerte|erreur|info" dans les noms de
    # tokens sous-estimait toutes les chartes ancrees metier. Un etat compte aussi quand le
    # style guide MONTRE le mot d'etat a cote d'une classe qui consomme un token couleur.
    fam_re = "|".join(sorted((re.escape(k) for k in fams), key=len, reverse=True)) or r"(?!x)x"
    token_use = re.compile(r"(?:bg|text|border|ring|from|to|via|fill|stroke|decoration)"
                           r"-(?:" + fam_re + r")[-.\w]*", re.I)

    def etat_utilise(pat):
        for m in re.finditer(pat, all_txt, re.I):
            if token_use.search(all_txt[max(0, m.start() - 400): m.end() + 400]):
                return True
        return False

    etats_usage = [k for k, p in etats_kw.items()
                   if k not in etats_nommes and etat_utilise(p)]
    etats_found = etats_nommes + etats_usage
    surfaces = [k for k in colors if re.search(r"surface|fond|bg|background|papier|paper|"
                                               r"carte|card|canvas|page|panneau", k, re.I)]

    checks = {}
    # --- couleur
    checks["c1_dominante_declinaisons"] = (
        max((len(v) for k, v in fams.items() if not fam_is_neutral(k)), default=0) >= 3,
        "une famille de marque avec >= 3 declinaisons")
    checks["c2_accent_distinct"] = (
        len(non_neutral_fams) >= 2 or bool(re.search(r"accent", color_names, re.I)),
        "un accent distinct de la dominante")
    checks["c3_neutres"] = (neutral_fam >= 4 or len(hexes) >= 12,
                            "echelle de neutres >= 4 crans")
    checks["c4_surfaces"] = (len(surfaces) >= 2 or neutral_fam >= 5 or len(clairs) >= 2,
                             "au moins 2 niveaux de surface (page vs carte)")
    checks["c5_etats_semantiques"] = (len(etats_found) >= 3,
                                      "3 couleurs d'etat sur 4 (succes/alerte/erreur/info)")
    etats_detail = {"par_nom": etats_nommes, "par_usage": etats_usage}
    # --- typo
    checks["t1_familles"] = (len(ffam) >= 2, "au moins 2 familles (display + body, ou + mono)")
    checks["t2_echelle"] = (len(fsizes) >= 5, "echelle typo >= 5 crans nommes")
    checks["t3_interlignes"] = (
        sum(1 for v in fsizes.values() if "lineheight" in str(v).lower().replace("-", "")) >= 3
        or len(lh) >= 3, "interlignes portes par l'echelle (>= 3)")
    checks["t4_graisses"] = (len(fweight) >= 3 or count_of(all_txt, r"font-(?:thin|extralight|light|"
                             r"normal|medium|semibold|bold|extrabold|black)") >= 3,
                             "au moins 3 graisses definies")
    checks["t5_chiffres"] = (any_of(all_txt, r"tabular-nums|font-variant-numeric|tabular"),
                             "traitement des chiffres (tabular-nums / mono)")
    # --- rythme
    checks["r1_espacement"] = (len(spacing) >= 5 or
                               any_of(dt + sg, r"(?:echelle|échelle|rythme|grille)\s+d.espacement")
                               and count_of(dt + sg, r"\b\d{1,3}\s?px\b") >= 5,
                               "echelle d'espacement explicite >= 5 crans")
    checks["r2_rayons"] = (len(radius) >= 3, "echelle de rayons >= 3 crans")
    checks["r3_bordures"] = (len(bwidth) >= 2 or count_of(all_txt, r"border-(?:0|2|4|8)\b") >= 2,
                             "au moins 2 epaisseurs de bordure")
    checks["r4_elevation"] = (len(shadow) >= 3, "echelle d'elevation >= 3 niveaux")
    # --- etats et composants demontres dans le style guide
    btn = sec(sg, "bouton", "button") or sg
    checks["e1_bouton_etats"] = (
        any_of(btn, r"hover") and any_of(btn, r"focus") and any_of(btn, r"disabled|desactiv|désactiv"),
        "bouton : hover + focus + disabled montres")
    checks["e2_focus_visible"] = (any_of(sg, r"focus-visible|focus:ring|outline-offset|anneau de focus"),
                                  "focus visible documente")
    form = sec(sg, "formulaire", "form", "champ", "saisie") or sg
    checks["e3_champ_erreur"] = (
        any_of(form, r"erreur|error|invalid") and any_of(form, r"<input|<textarea"),
        "champ en erreur avec son message")
    checks["e4_controles"] = (
        any_of(form, r'type="checkbox"|type=.radio|<select') and
        any_of(form, r"appearance-none|accent-|custom|stylis"),
        "select / checkbox / radio stylises (pas natifs bruts)")
    checks["e5_etat_vide"] = (
        any_of(sg, r"[eé]tat[s]?\s+vide|empty\s*state") and
        any_of(sec(sg, "vide", "empty") or sg, r"<button|<a\b"),
        "etat vide avec une phrase et une action")
    alerts = sec(sg, "alerte", "alert", "flash", "message", "notification") or sg
    checks["e6_alertes"] = (
        any_of(alerts, r"succ[eè]s|success") and any_of(alerts, r"erreur|error|danger"),
        "au moins 2 tons d'alerte (succes + erreur)")
    badges = sec(sg, "badge", "etiquette", "étiquette", "tag", "pastille", "statut") or sg
    # On compte les VARIANTES rendues dans la section, pas les occurrences du mot :
    # une charte peut nommer ses badges par leur sens ("Posee", "En retard").
    checks["e7_badges"] = (
        any_of(sg, r"badge|[eé]tiquette|pastille|statut|chip\b|jeton") and
        (count_of(badges, r"<span[^>]*class") >= 3
         or count_of(badges, r"badge|[eé]tiquette|pastille|chip\b") >= 3),
        "badge avec >= 3 variantes semantiques")
    tab = sec(sg, "tableau", "table", "donnee", "données", "liste") or sg
    checks["e8_tableau_densite"] = (
        any_of(tab, r"<table|role=\"table\"|grille de donn") and
        any_of(all_txt, r"densit|compact|dense|confortable|a[eé]r[eé]|hauteur de ligne|py-1\.5|py-2\b"),
        "tableau avec une densite documentee")
    checks["e9_navigation"] = (
        any_of(sg, r"navigation|menu|onglet|tab\b") and
        any_of(sec(sg, "navigation", "menu", "onglet", "tab") or sg,
               r"actif|active|aria-current|courant|sélectionn|selectionn"),
        "navigation : item actif vs inactif")
    checks["e10_liens"] = (
        any_of(sg, r"lien|link") and
        any_of(sec(sg, "lien", "link") or sg, r"hover|underline|soulign"),
        "liens et leurs etats")
    checks["e11_signature"] = (
        any_of(all_txt, r"signature|[eé]l[eé]ment signature|motif signature") and
        any_of(all_txt, r"r[eè]gle d.usage|s.emploie|usage :|quand l.utiliser|jamais"),
        "element signature nomme avec sa regle d'usage")
    # --- composants de l'ECRAN DENSE (les six trous mesures au banc de stress)
    tabsec = sec(sg, "tableau", "table", "donnee", "données", "liste", "ligne") or sg
    checks["d1_pagination"] = (
        any_of(sg, r"pagination|page suivante|next page|pages? \d") and
        count_of(sec(sg, "pagination", "page") or sg, r"<a\b|<button") >= 3,
        "pagination avec son compte d'elements")
    checks["d2_ligne_etats"] = (
        any_of(tabsec, r"hover:|survol|s[eé]lectionn|aria-selected|ligne active|:hover"),
        "survol / selection d'une ligne de tableau")
    checks["d3_textarea"] = (any_of(sg, r"<textarea"), "zone de texte multiligne")
    checks["d4_champ_date"] = (
        any_of(sg, r'type="date"|champ de date|date-picker|s[eé]lecteur de date|calendrier'),
        "champ de date (le natif brut etant interdit)")
    checks["d5_metadonnees"] = (
        any_of(sg, r"<dl\b") or any_of(sg, r"m[eé]tadonn|libell[eé] / valeur|fiche de d[eé]tail"),
        "liste de metadonnees (libelle / valeur)")
    checks["d6_filtres"] = (
        any_of(sg, r"filtre|filtrer|recherche") and
        any_of(sec(sg, "filtre", "recherche") or sg, r"<select|<input"),
        "barre de filtres")

    checks["e12_contraste_verifie"] = (
        count_of(all_txt, r"\d+[\.,]\d+\s*:\s*1") >= 3 or count_of(all_txt, r"AA\b") >= 2,
        "contrastes chiffres (>= 3 ratios ou AA verifie)")

    ok = sum(1 for v, _ in checks.values() if v)
    return {
        "couverture_n": ok, "couverture_total": len(checks),
        "couverture_pct": round(100.0 * ok / len(checks), 1),
        "manques": [f"{k} ({d})" for k, (v, d) in checks.items() if not v],
        "detail": {k: bool(v) for k, (v, d) in checks.items()},
        "etats": etats_detail,
        "inventaire": {"couleurs": len(colors), "familles": len(fams), "fontSize": len(fsizes),
                       "fontFamily": len(ffam), "fontWeight": len(fweight), "spacing": len(spacing),
                       "borderRadius": len(radius), "borderWidth": len(bwidth), "boxShadow": len(shadow)},
    }


# --------------------------------------------------------------------------- tracabilite
def traceability(tw, dt):
    js = strip_comments(tw)
    defined = {}
    for key, pre in [("colors", ""), ("fontSize", "fontSize."), ("fontFamily", "fontFamily."),
                     ("fontWeight", "fontWeight."), ("spacing", "spacing."),
                     ("borderRadius", "radius."), ("borderWidth", "border."),
                     ("boxShadow", "shadow."), ("lineHeight", "lineHeight.")]:
        b = block(js, key)
        if b:
            for p in leaves(b, pre):
                defined[p] = key
    if not defined:
        return {"tokens_definis": 0, "traces": 0, "tracabilite_pct": 0.0,
                "lignes_dt": 0, "lignes_valides": 0, "orphelines": 0}

    rows = []
    for line in dt.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or re.match(r"^[-: ]+$", cells[0]):
            continue
        name = re.sub(r"`|\*", "", cells[0]).strip()
        if not name or name.lower() in ("token", "nom", "jeton"):
            continue
        rest = " | ".join(cells[1:])
        # origine valide : un mot de la liste fermee (mode creation) OU un fichier:ligne
        # (mode extraction) — le contrat de tracabilite est le meme, la source differe.
        origine_ok = (any(re.search(r"\b" + o, rest, re.I) for o in ORIGINES)
                      or bool(re.search(r"[\w./-]+\.(?:css|tsx?|jsx?|html|json|md|pdf|png|svg):\d+", rest, re.I)))
        just = max(cells[1:], key=len)
        rows.append({"name": name, "ok": origine_ok and len(just) >= 15, "rest": rest})

    def norm(n):
        n = n.lower().replace("colors.", "").replace("theme.", "").replace("extend.", "")
        n = re.sub(r"[\s'\"]", "", n)
        return n

    # Un token peut etre nomme par son chemin de config (`fontSize.sm`) ou par la classe
    # utilitaire qu'il produit (`text-sm`) : les deux nomment le meme token.
    PREFIX = {"text-": ["fontsize."], "font-": ["fontfamily.", "fontweight."],
              "rounded-": ["radius."], "shadow-": ["shadow."], "border-": ["border."],
              "leading-": ["lineheight."], "gap-": ["spacing."], "space-": ["spacing."],
              "p-": ["spacing."], "m-": ["spacing."], "w-": ["spacing."], "h-": ["spacing."]}

    def aliases(name):
        n = norm(name)
        out = {n}
        for pre, targets in PREFIX.items():
            if n.startswith(pre):
                out |= {t + n[len(pre):] for t in targets}
        return out

    traced = set()
    used_rows = set()
    row_alias = [aliases(r["name"]) if r["ok"] else set() for r in rows]
    for path, _ in defined.items():
        np = norm(path)
        tail = ".".join(np.split(".")[-2:])
        leaf = np.split(".")[-1]
        for i, r in enumerate(rows):
            if not r["ok"]:
                continue
            nr = norm(r["name"])
            als = row_alias[i]
            if np in als or nr == np or any(a == np or np.endswith("." + a) for a in als) \
               or nr.endswith("." + tail) or nr == tail \
               or (len(leaf) > 3 and nr.endswith("." + leaf)):
                traced.add(path)
                used_rows.add(i)
                break
    return {"tokens_definis": len(defined), "traces": len(traced),
            "tracabilite_pct": round(100.0 * len(traced) / len(defined), 1),
            "lignes_dt": len(rows), "lignes_valides": sum(1 for r in rows if r["ok"]),
            "orphelines": len([i for i in range(len(rows)) if i not in used_rows]),
            "non_traces": [p for p in defined if p not in traced][:20]}


def score_dir(d):
    ch = os.path.join(d, "charte")
    if not os.path.isdir(ch):
        ch = d
    twp = None
    for cand in ("tailwind.config.js", "tailwind.config.mjs", "tailwind.config.cjs"):
        if os.path.exists(os.path.join(ch, cand)):
            twp = os.path.join(ch, cand)
            break
    sgp = os.path.join(ch, "style_guide.html")
    dtp = os.path.join(ch, "design_tokens.md")
    tw = read(twp) if twp else ""
    sg = read(sgp)
    dt = read(dtp)
    if not tw and sg:  # config inline dans le style guide
        m = re.search(r"tailwind\.config\s*=\s*\{", sg)
        if m:
            tw = sg[m.start():]
    out = {"candidate": os.path.basename(d.rstrip("/")),
           "artefacts": {"tailwind.config.js": bool(tw), "style_guide.html": bool(sg),
                         "design_tokens.md": bool(dt)}}
    out.update(coverage(tw, sg, dt))
    out["tracabilite"] = traceability(tw, dt)
    return out


if __name__ == "__main__":
    res = [score_dir(a) for a in sys.argv[1:]]
    print(json.dumps(res, ensure_ascii=False, indent=1))
