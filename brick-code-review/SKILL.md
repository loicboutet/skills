---
name: brick-code-review
description: "Pre-livraison bornee a DEUX passes : verrou et gel du perimetre a l'ouverture, pre-vol des outils, puis quatre verificateurs independants EN PARALLELE (recetteur du cahier, recette naive, matrice de permissions, verrou mobile) pendant que l'orchestrateur joue tests, consignation, config et securite ; un lot de fixes ; une passe 2 differentielle limitee a ce que les fixes ont touche ; verdict a deux etages (READY / READY SAUF DECISION HUMAINE / NEEDS FIXES) et journal des passes opposable. Parite et facades en indicateurs a seuil, une seule campagne adossee au tag. Utilise /brick-code-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. La review n'ECRIT pas le cahier de recette (il vient
de la reanalyse, rempli par le build) : elle le fait EXECUTER par des verificateurs qui
n'ont pas ecrit le code, corrige ce qu'ils trouvent, rejoue ce qu'elle a corrige, et
rend un verdict. **Elle tient en deux passes et une journee.** Au-dela, ce n'est plus de
la rigueur, c'est un process qui fuit, et on remonte a l'humain avec le journal.

> **Modeles et discipline de tour** : ce skill delegue a des sous-agents. Doctrine mesuree,
> commune a toute la chaine, dans `/brick-code-build` (« Repartition des modeles » et
> « Discipline de tour ») : tous les sous-agents en `model: "opus"`, et l'orchestrateur
> n'attend jamais un sous-agent en rendant son tour. **Les verificateurs de la passe 1
> tournent EN PARALLELE, chacun dans son worktree.**

## Ce que les six dernieres boucles ont mesure (pourquoi ce skill a cette forme)

Autopsie du 26/08/2026 sur yseis, vegetalents, gespilot, arcadesdata, tasteseller et
monmentor, logs de session a l'appui :

- **Le temps ne part pas dans la review, il part autour.** Occupation machine de 5 a
  18 % de l'empan calendaire (yseis : 23 h de travail sur 418 h). Une passe dure 2 a
  7 h quand elle tourne. Les jours viennent des arrets sans verdict (arcadesdata : 22 des
  23 trous d'une heure ou plus se terminent par une relance humaine, 25 relances
  vides), des nuits et week-ends, d'un verdict en attente d'un mot humain sur un point
  deja corrige (yseis : NEEDS FIXES tenu 10 jours), de l'agent reoriente ailleurs, et
  d'une collision entre deux VPS (monmentor : 26 h jetees).
- **Le rendement est inverse.** Parite `style_diff` : 558 constats pour 7 ecarts reels
  (yseis), 654 000 lignes de rapport pour 3 (vegetalents), 831 pour 0 (gespilot),
  4 079 pour ~17 (monmentor). Cahier : 92 % des criteres n'ont jamais porte un KO,
  rejoues integralement a chaque passe. Vingt-cinq pour cent des sous-agents filmaient
  le walkthrough a chaque lot de fixes. A l'inverse : recetteur independant (gespilot,
  2 h → 11 defauts dont le plus grave, arrive au 11e jour), recette naive (44 % de
  defauts reels), permissions (requete forgee, cross-tenant, 13 fuites), `mobile_gate`
  (101 → 0), et le tournage lui-meme (54 defauts APRES un cahier « 0 a remplir »).
