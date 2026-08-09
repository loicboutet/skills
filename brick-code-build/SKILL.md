---
name: brick-code-build
description: "Phase 3 : implementation par lots recettes, DoD executable par tache (preuve collee), inventaire d'interfaces calcule, deviations de perimetre signalees, tests et system tests par parcours, tracabilite vers les criteres d'acceptance. Utilise /brick-code-build pour developper une brick."
---

# Brick Implementation

Implemente le projet brick par brick avec tracabilite vers les criteres d'acceptance.

## Mode de travail : fable-mode

Pour toute brick non triviale, **active et applique la skill `fable-mode`** (`/fable-mode`) :
plan multi-etapes explicite avant de coder, verification a chaque etape (tests verts, AC
couverts) avant d'avancer, auto-critique avant de committer, 1 sous-agent par tache
independante.

## Principe directeur : decider, consigner, ne pas demander

Le client connait le QUOI ; le COMMENT est notre travail. Pendant tout le build :

- **Inconnue sur le COMMENT** → on tranche avec un defaut motive, une ligne dans
  `doc/memory/decisions.md`, et on continue. On ne remonte rien.
- **Inconnue sur le QUOI** (regle metier, montant, droit, obligation) → on tranche
  QUAND MEME, ligne dans `decisions.md` avec la case « a signaler » cochee. Ce sera
  presente a la livraison comme un choix explique, jamais comme une question.
