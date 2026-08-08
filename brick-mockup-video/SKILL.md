---
name: brick-mockup-video
description: "Assemble UNE seule video chapitree des mockups (un chapitre par parcours, cartons et transitions entre chapitres), pour la validation client a distance. Meme moteur que /brick-code-video, meme chapitrage que /brick-code-walkthrough. Utilise /brick-mockup-video quand les mockups sont prets a presenter."
---

# Brick Mockup Video — UNE video chapitree des mockups

Filme les mockups pour la validation client a distance : le client voit tous les
parcours s'enchainer dans une seule video, avec un sommaire cliquable, commente,
et valide sans attendre un call.

## Quand utiliser

- Les mockups d'une brique sont prets (apres `/brick-mockup-review`)
- Le client valide a distance, ou on veut preparer le call de presentation
- AVANT l'implementation : cette video est un outil de validation, pas de livraison

## Le principe : une seule video, chapitree

**Une video unique, un chapitre par parcours utilisateur.** Le client reçoit UN
lien avec un sommaire (« votre patient s'abonne », « votre admin valide une
demande »), navigue de chapitre en chapitre facon YouTube, et commente. Fini les
cinq liens separes a ouvrir un par un : un seul objet a envoyer, a regarder, a
valider.

Chaque chapitre reste court (45-90 s) et raconte UNE histoire. Des cartons de
titre et une transition les separent, pour que l'enchainement respire au lieu de
sauter d'une page a l'autre. Total typique : 3 a 8 minutes pour 4-6 parcours.

