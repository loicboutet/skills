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
mockup_scan est vert : pour ça il y a `--source`, `style_diff.js`, et l'œil.

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
