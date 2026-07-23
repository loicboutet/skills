---
name: brick-presentation-video
description: "Video de presentation longue (10-30 min) qui parcourt TOUS les chemins d'une brique : chapitres screencast assembles avec cartons Remotion, musique et SFX (apprentissages de /brick-promo-video). Utilise /brick-presentation-video pour une revue complete, une formation client ou une passation."
---

# Brick Presentation Video — 10 a 30 minutes, tous les chemins de la brique

Une seule video, longue, qui fait le tour COMPLET d'une brique : chaque
parcours, chaque ecran important, avec des chapitres annonces. Usages :
revue de livraison exhaustive, formation des utilisateurs du client,
passation a une nouvelle equipe.

A ne pas confondre avec :
- `/brick-video` : demo courte d'UNE livraison (~70 s)
- `/brick-mockup-video` : une video PAR parcours, pour valider des mockups
- `/brick-promo-video` : motion design de vente, pas un parcours d'app

## Architecture imposee : des chapitres assembles, JAMAIS une prise unique

C'est une contrainte de fiabilite, pas une preference. Le pipeline execute
~1 action toutes les 4-5 s : 30 minutes = 350+ steps. Meme avec 0,5 % d'echec
par step (selecteur, timing), une prise unique de 350 steps echoue plus de 8
fois sur 10, et chaque echec coute 30 minutes de re-tournage. En chapitres de
2-4 minutes (30-60 steps), un echec ne coute que SON chapitre.

```
[intro Remotion 5-10s] [carton chap.1] [screencast chap.1] [carton chap.2] [screencast chap.2] ... [outro Remotion]
```

## Le scenario : structure par les parcours, exhaustivite par la recette

Deux sources, deux roles distincts :

1. **`doc/memory/user_journeys.md` donne la STRUCTURE** : 1 chapitre = 1
   parcours utilisateur (ou 1 zone fonctionnelle). Une video raconte des
   histoires, pas une checklist — l'ordre des chapitres suit la logique
   metier (le parcours du client final d'abord, l'admin ensuite).

