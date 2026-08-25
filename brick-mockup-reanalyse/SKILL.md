---
name: brick-mockup-reanalyse
description: "Controle BLOQUANT apres la validation client des maquettes, avant le code : mobile mesure a 390 px, matrice AC-maquette, data model champ par champ (affiche ET saisi), matrice CRUD, chasse aux donnees fabriquees, parcours navigues au playwright, jeu de donnees canonique, conformite SEO des pages publiques, squelette du cahier de recette, kanban et matrice AC-tache, tag git de reference, verdict PRET / A CORRIGER. Utilise /brick-mockup-reanalyse quand le client a valide les maquettes, avant /brick-code-build."
---

# Brick Mockup Reanalyse

Derniere ligne de defense avant le code. Les maquettes validees par le client et
l'analyse doivent dire EXACTEMENT la meme chose, chaque promesse visuelle doit avoir
sa mecanique (saisie, route, decision ecrite), et le plan de travail doit couvrir tous
les AC. On n'ouvre pas le code sur un verdict A CORRIGER.

> **Modeles et discipline de tour** : ce skill delegue a des sous-agents. Doctrine mesuree,
> commune a toute la chaine, dans `/brick-code-build` (« Repartition des modeles » et
> « Discipline de tour ») : tous les sous-agents en `model: "opus"`, et l'orchestrateur
> n'attend jamais un sous-agent en rendant son tour.

## Quand utiliser

