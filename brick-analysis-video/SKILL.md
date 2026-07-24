---
name: brick-analysis-video
description: "Video INTERNE (jamais montree au client) qui explique les grands concepts d'une brique : modele de domaine, parcours cles, decisions structurantes. Sert a aligner l'equipe ou briefer un sous-agent. Utilise /brick-analysis-video sur une brique complexe apres /brick-analysis-review."
---

# Brick Analysis Video (interne)

Explique de vive voix les concepts d'une brique, pour l'equipe, pas pour le client. On la
tourne quand une brique est assez complexe pour que du texte ne suffise pas a aligner tout
le monde (nouveau dev, sous-agent, passation).

## Quand utiliser

- Brique complexe (domaine riche, plusieurs profils, regles metier subtiles).
- Optionnelle : la plupart des briques n'en ont pas besoin. Ne pas la produire par reflexe.

## Pre-requis

- Analyse validee (`brick-analysis-review` passe).
- Le moteur video : memes regles techniques que `brick-code-video` (pipeline, voix, TTS).

## Process

1. Scenariser a partir des fichiers d'analyse : modele de domaine, 2-3 parcours cles, les
   decisions structurantes et leurs raisons. Ton d'ingenieur a ingenieur, pas de vernis client.
2. Produire la video avec le moteur commun (voir `brick-code-video`).
3. **Publier en INTERNE** : `-F audience=internal` a l'upload. La video n'apparait PAS dans
   l'espace client, seulement cote equipe. Ne jamais la transmettre au client (trop brute,
   revele l'implementation).

## Validation gate

- [ ] Concepts, pas features : on explique le POURQUOI, pas un clic par clic
- [ ] Ton interne assume (jargon technique OK)
- [ ] Publiee avec `audience=internal` (invisible espace client)

## Ensuite

→ `brick-design-brief` / `brick-mockup-build`. La video reste une reference d'equipe pour
toute la duree de la brique.
