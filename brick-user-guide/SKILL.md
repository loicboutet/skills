---
name: brick-user-guide
description: "Genere le guide utilisateur d'une brique (chapitres markdown + captures) et le publie dans l'espace client ou il est rendu NATIVEMENT (page Guide, export PDF navigateur). Utilise /brick-user-guide apres une livraison, ou avec /brick-presentation-video (memes sources)."
---

# Brick User Guide — le guide utilisateur PDF dans l'espace client

Produit un guide PDF que le client consulte dans son espace (page Documents,
section « Guides utilisateur », en tete de page) : un chapitre par parcours,
des captures d'ecran reelles, des instructions pas a pas dans le vocabulaire
du client.

Memes sources que `/brick-presentation-video` — les produire ENSEMBLE quand
c'est possible : un seul travail de scenarisation, deux artefacts.

## Sources et structure (identiques a la video de presentation)

- **`doc/memory/user_journeys.md`** : la structure — un chapitre par parcours.
- **`doc/memory/brick-{N}/recette.md`** : l'exhaustivite, avec la MEME
  classification montrer / mentionner / hors-doc que la video. Les
  « mentionner » deviennent un encart « Bon a savoir » (ex. « chaque role ne
  voit que son perimetre »), les tests techniques restent hors du guide.
- **`doc/memory/acceptance_criteria.md`** : le vocabulaire — on decrit ce qui
  a ete promis, dans les mots du client, jamais le jargon technique.
- **Langue** : celle de l'espace client du projet (meme regle que les videos).

## Production

1. **Plan de chapitres** : le meme que la video si elle existe (reutiliser sa
   matrice de couverture). Sinon le construire pareil et le faire valider.

2. **Repertoire de travail** : `tmp/brick-user-guide/` dans le depot de l'app
   (gitignore par /tmp/*). JAMAIS de repertoire partage entre apps.

3. **Captures d'ecran** : parcourir chaque parcours au clic avec
   `playwright-cli` (session nommee, voir le skill `playwright`) et capturer
   chaque etape significative :
   ```bash
   playwright-cli -s=guide-<app> open <url-dev-server>
   playwright-cli -s=guide-<app> click <ref>       # avancer dans le parcours
   playwright-cli -s=guide-<app> screenshot        # une capture par etape
   ```
   Une capture = un etat que l'utilisateur doit reconnaitre. Pas de capture
   des etats transitoires. Donnees de demo propres (pas de donnees de test
   moches type "TEST-xxx" visibles — les remplacer avant si besoin).

4. **Source du guide : markdown par chapitre, VERSIONNE** dans
   `doc/memory/guide/chap-NN-<nom>.md` (+ captures dans
   `doc/memory/guide/img/`). C'est la source de verite : diffable, mis a jour
   chapitre par chapitre a chaque livraison, et directement consommable comme
   base de connaissances du futur chatbot (le markdown se lit mieux que le
   HTML et infiniment mieux qu'un PDF extrait). Puis assembler en UN HTML
   autonome (images embarquees, style sobre aligne sur la charte du
   style_guide) dans le repertoire de travail. Structure par chapitre :
   - titre du parcours + une phrase d'objectif (« Ce chapitre montre comment
     votre patient s'abonne »)
   - etapes numerotees : instruction (1 phrase imperative) + capture
   - encarts « Bon a savoir » pour les lignes « mentionner » de la recette
   Pied de page : version de la brique + date. Table des matieres en tete.

5. **Publication : le guide est RENDU NATIVEMENT dans l'espace client**
   (page /external/guide : sommaire, un chapitre par page, export PDF via
   l'impression navigateur). On ne genere PAS de PDF et on ne passe PAS par
   le Drive : un seul POST multipart idempotent, qui remplace tout le guide :

   ```bash
   cd "$APP_DIR"
   MCP_TOKEN=$(python3 -c "import json;a=json.load(open('.mcp.json'))['mcpServers']['nexrai']['args'];print(a[a.index('--header')+1].replace('Authorization: Bearer ',''))")
   NEXRAI_URL=$(python3 -c "import json;print(json.load(open('.nexrai/binding.json'))['nexrai_url'])")
   APP_ID=$(python3 -c "import json;print(json.load(open('.nexrai/binding.json'))['id'])")

   # chapters.json : [{"position":1,"slug":"demarrer","title":"...","body_md":"..."}, ...]
   # (les body_md sont exactement les fichiers doc/memory/guide/chap-*.md)
   IMGS=$(for f in doc/memory/guide/img/*.png; do printf -- "-F images[]=@%s " "$f"; done)
   curl -sf -X POST "$NEXRAI_URL/api/v1/apps/$APP_ID/guide" \
     -H "Authorization: Bearer $MCP_TOKEN" \
     -F "title=Guide utilisateur" -F "brick=Brique {N}" \
     -F "chapters=<tmp/brick-user-guide/chapters.json" \
     $IMGS
   ```

   La reponse contient l'URL du guide. **VERIFIER le rendu** : ouvrir
   /external/guide avec playwright-cli (connecte en compte client de test si
   dispo, sinon demander a l'utilisateur de verifier), controler qu'un
   chapitre s'affiche avec ses images. Ne jamais afficher MCP_TOKEN.

## Mise a jour a chaque livraison

Le guide se perime a chaque brique livree. La regle : toute livraison qui
change un parcours regenere les chapitres touches (les captures d'ecran
mentent sinon). Les chapitres inchanges se reutilisent tels quels — garder
les HTML/captures par chapitre dans le repertoire de travail du depot.

## Validation gate

- [ ] Un chapitre par parcours, matrice de recette classee (montrer /
      mentionner / hors-doc), toutes les « montrer » illustrees
- [ ] Chaque etape : une instruction imperative + une capture reconnaissable
- [ ] Aucune donnee de test moche visible sur les captures
- [ ] Langue de l'espace client, vocabulaire du client (zero jargon)
- [ ] Publication API reussie (reponse chapters/images aux bons comptes)
- [ ] Rendu verifie sur /external/guide : chapitre affiche AVEC ses images
- [ ] Session playwright-cli fermee
