---
name: brick-daily-video
description: "Assemble tous les changements du jour (mockup ET code) en UN bilan video chapitre, et l'envoie au client avec un message recap. Comble le skill manquant 'envoyer la video + un message au client' que brick-code-feedback et brick-mockup-feedback laissent en suspens. Utilise /brick-daily-video en fin de journee de dev ou de traitement de retours."
---

# Brick Daily Video — le bilan chapitre de la journee

En fin de journee, un seul objet a envoyer au client : une video chapitree qui
reprend TOUS les changements du jour (mockups valides + code livre), avec un
message recap. Le client ouvre un lien, voit le sommaire, regarde ce qui a
avance, commente. C'est l'etape de communication que les boucles feedback
laissent ouverte (`brick-code-feedback` : « a venir, un skill pour envoyer la
video + un message au client »).

## Quand utiliser

- Fin d'une journee de dev sur une brique, ou fin d'une vague de retours traitee
  via `brick-mockup-feedback` / `brick-code-feedback`.
- Quand il y a plusieurs changements dans la journee : un seul bilan vaut mieux
  que cinq liens envoyes au compte-gouttes.
- Pour UN seul changement urgent a envoyer tout de suite, garder `brick-code-video`
  (livraison unitaire) ; le bilan, lui, consolide la journee.

## Ce que ca produit

1. **UNE video « Bilan du [date] »** : carton d'intro, un chapitre par changement
   du jour (mockup ou code), outro avec appel aux retours. Sommaire facon YouTube.
2. **Un message recap** envoye au client (son canal habituel), avec le lien court
   et la liste des changements. Rédigé, relu contre la checklist anti-IA, et
   **confirme par l'utilisateur avant envoi** (message sortant vers le client).

## Rassembler les changements du jour

Croiser trois sources, puis **faire valider la liste par l'utilisateur** (c'est
lui qui sait ce qui est presentable et ce qui attend encore) :

- **Tracker** : issues passees a `fixed` aujourd'hui (`get_destination_tracker_issues`),
  chacune est un changement candidat, taguee mockup ou code selon la phase.
- **Git** : commits du jour (`git log --since=midnight --oneline`) pour ce qui
  n'a pas d'issue tracker.
- **Videos deja produites** : `GET /api/v1/bricks/{brick_id}/videos` — si un
  changement a deja ete filme unitairement dans la journee (via `brick-code-video`
  / `brick-mockup-video`), on REUTILISE son chapitre au lieu de refilmer (voir
  plus bas).

Chaque changement retenu devient un chapitre, nomme dans le vocabulaire du CLIENT
(« Filtre de recherche sur le kanban », pas « ajout scope kanban_controller »).
Ordre : logique metier / importance, pas ordre des commits.

## Architecture : chapitres assembles, comme le walkthrough

Meme moteur et memes garde-fous que `/brick-code-walkthrough`, en plus court :

```
[intro « Bilan du [date] »] [carton chap.1] [chap.1] [carton chap.2] [chap.2] ... [outro + appel aux retours]
```

- **Filmer un chapitre** : appliquer les regles de `/brick-code-video` pour un
  changement de CODE (app reelle, donnees de demo, `waitForUrl`/selecteurs), ou
  de `/brick-mockup-video` pour un changement de MOCKUP (pages `/mockups`,
  formulaires sans etat, narration au futur). Un chapitre = 30-90 s.
- **Reutiliser au lieu de refilmer** : si le changement a deja son mp4 archive du
  jour (`$WORK/chap-*.mp4` sauvegarde par une passe unitaire), le reprendre tel
  quel. Ne refilmer que ce qui n'existe pas encore.
- **Cartons + transition** : carton de titre par chapitre (charte client, MEME
  resolution/fps que le screencast, viewport 1536x900), whoosh SFX
  (`elevenlabs_sfx_tool`) sur chaque carton. Intro « Bilan du [date] » avec le
  nombre de changements.
- **Assemblage** : **concat FILTER obligatoire, JAMAIS le demuxer** (incident
  Nutchel — voir `/brick-code-walkthrough` Etape 4). Chaque segment avec piste
  audio (cartons muets rendus avec un silence).
- **Voix** : par langue de l'espace client (Rudy FR / `3WqHLnw80rOZqJzW9YRB` EN,
  `eleven_v3`), la MEME sur toute la video.

## Parallelisation : un sous-agent par chapitre a filmer

