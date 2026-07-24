---
name: brick-mockup-video
description: "Genere UNE video par parcours utilisateur principal des mockups, pour la validation client a distance. Meme execution technique que /brick-code-video (pipeline, voix, publication). Utilise /brick-mockup-video quand les mockups sont prets a presenter."
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

## Execution technique : suivre /brick-code-video

Toutes les regles techniques de `/brick-code-video` s'appliquent telles quelles —
ne pas les redecouvrir ici, OUVRIR le skill :

- **Repertoire de travail par app** (`tmp/brick-code-video/` dans le depot, jamais
  `~/demo-video/` partage). Le pipeline ecrit `out/voice.mp3` / `out/output.mp4`
  (singleton), donc UN repertoire PAR parcours : `CHAP="$WORK/j-<parcours>"`,
  copie du pipeline avec `node_modules` symlinke (comme un chapitre de
  `/brick-code-walkthrough`). C'est ce qui permet de filmer les parcours EN
  PARALLELE sans ecrasement croise.
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
   passe par les liens reels entre mockups (regle de `/brick-mockup-build` : les
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

## Parallelisation : un sous-agent par parcours

Les parcours sont independants (les mockups ne creent aucune donnee : pas d'etat
partage a corrompre entre deux tournages). Donc **l'orchestrateur delegue : un
sous-agent par parcours** (1 sous-agent par appel, regle CLAUDE.md), qui explore
ses pages, ecrit son narrative, genere son TTS et rend son mp4 dans SON
repertoire `$WORK/j-<parcours>/`. Plafonner a 3-4 sous-agents simultanes (chaque
tournage porte un chromium ~300-500 Mo). Brief autonome : parcours + URL du dev
server + credentials + voix/langue + chemin `$CHAP` + consigne de NE PAS toucher
aux autres repertoires. L'orchestrateur garde : la liste des parcours (avant) et
la publication (apres).

## Cartons d'intro (option)

Pour un rendu client plus soigne, un carton titre de 2-3 s en tete de chaque
video (nom du parcours, couleurs de la charte), rendu comme dans
`/brick-code-walkthrough`. Si tu colles un carton devant le screencast, tu
ASSEMBLES : applique la regle du moteur (concat FILTER + `freezedetect`, jamais
le demuxer — voir `/brick-code-video`), et le carton doit avoir une piste audio
(silence) sinon le concat echoue.

## Process

1. Lire `doc/memory/user_journeys.md`, etablir la liste des parcours a filmer
   (nom court + pages traversees), la confirmer avec l'utilisateur.
2. Deleguer un sous-agent par parcours (3-4 en parallele max), chacun dans son
   `$WORK/j-<parcours>/` :
   a. Explorer le chemin au clic via `playwright-cli` (selecteurs, pages, fold)
   b. Ecrire le narrative JSON, TTS (un appel), pipeline, verification (frames,
      audio, `freezedetect` si un carton est colle)
   c. Livrer `$WORK/j-<parcours>/out/output.mp4` a l'orchestrateur
3. Publier chaque video sur la brique avec `-F category=mockup`,
   `-F description=...` (une phrase : le parcours mocke que la video presente,
   au futur — s'affiche sous le player), `-F transcript=...` (les say du
   parcours) et un titre = le parcours :
   `Parcours patient — abonnement (mockups)`. Le titre est la cle de
   remplacement : refilmer un parcours remplace SA video, pas les autres.
4. `GET /api/v1/bricks/{brick_id}/videos` pour verifier la liste complete, et
   transmettre les liens de visionnage publics COURTS (champ `video_url`,
   `/v/xxxxxxx` ; jamais les fichiers bruts ni le `legacy_video_url` long).

## Validation gate

- [ ] Un video PAR parcours principal — pas de video fourre-tout
- [ ] Chaque video fait 45-90 s (au-dela, le parcours est a scinder)
- [ ] Narration dans la langue de l'espace client, voix conforme au tableau
- [ ] Narration au futur + invitation aux retours en fin de video
- [ ] Elements hors brique explicitement annonces comme tels
- [ ] Titres = noms de parcours, toutes publiees sur la meme brique
- [ ] Liste verifiee via l'endpoint videos, liens publics transmis

## Ensuite

→ envoyer au client, puis `brick-mockup-feedback` à chaque vague de retours. Mockups validés → `brick-code-build`.