- **La boucle n'avait pas de porte de sortie.** Porte de convergence jamais executee,
  code neuf et retours client absorbes par la review, fixes qui fabriquent la passe
  suivante (« six passes, six defauts deplaces »), perimetre qui grossit pendant la
  mesure (paires 21 → 87, bloquants 427 → 1 123 pendant que le produit s'ameliore),
  cahiers auto-attestes par le build a 48 % (« 0 critere a remplir », 54 defauts le
  lendemain).
- **La contre-preuve** : arcadesdata 25/08, quatre recetteurs en parallele dans des
  worktrees, boucle en 2,7 h fixes compris.

## LA REGLE DU DEFAUT CONNU (elle commande le verdict)

Un defaut de l'une de ces quatre familles, une fois CONSTATE par qui que ce soit et a
n'importe quel moment de la brique, **ne se consigne pas : il se corrige**.

1. **Argent** : montant faux, total inexplique, remise appliquee au mauvais client,
   document legal incomplet, arrondi qui derive.
2. **Permissions** : donnee lisible par un role qui n'y a pas droit, action possible sans
   le droit, fuite cross-tenant, IDOR.
3. **Donnees fausses** : valeur affichee qui ne correspond pas a la base, donnee
   fabriquee, enregistrement rattache silencieusement au mauvais parent.
4. **Fuite** : secret, credential ou donnee personnelle exposes.

Deux issues, pas trois : **corrige avant de livrer**, ou **verdict NEEDS FIXES et la
livraison ne part pas**. Aucune troisieme voie appelee « consigne », « argumente »,
« laisse ouvert », « a trancher » ou « connu ». Et la regle ne s'arrete pas aux quatre
familles : **un critere de recette note KO ne part pas en livraison**, quelle qu'en soit
la famille (audit qualite 08/2026 : un controle mort, note KO par le recetteur, livre).

**Interdit** : ranger un tel defaut dans `decisions.md`, `config.md`, le cahier ou le
rapport. Une ligne qui decrit un defaut d'argent ou de permission n'est pas une
decision, c'est un bug ouvert. Provenance : audit qualite 08/2026, devis emis pour le
mauvais client avec la mauvaise remise, « trouve par la review, laisse ouvert et
argumente », et cle d'API morte nommee « facade a trancher ».

## 0. Ouverture de la review : verrou, gel, pre-vol, budget

Rien de ce qui suit ne commence avant que cette section soit ecrite dans
`doc/memory/brick-{N}/passes.md` (cree ici, en append-only ; c'est le journal opposable
de la review).

### 0.1 Verrou d'exclusivite

1. `brick_tool` (action `get`) : si `held_by` porte quelqu'un d'autre → STOP, remonter.
   Sinon poser `held_by` a ton identite (`brick_tool update held_by:`).
2. `git fetch && git log --all --since=36.hours --format="%ae %ad %s"` : un autre auteur
   actif → STOP, remonter. (monmentor B2 : deux `/brick-code-review` sur la meme brique
   en parallele, memes defauts trouves deux fois, 102 commits a la poubelle.)

### 0.2 Gel du perimetre

```bash
git tag review-brique-{N}-passe-1          # le perimetre de la review, c'est CE commit
git worktree add /tmp/review-{N}-ro review-brique-{N}-passe-1   # arbre gele, lecture seule
```

- **Toute mesure (cahier, parite, mobile, facades) se fait sur l'arbre gele**, jamais
  sur la branche de travail. Une mesure faite pendant qu'un autre agent modifie des
  vues n'est pas une mesure (monmentor : « NON CERTIFIEE, a rejouer sur arbre gele »).
- **Aucun code neuf pendant la review.** Une exigence qui n'est pas dans le cahier
  derive a la reanalyse n'entre pas ici : elle va dans `later_brick` ou en changement
  de scope, et la review continue sur le tag. (arcadesdata 17/08 : 2 836 lignes de code
  neuf et 7 outils MCP « sous couvert de recette » ; yseis 21/08 : +21 000 lignes de
  nouvelles exigences, puis READY sur autre chose que le NEEDS FIXES.)
- **Aucun retour client pendant la review.** Ce qui arrive du client pendant la
  fenetre part dans le tracker et sera traite par `/brick-code-feedback` APRES le
  verdict. La review ne s'interrompt pas pour lui (tasteseller 06/08 : refus client
  absorbe par la review, 18 h et 3 312 messages, compteur jamais reparti).
- Les seuls fichiers qui bougent pendant une passe de mesure : `passes.md` et le cahier
  (statuts). Le code bouge entre les passes, dans le lot de fixes, et nulle part ailleurs.

### 0.3 Pre-vol des outils (15 minutes, pas plus)

Avant de rendre un outil bloquant, verifier qu'il voit cette application :

- `pairs_gen` apparie au moins 80 % des vues livrees a une maquette du tag
  `mockups-valides-brique-{N}` ; sinon completer `pairs.json` a la main sur les vues
  livrees, et ecrire le taux dans `passes.md` (monmentor : 7 vues appariees sur 79).
- `facade_scan readwrite` lit le schema REEL : si le metier vit dans des shards ou une
  seconde base, le pointer dessus ou le declasser en INFORMATION par ecrit (monmentor :
  scan sur `db/schema.rb`, 4 tables, « 0 constat » qui ne couvrait rien).
- `style_diff` prend pour reference les maquettes **au tag `mockups-valides-brique-{N}`**
  (worktree du tag), jamais `/mockups` courant (vegetalents : trois campagnes relancees
  pour cette seule raison).
- Serveur de dev lance sur l'arbre gele, base seedee avec le jeu canonique, memes
  donnees des deux cotes de chaque paire.

Un outil qui echoue au pre-vol n'est pas bloquant sur cette brique ; il est note
INFORMATION dans `passes.md` et le defaut d'outil remonte a `/outils-recette`.

### 0.4 Budget et journal des passes

