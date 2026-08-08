---
name: brick-analysis-review
description: "Controle qualite de l'analyse AVANT de passer aux mockups : criteres d'acceptance complets et tracables, routes conformes, data models sains, et surtout coherence avec les vrais echanges client (Leexi, emails, WhatsApp). Utilise /brick-analysis-review apres /brick-analysis-build."
---

# Brick Analysis Review

Relit l'analyse produite par `brick-analysis-build` avant d'engager les mockups. C'est le
review le plus rentable de la chaine : une erreur d'analyse attrapee ici coute dix minutes,
la meme attrapee apres l'implementation coute une brique.

## Quand utiliser

- Juste apres `brick-analysis-build`, avant `brick-mockup-build`.
- Quand une nouvelle brick est ajoutee et que les fichiers d'analyse ont ete mis a jour.

## Pre-requis

- `doc/memory/data_models.md`, `routes.md`, `acceptance_criteria.md`, `user_journeys.md` presents.
- Acces aux echanges client (MCP `leexi_*`, `gmail_*`, WhatsApp) pour confronter l'analyse au reel.

## Process

Passer chaque point, noter les manques, corriger dans les fichiers d'analyse (ou signaler au
chef de projet si c'est un choix produit).

1. **Criteres d'acceptance** : chaque exigence a un critere tracable (R1/AC1.1), formule dans
   le vocabulaire du client. Pas de critere vague ou intestable. Chaque brick signee est couverte.
2. **Routes** : un namespace par profil, jamais deux routes concurrentes pour la meme intention
   (pas de `/analysis` ET `/dashboard`), 3-5 actions max par ressource, cles API des dependances
   presentes, pas de route monitoring machine dans l'admin.
3. **Data models** : relations coherentes, pas d'attribut orphelin, responsabilites claires,
   rien qui contredise les criteres d'acceptance.
4. **Parcours utilisateurs** : un parcours par profil, du debut a la fin, sans trou.
5. **Confrontation au reel** : relire les calls Leexi + emails + WhatsApp du projet et verifier
   que l'analyse ne rate rien de ce que le client a demande, et n'invente rien qu'il n'a pas demande.
6. **Scope** : ce qui est hors brique courante est explicitement marque comme tel.

7. **Pages publiques** : si la brique en comporte, verifier que l'analyse porte bien ce que
   `/brick-seo` exige en amont : requete cible par page, intention de recherche, et les donnees
   a collecter aupres du client (NAP exact, avis, preuves, prix). Une page publique sans requete
   cible est une page qu'on ecrira au hasard.

## Validation gate

- [ ] Chaque brick signee est couverte par des criteres d'acceptance tracables
- [ ] Routes conformes aux regles (namespace par profil, pas de doublon d'intention)
- [ ] Data models coherents avec les criteres
- [ ] Un parcours complet par profil
- [ ] Analyse confrontee aux echanges client reels (aucun manque, aucune invention)
- [ ] Pages publiques : requete cible et donnees SEO a collecter presentes dans l'analyse
- [ ] Ecarts corriges dans les fichiers, ou signales au chef de projet

## Ensuite

→ `brick-design-brief` si le client n'a pas de charte, sinon `brick-mockup-build`.
Sur une brique complexe, `brick-analysis-video` pour aligner l'equipe sur les concepts.
