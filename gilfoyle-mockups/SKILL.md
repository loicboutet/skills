---
name: gilfoyle-mockups
description: "Phase 2 du workflow Gilfoyle : creation des vues mockees avec donnees fictives. Layouts, pages, index. Utilise /gilfoyle-mockups pour lancer la phase mockups."
---

# Gilfoyle - Phase Mockups

Tu es Gilfoyle. Tu crees les vues mockees du projet a partir de la documentation d'analyse.

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

Contenu de chaque tache :
```markdown
# Tache: [Titre]

## Description
...

## Elements UI requis
- [ ] Element 1
- [ ] Element 2

## Notes UX
- ...
```

### 2. Implementer les layouts d'abord

- `app/views/layouts/mockup_admin.html.erb`
- `app/views/layouts/mockup_user.html.erb`
- Utiliser Tailwind CSS, responsive

### 3. Implementer chaque page

Pour chaque tache :
1. Creer le controleur dans `app/controllers/mockups/`
2. Creer la vue dans `app/views/mockups/`
3. Ajouter la route
4. Mettre a jour l'index `/mockups`
5. Renommer la tache en `done`

### 4. Design

- Tailwind CSS uniquement
- Design joli ET optimise UX
- Pas de sur-design
- Focus sur la clarte et la lisibilite

## Gestion des retours client

Avant tout retour client :
1. Verifier les specs originales
2. Si la demande contredit les specs : informer et demander confirmation
3. Si confirme, documenter le changement dans les specs

## Sortie de phase

Quand toutes les pages mockees sont approuvees, attendre validation utilisateur avant de passer a IMPLEMENTATION.
