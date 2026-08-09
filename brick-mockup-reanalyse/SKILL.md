---
name: brick-mockup-reanalyse
description: "Controle BLOQUANT apres la validation client des maquettes, avant le code : matrice AC-maquette, data model champ par champ (affiche ET saisi), chasse aux donnees fabriquees, parcours navigues au playwright, jeu de donnees canonique, conformite SEO des pages publiques, kanban et matrice AC-tache, tag git de reference, verdict PRET / A CORRIGER. Utilise /brick-mockup-reanalyse quand le client a valide les maquettes, avant /brick-code-build."
---

# Brick Mockup Reanalyse

Derniere ligne de defense avant le code. Les maquettes validees par le client et
l'analyse doivent dire EXACTEMENT la meme chose, chaque promesse visuelle doit avoir
sa mecanique (saisie, route, decision ecrite), et le plan de travail doit couvrir tous
les AC. On n'ouvre pas le code sur un verdict A CORRIGER.

## Quand utiliser

- Les maquettes de la brique sont validees par le client (fin de la boucle MOCKUP)
- JAMAIS pendant la boucle mockup : c'est une etape de sortie, pas une review intermediaire

## Pre-requis

- `doc/memory/` : objectif.md, acceptance_criteria.md, data_models.md,
  user_journeys.md, jeu_de_donnees.md, decisions.md, config.md
- Les vues `/mockups` navigables (serveur de dev lance)

## Process

### 1. Matrice AC ↔ maquette

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

### 2. Data model champ par champ : affiche ET saisi (anti-facade)

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
- L'inverse aussi : un champ saisi jamais affiche → questionner (saisie pour rien,
  ou affichage manquant).