- **Deux passes de mesure, quatre heures d'horloge chacune au plus**, puis le rejeu des
  fixes de la passe 2. Pas de troisieme passe de mesure. Si la passe 2 rend encore du
  neuf qui n'est pas une regression du lot de fixes, on s'arrete et on remonte a
  l'humain avec `passes.md` : c'est le perimetre ou la methode, pas la quantite de
  recettes.
- `passes.md`, append-only, une entree par passe :
  ```markdown
  ## Passe 1 — 2026-08-27 08:10 → 11:40 — tag review-brique-2-passe-1
  Verificateurs : R1 cahier (worktree a), R2 naive (b), R3 permissions (c), R4 mobile (d)
  Trouvailles : 23 (R1 9, R2 8, R3 4, R4 2) — dont defaut connu : 4
  Solde a l'ouverture de la passe 2 : 23 CORRIGEES (preuve rejouee) / 0 REPORTEES
  ```
  Une trouvaille n'a que deux statuts : CORRIGEE (preuve rejouee) ou REPORTEE (motif
  ecrit + accord consigne). Pas de « en cours ». **Une trouvaille deja vue qui ressort
  = echec de process** : elle ne regonfle pas le compteur, elle declenche la question
  « pourquoi la correction a-t-elle saute ? » et la reponse s'ecrit.
- Un commit de doc par passe, pas un par trouvaille : `review.md` s'ecrit UNE fois, au
  verdict (gespilot : reecrit 16 fois, 22 % des commits ne touchaient que `doc/`).

### 0.5 Prerequis : projet qui n'a pas suivi la chaine complete

Sur un projet plus ancien sans `objectif.md`, `decisions.md`, `jeu_de_donnees.md`,
`config.md` ou sans cahier derive, NE T'ARRETE PAS et ne les fabrique pas
retroactivement : signale en tete de `passes.md` lesquels manquent, ecris ici le cahier
qui manque (seule exception a « le cahier vient de la reanalyse »), et deroule quand
meme la passe 1 : ce sont les verificateurs qui trouvent les defauts, pas les artefacts.
Ce que la review ne peut pas verifier faute d'artefact s'ecrit comme tel, en une ligne,
et ne rouvre pas la boucle plus tard (tasteseller : la dette d'analyse a ete payee en
trois passes de review au lieu d'un refus d'entree en 20 minutes).

## 1. Passe 1 : quatre verificateurs independants, en parallele

**Regle d'organisation : verificateur ≠ implementeur.** Les criteres sont coches par
des sous-agents qui n'ont pas ecrit le code, briefes pour refuter (« prouve que ca
marche DEPUIS L'INTERFACE »). Ils travaillent sur l'app lancee depuis l'arbre gele,
avec les personas du jeu canonique, chacun dans son worktree, et rendent chacun une
liste de KO au format du cahier (ID, URL, compte, geste, observe, capture). Ils sont
lances **dans le meme appel**, l'orchestrateur attend les quatre DANS son tour.

### R1. Recetteur du cahier (`doc/memory/brick-{N}/recette.md`)

- **L'auto-attestation ne compte pas.** Un statut « couvert par la tache NNN » pose par
  le build vaut NON PROUVE : le recetteur rejoue ou le critere reste ouvert.
  (vegetalents : 48 % du cahier attestes par le build, « 0 critere a remplir », 54
  defauts le lendemain ; gespilot : 61/61 auto-coches dont un inatteignable, vu par un
  audit externe.)
- Preuve exigee pour chaque critere coche : URL, compte, geste, observation, capture.
  Un ATTEINT se prouve aussi durement qu'un NON ATTEINT. Console Rails ou test seul =
  NON atteint.
- **Cellule Statut = verdict + chemin de capture, 200 caracteres maximum.** Pas de
  prose (monmentor : 921 caracteres par cellule, 553 Ko de prose dans un cahier de
  821 Ko).
- Le recetteur execute un cahier qu'il n'a pas ecrit. Il ne retire ni n'affaiblit un
  critere ; il n'en AJOUTE que sur un defaut reel constate ou une classe de la taxonomie
  (`~/.claude/skills/taxonomie-recette/SKILL.md`) sans critere, jamais en masse.
  (yseis : 93 → 334 criteres en quatre passes ; monmentor : 92 % jamais KO.)
- Rejeu aleatoire : 10 preuves deposees par le build, rejouees ; un ecart invalide la
  preuve du critere. Le compte figure dans `passes.md`.
- Grosse brique (> 150 criteres) : R1 se decoupe en 2 a 4 recetteurs par sections du
  cahier, toujours en parallele (arcadesdata : quatre recetteurs, 2,7 h fixes compris).

