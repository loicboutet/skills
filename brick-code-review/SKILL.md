---
name: brick-code-review
description: "Pre-livraison : regle du defaut connu qui commande le verdict, execution du cahier de recette derive a la reanalyse, recetteur separe qui rejoue les preuves, rapport de parite maquette/appli (style_diff) et mobile mesure a 390 px, chasse aux facades a l'outil, matrice de permissions, journal de decisions deroule, manifeste de config confronte a l'environnement livre, security-review, smoke test et surveillance post-deploiement. Utilise /brick-code-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. La review n'ECRIT pas le cahier de recette : il a
ete derive a la reanalyse, avant la premiere ligne de code, et rempli par le build. La
review l'EXECUTE, l'etend si la taxonomie ou une regression l'exige, puis deroule les
checks complementaires. Le cochage final est fait par un recetteur qui n'a pas ecrit le
code. La brique n'est livree qu'apres le smoke test et 24 h d'error tracker propres.

> **Modeles et discipline de tour** : ce skill delegue a des sous-agents. Doctrine mesuree,
> commune a toute la chaine, dans `/brick-code-build` (« Repartition des modeles » et
> « Discipline de tour ») : tous les sous-agents en `model: "opus"`, et l'orchestrateur
> n'attend jamais un sous-agent en rendant son tour.

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
« laisse ouvert », « a trancher » ou « connu ». Un rapport de review qui DECRIT un tel
defaut sans le fermer n'est pas une review : c'est un aveu.

**Et la regle ne s'arrete pas aux quatre familles : un critere de recette note KO ne part
pas en livraison, quelle qu'en soit la famille.** Soit il est corrige et re-prouve, soit
le verdict est NEEDS FIXES. Un cahier qui porte un KO et un verdict READY se contredit
lui-meme. (Audit qualite 08/2026 : un controle mort, explicitement note KO par le
recetteur, est parti en livraison.)

**Interdit** : ranger un tel defaut dans `decisions.md`, `config.md`, le cahier de
recette ou ce rapport. **Une ligne qui decrit un defaut d'argent ou de permission n'est
pas une decision, c'est un bug ouvert.**

PREMIERE ACTION DE LA REVIEW, avant tout le reste : relire `decisions.md`, `config.md`
et tout fichier de consignation du projet en se demandant, ligne par ligne, « est-ce que
cette ligne DECRIT un bug ? ». Chaque oui sort du fichier et part en `/brick-code-fix`
avant le verdict. Le rapport final compte ces lignes.

Provenance : audit qualite 08/2026. Une livraison a emis un devis qui retombait sur le
mauvais client avec la mauvaise remise (defaut trouve par la review, laisse ouvert et
argumente) et une cle d'API morte nommee dans le manifeste avec la mention « facade a
trancher », jamais corrigee. Le process voyait les defauts et les rangeait.

## Prerequis : projet qui n'a pas suivi la chaine complete

Les artefacts `doc/memory/objectif.md`, `decisions.md`, `jeu_de_donnees.md` et
`config.md` — et le cahier `brick-{N}/recette.md` derive a la reanalyse — n'existent que
sur les projets passes par la chaine actuelle. Sur un projet plus ancien, NE T'ARRETE PAS
et ne les fabrique pas retroactivement : mene la review avec ce qui existe
(`acceptance_criteria.md`, les maquettes, le code), signale en tete de rapport lesquels
manquaient, ecris ici le cahier de recette qui manque (c'est la seule exception a la
regle « le cahier vient de la reanalyse »), et deroule quand meme la taxonomie, la
parite, la matrice de permissions et la chasse aux facades — ce sont eux qui trouvent les
defauts, pas les artefacts.

## Quand utiliser

- Avant de livrer une brick au client
- Avant de passer a la brick suivante
- Quand l'utilisateur demande un check global

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
- **Il execute un cahier qu'il n'a pas ecrit.** Il peut AJOUTER des criteres (taxonomie,
  regression, securite) ; il ne peut ni en retirer, ni en affaiblir la formulation.
  Tout « non applicable » se justifie par ecrit, ligne par ligne.
