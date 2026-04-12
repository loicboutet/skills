---
name: vanilla-rails
description: "Review et simplification de code Rails suivant les principes 37signals/DHH. Utilise /vanilla-rails pour analyser du code ou /vanilla-rails simplify [goal] pour simplifier."
---

# Vanilla Rails - 37signals Style

Review et simplification de code suivant la philosophie 37signals/Basecamp/DHH.

## Principes

### Architecture
- **Server-rendered HTML** par defaut, JS seulement si necessaire
- **Fat Model, Thin Controller** - business logic dans les modeles
- **RESTful controllers** - 7 actions standard (index, show, new, create, edit, update, destroy)
- Si un controller a besoin de plus d'actions, extraire un nouveau controller
- **Concerns** pour partager du comportement entre modeles/controllers

### Hotwire
- **Turbo Drive** : navigation SPA gratuite
- **Turbo Frames** : mise a jour partielle de page
- **Turbo Streams** : updates temps reel via Action Cable
- **Stimulus** : JS minimal pour le comportement cote client
- **Broadcast depuis les modeles** (after_create_commit, etc.)

### Base de donnees
- SQLite pour les petits/moyens projets (Rails 8 way)
- Solid Queue, Solid Cache, Solid Cable
- Migrations simples, reversibles

### Pas de sur-ingenierie
- Pas de service objects sauf si vraiment necessaire
- Pas de decorators/presenters quand un helper suffit
- Pas de form objects quand accepts_nested_attributes suffit
- Pas de DDD/hexagonal/clean architecture

## Commandes

### Review
Analyser le code existant et identifier :
- Controllers avec trop d'actions (> 7)
- Logique business dans les controllers
- JS qui pourrait etre remplace par Turbo/Stimulus
- Queries N+1
- Modeles sans validations

### Simplify
Proposer des simplifications :
- Extraire concerns
- Remplacer JS custom par Turbo Frames/Streams
- Deplacer la logique dans les modeles
- Utiliser les conventions Rails (resourceful routes, etc.)

## Anti-patterns a signaler

- `respond_to` avec plus de 2 formats
- Callbacks complexes (preferer des methodes explicites)
- `before_action` qui fait de la logique business
- Helpers de plus de 10 lignes (extraire en partial/component)
- Tests qui mockent tout (preferer les tests d'integration)
