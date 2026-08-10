---
name: brick-mockup-reanalyse
description: "Controle BLOQUANT apres la validation client des maquettes, avant le code : mobile mesure a 390 px, matrice AC-maquette, data model champ par champ (affiche ET saisi), matrice CRUD, chasse aux donnees fabriquees, parcours navigues au playwright, jeu de donnees canonique, conformite SEO des pages publiques, squelette du cahier de recette, kanban et matrice AC-tache, tag git de reference, verdict PRET / A CORRIGER. Utilise /brick-mockup-reanalyse quand le client a valide les maquettes, avant /brick-code-build."
---

# Brick Mockup Reanalyse

Derniere ligne de defense avant le code. Les maquettes validees par le client et
l'analyse doivent dire EXACTEMENT la meme chose, chaque promesse visuelle doit avoir
sa mecanique (saisie, route, decision ecrite), et le plan de travail doit couvrir tous
les AC. On n'ouvre pas le code sur un verdict A CORRIGER.

**Modele** : porte bloquante = modele fort (Opus). Ni la reanalyse ni le cahier de
recette derive ici ne se delegue a un modele economique.

## Quand utiliser

- Les maquettes de la brique sont validees par le client (fin de la boucle MOCKUP)
- JAMAIS pendant la boucle mockup : c'est une etape de sortie, pas une review intermediaire

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
il est decouvert apres. Pour CHAQUE maquette de la brique, sans echantillonnage :

```bash
playwright-cli -s=mob goto <url>/mockups/<page>
playwright-cli -s=mob resize 390 844
playwright-cli -s=mob eval "document.documentElement.scrollWidth"
```

- Attendu : **`scrollWidth == 390` exactement** sur le document. Toute valeur superieure
  est un debordement, donc un defaut de la maquette : on la CORRIGE (coupables habituels :
  groupe d'actions de topbar en `shrink-0`, tableau sans conteneur `overflow-x-auto`,
  largeur fixe en px), on re-mesure, et on ne pose pas le tag avant que tout soit a 390.

- **Le document seul ne suffit pas : mesurer aussi les conteneurs NON defilants.** Un
  bloc en `overflow-y-auto` fait calculer au navigateur un `overflow-x: auto` implicite :
  il avale le debordement, le document reste sagement a 390 et le tableau se coupe en
  silence.
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

- Tableau tenu dans reanalyse.md : une ligne par maquette, mesure AVANT / APRES, pour les
  trois mesures (document, conteneurs, champs).
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

### 6. Jeu de donnees canonique dans les maquettes

Les maquettes affichent les valeurs EXACTES de jeu_de_donnees.md (noms, montants,
statuts). Puis :

- [ ] Quotas respectes : au moins un cas par categorie (etats difficiles, argent aux
      bornes, chaines hostiles, temps, volumes, multi-tenant), chaque cas etiquete
- [ ] Sous-ensemble representatif MONTRE : au minimum empty states, un badge
      suspendu/archive, une troncature
- Donnee inventee dans une maquette → remplacer par le canonique, OU enrichir le
  canonique si le cas est bon (mise a jour bidirectionnelle, journalisee)

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

### 11. Tag git de reference

Quand tout est corrige et coherent (mesures 390 comprises) :

```bash
git tag mockups-valides-brique-{N}
```

Ce tag est LA reference visuelle de la brique : le rapport de parite de
`brick-code-review` et les briques suivantes comparent contre lui, pas contre l'etat
courant de `/mockups`. On ne le deplace JAMAIS.

### 12. Verdict

Ecrire `doc/memory/brick-{N}/reanalyse.md` :

```markdown
# Reanalyse — Brick #{N} — {date}

## Mobile 390 px : X/X maquettes conformes (document, conteneurs non defilants, champs)
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

- [ ] **Chaque maquette mesuree a 390 px** : `scrollWidth == 390` sur le document,
      aucun conteneur non defilant en debordement, aucun champ de saisie sous 120 px
      (mesures avant/apres ecrites)
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
- [ ] Tag `mockups-valides-brique-{N}` pose ; verdict PRET ecrit

## Ensuite

→ `brick-code-build` (uniquement sur verdict PRET).
