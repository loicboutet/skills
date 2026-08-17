---
name: outils-recette
description: Le balayage de recette, en une invocation, sur n'importe quel projet Rails de l'atelier et a n'importe quelle phase - facades non branchees (facade_scan), paires maquette/ecran generees (pairs_gen), ecart de style aux deux viewports (style_diff), rendus en UN rapport priorise. Utilise /outils-recette pour "fais le balayage", un audit, une review pre-livraison, ou juste "les facades" / "le mobile".
---

# Balayage de recette

Une invocation, un rapport. L'agent qui charge ce skill DÉROULE la procédure
ci-dessous sans rien demander : il détecte le projet, lance les scans, démarre
et arrête le serveur, et rend un rapport priorisé. La documentation des outils
vient après, pour le résidu.

Trois règles qui ne se négocient pas :

1. **Rien n'est saisi à la main.** `pairs.json` est généré, pas écrit.
2. **Ce qui n'a pas pu être mesuré est dit.** Un rapport vide n'est pas un feu
   vert : « serveur non démarrable », « pas de maquettes », « connexion
   introuvable » sont des conclusions, et elles se mettent en tête.
3. **Le projet audité n'est pas modifié.** Les artefacts vont dans
   `/tmp/recette-<projet>/` (ou `doc/memory/brick-{N}/parite/` si le balayage
   sert une livraison). `git status` doit être identique avant et après.

Dans les commandes, `$SK` = `~/.claude/skills/outils-recette`.

---

## Procédure

### 0. Le projet et sa branche

```bash
cd <projet>
git status --porcelain > /tmp/recette-git-avant.txt     # référence de propreté
git branch --sort=-committerdate --format='%(committerdate:short)  %(refname:short)' | head -5
git log -1 --format='%h %ad %s' --date=short
```

Compare la date de la branche courante à la plus récente des branches locales.
**Si la branche courante n'est pas la plus récente, écris-le en tête du rapport
et dis sur quoi tu as balayé.** Le piège est réel : un projet du parc avait sa
`main` figée trois semaines en arrière, tout le travail vivait sur `staging`, et
l'audit de `main` racontait un projet qui n'existait plus.

Note aussi la phase, elle change la lecture :

| Ce que tu vois | Phase | Ce qui a du sens |
|---|---|---|
| `app/views/mockups/**` seul, pas de contrôleurs applicatifs | MOCKUP | `facade_scan --mockups`, pas de parité |
| maquettes **et** écrans réels | CODE | le balayage complet |
| pas de `app/views/mockups` | livré, ou maquettes hors dépôt | façades seules, et le dire |

### 1. Les façades (sans serveur, rapide)

```bash
ruby $SK/facade_scan.rb readwrite .        # colonnes en sens unique + colonnes seed-only
ruby $SK/facade_scan.rb static .           # contrôles non branchés dans les vues
ruby $SK/mockup_scan.rb inventory .        # blocs inventés / promesses non tenues
```

Lance-les depuis le répertoire du projet (rbenv y choisit le bon Ruby). En phase
maquettes, ajoute `--mockups` aux deux premiers ; `inventory` n'a de sens qu'en
phase CODE, quand les deux côtés existent. Ajoute `reachability .` si tu veux
aussi les routes qu'aucun geste n'atteint (plus bruyant, garde-le pour une
review). Ces modes sortent en 0 : ce sont des rapports. Une sortie 2 = scan
interrompu, le rapport est incomplet et le dit en tête.

Les deux **bloquants** à ne jamais laisser passer en livraison, parce qu'ils ne
se voient pas en développement :

- `column_seed_only` : un champ affiché que seuls `db/seeds.rb` ou des fixtures
  remplissent. Vide ou figé chez le vrai client, juste chez toi ;
- `inventory / app_only` : un bloc d'interface que la maquette validée ne
  contient nulle part. Il n'a été demandé par personne.

### 2. Le serveur

```bash
PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1])")
bin/rails db:prepare                                  # migrations en attente
bin/rails tailwindcss:build                           # si tailwindcss-rails et build absent/vieux
nohup bin/rails server -p $PORT -b 127.0.0.1 > /tmp/recette-server.log 2>&1 &
```

Lance-le en tâche de fond (`run_in_background`), jamais au premier plan : c'est
la seule interdiction. Si le projet audité est l'app à laquelle tu es rattaché
et qu'il te faut une URL publique (montrer au client), utilise plutôt l'outil
MCP `vps_dev_server_start` ; pour un autre projet du parc, le serveur local
suffit, Playwright tourne sur la même machine.

Attends une réponse avant de continuer :

```bash
until curl -sf -o /dev/null http://127.0.0.1:$PORT/up; do sleep 2; done
```

Si ça ne monte pas : lis `/tmp/recette-server.log`, corrige ce qui est de ton
ressort (bundle, migrations, assets), relance. Deux échecs de suite sur la même
cause : arrête-toi, et écris dans le rapport que la parité n'a pas pu être
mesurée, avec l'erreur exacte. Les façades, elles, sont déjà mesurées.

Base vide (`Model.count == 0` partout) : joue `bin/rails db:seed` si le projet
t'appartient ; en audit lecture seule, ne sème pas, et signale que les écrans de
liste ont été comparés à vide.

### 3. Les paires et la parité

```bash
ruby $SK/pairs_gen.rb . --out /tmp/recette-<projet>/pairs.json --base http://127.0.0.1:$PORT
```

**Lis le fichier produit avant de continuer**, deux clés en particulier :

- `_commentaire` : les avertissements du générateur (routes illisibles, champs
  de connexion introuvables, écran applicatif ambigu). Si `auth.*.fill` est
  vide, complète-le à la main maintenant : sans session, tout ce qui est privé
  sera comparé à une page de connexion et le rapport ne vaudra rien.
- `non_appariees` : les maquettes sans écran réel. **C'est déjà un résultat**,
  il ira au chapitre (b) du rapport.

```bash
node $SK/style_diff.js --pairs /tmp/recette-<projet>/pairs.json --out /tmp/recette-<projet>/parite/
```