Les chapitres a (re)filmer sont independants → **l'orchestrateur delegue : un
sous-agent par chapitre** (1 par appel, regle CLAUDE.md), chacun dans SA copie du
pipeline (`CHAP="$WORK/chap-NN"`, `node_modules` symlinke — `out/` est un
singleton, deux agents dans le meme repertoire s'ecrasent). Discipline d'etat du
walkthrough : les chapitres de CODE qui ecrivent des donnees passent en sequence
ou sur des comptes dedies ; les mockups n'ecrivent rien (parallele libre).
Plafonner a 3-4 sous-agents (chromium ~300-500 Mo chacun). L'orchestrateur garde :
la liste des changements (avant), cartons + assemblage + envoi (apres).

## Process

1. **Liste du jour** : croiser tracker (`fixed` aujourd'hui) + git + videos deja
   produites. Tagger chaque changement mockup/code. **La faire valider par
   l'utilisateur** — c'est le sommaire du bilan.
2. **Chapitres** : reutiliser les mp4 deja archives du jour ; filmer les autres
   par sous-agents (section ci-dessus), regles code-video ou mockup-video selon
   le tag. Chacun livre `$WORK/chap-NN/out/output.mp4`.
3. **Cartons** : intro « Bilan du [date] » + un carton par chapitre, whoosh SFX.
4. **Assembler** (concat FILTER) → `$WORK/out/bilan.mp4`. Additionner les durees
   (`ffprobe`) pour la table des timecodes.
5. **Verifier — freezedetect NON NEGOCIABLE** sur le fichier FINAL :
   ```bash
   ffmpeg -i "$WORK/out/bilan.mp4" -vf "freezedetect=n=0.001:d=8" -an -f null - 2>&1 | grep freeze || echo "aucun gel > 8s"
   ```
   Plus une frame au milieu de chaque chapitre et l'audio aux coutures.
6. **Publier UNE video** (`delivery_video`, derivation `MCP_TOKEN`/`PLATFORM_API_URL`
   depuis `.mcp.json` / `.nexrai/binding.json`) :
   - `-F category=daily`
   - titre = `Bilan du [date] — brique {N}` (cle de remplacement : re-publier le
     meme jour remplace le bilan, pas les livraisons unitaires)
   - `-F description=...` (une phrase : les changements couverts)
   - `-F transcript=...` (toute la narration)
   - `-F 'chapters=[{"start":0,"title":"Introduction"},{"start":8,"title":"Filtre kanban"},...]'`
   La reponse renvoie le lien COURT `video_url` (`/v/xxxxxxx`) — c'est celui a
   transmettre, jamais le fichier brut ni le `legacy_video_url` long.
7. **Message recap au client** :
   - Court, direct, ton 5000.dev (factuel, sans superlatif). Relu contre la
     checklist anti-IA du prompt (pas de tiret cadratin, pas de vocabulaire IA,
     pas de triades ni de « non seulement... mais aussi »).
   - Contenu : ce qui a avance aujourd'hui (le sommaire), le lien court, et
     l'invitation aux retours (widget de capture sur les pages).
   - **Rédiger puis CONFIRMER avec l'utilisateur avant d'envoyer** — c'est un
     message sortant vers le client. Canal = celui du projet (email via
     `gmail_*`, WhatsApp), selon les contacts du profil.

## Validation gate

- [ ] Liste des changements du jour validee par l'utilisateur (mockup + code)
- [ ] Chapitres reutilises quand deja filmes, refilmes seulement si absents
- [ ] UNE video « Bilan du [date] », intro + un chapitre par changement + outro
- [ ] Cartons a la resolution du screencast, transition (whoosh SFX) sur chacun
- [ ] `freezedetect` passe sur le fichier FINAL (aucun gel > 8 s inexplique)
- [ ] Meme voix / langue de l'espace client sur toute la video
- [ ] Metadonnees `chapters=[...]` + lien court transmis
- [ ] Message recap relu contre la checklist anti-IA, CONFIRME avant envoi
- [ ] Tracker a jour (les issues du bilan pointees vers la video si utile)

## Ensuite

→ fin de journee. Le lendemain matin, `brick-daily-triage` refait le tour des
canaux (emails / WhatsApp / tracker), traite l'actionnable et rappelle
`brick-daily-video` pour le bilan suivant. Entre-temps, `brick-mockup-feedback` /
`brick-code-feedback` a chaque vague de retours.
