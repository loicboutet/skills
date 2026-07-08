---
name: brick-implementation
description: "Phase 3 : implementation brick par brick avec tests, commits, tracabilite vers les criteres d'acceptance. Utilise /brick-implementation pour developper une brick."
---

# Brick Implementation

Implemente le projet brick par brick avec tracabilite vers les criteres d'acceptance.

## Mode de travail : fable-mode

Pour toute brick non triviale, **active et applique la skill `fable-mode`** (`/fable-mode`)
pendant toute l'implementation :
- **Plan multi-etapes explicite** avant de coder (numerote les etapes + sortie attendue).
- **Verification a chaque etape** (tests verts, criteres d'acceptance couverts) avant d'avancer.
- **Auto-critique** avant de committer / livrer.
- **Delegation** : 1 sous-agent par tache independante (voir la section "Sous-agents").

## Pre-requis

- Phase MOCKUPS validee
- README indique `Etat: IMPLEMENTATION - Brick #X`
- `doc/memory/acceptance_criteria.md` existe
- `doc/memory/user_journeys.md` existe

## Transition depuis les mockups

**JAMAIS modifier les fichiers dans `/mockups/`**. Les mockups servent de reference visuelle.

### Regle d'or : le markup mockup est IMMUABLE

Le client a valide les mockups au pixel pres. Toute liberte prise avec le rendu = retour client garanti.

1. **NE JAMAIS toucher au markup d'une vue mockup copiee.** La SEULE modification autorisee
   est de remplacer la liaison de donnees : `user[:name]` -> `user.name`.
   - Interdit : changer les classes Tailwind, la structure HTML, l'ordre des elements,
     ajouter/retirer des sections, "ameliorer" le design, transformer une vue mockee en
     "vraie" vue restructuree.
   - Si une vue mockup semble incomplete ou "fausse" : NE PAS la corriger soi-meme.
     Signaler a l'utilisateur, le mockup est la source de verite visuelle.

2. **ZERO faux objet dans les controleurs.** En implementation, les controleurs n'utilisent
   QUE de vrais modeles / requetes ActiveRecord. Aucun hash, `OpenStruct`, ou donnee fictive
   ne doit survivre du mockup vers le controleur reel.
   - Interdit : `@user = OpenStruct.new(name: "Marie")` ou un hash code en dur "pour que la vue
     s'affiche". Si le modele n'existe pas encore, le creer (voir `/rails-models`), pas le simuler.

3. **Process recommande (cadrage de l'IA/sous-agent) :** dans le prompt de chaque tache,
   imposer explicitement : "copie la vue mockup telle quelle, ne modifie QUE la liaison de
   donnees, modifie controleurs et modeles uniquement". Puis correction iterative manuelle.

4. **Auto-check pixel avant de marquer la tache `done`** : ouvrir cote a cote la vue mockup
   et la vue implementee, comparer section par section. Tout ecart non justifie = a corriger
   avant de continuer. Le check systematique se fait en `/brick-review` (etape Pixel match).

### Comment reutiliser les mockups

1. **Layouts** : copier `app/views/layouts/mockup_admin.html.erb` → `app/views/layouts/admin.html.erb`
   - Remplacer les liens mockups par les vraies routes
   - Garder la structure HTML/Tailwind identique

2. **Partials** : copier les partials mockups vers les vrais emplacements
   ```
   app/views/mockups/users/_user_card.html.erb → app/views/users/_user_card.html.erb
   app/views/mockups/users/_form.html.erb      → app/views/users/_form.html.erb
   app/views/mockups/shared/_sidebar.html.erb   → app/views/shared/_sidebar.html.erb
   ```

3. **Remplacer les donnees fictives** par les vraies :
   ```erb
   <%% # AVANT (mockup) : hash %>
   <%%= user[:name] %>

   <%% # APRES (implementation) : modele %>
   <%%= user.name %>
   ```

4. **Garder les memes noms de partials** pour faciliter la comparaison avec les mockups

5. **Supprimer les routes `/mockups/`** une fois toutes les vues copiees

## Widget de feedback : TOUJOURS verifier qu'il est installe

Le client annote l'app en recette via le widget de feedback (chaque annotation = une issue
dans le tracker nexrai). En implementation, la version **gated** doit etre presente dans les
layouts de la vraie app — le launcher reste cache pour les vrais utilisateurs et n'apparait
que si un testeur tape "bug" ou visite avec `?debug=true`.

### Verification

1. Chaque layout applicatif (`admin.html.erb`, `application.html.erb`, etc.) rend un partial
   `app/views/shared/_feedback_widget.html.erb` (juste avant `</body>`)
2. Le snippet contient bien `data-gated="true"` (sinon le widget est visible par tous les
   utilisateurs finaux — a corriger)
3. Ne PAS reprendre tel quel le partial mockup : lui n'est pas gated

### Installation si absent

1. Recuperer l'app id dans `.nexrai/binding.json` a la racine du projet
2. Appeler l'outil MCP `get_feedback_widget` avec cet `app_id` — utiliser le champ
   `app_snippet` (version gated) :

```erb
<%% # app/views/shared/_feedback_widget.html.erb %>
<script src="https://5000dev.nexrai.ai/feedback-widget.js"
        data-app-id="..."
        data-secret="..."
        data-project="..."
        data-gated="true"
        defer></script>
```

3. Rendre le partial dans chaque layout de l'app
4. Verifier : en navigation normale le widget est invisible ; avec `?debug=true` il apparait

Guide complet : artefact nexrai `feedback_widget_install` (app 37).

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
2. Ecrire les tests — strategie (voir `/rails-testing`) :
   - **Chaque AC = un test d'integration** dans `test/integration/`
   - **Validations critiques = test model** dans `test/models/`
   - Nommer le test avec la ref AC : `# R1/AC1.1: User peut s'inscrire`
3. Lancer : `rails test path/to/test.rb 2>&1 | head -50`
4. Renommer la tache en `done`
5. **Committer** (message clair, ne PAS push sans demande)

### 3. Convergence

Si un test echoue :
1. Diagnostiquer le probleme
2. Fixer
3. Relancer les tests
4. Max 3 iterations — apres, demander aide a l'utilisateur

### 4. Si bloque

- Demander de l'aide a l'utilisateur
- Ne pas tourner en boucle sur un bug

## Branches

- **Brick 1** : travailler sur `main` (pas de prod existante)
- **Brick 2+** : travailler sur `staging`, le client valide sur `projet-staging.5000.dev`
- **Committer sur la bonne branche** : verifier avec `git branch` avant de committer
- Quand la brick est validee → l'utilisateur merge staging dans main

## Retours client

Avant d'implementer un retour client, TOUJOURS :
1. Verifier `doc/memory/acceptance_criteria.md`
2. Si hors spec → signaler, demander confirmation
3. Si confirme → documenter le changement de scope
4. Ne JAMAIS implementer silencieusement un truc hors spec

## Regles techniques

- Ruby/HTML maximum, JS = Turbo/Stimulus (voir `/rails-hotwire`)
- Idiomatique, DRY, conventions Rails (voir `/vanilla-rails`)
- Fichiers < 400 lignes
- SQLite + Solid libraries (Rails 8)
- Migrations via generateur : `rails generate migration ...`
- Modeles : voir `/rails-models` pour les conventions

## Sous-agents

Pour un process multi-taches (pas une tache isolee) :
- Decouper en taches independantes
- 1 sous-agent par tache
- Toi = orchestrateur qui delegue, verifie, et passe a la suivante
- 1 sous-agent par appel (pas plusieurs en parallele)

## Passage a la brick suivante

0. Verifier que le widget de feedback (version gated) est present dans tous les layouts
1. Lancer `/brick-review` pour la validation pre-livraison
2. L'utilisateur valide la review
3. Creer `doc/memory/brick-{N+1}/tasks/`
4. Mettre a jour le README
