---
name: brick-code-build
description: "Phase 3 : implementation brick par brick, par lots recettes, avec tests, system tests par parcours, commits, tracabilite vers les criteres d'acceptance. Utilise /brick-code-build pour developper une brick."
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

- Phase MOCKUPS validee ET reanalyse rendue : `doc/memory/brick-{N}/reanalyse.md`
  avec **verdict PRET** (sinon → `brick-mockup-reanalyse` d'abord)
- Tag `mockups-valides-brique-{N}` pose (reference visuelle de la brique)
- README indique `Etat: IMPLEMENTATION - Brick #X`
- `doc/memory/acceptance_criteria.md`, `user_journeys.md`, `jeu_de_donnees.md` existent

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
   avant de continuer. Le check systematique se fait en `/brick-code-review` (rapport de parite).

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

3. **Remplacer les donnees fictives** par les vraies (`user[:name]` → `user.name`)

4. **Garder les memes noms de partials** pour faciliter la comparaison avec les mockups

5. **Ne JAMAIS supprimer `/mockups/` ni ses routes, et les laisser ACCESSIBLES
   EN PRODUCTION.** C'est voulu : le client suit les briques a venir sur l'app
   livree. Le namespace reste dans le repo pour toute la vie du projet, cumulatif
   d'une brique a l'autre (les maquettes de la brique 1 restent quand la 2 arrive) :
   c'est la reference du rapport de parite ET la vitrine de la suite. Deux seules
   contraintes : `noindex` sur ces pages (elles ne doivent pas remonter dans les
   moteurs a la place des vraies) et aucune donnee client reelle dans les donnees
   fictives. La version validee client est figee par le tag
   `mockups-valides-brique-{N}` : c'est le tag, pas une copie, qui garantit la
   reference. Quand une page maquette a ete livree pour de vrai, le hub `/mockups`
   l'indique et pointe vers l'ecran reel.

## Authentification : Devise, obligatoire

Decision 08/2026 : toute authentification passe par **Devise**. JAMAIS d'auth native
ou maison (`has_secure_password`, sessions a la main, generateur d'auth Rails 8).
Si un socle existant a une auth maison : signaler a l'utilisateur, ne pas l'etendre.

## Seeds & fixtures = jeu de donnees canonique

`db/seeds.rb` et les fixtures reproduisent `doc/memory/jeu_de_donnees.md` :
- Memes personas (noms, emails, roles, droits), memes entites, memes valeurs exactes.
- TOUS les cas etiquetes du jeu (etats difficiles, argent aux bornes, chaines hostiles,
  temps, volumes, second tenant) — regle de propagation : les seeds les implementent TOUS.
- Dates en RELATIF (ERB dans les fixtures, `Date.current - n` dans les seeds) : la suite
  doit rester verte a J+90.
- INTERDIT d'inventer d'autres donnees de demo : la meme donnee traverse
  maquette → seed → recette → video.

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
4. Le widget gated est INVISIBLE par defaut : on l'active en **tapant le mot "bug"**
   n'importe ou sur la page (ou en visitant avec `?debug=true`). C'est normal qu'on ne
   voie rien tant qu'on n'a pas tape "bug" — ne pas croire qu'il est casse.

### Installation si absent

1. Recuperer l'app id dans `.nexrai/binding.json` a la racine du projet
2. Appeler l'outil MCP `get_feedback_widget` avec cet `app_id` — utiliser le champ
   `app_snippet` (version gated)
3. Rendre le partial dans chaque layout de l'app
4. Verifier l'activation : invisible en navigation normale ; apparait quand on tape
   "bug" (ou avec `?debug=true`). Tester les deux.

Guide complet : artefact nexrai `feedback_widget_install` (app 37).

## Process

### 1. Creer les taches, organisees en LOTS

Dossier : `doc/memory/brick-{N}/tasks/`
Nommage : `{NNN}-{titre}-{etat}.md` — Etats : `todo` → `coding` → `testing` → `done`

Chaque tache reference les criteres d'acceptance :
```markdown
# Tache: User Registration

## Criteres couverts
- R1/AC1.1: L'utilisateur peut s'inscrire avec email/password
- R1/AC1.2: Un email de confirmation est envoye
```

**Regrouper les taches en lots de 4-5 maximum** (numeroter le lot dans le fichier de
tache). JAMAIS toute la brique d'un bloc : le premier regard exterieur sur 15 000
lignes d'un coup, c'est trop tard (constat de l'audit 08/2026 : 19 taches en un jour).

### 2. Pour chaque tache

1. Ecrire le code (Ruby/HTML first, JS = Turbo/Stimulus uniquement)
2. Ecrire les tests — strategie (voir `/rails-testing`) :
   - **Chaque AC = un test d'integration** dans `test/integration/`
   - **Validations critiques = test model** dans `test/models/`
   - Nommer le test avec la ref AC : `# R1/AC1.1: User peut s'inscrire`
3. **System test par parcours, ecrit AU FIL DES TACHES** : si la tache termine ou
   modifie un parcours de `user_journeys.md`, ecrire/completer le system test
   navigateur de ce parcours dans `test/system/` — un test PAR parcours, qui deroule
   le parcours de bout en bout avec le persona et les donnees canoniques.
   Raison : les bugs Turbo ("form must redirect", action Stimulus non branchee,
   select sans `data-action`) sont INVISIBLES aux tests d'integration
   (constat de l'audit 08/2026). Le walkthrough final = tournage, pas decouverte.
4. Lancer : `rails test path/to/test.rb 2>&1 | head -50`
5. Renommer la tache en `done`
6. **Committer** (message clair, ne PAS push sans demande)

### 3. Mini-recette de FIN DE LOT (obligatoire, bloquante)

Apres chaque lot de 4-5 taches, AVANT d'ouvrir le lot suivant :

1. Suite COMPLETE : `rails test 2>&1 | tail -20` (pas fichier par fichier)
2. System tests : `rails test:system 2>&1 | tail -20`
3. Scan de facades (script `facade_scan` ou equivalent : inputs sans `name`, actions
   Stimulus orphelines, liens vers routes inexistantes, donnees en dur dans les vues
   copiees) si disponible — en jugeant les resultats : le scan ne voit pas les facades
   semantiques (colonne affichee sans saisie, cle stockee jamais lue), c'est la matrice
   de la reanalyse et les classes T4/T5 de la taxonomie de recette qui les couvrent
4. Tout rouge se corrige DANS le lot. Un lot ne se ferme pas avec des tests rouges.

### 4. Convergence

Si un test echoue :
1. Diagnostiquer le probleme
2. Fixer
3. Relancer les tests
4. Max 3 iterations — apres, demander aide a l'utilisateur

### 5. Si bloque

- Demander de l'aide a l'utilisateur
- Ne pas tourner en boucle sur un bug

## Branches

- **Brick 1** : travailler sur `main` (pas de prod existante)
- **Brick 2+** : travailler sur `staging`, le client valide sur `projet-staging.5000.dev`
- **Committer sur la bonne branche** : verifier avec `git branch` avant de committer
- Quand la brick est validee → l'utilisateur merge staging dans main

## Retours client

Avant d'implementer un retour client, TOUJOURS :
1. Arbitrer contre `doc/memory/objectif.md` (le QUOI signe) : la demande sert le
   QUOI → due ; hors du QUOI → later_brick ou avenant, reponse qui cite l'objectif
2. Verifier `doc/memory/acceptance_criteria.md` (le COMMENT)
3. Si hors spec → signaler, demander confirmation
4. Si confirme → documenter le changement de scope (journal de scope)
5. Ne JAMAIS implementer silencieusement un truc hors spec

## Regles techniques

- Ruby/HTML maximum, JS = Turbo/Stimulus (voir `/rails-hotwire`)
- Idiomatique, DRY, conventions Rails (voir `/vanilla-rails`)
- Fichiers < 400 lignes
- SQLite + Solid libraries (Rails 8)
- Auth : Devise (voir plus haut), jamais d'auth maison
- Migrations via generateur : `rails generate migration ...`
- Modeles : voir `/rails-models` pour les conventions
- Pages publiques : appliquer `/brick-seo` (section "Phase code" : helpers SEO, friendly_id,
  301, sitemap au build Kamal, staging noindex, CWV)

## Sous-agents

Pour un process multi-taches (pas une tache isolee) :
- Decouper en taches independantes
- 1 sous-agent par tache
- Toi = orchestrateur qui delegue, verifie, et passe a la suivante
- 1 sous-agent par appel (pas plusieurs en parallele)

## Passage a la brick suivante

0. Verifier que le widget de feedback (version gated) est present dans tous les layouts
1. Verifier que chaque parcours de `user_journeys.md` a son system test vert
2. Lancer `/brick-code-review` pour la validation pre-livraison
3. L'utilisateur valide la review
4. Creer `doc/memory/brick-{N+1}/tasks/`
5. Mettre a jour le README

## Ensuite

→ `brick-code-review` (pre-livraison).
