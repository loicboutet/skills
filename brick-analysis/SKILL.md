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

#### Rattachement : chaque feature sert une fin

Une feature ne vaut rien en soi, elle vaut dans la mesure ou elle sert un
critere d'acceptance. Passer la liste des features envisagees une par une et
nommer l'AC que chacune sert. L'exercice consiste a le faire feature par
feature et a l'ecrire, pas a s'en souvenir en general.

Une feature qui ne se rattache a aucun AC n'est pas un bonus, c'est du poids
mort qu'on portera pendant toute la vie du projet. Deux issues possibles :
soit elle revele un AC manquant (l'ajouter et le tracer), soit elle est hors
scope (le dire a l'utilisateur avant de la mettre dans les mockups).

### 5. Creer `doc/memory/user_journeys.md`

Definir les parcours utilisateurs cles. Chaque parcours = un chemin complet dans l'app.

#### Composition de lieu (a faire AVANT d'ecrire les parcours)

Un persona abstrait ("Marie, 42 ans, responsable RH") ne produit aucune
decision de design. Avant d'ecrire les parcours d'un profil, se representer
concretement la situation reelle et repondre par ecrit :

- A quelle heure il ouvre l'app, sur quel appareil, quelle taille d'ecran
- Ce qu'il faisait juste avant, ce qu'il fera juste apres
- Ce qu'il a d'autre sous les yeux au meme moment (un mail, un tableur, un
  client au telephone, un dossier papier a recopier)
- Combien de temps il a devant lui, et qui peut l'interrompre
- Ce qui se passe pour lui si l'app est indisponible ce jour-la
- A quelle frequence il fait ca : dix fois par jour ou une fois par trimestre

Trois a cinq lignes par profil, en tete de sa section dans
`user_journeys.md`. C'est ce qui determine la densite d'information des
ecrans, le nombre de clics tolerable, ce qui doit tenir sans scroll et ce
qui merite un raccourci clavier. Un usage dix fois par jour et un usage
trimestriel ne donnent pas la meme interface.

Si on ne sait pas repondre a une question, c'est une question a poser au
client, jamais a inventer.

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
- [ ] Chaque feature envisagee est rattachee a un AC nomme (aucune orpheline)
- [ ] Les parcours utilisateurs couvrent tous les profils
- [ ] Chaque profil a sa composition de lieu, sans trou invente
- [ ] Le style guide est defini (sinon lancer `/brick-design`)
- [ ] L'utilisateur a valide
