---
name: brick-analysis
description: "Phase 1 : analyse des specs, data models, routes, style guide, criteres d'acceptance. Utilise /brick-analysis pour demarrer l'analyse d'un projet ou d'une nouvelle brick."
---

# Brick Analysis

Analyse les specs et cree la documentation technique avec des criteres d'acceptance tracables.

## Quand utiliser

- Nouveau projet sans README ou avec `Etat: ANALYSIS`
- Nouvelle brick ajoutee au projet

## Process

### 1. Collecter les informations

- Lire les specs fournies (system prompt, fichiers, conversations)
- Si des outils Leexi sont disponibles, recuperer les conversations client
- **Toujours demander** : "Y a-t-il des bricks additionnelles ?"
- Demander clarifications si necessaire

### 2. Creer `doc/memory/data_models.md`

Pour chaque modele :
- Responsabilites
- Attributs (nom, type, description)
- Relations
- Methodes principales

Inclure un historique des modifications (date + modeles ajoutes/modifies).

### 3. Creer `doc/memory/routes.md`

Regles :
- Un namespace par profil (`/admin/`, `/users/`, etc.)
- JAMAIS `/analysis` ET `/dashboard` pour le meme profil
- Max 3-5 actions rapides par ressource
- TOUJOURS des routes pour gerer les cles API
- JAMAIS de routes monitoring systeme

### 4. Creer `doc/memory/acceptance_criteria.md`

Chaque feature a des criteres testables et tracables.

```markdown
# Acceptance Criteria

## Feature: [Nom]
### Requirements
- R1: [Description]
  - [ ] AC1.1: [Critere verifiable]
  - [ ] AC1.2: [Critere verifiable]

- R2: [Description]
  - [ ] AC2.1: [Critere verifiable]
```

Chaque critere doit etre :
- **Specifique** : pas "ca marche bien" mais "l'utilisateur voit un message de succes"
- **Testable** : peut etre verifie par un test automatise ou manuel
- **Tracable** : reference dans les taches d'implementation (R1 → tache 003)

### 5. Creer `doc/memory/user_journeys.md`

Definir les parcours utilisateurs cles. Chaque parcours = un chemin complet dans l'app.

```markdown
# User Journeys

## Profil: Admin

### Parcours: Gestion des utilisateurs
1. Admin se connecte → Dashboard
2. Click "Utilisateurs" → Liste paginee
3. Click "Nouveau" → Formulaire creation
4. Remplit le formulaire → Validation
5. Succes → Redirect vers profil avec flash "Utilisateur cree"
6. Erreur → Formulaire avec messages d'erreur

### Parcours: ...

## Profil: User

### Parcours: Premiere utilisation (onboarding)
1. User recoit email d'invitation
2. Click lien → Page de creation de mot de passe
3. Remplit → Redirect vers onboarding wizard
4. Complete les etapes → Redirect vers dashboard
```

Pour chaque parcours :
- **Entree** : comment l'utilisateur arrive
- **Etapes** : chaque action et la reponse attendue
- **Succes** : ou ca mene quand tout va bien
- **Erreurs** : les cas d'erreur et comment on les gere
- **Sortie** : ou l'utilisateur finit

### 6. Verifier `doc/memory/style_guide.html`

- Si fourni : utiliser tel quel
- Si elements fournis : generer
- Si rien : DEMANDER (couleurs, fonts, style)

### 6. Mettre a jour le README.md

```markdown
## Etat du projet
Etat: ANALYSIS COMPLETE

## Documentation
- [x] data_models.md
- [x] routes.md
- [x] acceptance_criteria.md
- [x] user_journeys.md
- [x] style_guide.html

Pret pour MOCKUPS
```

## Validation gate

Avant de passer a MOCKUPS, verifier :
- [ ] Tous les modeles ont des relations coherentes
- [ ] Les routes couvrent toutes les features des specs
- [ ] Chaque feature a au moins 2 criteres d'acceptance
- [ ] Les parcours utilisateurs couvrent tous les profils
- [ ] Le style guide est defini (sinon lancer `/brick-design`)
- [ ] L'utilisateur a valide
