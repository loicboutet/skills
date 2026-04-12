# nexrai Skills for Claude Code

Skills pour le workflow de developpement nexrai.

## Installation

Ajouter le repo dans les settings du developer sur nexrai, ou dans `.claude/settings.json` :
```json
{
  "skills": ["https://github.com/loicboutet/skills"]
}
```

## Workflow Brick

Pipeline complet pour livrer un projet client, de l'analyse a la livraison.

```
/brick-analysis → /brick-design → /brick-mockups → /brick-implementation → /brick-review
                    (optionnel)
```

| Skill | Commande | Description |
|-------|----------|-------------|
| Analysis | `/brick-analysis` | Specs, data models, routes, criteres d'acceptance, parcours utilisateurs |
| Design | `/brick-design` | Creer une charte graphique quand le client n'en a pas |
| Mockups | `/brick-mockups` | Vues mockees, layouts, verification UX des parcours |
| Implementation | `/brick-implementation` | Dev brick par brick, tests, tracabilite vers les criteres |
| Review | `/brick-review` | Pre-livraison : gap analysis, tests, UX, securite |

Chaque phase a une **validation gate** — checklist a cocher avant de passer a la suivante.

## Rails 8 / Hotwire

Skills techniques utilisables a tout moment.

| Skill | Commande | Description |
|-------|----------|-------------|
| Vanilla Rails | `/vanilla-rails` | Review/simplify a la 37signals (RESTful, fat model, Hotwire first) |
| Hotwire | `/rails-hotwire` | Decision tree Turbo Frames/Streams/Stimulus + patterns |
| Models | `/rails-models` | Models, migrations, validations, scopes, SQLite Rails 8 |
| Testing | `/rails-testing` | Minitest, fixtures, integration tests, Turbo Stream tests |

## Inspirations

- [Cavekit](https://github.com/JuliusBrussee/cavekit) — spec-first, criteres d'acceptance tracables, gap analysis
- [superpowers-ruby](https://github.com/lucianghinda/superpowers-ruby) — skills Rails/Hotwire
- [vanilla-rails](https://github.com/obie/claude-on-rails) — 37signals philosophy
- [BMAD Method](https://github.com/bmadcode/BMAD-METHOD) — workflows adaptatifs, facilitation