- **Cles et credentials** : tout ecran de configuration (cle API, parametres d'envoi)
  doit nommer le code qui LIRA la valeur saisie, et la cle doit figurer dans
  `doc/memory/config.md`. Ecran de saisie sans consommateur nomme = facade.
  (Audit qualite 08/2026 : cle Postmark soigneusement stockee, jamais lue a l'envoi.)
- Les controles interactifs promis par une maquette (select qui rafraichit, recherche,
  filtre) sont listes avec leur mecanique prevue (Turbo/Stimulus + route). Promesse
  sans mecanique = A CORRIGER. (Audit qualite 08/2026 : select client sans `data-action`.)

### 3. Chasse aux DONNEES FABRIQUEES dans les maquettes

Une maquette a le droit d'afficher des donnees FICTIVES (celles du jeu canonique) ;
elle n'a pas le droit de promettre une donnee que rien ne pourra produire. Pour chaque
chiffre, compteur, score, graphique, badge de tendance et vignette visible :

| Element visible | Source reelle prevue | Verdict |
|-----------------|----------------------|---------|
| "127 connexions ce mois" | aucune (pas d'evenement trace) | A CORRIGER → etat vide honnete ou tracer l'evenement |
| "Perfect Match 92 %" | Matching::Score#call (a coder) | OK |

- Source introuvable → deux issues seulement : (a) on cree la source (une decision de
  plus dans `decisions.md`), (b) la maquette montre un **etat vide honnete**
  ("aucune donnee pour l'instant"). Jamais un chiffre en dur qui survivra dans le code.
- Provenance : Tastellers (compteurs en dur "127 connexions" affiches au vrai client,
  moteur de matching melangeant scores reels et fake).

### 4. Parcours NAVIGUES au playwright (jamais relus)

Pour CHAQUE parcours de user_journeys.md : le DEROULER dans les maquettes avec
`playwright-cli`, etape par etape, en cliquant reellement. Screenshot a chaque etape.

- Un lien mort, un bouton sans cible, une etape sans ecran = A CORRIGER.
- Lire le code des maquettes NE remplace PAS la navigation (constat d'audit :
  "parcours verifies en lisant" = bugs invisibles).
- Conserver les captures dans `doc/memory/brick-{N}/reanalyse-shots/` (trace du verdict).

### 5. Jeu de donnees canonique dans les maquettes

Verifier que les maquettes affichent les valeurs EXACTES de jeu_de_donnees.md
(noms, montants, statuts), puis les quotas et la regle de propagation :

- [ ] Quotas respectes : au moins un cas par categorie (etats difficiles, argent aux
      bornes, chaines hostiles, temps, volumes, multi-tenant), chaque cas etiquete
      avec ce qu'il exerce
- [ ] Les maquettes MONTRENT le sous-ensemble representatif : au minimum les empty
      states, un badge suspendu/archive, une troncature
- Donnee inventee dans une maquette → remplacer par le canonique, OU enrichir le
  canonique si le cas est bon (mise a jour bidirectionnelle, journalisee)

### 5b. Pages publiques : conformite SEO des maquettes

Si la brique a des pages publiques, derouler la section "Phase mockup" de `/brick-seo` sur
chacune : head complet (title, meta description, canonical, OG/Twitter), un seul H1 et une
hierarchie de titres coherente, blocs de contenu citable (FAQ, donnees factuelles) presents,
NAP coherent partout. La requete cible de l'analyse doit se retrouver dans la page. Un ecart
se corrige ici, pas au moment du code : le markup des maquettes est repris tel quel.

### 6. Decisions a la lumiere des maquettes

Relire `decisions.md` maquette en main :
- Une maquette montre un bouton Supprimer → la decision suppression de l'entite existe ?
- Un badge d'etat (suspendu, archive) apparait → l'etat degrade est decide ?
- Des ecrans mobiles sont montres → coherent avec la decision responsive ?
- Une maquette impose un defaut non decide (delai, tri, seuil, libelle metier) →
  **on tranche ici** : une ligne de plus dans le journal courant (defaut retenu, motif,
  reversible, « a signaler » si ca touche au QUOI). On ne renvoie pas la question au client.

Reponses autorisees : "gere", "hors scope assume (ecrit)", "non applicable".
Case vide ou contradiction maquette/decision = A CORRIGER.

### 7. Mise a jour bidirectionnelle

Chaque ecart se corrige d'UN cote (maquette OU analyse), jamais des deux en silence :
- Corriger, journaliser dans reanalyse.md (quoi, quel cote, pourquoi)
- Si la correction change ce que le client a valide visuellement → le signaler a
  l'utilisateur AVANT (pas de re-validation silencieuse)
- Re-jouer l'etape de verification impactee apres correction (matrice ou navigation)

### 8. Kanban de la brique et matrice AC ↔ tache (BLOQUANT)

Le plan de travail se decide ici, pas au fil de l'eau. Creer
`doc/memory/brick-{N}/tasks/{NNN}-{titre}-todo.md`, regroupes en **lots de 4-5 taches**
(le numero de lot est ecrit dans le fichier).

Chaque fichier de tache contient, des sa creation :

```markdown
# Tache 003 — Formulaire client (lot 1)

## Criteres couverts
- R1/AC1.1 : un admin cree un client depuis l'UI
- R1/AC1.4 : le code postal figure sur la facture

## Perimetre prevu (3 lignes max, chemins/globs)
- app/models/client.rb, app/controllers/clients_controller.rb
- app/views/clients/**
- test/integration/clients_test.rb, test/system/parcours_client_test.rb

## Preuve a produire (DoD — a executer, pas a declarer)
- `bin/rails test test/integration/clients_test.rb` → 0 failure
- URL : {url}/app/clients/new — compte : claire@exemple.fr / {mdp du jeu canonique}
- On doit voir : les 6 champs du formulaire dont Code postal, flash « Client cree »,
  et le code postal imprime sur la facture generee ensuite
```

Puis la **matrice AC ↔ tache**, ecrite dans reanalyse.md :

| AC | Tache(s) | | Tache | AC servis |
|----|----------|-|-------|-----------|
| AC1.1 | 003 | | 003 | AC1.1, AC1.4 |

Regles bloquantes :
- **Tout AC a au moins une tache.** AC orphelin = le plan est faux, pas le AC.
- **Toute tache sert au moins un AC.** Tache orpheline = a supprimer, ou elle revele
  un AC manquant (l'ajouter et le tracer dans le journal de scope).
- Une tache dont on ne sait pas ecrire la preuve a produire n'est pas prete : la
  decouper jusqu'a ce qu'on sache.

Provenance : audit qualite 08/2026 — aucune matrice de tracabilite complete AC ↔
maquette ↔ tache ↔ test, brique entiere codee en un jour sans plan verifiable.

### 9. Tag git de reference

Quand tout est corrige et coherent :

```bash
git tag mockups-valides-brique-{N}
```

Ce tag est LA reference visuelle de la brique : le rapport de parite de
`brick-code-review` et les briques suivantes comparent contre lui, pas contre l'etat
courant de `/mockups`. On ne le deplace JAMAIS.

### 10. Verdict

Ecrire `doc/memory/brick-{N}/reanalyse.md` :

```markdown
# Reanalyse — Brick #{N} — {date}

## Matrice AC ↔ maquette : X/Y AC couverts
## Data model : X champs, Y decisions ecrites, Z corrections
## Donnees fabriquees : X elements verifies, Y sources creees, Z passes en etat vide
## Parcours navigues : X/Y OK (captures : reanalyse-shots/)
## Pages publiques : SEO maquette OK/KO (ou : aucune page publique)
## Jeu de donnees : quotas OK/KO, sous-ensemble montre OK/KO
## Decisions : completes OUI/NON — N nouvelles entrees dans decisions.md
## Kanban : X taches en Y lots — matrice AC ↔ tache complete OUI/NON
## Corrections journalisees : [quoi / quel cote / pourquoi]
## Tag : mockups-valides-brique-{N} pose sur {sha}

## Verdict : PRET / A CORRIGER
```

**A CORRIGER = on n'ouvre pas le code.** Corriger, re-jouer les etapes impactees,
re-rendre le verdict. PRET est la seule porte d'entree de `brick-code-build`.

## Validation gate

- [ ] Chaque AC a sa maquette nommee (ou sa sortie de scope journalisee)
- [ ] Chaque champ du data model a sa ligne affiche/saisi/decision, aucune vide
- [ ] Chaque chiffre/compteur/score visible a une source reelle prevue, ou un etat vide
- [ ] Chaque parcours navigue au playwright, captures a l'appui
- [ ] Jeu de donnees : quotas respectes, maquettes montrent le sous-ensemble
- [ ] Pages publiques : head, H1, contenu citable et NAP conformes a `/brick-seo`
- [ ] `decisions.md` complet et coherent avec les maquettes, defauts tranches
- [ ] Kanban ecrit : chaque tache a criteres couverts + perimetre prevu + preuve a produire
- [ ] Matrice AC ↔ tache complete dans les deux sens (aucun orphelin)
- [ ] Tag `mockups-valides-brique-{N}` pose
- [ ] Verdict PRET ecrit dans reanalyse.md

## Ensuite

→ `brick-code-build` (uniquement sur verdict PRET).
