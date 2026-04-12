# nexrai Skills for Claude Code

Skills pour le workflow de développement nexrai. Conçus pour Claude Code.

## Installation

```bash
claude /install-skill https://github.com/loicboutet/skills
```

Ou ajouter dans `.claude/settings.json` :
```json
{
  "skills": ["https://github.com/loicboutet/skills"]
}
```

## Skills disponibles

### Workflow Gilfoyle (projet complet)

| Skill | Commande | Description |
|-------|----------|-------------|
| Analysis | `/gilfoyle-analysis` | Phase 1 : Analyse specs, data models, routes, style guide |
| Mockups | `/gilfoyle-mockups` | Phase 2 : Vues mockees, layouts, index |
| Implementation | `/gilfoyle-implementation` | Phase 3 : Dev brick par brick, tests, commits |

### Rails 8 / Hotwire

| Skill | Commande | Description |
|-------|----------|-------------|
| Vanilla Rails | `/vanilla-rails` | Review/simplify suivant les principes 37signals |
| Hotwire | `/rails-hotwire` | Features Turbo Frames, Streams, Stimulus |
| Models | `/rails-models` | Models, migrations, validations, scopes |
| Testing | `/rails-testing` | Tests Minitest, fixtures, system tests |