Les deux viewports (1440 et 390) sont dans le fichier généré : une seule
commande suffit. Sortie non nulle = il reste des écarts hors tolérance, c'est
le cas normal, ce n'est pas une panne.

À lire ensuite : `parite/resume.json` (totaux, `exit_code`), `parite/paires/*.json`
(chaque écart avec sa gravité, sa catégorie et son élément), `parite/index.html`
(rapport filtrable, à joindre au client via `~/.nexrai/bin/nexrai-parite`).

### 4. Arrêt et propreté

```bash
kill %1        # ou le PID noté au démarrage
git status --porcelain | diff - /tmp/recette-git-avant.txt
```

Le `diff` doit être vide. S'il ne l'est pas, dis ce que tu as laissé.

### 5. Le rapport

UN rapport, dans cet ordre, jamais un autre. Chaque point porte **où c'est** et
**comment le vérifier à la main** (une URL à ouvrir, un fichier:ligne à lire).

**(a) L'argent, les permissions, la donnée fausse.** Ce qui se lit dans un
document sortant sans jamais avoir été saisi (`readwrite`, gravité bloquante :
une facture qui imprime un champ que personne ne remplit), une action d'argent
non atteignable, un écran d'un rôle rendu à un autre (une paire `superadmin`
qui répond alors que tu es connecté en entreprise), un nombre en dur repéré par
`static` dans une vue de facture ou de devis.

**(b) Les façades.** Colonne lue jamais saisissable, colonne saisie jamais lue,
contrôle mort (`href="#"`, `data-controller` inexistant, helper de route
inconnu), et **maquette validée jamais implémentée** (`non_appariees`, raison
« aucune route applicative »).

**(c) Le mobile et le style.** Débordement horizontal à 390 px (dis de quel
côté : app ou maquette, le script le précise), **conteneurs qui rognent leur
contenu** (`clip-implicite` / `clip-declare` : ceux-là ne font pas déborder le
document, ils coupent en silence) et **contrôles écrasés**, puis les écarts
bloquants et majeurs de `style_diff`, **groupés par cause** et non par page :
« padding 16 au lieu de 24 sur 39 pages » est une ligne du gabarit, pas
trente-neuf. N'écris jamais « pas de débordement mobile » sur la seule foi du
`scrollWidth` du document : c'est la mesure qui a laissé passer 41 pages.

**(d) Le reste, en information.** Colonnes mortes, écarts mineurs, ambiguïtés du
générateur de paires.

**(e) Ce qui n'a pas été mesuré.** Obligatoire, même vide. Serveur non
démarrable, base vide, connexion non trouvée, maquettes absentes, paires
écartées faute d'identifiant, branche auditée qui n'est pas la plus récente.
Sans ce chapitre, un rapport court se lit comme un feu vert.

Termine par les chiffres bruts (n bloquants, n majeurs, n paires, n non
appariées) et le chemin des artefacts.

---

## Modes courts

Si la demande ne porte que sur un morceau, ne fais que ce morceau et dis-le.

| Demande | Étapes | Commandes |
|---|---|---|
| « les façades », « ce qui n'est pas branché » | 0, 1, 5 | `facade_scan readwrite` + `static` |
| « le mobile » | 0, 2, 3, 4, 5 | `pairs_gen` puis `style_diff --viewport mobile` |
| « la parité », « l'écart aux maquettes » | 0, 2, 3, 4, 5 | `pairs_gen` puis `style_diff` |
| « une page » | idem + `--only "<nom de la paire>"` | |
| « les routes sans geste » | 0, 5 | `facade_scan reachability` |
| « la qualité des maquettes », « c'est transcrit comment ? » | 0, 5 | `mockup_scan` |
| « la charte est propre ? », avant les maquettes | 0, 5 | `charte_scan` |
| « on peut y arriver en cliquant ? », maquettes | 0, 5 | `mockup_inventory` |
| « qu'est-ce qu'on a inventé ? », « ce bloc était dans la maquette ? » | 0, 1, 5 | `mockup_scan inventory` |
| « ce champ est vrai ou c'est du seed ? » | 0, 1, 5 | `facade_scan readwrite` (catégorie `column_seed_only`) |

---

## Les outils

### pairs_gen.rb — le fichier de paires, généré

```bash
ruby $SK/pairs_gen.rb <rails_app_dir> [--out pairs.json] [--base http://127.0.0.1:PORT] [--no-boot] [--quiet]
```

Il énumère les vues de `app/views/mockups/**` (partials exclus), leur donne leur
URL via `bin/rails routes`, cherche l'écran applicatif de même contrôleur privé
du préfixe `mockups` et de même action, et **ne garde la paire que si la route
applicative existe vraiment**. Le reste part dans `non_appariees` avec sa raison.

L'heuristique d'appariement vit dans `pairing.rb`, à côté. `mockup_scan.rb
inventory` charge le même fichier : deux outils qui apparieraient différemment
finiraient par ne pas parler de la même paire.

- Segments dynamiques : une paire n'est gardée que si l'identifiant se résout.
  Il interroge la base de dev (`bin/rails runner`), en scopant sur le tenant du
  premier compte de démonstration quand le modèle porte une clé
  (`company_id`, `account_id`…), et retombe sur `id=1` si les seeds créent bien
  ce modèle. Sinon : `non_appariees`.
- Comptes de démonstration : lus dans `db/seeds.rb` (e-mails, mots de passe en
  clair, `role:`), un profil par rôle. Les comptes en attente d'activation
  (`password: nil`) sont ignorés.
- Formulaire de connexion : cherché dans les vues (champ `type=password` et son
  voisin e-mail), sélecteurs par `id` puis par `name`. `expect_url` est posé sur
  le tableau de bord déduit du rôle : une connexion ratée fait échouer le run au
  lieu de produire un rapport d'écarts inventés.
- Viewports 1440 et 390 par défaut, tolérances par défaut, allowlist vide.

**Limites connues** (elles se corrigent à la main dans le JSON produit) :

- l'appariement se fait sur le **nom** du contrôleur ; un écran renommé entre la
  maquette et le code sort en « jamais implémenté » alors qu'il existe ;
