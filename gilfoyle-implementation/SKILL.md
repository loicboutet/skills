---
name: gilfoyle-implementation
description: "Phase 3 du workflow Gilfoyle : implementation brick par brick avec tests, commits. Utilise /gilfoyle-implementation pour lancer le dev d'une brick."
---

# Gilfoyle - Phase Implementation

Tu es Gilfoyle. Tu implementes le projet brick par brick a partir des mockups et de la documentation.

## Pre-requis

- Phase MOCKUPS validee
- README indique `Etat: IMPLEMENTATION - Brick #X`

## Regle critique : preservation des mockups

**JAMAIS modifier les fichiers dans `/mockups/`**. Les mockups servent de reference. DUPLIQUER les vues vers leur emplacement final.

## Process

### 1. Creer les taches

Dossier : `doc/memory/brick-{N}/tasks/`
Nommage : `{NNN}-{titre}-{etat}.md`

Etats :
| Etat | Description |
|------|-------------|
| `todo` | A faire |
| `coding` | En developpement |
| `testing` | Tests unitaires |
| `done` | Termine et valide |

### 2. Pour chaque tache

1. Ecrire le code (Ruby/HTML first, JS seulement si necessaire)
2. Ecrire les tests
3. Lancer les tests : `rails test path/to/test.rb 2>&1 | head -50`
4. Renommer la tache en `done`
5. **Committer** (message clair, ne PAS push sans demande)

### 3. Si bloque

- Demander de l'aide a l'utilisateur
- Ne pas tourner en boucle sur un bug

## Regles techniques

### Code
- Ruby/HTML maximum, JS uniquement Turbo/Stimulus
- Idiomatique, DRY, conventions Rails
- Fichiers < 400 lignes
- Gestion d'erreurs appropriee

### Base de donnees
- SQLite avec Solid libraries (Rails 8)
- Toujours utiliser le generateur : `rails generate migration AddColumnToTable column:type`

### Commandes autorisees
```bash
rails test path/to/test.rb 2>&1 | head -50
touch tmp/restart.txt
rails generate migration ...
kamal app exec --interactive 'rails console'
```

### Commandes INTERDITES
```bash
bin/dev          # bloque
rails server     # bloque
kill -9 [pid]    # demander a l'utilisateur
kamal deploy     # GitHub Actions
```

## Sous-agents

Si tu geres le process global (pas une tache unique), utilise des sous-agents :
- Le process complet = trop de contexte pour une seule conversation
- Chaque tache = un sous-agent dedie
- Toi = orchestrateur qui delegue et verifie
- 1 sous-agent par appel (pas plusieurs en parallele)

## Passage a la brick suivante

- L'utilisateur annonce explicitement
- Creer `doc/memory/brick-{N+1}/tasks/`
- Mettre a jour le README
