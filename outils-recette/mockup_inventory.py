#!/usr/bin/env python3
"""Inventaire d'un lot de maquettes : ecrans, titres, et GRAPHE DE NAVIGABILITE.

CANDIDAT (passe p6, 12/08/2026), non deploye. Cible proposee si Loic tranche pour :
    ~/.claude/skills/outils-recette/mockup_inventory.py

Repond a la question que `mockup_scan.rb inventory` ne pose pas : au stade maquette,
avant qu'aucune application n'existe, quels ecrans du lot ne sont atteignables par
AUCUN clic depuis le produit ?

Le hub des maquettes (l'index qui liste tous les ecrans) est EXCLU du graphe : c'est
un outil de revue interne, il n'existera pas dans le produit, et l'inclure rend tout
ecran atteignable en un clic.

LIMITE MESUREE : un chemin porte par un <button> Stimulus est invisible ici. La sortie
est une LISTE DE CANDIDATS a trancher au navigateur, jamais un verdict.

Usage: mockup_inventory.py <base_url> <routes_file> <hub_path> <out.md>
  routes_file : `bin/rails routes | grep mockups | awk '{print $2, $3}' | grep GET | sort -u`
"""
import sys, re, urllib.request, urllib.parse, json
from html.parser import HTMLParser

base, routes_file, hub, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

paths = []
for line in open(routes_file):
    line = line.strip()
    if not line.startswith("GET "):
        continue
    p = line[4:].replace("(.:format)", "")
    p = p.replace(":id", "1")
    if p not in paths:
        paths.append(p)


class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = None
        self.h1 = []
        self._in_title = False
        self._in_h1 = 0
        self.links = []          # (href, texte)
        self._cur_a = None
        self._a_text = []
        self.buttons = []
        self._in_btn = 0
        self._btn_text = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self._in_title = True
        elif tag == "h1":
            self._in_h1 += 1
        elif tag == "a":
            self._cur_a = a.get("href", "")
            self._a_text = []
        elif tag == "button":
            self._in_btn += 1
            self._btn_text = []

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        elif tag == "h1":
            self._in_h1 = max(0, self._in_h1 - 1)
        elif tag == "a" and self._cur_a is not None:
            txt = re.sub(r"\s+", " ", "".join(self._a_text)).strip()
            self.links.append((self._cur_a, txt))
            self._cur_a = None
        elif tag == "button" and self._in_btn:
            self._in_btn -= 1
            txt = re.sub(r"\s+", " ", "".join(self._btn_text)).strip()
            if txt:
                self.buttons.append(txt)

    def handle_data(self, d):
        if self._in_title:
            self.title = (self.title or "") + d
        if self._in_h1:
            self.h1.append(d)
        if self._cur_a is not None:
            self._a_text.append(d)
        if self._in_btn:
            self._btn_text.append(d)


pages = {}
for p in paths:
    url = base + p
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            html = r.read().decode("utf-8", "replace")
        code = 200
    except Exception as e:
        pages[p] = {"code": str(e), "title": "", "h1": "", "links": [], "buttons": []}
        continue
    par = P()
    par.feed(html)
    links = []
    for href, txt in par.links:
        if href.startswith("/mockups") or href.startswith("/demo") or href.startswith("/style-guide"):
            href = href.split("#")[0].split("?")[0]
            links.append((href, txt))
    pages[p] = {
        "code": code,
        "title": re.sub(r"\s+", " ", (par.title or "")).strip(),
        "h1": re.sub(r"\s+", " ", "".join(par.h1)).strip()[:120],
        "links": links,
        "buttons": sorted(set(par.buttons))[:40],
    }

# graphe entrant, HORS hub
inbound = {p: [] for p in pages}
for src, d in pages.items():
    if src == hub:
        continue
    for href, txt in d["links"]:
        tgt = href
        # normalise les ids
        tgt_n = re.sub(r"/\d+(/|$)", r"/1\1", tgt)
        for cand in (tgt, tgt_n):
            if cand in inbound and cand != src:
                inbound[cand].append((src, txt or "(sans libelle)"))
                break

with open(out, "w") as fh:
    fh.write(f"# Inventaire du lot de maquettes — {base}\n\n")
    fh.write(f"{len(pages)} ecrans routes. Le hub `{hub}` est exclu du graphe de navigabilite\n")
    fh.write("(c'est un index de revue interne, il n'existera pas dans le produit).\n\n")
    fh.write("## Ecrans, et QUI y mene (hors hub)\n\n")
    fh.write("| # | URL | Titre / H1 | Liens entrants (ecran source -> libelle du lien) |\n")
    fh.write("|---|-----|------------|--------------------------------------------------|\n")
    for i, (p, d) in enumerate(sorted(pages.items()), 1):
        ins = inbound[p]
        if p == hub:
            cell = "_(hub de revue, exclu)_"
        elif not ins:
            cell = "**AUCUN — atteignable seulement par le hub ou par l'URL**"
        else:
            seen, parts = set(), []
            for s, t in ins:
                k = (s, t)
                if k in seen:
                    continue
                seen.add(k)
                parts.append(f"`{s}` → « {t} »")
            cell = " ; ".join(parts[:8]) + (" ; …" if len(parts) > 8 else "")
        lab = d["h1"] or d["title"]
        fh.write(f"| {i} | `{p}` | {lab} | {cell} |\n")

    fh.write("\n## Liens sortants et boutons, ecran par ecran\n\n")
    for p, d in sorted(pages.items()):
        if p == hub:
            continue
        fh.write(f"### `{p}` — {d['h1'] or d['title']}\n")
        outs = sorted({f"{h} « {t} »" for h, t in d["links"]})
        fh.write(f"- liens sortants ({len(outs)}) : " + ("; ".join(outs) if outs else "_aucun_") + "\n")
        if d["buttons"]:
            fh.write("- boutons (libelles) : " + " | ".join(d["buttons"]) + "\n")
        fh.write("\n")

print(f"{len(pages)} pages -> {out}")
orphans = [p for p in pages if p != hub and not inbound[p]]
print(f"orphelins (aucun lien entrant hors hub) : {len(orphans)}")
for o in sorted(orphans):
    print("  ", o)
