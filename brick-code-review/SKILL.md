---
name: brick-code-review
description: "Pre-livraison : cahier de recette pilote par la taxonomie de recette, recetteur separe, rapport de parite maquette/appli, matrice de permissions, gap analysis, UX, securite. Utilise /brick-code-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. La review commence par l'ecriture du
CAHIER DE RECETTE, puis la suite de tests qui le fait passer, puis les checks
complementaires. Le cochage final est fait par un recetteur qui n'a pas ecrit le code.

## Quand utiliser

- Avant de livrer une brick au client
- Avant de passer a la brick suivante
- Quand l'utilisateur demande un check global

## Scope check

Avant la review, verifier qu'on n'a pas implemente de features hors spec :
- [ ] Tout le code implemente correspond a un critere d'acceptance
- [ ] Chaque AC sert le QUOI de `doc/memory/objectif.md` (l'objectif signe)
- [ ] Pas de features "bonus" non demandees
- [ ] Les changements de scope sont documentes dans le journal de scope

## Regle d'organisation : recetteur ≠ implementeur

**Les AC et les criteres 🖐 sont coches par un SOUS-AGENT DE VERIFICATION qui n'a
pas ecrit le code.** (Audit 08/2026 : Gespilot 61/61 AC auto-coches dont un inatteignable.)

- L'implementeur (ou l'orchestrateur) PREPARE : recette, tests, captures.
- Le recetteur COCHE, brief pour refuter : "prouve que ca marche DEPUIS L'INTERFACE".
- Preuve exigee pour chaque AC coche : screenshot ou trace playwright montrant que
  l'AC est atteignable depuis l'interface (pas la console Rails, pas un test seul).
  Un AC atteignable seulement en console = NON atteint.
- Le recetteur travaille sur l'app lancee, avec les personas du jeu de donnees
  canonique. Il rend son propre tableau ; ses "NON PROUVE" bloquent.

## Process

### 1. Cahier de recette (AVANT les tests)