- **Fabriquer une DONNEE est interdit, sans exception** : compteur en dur, image
  inventee, score bidon, moyenne calculee sur du vide, texte de demo presente comme
  reel. Seule interdiction absolue. A la place : la vraie donnee, ou un **etat vide
  honnete**. (Tastellers : "127 connexions" en dur sur le dashboard d'un vrai client.)
- Chaque ligne de `decisions.md` deviendra un critere de recette : ecris-la testable.

## Pre-requis

- Reanalyse rendue : `doc/memory/brick-{N}/reanalyse.md` avec **verdict PRET**
  (sinon → `brick-mockup-reanalyse` d'abord)
- Tag `mockups-valides-brique-{N}` pose (reference visuelle de la brique)
- Kanban ecrit par la reanalyse : `doc/memory/brick-{N}/tasks/` avec, pour chaque
  tache, criteres couverts + perimetre prevu + preuve a produire
- `acceptance_criteria.md`, `user_journeys.md`, `jeu_de_donnees.md`, `decisions.md`,
  `config.md` existent ; README indique `Etat: IMPLEMENTATION - Brick #X`

## Transition depuis les mockups

**JAMAIS modifier les fichiers dans `/mockups/`**. Les mockups servent de reference visuelle.

### Regle d'or : le markup mockup est IMMUABLE

Le client a valide les mockups au pixel pres. Toute liberte prise avec le rendu = retour client garanti.

1. **NE JAMAIS toucher au markup d'une vue mockup copiee.** La SEULE modification autorisee
   est de remplacer la liaison de donnees : `user[:name]` -> `user.name`.
   - Interdit : changer les classes Tailwind, la structure HTML, l'ordre des elements,
     ajouter/retirer des sections, "ameliorer" le design, restructurer la vue.
   - Si une vue mockup semble incomplete ou "fausse" : NE PAS la corriger soi-meme.
     Signaler a l'utilisateur, le mockup est la source de verite visuelle.

2. **ZERO faux objet dans les controleurs.** En implementation, les controleurs n'utilisent
   QUE de vrais modeles / requetes ActiveRecord. Aucun hash, `OpenStruct`, ou donnee fictive
   ne doit survivre du mockup vers le controleur reel. Si le modele n'existe pas encore,
   le creer (voir `/rails-models`), pas le simuler.

3. **Cadrage du sous-agent :** dans le prompt de chaque tache, imposer explicitement :
   "copie la vue mockup telle quelle, ne modifie QUE la liaison de donnees, modifie
   controleurs et modeles uniquement".

4. **Auto-check pixel avant de marquer la tache `done`** : ouvrir cote a cote la vue mockup
   et la vue implementee, comparer section par section. Tout ecart non justifie = a corriger
   avant de continuer. Le check systematique se fait en `/brick-code-review`.

### Comment reutiliser les mockups

1. **Layouts** : copier `app/views/layouts/mockup_admin.html.erb` → `app/views/layouts/admin.html.erb`
   (remplacer les liens mockups par les vraies routes, garder la structure HTML/Tailwind)
2. **Partials** : copier les partials mockups vers les vrais emplacements
   ```
   app/views/mockups/users/_user_card.html.erb → app/views/users/_user_card.html.erb
   app/views/mockups/shared/_sidebar.html.erb  → app/views/shared/_sidebar.html.erb
   ```
3. **Remplacer les donnees fictives** par les vraies (`user[:name]` → `user.name`)
4. **Garder les memes noms de partials** pour faciliter la comparaison
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
  temps, volumes, second tenant) — les seeds les implementent TOUS.
- Dates en RELATIF (ERB dans les fixtures, `Date.current - n` dans les seeds) : la suite
  doit rester verte a J+90.
- **`db/seeds.rb` doit etre idempotent** (rejouable sans doublon : `find_or_create_by!`)
  et jouable sur une base VIDE (voir la mini-recette de fin de lot).
- INTERDIT d'inventer d'autres donnees de demo : la meme donnee traverse
  maquette → seed → recette → video.

## Manifeste de configuration

Toute tache qui introduit une variable d'environnement, une cle, un secret ou un
reglage par environnement l'ajoute a `doc/memory/config.md` AVANT de fermer la tache :
cle, **consommateur nomme** (`fichier:ligne` qui la LIT), valeur attendue en dev /
staging / prod, et ce qui casse si elle est absente. Une cle sans consommateur nomme
est une facade (audit qualite 08/2026 : ecran de saisie de la cle Postmark, jamais lue
a l'envoi). `brick-code-review` confronte ce manifeste a l'environnement livre.

## Widget de feedback : TOUJOURS verifier qu'il est installe

Le client annote l'app en recette via le widget (chaque annotation = une issue tracker).
La version **gated** doit etre presente dans les layouts de la vraie app.

1. Chaque layout applicatif rend `app/views/shared/_feedback_widget.html.erb` (avant `</body>`)
2. Le snippet contient `data-gated="true"` (sinon visible par tous les utilisateurs finaux)
3. Ne PAS reprendre le partial mockup : lui n'est pas gated
4. Le widget gated est INVISIBLE par defaut : il apparait en tapant "bug" sur la page,
   ou avec `?debug=true`. C'est normal qu'on ne voie rien avant. Tester les deux.

Installation si absent : app id dans `.nexrai/binding.json` → outil MCP
`get_feedback_widget` → champ `app_snippet` (gated) → rendre dans chaque layout.
Guide complet : artefact nexrai `feedback_widget_install` (app 37).

## Process

### 1. Ouvrir une tache

Le kanban vient de la reanalyse. Nommage : `{NNN}-{titre}-{etat}.md` — etats
`todo` → `coding` → `testing` → `done`. Verifier qu'aucune tache n'est deja `coding`.

**Avant d'ecrire la moindre ligne** :

1. Lire `doc/memory/brick-{N}/interfaces.md` (ce que les taches precedentes ont
   produit : modeles, methodes, routes, partials, services, jobs). On REUTILISE ce
   qui existe, on ne re-cree pas un helper ou un partial jumeau.
2. Poser la base de calcul de la tache :
   ```bash
   git rev-parse HEAD > tmp/task-{NNN}-base.sha
   bin/rails routes > tmp/routes-{NNN}-before.txt
   ```
3. Relire le **perimetre prevu** et la **preuve a produire** ecrits dans le fichier de tache.

### 2. Coder

1. Ecrire le code (Ruby/HTML first, JS = Turbo/Stimulus uniquement)
2. Ecrire les tests — strategie (voir `/rails-testing`) :
   - **Chaque AC = un test d'integration** dans `test/integration/`
   - **Validations critiques = test model** dans `test/models/`
   - Nommer le test avec la ref AC : `# R1/AC1.1: User peut s'inscrire`
3. **System test par parcours, ecrit AU FIL DES TACHES** : si la tache termine ou
   modifie un parcours de `user_journeys.md`, ecrire/completer le system test navigateur
   de ce parcours dans `test/system/` — un test PAR parcours, deroule avec le persona et
   les donnees canoniques. Les bugs Turbo ("form must redirect", action Stimulus non
   branchee, select sans `data-action`) sont INVISIBLES aux tests d'integration
   (constat de l'audit qualite 08/2026).
4. Chaque decision prise en chemin → une ligne dans `decisions.md` (defaut, motif,
   reversible, « a signaler » si QUOI). Chaque cle de config → `config.md`.

### 3. Fermer la tache : la preuve, l'inventaire, la deviation

**Une tache passe `done` uniquement apres avoir EXECUTE sa preuve et colle la sortie
reelle dans le fichier de tache.** "Done" declare sans sortie collee = interdit.

1. **DoD executee** : lancer les commandes exactes de la section "Preuve a produire",
   coller la sortie (`N runs, 0 failures`), puis ouvrir l'URL exacte avec le compte
   exact (`playwright-cli`) et verifier de ses yeux ce qui est ecrit dans "On doit voir"
   (capture jointe dans `doc/memory/brick-{N}/preuves/{NNN}-*.png`).
2. **Deviation de perimetre, CALCULEE** :
   ```bash
   BASE=$(cat tmp/task-{NNN}-base.sha)
   git diff --name-only $BASE..HEAD | sort
   ```
   Comparer a la section "Perimetre prevu". Ce n'est pas un verrou : c'est un signal.
   Toute ligne hors intention part dans le message de commit :
   ```
   Deviation: app/assets/tailwind/application.css (non prevu) — {raison en 1 ligne}
   ```
   Aucune deviation → `Deviation: aucune`. La review regarde ces lignes en priorite
   (c'est ainsi qu'on attrape la regression CSS auto-infligee, cf. audit Tastellers).
3. **Inventaire d'interfaces, CALCULE depuis le diff** (jamais redige a l'avance,
   jamais "prevu") — ajouter au fichier `doc/memory/brick-{N}/interfaces.md` :
   ```bash
   BASE=$(cat tmp/task-{NNN}-base.sha)
   # modeles / services / jobs : methodes publiques et associations ajoutees
   git diff $BASE..HEAD -- app/models app/services app/jobs \
     | grep -E '^\+\s*(def |scope |has_|belongs_to|validates )'
   # routes nouvelles
   bin/rails routes > tmp/routes-{NNN}-after.txt
   diff tmp/routes-{NNN}-before.txt tmp/routes-{NNN}-after.txt | grep '^>'
   # partials et controleurs Stimulus ajoutes
   git diff --name-only --diff-filter=A $BASE..HEAD -- 'app/views/**/_*' 'app/javascript/controllers/*'
   ```
   Format (append, on ne reecrit pas) :
   ```markdown
   ## Tache 003 — Formulaire client
   - Modeles : `Client#full_address` (String), `Client.active` (scope), `has_many :invoices`
   - Services : `Billing::TotalsCalculator.new(invoice).call` → Hash{ht:, tva:, ttc:}
   - Jobs : `SendInvoiceJob.perform_later(invoice_id)`
   - Routes : `GET /app/clients/:id/edit` (clients#edit), `PATCH /app/clients/:id`
   - Partials : `clients/_form`, `shared/_address_fields`
   - Stimulus : `clients--form` (actions : `change->clients--form#refreshDiscount`)
   ```
4. Renommer la tache en `done` et **committer** (message clair, ne PAS push sans demande).

### 4. Mini-recette de FIN DE LOT (obligatoire, bloquante)

Apres chaque lot de 4-5 taches, AVANT d'ouvrir le lot suivant :

1. Suite COMPLETE : `bin/rails test 2>&1 | tail -20` (pas fichier par fichier)
2. System tests : `bin/rails test:system 2>&1 | tail -20`
3. **Base fraiche depuis zero** (classe T16 de la taxonomie de recette) :
   ```bash
   RAILS_ENV=development bin/rails db:drop db:prepare db:seed 2>&1 | tail -20
   ```
   Doit passer sans erreur, migrations comprises, puis rejouer `db:seed` une seconde
   fois (idempotence, pas de doublon). Une migration qui appelle un modele applicatif
   se reecrit en SQL/`execute` ou en classe locale legere : le modele evoluera, pas
   la migration. (Provenance : `CreateDefaultAdmin` cassee sur base fraiche.)
4. `facade_scan` (`/outils-recette`, modes `readwrite` et `static`, `crawl` si le
   serveur tourne) — `readwrite` est le plus rentable des trois : il sort la colonne
   affichee que personne ne peut saisir et le champ saisi que personne ne lit. En jugeant les
   resultats : le scan ne voit pas les facades semantiques (colonne affichee sans
   saisie, cle stockee jamais lue), ce sont la matrice de la reanalyse et les classes
   T4/T5 de la taxonomie qui les couvrent
5. **Controle de simplicite** (relecture courte facon `/vanilla-rails`, 10 minutes) :
   lister ce que le lot a AJOUTE — gems, tables, colonnes, services, concerns,
   modules, controleurs Stimulus, abstractions. Pour chacun : quel AC ou quelle ligne
   de `decisions.md` il sert ? **Sans rattachement, on retire** (ou on trace l'AC
   manquant). On veut du code simple qui marche, sans cas a la con qui traine.
6. Tout rouge se corrige DANS le lot. Un lot ne se ferme pas avec des tests rouges,
   une base fraiche cassee, ou une abstraction orpheline.

### 5. Convergence

Si un test echoue : diagnostiquer → fixer → relancer. Max 3 iterations, apres quoi
demander de l'aide a l'utilisateur. Ne pas tourner en boucle sur un bug.

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
- Fichiers < 400 lignes ; SQLite + Solid libraries (Rails 8)
- Auth : Devise (voir plus haut), jamais d'auth maison
- Migrations via generateur (`rails generate migration ...`), sans dependance a un
  modele applicatif, rejouables sur base fraiche
- Modeles : voir `/rails-models`
- Pages publiques : appliquer `/brick-seo` (helpers SEO, friendly_id, 301, sitemap au
  build Kamal, staging noindex, CWV)

## Sous-agents

Decouper en taches independantes, 1 sous-agent par tache, 1 sous-agent par appel.
Toi = orchestrateur qui delegue, verifie la preuve executee, et passe a la suivante.
Transmettre au sous-agent : le fichier de tache (perimetre + DoD), `interfaces.md`,
et les regles de decision ci-dessus.

## Passage a la brick suivante

0. Widget de feedback (gated) present dans tous les layouts
1. Chaque parcours de `user_journeys.md` a son system test vert
2. `interfaces.md`, `decisions.md` et `config.md` a jour du dernier commit
3. Lancer `/brick-code-review` pour la validation pre-livraison
4. L'utilisateur valide la review
5. Creer `doc/memory/brick-{N+1}/tasks/`, mettre a jour le README

## Ensuite

→ `brick-code-review` (pre-livraison).