Source des parcours : **`doc/memory/user_journeys.md`** (artefact de la phase
ANALYSIS). Prendre les parcours principaux (typiquement 3 a 6, un par profil x
objectif majeur) ; ils deviennent l'ordre des chapitres, logique metier d'abord
(le client final, puis l'admin). Si le fichier manque, les deduire de l'index
`/mockups` et **confirmer le plan de chapitres avec l'utilisateur avant de
filmer** — c'est le sommaire de la video, et c'est lui qui sait ce que le client
doit valider en priorite.

## Perimetre : le tour complet UNE fois, ensuite seulement le nouveau

Regle de cadrage, alignee sur `/brick-code-video` (une video par changement) et
sur la boucle `/brick-mockup-feedback` (on filme les changements du jour) :

- **Premiere presentation d'une brique** : tour complet, un chapitre par parcours
  principal (rien n'est encore valide).
- **Briques suivantes (2, 3...) ET chaque vague de retours** : on ne chapitre
  **QUE les parcours nouveaux ou modifies**. Le client a deja valide le reste ;
  le refilmer lui fait perdre son temps et noie ce qu'il doit reellement valider.
  Un chapitre = un parcours neuf ou une modif. Si la brique n'ajoute qu'un ecran,
  la « video chapitree » peut n'avoir qu'un seul chapitre, c'est normal.

Pour savoir ce qui est nouveau : le tracker (issues traitees depuis la derniere
video) et `doc/memory/acceptance_criteria.md` (AC ajoutes par la brique
courante). En cas de doute sur ce qui a deja ete valide, demander a
l'utilisateur — c'est lui qui tient l'historique client.

## Architecture : des chapitres assembles, jamais une prise unique

Meme contrainte de fiabilite que `/brick-code-walkthrough` : le pipeline execute
~1 action toutes les 4-5 s, une prise unique de tous les parcours echoue trop
souvent et coute un re-tournage complet a chaque rate. On tourne chaque chapitre
separement (30-60 steps), puis on assemble :

```
[carton chap.1] [screencast parcours 1] [carton chap.2] [screencast parcours 2] ... [outro]
```

Un carton en tete de chaque parcours = la transition. Pas besoin d'intro/outro
Remotion lourde comme le walkthrough : un carton titre suffit a rythmer.

## Execution technique : suivre /brick-code-video + le chapitrage du walkthrough

Ne pas redecouvrir les regles, OUVRIR les skills :

- **Moteur** (`/brick-code-video`) : repertoire de travail par app
  (`tmp/brick-code-video/`, jamais `~/demo-video/` partage), voix par langue
  (Rudy FR / `3WqHLnw80rOZqJzW9YRB` EN, `eleven_v3`, langue = espace client du
  projet), TTS en un appel sous 3000 caracteres (un parcours de 45-90 s fait
  600-1200 caracteres), scenarisation `goto` au step 0 seulement, `waitForUrl`
  sur les navigations, selecteurs verifies via `playwright-cli`, scroll pour le
  contenu sous le fold.
- **Chapitrage + assemblage** (`/brick-code-walkthrough`) : cartons de chapitre
  rendus au template Remotion (2-3 s, titre du parcours, style charte du client,
  MEME resolution/fps que le screencast — viewport pipeline 1536x900), whoosh SFX
  (`elevenlabs_sfx_tool`) sur chaque carton, **concat FILTER obligatoire, JAMAIS
  le demuxer** (voir l'incident Nutchel), table des timecodes, `freezedetect` sur
  le fichier FINAL, metadonnees `chapters=[...]` a la publication.

## Specificites mockups (ce qui CHANGE par rapport a une video de code)

1. **Cible** : le dev server de l'app, pages sous `/mockups/...`. La navigation
   passe par les liens reels entre mockups (regle de `/brick-mockup-build` : les
   pages doivent linker entre elles — si un parcours est infranchissable au
   clic, c'est un bug de mockup a corriger AVANT de filmer).
2. **Les formulaires ne creent rien** : donnees fictives dans les controleurs,
   pas de DB. Un submit navigue vers la page mockee suivante, c'est tout. Donc
   pas de reset de donnees, pas de `moveUrl`/`moveStatus` pour les drags
   (utiliser un `hover` + narration a la place si le drag est central). **Bonus :
   comme aucun chapitre n'ecrit en base, ils se parallelisent tous librement**
   (pas de discipline lecture/ecriture du walkthrough, pas d'enregistrement
   fantome possible chez le voisin).
3. **Narration de validation, pas de livraison.** On presente ce que le client
   POURRA faire, et on l'invite a reagir :
   - « Voici comment votre patient s'abonnera... » (futur, pas accompli)
   - Terminer la video (outro ou dernier chapitre) par une invitation aux retours
     via le widget de capture present sur les mockups (« cliquez sur la bulle
     pour commenter directement la page »)
   - Ne JAMAIS presenter comme fini ce qui est mocke : pas de « c'est en ligne »,
     pas de chiffres presentes comme reels
4. **Scope brique** : si un parcours traverse un element grise « Brique 2 », la
   narration du chapitre le dit explicitement — le client ne doit pas croire
   qu'il valide cette partie-la.

## Parallelisation : un sous-agent par chapitre

Les parcours sont independants et sans etat partage (les mockups ne creent
rien), donc **l'orchestrateur delegue : un sous-agent par chapitre** (1 sous-agent
par appel, regle CLAUDE.md), qui explore ses pages, ecrit son narrative, genere
son TTS et rend son mp4 dans SON repertoire. L'orchestrateur garde : le plan de
chapitres (avant), les cartons, l'assemblage, la publication (apres).

Garde-fou obligatoire : **un repertoire pipeline PAR chapitre**. `out/` est un
singleton (voice.mp3, output.mp4). Chaque sous-agent recoit SA copie du pipeline
avec `node_modules` symlinke :

```bash
CHAP="$WORK/chap-NN"   # copie du pipeline comme dans /brick-code-video
```

Le sous-agent livre `$CHAP/out/output.mp4`, l'orchestrateur le collecte. Deux
sous-agents dans le meme repertoire = ecrasement croise garanti. Plafonner a
**3-4 sous-agents simultanes** (chaque tournage porte un chromium ~300-500 Mo).
Brief autonome : parcours + URL du dev server + credentials + voix/langue +
chemin `$CHAP` + consigne de NE PAS toucher aux autres repertoires.

## Process

1. **Plan de chapitres** : lire `doc/memory/user_journeys.md`, etablir la liste
   ordonnee des parcours (nom court + pages traversees). La **faire valider par
   l'utilisateur** — c'est le sommaire de la video.
2. **Tourner les chapitres** — en parallele par sous-agents (section ci-dessus),
   chacun dans son `$WORK/chap-NN/` :
   a. Explorer le chemin au clic via `playwright-cli` (selecteurs, pages, fold)
   b. Ecrire le narrative JSON (narration au futur + invitation aux retours sur
      le dernier chapitre), TTS (un appel), pipeline, verification (frames, audio)
   c. Livrer `$WORK/chap-NN/out/output.mp4` a l'orchestrateur
3. **Rendre les cartons** Remotion (`chap-NN-card.mp4`, titre du parcours, charte
   client), whoosh SFX sur chacun. Meme resolution/fps que les screencasts.
4. **Assembler — concat FILTER obligatoire, jamais le demuxer** (regle du moteur,
   voir `/brick-code-walkthrough` Etape 4) :

   ```bash
   # FILES dans l'ordre : carton 1, parcours 1, carton 2, parcours 2, ...
   # Chaque segment DOIT avoir une piste audio (cartons muets = rendre avec un
   # silence, sinon concat n=..:a=1 echoue), meme resolution partout.
   INPUTS=""; FC=""
   i=0; for f in "${FILES[@]}"; do INPUTS="$INPUTS -i $f"; FC="$FC[$i:v][$i:a]"; i=$((i+1)); done
   ffmpeg $INPUTS -filter_complex "${FC}concat=n=$i:v=1:a=1[v][a]" \
     -map "[v]" -map "[a]" -c:v libx264 -crf 20 -preset medium -r 25 \
     -c:a aac -movflags +faststart "$WORK/out/mockups.mp4"
   ```
5. **Table des chapitres** : additionner les durees (`ffprobe -show_entries
   format=duration`) pour produire les timecodes (`00:00 Parcours patient,
   01:12 Parcours admin, ...`).
6. **Verifier — freezedetect NON NEGOCIABLE** sur le fichier FINAL :

   ```bash
   ffmpeg -i "$WORK/out/mockups.mp4" -vf "freezedetect=n=0.001:d=8" -an -f null - 2>&1 | grep freeze || echo "aucun gel > 8s"
   ```
   Plus une frame au MILIEU de chaque chapitre (pas aux transitions) et l'audio
   aux coutures.
7. **Publier UNE video** sur la brique (`delivery_video`, meme derivation
   `MCP_TOKEN`/`PLATFORM_API_URL` depuis `.mcp.json` / `.nexrai/binding.json`) :
   - `-F category=mockup`
   - titre = la brique + « mockups » (ex : `Mockups — brique 1 (parcours patient & admin)`).
     Le titre est la cle de remplacement : refilmer remplace CETTE video.
   - `-F description=...` (une phrase : les parcours mockes que la video presente,
     au futur — s'affiche sous le player)
   - `-F transcript=...` (toute la narration concatenee)
   - `-F 'chapters=[{"start":0,"title":"Parcours patient"},...]'` — les timecodes
     JSON : le player Mux affiche les chapitres facon YouTube, le sommaire vit
     DANS la video.
8. `GET /api/v1/bricks/{brick_id}/videos` pour verifier, et transmettre le lien
   de visionnage public COURT (`video_url`, `/v/xxxxxxx` ; jamais le fichier brut
   ni le `legacy_video_url` long), avec la table des chapitres.

## Validation gate

- [ ] Plan de chapitres (parcours) valide par l'utilisateur AVANT tournage
- [ ] Perimetre correct : tour complet en brique 1, seulement les parcours
      nouveaux/modifies en briques 2+ et en iterations de retours
- [ ] UNE seule video, un chapitre par parcours retenu
- [ ] Chaque chapitre 45-90 s ; total 3-8 min (au-dela, scinder un parcours)
- [ ] Cartons a la resolution du screencast, transition (whoosh SFX) sur chacun
- [ ] `freezedetect` passe sur le fichier FINAL (aucun gel > 8 s inexplique)
- [ ] Narration au futur + invitation aux retours en fin de video
- [ ] Elements hors brique explicitement annonces comme tels
- [ ] Narration dans la langue de l'espace client, meme voix sur toute la video
- [ ] Metadonnees `chapters=[...]` + table des timecodes fournie avec le lien

## Ensuite

→ envoyer au client, puis `brick-mockup-feedback` à chaque vague de retours. Mockups validés → `brick-mockup-reanalyse`, puis `brick-code-build` sur verdict PRET.