- un préfixe applicatif qui porte le nom d'un namespace de maquette est refusé
  (c'est ce qui évite d'apparier le tableau de bord entreprise avec celui du
  superadmin) ; en contrepartie une vraie route ainsi préfixée est manquée ;
- l'identifiant vient du **premier** enregistrement, pas de celui de la
  maquette : la forme est comparable, pas le contenu ;
- un modèle qui ne se déduit pas du nom du contrôleur (`settings/team` →
  `Team`, alors que le modèle est `User`) sort en non apparié ;
- les champs de connexion posés par des helpers Rails (`f.email_field`) ne sont
  pas lus : le bloc `auth` est alors vide, avec un avertissement ;
- une seule page par écran : ni survol, ni modale, ni formulaire en erreur ;
- `--no-boot` ne confronte rien aux routes réelles, les URL sont conventionnelles.

### style_diff.js — écart maquette / application

Compare les STYLES CALCULÉS des deux côtés, élément par élément, au lieu de
comparer des pixels. Sort la propriété qui diffère, pas une image rouge.

```bash
node $SK/style_diff.js --pairs pairs.json --out doc/memory/brick-{N}/parite/
```

Options : `--only <motif>` (filtre sur le nom de la paire), `--viewport mobile`,
`--fail-on bloquant|majeur|mineur`, `--headed`. Sortie : `index.html` autonome
(filtres par gravité), un JSON par paire, `resume.json`. Code de sortie non nul
s'il reste des écarts hors tolérance, donc utilisable comme gate.

Détecte en plus, et ce sont les quatre qui coûtent le plus cher en livraison :

- le **débordement horizontal du document** par viewport (mobile 390 px
  surtout), en disant de quel côté il se produit ;
- les **conteneurs qui rognent leur contenu** sans que le document déborde
  (voir la mise en garde ci-dessous) ;
- les **contrôles de saisie écrasés** (un `input` rendu à 18 px de large) et
  ceux qui passent sous la cible tactile de 44 px ;
- les **feuilles de style étrangères** chargées à côté des nôtres (un export
  Lovable ou Figma qui cohabite avec le design system : c'est ce qui a déformé
  une application entière pendant des semaines).

#### ⚠️ Un `scrollWidth` de document conforme ne prouve RIEN

`document.documentElement.scrollWidth === 390` a longtemps servi de feu vert.
C'est un faux vert, et le mode de défaillance le plus dangereux d'un instrument.
Dès qu'un conteneur porte `overflow-y: auto` (le gabarit `<main>` de presque
toutes nos applis), le navigateur calcule un `overflow-x: auto` implicite sur ce
même conteneur. Le document ne déborde donc plus, le chiffre est propre, **et le
tableau à l'intérieur est tronqué** : mesuré une fois, 41 pages coupaient leurs
tableaux en silence pendant que l'outil annonçait 46 conformes sur 47.

La sonde parcourt donc les éléments et compare `scrollWidth` à `clientWidth`,
puis **lit la cascade CSS** pour trancher entre les deux cas, parce que la valeur
CALCULÉE est identique dans les deux :

| Ce que dit le rapport | Ce que ça veut dire | Gravité |
|---|---|---|
| `scroll-voulu` | `overflow-x: auto\|scroll` **déclaré** dans la feuille de style (ou région focalisable enveloppant un tableau) : décision assumée | info |
| `clip-implicite` | `overflow-x` calculé à `auto` **sans être déclaré nulle part** : le navigateur l'a dérivé d'un `overflow-y`. Rien n'indique à l'utilisateur qu'il reste du contenu à droite | bloquant |
| `clip-declare` | `overflow-x: hidden\|clip` déclaré : le contenu est coupé net | bloquant |
| `clip-maquette` | c'est la maquette qui coupe, l'app tient | majeur |

Chaque ligne porte le sélecteur, la largeur du contenu et celle du conteneur, et
dit si le document, lui, était silencieux. Sans cette distinction, la correction
est un jeu de devinettes : on ne sait pas s'il faut retirer un `overflow`,
ajouter un `overflow-x-auto` explicite, ou refaire la mise en page.

Si la cascade n'est pas lisible (feuille CSS cross-origin), la gravité est
abaissée à majeur et le rapport le dit.

#### Contrôles de saisie

Un écran peut être conforme à 390 px (pas de débordement, charte respectée) et
rendre ses `input` à 18 px de large : les styles calculés sont les mêmes des deux
côtés, c'est la boîte résolue qui s'effondre. La sonde mesure la boîte RENDUE de
chaque `input` / `select` / `textarea` / `button` :

- moins de **24 px** de large : `control-crushed`, bloquant, le champ n'est plus
  saisissable ;
- moins de **44 px** (cible tactile) : `control-target`, majeur si le champ est
  trop étroit pour une saisie ou trop petit sur les deux axes, mineur si c'est
  seulement la hauteur ;
- largeur dans l'app **inférieure de moitié** à celle de la maquette :
  `control-shrunk`, bloquant (la maquette le montrait normal, l'app l'a écrasé) ;
- cases à cocher et boutons radio : légitimement petits, mesurés à un seuil de
  10 px seulement, et les contrôles volontairement masqués (`sr-only`, radio de
  1×1 px derrière une pastille) sont exclus ;
- si la maquette a le même défaut, la gravité descend d'un cran et le message le
  dit : c'est la charte qu'il faut reprendre, pas l'app.

Seuils réglables dans `pairs.json` : `"controls": {"min_px": 44, "crushed_px":
24, "tiny_min_px": 10, "shrink_ratio": 0.5}` et `"clip_min_excess": 3`.

#### Les totaux

Tous les chiffres du rapport (par paire, par viewport, en tête de page) sont
**recalculés depuis la liste publiée**, jamais incrémentés à côté. Le nombre de
lignes listées est affiché à côté des totaux. Un écran qui a planté apparaît
dans un bandeau « n écran(s) non mesuré(s) » : sans lui, un échec de mesure se
lit comme un feu vert (c'est le même piège qu'un cahier de recette qui annonce
672 critères pour 111 lignes écrites).

