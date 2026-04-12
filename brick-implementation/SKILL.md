---
name: brick-implementation
description: "Phase 3 : implementation brick par brick avec tests, commits, tracabilite vers les criteres d'acceptance. Utilise /brick-implementation pour developper une brick."
---

# Brick Implementation

Implemente le projet brick par brick avec tracabilite vers les criteres d'acceptance.

## Pre-requis

- Phase MOCKUPS validee
- README indique `Etat: IMPLEMENTATION - Brick #X`
- `doc/memory/acceptance_criteria.md` existe

## Regle critique : preservation des mockups

**JAMAIS modifier les fichiers dans `/mockups/`**. DUPLIQUER les vues vers leur emplacement final.

## Process

### 1. Creer les taches

Dossier : `doc/memory/brick-{N}/tasks/`
Nommage : `{NNN}-{titre}-{etat}.md`

Chaque tache reference les criteres d'acceptance :
```markdown
# Tache: User Registration

## Criteres couverts
- R1/AC1.1: L'utilisateur peut s'inscrire avec email/password
- R1/AC1.2: Un email de confirmation est envoye

## Implementation
...
```

Etats : `todo` → `coding` → `testing` → `done`

### 2. Pour chaque tache

1. Ecrire le code (Ruby/HTML first, JS = Turbo/Stimulus uniquement)
2. Ecrire les tests — voir `/rails-testing` pour la strategie :
   - **Chaque AC → un test d'integration** (`test/integration/`)
   - **Validations critiques → test model** (`test/models/`)
   - Nommer le test avec la ref AC : `# R1/AC1.1: User peut s'inscrire`
3. Lancer : `rails test path/to/test.rb 2>&1 | head -50`
4. Renommer la tache en `done`
5. **Committer** (message clair, ne PAS push sans demande)

### 3. Convergence (inspire de Cavekit)

Si un test echoue :
1. Diagnostiquer le probleme
2. Fixer
3. Relancer les tests
4. Max 3 iterations, apres demander aide a l'utilisateur

### 4. Si bloque

- Demander de l'aide a l'utilisateur
- Ne pas tourner en boucle

## Regles techniques

- Ruby/HTML maximum, JS = Turbo/Stimulus
- Idiomatique, DRY, conventions Rails
- Fichiers < 400 lignes
- SQLite + Solid libraries (Rails 8)
- Migrations via generateur : `rails generate migration ...`

## Sous-agents

Si process global (pas une tache unique) :
- Chaque tache = un sous-agent dedie
- Toi = orchestrateur
- 1 sous-agent par appel

## Passage a la brick suivante

- L'utilisateur annonce explicitement
- Lancer `/brick-review` avant de livrer
- Creer `doc/memory/brick-{N+1}/tasks/`
