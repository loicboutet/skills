---
name: brick-mockup-review
description: "Verifie qu'une serie de mockups en cours de validation respecte les regles de process (scope par brique, partials, sync specs, outil de capture). Utilise /brick-mockup-review avant de presenter les mockups au client."
---

# Brick Mockup Review

Controle qualite des mockups AVANT presentation au client. Verifie que les regles de process
sont appliquees, synchronise les mockups avec les specs, et confirme que l'outil de capture
de feedback est en place. A lancer sur des mockups en cours de validation.

## Quand utiliser

- Mockups crees (via `/brick-mockups`) et prets a etre montres au client
- Reprise d'une serie de mockups existante dont on veut verifier la conformite
- Avant chaque presentation client d'un lot de mockups

## Pre-requis

- Les mockups existent dans `app/views/mockups/`
- `doc/memory/routes.md`, `data_models.md`, `acceptance_criteria.md`, `user_journeys.md` existent
- `doc/memory/style_guide.html` existe

## Process

Pour chaque check : lister ce qui est OK, ce qui est A CORRIGER. Ne rien corriger silencieusement.

### 1. Couverture (mockups vs routes)

Comparer `doc/memory/routes.md` avec les vues de `app/views/mockups/` :
- [ ] Chaque route a un mockup correspondant
- [ ] L'index `/mockups` liste TOUTES les pages
- [ ] Aucune page en impasse (chaque page linke vers ses pages liees)

### 2. Scope par brique (marquage)

Le client doit comprendre d'un coup d'oeil ce qui est livre maintenant vs plus tard :
- [ ] Les elements des briques suivantes sont grises + badge "Brique 2" / "Brique 3"
- [ ] L'index `/mockups` indique la brique de chaque page
- [ ] Aucun element hors brique courante presente comme livrable sans marquage

### 3. Synchronisation mockups vers specs (CRITIQUE)

Pendant le mockup, on ajoute souvent des elements qui ne sont pas (encore) dans les specs :
un champ, une page, une action, une etape de parcours. Les specs sont la source de verite --
elles doivent rester a jour, sinon ecart specs / mockups / implementation.

Pour chaque element present dans un mockup mais absent des specs :

1. **Le lister** (quoi, sur quelle page).
2. **Proposer l'ajout dans le bon fichier de specs, au bon endroit** :
   - Nouvel attribut affiche -> `data_models.md` (sur le bon modele)
   - Nouvelle page / nouvelle action -> `routes.md` (dans le bon namespace)
   - Nouveau comportement verifiable -> `acceptance_criteria.md` (nouveau AC, numerote)
   - Nouvelle etape de parcours -> `user_journeys.md` (dans le bon parcours/profil)
3. **Demander validation a l'utilisateur AVANT d'ecrire** dans les specs. Ne jamais
   ajouter aux specs silencieusement (cf. regle "Specs = source de verite").

Verifier aussi l'inverse :
- [ ] Tout element des specs (champ, page, parcours) a bien un mockup -> sinon, gap a signaler

Sortie de cette etape : une liste "Elements mockup absents des specs -> proposition d'ajout"
soumise a l'utilisateur.

### 4. Outil interne de capture de feedback

L'outil interne de capture (screenshot + URL + commentaire) sert au client a remonter ses
retours directement depuis les mockups. Verifier qu'il est bien applique :
- [ ] L'outil de capture est integre dans les layouts mockups (present sur chaque page)
- [ ] Il capture bien l'**URL** de la page en plus du screenshot et du commentaire
- [ ] Verification comportementale : naviguer sur 1-2 pages (Playwright), declencher une
      capture, confirmer que screenshot + URL + commentaire partent correctement
- [ ] Aucun mockup n'echappe a l'outil (verifier les layouts admin ET user)

### 5. Conformite technique

- [ ] Tout est dans le namespace `/mockups` (routes, controleurs, vues)
- [ ] Aucun modele ni migration (donnees fictives dans les controleurs uniquement)
- [ ] Partials extraites pour tout element repetable / reutilisable (cf. `/brick-mockups`)
- [ ] Tailwind via le pipeline `tailwindcss-rails` (PAS le CDN)
- [ ] Couleurs custom dans `tailwind.config.js`, jamais en arbitraire (`bg-[#3B82F6]`)
- [ ] Pas de CSS custom hors `application.tailwind.css`

### 6. Conformite au style guide & UX

Avec `doc/memory/style_guide.html` et `doc/memory/user_journeys.md` :
- [ ] Design coherent entre les pages, respecte le style guide
- [ ] Chaque parcours utilisateur est faisable de bout en bout
- [ ] Empty states avec message + CTA
- [ ] Etats d'erreur (formulaire invalide) visibles au moins une fois
- [ ] Actions destructives avec confirmation

### 7. Rapport

Generer `doc/memory/mockups/review.md` :

```markdown
# Mockup Review - [Date]

## Couverture: X/Y pages (vs routes.md)
## Scope brique: OK / marquages manquants [liste]
## Sync specs: N elements a ajouter aux specs [liste + proposition]
## Outil capture: OK / NON integre [details]
## Technique & style: OK / issues [liste]

## A CORRIGER avant client:
- [liste priorisee]

## Verdict: PRET POUR CLIENT / A CORRIGER
```

## Sortie

- **PRET POUR CLIENT** -> informer l'utilisateur, mockups presentables.
- **A CORRIGER** -> lister les corrections. Les corrections de mockups passent par
  `/brick-mockups` (jamais modifier les specs sans validation, cf. etape 3).
