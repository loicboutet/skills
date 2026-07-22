---
name: brick-mockup-video
description: "Genere UNE video par parcours utilisateur principal des mockups, pour la validation client a distance. Meme execution technique que /brick-video (pipeline, voix, publication). Utilise /brick-mockup-video quand les mockups sont prets a presenter."
---

# Brick Mockup Video — une video PAR parcours utilisateur

Filme les mockups pour la validation client a distance : le client voit chaque
parcours se derouler, commente, et valide sans attendre un call.

## Quand utiliser

- Les mockups d'une brique sont prets (apres `/brick-mockup-review`)
- Le client valide a distance, ou on veut preparer le call de presentation
- AVANT l'implementation : ces videos sont un outil de validation, pas de livraison

## Le principe : 1 video = 1 parcours, jamais une visite guidee

**Interdit : une seule video qui fait le tour de toutes les pages.** Le client
decroche au bout de 90 secondes et ne commente rien. A la place, une video
courte (45-90 s) par parcours utilisateur principal, chacune racontant UNE
histoire : « votre patient s'abonne », « votre admin valide une demande ».

Source des parcours : **`doc/memory/user_journeys.md`** (artefact de la phase
ANALYSIS). Prendre les parcours principaux (typiquement 3 a 6, un par profil x
objectif majeur). Si le fichier manque, les deduire de l'index `/mockups` et
**confirmer la liste avec l'utilisateur avant de filmer** — c'est lui qui sait
ce que le client doit valider en priorite.

## Execution technique : suivre /brick-video

Toutes les regles techniques de `/brick-video` s'appliquent telles quelles —
ne pas les redecouvrir ici, OUVRIR le skill :

- **Repertoire de travail par app** (`tmp/brick-video/` dans le depot, jamais
  `~/demo-video/` partage) — un seul repertoire pour tous les parcours, mais
  ATTENTION : le pipeline ecrit `out/voice.mp3` / `out/output.mp4`, donc les
  parcours se tournent EN SEQUENCE, en archivant chaque resultat avant le
  suivant (`mv out/output.mp4 out/<parcours>.mp4`)
- **Voix par langue** (Rudy FR / `3WqHLnw80rOZqJzW9YRB` EN, `eleven_v3`),
  langue = celle de l'espace client du projet
- **TTS en un seul appel** sous 3000 caracteres — un parcours de 45-90 s fait
  600-1200 caracteres, on est toujours en un appel
- **Regles de scenarisation** : `goto` uniquement au step 0, `waitForUrl` sur
  les navigations, selecteurs verifies via `playwright-cli`, scroll pour le
  contenu sous le fold
- **Publication** : meme endpoint `delivery_video`, derivation de `MCP_TOKEN`
  et `PLATFORM_API_URL` depuis `.mcp.json` / `.nexrai/binding.json`

## Specificites mockups (ce qui CHANGE par rapport a une video de brick)

1. **Cible** : le dev server de l'app, pages sous `/mockups/...`. La navigation
   passe par les liens reels entre mockups (regle de `/brick-mockups` : les
   pages doivent linker entre elles — si un parcours est infranchissable au
   clic, c'est un bug de mockup a corriger AVANT de filmer).
2. **Les formulaires ne creent rien** : donnees fictives dans les controleurs,
   pas de DB. Un submit navigue vers la page mockee suivante, c'est tout.
   Donc pas de reset de donnees, pas de `moveUrl`/`moveStatus` pour les drags
   (utiliser un `hover` + narration a la place si le drag est central).
3. **Narration de validation, pas de livraison.** On presente ce que le client
   POURRA faire, et on l'invite a reagir :
   - « Voici comment votre patient s'abonnera... » (futur, pas accompli)
   - Terminer CHAQUE video par une invitation aux retours via le widget de
     capture present sur les mockups (« cliquez sur la bulle pour commenter
     directement la page »)
   - Ne JAMAIS presenter comme fini ce qui est mocke : pas de « c'est en
     ligne », pas de chiffres presentes comme reels
4. **Scope brique** : si un parcours traverse un element grise « Brique 2 »,
   la narration le dit explicitement — le client ne doit pas croire qu'il
   valide cette partie-la.

## Process

1. Lire `doc/memory/user_journeys.md`, etablir la liste des parcours a filmer
   (nom court + pages traversees), la confirmer avec l'utilisateur.
2. Pour chaque parcours, EN SEQUENCE :
   a. Explorer le chemin au clic via `playwright-cli` (selecteurs, pages, fold)
   b. Ecrire le narrative JSON (`$WORK/narratives/<parcours>.json`)
   c. TTS (un appel), pipeline, verification (frames + audio)
   d. Archiver : `mv "$WORK/out/output.mp4" "$WORK/out/<parcours>.mp4"`
3. Publier chaque video sur la brique avec un titre = le parcours :
   `Parcours patient — abonnement (mockups)`. Le titre est la cle de
   remplacement : refilmer un parcours remplace SA video, pas les autres.
4. `GET /api/v1/bricks/{brick_id}/videos` pour verifier la liste complete, et
   transmettre les liens de visionnage publics (jamais les fichiers bruts).

## Validation gate

- [ ] Un video PAR parcours principal — pas de video fourre-tout
- [ ] Chaque video fait 45-90 s (au-dela, le parcours est a scinder)
- [ ] Narration dans la langue de l'espace client, voix conforme au tableau
- [ ] Narration au futur + invitation aux retours en fin de video
- [ ] Elements hors brique explicitement annonces comme tels
- [ ] Titres = noms de parcours, toutes publiees sur la meme brique
- [ ] Liste verifiee via l'endpoint videos, liens publics transmis