Ce qu'il ne voit pas : un seul état par page (ni survol, ni focus, ni modale, ni
formulaire en erreur), ni le contraste. Les positions sont volontairement
tolérantes (un décalage isolé de 3 px passe). La précision monte quand les deux
côtés affichent les MÊMES données : c'est la raison d'être du jeu de données
canonique (`doc/memory/jeu_de_donnees.md`).

### mobile_gate.rb — le verrou mobile avant le verdict

`style_diff` mesure les champs écrasés et le contenu coupé, et il les classe
bloquants. Ça n'a pas suffi : banc modèles des 16-17/08/2026, deux livraisons
sur trois rendues avec des champs de prix à 18 px sur mobile, l'une avec 26
`control-crushed` dans son propre rapport au moment du verdict READY. La règle
était écrite dans le skill, le rapport n'était pas lu. Ce script LIT le
rapport à la place du reviewer et rend un verdict binaire.

```bash
ruby $SK/mobile_gate.rb doc/memory/brick-{N}/parite/     # mode RAPPORT : le dossier --out de style_diff
ruby $SK/mobile_gate.rb --urls ecrans.txt                # mode DIRECT : une URL par ligne, mesure via playwright-cli
```

Mode direct (réanalyse des maquettes, ou n'importe quel lot d'écrans servis) :
il ouvre chaque URL à 390 px dans une session playwright-cli dédiée (fermée à
la fin) et applique les trois mesures que les skills prescrivent à la main :
bord droit réel hors `position: fixed` et hors conteneur à défilement déclaré,
conteneurs de LAYOUT qui coupent (div/section/table/form… dont le contenu
dépasse sans `overflow-x: auto|scroll`, contrôles et texte en ellipse exclus),
champs de saisie visibles sous 24 px. `documentElement.scrollWidth` est relevé
mais ne décide rien. Vérifié : une page piège avec `body{overflow-x:hidden}`,
un tableau à 800 px et trois inputs à 14 px est refusée sur les trois axes ;
trois maquettes saines passent.

En mode rapport, il ne regarde QUE les classes de saisie mobile : `control-crushed`,
`control-shrunk`, `clip-implicite`, `clip-declare`, `clip-reste`,
`overflow-el`, `overflow-doc`, sur le viewport mobile. La parité de style
(`missing`, `style`, `box`, `added`…), bruyante et pleine de mis-appariements,
reste au jugement humain et n'entre pas dans la gate : personne ne peut donc
la contourner en disant « trop de bruit ».

- exit 0 : PASSE. Dernière ligne = la ligne « Mobile (gate) » à coller telle
  quelle dans review.md.
- exit 1 : REFUS, constats listés par classe avec écran et élément. Verdict
  READY interdit tant que ce n'est pas corrigé ET re-mesuré.
- exit 2 : NON MESURÉ (pas de `resume.json`, pas de viewport mobile, aucune
  paire). Même interdiction : un style_diff dont on n'a gardé que le HTML
  n'a pas eu lieu.