### R2. Recette naive : le premier jour d'un vrai utilisateur

Derouler `~/.claude/skills/recette-naive/SKILL.md`, **mode application** : un compte
par run ou runs serialises, URL de depart = ecran de connexion avec les identifiants
de la persona, verificateur distinct. Elle attrape ce qu'aucune ligne du cahier ne
peut voir (fonction livree qu'aucun lien n'appelle, menu enferme sous les cartes,
« le candidat sera notifie » sans notification). Mesure : 44 % de defauts reels sur
les signalements arbitrables (yseis). Dose ~500 k jetons ; elle se lance ICI, en
passe 1, jamais apres le verdict (monmentor : sautee pour son cout, puis jouee apres
le GO, 4 ecrans manquants sur un lot valide).

### R3. Matrice de permissions : URL directe ET blocs d'affichage

Pour CHAQUE role du jeu canonique (dont les droits restreints) x CHAQUE donnee ou action
sensible, trois verifications :

1. **URL directe** : GET et verbe d'ecriture (PATCH/POST/DELETE) sur chaque ressource
   interdite — IDOR, cross-tenant (second tenant du jeu), etat interdit. Attendu :
   refus propre, donnee inchangee.
2. **Blocs d'affichage** : connecte AVEC le role restreint, ouvrir chaque page qui
   affiche la donnee (fiche, liste, dashboard, export, PDF, mail) et verifier
   VISUELLEMENT qu'elle n'y est pas. Le controle du menu ne protege pas la fiche.
3. **Valeur RENDUE d'un droit** : poster chaque niveau depuis l'invitation ET
   l'edition, relire en base. Un `read` qui ressort `write` est une fuite.

Livrable : matrice lignes = donnees/actions, colonnes = roles, cellule OK/FUITE avec
preuve, dans `recette.md`. Toute FUITE = defaut connu : elle se corrige. C'est le poste
au meilleur rendement de tout le corpus (vegetalents : remise en ligne d'une offre
archivee par requete forgee, cross-tenant `student_id` ; monmentor : 13 fuites d'une
seule famille).

### R4. Verrou mobile et parcours navigues

**Mobile : mesure, pas impression.** Sur CHAQUE ecran livre, a 390 px :

```bash
ruby ~/.claude/skills/outils-recette/mobile_gate.rb doc/memory/brick-{N}/parite/
```