**Fichier standardise : `doc/memory/brick-{N}/recette.md`** (un par brick ;
mettre a jour l'existant si la brick evolue, ne jamais en creer un deuxieme).

Le cahier de recette liste TOUT ce qui doit etre vrai pour livrer, en criteres
courts, testables, traces. C'est lui qui pilote la suite de tests, pas l'inverse.
L'ecrire AVANT d'ecrire ou completer les tests.

#### Format

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
La recette est passee quand : tous les ✅ sont verts, tous les 🖐 coches PAR LE
RECETTEUR avec preuve, aucune ligne sans statut.
```

Regles de redaction (issues des standards UAT) :
- **Un critere = un objectif verifiable**, formule en langage metier
  ("le client voit ses factures triees"), pas en termes techniques.
- **Chaque critere d'acceptance (doc/memory/acceptance_criteria.md) doit
  apparaitre** dans au moins un critere de recette (tracabilite AC ↔ recette ↔ test).
- **Chaque critere happy path appelle son negatif** : si "peut creer X",
  alors "ne peut pas creer X invalide / sans droit".
- IDs stables `R{N}-section.item` : on ne renumerote jamais, on ajoute.

#### Taxonomie de recette : la derouler INTEGRALEMENT

La taxonomie de reference est `~/.claude/skills/taxonomie-recette/SKILL.md`
(versionnee dans le repo skills). Pour CHAQUE classe T1-T15 : appliquer sa
**methode de verification** et creer les criteres de recette correspondants
(colonne "Classe taxo"). Une classe sans critere = ligne "non applicable"
JUSTIFIEE dans la recette, jamais un silence.

La recette exerce aussi **TOUS les cas etiquetes du jeu de donnees canonique**
(`doc/memory/jeu_de_donnees.md`, regle de propagation) : chaque cas apparait dans
au moins un critere.

**EXCEPTION mockups** : les vues sous `/mockups` sont volontairement accessibles
sans authentification en dev/staging. Choix assume (reference visuelle statique) :
ne PAS le signaler comme faille ; verifier en revanche qu'elles ne sont pas
exposees en PROD (classe T11).

### 2. Suite de tests : faire passer la recette

Ecrire ou completer les tests pour que CHAQUE critere ✅ ait son test, puis iterer
jusqu'au vert :

```bash
rails test 2>&1 | tail -20
rails test:system 2>&1 | tail -20
```

- [ ] Chaque critere ✅ de la recette pointe vers un test qui existe
- [ ] Chaque test cite son ID de recette en commentaire (`# R{N}-1.2`)
- [ ] Chaque parcours de `user_journeys.md` a son SYSTEM test navigateur vert
- [ ] Suite verte a J, **J+3 et J+90** (shim d'horloge / `travel_to` global — classe T7 ;
      audit 08/2026 : fixtures de dates qui explosent a J+3)
- [ ] Tous les tests passent, aucun skip sans raison
- [ ] Si un test revele un bug → le corriger fait partie de la review
      (le test reste comme regression)

Ne JAMAIS affaiblir un critere pour faire passer un test : si le comportement reel
est different du critere, c'est soit un bug (fix), soit un changement de scope
(documenter dans les specs, puis ajuster la recette).

### 3. Gap Analysis (built vs specified)

Comparer `doc/memory/acceptance_criteria.md` avec la recette et le code :

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

La comparaison complementaire se fait par SCREENSHOTS, jamais de memoire ni en lisant le code.
**Reference = le tag `mockups-valides-brique-{N}`** (si `/mockups` a bouge depuis,
capturer les maquettes depuis le tag), pas l'etat courant du repo.

Protocole (playwright-cli, serveur dev lance, DB seedee avec le jeu canonique) :

1. **Meme jeu de donnees des deux cotes** : les maquettes et l'appli affichent les
   valeurs de `jeu_de_donnees.md` — toute comparaison a donnees differentes est nulle.
2. Pour chaque page implementee, capturer les paires dans les memes conditions,
   aux DEUX viewports : **1440x900 ET 390x844** :
   ```
   playwright-cli -s=parite goto <url>/mockups/users && resize + screenshot → parite/users-mockup-1440.png / -390.png
   playwright-cli -s=parite goto <url>/admin/users   && resize + screenshot → parite/users-impl-1440.png / -390.png
   ```
3. Ouvrir chaque paire (Read) et comparer section par section : structure, ordre,
   espacements, couleurs, typographie, etats visibles (dont empty states, badges,
   troncatures du jeu canonique).
4. Sur un ecart douteux, trancher au DOM (markup mockup vs reel) : la seule
   difference autorisee est la liaison de donnees.
5. Si la brique est grosse : 1 sous-agent juge par paire de pages, puis verifier
   ses "A CORRIGER".
6. **Generer le rapport HTML cote a cote** : `doc/memory/brick-{N}/parite/index.html`
   — chaque ligne = paire d'images (mockup | impl), viewport, statut
   (CONFORME / ECART JUSTIFIE : {raison ecrite} / A CORRIGER). Le rapport propre
   sert de PREUVE DE LIVRAISON au client.

Mobile selon la decision d'analyse (`decisions_comportement.md`) :
- Responsive **dans le scope** → a 390 px : aucun `scrollWidth` > 390 sur les ecrans
  cles (`playwright-cli eval "document.documentElement.scrollWidth"`), formulaires
  utilisables. Deborde = A CORRIGER (audit 08/2026 : ecran contacts a 1264 px).
- **"Hors scope assume (ecrit)"** → verifier que c'est bien ecrit ; capturer quand
  meme les 390 pour trace, sans bloquer.

Verifier :
- [ ] Chaque page a sa paire aux deux viewports dans le rapport
- [ ] Markup HTML / classes Tailwind identiques au mockup (seule la liaison change)
- [ ] Aucune section ajoutee / retiree / reordonnee
- [ ] Aucun faux objet (hash / OpenStruct) restant dans un controleur reel
- [ ] Tout ecart est CONFORME, JUSTIFIE PAR ECRIT, ou corrige

**Toute ligne A CORRIGER non justifiee bloque la livraison** (verdict NEEDS FIXES).

### 5. Matrice de permissions : URL directe ET blocs d'affichage

Pour CHAQUE role (les personas du jeu canonique, y compris ceux a droits
restreints) x CHAQUE donnee/action sensible, DEUX verifications distinctes :

1. **URL directe** : tenter le GET et le verbe d'ecriture (PATCH/POST/DELETE) sur
   chaque ressource interdite — IDOR (id devine), cross-tenant (avec le second
   tenant du jeu de donnees), etat interdit (ex : editer un devis facture).
   Attendu : refus propre, donnee inchangee.
2. **Blocs d'affichage** : se connecter AVEC le role restreint et OUVRIR chaque
   page qui affiche la donnee sensible (fiche, liste, dashboard, export, PDF,
   mail) ; verifier VISUELLEMENT qu'elle n'y est pas. Le controle d'acces pense
   pour le menu ne protege pas la fiche (audit 08/2026 : commercial billing:none
   lisait le CA sur la fiche client).

Livrer la matrice dans recette.md : lignes = donnees/actions sensibles, colonnes =
roles, chaque cellule = OK/FUITE avec la preuve (statut HTTP ou capture).

### 6. Review UX

Verifier les parcours utilisateurs de `doc/memory/user_journeys.md` :
- [ ] Chaque parcours est fonctionnel de bout en bout (system test + navigation reelle)
- [ ] Les etats d'erreur sont geres (formulaire invalide, 404, etc.)
- [ ] Les messages flash sont presents et clairs
- [ ] La navigation est coherente

### 7. Review Code (vanilla Rails)

- [ ] Controllers < 7 actions (sinon extraire)
- [ ] Pas de logique business dans les controllers
- [ ] Modeles avec validations
- [ ] Pas de JS custom quand Turbo/Stimulus suffit
- [ ] Pas de N+1 queries (utiliser `includes`)
- [ ] Fichiers < 400 lignes

### 8. SEO (si pages publiques)

Derouler la "Checklist review" de `/brick-seo` :
- [ ] Chaque page publique : title unique 50-60c, meta description unique, canonical
- [ ] curl staging → X-Robots-Tag: noindex present ; curl prod → ABSENT
- [ ] robots.txt prod : pas de Disallow: /, ligne Sitemap, bots IA non bloques
- [ ] sitemap.xml.gz accessible en prod, soumis GSC + Bing
- [ ] JSON-LD valide (validator.schema.org) sur home + 1 page de chaque gabarit
- [ ] NAP identique au caractere pres JSON-LD / footer
- [ ] 404 reel sur URL bidon ; test d'integration d'unicite des <title>
- [ ] Image heros : pas de lazy, fetchpriority=high ; toutes images width/height
- [ ] Coherence nombres/dates ; aucun placeholder visible ; aucun jargon interne

### 8bis. Performance (pages publiques) : les prerequis CWV se verifient au HTML

Sur le staging, pour la home + 1 page de chaque gabarit public :
- [ ] Poids : CSS < 20 Ko gz, page HTML < 150 Ko, aucune image > 300 Ko
      (`curl -so /dev/null -w '%{size_download}'`, assets via `playwright-cli requests`)
- [ ] Image heros : `fetchpriority="high"`, PAS de `loading="lazy"` ; toutes les images
      avec width/height ou aspect-ratio (sinon CLS)
- [ ] Polices : woff2 self-hosted + `preload`, pas de requetes Google Fonts en prod
- [ ] TTFB staging < 800 ms (`curl -so /dev/null -w '%{time_starttransfer}'`) ;
      si au-dessus, verifier fresh_when / fragment caching
- [ ] DOM < 1500 noeuds (`playwright-cli eval "document.querySelectorAll('*').length"`)
- [ ] Aucune image uploadee par le client servie brute : variants ActiveStorage partout

### 9. Repetition : repasser les points de friction

On ne relit pas toute la brick avec la meme attention. Les bugs sont concentres la
ou le dev a coince, pas dans le CRUD sorti tout seul. Reconstituer la liste des
points de friction a partir des taches (`doc/memory/brick-{N}/tasks/`), des commits
et de l'historique de la conversation :

- endroits ou un test a echoue plusieurs fois avant de passer
- code reecrit, deplace ou renomme en cours de route
- decisions prises sous contrainte de temps, ou notees "a verifier plus tard"
- TODO / FIXME / commentaires d'excuse laisses dans le code
- fichiers les plus remanies : `git diff --stat {base}..HEAD | sort -k3 -n | tail -10`
- endroits ou il a fallu demander de l'aide a l'utilisateur

Pour chacun, relire le code a froid : est-ce la solution qu'on choisirait
maintenant, en sachant ce qu'on sait a la fin de la brick ? Ce qui reste douteux
devient une ligne du rapport (section Issues), pas un souvenir.

### 10. Security check

(Les cas de securite de la taxonomie sont deja dans la recette avec leurs tests ;
ici on verifie le socle.)
- [ ] Strong parameters sur tous les controllers
- [ ] Autorisation verifiee (l'utilisateur a acces a la ressource)
- [ ] Pas de donnees sensibles dans les logs
- [ ] CSRF protection active
- [ ] Auth = Devise (aucune auth maison introduite pendant la brick)

### 11. Rapport

Generer un rapport dans `doc/memory/brick-{N}/review.md` :

```markdown
# Review Brick #X - [Date]

## Recette: X/Y criteres passes (✅ automatises: A, 🖐 manuels: M)
## Recetteur: sous-agent distinct OUI/NON — AC coches avec preuve: X/Y
## Taxonomie: X/15 classes deroulees (N/A justifies: ...)
## Tests: X/Y passing (verts a J, J+3, J+90)
## Acceptance criteria: X/Y couverts par la recette
## Parite: X/Y paires conformes (1440 + 390) — rapport: parite/index.html
## Permissions: matrice X roles x Y donnees, fuites: [liste]
## Points de friction repasses: X (dont Y encore douteux)
## Gaps: [liste]
## Issues: [liste]
## Bugs trouves par la recette: [liste — c'est un bon signe, pas un mauvais]
## Verdict: READY / NEEDS FIXES
```

## Sortie

Si READY → informer l'utilisateur, pret a livrer. Le cahier de recette et le
rapport de parite sont des LIVRABLES : partageables au client comme preuve de
couverture et de conformite.
Si NEEDS FIXES → lister les fixes. Pour chaque fix, utiliser `/brick-code-fix`
(test qui reproduit → fix → meme bug ailleurs → re-check navigateur → taxonomie),
puis re-derouler la recette.

## Ensuite

→ `brick-code-video` (filmer la livraison), + `brick-code-guide` / `brick-code-walkthrough`.
