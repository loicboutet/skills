---
name: brick-promo-video
description: "Cree une video de presentation produit (promo site web / lancement) en motion design Remotion : scenario PAS, voix ElevenLabs, musique et SFX generes, UI recomposee aux couleurs du client. Utilise /brick-promo-video pour produire une video de promo facturable."
---

# Brick Promo Video — Video de presentation produit en motion design

Produit une video de promo de 45-60 s pour le site web ou le lancement d'un
produit client : motion design style agence (reference : 1600.agency), voix
off dynamique, musique et sound design generes, UI recomposee en composants
React animes aux couleurs de la charte.

Ne pas confondre avec `/brick-video` (walkthrough de livraison d'une brick,
enregistrement de l'app reelle). Ici on VEND le produit, on ne le documente pas.

## Quand utiliser

- Le client veut une video pour sa page d'accueil, un lancement, ses reseaux
- Video de presentation d'un produit 5000.dev (prestation facturable)
- L'utilisateur invoque /brick-promo-video

## Pre-requis

- Projet Remotion template : `~/demo-video/remotion/` — LECTURE SEULE, a copier dans l'app (composition de reference
  `src/Promo1600.jsx`, celle d'Izi Wage — copier/adapter, ne pas partir de zero)
- Tools plateforme (MCP nexrai) : `elevenlabs_tts_tool`, `elevenlabs_music_tool`,
  `elevenlabs_sfx_tool` (cles cote serveur, jamais en local)
- Images generatives : CLI `~/.nexrai/bin/nexrai-image`
- Charte du client : couleurs et fonts depuis son `tailwind.config.js` (ou
  equivalent), logo dans ses assets

Si un tool audio manque au catalogue, le signaler a l'utilisateur (specs de
reference dans les artefacts nexrai `spec_music_tool` de l'app 86).

## Process

### Phase 1 — Scenario (VALIDATION UTILISATEUR OBLIGATOIRE)

Framework **PAS en 7 temps** (~110 mots pour 45 s, ~150 mots/minute) :

| # | Duree | Role | Regle |
|---|-------|------|-------|
| 1 | 3-5 s | Hook | Pattern interrupt ou affirmation choc. JAMAIS le nom du produit. |
| 2 | 5-7 s | Agiter | Douleur concrete + cout de l'inaction (le moment qui vend) |
| 3 | 4 s | Solution | Le produit, une phrase outcome |
| 4 | 12-15 s | Comment | 3 capacites MAX, en resultats, pas en fonctionnalites |
| 5 | 4-5 s | Preuve | UN benefice representatif du quotidien |
| 6 | 3-4 s | Zoom out | L'outcome global |
| 7 | 5-6 s | CTA | Un seul ask, explicite |

Regles d'ecriture :
- Phrases de 3 a 8 mots. Une idee par phrase. Ton direct, zero superlatif.
- **Chiffres : vrais, verifiables ET representatifs.** Un outlier spectaculaire
  (ex : 1 000 € recuperes sur un bulletin) decredibilise ; le benefice
  quotidien (temps gagne) convainc. Ne JAMAIS inventer ni prendre un chiffre
  de la base de dev sans verifier la prod. Dans le doute : des categories
  plutot qu'un comptage (« LEGAL · URSSAF · CCN » plutot que « 151 regles »).
- Ecrire le scenario dans un artefact nexrai (tableau scene par scene : temps,
  voix, visuel) et le faire valider AVANT toute production.

### Phase 2 — Assets visuels

1. Couleurs/fonts : lire le tailwind.config du projet client. Reprendre les
   tokens exacts (couleurs, radius, familles).
2. Logo : cropper le glyphe seul si le wordmark est illisible sur fond colore
   (`ffmpeg -vf crop=...`). Verifier le resultat en le lisant.
3. Fonds : 2 textures generees via nexrai-image (une sombre, une claire),
   prompt type : "Abstract premium background texture, [couleur marque] base,
   soft flowing silky waves, elegant, no text, wide 16:9". Les animer en Ken
   Burns lent (scale 1.06 + drift sinusoidal). PAS de bulles/confettis.

### Phase 3 — Voix

1. **Script phonetique** : dans le texte TTS, epeler les marques et sigles a la
   francaise (« Izi Wage » → « Izi Oueidj », « URSSAF » → « Ursaf ») ; garder
   l'orthographe reelle a l'ecran. Ponctuation expressive (!, ?) : elle pilote
   l'intonation.
2. Modele **eleven_v3** (bien plus expressif que multilingual_v2). Voix de
   reference pub : Rudy `wufFsVwuYBePWKO6dMMN` (dynamique) ; alternatives
   Sophie `BewlJwjEWiFLWoXrbGMf`, Marie `sANWqF1bCMzR6eyZbCGw`.
3. **Generer 2-3 prises** et faire choisir l'utilisateur a l'oreille (pas de
   graine fixe chez ElevenLabs, chaque prise differe).
4. Recuperer l'audio ET l'alignement JSON. Si le tool MCP de la session ne
   renvoie pas l'alignement exploitable, appeler l'endpoint MCP direct en curl
   (URL et token dans le `.mcp.json` du projet, JSON-RPC `initialize` puis
   `tools/call`) et parser la reponse par script.
5. **Decouper la voix en un segment par scene** (ffmpeg, frontieres = fins de
   phrases lues dans l'alignement) : `ffmpeg -i voix.mp3 -ss A -to B -c:a
   libmp3lame -q:a 2 vo/sN.mp3`. Chaque segment est pose au debut de sa scene
   dans Remotion. C'est ce qui permet : l'air entre les scenes, et le
   remplacement d'UNE phrase sans regenerer le reste.

### Phase 4 — Musique et SFX

- Musique : `elevenlabs_music_tool`, duree = duree video exacte, prompt type
  "Upbeat corporate tech track, 120 BPM, punchy clean drums, progressive
  energy build, confident ending, no vocals". Le tool renvoie bpm +
  beat_offsets (utilisables pour caler des accents).
- SFX : `elevenlabs_sfx_tool` — 4 assets suffisent : whoosh (transitions),
  pop (apparitions de cartes/mots), tick (compteurs), chime (CTA). Cache cote
  plateforme : les reutiliser d'une video a l'autre.

### Phase 5 — Composition Remotion

Partir de `Promo1600.jsx` (structure : SCENES[], Scene/SceneInner, BandWipe,
Bg, KineticLine, tableau SFX, segments voix en Sequences).

Regles d'animation NON NEGOCIABLES (retours client integres) :
- **Une scene = duree de son segment voix + ~30 frames de respiration** avant
  la coupe, pour laisser finir les animations.
- Springs amortis (`damping >= 13`). **JAMAIS de rotation animee sur du
  texte, jamais de pulsation continue** : entree par translateY + scale leger
  + opacite, puis le texte reste stable.
- 2 styles de transitions MAX : push directionnel avec parallaxe (la scene
  sortante recule, s'assombrit, s'arrondit) + bandeau plein ecran sur les 2-3
  ruptures de chapitre. Le bandeau doit couvrir 100 % de l'ecran a l'instant
  de la coupe (train de bandes skewees, cœur opaque ~150 % de large).
- UI recomposee en React avec les tokens du client (cartes, badges, KPI),
  jamais de captures d'ecran brutes dans ce format.
- Compteurs : n'afficher le bloc qu'au moment ou la voix annonce le chiffre
  (pas de « 0 » solitaire).
- Alternance de fonds sombre/clair/accent entre les scenes.

Mixage : musique 0.13 sous la voix, 0.40-0.45 quand elle se tait (outro),
fondu final. SFX : whoosh 0.2-0.5 selon l'importance, pops 0.3-0.5.

### Phase 6 — Declinaisons de format (16:9, 1:1, 9:16)

Une seule composition responsive, trois `<Composition>` dans Root :
16:9 `1920x1080` (site web), 1:1 `1080x1080` (feed), 9:16 `1080x1920`
(stories/reels). Memes timings, meme audio.

- Le composant lit les dimensions via `useVideoConfig()` ; un helper derive le
  format (`ratio > 1.4` → wide, `< 0.8` → tall, sinon square) et un facteur
  d'echelle typo (wide 1, square ~0.7, tall ~0.75).
- Les layouts horizontaux (rangées de cartes KPI, doc → champs OCR, mots
  geants cote a cote) **basculent en pile verticale** en tall ; en square,
  reduire les tailles pour garder la rangée quand elle tient.
- Elements positionnes en absolu (chips decoratives) : coordonnees en
  fractions de largeur/hauteur, jamais en pixels fixes ; en reduire le nombre
  dans les formats etroits.
- Largeurs de cartes : `min(largeur_ideale, W - 140)`.
- Safe zones reseaux (9:16) : garder le contenu essentiel dans les 80 %
  centraux verticaux (UI des plateformes en haut/bas).
- Verifier chaque format par extraction de frames : les debordements
  horizontaux ne se voient qu'a l'image.

### Phase 7 — Rendu et revue critique

```bash
# JAMAIS dans ~/demo-video directement : repertoire PARTAGE entre agents
# (deux rendus concurrents s'ecrasent). Copie de travail par app, comme
# brick-video :
WORK="$(pwd)/tmp/brick-promo-video"
mkdir -p "$WORK" && cp -a ~/demo-video/remotion "$WORK/remotion"
ln -sfn ~/demo-video/node_modules "$WORK/remotion/node_modules" 2>/dev/null || true
cd "$WORK/remotion" && npx remotion render src/index.js <CompoId> out/<slug>-vN.mp4
```
(~3 min pour 50 s en 1080p. Iterer = re-render, c'est pas cher.)

Revue OBLIGATOIRE avant de livrer : extraire des frames aux moments cles et
les REGARDER (`ffmpeg -ss T -i out.mp4 -frames:v 1 f.jpg`) — en particulier :
le hook, chaque transition, les moments ou la voix cite un element visuel
(verifier la synchro), le CTA. Verifier la piste audio presente
(`ffprobe ... codec_type`).

Livrer dans `doc/demo_videos/` du projet client (dossier gitignore, les mp4
ne se committent pas).

### Phase 8 — Retours

Chaque retour est une petite edition : frontieres dans SCENES[], niveaux dans
SFX[], une phrase = re-generer UN segment voix. Toujours re-extraire des
frames apres correction. Documenter les lecons generales dans ce skill.

## Troubleshooting

| Symptome | Cause | Fix |
|----------|-------|-----|
| Prononciation anglaise/sigle ratee | TTS lit a la francaise | Graphie phonetique dans le texte TTS uniquement |
| Intonation plate ou moins bonne | Loterie ElevenLabs | Re-generer 2-3 prises, faire choisir ; ponctuation expressive |
| Voix inaudible | Musique trop forte | 0.13 max sous la voix |
| Animations coupees | Scene = duree voix pile | +30 frames de respiration par scene |
| Texte qui « tremble » | Rotation animee / overshoot / pulse | Supprimer rotate et pulse, damping >= 13 |
| Coupe visible pendant un bandeau | Bande trop etroite | Cœur opaque du train >= 150 % de l'ecran |
| Logo illisible sur fond colore | Wordmark integre au PNG | Cropper le glyphe seul, verifier visuellement |
| Contenu coupe en 1:1 ou 9:16 | Layout pixels fixes | Piles verticales + largeurs min(ideal, W-140) + frames de controle |
| Erreur encodage / 422 sur tools audio | Bug plateforme | Diagnostiquer precisement (mp3 vs wav, prompt ASCII) et remonter a l'utilisateur |
| Tool audio absent de la session MCP | Tool active apres connexion | Endpoint MCP direct en curl (token du .mcp.json) |

## Validation gate

- [ ] Scenario PAS valide par l'utilisateur (artefact) AVANT production
- [ ] Aucun chiffre non verifie ou non representatif a l'ecran ou en voix
- [ ] Prise de voix choisie par l'utilisateur parmi 2-3
- [ ] Textes stables (zero rotation, zero pulse), respiration avant chaque coupe
- [ ] Synchro voix/visuel verifiee frame par frame sur les moments cles
- [ ] Musique sous la voix, SFX en place, piste audio presente au ffprobe
- [ ] Les 3 formats rendus et verifies par frames (16:9, 1:1, 9:16)
- [ ] Videos livrees dans doc/demo_videos/ (gitignore)