Vérifié sur les deux livraisons du banc : la première est refusée en exit 2
(rapport machine non conservé, exactement le trou), la seconde en exit 1 (deux
débordements réels que l'audit avait vus). Sur un dépôt propre il passe.

### facade_scan.rb — contrôles non branchés

Chasse la façade : l'élément qui a l'air de marcher et n'est relié à rien. C'est
le défaut signature du pipeline maquette vers code.

```bash
ruby $SK/facade_scan.rb static .            # analyse des vues
ruby $SK/facade_scan.rb crawl http://localhost:3000 --cookie "..."
ruby $SK/facade_scan.rb static . --json     # résumé machine
```

Mode `static` : champs de formulaire sans `name`, `data-controller`/`data-action`
pointant vers un contrôleur Stimulus inexistant, `data-action` posé sur un élément
inerte, liens morts (`href="#"`), helpers de route inconnus, nombres en dur
suspects dans les vues. Mode `crawl` : 404/500, champs sans `name` dans le DOM
rendu, formulaires sans action, boutons non branchés. `app/views/mockups` est
exclu (c'est la référence, elle a le droit d'être inerte).

Toujours code de sortie 0 : c'est un rapport, pas un gate. Beaucoup de réglages
et l'allowlist sont en tête de script.

#### La flèche inverse : `reachability` et `readwrite`

`static` et `crawl` vérifient qu'un contrôle mène quelque part. Ces deux modes
vérifient l'inverse : ce que le serveur sait faire, et que l'interface ne permet
pas de déclencher ni de remplir.

```bash
ruby $SK/facade_scan.rb reachability .            # routes sans geste
ruby $SK/facade_scan.rb readwrite .               # colonnes en sens unique
ruby $SK/facade_scan.rb reachability . --mockups  # phase maquettes
ruby $SK/facade_scan.rb readwrite . --mockups
```

`reachability` confronte les routes (`bin/rails routes`, repli sur
`config/routes.rb` avec `--no-boot`) aux gestes des vues : `form_with`,
`button_to`, `link_to` avec `turbo_method`, `formaction`, `<form action>`.
Bloquant : action non-GET qu'aucun geste ne vise, et route déclarée vers une
action inexistante. Info : page GET vers laquelle aucun lien ne mène, et action
atteinte seulement par du JS (le verbe n'est alors pas vérifiable).

`readwrite` confronte chaque colonne de `db/schema.rb` à ses lectures (vue,
helper, mailer, PDF, requête) et à ses écritures (`permit`/`expect`, champ de
formulaire, affectation, seed). Sort la colonne **lue mais jamais saisissable**
et la colonne **saisie mais jamais lue** : deux façades symétriques. Bloquant si
la colonne part dans un document sortant (PDF, e-mail).

##### `column_seed_only` — la colonne que seuls les seeds remplissent

Le troisième constat, **bloquant**, est celui qui se voit le moins en
développement et le plus chez le client : une colonne **affichée** à l'écran et
**écrite uniquement** par `db/seeds.rb`, `db/seeds/**` ou des fixtures. En
local elle a une valeur, chez un vrai utilisateur elle est vide ou figée à son
défaut de schéma, pour toujours. `db:seed` ne se rejoue pas en production.

Deux cas réels, tous deux payés sur le même projet :

- `users.last_active_at` et `users.response_time` alimentaient les pastilles
  « Actif il y a 3 h » et « Répond en < 2 h » du profil. Aucun formulaire ne les
  saisit, aucun code ne les calcule. Sur un compte réel la première affichait
  l'âge du seed, la seconde un délai jamais mesuré ;
- une ontologie de 42 rôles importée par les seuls seeds : 31 rôles en
  développement, **0 en production**, donc des filtres « Catégorie » et
  « Domaine » vides chez le client seulement.

Ce que le détecteur ne confond pas :
- une colonne **jamais écrite du tout** reste dans `column_read_not_writable` ;
- une colonne **écrite mais jamais lue** reste dans `column_written_not_read` ;
- une colonne alimentée par une **tâche rake** (`lib/tasks/*.rake`), une
  migration de données ou `db/data/**` n'est PAS un défaut : c'est un import
  rejouable au déploiement. Un fichier de seeds qu'une tâche rake `require` (ou
  dont elle appelle la constante) bascule avec elle. C'est exactement la
  correction de l'ontologie : le jour où `lib/tasks/ontology.rake` exécute
  `db/seeds/ontology/import.rb`, les colonnes concernées disparaissent du
  rapport, sans toucher au reste.

Les garde-fous, tous payés par un faux positif observé. Pour partir en bloquant,
il faut : une lecture dans une **surface de rendu** (`app/views`, `helpers`,
`mailers`, `components`, `serializers`) hors maquettes (`mockups`, `lovable`,
`figma`) ; un accès **d'attribut ou de requête** (`user.col`, `pluck(:col)`),
jamais un `hash[:col]` ; et un **receveur résolu à la table de la colonne**.
Conséquence assumée : une colonne toujours lue via un receveur anonyme
(`f.object.x`, `d&.x`) reste dans la catégorie majeure au lieu de monter en
bloquant.

`--mockups` cadre les deux sur la phase maquettes, avant le code : les routes
prévues face aux gestes de `app/views/mockups`, et les champs de
`doc/memory/data_models.md` face à ce que les maquettes affichent et saisissent.
C'est là que ça coûte le moins cher de corriger.

Limites connues : une lecture dont le receveur n'est pas identifiable compte pour
toutes les tables portant la colonne (le rapport le signale) ; une écriture qui
passe par un attribut virtuel autre que `<colonne>_input` échappe au scan ; en
mode maquettes le rapprochement se fait sur les noms, un champ nommé autrement
dans la maquette que dans `data_models.md` remonte comme absent.

Ce que `column_seed_only` ne voit pas : une colonne écrite par un job de fond ou
un webhook que le scan lit quand même comme du code applicatif (elle sort du
bloquant, à raison) ; une colonne remplie par un `*_tag` de formulaire portant le
nom d'une colonne d'une AUTRE table (le contrôle n'a pas de modèle, l'écriture
compte alors pour toutes les tables et éteint le constat) ; et un projet sans
`db/schema.rb` (structure.sql) où le mode ne démarre pas.

### charte_scan.rb — hygiène de la charte

```bash
ruby $SK/charte_scan.rb <dossier_charte | style_guide.html> [--json]
                        [--tokens tailwind.config.js] [--delta-e 4.0] [--sans-couverture]
```

Ni serveur ni navigateur. Audite la charte elle-même, pas les écrans : classes
arbitraires `[...]` **avec leur ligne**, `style=` en dur, couleurs appliquées
absentes des tokens, grappes de quasi-doublons (ΔE < 4 en CIELAB) et trous de
couverture. Il partage `Color` et `ErbDoc` avec `mockup_scan.rb` et s'arrête si
son propre compte diverge du sien.

Pourquoi il existe : la charte est le seul artefact que reçoit l'agent qui
construira les écrans, et **il n'applique pas les règles qu'on lui écrit, il
imite le code qu'on lui donne**. Mesuré en août 2026 sur neuf chartes appariées :
une relecture qui écrit les bonnes pratiques dans le guide laisse 89 classes
arbitraires dans les écrans produits, une relecture qui nettoie le code du guide
en laisse 0. Pire, nommer une classe fautive pour l'interdire la fait recopier
telle quelle. Une charte sale est donc un budget de correction déjà engagé sur
tous les écrans à venir.

Le rapport rend une **liste actionnable, pas un compteur** : un compteur ne se
corrige pas, une ligne si. C'est `brick-design-review` qui le déroule.

Les grappes de quasi-doublons se **signalent** et ne se fusionnent jamais toutes
seules. Deux couleurs indiscernables à l'œil qui portent des rôles différents (un
fond de page et une teinte d'état de succès) doivent s'écarter, pas fusionner :
sinon l'écart sémantique disparaît de l'écran. Même mise en garde que
`normaliser.rb`, payée en vrai sur le banc.

### mockup_inventory.py — liens ENTRANTS d'un lot de maquettes

```bash
bin/rails routes | grep mockups | awk '{print $2, $3}' | grep GET | sort -u > /tmp/routes.txt
python3 $SK/mockup_inventory.py http://localhost:{port} /tmp/routes.txt /mockups \
  doc/memory/mockups/inventaire.md
```

Rend, pour chaque écran routé du namespace : URL, titre, liens sortants **avec leur
libellé**, boutons, et **liens entrants hub exclu**. Tout écran marqué « AUCUN » est un
candidat orphelin.

Pourquoi les liens ENTRANTS : la question qui compte n'est pas « cette page a-t-elle des
liens morts » mais « depuis l'écran d'accueil de son rôle, l'utilisateur peut-il atteindre
cet écran en cliquant ». Le contrôle qu'il remplace mesurait les liens *sortants*
(`grep href="#"`) et laissait passer un lot où l'écran de modification d'un devis n'avait
aucun lien entrant.

**Le hub `/mockups` ne compte pas** : index de revue interne, absent du produit, il rend
tout écran atteignable en un clic. Sans cette exclusion le contrôle ne mesure rien.

Un « AUCUN » n'est **jamais un verdict** : un chemin porté par un `<button>` Stimulus est
invisible à un collecteur de `href`. Chaque candidat se tranche au navigateur. Ordre de
grandeur observé : 5 orphelins sur 52 écrans, 11 sur 51.

### mockup_scan.rb — qualité de transcription des maquettes

```bash
ruby $SK/mockup_scan.rb <rails_app_dir> [--json] [--tokens config/tailwind.config.js]
                                        [--source <dir>] [--top N] [--max-lines 400]
```

Ne demande ni serveur ni navigateur, ne touche à rien, tourne en 2 s sur
52 000 lignes. Il lit `app/views/mockups/**` (partials compris) et rend un
rapport par écran, trié du plus problématique au moins, plus un **score de
dérive sur 100** et son détail par axe.

Il sert à deux choses : dire à un dev ce qu'il lui reste à reprendre sur des
maquettes en cours, et donner un chiffre comparable d'un projet à l'autre.

**Six axes, six poids.**

| Axe | Poids | Ce qu'il compte |
|---|---|---|
| palette | 25 | couleurs distinctes (hex, `rgb()`, `hsl()` normalisés), celles qui ne correspondent à aucun token de la charte, les **quasi-doublons** (ΔE < 4 en CIELAB), les custom properties définies dans la vue elle-même |
| typo | 10 | familles de police distinctes, tailles hors échelle Tailwind |
| arbitraire | 20 | `style="..."` en dur, classes Tailwind `[...]`, blocs `<style>` inline et leur volume en lignes |
| duplication | 15 | blocs identiques **et quasi identiques** partagés entre écrans, lignes récupérables en partials |
| hygiène | 20 | emoji/glyphe à la place d'un asset, jargon interne visible, tiret cadratin dans une phrase affichée, `<a>` imbriqué, responsive absent, z-index par-dessus la navbar |
| volume | 10 | lignes par fichier, part des lignes dans les fichiers au-dessus du seuil (400, la convention de l'atelier) |

Verdicts : `< 12` PROPRE, `12-28` À SURVEILLER, `28-50` DÉRIVE NETTE,
`≥ 50` TRANSCRIPTION À REPRENDRE. Chaque total affiché est recalculé depuis la
liste qu'il résume ; rien n'est tenu à part.

**Ce qui rend les remontées lisibles.** Le fichier est découpé en zones (code
ERB, commentaire ERB, commentaire HTML, `<style>`, `<script>`, balise, texte).
Une couleur citée dans un commentaire ne compte pas comme une couleur employée,
un tiret cadratin dans une note de dev n'est pas un tiret montré au client. Le
texte affiché inclut les littéraux Ruby (les maquettes de l'atelier posent leurs
données fictives en tête de vue), moins les chemins de partials, les helpers de
route, les listes de classes et les données de path SVG.

**Les quasi-doublons de couleur se regroupent par graine.** La couleur la plus
employée sert de référence, et on lui rattache celles qui sont à moins de ΔE
d'**elle**. Une union-find sur les paires proches enchaîne de fil en aiguille et
finit par mettre le blanc et l'or dans le même paquet ; ici le groupe se lit
« voici la couleur, voici ses sosies ».

**`--source <dir>`** confronte les valeurs numériques (`NNpx`) et les couleurs
d'une source externe (CSS, TSX, HTML d'un export Lovable/Figma) à celles
produites. Il sort les valeurs présentes d'un côté et pas de l'autre, et surtout
les **valeurs proches sans être égales** (écart de 2 px à 15 %) : c'est le
détecteur de « valeur estimée au lieu de mesurée ». Le rapport annonce lui-même
cette comparaison comme indicative.

**Ce qu'il ne détecte pas.**

- La fidélité à la maquette source. Sans `--source` il ne voit que le rendu ; un
  écran entièrement réinventé mais bien rangé sort propre.
- Une section de la source purement et simplement oubliée : il compte ce qui est
  là, pas ce qui manque.
- Ce que donne le navigateur : chevauchements réels, débordements, contraste.
  C'est le travail de `style_diff.js`, pas le sien.
- La cohérence des données fictives entre écrans (un même client avec deux
  chiffres d'affaires).
- Les classes construites dynamiquement en Ruby, qu'il ne sait pas résoudre.

**Faux positifs connus, à écarter à la lecture.**

- Couleurs de marque tierces (le bouton Google et ses `#4285f4 #34a853 #fbbc05
  #ea4335`) remontent en « hors charte ».
- Sans `tailwind.config.js` ni feuille de style exploitable, « hors charte »
  veut dire « en dur, sans référence » : le rapport le dit en tête.
- Les `style="..."` interpolés en ERB (`style="background: <%= c %>"`) sont
  comptés à part et tolérés : une couleur calculée ne peut pas être une classe.
- Le z-index d'une modale : les sélecteurs nommés `overlay`, `modal`, `dialog`,
  `drawer`, `popover`, `toast`… sont écartés, les autres remontent.
- Le tiret cadratin n'est signalé qu'au milieu d'une phrase d'au moins huit mots.
  Le tiret « valeur vide » d'un tableau et le séparateur d'un titre court sont
  des conventions typographiques, pas la signature d'une IA.

**La mise en garde qui compte.** Un score propre prouve l'HYGIÈNE, pas la
fidélité. Il dit que les couleurs sont dans la charte, que les fichiers sont
courts, que rien n'est recopié six fois. Il ne dit pas que l'écran ressemble à
ce que le client a validé. Ne jamais écrire « conforme aux maquettes » parce que
mockup_scan est vert : pour ça il y a `inventory` (ci-dessous), `--source`,
`style_diff.js`, et l'œil.

#### `inventory` — l'inventaire de blocs, application contre maquette

```bash
ruby $SK/mockup_scan.rb inventory <rails_app_dir> [--json]
```

Le mode qui répond à la question que le score d'hygiène ne pose pas : **est-ce
que l'application montre un bloc que la maquette validée ne contient pas** (bloc
inventé), ou l'inverse (promesse non tenue) ? Sans serveur, sans navigateur,
3 s sur 25 écrans.

Cas réel qui l'a payé : trois pastilles de visibilité (`tdb-vis-state-btn`)
posées sur le tableau de bord par un commit intitulé « pixel-perfect », alors
que la maquette, présente dans le même dépôt et navigable, n'en contenait
aucune trace. Huit semaines de survie, jusqu'à ce que le client les voie.

**Comment il apparie.** Même heuristique que `pairs_gen.rb`, partagée dans
`pairing.rb` : contrôleur de maquette privé du préfixe `mockups`, préfixe de
namespace toléré sauf s'il est lui-même un namespace de maquette. Deux règles en
plus, propres aux fichiers de vue : `mockups/talent/dashboard` retrouve
`talent/dashboard#index` (la maquette met l'écran dans un fichier, Rails lui
donne son contrôleur), et `mockups/talent/profile` retrouve `talent/profiles#show`
(singulier de la maquette, pluriel de la ressource). Une maquette sans écran, un
écran sans maquette : les deux sont dits, ce sont des constats de recette.

**Quatre familles de blocs**, sur la vue ET ses partials inlinés (l'application
découpe, la maquette non) :

| Famille | Ce qui est comparé |
|---|---|
| `classe` | classes de composant : ce qui n'est pas une utilitaire Tailwind, ni une valeur arbitraire, ni un fragment d'ERB |
| `stimulus` | `data-controller` et `data-action` (`controleur#methode`) |
| `controle` | boutons et liens, par leur libellé normalisé |
| `titre` | `<h1>`…`<h6>`, par leur libellé normalisé |

**Trois listes plus deux seaux.** *Présent dans l'app, absent de la maquette*
(bloquant) et *présent dans la maquette, absent de l'app* (bloquant) ; les
*correspondances* en information. Puis deux seaux qui existent pour que les deux
premières restent lisibles :

- **présent des deux côtés mais pas sur le même écran** : le bloc a bien été
  dessiné, ailleurs (partial partagé, écran voisin). Ce n'est pas un bloc
  inventé, au pire un écart de placement. Un bloc ne part en bloquant que s'il
  est absent de TOUT le corpus d'en face ;
- **non comparable** : l'application traduit ses libellés (`t('.envoyer')`), la
  maquette les écrit en clair. Comparer mot à mot produirait des centaines
  d'écarts qui ne sont que de l'i18n. Dès que le côté opposé a des libellés
  dynamiques dans la famille, le diff sort du bloquant, avec sa raison. Même
  chose quand une famille est **absente d'un côté** : un écran dont le titre est
  un `<div>` stylisé n'a aucun `<h*>`, et « titre Paramètres absent de
  l'application » était faux, le titre est bien là.

**Faux positifs connus, à écarter à la lecture.**

- Une classe construite en Ruby : `avatar_variants = %w[hotel resto private]`
  puis `class="ed-mission-avatar <%= variant %>"`. Le bloc est bien là, le scan
  ne le voit pas. C'est la principale source de faux « absent de l'application ».
- Une classe dont la tête est un utilitaire Tailwind (`text-block`, `border-card`)
  est écartée comme utilitaire : ajoute-la à `class_denylist` à l'envers, ou
  retire sa tête de `tailwind_heads` pour ce projet.
- Un bloc dont la maquette porte le CSS mais pas le markup (ou l'inverse) : le
  scan lit le `<style>` des maquettes, PAS `app/assets/stylesheets`. Un bloc dont
  seul le style a été porté remonte comme « promesse non tenue », ce qu'il est.

**Ce qui est neutralisé exprès** (branchement de données, pas bloc inventé) :
les chiffres dans les libellés (« 12 candidatures » = « 3 candidatures »), les
`id` dynamiques, les valeurs interpolées. Une classe seulement déclarée dans le
`<style>` d'une maquette compte comme dessinée. Une `data-action` dont le
CONTRÔLEUR existe déjà en face descend en information : le composant est là,
c'est le câblage qui diffère.

**Réglages en tête de script** (`INV`) : `tailwind_heads` (la liste des têtes
d'utilitaires, à compléter si une classe de composant du projet est avalée),
`class_denylist`, `cluster_min` (au-delà de 4 classes de même préfixe on parle
d'UN composant, `tsm-why-* (9 classes)`), `not_shipped` (dossiers de vues qui ne
sont pas le produit : `mockups`, `lovable`, `figma`…), `per_pair` (détail par
écran dans le rapport texte ; le JSON garde tout).

**Ce qu'il ne voit pas.**

- La mise en page. Deux écrans avec les mêmes blocs dans un ordre différent
  sortent identiques : c'est `style_diff.js` qui mesure le rendu.
- Les blocs construits dynamiquement (`class="#{prefix}-card"`), les composants
  ViewComponent rendus par constante, les partials résolus par variable.
- Les libellés traduits face à des libellés en clair : ils partent en « non
  comparable », pas en « conforme ».
- Un écran entièrement réécrit remonte comme des centaines de blocs, pas comme
  un verdict « écran divergent ». Lis d'abord la répartition par écran : quatre
  écrans qui portent la moitié des constats, c'est quatre écrans à revoir, pas
  600 corrections.

### normaliser.rb — les valeurs en dur deviennent une charte, APRÈS validation client

```bash
ruby $SK/normaliser.rb --charte doc/memory/charte_normalisee.css \
     --sortie app/views/mockups --rapport /tmp/normalisation.md --json /tmp/normalisation.json \
     --seuil 3 app/views/mockups/<lot>/
```

L'étape qui manquait entre une transcription fidèle (`/brick-mockup-transcription`,
qui porte les valeurs littérales de la source) et la discipline de charte que
l'atelier tient partout ailleurs. Elle prend un **lot** de vues, calcule la
charte, réécrit les vues et rend un rapport. Elle ne se lance **jamais avant la
validation client** : ce que le client valide, c'est le rendu littéral.

**Pourquoi une passe séparée, et pas une règle de plus dans le prompt.** Mesure
08/2026 : avec la charte déjà remplie sous les yeux et l'interdiction écrite
d'arrondir, l'agent qui transcrit arrondit quand même, 4 couleurs sur 18 et
7 longueurs sur 20, et l'écran perd 15 points de fidélité. Un menu de tokens
invite à substituer, même interdit. Cette passe-ci est un **calcul**, pas une
consigne.

**Ce qu'elle garantit.**

- **Une valeur est remplacée par elle-même, nommée.** Une substitution ne peut
  pas arrondir : c'est ce qui la rend sûre là où la consigne échoue. Mesuré sur
  un lot de 7 écrans : la fidélité ne bouge **d'aucun dixième de point**, sur
  aucun des trois volets (visuel, interaction, contenu).
- **Une valeur employée dans plusieurs vues devient un token, une valeur
  employée dans une seule reste littérale.** La longue traîne propre à un écran
  n'a rien à faire dans la charte.
- **Idempotente** : relancée sur sa propre sortie elle rend des vues identiques
  au byte près, la même charte, les mêmes comptes, et zéro substitution.
- **Bruyante** : elle se relit (chaque token redéveloppé doit rendre l'original)
  et se contrôle en complétude (plus aucune valeur tokenisée écrite en dur).
  Toute incohérence l'arrête au lieu de rendre un résultat à moitié juste.
- Gain mesuré sur les mêmes 7 écrans : couleurs en dur **988 → 365** (−63 %),
  longueurs en dur **2 252 → 114** (−95 %), tailles de police distinctes 43 → 14.

**Ce qu'elle signale sans le décider.** Trois choses remontent au rapport et
attendent un arbitrage humain, parce que ce sont des décisions de design :

- les **quasi-doublons** de couleur (l'or `#c4a559`, 49 emplois sur 5 écrans,
  contre `#bfa15c`, 3 emplois sur 1 écran, à 3,75 ΔE). Jamais fusionnés en
  silence ;
- l'**accroche à ±1 px** d'une longueur vers l'échelle de la charte : elle
  change le rendu, donc elle est listée, pas appliquée ;
- les **niveaux d'élévation** proposés pour les ombres (groupés sur la géométrie
  seule), jamais imposés.

**Le seuil monte avec la taille du lot.** `--seuil N` = nombre de vues à partir
duquel une valeur est systémique. Mesuré sur 7 écrans : à seuil 2 la charte fait
124 tokens et **ne se stabilise pas** (elle gagne encore 16 tokens au septième
écran) ; **à seuil 3 elle tient en 68 tokens** et retire encore la moitié des
couleurs en dur et 90 % des longueurs. Sur un lot de 7 écrans, seuil 3. Sur une
trentaine d'écrans, monter encore et vérifier que la charte se stabilise, sinon
elle dépasse les 60 tokens que la doctrine design autorise.

**Ce qu'elle ne touche pas** : le JavaScript, les attributs de présentation SVG,
le bloc de données fictives. `var()` n'y est pas résolu ou pas valide. Deux
autres cas sont non substituables par nature, et c'est normal de les voir dans
le résidu : les longueurs d'un prélude `@media` (où `var()` est interdit) et les
valeurs négatives (`-var()` n'est pas du CSS).

**À lire avec, pas à la place.** Sur un lot, le score d'hygiène de `mockup_scan`
ne voit presque rien du gain (70,7 → 69,2) : son volet palette sature bien avant.
Lis les comptes bruts du rapport de normalisation, pas le score.

---

## Quand s'en servir

- Le balayage complet : sur demande (« fais le balayage »), pendant
  `/brick-code-review`, ou sur un projet déjà livré qu'on reprend.
- En fin de lot pendant `/brick-code-build` : les modes courts, sur les pages du
  lot (`--only`).
- En phase maquettes : `facade_scan --mockups` et `mockup_scan`, il n'y a pas
  encore de parité à mesurer. `mockup_scan` sur des maquettes issues d'un export
  externe, avec `--source` pointé sur cet export.
- Après un `/brick-code-fix` qui touche une vue : `style_diff --only <page>`.
- **Après la validation client** d'un lot de maquettes transcrites :
  `normaliser.rb`, appelé par `/brick-mockup-transcription`. Jamais avant, et
  jamais sur des maquettes créées de zéro (elles sortent déjà avec la charte).

Le rapport de parité produit ici est celui qu'attend `/brick-code-review` et que
`~/.nexrai/bin/nexrai-parite` publie dans l'espace client.

## Vérité d'usage

Sur une livraison réelle dont la review avait conclu « pixel match 32 pages,
32/32 conformes », `style_diff` a trouvé 157 écarts, dont un débordement mobile
sur 14 pages sur 15 et une pastille de notification cassée par un conteneur Turbo
Stream, invisible sur une capture. Un rapport sans écart veut dire quelque chose ;
un œil humain qui dit « c'est conforme » ne veut rien dire.

Sur gespilot (brique 1 livrée, 47 maquettes), le balayage complet a pris huit
minutes : 41 paires générées sans une ligne écrite à la main, 6 maquettes sans
écran réel, une colonne imprimée sur les factures que personne ne peut saisir, et
un débordement mobile sur 39 pages sur 41 côté maquettes.

`mockup_scan` a été calibré sur deux extrêmes réels. Des maquettes inventées
puis rangées (80 fichiers, 4 607 lignes, 6 couleurs, aucun `<style>` inline)
sortent à **6,5 / 100, PROPRE**. La transcription d'un export Lovable vers des
vues Rails (137 fichiers, 52 729 lignes, 1 091 couleurs distinctes dont 438 hors
charte, 983 `style="..."`, 20 107 lignes de CSS dans 61 vues, 6 familles de
police, 49 fichiers au-dessus de 400 lignes) sort à **78,1 / 100, TRANSCRIPTION
À REPRENDRE**. Un facteur douze entre les deux : le score sépare, il ne coupe pas
les cheveux en quatre.

Sur ce même projet il a retrouvé, sans qu'on lui dise où chercher, les deux
défauts que l'enquête humaine avait mis des jours à isoler : les cinq verts
quasi identiques employés pour un seul vert de charte (`#1B7A4E` 107 fois,
`#2D7A4E`, `#2D7A4F`, `#2D7B4A`, `rgba(29,122,70)`), et la colonne de droite
transcrite à `302px` là où la source Lovable écrit `grid-template-columns: 1fr
300px`. Le premier vient de l'axe palette, le second de `--source`.
