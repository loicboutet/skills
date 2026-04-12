---
name: brick-mockups
description: "Phase 2 : creation des vues mockees avec donnees fictives. Layouts, pages, index. Utilise /brick-mockups pour lancer la phase mockups."
---

# Brick Mockups

Cree les vues mockees du projet a partir de la documentation d'analyse.

## Pre-requis

- `doc/memory/data_models.md` existe
- `doc/memory/routes.md` existe
- `doc/memory/style_guide.html` existe
- README indique `Pret pour MOCKUPS`

## Regles fondamentales

- **JAMAIS de modeles** - Uniquement vues et controleurs
- **Tout dans `/mockups/`** namespace
- **Un layout par type d'utilisateur** (memes couleurs pour tous)
- **Index `/mockups`** = liste de toutes les pages par profil
- **Donnees fictives** directement dans les controleurs

## Process

### 1. Creer les taches

Dossier : `doc/memory/mockups/tasks/`
Nommage : `{NNN}-{titre}-{etat}.md`
Etats : `todo`, `inprogress`, `done`

### 2. Implementer les layouts d'abord

- `app/views/layouts/mockup_admin.html.erb`
- `app/views/layouts/mockup_user.html.erb`
- Tailwind CSS, responsive, accessible

### 3. Implementer chaque page

1. Creer le controleur dans `app/controllers/mockups/`
2. Creer la vue dans `app/views/mockups/`
3. Ajouter la route
4. Mettre a jour l'index `/mockups`
5. Renommer la tache en `done`

### 4. Design challenge (inspire de Cavekit)

Avant de presenter les mockups au client, auto-review :
- Les pages couvrent-elles toutes les routes de `routes.md` ?
- Les donnees affichees correspondent-elles aux attributs de `data_models.md` ?
- Le design respecte-t-il le `style_guide.html` ?
- L'UX est-elle coherente entre les pages du meme profil ?

## Gestion des retours client

1. Verifier les specs originales
2. Si la demande contredit les specs : informer et demander confirmation
3. Si confirme, documenter le changement

## Verification UX

Avant de presenter les mockups, verifier avec `doc/memory/user_journeys.md` :
- [ ] Chaque parcours utilisateur est realise bout en bout dans les mockups
- [ ] Les etats d'erreur sont visibles (formulaire invalide, page vide, 404)
- [ ] Les empty states ont un message + CTA
- [ ] La navigation permet de suivre chaque parcours sans impasse
- [ ] Les actions destructives ont une confirmation

## Validation gate

Avant de passer a IMPLEMENTATION :
- [ ] Toutes les pages de `routes.md` ont un mockup
- [ ] L'index `/mockups` liste toutes les pages
- [ ] Le design est coherent entre les pages
- [ ] Les parcours utilisateurs sont fluides
- [ ] L'utilisateur a valide
