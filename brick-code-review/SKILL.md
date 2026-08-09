---
name: brick-code-review
description: "Pre-livraison : cahier de recette pilote par la taxonomie de recette, recetteur separe, rapport de parite maquette/appli (style_diff), matrice de permissions, journal de decisions deroule, manifeste de config confronte a l'environnement livre, security-review, smoke test et surveillance post-deploiement. Utilise /brick-code-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. La review commence par l'ecriture du CAHIER DE
RECETTE, puis la suite de tests qui le fait passer, puis les checks complementaires.
Le cochage final est fait par un recetteur qui n'a pas ecrit le code. La brique n'est
livree qu'apres le smoke test et 24 h d'error tracker propres.

## Quand utiliser

- Avant de livrer une brick au client
- Avant de passer a la brick suivante
- Quand l'utilisateur demande un check global

## LA REGLE DU DEFAUT CONNU (elle commande le verdict)

Un defaut des quatre familles suivantes, une fois CONSTATE par qui que ce soit et
a n'importe quel moment, ne peut pas etre livre :

**argent** (calcul, total, remise, avoir) · **permissions** (fuite, action
interdite possible) · **donnee fausse** (valeur affichee qui ne vient pas de la
donnee reelle) · **fuite** (information exposee a qui ne doit pas la voir).

Deux issues, pas trois : il est CORRIGE, ou le verdict est NEEDS FIXES et la
livraison ne part pas. Il est interdit de le « consigner » dans
`decisions.md`, `config.md`, `initiatives.md`, le cahier de recette ou le rapport
de review et de livrer quand meme. **Une ligne qui decrit un defaut d'argent ou
de permission n'est pas une decision, c'est un bug ouvert.**

PREMIERE ACTION DE LA REVIEW, avant tout le reste : relire `decisions.md`,
`config.md` et tout fichier de consignation du projet en se demandant, ligne par
ligne, « est-ce que cette ligne DECRIT un bug ? ». Chaque oui part en
`/brick-code-fix` avant le verdict. Le rapport final compte ces lignes.

Provenance : mesure 08/2026. Une passe a livre un devis qui retombait sur le
mauvais client avec la mauvaise remise (defaut trouve par la review, laisse
ouvert) et une cle d'API morte nommee dans le manifeste avec la mention « facade
a trancher », jamais corrigee. Le process voyait les defauts et les rangeait.

## Prerequis : projet qui n'a pas suivi la chaine complete

Les artefacts `doc/memory/objectif.md`, `decisions.md`, `jeu_de_donnees.md` et
`config.md` n'existent que sur les projets passes par la chaine actuelle. Sur un
projet plus ancien, NE T'ARRETE PAS et ne les fabrique pas retroactivement : mene
la review avec ce qui existe (`acceptance_criteria.md`, les maquettes, le code),
signale en tete de rapport lesquels manquaient, et deroule quand meme la
taxonomie, la parite, la matrice de permissions et la chasse aux facades — ce
sont eux qui trouvent les defauts, pas les artefacts.

## Scope check

