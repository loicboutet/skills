---
name: brick-design-review
description: "Controle leger de la charte generee par /brick-design-build : coherence avec le brief client, contraste/accessibilite, lisibilite des composants. Utilise /brick-design-review avant de s'appuyer sur la charte pour les mockups."
---

# Brick Design Review

Relit la charte produite par `brick-design-build` avant de la figer comme reference des mockups.
Controle leger, pas une refonte.

## Quand utiliser

- Juste apres `brick-design-build`, avant `brick-mockup-build`.

## Pre-requis

- `doc/memory/style_guide.html` genere.
- La source du brief (`brick-design-brief`) pour confronter charte et attentes client.

## Process

1. **Fidelite au brief** : couleurs, typo et ton correspondent a ce que le client a fourni.
2. **Accessibilite** : contraste texte/fond suffisant (WCAG AA), etats focus visibles, tailles
   lisibles.
3. **Coherence des composants** : boutons, champs, cartes, alertes homogenes et reutilisables.
4. **Deux themes si prevu** (clair/sombre) : les deux tiennent, pas juste une inversion naive.
5. Corriger directement dans `style_guide.html` les ecarts mineurs ; signaler au client si un
   choix de fond est a trancher.

## Validation gate

- [ ] Charte fidele au brief client
- [ ] Contraste AA respecte, focus visibles
- [ ] Composants coherents et reutilisables
- [ ] Ecarts mineurs corriges, choix de fond signales

## Ensuite

→ `brick-mockup-build` : construire les mockups sur cette charte.
