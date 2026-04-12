---
name: brick-review
description: "Pre-livraison : gap analysis, tests, criteres d'acceptance, couverture. Utilise /brick-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. Lance tous les checks avant de livrer.

## Quand utiliser

- Avant de livrer une brick au client
- Avant de passer a la brick suivante
- Quand l'utilisateur demande un check global

## Scope check

Avant la review, verifier qu'on n'a pas implemente de features hors spec :
- [ ] Tout le code implemente correspond a un critere d'acceptance
- [ ] Pas de features "bonus" non demandees
- [ ] Les changements de scope sont documentes dans les specs

## Process

### 1. Tests

```bash
rails test 2>&1 | tail -20
```

- [ ] Tous les tests passent
- [ ] Pas de tests skipped sans raison
- [ ] Les cas d'erreur importants sont couverts

### 2. Gap Analysis (built vs specified)

Comparer `doc/memory/acceptance_criteria.md` avec le code :

```markdown
## Gap Analysis - Brick #X

### Couvert
- [x] R1/AC1.1: User registration (/test/models/user_test.rb:15)
- [x] R1/AC1.2: Confirmation email (/test/mailers/user_mailer_test.rb:8)

### Manquant
- [ ] R2/AC2.3: Admin peut desactiver un compte (pas de test)

### Hors scope (ajoute pendant le dev)
- Extra: Pagination sur la liste users (pas dans les specs)
```

### 3. Review UX

Verifier les parcours utilisateurs de `doc/memory/user_journeys.md` :
- [ ] Chaque parcours est fonctionnel de bout en bout
- [ ] Les etats d'erreur sont geres (formulaire invalide, 404, etc.)
- [ ] Les messages flash sont presents et clairs
- [ ] La navigation est coherente

### 4. Review Code (vanilla Rails)

- [ ] Controllers < 7 actions (sinon extraire)
- [ ] Pas de logique business dans les controllers
- [ ] Modeles avec validations
- [ ] Pas de JS custom quand Turbo/Stimulus suffit
- [ ] Pas de N+1 queries (utiliser `includes`)
- [ ] Fichiers < 400 lignes

### 5. Security check

- [ ] Strong parameters sur tous les controllers
- [ ] Autorisation verifiee (l'utilisateur a acces a la ressource)
- [ ] Pas de donnees sensibles dans les logs
- [ ] CSRF protection active

### 6. Rapport

Generer un rapport dans `doc/memory/brick-{N}/review.md` :

```markdown
# Review Brick #X - [Date]

## Tests: X/Y passing
## Acceptance criteria: X/Y covered
## Gaps: [liste]
## Issues: [liste]
## Verdict: READY / NEEDS FIXES
```

## Sortie

Si READY → informer l'utilisateur, pret a livrer.
Si NEEDS FIXES → lister les fixes. Pour chaque fix, utiliser `/brick-bugfix` (test qui reproduit → fix → verify).