- [ ] Tout le code implemente correspond a un critere d'acceptance
- [ ] Chaque AC sert le QUOI de `doc/memory/objectif.md` (l'objectif signe)
- [ ] Pas de features "bonus" non demandees
- [ ] Les changements de scope sont documentes dans le journal de scope

## Regle d'organisation : recetteur ≠ implementeur

**Les AC et les criteres 🖐 sont coches par un SOUS-AGENT DE VERIFICATION qui n'a pas
ecrit le code.** (Audit qualite 08/2026 : Gespilot 61/61 AC auto-coches dont un inatteignable.)

- L'implementeur PREPARE : recette, tests, captures. Le recetteur COCHE, brief pour
  refuter : "prouve que ca marche DEPUIS L'INTERFACE".
- Preuve exigee pour chaque AC coche : screenshot ou trace playwright montrant que
  l'AC est atteignable depuis l'interface (pas la console Rails, pas un test seul).
  Un AC atteignable seulement en console = NON atteint.
- Le recetteur travaille sur l'app lancee, avec les personas du jeu canonique. Il rend
  son propre tableau ; ses "NON PROUVE" bloquent.

## Process

### 1. Cahier de recette (AVANT les tests)

**Fichier standardise : `doc/memory/brick-{N}/recette.md`** (un par brick ; mettre a
jour l'existant si la brick evolue, ne jamais en creer un deuxieme).

```markdown
# Recette — Brick #{N} : {nom}

Perimetre : {ce que couvre cette recette}
Hors perimetre : {explicitement exclu, avec raison}
Legende : ✅ = test automatise (chemin du test) · 🖐 = verification manuelle (preuve jointe)

## 1. {Domaine fonctionnel}

| ID | Critere | AC lie | Classe taxo | Test / preuve |
|----|---------|--------|-------------|---------------|
| R{N}-1.1 | Un {role} peut {action} et voit {resultat} | AC1.2 | — | ✅ test/... |
| R{N}-1.2 | {cas limite} ne {casse pas / ne fuit pas} | — | T{n} | ✅ test/... |

## Limites connues de l'environnement de test
- {ce qui n'est testable qu'a la main, et pourquoi}

## Criteres de sortie
Tous les ✅ verts, tous les 🖐 coches PAR LE RECETTEUR avec preuve, aucune ligne sans statut.
```

Regles de redaction :
- **Un critere = un objectif verifiable**, en langage metier ("le client voit ses
  factures triees"), pas en termes techniques.
- **Chaque critere d'acceptance de `acceptance_criteria.md` apparait** dans au moins
  un critere de recette (tracabilite AC ↔ recette ↔ test).
- **Chaque critere happy path appelle son negatif** : si "peut creer X", alors "ne
  peut pas creer X invalide / sans droit".
- IDs stables `R{N}-section.item` : on ne renumerote jamais, on ajoute.

#### Taxonomie de recette : la derouler INTEGRALEMENT

La taxonomie de reference est `~/.claude/skills/taxonomie-recette/SKILL.md`
(versionnee dans le repo skills). Pour CHAQUE classe T1-T19 : appliquer sa
**methode de verification** et creer les criteres correspondants (colonne "Classe
taxo"). Une classe sans critere = ligne "non applicable" JUSTIFIEE dans la recette,
jamais un silence.

La recette exerce aussi **TOUS les cas etiquetes du jeu de donnees canonique** : chaque
cas apparait dans au moins un critere.

#### Journal de decisions : chaque decision est un critere de recette

Ouvrir `doc/memory/decisions.md` et le derouler LIGNE A LIGNE :

- Chaque decision (analyse ET journal courant) donne un critere de recette qui prouve
  que le comportement decide est bien celui de l'app. Decision sans critere = trou.
- **Aucune donnee fabriquee** : reprendre chaque chiffre, compteur, score, graphique
  et vignette de l'app livree, et nommer sa source reelle. Une valeur sans source =
  bug bloquant, remplace par un etat vide honnete (jamais "corrige" en la laissant).
- Les lignes cochees **« a signaler »** sont extraites telles quelles dans une section
  `## Choix a expliquer au client` du rapport : formulation "voici ce qu'on a retenu et
  pourquoi", jamais une question.

**EXCEPTION mockups** : les vues sous `/mockups` sont volontairement accessibles sans
authentification, y compris EN PRODUCTION — c'est un choix assume (le client y suit les
briques a venir). Ne PAS le signaler comme faille. Ce qui se verifie, c'est ce qu'exige
la classe T11 : `noindex` sur ces pages, aucune donnee client reelle dans les donnees
fictives, et le hub `/mockups` qui indique les pages deja livrees et pointe vers l'ecran reel.

### 2. Suite de tests : faire passer la recette

```bash
bin/rails test 2>&1 | tail -20
bin/rails test:system 2>&1 | tail -20
bin/rails db:drop db:prepare db:seed 2>&1 | tail -20   # base fraiche, classe T16
```

- [ ] Chaque critere ✅ pointe vers un test qui existe ; chaque test cite son ID (`# R{N}-1.2`)
- [ ] Chaque parcours de `user_journeys.md` a son SYSTEM test navigateur vert
- [ ] Suite verte a J, **J+3 et J+90** (shim d'horloge / `travel_to` global — T7 ;
      audit qualite 08/2026 : fixtures de dates qui explosent a J+3)
- [ ] **Base fraiche** : `db:prepare` + `db:seed` depuis zero passent, `db:seed` rejoue
      ne cree pas de doublon, aucune migration ne depend d'un modele applicatif (T16)
- [ ] Tous les tests passent, aucun skip sans raison
- [ ] Si un test revele un bug → le corriger fait partie de la review

Ne JAMAIS affaiblir un critere pour faire passer un test : soit c'est un bug (fix),
soit c'est un changement de scope (documenter, puis ajuster la recette).

### 3. Gap Analysis (built vs specified)

```markdown
## Gap Analysis - Brick #X
### Couvert
- [x] R1/AC1.1: User registration (recette R2-1.1 → test)
### Manquant
- [ ] R2/AC2.3: Admin peut desactiver un compte (aucun critere de recette)
### Hors scope (ajoute pendant le dev)
- Extra: Pagination sur la liste users (pas dans les specs)
```

### 4. Rapport de parite maquette / appli

**Lance d'abord `style_diff` (`/outils-recette`)** : il compare les styles calcules
des deux cotes et sort la propriete qui differe, la ou l'oeil ne voit rien. Sur une
livraison declaree « 32/32 conformes » il a trouve 157 ecarts reels.

```bash
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json \
  --out doc/memory/brick-{N}/parite/
```

Tu ne juges ensuite a l'oeil que le residu : les ecarts que l'outil signale et que
tu dois trancher (corriger, ou justifier par ecrit avec la spec qui l'exige). Le
rapport genere est celui qu'on publie au client
(`~/.nexrai/bin/nexrai-parite`, page Conformite de l'espace client).

La comparaison complementaire se fait par SCREENSHOTS, jamais de memoire ni en lisant
le code. **Reference = le tag `mockups-valides-brique-{N}`** (si `/mockups` a bouge
depuis, capturer les maquettes depuis le tag), pas l'etat courant du repo.

Protocole (playwright-cli, serveur dev lance, DB seedee avec le jeu canonique) :

1. **Meme jeu de donnees des deux cotes** : toute comparaison a donnees differentes est nulle.
2. Pour chaque page implementee, capturer les paires aux DEUX viewports, **1440x900 ET 390x844** :
   ```
   playwright-cli -s=parite goto <url>/mockups/users && resize + screenshot → parite/users-mockup-1440.png / -390.png
   playwright-cli -s=parite goto <url>/admin/users   && resize + screenshot → parite/users-impl-1440.png / -390.png
   ```
3. Ouvrir chaque paire (Read) et comparer section par section : structure, ordre,
   espacements, couleurs, typographie, etats visibles (empty states, badges, troncatures).
4. Sur un ecart douteux, trancher au DOM : la seule difference autorisee est la liaison de donnees.
5. Grosse brique : 1 sous-agent juge par paire de pages, puis verifier ses "A CORRIGER".
6. **Rapport HTML cote a cote** : `doc/memory/brick-{N}/parite/index.html` — chaque ligne
   = paire d'images (mockup | impl), viewport, statut (CONFORME / ECART JUSTIFIE : {raison}
   / A CORRIGER). Le rapport propre sert de PREUVE DE LIVRAISON au client.

Mobile selon `decisions.md` :
- Responsive **dans le scope** → a 390 px : aucun `scrollWidth` > 390 sur les ecrans cles
  (`playwright-cli eval "document.documentElement.scrollWidth"`), formulaires utilisables.
  Deborde = A CORRIGER (audit qualite 08/2026 : ecran contacts a 1264 px).
- **"Hors scope assume (ecrit)"** → verifier que c'est ecrit ; capturer quand meme pour trace.

Verifier :
- [ ] Chaque page a sa paire aux deux viewports dans le rapport
- [ ] Markup HTML / classes Tailwind identiques au mockup (seule la liaison change)
- [ ] Aucune section ajoutee / retiree / reordonnee ; aucun faux objet (hash/OpenStruct)
- [ ] Tout ecart est CONFORME, JUSTIFIE PAR ECRIT, ou corrige

**Toute ligne A CORRIGER non justifiee bloque la livraison** (verdict NEEDS FIXES).

### 4b. Chasse aux facades a l'outil (BLOQUANT)

`style_diff` compare ce qui se voit. Ces deux scans trouvent ce qui ne se voit
pas : la donnee affichee que personne ne peut saisir, et le controle qui ne mene
nulle part.

```bash
ruby ~/.claude/skills/outils-recette/facade_scan.rb readwrite .
ruby ~/.claude/skills/outils-recette/facade_scan.rb static .
```

`readwrite` sort deux listes. **Colonne lue mais jamais saisissable** : l'ecran
(ou pire, le PDF ou l'e-mail) montre une valeur qu'aucun formulaire ne permet de
renseigner — chez un vrai client, le champ restera vide pour toujours.
**Colonne saisie mais jamais lue** : l'utilisateur remplit un champ qui ne sert a
rien. Les deux sont bloquantes des que la colonne part dans un document sortant.

Chaque remontee se tranche par ECRIT : defaut corrige, ou faux positif avec la
raison (colonne technique, alimentee par un service, homonyme dans une autre
table — l'outil rapproche sur le nom). Ne jamais se contenter du compte.

Si un scan sort en code 2, il s'est interrompu : son rapport ne prouve rien, on
le relance. Un rapport vide n'est un feu vert que si le scan est alle au bout.

Provenance : audit 08/2026 (clients.postal_code imprime sur les factures sans
champ de saisie, cle d'API saisie que l'envoi ne lit pas) ; mesure 08/2026 sur le
parc : 27 colonnes lues et non saisissables sur un projet client, 13 sur un
autre. Le mode `reachability` existe aussi mais reste EN INFORMATION : mesure a
l'appui, il ne produit presque que des faux positifs (actions appelees en
`fetch`, helpers resolus a l'execution).

### 5. Matrice de permissions : URL directe ET blocs d'affichage

Pour CHAQUE role (les personas du jeu canonique, dont ceux a droits restreints) x
CHAQUE donnee/action sensible, DEUX verifications distinctes :

1. **URL directe** : GET et verbe d'ecriture (PATCH/POST/DELETE) sur chaque ressource
   interdite — IDOR (id devine), cross-tenant (second tenant du jeu), etat interdit
   (editer un devis facture). Attendu : refus propre, donnee inchangee.
2. **Blocs d'affichage** : se connecter AVEC le role restreint et OUVRIR chaque page qui
   affiche la donnee sensible (fiche, liste, dashboard, export, PDF, mail) ; verifier
   VISUELLEMENT qu'elle n'y est pas. Le controle pense pour le menu ne protege pas la
   fiche (audit qualite 08/2026 : commercial billing:none lisait le CA sur la fiche client).

Livrer la matrice dans recette.md : lignes = donnees/actions sensibles, colonnes =
roles, chaque cellule = OK/FUITE avec la preuve (statut HTTP ou capture).

### 6. Manifeste de configuration contre l'environnement livre

Ouvrir `doc/memory/config.md` et verifier, ligne par ligne, sur l'environnement CIBLE :

- [ ] La cle existe bien dans l'environnement livre (ENV, credentials, config par env)
- [ ] Son **consommateur nomme** la lit vraiment : `grep` du nom de la cle dans le code,
      et le point d'usage reel correspond (audit qualite 08/2026 : ecran /admin/api_keys
      stockant un credential jamais lu a l'envoi)
- [ ] Sa valeur est celle attendue pour cet environnement : APP_HOST → les liens des
      mails generes pointent sur le host reel, pas app.5000.dev (Tastellers, educxa)
- [ ] Aucun compte, mot de passe ou secret en dur dans migrations, seeds ou code
      (Gespilot : superadmin `secret5000` actif en prod)
- [ ] Toute cle presente dans le code mais absente du manifeste y est ajoutee ici

### 7. Review UX

- [ ] Chaque parcours de `user_journeys.md` fonctionnel de bout en bout (system test +
      navigation reelle)
- [ ] Etats d'erreur geres (formulaire invalide, 404), messages flash presents et clairs
- [ ] Navigation coherente

### 8. Review code, deviations et simplicite

Vanilla Rails :
- [ ] Controllers < 7 actions, pas de logique business dedans ; modeles avec validations
- [ ] Pas de JS custom quand Turbo/Stimulus suffit ; pas de N+1 (`includes`) ; fichiers < 400 lignes

**Deviations de perimetre** (signal, pas verrou) — le build a calcule et signale dans
chaque commit les fichiers touches hors intention :
```bash
git log {base}..HEAD --grep='Deviation' -p --stat | head -80
```
Chaque deviation se relit specifiquement : un fichier partage touche par une tache qui
ne le prevoyait pas est le lieu classique de la regression auto-infligee (CSS global,
layout, partial partage, helper). Verifier que les autres pages qui en dependent sont
toujours conformes (parite + parcours).

**Controle de simplicite** (final, facon `/vanilla-rails`) : lister gems, tables,
colonnes, services, concerns et abstractions ajoutes par la brique ; pour chacun,
nommer l'AC ou la ligne de `decisions.md` qu'il sert. Sans rattachement → on retire.
Du code simple qui marche, sans cas a la con qui traine.

### 9. Securite

1. **Lancer le skill `/security-review` sur le diff de la brique** (`{base}..HEAD`) et
   traiter chaque finding : corrige, ou justifie par ecrit dans le rapport. C'est un
   passage obligatoire, pas une option.
2. Socle (les cas de securite de la taxonomie sont deja dans la recette avec leurs tests) :
   - [ ] Strong parameters sur tous les controllers
   - [ ] Autorisation verifiee (l'utilisateur a acces a la ressource)
   - [ ] Pas de donnees sensibles dans les logs ; CSRF actif
   - [ ] Auth = Devise (aucune auth maison introduite pendant la brick)

### 10. SEO et performance (si pages publiques)

Derouler la "Checklist review" de `/brick-seo` :
- [ ] Chaque page publique : title unique 50-60c, meta description unique, canonical
- [ ] curl staging → `X-Robots-Tag: noindex` present ; curl prod → ABSENT
- [ ] robots.txt prod : pas de `Disallow: /`, ligne Sitemap, bots IA non bloques
- [ ] sitemap.xml.gz accessible en prod, soumis GSC + Bing
- [ ] JSON-LD valide (validator.schema.org) sur home + 1 page de chaque gabarit
- [ ] NAP identique au caractere pres JSON-LD / footer
- [ ] 404 reel sur URL bidon ; test d'integration d'unicite des `<title>`
- [ ] Image heros : pas de lazy, `fetchpriority="high"` ; toutes images width/height
- [ ] Coherence nombres/dates ; aucun placeholder visible ; aucun jargon interne
- [ ] Les pages `/mockups` restent en `noindex` (elles ne remontent pas a la place des vraies)

Prerequis CWV, verifies au HTML sur staging (home + 1 page par gabarit) :
- [ ] Poids : CSS < 20 Ko gz, HTML < 150 Ko, aucune image > 300 Ko
      (`curl -so /dev/null -w '%{size_download}'`, assets via `playwright-cli requests`)
- [ ] Polices woff2 self-hosted + `preload`, pas de Google Fonts en prod
- [ ] TTFB staging < 800 ms (`curl -so /dev/null -w '%{time_starttransfer}'`) ; sinon
      verifier `fresh_when` / fragment caching
- [ ] DOM < 1500 noeuds (`playwright-cli eval "document.querySelectorAll('*').length"`)
- [ ] Aucune image uploadee servie brute : variants ActiveStorage partout

### 11. Repetition : repasser les points de friction

Les bugs sont concentres la ou le dev a coince, pas dans le CRUD sorti tout seul.
Reconstituer la liste depuis les taches, les commits et la conversation :

- endroits ou un test a echoue plusieurs fois avant de passer
- code reecrit, deplace ou renomme en cours de route
- decisions prises sous contrainte de temps, ou notees "a verifier plus tard"
- TODO / FIXME / commentaires d'excuse laisses dans le code
- fichiers les plus remanies : `git diff --stat {base}..HEAD | sort -k3 -n | tail -10`
- endroits ou il a fallu demander de l'aide a l'utilisateur

Pour chacun, relire le code a froid : est-ce la solution qu'on choisirait maintenant,
en sachant ce qu'on sait a la fin de la brick ? Ce qui reste douteux devient une ligne
du rapport (section Issues), pas un souvenir.

### 12. Rapport

`doc/memory/brick-{N}/review.md` :

```markdown
# Review Brick #X - [Date]

## Recette: X/Y criteres passes (✅ automatises: A, 🖐 manuels: M)
## Recetteur: sous-agent distinct OUI/NON — AC coches avec preuve: X/Y
## Taxonomie: X/19 classes deroulees (N/A justifies: ...)
## Tests: X/Y passing (verts a J, J+3, J+90 ; base fraiche OK)
## Decisions: X/X deroulees, 0 donnee fabriquee
## Choix a expliquer au client: [les lignes « a signaler » de decisions.md]
## Config: X/Y cles verifiees sur l'env livre (consommateur + valeur)
## Parite: X/Y paires conformes (1440 + 390) — style_diff: N ecarts, rapport: parite/index.html
## Permissions: matrice X roles x Y donnees, fuites: [liste]
## Deviations de perimetre relues: X (dont Y ayant motive une verification)
## Simplicite: X ajouts, Y retires faute de rattachement
## Securite: /security-review — X findings, Y corriges, Z justifies
## Points de friction repasses: X (dont Y encore douteux)
## Gaps / Issues / Bugs trouves par la recette: [listes]
## Verdict: READY / NEEDS FIXES
```

### 13. Apres le deploiement : la livraison ne s'arrete pas a la video

Un verdict READY autorise le deploiement, pas la cloture. Une fois deploye :

1. **Smoke test sur l'URL REELLE** (pas localhost, pas un mock) : jouer le parcours
   principal avec un compte reel du client ou un compte de test cree sur l'environnement
   livre, et **declencher un mail reel** (invitation, confirmation) — l'ouvrir, verifier
   habillage, destinataire et liens (host reel). Captures dans `brick-{N}/smoke/`.
2. **Surveillance de l'error tracker sur 24 h** : relever la baseline au moment du
   deploiement puis re-verifier a +1 h et +24 h.
   ```
   glitchtip_list_issues (projet de l'app) → baseline, puis +1 h, +24 h
   glitchtip_issue_detail sur toute issue nouvelle
   ```
   Si le projet GlitchTip n'existe pas : `glitchtip_create_project` et cabler le DSN
   AVANT de livrer (une brique sans error tracker n'est pas surveillable).
3. **Toute erreur nouvelle rouvre la boucle** : `/brick-code-fix` (test qui reproduit →
   fix → meme bug ailleurs → taxonomie), puis re-derouler la partie de recette impactee.
   La brique n'est declaree livree qu'apres 24 h sans erreur nouvelle.

## Sortie

Si READY → informer l'utilisateur, deployer, puis executer la section 13. Le cahier de
recette et le rapport de parite sont des LIVRABLES : partageables au client comme preuve
de couverture et de conformite. Les « choix a expliquer » accompagnent la livraison.
Si NEEDS FIXES → lister les fixes. Pour chaque fix, `/brick-code-fix` (test qui reproduit
→ fix → meme bug ailleurs → re-check navigateur → taxonomie), puis re-derouler la recette.

## Ensuite

→ `brick-code-video` (filmer la livraison), + `brick-code-guide` / `brick-code-walkthrough`.
Cloture seulement apres smoke test et 24 h d'error tracker propres.