Il lit le `resume.json` de `style_diff` (campagne de la section 3, lancee en debut de
passe 1 sur l'arbre gele) et ne regarde QUE les classes de saisie mobile
(`control-crushed`, `control-shrunk`, `clip-*`, `overflow-*`). Sa derniere ligne est la
ligne « Mobile (gate) » du rapport, collee telle quelle. exit 0 = passe ; exit 1 =
refus ; exit 2 = non mesure (un `style_diff` dont on n'a garde que le HTML n'a pas eu
lieu). Ne pas contourner en relancant sur moins d'ecrans.

A la main, sur un ecran douteux, TROIS sondes, jamais le seul `scrollWidth` (un
`overflow-x: clip|hidden` sur `body` rend toujours 390 ; 41 pages coupaient leurs
tableaux derriere un document au vert) :

```bash
playwright-cli -s=mob goto <url> && playwright-cli -s=mob resize 390 844
# 1. bord droit REEL hors conteneur defilant declare, hors fixed, hors animation : <= 390
playwright-cli -s=mob eval "(()=>{const ok=e=>{const s0=getComputedStyle(e);if(s0.position==='fixed'||s0.animationName!=='none')return false;for(let p=e.parentElement;p&&p!==document.body;p=p.parentElement){const s=getComputedStyle(p);if(['auto','scroll'].includes(s.overflowX)||s.position==='fixed'||s.animationName!=='none')return false}return true};let m=null;for(const e of document.querySelectorAll('body *')){const r=e.getBoundingClientRect();if(r.width<=0||!ok(e))continue;if(!m||r.right>m.right)m={right:r.right,lbl:e.tagName+'.'+(e.className||'')}}return m?Math.round(m.right)+' '+m.lbl:'rien'})()"
# 2. conteneurs NON defilants qui coupent : liste vide attendue
playwright-cli -s=mob eval "[...document.querySelectorAll('*')].filter(e => e.scrollWidth > e.clientWidth + 1 && !['auto','scroll'].includes(getComputedStyle(e).overflowX)).map(e => e.tagName + '.' + (e.className || '') + ' ' + e.scrollWidth + '/' + e.clientWidth)"
# 3. champs de saisie < 120 px : liste vide attendue
playwright-cli -s=mob eval "[...document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]), select, textarea')].map(e => (e.name || e.id || e.type) + ' ' + Math.round(e.getBoundingClientRect().width)).filter(l => +l.split(' ').pop() < 120)"
```

**Clause d'artefact.** Un constat de la gate verifie UN PAR UN comme artefact d'outil
(tableau a `overflow-x: auto` DECLARE, `object-cover` sur une image, element hors flux
masque) se documente avec sa preuve (capture + regle CSS) et ne bloque pas : la gate
rend « PASSE avec N artefacts documentes », et l'artefact remonte a `/outils-recette`
pour corriger la sonde. Une porte qui ne peut pas devenir verte par construction n'est
pas une porte (monmentor : 11 constats residuels, tous artefacts, verdict rendu a
l'humain faute de clause).

**Parcours navigues** : chaque parcours de `user_journeys.md` deroule au navigateur, en
cliquant (jamais en rejouant l'URL), avec la persona. Un ecran d'arrivee qui n'est pas
celui du parcours, un lien qui rend `Content missing`, une etape sans ecran = KO.

### Pendant ce temps, l'orchestrateur (sur l'arbre gele)

- **Consignation** : relire `decisions.md`, `config.md` et tout fichier de consignation
  ligne par ligne avec une seule question, « est-ce que cette ligne DECRIT un bug ? ».
  Chaque oui sort du fichier et devient un fix du lot. Le rapport compte ces lignes.
- **Suite de tests** : `bin/rails test` et `test:system` verts a J, J+3 et J+90 (shim
  d'horloge, T7) ; base fraiche T16 en TROIS invocations separees (`db:drop`, puis
  `db:prepare`, puis `db:seed`, puis `ls -l storage/*.sqlite3` et un comptage ; enchainees
  en une commande, SQLite ecrit dans l'inode efface et la preuve lit un fantome) ; second
  `db:seed` sans doublon ; aucune migration qui depend d'un modele ; chaque parcours de
  `user_journeys.md` a son system test ; **CI** qui a reellement tourne sur le dernier
  commit (`gh run list --limit 3`, `gh run view`) et gate le deploiement, sinon la creer.
- **Manifeste de configuration contre l'environnement livre** : chaque cle de
  `config.md` existe sur la cible, son consommateur nomme la lit vraiment (`grep`), sa
  valeur est celle de l'environnement (APP_HOST → liens des mails sur le host reel),
  aucun compte ni secret en dur dans migrations, seeds ou code (gespilot :
  `admin@5000.dev` / `secret5000` actif en prod depuis le 19 juin). Cle presente dans le
  code et absente du manifeste → ajoutee ici.
- **Securite** : `/security-review` sur `{base}..HEAD`, chaque finding corrige ou
  justifie par ecrit ; un finding permissions/fuite ne se justifie pas. Socle : strong
  parameters, autorisation sur chaque ressource, CSRF, pas de donnees sensibles dans les
  logs, auth = Devise.
- **Scope et gap analysis** : chaque AC de `acceptance_criteria.md` a un critere et un
  test ; chaque AC sert le QUOI de `objectif.md` ; les ajouts hors spec sont dans le
  journal de scope ou sortent. Format :
  ```markdown
  ## Gap Analysis - Brick #X
  ### Couvert — [x] R1/AC1.1 (recette R2-1.1 → test)
  ### Manquant — [ ] R2/AC2.3 (aucun critere)
  ### Hors scope (ajoute pendant le dev) — Extra: pagination users
  ```
- **Points de friction** : endroits ou un test a echoue plusieurs fois, code deplace ou
  renomme, TODO/FIXME, fichiers les plus remanies (`git diff --stat {base}..HEAD | sort
  -k3 -n | tail -10`), deviations de perimetre signalees par le build (`git log
  {base}..HEAD --grep='Deviation' --stat`) : un fichier partage touche par une tache qui
  ne le prevoyait pas est le lieu de la regression auto-infligee, on verifie les pages
  qui en dependent. Relecture a froid, facon `/vanilla-rails` : controllers < 7 actions,
  pas de logique metier dedans, pas de N+1, fichiers < 400 lignes, aucune abstraction
  sans AC ou decision qui la rattache (sinon on retire).

## 2. Le lot de fixes, puis la passe 2 differentielle

### 2.1 Un seul lot de fixes

Toutes les trouvailles de la passe 1 (R1 a R4 + orchestrateur) sont corrigees en UN lot,
sur la branche de travail, avec la methode de `/brick-code-fix` : test qui reproduit →
fix → **le meme bug ailleurs** (grep de la famille entiere, pas l'occurrence signalee :
arcadesdata D-26, « six passes, six defauts deplaces » ; 24/08, deux bloquants sur trois
etaient des regressions du 21/08) → re-check navigateur. Chaque fix cite l'ID de la
trouvaille. Le lot se termine par la suite complete verte et un nouveau tag
`review-brique-{N}-passe-2`.

### 2.2 Passe 2 : rejouer ce qui a bouge, pas tout

Sur l'arbre gele au tag passe-2, les verificateurs rejouent **uniquement** :

1. chaque trouvaille corrigee (preuve rejouee, statut CORRIGEE dans `passes.md`) ;
2. les criteres du cahier dont l'URL ou le parcours touche un fichier modifie par le
   lot (`git diff --name-only passe-1..passe-2` → vues, controleurs, partials, layouts
   → pages → criteres) ; un layout ou un partial partage touche = toutes les pages qui
   le rendent ;
3. `mobile_gate` sur les ecrans touches ;
4. la matrice de permissions sur les ressources touchees ;
5. 10 rejeux aleatoires supplementaires hors perimetre du lot, pour attraper la
   regression que la carte des fichiers ne voit pas.

Le reste du cahier n'est pas rejoue : il a ete prouve en passe 1 sur un arbre gele et
le lot ne l'a pas touche. (monmentor : 122 criteres rejoues integralement six fois.)

### 2.3 Sortie de la passe 2

- **Vide** (ou seulement des artefacts documentes) → verdict.
- **Regressions du lot** uniquement → un dernier lot de fixes borne a ces regressions,
  chaque fix rejoue par le verificateur, puis verdict. Ce n'est pas une passe : pas de
  mesure au-dela des fixes.
- **Du neuf qui n'est pas une regression** → STOP. On n'ouvre pas une passe 3. On
  remonte a l'humain avec `passes.md` et la liste : soit le perimetre gele etait faux,
  soit la methode de la passe 1 a un trou, et c'est ca qu'on corrige, pas le compteur.

## 3. Indicateurs a seuil : parite, facades, SEO, performance

Ces mesures se lancent UNE fois, en debut de passe 1, sur l'arbre gele, en parallele
des verificateurs. Elles produisent des indicateurs, pas des verdicts, sauf les cas
enumeres ci-dessous.

### 3.1 Parite maquette / application (une campagne)

```bash
ruby ~/.claude/skills/outils-recette/pairs_gen.rb . --out pairs.json --base http://127.0.0.1:$PORT
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json --out doc/memory/brick-{N}/parite/
```

- Reference = tag `mockups-valides-brique-{N}` (worktree), jeu canonique des deux
  cotes, **perimetre de chaque paire = la page entiere, layout compris** (sharifunding
  B2 : « tout etait bon sauf les sidebars », jamais comparees). Deux viewports.
- **Bloquant** : les ecarts de STRUCTURE (section manquante, ajoutee, reordonnee ; un
  partial de layout absent ; un faux objet dans le controleur) et les classes de saisie
  mobile (deja portees par `mobile_gate`). Ceux-la sont des KO du cahier.
- **Indicateur** : les ecarts de style (couleurs, espacements, tailles, typographie).
  On les lit TRIES PAR CAUSE (le rapport les regroupe), on corrige les causes qui
  tiennent en une heure, et le reste s'ecrit en une ligne : « N ecarts de style
  residuels, M causes, rapport `parite/index.html` ». Ils ne bloquent pas le verdict.
  Rendement mesure : 0,4 a 1,3 % d'ecarts reels par constat, 654 000 lignes de rapport
  pour 3 defauts. On ne relance pas la campagne en passe 2 hors pages touchees.
- Vue transcrite d'une source client (export Lovable, HTML depose) : le taux de reprise
  de classes n'est PAS un critere ; la reference est la source transcrite au tag, pas
  nos composants (tasteseller : pixel-match a 0-5 % realigne trois fois pour rien).
- Le rapport HTML cote a cote (`parite/index.html`, CONFORME / ECART JUSTIFIE / A
  CORRIGER par paire) reste la preuve de livraison publiable au client
  (`~/.nexrai/bin/nexrai-parite`).

### 3.2 Chasse aux facades (si le pre-vol l'a validee)

```bash
ruby ~/.claude/skills/outils-recette/facade_scan.rb readwrite .
ruby ~/.claude/skills/outils-recette/facade_scan.rb static .
```

`readwrite` sort la colonne affichee que personne ne peut saisir et le champ saisi que
personne ne lit. **Bloquant** seulement si la colonne part dans un document sortant
(facture, PDF, mail) ou porte de l'argent ou un droit ; sinon chaque remontee se tranche
par ecrit (defaut corrige, ou faux positif motive : colonne technique, service,
homonyme). `static` et `crawl` : information. `reachability` : information seulement,
presque que des faux positifs. Un scan sorti en code 2 n'a pas eu lieu. La matrice
affiche/saisi de la reanalyse et la matrice CRUD de `decisions.md` (chaque case
« offert » jouee depuis l'interface par R1, chaque « non offert » prouvee absente)
restent la reference. **Exception `/mockups`** : accessibles sans auth, y compris en
prod, inertes : pas une faille, pas une facade ; ce qui se verifie est T11 (`noindex`,
aucune donnee client reelle, hub qui pointe vers l'ecran livre).

### 3.3 SEO et performance (si pages publiques)

Derouler la « Checklist review » de `/brick-seo` (head, noindex staging, robots et
sitemap, JSON-LD, NAP, 404, titles, images). Prerequis CWV sur staging : CSS < 20 Ko
gz, HTML < 150 Ko, aucune image > 300 Ko, polices woff2 self-hosted, TTFB < 800 ms,
DOM < 1 500 noeuds, variants ActiveStorage partout. Un ecart bloquant ici = une page
publique inaccessible ou indexee a tort ; le reste est indicateur.

## 4. Verdict a deux etages

Le verdict s'ecrit quand la passe 2 est vide (ou quand ses regressions sont rejouees).
Trois valeurs, pas deux :

- **READY** : aucun KO, aucun defaut connu ouvert, gate mobile PASSE (artefacts
  documentes compris), CI verte sur le tag passe-2.
- **READY SAUF DECISION HUMAINE** : tout ce qui depend de nous est ferme ; il reste des
  points qui appartiennent a l'humain (un compte de demo a garder ou non, un choix de
  scope, une formulation client). Ils sont listes avec la recommandation, **le reste de
  la chaine s'enchaine** (walkthrough, guide, `finished`, `test_access`) et seul l'envoi
  attend la reponse. (yseis : NEEDS FIXES tenu 10 jours pour un point deja corrige, en
  attente d'un « laisse ».)
- **NEEDS FIXES** : il reste un KO ou un defaut connu que nous pouvons corriger et qui
  ne l'est pas. Ce verdict n'existe qu'entre deux passes ; il n'est jamais le mot de la
  fin d'une review bornee.

Un verdict est un fichier ecrit, date, avec le tag qu'il juge. Une boucle sans verdict
ecrit n'a pas eu lieu (arcadesdata : `recette.md` gele au 19/08, cinq passes apres, READY
jamais ecrit).

## 5. Rapport (court) : `doc/memory/brick-{N}/review.md`

Ecrit UNE fois, au verdict. 150 lignes au plus ; le detail vit dans `recette.md`,
`passes.md` et `parite/`.

```markdown
# Review Brick #X — {date} — tags passe-1 {sha} / passe-2 {sha}

## Verdict : READY | READY SAUF DECISION HUMAINE | NEEDS FIXES
## Decisions humaines en attente : [liste + recommandation] (ou aucune)
## Defauts connus (argent / permissions / donnees fausses / fuite) : X trouves, X corriges
## Criteres KO restants : 0 — lignes sorties des fichiers de consignation : X
## Passes : 2 — duree passe 1 : Xh — lot de fixes : N (dont M famille elargie) — passe 2 : rejoues Y, regressions Z
## Cahier : X criteres, dont A prouves par le recetteur, B ajoutes (defaut reel / taxonomie), C non applicables motives — auto-attestes comptes comme prouves : 0
## Recette naive : N runs, signalements Y, defauts reels Z (Z/Y), tous verses au cahier
## Permissions : matrice X roles x Y donnees, fuites trouvees F, toutes corrigees
## Mobile (gate) : [derniere ligne de mobile_gate.rb, collee telle quelle] — artefacts documentes : N
## Parcours navigues : X/Y
## Tests : X/Y, verts a J / J+3 / J+90, base fraiche 3 invocations, CI sur passe-2 OUI
## Config : X/Y cles verifiees sur l'env livre — secrets en dur : 0
## Securite : /security-review — X findings, Y corriges, Z justifies
## Parite : structure X/Y paires conformes (bloquant) — style : N ecarts residuels, M causes, rapport parite/index.html (indicateur)
## Facades : readwrite X remontees, Y tranchees (pre-vol : OUTIL VALIDE / INFORMATION)
## Gap analysis : couvert X / manquant Y / hors scope Z
## Choix a expliquer au client : [« a signaler » + corrections de maquette assumees]
## Outils : pairs_gen X % apparie — anomalies remontees a /outils-recette : [liste]
```

## 6. Apres le verdict

### 6.1 READY (ou READY SAUF DECISION HUMAINE) : la chaine s'enchaine, une fois

1. `git tag review-brique-{N}-ready`, `git worktree remove /tmp/review-{N}-ro`,
   `brick_tool update held_by: "-"`.
2. `brick-code-walkthrough` puis `brick-code-guide`, **tournes UNE fois, sur le tag
   ready**. Un walkthrough ne se refilme pas a chaque lot de fixes (yseis : 30 % des
   sous-agents en tournage, 0 defaut) ; si le tournage revele un defaut, il part en
   `/brick-code-fix` avec rejeu du critere, et seul le chapitre touche se refilme,
   decision de `brick-code-video`.
3. `brick_tool update status: finished` + `test_access` (URL et comptes de TEST que
   l'humain enverra) : le planning affiche « Termine — a envoyer au client ».
4. **STOP : l'envoi de la livraison est un geste humain.** Compte rendu final ici, avec
   les decisions humaines en attente s'il y en a.

Le cahier, `passes.md` et le rapport de parite sont des LIVRABLES, partageables au client
comme preuve de couverture et de conformite. Les « choix a expliquer » accompagnent la
livraison.

### 6.2 Apres le deploiement : la livraison ne s'arrete pas a la video

1. **Smoke test sur l'URL REELLE** : le parcours principal avec un compte reel ou un
   compte de test cree sur l'environnement livre, et **un mail reel declenche**, ouvert,
   verifie (habillage, destinataire, liens sur le host reel). Captures dans
   `brick-{N}/smoke/`.
2. **Error tracker sur 24 h** : baseline au deploiement, +1 h, +24 h
   (`glitchtip_list_issues`, `glitchtip_issue_detail`) ; projet absent →
   `glitchtip_create_project` et DSN cables AVANT de livrer.
3. **Une erreur nouvelle ne rouvre pas la review** : elle part dans `/brick-code-fix`
   (test qui reproduit → fix → meme bug ailleurs → taxonomie) avec rejeu du seul critere
   impacte. Un retour client part dans `/brick-code-feedback`. La review est close au
   tag ready ; ce qui vient apres est de la maintenance, pas une passe.

La brique est declaree livree apres 24 h sans erreur nouvelle.

**Acces prod** : toute lecture ou verification en production passe par kamal depuis le
dossier du projet, voir `/kamal` (`kamal app exec --reuse`, jamais de deploy manuel,
jamais les seeds pour deviner les donnees prod).

## Validation gate

- [ ] `passes.md` ouvert : verrou pose, tag passe-1, pre-vol des outils ecrit (valides /
      information), budget rappele
- [ ] Passe 1 : R1 a R4 lances en parallele dans des worktrees, sur l'arbre gele, avec
      les personas du jeu canonique ; aucune auto-attestation comptee
- [ ] Orchestrateur : consignation relue, tests J/J+3/J+90 + base fraiche + CI, config
      contre l'environnement, `/security-review`, gap analysis, points de friction
- [ ] Un seul lot de fixes, famille elargie a chaque fois, tag passe-2, suite verte
- [ ] Passe 2 differentielle : trouvailles rejouees, criteres des fichiers touches,
      mobile et permissions sur le perimetre touche, 10 rejeux hors perimetre
- [ ] Pas de passe 3 : du neuf non regressif en passe 2 = remontee humaine avec le journal
- [ ] Parite : structure bloquante, style en indicateur, une campagne sur le tag
- [ ] Verdict ecrit, date, avec ses tags ; rapport <= 150 lignes ecrit une fois
- [ ] Aucun code neuf ni retour client traite pendant la review
- [ ] Walkthrough tourne une fois sur le tag ready ; `finished` + `test_access` poses ;
      `held_by` libere

## Ensuite

L'enchainement est AUTOMATIQUE, dans le meme tour :

- **NEEDS FIXES** (entre les passes) → lot de fixes, tag passe-2, passe 2 differentielle,
  sans relance humaine. On ne remonte a l'humain qu'au STOP de 2.3 ou pour une decision
  qui lui appartient, et dans ce cas le verdict est READY SAUF DECISION HUMAINE et la
  chaine continue.
- **READY** ou **READY SAUF DECISION HUMAINE** → `brick-code-walkthrough` puis
  `brick-code-guide` (une fois, sur le tag ready), statut `finished` + `test_access`,
  `brick-code-video` pour les changements du jour. **PUIS STOP : l'envoi de la
  livraison au client est un geste humain**, le compte rendu final se fait la.

Cloture seulement apres smoke test et 24 h d'error tracker propres.
