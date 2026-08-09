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
ruby $SK/facade_scan.rb readwrite .    # colonnes en sens unique
ruby $SK/facade_scan.rb static .       # contrôles non branchés dans les vues
```

Lance-les depuis le répertoire du projet (rbenv y choisit le bon Ruby). En phase
maquettes, ajoute `--mockups` aux deux. Ajoute `reachability .` si tu veux aussi
les routes qu'aucun geste n'atteint (plus bruyant, garde-le pour une review).
Ces deux modes sortent toujours en 0 : ce sont des rapports.

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
côté : app ou maquette, le script le précise), puis les écarts bloquants et
majeurs de `style_diff`, **groupés par cause** et non par page : « padding 16
au lieu de 24 sur 39 pages » est une ligne du gabarit, pas trente-neuf.

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

Détecte en plus, et ce sont les deux qui coûtent le plus cher en livraison :

- le **débordement horizontal** par viewport (mobile 390 px surtout), en disant
  de quel côté il se produit ;
- les **feuilles de style étrangères** chargées à côté des nôtres (un export
  Lovable ou Figma qui cohabite avec le design system : c'est ce qui a déformé
  une application entière pendant des semaines).

Ce qu'il ne voit pas : un seul état par page (ni survol, ni focus, ni modale, ni
formulaire en erreur), ni le contraste, ni la taille des cibles tactiles. Les
positions sont volontairement tolérantes (un décalage isolé de 3 px passe).
La précision monte quand les deux côtés affichent les MÊMES données : c'est la
raison d'être du jeu de données canonique (`doc/memory/jeu_de_donnees.md`).

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

`--mockups` cadre les deux sur la phase maquettes, avant le code : les routes
prévues face aux gestes de `app/views/mockups`, et les champs de
`doc/memory/data_models.md` face à ce que les maquettes affichent et saisissent.
C'est là que ça coûte le moins cher de corriger.

Limites connues : une lecture dont le receveur n'est pas identifiable compte pour
toutes les tables portant la colonne (le rapport le signale) ; une écriture qui
passe par un attribut virtuel autre que `<colonne>_input` échappe au scan ; en
mode maquettes le rapprochement se fait sur les noms, un champ nommé autrement
dans la maquette que dans `data_models.md` remonte comme absent.

---

## Quand s'en servir

- Le balayage complet : sur demande (« fais le balayage »), pendant
  `/brick-code-review`, ou sur un projet déjà livré qu'on reprend.
- En fin de lot pendant `/brick-code-build` : les modes courts, sur les pages du
  lot (`--only`).
- En phase maquettes : `facade_scan --mockups` seul, il n'y a pas encore de
  parité à mesurer.
- Après un `/brick-code-fix` qui touche une vue : `style_diff --only <page>`.

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