2. **`doc/memory/brick-{N}/recette.md` (produit par `/brick-review`) donne
   l'EXHAUSTIVITE** : c'est la matrice de couverture. Mais une recette reelle
   contient beaucoup de lignes infilmables (tests de securite, config) :
   classer CHAQUE ligne dans un des trois traitements, c'est la colonne
   supplementaire de la matrice.

   | Traitement | Quoi | Exemples (recette Yseis brick 1) |
   |---|---|---|
   | **montrer** | comportement visible par un utilisateur legitime | connexion, creation d'observation, envoi du rapport PDF |
   | **mentionner** | invisible a l'ecran mais precieux pour la confiance : UNE phrase de narration, pas de demo | « chaque role ne voit que son perimetre, verifie par audit » (IDOR, cross-agence, scellement des tokens) |
   | **hors-video** | plomberie et tests negatifs/techniques | cookies httponly, mass-assignment, redirection canonique, id forge dans l'URL |

   Piege a eviter : les lignes de PERIMETRE PAR ROLE (« le directeur voit
   tout, le responsable ne voit que son agence ») ressemblent a de la
   securite mais sont parmi les plus VENDABLES a montrer — un chapitre « ce
   que voit chaque role » les demontre naturellement, souvent le meilleur
   sommaire pour la partie admin.

   La video est complete quand chaque ligne est CLASSEE et que toutes les
   « montrer » sont visibles dans un chapitre. Les « mentionner » se
   regroupent en une ou deux phrases (typiquement sur l'outro). On ne filme
   JAMAIS une attaque (URL forgee, etc.) : c'est sans valeur pour le client
   et anxiogene.

Ecriture de la narration, chapitre par chapitre :
- partir des criteres d'acceptance couverts par le chapitre, formules dans le
  vocabulaire du CLIENT (ce qui a ete promis, pas comment c'est code) ;
- une phrase = une action a l'ecran (regle /brick-video), l'enchainement des
  phrases EST le scenario du chapitre ;
- montrer le comportement, pas le decrire : pour « le montant est
  facultatif », on valide SANS montant a l'ecran plutot que de le dire.

Si la recette n'existe pas encore (brique pas passee par `/brick-review`),
la faire d'abord — la video de presentation sans recette redevient une
balade dont on ne peut pas prouver la couverture.

Confirmer le plan de chapitres AVEC le tableau de couverture avec
l'utilisateur avant de tourner.

## Execution technique

**Base : toutes les regles de `/brick-video` s'appliquent** (repertoire de
travail par app `tmp/brick-video/`, scenarisation waitForUrl/selecteurs,
voix par langue — Rudy FR / `3WqHLnw80rOZqJzW9YRB` EN, `eleven_v3`).

**Emprunts a `/brick-promo-video`** pour le liant :
- **Cartons de chapitre** rendus avec le template Remotion (copie de travail,
  comme la promo : `~/demo-video/remotion` copie dans l'app). Un carton =
  2-3 s, titre du chapitre, style charte du client. IMPORTANT : rendre les
  cartons a la MEME resolution/fps que le screencast (viewport pipeline :
  1536x900) pour un concat sans surprise.
- **Musique** : `elevenlabs_music_tool` pour l'intro et l'outro (le cache
  ElevenLabs rend le meme prompt gratuit d'une video a l'autre — garder un
  prompt par client pour une identite sonore stable). Sous les chapitres
  parles : PAS de musique en v1 (la voix prime, le mix ducking est du
  raffinement, pas un prerequis).
- **SFX** : `elevenlabs_sfx_tool`, un whoosh de transition sur chaque carton.

**TTS par chapitre** : un chapitre de 2-4 min = 1800-3600 caracteres, donc un
ou deux appels TTS au plus — on reste dans la regle « un appel sous 3000
caracteres » de /brick-video, et les coutures de prosodie tombent sur les
cartons, donc inaudibles.

## Process

1. **Plan de chapitres** : parcours + ecrans restants -> 4 a 10 chapitres
   nommes. Le faire VALIDER par l'utilisateur (c'est le sommaire de la video).
2. **Tourner chapitre par chapitre**, en sequence (le pipeline ecrit
   `out/output.mp4` : archiver `mv "$WORK/out/output.mp4" "$WORK/out/chap-NN.mp4"`
   apres chaque rendu, comme /brick-mockup-video).
3. **Rendre les cartons** Remotion (`chap-NN-card.mp4`) + intro/outro.
4. **Assembler** :
   ```bash
   # Liste ordonnee intro, carton, chapitre, carton, chapitre..., outro
   for f in intro.mp4 chap-01-card.mp4 chap-01.mp4 ...; do echo "file '$WORK/out/$f'"; done > "$WORK/out/concat.txt"
   # Re-encoder au concat (sources heterogenes Remotion/Playwright) :
   ffmpeg -f concat -safe 0 -i "$WORK/out/concat.txt" -c:v libx264 -crf 20 -preset medium -c:a aac -movflags +faststart "$WORK/out/presentation.mp4"
   ```
5. **Table des chapitres** : additionner les durees (`ffprobe -show_entries
   format=duration`) pour produire la liste des timecodes (`00:00 Introduction,
   02:14 Parcours patient, ...`). Elle accompagne TOUJOURS le lien envoye au
   client : personne ne regarde 25 minutes sans sommaire cliquable mentalement.
6. **Verifier** avant publication : regarder au moins le debut, une transition
   de carton, et la fin (`ffmpeg -ss` pour extraire des frames), verifier
   l'audio aux coutures.
7. **Publier** comme /brick-video (`delivery_video`, meme derivation
   MCP_TOKEN/PLATFORM_API_URL). Un fichier de 10-30 min fait 100-400 Mo :
   l'infra accepte (pas de plafond de taille, delais d'upload releves a 600 s).
   Transmettre le lien public + la table des chapitres.

## Validation gate

- [ ] Plan de chapitres valide par l'utilisateur AVANT tournage
- [ ] Matrice de couverture complete : CHAQUE ligne de recette classee
      (montrer / mentionner / hors-video), toutes les « montrer » visibles
      dans un chapitre, les « mentionner » couvertes par la narration
- [ ] Chapitres de 2-4 min, tournes et archives separement
- [ ] Cartons a la resolution du screencast, transitions avec SFX
- [ ] Narration dans la langue de l'espace client, meme voix sur toute la video
- [ ] Table des timecodes fournie avec le lien
- [ ] Duree totale 10-30 min — au-dela de 30, scinder en deux videos