- **Un ATTEINT se prouve aussi durement qu'un NON ATTEINT** : URL, compte, geste,
  observation, capture. Une phrase ne coche rien. (Audit qualite 08/2026 : AC8.1 coche
  sur « suppression proposee sur la page d'edition », page qui n'offre que Annuler et
  Enregistrer.)
- **Rejeu aleatoire** : le recetteur tire 10 preuves deposees par le build et les REJOUE
  lui-meme depuis l'interface. Le compte de rejeux et leurs ecarts figurent dans le
  rapport ; un ecart invalide toute la preuve du critere, qui est refaite. (Ce rejeu a
  trouve 3 ecarts sur 10 lors de l'audit qualite 08/2026.)

## Convergence : pas de nouvelle passe de recette sans solde de la precedente

Une recette qui tourne en boucle (8 passes sur un meme lot, du nouveau a chaque fois)
n'est pas de la rigueur, c'est un process qui fuit. Provenance : retour terrain 08/2026,
l'agent relançait des recettes alors que, interroge, il admettait que les trouvailles
precedentes n'etaient ni toutes corrigees ni consignees.

Avant TOUTE nouvelle passe de recette (recetteur, recette-naive, rejeu), reponds par
ecrit, preuves a l'appui, a ces deux questions ; un seul « non » INTERDIT la passe :

1. **« Tout ce que la passe precedente a trouve est-il corrige ? »** Chaque trouvaille
   a un statut : CORRIGEE (avec la preuve rejouee, comme un AC) ou REPORTEE (avec le
   motif ecrit et l'accord consigne). Pas de troisieme statut, pas de « en cours ».
2. **« La memoire est-elle a jour ? »** Cahier de recette, fichiers de consignation,
   doc/memory : les trouvailles corrigees y sont soldees, les reportees y sont
   inscrites. Sinon la passe suivante re-decouvre les memes defauts et le compte
   de « nouveautes » ment.

Et deux regles de bouclage :

- **Une trouvaille deja vue qui ressort = echec de process, pas une nouveaute.**
  Elle ne regonfle pas le compteur ; elle declenche la question « pourquoi la
  correction ou la consignation a-t-elle saute ? », et la reponse s'ecrit.
- **Deux passes successives qui apportent chacune du nouveau → on ne relance pas
  une troisieme a l'aveugle.** On s'arrete, on fait UN balayage outille complet
  (cahier + outils + parcours), on solde tout, et la passe suivante doit sortir
  quasi vide. Si elle ne l'est pas, on remonte a l'humain avec le journal des
  passes : c'est le perimetre ou la methode qui est en cause, pas la quantite
  de recettes.

## Process

### 1. Cahier de recette : l'executer, l'etendre, jamais le rabaisser

**Fichier `doc/memory/brick-{N}/recette.md`**, DEJA ecrit par la reanalyse et rempli par
le build (un par brick, jamais un deuxieme). La review l'ouvre, verifie qu'il est complet
au regard des trois sources d'origine (AC x role, cas etiquetes du jeu canonique, lignes
de `decisions.md` dont la matrice CRUD), puis l'etend avec ce que les sections suivantes
exigent. Format d'une ligne : ID, critere, AC/decision, URL, compte, geste, observation
attendue — puis la preuve constatee et le statut.

Regles :
- **Un critere = un objectif verifiable**, en langage metier ("le client voit ses
  factures triees"), pas en termes techniques.
- **Chaque AC de `acceptance_criteria.md` apparait** dans au moins un critere.
- **Chaque critere happy path appelle son negatif** : si "peut creer X", alors "ne
  peut pas creer X invalide / sans droit".
- IDs stables `R{N}-section.item` : on ne renumerote jamais, on ajoute.
- **On ajoute, on ne retire pas.** Un critere juge trop dur reste : soit il est atteint,
  soit c'est un defaut. Le seul retrait possible est un « non applicable » ecrit et motive.
- Criteres de sortie : tous les ✅ verts, tous les 🖐 coches PAR LE RECETTEUR avec preuve,
  aucune ligne sans statut, **aucun KO restant** (voir la regle du defaut connu).

#### Taxonomie de recette : la derouler INTEGRALEMENT

La taxonomie de reference est `~/.claude/skills/taxonomie-recette/SKILL.md`
(versionnee dans le repo skills). Pour CHAQUE classe T1-T19 : appliquer sa
**methode de verification** et creer les criteres correspondants (colonne "Classe
taxo"). Une classe sans critere = ligne "non applicable" JUSTIFIEE dans la recette,
jamais un silence. La section « Conventions de l'atelier » de la taxonomie dit ce qui
N'EST PAS un defaut : la lire avant de qualifier une remontee.

La recette exerce aussi **TOUS les cas etiquetes du jeu de donnees canonique** : chaque
cas apparait dans au moins un critere.

#### Journal de decisions : chaque decision est un critere de recette

Ouvrir `doc/memory/decisions.md` et le derouler LIGNE A LIGNE :

- Chaque decision (analyse ET journal courant) donne un critere de recette qui prouve
  que le comportement decide est bien celui de l'app. Decision sans critere = trou.
- **Aucune donnee fabriquee** : reprendre chaque chiffre, compteur, score, graphique
  et vignette de l'app livree, et nommer sa source reelle. Une valeur sans source =
  bug bloquant, remplace par un etat vide honnete (jamais "corrige" en la laissant).
- **Aucune ligne qui decrive un defaut** (voir la regle du defaut connu) : celles-la
  sortent du fichier et deviennent des fixes.
- Les lignes cochees **« a signaler »** sont extraites telles quelles dans une section
  `## Choix a expliquer au client` du rapport : formulation "voici ce qu'on a retenu et
  pourquoi", jamais une question. Les corrections de maquette faites en cours de route
  (regle « la maquette n'est jamais une excuse ») y figurent aussi.

#### Matrice CRUD jouee depuis l'interface

Le scanner de facades (section 4b) ne cherche pas ce qui MANQUE : croiser avec la
**matrice CRUD** de `decisions.md` — chaque case « offert » est jouee DEPUIS L'INTERFACE
(bouton trouve, geste fait, effet constate), chaque case « non offert » est prouvee
absente (aucun bouton, et verbe direct refuse).

**EXCEPTION mockups** : les vues sous `/mockups` sont volontairement accessibles sans
authentification, y compris EN PRODUCTION — c'est un choix assume (le client y suit les
briques a venir), et elles ont le droit d'etre inertes : ne PAS les signaler comme faille
ni comme facade. Ce qui se verifie, c'est ce qu'exige la classe T11 : `noindex` sur ces
pages, aucune donnee client reelle dans les donnees fictives, et le hub `/mockups` qui
indique les pages deja livrees et pointe vers l'ecran reel.

### 2. Suite de tests : faire passer la recette

```bash
bin/rails test 2>&1 | tail -20
bin/rails test:system 2>&1 | tail -20
```

- [ ] Chaque critere ✅ pointe vers un test qui existe ; chaque test cite son ID (`# R{N}-1.2`)
- [ ] Chaque parcours de `user_journeys.md` a son SYSTEM test navigateur vert
- [ ] Suite verte a J, **J+3 et J+90** (shim d'horloge / `travel_to` global — T7 ;
      audit qualite 08/2026 : fixtures de dates qui explosent a J+3)
- [ ] **Base fraiche** (T16), en TROIS invocations SEPAREES — `db:drop`, puis
      `db:prepare`, puis `db:seed` — suivies d'un `ls -l storage/*.sqlite3` et d'un
      comptage en base. Enchainees en une seule commande, SQLite ecrit dans le fichier
      efface (inode encore ouvert) : la commande sort 0 et la base reste vide, la preuve
      d'idempotence lit un fantome. Puis `db:seed` une seconde fois : aucun doublon.
- [ ] Aucune migration ne depend d'un modele applicatif (T16)
- [ ] Tous les tests passent, aucun skip sans raison
- [ ] Si un test revele un bug → le corriger fait partie de la review
- [ ] **CI** : un workflow joue les deux suites sur push/PR, a REELLEMENT tourne sur le
      dernier commit (`gh run list --limit 3` puis `gh run view <id>` ; `gh` est
      installe et authentifie sur les VPS) et gate le deploiement. Absente → la
      creer ici, pas a la brique suivante.

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

### 4. Rapport de parite maquette / appli, et mobile mesure

**Lance d'abord `style_diff` (`/outils-recette`)** : il compare les styles calcules
des deux cotes et sort la propriete qui differe, la ou l'oeil ne voit rien. Sur une
livraison declaree « 32/32 conformes » il a trouve 157 ecarts reels.

```bash
ruby ~/.claude/skills/outils-recette/pairs_gen.rb . --out pairs.json --base http://127.0.0.1:$PORT
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json \
  --out doc/memory/brick-{N}/parite/
```

**Le perimetre de chaque paire est la PAGE ENTIERE, layout compris** : sidebar,
topbar, footer, navigation. Pas seulement le contenu central. (Retour terrain
21/08/2026, sharifunding B2 : « tout etait bon sauf les sidebars » — jamais
comparees parce que rendues par des partials de layout. Une paire qui exclut le
cadre valide une page qui n'existe pas.)

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

**Mobile : mesure, pas impression.** Sur CHAQUE ecran livre, a 390 px, TROIS mesures.
**Ne conclus JAMAIS « conforme » sur le seul `document.documentElement.scrollWidth`** :
cette valeur ne prouve rien a elle seule, parce qu'un `overflow-x: clip|hidden` pose sur
`body` (ou sur un conteneur du gabarit) CLIPPE le debordement au lieu de le rendre
defilable, et la fait donc toujours egale a la largeur du viewport. Mesure 08/2026 : une
messagerie dont le bouton « Envoyer » etait hors ecran, et 20 maquettes dont plusieurs
debordaient franchement, passaient toutes au vert sur cette seule mesure.

Le chemin le plus court est l'outil : `style_diff` detecte deja les conteneurs qui
rognent et les controles ecrases, et rend ses resultats CLASSES par cause. On le lance et
on lit ses categories (`clip-implicite` et `clip-declare` = contenu coupe, bloquants ;
`scroll-voulu` = defilement declare, information), on ne compare pas deux nombres a la
main :

```bash
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json --viewport mobile \
  --out doc/memory/brick-{N}/parite/
```

A la main, ecran par ecran :

```bash
# 1. le bord droit REEL : l'element le plus a droite de la page, en excluant ce qui vit
#    dans un conteneur a defilement horizontal DECLARE, ce qui est en position: fixed,
#    et ce qui est en cours d'animation. Doit rendre <= 390.
playwright-cli -s=mob eval "(()=>{const ok=e=>{const s0=getComputedStyle(e);if(s0.position==='fixed'||s0.animationName!=='none')return false;for(let p=e.parentElement;p&&p!==document.body;p=p.parentElement){const s=getComputedStyle(p);if(['auto','scroll'].includes(s.overflowX)||s.position==='fixed'||s.animationName!=='none')return false}return true};let m=null;for(const e of document.querySelectorAll('body *')){const r=e.getBoundingClientRect();if(r.width<=0||!ok(e))continue;if(!m||r.right>m.right)m={right:r.right,lbl:e.tagName+'.'+(e.className||'')}}return m?Math.round(m.right)+' '+m.lbl:'rien'})()"
# 2. les conteneurs NON defilants (un overflow-y-auto fait calculer un overflow-x: auto
#    implicite qui absorbe le debordement et coupe le contenu en silence)
playwright-cli -s=mob eval "[...document.querySelectorAll('*')].filter(e => e.scrollWidth > e.clientWidth + 1 && !['auto','scroll'].includes(getComputedStyle(e).overflowX)).map(e => e.tagName + '.' + (e.className || '') + ' ' + e.scrollWidth + '/' + e.clientWidth)"
# 3. la largeur reelle des champs de saisie
playwright-cli -s=mob eval "[...document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]), select, textarea')].map(e => (e.name || e.id || e.type) + ' ' + Math.round(e.getBoundingClientRect().width)).filter(l => +l.split(' ').pop() < 120)"
```

Les deux dernieres listes doivent etre VIDES : une ligne = du contenu coupe que rien ne
permet de faire defiler, ou un champ inutilisable. (Audit qualite 08/2026 : 41 pages
coupaient leurs tableaux derriere un document a 390 ; des `input` a 18 px sur un ecran
declare conforme.) Un ecart se corrige, meme si la maquette deborde pareil : dans ce cas
la maquette est fausse, on corrige les deux cotes et on le signale au client. Comparer
aux mesures ecrites par la reanalyse : un ecran a 390 en maquette et a 465 dans l'app est
une regression du build. Si `decisions.md` dit « responsive hors scope assume (ecrit) »,
mesurer et ecrire quand meme.

Verifier :
- [ ] Chaque page a sa paire aux deux viewports dans le rapport
- [ ] Markup HTML / classes Tailwind identiques au mockup (seule la liaison change, ou
      une correction assumee des DEUX cotes)
- [ ] Aucune section ajoutee / retiree / reordonnee ; aucun faux objet (hash/OpenStruct)
- [ ] Les trois mesures mobiles passent sur tous les ecrans livres
- [ ] Tout ecart est CONFORME, JUSTIFIE PAR ECRIT, ou corrige

**Toute ligne A CORRIGER non justifiee bloque la livraison** (verdict NEEDS FIXES).

**Le verrou mobile, mecanique (OBLIGATOIRE avant d'ecrire le verdict).** Les trois
mesures ci-dessus sont ecrites depuis aout 2026 ; le 16-17/08 deux livraisons sur trois
ont quand meme ete rendues avec des champs de prix a 18 px sur mobile, l'une avec 26
`control-crushed` bloquants dans son propre rapport style_diff au moment du READY. La
regle etait lue, le rapport ne l'etait pas. Donc on ne lit plus, on verrouille :

```bash
ruby ~/.claude/skills/outils-recette/mobile_gate.rb doc/memory/brick-{N}/parite/
```

Il lit le `resume.json` et les `paires/*.json` de style_diff et ne regarde QUE les
classes de saisie mobile (`control-crushed`, `control-shrunk`, `clip-*`, `overflow-*`) :
la parite de style, bruyante, reste a ton jugement. Sa derniere ligne de sortie EST la
ligne « Mobile (gate) » du rapport (section 12) : on la colle, on ne la reformule pas.
- exit 0 → la gate passe, tu peux ecrire le verdict.
- exit 1 → REFUS : un verdict READY est interdit. Corriger, relancer style_diff,
  relancer la gate.
- exit 2 → NON MESURE (rapport absent, sans viewport mobile, ou vide) : meme interdit.
  Un `style_diff` dont on n'a garde que le HTML n'a pas eu lieu.
Ne pas contourner en relancant style_diff sur moins d'ecrans : `pairs.json` doit couvrir
chaque page livree (controle [ ] ci-dessus).

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

Chaque remontee finit en critere de recette (T4/T5) et se tranche par ECRIT : defaut
corrige, ou faux positif avec la raison (colonne technique, alimentee par un service,
homonyme dans une autre table — l'outil rapproche sur le nom). Ne jamais se contenter du
compte. Angle mort connu : le scan rate une colonne dont le nom existe ailleurs, la
matrice affiche/saisi de la reanalyse reste la reference.

Si un scan sort en code 2, il s'est interrompu : son rapport ne prouve rien, on
le relance. Un rapport vide n'est un feu vert que si le scan est alle au bout.

Provenance : audit qualite 08/2026 (clients.postal_code imprime sur les factures sans
champ de saisie, cle d'API saisie que l'envoi ne lit pas ; sur le parc : 27 colonnes lues
et non saisissables sur un projet client, 13 sur un autre). Les modes `crawl` et
`reachability` existent aussi mais restent EN INFORMATION : mesures a l'appui,
`reachability` ne produit presque que des faux positifs (actions appelees en `fetch`,
helpers resolus a l'execution). Les lire, ne rien bloquer dessus.

### 5. Matrice de permissions : URL directe ET blocs d'affichage

Pour CHAQUE role (les personas du jeu canonique, dont ceux a droits restreints) x
CHAQUE donnee/action sensible, TROIS verifications distinctes :

1. **URL directe** : GET et verbe d'ecriture (PATCH/POST/DELETE) sur chaque ressource
   interdite — IDOR (id devine), cross-tenant (second tenant du jeu), etat interdit
   (editer un devis facture). Attendu : refus propre, donnee inchangee.
2. **Blocs d'affichage** : se connecter AVEC le role restreint et OUVRIR chaque page qui
   affiche la donnee sensible (fiche, liste, dashboard, export, PDF, mail) ; verifier
   VISUELLEMENT qu'elle n'y est pas. Le controle pense pour le menu ne protege pas la
   fiche (audit qualite 08/2026 : commercial billing:none lisait le CA sur la fiche client).
3. **Valeur RENDUE d'un droit** : poster chaque niveau de permission depuis l'ecran
   d'invitation ET l'ecran d'edition, puis relire la valeur en base. Un `read` poste qui
   ressort en `write` est une fuite silencieuse (audit qualite 08/2026).

Livrer la matrice dans recette.md : lignes = donnees/actions sensibles, colonnes =
roles, chaque cellule = OK/FUITE avec la preuve (statut HTTP ou capture). Toute FUITE
tombe sous la regle du defaut connu : elle se corrige, elle ne se note pas.

### 6. Manifeste de configuration contre l'environnement livre

Ouvrir `doc/memory/config.md` et verifier, ligne par ligne, sur l'environnement CIBLE :

- [ ] La cle existe bien dans l'environnement livre (ENV, credentials, config par env)
- [ ] Son **consommateur nomme** la lit vraiment : `grep` du nom de la cle dans le code,
      et le point d'usage reel correspond. Un ecran qui enregistre une valeur que
      personne ne relit est une facade : on la branche, ou on retire l'ecran. Ecrire
      « facade a trancher » dans le manifeste est interdit (audit qualite 08/2026 :
      ecran /admin/api_keys stockant un credential jamais lu a l'envoi)
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

### 7b. Recette naive : le premier jour d'un vrai utilisateur (BLOQUANT si un defaut reel sort)

La section 7 deroule `user_journeys.md`. Le cahier de recette porte l'URL, le compte, le geste et
l'observation attendue de chaque ligne. Consequence : **rien dans la chaine ne peut etre
surpris.** On verifie « le critere est-il satisfait », jamais « quelqu'un qui ne sait rien y
arrive-t-il ». Cette section est le seul endroit du process ou l'on mesure la seconde question.

**Derouler `~/.claude/skills/recette-naive/SKILL.md`, en MODE APPLICATION.** La methode y est
entiere. Ce qui est propre a ce stade :

- **Un compte par run, ou des runs serialises.** Deux agents sur le meme compte produisent des
  devis en double et des compteurs qui bougent : 12 faux signalements sur un seul projet.
- **L'URL de depart est l'ecran de connexion**, avec les identifiants de la persona.
- **Chaque defaut reel rejoint le cahier de recette au statut KO** et commande le verdict (regle
  du defaut connu). Il ne se consigne pas, il se corrige.

Ce qu'elle attrape et que rien d'autre n'attrape (mesure, banc livraison p5, 33 defauts reels
dont 33 sur 34 absents des rapports de recette) : un lien qui remplace la page par `Content
missing` parce que la recette avait rejoue l'URL et jamais le clic ; une fonction livree et
complete qu'aucun lien n'appelle ; un onglet inatteignable a vie, seule fonction differee sans
badge « a venir » ; un menu dont 8 options sur 9 sont physiquement enfermees sous les cartes ;
« Le candidat sera notifie. » alors qu'aucune notification n'est creee.

**Elle ne remplace aucune ligne du cahier** : sur tout le corpus mesure les deux bras ne se
recouvrent qu'en un seul point. Dose : ~500 k jetons par brique, et elle suit le nombre de types
d'utilisateurs enumeres.

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
   traiter chaque finding : corrige, ou justifie par ecrit dans le rapport. Un finding de
   la famille permissions/fuite ne se justifie pas : il se corrige. C'est un passage
   obligatoire, pas une option.
2. Socle (les cas de securite de la taxonomie sont deja dans la recette avec leurs tests) :
   - [ ] Strong parameters sur tous les controllers
   - [ ] Autorisation verifiee (l'utilisateur a acces a la ressource)
   - [ ] Pas de donnees sensibles dans les logs ; CSRF actif
   - [ ] Auth = Devise (aucune auth maison introduite pendant la brick)

### 10. SEO et performance (si pages publiques)

Derouler INTEGRALEMENT la « Checklist review » de `/brick-seo` (head complet, noindex
staging / absent en prod, robots + sitemap, JSON-LD valide, NAP identique, 404 reel,
unicite des titles, images, coherence des chiffres). Elle n'est pas recopiee ici : elle
vit dans ce skill, on l'ouvre et on la deroule ligne a ligne.

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

## Defauts connus (argent / permissions / donnees fausses / fuite) : X trouves, X corriges
   — si un seul reste ouvert, le verdict est NEEDS FIXES
## Criteres de recette au statut KO : X — un seul KO restant = NEEDS FIXES
   — et mobile_gate.rb en REFUS ou NON MESURE = NEEDS FIXES, sans discussion
## Lignes sorties des fichiers de consignation parce qu'elles decrivaient un bug : X
## Recette: X/Y criteres passes (✅ automatises: A, 🖐 manuels: M)
## Recetteur: sous-agent distinct OUI/NON — 10 preuves rejouees, Z ecarts
## Cahier execute (ecrit a la reanalyse): X criteres, Y ajoutes ici, Z « non applicable » motives
## readwrite / static: X remontees, Y tranchees — CRUD: A cases « offert » jouees, B « non offert » prouvees absentes
## CI: presente OUI/NON — a tourne sur le dernier commit OUI/NON
## Taxonomie: X/19 classes deroulees (N/A justifies: ...)
## Tests: X/Y passing (verts a J, J+3, J+90 ; base fraiche verifiee en 3 invocations)
## Decisions: X/X deroulees, 0 donnee fabriquee
## Choix a expliquer au client: [« a signaler » + corrections de maquette assumees]
## Config: X/Y cles verifiees sur l'env livre (consommateur + valeur)
## Parite: X/Y paires conformes (1440 + 390) — style_diff: N ecarts, rapport: parite/index.html
## Mobile (gate) : [derniere ligne de mobile_gate.rb, collee telle quelle — PASSE ou REFUS/NON MESURE]
## Mobile: X/X ecrans — document 390, conteneurs non defilants OK, champs >= 120 px
## Permissions: matrice X roles x Y donnees, fuites: [liste] — toutes corrigees OUI/NON
## Deviations de perimetre relues: X (dont Y ayant motive une verification)
## Simplicite: X ajouts, Y retires faute de rattachement
## Securite: /security-review — X findings, Y corriges, Z justifies
## Points de friction repasses: X (dont Y encore douteux)
## Recette naive: N runs (M personas x P objectifs derives du QUOI), verificateur distinct OUI/NON
##   — signalements bruts: X, arbitrables: Y, defauts reels: Z (rendement Z/Y), tous verses au cahier
##   — soustraction verifiee sur les N traces: 0 lecture du depot, 0 URL tapee hors URL de depart
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
de couverture et de conformite (le rapport de parite se publie avec
`~/.nexrai/bin/nexrai-parite`). Les « choix a expliquer » accompagnent la livraison.
Si NEEDS FIXES → lister les fixes. Pour chaque fix, `/brick-code-fix` (test qui reproduit
→ fix → meme bug ailleurs → re-check navigateur → taxonomie), puis re-derouler la recette.

**Accès prod** : toute lecture ou vérification en production passe par kamal
depuis le dossier du projet — voir `/kamal` (règle d'or : `kamal app exec --reuse`,
jamais de deploy manuel, jamais les seeds pour deviner les données prod).

## Ensuite

→ `brick-code-video` (filmer la livraison), + `brick-code-guide` / `brick-code-walkthrough`.
Cloture seulement apres smoke test et 24 h d'error tracker propres.
