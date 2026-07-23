---
name: brick-user-guide
description: "Genere le guide utilisateur PDF d'une brique (un chapitre par parcours, captures d'ecran annotees) et le publie dans l'espace client (page Documents, type guide). Utilise /brick-user-guide apres une livraison, ou avec /brick-presentation-video (memes sources)."
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

4. **HTML du guide** : UN fichier autonome dans le repertoire de travail,
   images en chemins relatifs, style sobre aligne sur la charte du client
   (couleurs du style_guide). Structure par chapitre :
   - titre du parcours + une phrase d'objectif (« Ce chapitre montre comment
     votre patient s'abonne »)
   - etapes numerotees : instruction (1 phrase imperative) + capture
   - encarts « Bon a savoir » pour les lignes « mentionner » de la recette
   Pied de page : version de la brique + date. Table des matieres en tete.

5. **PDF** : chaine verifiee, zero dependance nouvelle :
   ```bash
   playwright-cli -s=guide-<app> goto "file://$PWD/tmp/brick-user-guide/guide.html"
   playwright-cli -s=guide-<app> pdf    # recuperer le chemin du PDF produit
   playwright-cli -s=guide-<app> close  # TOUJOURS fermer sa session
   ```
   Verifier le PDF : l'ouvrir (extraire 2-3 pages en images), controler que
   les captures sont nettes et que rien ne deborde.

6. **Publication** :
   a. Uploader le PDF sur le Drive du projet (`google_drive_upload_file`),
      dossier du client.
   b. Le lier dans l'espace client :
      ```
      client_document_tool(action: "add", kind: "guide",
        title: "Guide utilisateur — Brique {N}",
        drive_file_id: "<id>", app_id: <id>)
      ```
   Le titre porte le numero de brique : re-publier apres une livraison cree
   le guide de LA brique, l'ancien reste consultable (remplacer = action
   remove sur l'ancien PUIS add, si l'utilisateur le demande).

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
- [ ] PDF verifie visuellement (nettete, debordements) avant publication
- [ ] Publie en kind "guide" avec titre versionne par brique
- [ ] Session playwright-cli fermee
