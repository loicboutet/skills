# nexrai Skills for Claude Code

Skills pour le workflow de developpement nexrai.

## Installation

Ajouter le repo dans les settings du developer sur nexrai, ou dans `.claude/settings.json` :
```json
{
  "skills": ["https://github.com/loicboutet/skills"]
}
```

## Workflow Brick : la carte de l'usine

Nommage unique : **`brick-<etape>-<action>`**. Chaque etape suit le meme geste
`build → review → video`, avec `brief` / `guide` / `walkthrough` / `feedback` / `fix` la ou
c'est utile. Chaque skill finit par un pointeur `Ensuite →` : le workflow se navigue tout seul.

```
Fondations : analysis-build → analysis-review → [design-brief → design-build → design-review]
Boucle mockup : mockup-build → mockup-review → mockup-video ↻ mockup-feedback → mockup-reanalyse (gate)
Boucle code   : code-build → code-review → code-video (→ code-guide, code-walkthrough) ↻ code-feedback
                                                                          code-fix = methode bug
```

| Etape | Produire (build) | Relire (review) | Filmer (video) | Boucle retours (feedback) |
|-------|------------------|-----------------|----------------|---------------------------|
| **analysis** | `/brick-analysis-build` | `/brick-analysis-review` | `/brick-analysis-video` *(interne, option)* | — |
| **design** *(option)* | `/brick-design-brief` puis `/brick-design-build` | `/brick-design-review` | — | — |
| **mockup** | `/brick-mockup-build` | `/brick-mockup-review` | `/brick-mockup-video` | `/brick-mockup-feedback` |

Sortie de la boucle mockup : `/brick-mockup-reanalyse`, gate bloquante entre la validation
client des maquettes et `/brick-code-build` (matrice AC↔maquette, champ a champ affiche/saisi,
parcours navigues, tag `mockups-valides-brique-{N}`, verdict PRET / A CORRIGER).
| **code** | `/brick-code-build` | `/brick-code-review` | `/brick-code-video` | `/brick-code-feedback` |

Livrables en plus de l'etape code : `/brick-code-guide`, `/brick-code-walkthrough` (video longue),
`/brick-code-fix` (methode bug). Referentiel partage : `/taxonomie-recette` (classes de bugs T1-T15,
deroulees par code-review, alimentees par code-fix). Connaissance transverse : `/brain` (second cerveau cross-projet : chercher une conclusion réutilisable avant, distiller après). Rythme quotidien transverse : `/brick-daily-triage` (matin : tour
des canaux, tri par scope, execution + reponse sur le canal d'origine, escalade des decisions) puis
`/brick-daily-video` (soir : bilan chapitre de tous les changements, envoye au client). Hors-cycle :
`/brick-promo-video`.

Les etapes **mockup** et **code** sont des **boucles** : on presente au client, il renvoie ses
retours (widget → tracker, + emails/WhatsApp/Drive), `*-feedback` les traite, `*-video` refilme
les changements du jour, on recommence jusqu'a validation. Chaque skill a une **validation gate**.

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