- Les maquettes de la brique sont validees par le client (fin de la boucle MOCKUP)
- JAMAIS pendant la boucle mockup : c'est une etape de sortie, pas une review
  intermediaire. Les controles qui produisent des QUESTIONS client (affiche/saisi,
  donnees fabriquees, regles d'argent ambigues) ont leur version courte dans
  `/brick-mockup-review` (« Pre-vol reanalyse ») : les questions partent AVEC chaque
  envoi de lot, pas apres la validation. Ici on VERIFIE et on TRANCHE, on ne demande
  plus rien au client.

## Discipline : la reanalyse se deroule d'un seul tenant

Retour terrain 08/2026 : « il est top mais il s'arrete beaucoup ». Un arret entre deux
sections = une relance humaine = une demi-journee perdue. Les 12 sections s'enchainent
DANS LE MEME TOUR, y compris les boucles de correction :

- **A CORRIGER n'est pas une fin de tour.** Un ecart constate se corrige seance
  tenante (maquette ou spec, regle de l'etape 8), l'etape impactee se rejoue, et on
  continue. On ne rend pas la main pour annoncer qu'on va corriger.
- On ne s'arrete que sur deux cas : une decision qui appartient a l'humain (changement
  visible de ce que le client a valide → signalement AVANT, cf. etape 8), ou un blocage
  technique que trois tentatives documentees n'ont pas leve. « J'ai fini la section 5 »
  n'est aucun des deux : section 6.
- Les sous-agents (mesures, navigation, matrices) se lancent en parallele quand ils
  sont independants, et on attend leurs retours DANS le tour (discipline de tour de
  `/brick-code-build`).
- Le compte rendu se redige UNE fois, au verdict (PRET ou A CORRIGER final), pas a
  chaque section.

## Pre-requis

- `doc/memory/` : objectif.md, acceptance_criteria.md, data_models.md,
  user_journeys.md, jeu_de_donnees.md, decisions.md, config.md
- Les vues `/mockups` navigables (serveur de dev lance)

## La maquette n'est jamais une excuse

Quand la conformite a la maquette conduirait a livrer un defaut — debordement a 390 px,
selecteur sans option vide, garde ou controle manquant — c'est **LA MAQUETTE qui est
fausse**. On la corrige ici, on journalise la correction dans reanalyse.md, et on le
signale au client a la livraison (« la maquette debordait au telephone, on l'a corrigee »).

« Le client a valide » et « ca toucherait trois formulaires deja valides » ne sont pas
des motifs de conservation d'un defaut. La maquette est une reference de RENDU : elle
n'a autorite ni sur la justesse d'un devis, ni sur la largeur d'un ecran de telephone,
ni sur une regle de permission. (Audit qualite 08/2026 : les deux plus gros trous du
lot etaient argumentes par la maquette, et livres tous les deux.)

## Process

### 1. Mobile : chaque maquette mesuree a 390 px (PREMIER controle, BLOQUANT)

En tete parce qu'il ne coute presque rien ici et une section entiere de la qualite quand
il est decouvert apres. Pour CHAQUE maquette de la brique, sans echantillonnage.

**Ne conclus JAMAIS « conforme » sur le seul `document.documentElement.scrollWidth`.**
Cette valeur ne prouve rien a elle seule : des que `body` (ou un conteneur du gabarit)
porte `overflow-x: clip` ou `hidden`, le debordement est CLIPPE au lieu d'etre defilable,
et le chiffre rend la largeur du viewport quoi qu'il arrive. Mesure 08/2026 : une
messagerie dont le bouton « Envoyer » etait hors ecran, et 20 maquettes dont plusieurs
debordaient franchement, passaient toutes au vert sur cette seule mesure.

Le chemin le plus court est l'outil, qui fait les trois mesures et rend ses resultats
CLASSES par cause. On lance l'outil et on lit ses categories, on ne compare pas deux
nombres a la main :

```bash
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json --viewport mobile \
  --out doc/memory/brick-{N}/parite/
```

`clip-implicite` et `clip-declare` = du contenu coupe que rien ne permet d'atteindre,
A CORRIGER avant le tag ; `scroll-voulu` = defilement horizontal declare, information ;
plus les controles de saisie ecrases. A la main, sur une maquette isolee (pas encore de
paires applicatives), TROIS sondes, jamais une :

```bash
playwright-cli -s=mob goto <url>/mockups/<page>
playwright-cli -s=mob resize 390 844
```

- **Le bord droit REEL : l'element le plus a droite de la page.** On exclut ce qui vit
  dans un conteneur a defilement horizontal DECLARE (`overflow-x: auto|scroll` voulu), ce
  qui est en `position: fixed`, et ce qui est en cours d'animation (une largeur mesuree
  pendant une animation ne veut rien dire).
  ```bash
  playwright-cli -s=mob eval "(()=>{const ok=e=>{const s0=getComputedStyle(e);if(s0.position==='fixed'||s0.animationName!=='none')return false;for(let p=e.parentElement;p&&p!==document.body;p=p.parentElement){const s=getComputedStyle(p);if(['auto','scroll'].includes(s.overflowX)||s.position==='fixed'||s.animationName!=='none')return false}return true};let m=null;for(const e of document.querySelectorAll('body *')){const r=e.getBoundingClientRect();if(r.width<=0||!ok(e))continue;if(!m||r.right>m.right)m={right:r.right,lbl:e.tagName+'.'+(e.className||'')}}return m?Math.round(m.right)+' '+m.lbl:'rien'})()"
  ```
  Attendu : **bord droit <= 390**. Au-dela c'est un debordement reel, meme si le document
  mesure 390 : defaut de la maquette, on la CORRIGE (coupables habituels : groupe
  d'actions de topbar en `shrink-0`, tableau sans conteneur `overflow-x-auto`, largeur
  fixe en px), on re-mesure, et on ne pose pas le tag avant que tout soit a 390.

- **Les conteneurs NON defilants.** Un bloc en `overflow-y-auto` fait calculer au
  navigateur un `overflow-x: auto` implicite : il avale le debordement, le document reste
  sagement a 390 et le tableau se coupe en silence.
  ```bash
  playwright-cli -s=mob eval "[...document.querySelectorAll('*')].filter(e => e.scrollWidth > e.clientWidth + 1 && !['auto','scroll'].includes(getComputedStyle(e).overflowX)).map(e => e.tagName + '.' + (e.className || '') + ' ' + e.scrollWidth + '/' + e.clientWidth)"
  ```
  Toute ligne rendue est un debordement reel : le contenu est coupe et rien ne permet de
  le faire defiler. A CORRIGER, meme si le document mesure 390. (Audit qualite 08/2026 :
  41 pages coupaient leurs tableaux derriere un `scrollWidth` de document au vert.)

- **Largeur reelle des champs de saisie.** Un champ peut tenir dans 390 px en etant
  inutilisable :
  ```bash
  playwright-cli -s=mob eval "[...document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]), select, textarea')].map(e => (e.name || e.id || e.type) + ' ' + Math.round(e.getBoundingClientRect().width)).filter(l => +l.split(' ').pop() < 120)"
  ```
  Tout champ sous 120 px de large est A CORRIGER. (Audit qualite 08/2026 : des `input`
  a 18 px sur un ecran declare conforme.)

- **Le verrou, mecanique, avant le verdict PRET.** Les trois mesures a la main sont le
  diagnostic ; le verdict, lui, passe par l'outil, parce que la regle en gras ci-dessus a
  ete lue et quand meme contournee deux fois sur trois au banc du 16-17/08/2026 (champs
  de prix a 18 px derriere un document a 390) :
  ```bash
  # une URL de maquette par ligne (toutes celles du lot, hub /mockups exclu)
  ruby ~/.claude/skills/outils-recette/mobile_gate.rb --urls doc/memory/brick-{N}/mockup-urls.txt
  ```
  Mode direct : il ouvre chaque ecran a 390 px dans sa propre session playwright-cli et
  applique les trois mesures ci-dessus (bord droit reel hors conteneur defilant,
  conteneurs de layout qui coupent, champs de saisie sous 24 px), puis rend un verdict
  binaire. exit 1 ou 2 = pas de PRET, pas de tag. Sa derniere ligne se colle telle quelle
  dans reanalyse.md. Il exclut a raison ce qui defile par choix (`overflow-x: auto`) et
  le texte tronque en ellipse : ce qu'il refuse est un vrai defaut. Voir `/outils-recette`.
- Tableau tenu dans reanalyse.md : une ligne par maquette, mesure AVANT / APRES, pour les
  trois mesures (bord droit reel, conteneurs, champs).
- Si `decisions.md` dit « responsive hors scope assume (ecrit) », les mesures sont faites
  et ecrites quand meme : on livre en connaissance de cause, jamais par omission.

Provenance : audit qualite 08/2026 — ecran contacts a 1264 px de large ; 17 des 22 ecrans
d'une brique debordant, maquettes comprises (la conformite avait ete tenue jusque dans le
defaut).

### 2. Matrice AC ↔ maquette

Pour CHAQUE AC de acceptance_criteria.md, nommer la ou les maquettes qui le rendent
atteignable, et ou exactement (ecran, bouton, champ) :

| AC | Maquette(s) | Ou (element concret) | Statut |
|----|-------------|----------------------|--------|
| AC1.1 | mockups/users/new | formulaire, bouton "Inviter" | OK |
| AC2.3 | — | aucune | A CORRIGER |

- AC sans maquette → soit la maquette manque (la creer, re-valider aupres du client
  si visible), soit l'AC est hors brique (journal de scope).
- Maquette sans AC → feature orpheline : rattacher ou retirer (regle du rattachement
  de l'analyse).
- **La matrice se satisfait d'un ecran de la bonne FAMILLE si on la laisse faire.** Elle
  doit nommer l'ecran ET l'element concret ; une route de detail specifiee dans
  `routes.md` sans maquette de detail est un manque, pas un OK sur l'index. (Mesure
  08/2026 : `routes.md` specifiait `GET /admin/ai_decisions/:id` avec son contenu ligne a
  ligne, aucune maquette ne le dessinait, l'AC etait classe OK sur la page d'index.)

### 3. Data model champ par champ : affiche ET saisi (anti-facade)

Pour CHAQUE champ de CHAQUE modele de data_models.md :

| Modele.champ | Affiche dans | Saisi dans | Decision |
|--------------|--------------|------------|----------|
| Client.postal_code | factures, PDF | mockups/clients/_form | OK |
| Client.score | fiche client | AUCUN ecran | calcule par {X} / A CORRIGER |

Regles :
- **Toute donnee affichee doit avoir un ecran de saisie**, sinon une decision ECRITE
  qui dit d'ou elle vient ("calcule par...", "importe par...", "seede par...").
  Pas de decision = A CORRIGER. (Audit qualite 08/2026 : postal_code imprime sur les
  factures et le PDF, absent du formulaire et du permit.)
- L'inverse aussi : champ saisi jamais affiche = A CORRIGER (audit qualite 08/2026 :
  `client[notes]` enregistre, rendu sur aucune page de lecture).
- **Cles et credentials** : tout ecran de configuration (cle API, parametres d'envoi)
  doit nommer le code qui LIRA la valeur saisie, et la cle doit figurer dans
  `doc/memory/config.md`. Ecran de saisie sans consommateur nomme = facade.
  (Audit qualite 08/2026 : cle Postmark soigneusement stockee, jamais lue a l'envoi.)
- **Selecteurs** : tout `select` sur une donnee qui porte de l'argent ou un droit
  (client d'un devis, taux, role) montre une **option vide en premiere position**, sans
  presselection. Un premier element selectionne par defaut fabrique un rattachement
  silencieux. (Audit qualite 08/2026 : devis emis pour le premier client de la liste,
  avec la remise d'un autre.)
- Les controles interactifs promis par une maquette (select qui rafraichit, recherche,
  filtre) sont listes avec leur mecanique prevue (Turbo/Stimulus + route). Promesse
  sans mecanique = A CORRIGER. (Audit qualite 08/2026 : select client sans `data-action`.)

### 4. Chasse aux DONNEES FABRIQUEES dans les maquettes

Une maquette a le droit d'afficher des donnees FICTIVES (celles du jeu canonique) ;
elle n'a pas le droit de promettre une donnee que rien ne pourra produire. Pour chaque
chiffre, compteur, score, graphique, badge de tendance et vignette visible :

| Element visible | Source reelle prevue | Verdict |
|-----------------|----------------------|---------|
| "127 connexions ce mois" | aucune (pas d'evenement trace) | A CORRIGER → etat vide honnete |
| "Perfect Match 92 %" | Matching::Score#call (a coder) | OK |

Source introuvable → deux issues seulement : (a) on cree la source (une decision de plus
dans `decisions.md`), (b) la maquette montre un **etat vide honnete**. Jamais un chiffre
en dur qui survivra dans le code. (Tastellers : "127 connexions" affichees au vrai client,
moteur de matching melangeant scores reels et fake.)

### 5. Parcours NAVIGUES au playwright (jamais relus)

Pour CHAQUE parcours de user_journeys.md : le DEROULER dans les maquettes avec
`playwright-cli`, etape par etape, en cliquant reellement. Screenshot a chaque etape.

- Un lien mort, un bouton sans cible, une etape sans ecran = A CORRIGER.
- Lire le code des maquettes NE remplace PAS la navigation (constat d'audit :
  "parcours verifies en lisant" = bugs invisibles).
- Captures conservees dans `doc/memory/brick-{N}/reanalyse-shots/` (trace du verdict).
- **Verifier que l'ecran d'ARRIVEE est celui du parcours, pas seulement qu'il repond.**
  Un formulaire d'ecriture passe pour un ecran de lecture : il repond 200, il a des liens
  entrants, il passe tous les controles mecaniques. (Mesure 08/2026 : un parcours cochait
  OK sur « clic sur le nom de l'affaire -> /mockups/opportunities/1/edit, l'etape est
  changeable au formulaire » ; trois utilisateurs sur trois ont bute dessus, dont un qui a
  ecrase la note d'une collegue.)

### 6. Jeu de donnees canonique dans les maquettes

Les maquettes affichent les valeurs EXACTES de jeu_de_donnees.md (noms, montants,
statuts). Puis :

- [ ] Quotas respectes : au moins un cas par categorie (etats difficiles, argent aux
      bornes, chaines hostiles, temps, volumes, multi-tenant), chaque cas etiquete
- [ ] Sous-ensemble representatif MONTRE : au minimum empty states, un badge
      suspendu/archive, une troncature
- Donnee inventee dans une maquette → remplacer par le canonique, OU enrichir le
  canonique si le cas est bon (mise a jour bidirectionnelle, journalisee)
- **Le jeu porte-t-il un exemplaire « ne du produit » par entite d'argent ou de droit ?**
  (regle de fabrication de `/brick-analysis-build`) : pour chaque facture, avoir,
  reglement, invitation… le cahier de recette derive ici (section 8) doit contenir un
  critere « creer par l'interface, puis comparer les agregats avant/apres ». Si le jeu ne
  le prevoit pas, l'ajouter au jeu ET au cahier maintenant : c'est le critere qui attrape
  une donnee de seed dans un etat que l'application ne produit jamais (banc 16-17/08 :
  avoir de seed `sent`, avoirs de l'app `draft`, CA faux et recette verte).

### 6b. Pages publiques : conformite SEO des maquettes

Si la brique a des pages publiques, derouler la section "Phase mockup" de `/brick-seo` sur
chacune : head complet (title, meta description, canonical, OG/Twitter), un seul H1 et une
hierarchie de titres coherente, blocs de contenu citable (FAQ, donnees factuelles) presents,
NAP coherent partout. La requete cible de l'analyse doit se retrouver dans la page. Un ecart
se corrige ici, pas au moment du code : le markup des maquettes est repris tel quel.

### 7. Decisions et matrice CRUD a la lumiere des maquettes

**La matrice CRUD se confronte dans les DEUX sens** : chaque case « offert » a son geste
visible dans une maquette nommee (sinon la maquette manque, ou la case devient « non
offert ») ; chaque bouton creer / modifier / supprimer / archiver visible dans une
maquette a sa case (sinon la matrice est incomplete, ou le bouton est de trop). Les deux
cas sont A CORRIGER. (Audit qualite 08/2026 : neuf `destroy` cote serveur sans le moindre
bouton.)

Puis relire `decisions.md` ligne a ligne, maquette en main : etat degrade decide pour
chaque badge (suspendu, archive) ; coherence avec la decision responsive ; et tout defaut
impose par une maquette sans etre decide (delai, tri, seuil, libelle) **se tranche ici**,
une ligne de plus dans le journal courant. On ne renvoie pas la question au client.
Reponses autorisees : "gere", "hors scope assume (ecrit)", "non applicable". Case vide
ou contradiction maquette/decision = A CORRIGER.

### 8. Mise a jour bidirectionnelle

Chaque ecart se corrige d'UN cote (maquette OU analyse), jamais des deux en silence :
- Corriger, journaliser dans reanalyse.md (quoi, quel cote, pourquoi)
- Si la correction change ce que le client a valide visuellement → le signaler a
  l'utilisateur AVANT, et le reprendre dans la note de livraison
- Re-jouer l'etape impactee apres correction (mesures 390, matrice, navigation)

### 9. Squelette du cahier de recette (BLOQUANT, avant la premiere ligne de code)

Le cahier ne s'ecrit pas a la review : il s'ecrit ICI, DERIVE mecaniquement, et le
recetteur executera plus tard un cahier qu'il n'a pas ecrit. Fichier
`doc/memory/brick-{N}/recette.md`, IDs stables `R{N}-section.item`, trois sources :

1. **Un critere par AC et par role concerne** (le meme AC vu par un admin et par un
   commercial restreint = deux criteres).
2. **Un critere par cas etiquete du jeu canonique** (argent aux bornes, chaine hostile,
   contact archive avec affaire liee, liste vide, second tenant...).
3. **Un critere par ligne de `decisions.md`**, matrice CRUD comprise : chaque case
   « offert » donne un critere qui joue le geste DEPUIS l'INTERFACE, chaque case « non
   offert » un critere qui prouve l'absence (ni bouton, ni route, ni action).

**Format de preuve rejouable — un critere n'est pas une phrase** :

| ID | Critere | AC / decision | URL | Compte | Geste | Observation attendue | Statut |
|----|---------|---------------|-----|--------|-------|----------------------|--------|
| R1-2.4 | Un admin supprime un taux de TVA inutilise | CRUD TaxRate | /app/settings/taxes | claire@exemple.fr | clic « Supprimer » sur la ligne 5,5 % | ligne disparue, flash « Taux supprime », 7 taux restants | a remplir |
| R1-2.5 | Un contact ne se supprime pas | CRUD Client (non offert) | /app/clients/1 | claire@exemple.fr | chercher un bouton Supprimer | aucun bouton ; DELETE direct → refus, contact intact | a remplir |

Sans URL + compte + geste + observation, ce n'est pas un critere mais un souhait.
(Audit qualite 08/2026 : AC8.1 coche sur la phrase « suppression proposee sur la page
d'edition », page qui n'offre que Annuler et Enregistrer.)
Le squelette sort d'ici complet et SANS aucun statut : rempli pendant le build, execute
a la review, **commite avant le tag** donc couvert par lui.

### 10. Kanban de la brique et matrice AC ↔ tache (BLOQUANT)

Le plan de travail se decide ici, pas au fil de l'eau. Creer
`doc/memory/brick-{N}/tasks/{NNN}-{titre}-todo.md`, en **lots de 4-5 taches** (le numero
de lot est ecrit dans le fichier). Chaque tache, des sa creation :

```markdown
# Tache 003 — Formulaire client (lot 1)

## Criteres couverts
- R1/AC1.1 : un admin cree un client depuis l'UI ; R1/AC1.4 : code postal sur la facture
- Criteres de recette juges sur cette tache : R1-1.1, R1-1.2, R1-2.4
  (le sous-agent sait AVANT de commencer par quoi il sera juge)

## Perimetre prevu (3 lignes max, chemins/globs)
- app/models/client.rb, app/controllers/clients_controller.rb, app/views/clients/**
- test/integration/clients_test.rb, test/system/parcours_client_test.rb

## Preuve a produire (DoD — a executer, pas a declarer ; format rejouable)
- `bin/rails test test/integration/clients_test.rb` → 0 failure
- URL : {url}/app/clients/new — compte : claire@exemple.fr / {mdp du jeu canonique}
- Geste : remplir les 6 champs, cliquer « Enregistrer »
- On doit voir : flash « Client cree », le code postal sur la fiche, puis imprime sur
  la facture generee ensuite
```

Puis la **matrice AC ↔ tache** dans reanalyse.md (`AC1.1 → 003` et `003 → AC1.1, AC1.4`).
Regles bloquantes : tout AC a au moins une tache (AC orphelin = le plan est faux) ;
toute tache sert au moins un AC (tache orpheline = a supprimer, ou elle revele un AC
manquant a tracer) ; une tache dont on ne sait pas ecrire la preuve n'est pas prete, on
la decoupe jusqu'a ce qu'on sache.

Provenance : audit qualite 08/2026 — aucune matrice de tracabilite complete AC ↔
maquette ↔ tache ↔ test, brique entiere codee en un jour sans plan verifiable.

#### Le perimetre de la brique ne se rediscute pas ici

La brique est vendue et son perimetre est arrete. La reanalyse verifie que les maquettes
et le plan couvrent ce perimetre : elle ne le redimensionne pas. Ne propose ni decoupage
en deux briques, ni livraison partielle, ni report de lots au motif que le compte de
taches te parait eleve. Ce n'est pas la decision de cette etape.

Ce que tu fais quand le plan te parait lourd : rien de plus que le reste de la reanalyse.
Tu comptes les AC et les taches parce que la matrice AC ↔ tache l'exige, tu verifies que
chaque AC a sa tache et chaque tache sa preuve, et tu rends PRET ou A CORRIGER sur la
completude et la coherence du plan, jamais sur son volume.

### 11. Tag git de reference

Quand tout est corrige et coherent (mesures 390 comprises) :

```bash
git tag mockups-valides-brique-{N}
```

Ce tag est LA reference visuelle de la brique : le rapport de parite de
`brick-code-review` et les briques suivantes comparent contre lui, pas contre l'etat
courant de `/mockups`. On ne le deplace JAMAIS.

### 11b. Sortie de la review mockup : ce qui doit etre ferme (BLOQUANT)

- [ ] Inventaire des liens entrants REJOUE apres les corrections de la boucle mockup :
      aucun candidat orphelin non tranche (une correction de maquette cree des orphelins)
- [ ] Chaque defaut de navigabilite et chaque trou de perimetre de la review est FERME,
      ou porte une decision ecrite dans decisions.md. Un trou de perimetre encore ouvert
      = A CORRIGER : l'ecran manquant sera invente pendant le code.

### 12. Verdict

Ecrire `doc/memory/brick-{N}/reanalyse.md` :

```markdown
# Reanalyse — Brick #{N} — {date}

## Mobile 390 px : X/X maquettes conformes (bord droit reel, conteneurs non defilants, champs)
## Matrice AC ↔ maquette : X/Y AC couverts
## Data model : X champs, Y decisions ecrites, Z corrections (dont selecteurs a option vide)
## Matrice CRUD ↔ maquettes : X cases « offert », toutes avec leur geste OUI/NON
## Donnees fabriquees : X verifiees, Y sources creees, Z passees en etat vide
## Parcours navigues : X/Y OK — Jeu de donnees : quotas OK/KO
## Pages publiques : SEO maquette OK/KO (ou : aucune page publique)
## Cahier de recette : X criteres derives (AC x role : A, jeu canonique : B, decisions : C)
## Kanban : X taches en Y lots — matrice AC ↔ tache complete OUI/NON
## Corrections de maquette a signaler au client : [liste]
## Tag : mockups-valides-brique-{N} pose sur {sha}

## Verdict : PRET / A CORRIGER
```

**A CORRIGER = on n'ouvre pas le code.** Corriger, re-jouer les etapes impactees,
re-rendre le verdict. PRET est la seule porte d'entree de `brick-code-build`.

## Validation gate

- [ ] **Chaque maquette mesuree a 390 px** : bord droit de l'element le plus a droite
      <= 390, aucun conteneur non defilant en debordement, aucun champ de saisie sous
      120 px (mesures avant/apres ecrites ; jamais un verdict sur le seul `scrollWidth`
      du document)
- [ ] Chaque AC a sa maquette nommee (ou sa sortie de scope journalisee)
- [ ] Chaque champ du data model a sa ligne affiche/saisi/decision, aucune vide
- [ ] Chaque selecteur portant argent ou droit a une option vide, sans presselection
- [ ] Matrice CRUD confrontee aux maquettes dans les DEUX sens (case offert ↔ geste)
- [ ] Cahier de recette derive au format URL / compte / geste / observation, commite
      avant le tag
- [ ] Chaque chiffre/compteur/score visible a une source reelle prevue, ou un etat vide
- [ ] Chaque parcours navigue au playwright, captures a l'appui
- [ ] Pages publiques : head, H1, contenu citable et NAP conformes a `/brick-seo`
- [ ] `decisions.md` complet et coherent avec les maquettes, defauts tranches
- [ ] Kanban ecrit, matrice AC ↔ tache complete dans les deux sens
- [ ] Aucune proposition de redimensionnement de la brique (decoupage, livraison
      partielle, report de lots) : le perimetre est arrete, la reanalyse le verifie
- [ ] Tag `mockups-valides-brique-{N}` pose ; verdict PRET ecrit

## Ensuite

→ `brick-code-build` (uniquement sur verdict PRET).
