---
name: brick-mockup-reanalyse
description: "Controle BLOQUANT apres la validation client des maquettes, avant le code : matrice AC-maquette, data model champ par champ (affiche ET saisi), parcours navigues au playwright, jeu de donnees canonique, tag git de reference, mise a jour bidirectionnelle de l'analyse, verdict PRET / A CORRIGER. Utilise /brick-mockup-reanalyse quand le client a valide les maquettes, avant /brick-code-build."
---

# Brick Mockup Reanalyse

Derniere ligne de defense avant le code. Les maquettes validees par le client et
l'analyse doivent dire EXACTEMENT la meme chose, et chaque promesse visuelle doit
avoir sa mecanique (saisie, route, decision ecrite). On n'ouvre pas le code sur un
verdict A CORRIGER.

## Quand utiliser

- Les maquettes de la brique sont validees par le client (fin de la boucle MOCKUP)
- JAMAIS pendant la boucle mockup : c'est une etape de sortie, pas une review intermediaire

## Pre-requis

- `doc/memory/` : objectif.md, acceptance_criteria.md, data_models.md,
  user_journeys.md, jeu_de_donnees.md, decisions_comportement.md
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
  Pas de decision = A CORRIGER. (Audit 08/2026 : postal_code imprime sur les
  factures et le PDF, absent du formulaire et du permit.)
- L'inverse aussi : un champ saisi jamais affiche → questionner (saisie pour rien,
  ou affichage manquant).
- **Cles et credentials** : tout ecran de configuration (cle API, parametres d'envoi)
  doit nommer le code qui LIRA la valeur saisie. Ecran de saisie sans consommateur
  nomme = facade. (Audit 08/2026 : cle Postmark soigneusement stockee, jamais lue
  a l'envoi.)
- Les controles interactifs promis par une maquette (select qui rafraichit, recherche,
  filtre) sont listes avec leur mecanique prevue (Turbo/Stimulus + route). Promesse
  sans mecanique = A CORRIGER. (Audit 08/2026 : select client sans `data-action`.)

### 3. Parcours NAVIGUES au playwright (jamais relus)

Pour CHAQUE parcours de user_journeys.md : le DEROULER dans les maquettes avec
`playwright-cli`, etape par etape, en cliquant reellement. Screenshot a chaque etape.

- Un lien mort, un bouton sans cible, une etape sans ecran = A CORRIGER.
- Lire le code des maquettes NE remplace PAS la navigation (constat d'audit :
  "parcours verifies en lisant" = bugs invisibles).
- Conserver les captures dans `doc/memory/brick-{N}/reanalyse-shots/` (trace du verdict).

### 4. Jeu de donnees canonique dans les maquettes

Verifier que les maquettes affichent les valeurs EXACTES de jeu_de_donnees.md
(noms, montants, statuts), puis les quotas et la regle de propagation :

- [ ] Quotas respectes : au moins un cas par categorie (etats difficiles, argent aux
      bornes, chaines hostiles, temps, volumes, multi-tenant), chaque cas etiquete
      avec ce qu'il exerce
- [ ] Les maquettes MONTRENT le sous-ensemble representatif : au minimum les empty
      states, un badge suspendu/archive, une troncature
- Donnee inventee dans une maquette → remplacer par le canonique, OU enrichir le
  canonique si le cas est bon (mise a jour bidirectionnelle, journalisee)

### 5. Decisions de comportement a la lumiere des maquettes

Relire decisions_comportement.md maquette en main :
- Une maquette montre un bouton Supprimer → la decision suppression de l'entite existe ?
- Un badge d'etat (suspendu, archive) apparait → l'etat degrade est decide ?
- Des ecrans mobiles sont montres → coherent avec la decision responsive ?

Reponses autorisees : "gere", "hors scope assume (ecrit)", "non applicable".
Case vide ou contradiction maquette/decision = A CORRIGER.

### 6. Mise a jour bidirectionnelle

Chaque ecart se corrige d'UN cote (maquette OU analyse), jamais des deux en silence :
- Corriger, journaliser dans reanalyse.md (quoi, quel cote, pourquoi)
- Si la correction change ce que le client a valide visuellement → le signaler a
  l'utilisateur AVANT (pas de re-validation silencieuse)
- Re-jouer l'etape de verification impactee apres correction (matrice ou navigation)

### 7. Tag git de reference

Quand tout est corrige et coherent :

```bash
git tag mockups-valides-brique-{N}
```

Ce tag est LA reference visuelle de la brique : le rapport de parite de
`brick-code-review` et les briques suivantes comparent contre lui, pas contre l'etat
courant de `/mockups`. On ne le deplace JAMAIS.

### 8. Verdict

Ecrire `doc/memory/brick-{N}/reanalyse.md` :

```markdown
# Reanalyse — Brick #{N} — {date}

## Matrice AC ↔ maquette : X/Y AC couverts
## Data model : X champs, Y decisions ecrites, Z corrections
## Parcours navigues : X/Y OK (captures : reanalyse-shots/)
## Jeu de donnees : quotas OK/KO, sous-ensemble montre OK/KO
## Decisions de comportement : completes OUI/NON
## Corrections journalisees : [quoi / quel cote / pourquoi]
## Tag : mockups-valides-brique-{N} pose sur {sha}

## Verdict : PRET / A CORRIGER
```

**A CORRIGER = on n'ouvre pas le code.** Corriger, re-jouer les etapes impactees,
re-rendre le verdict. PRET est la seule porte d'entree de `brick-code-build`.

## Validation gate

- [ ] Chaque AC a sa maquette nommee (ou sa sortie de scope journalisee)
- [ ] Chaque champ du data model a sa ligne affiche/saisi/decision, aucune vide
- [ ] Chaque parcours navigue au playwright, captures a l'appui
- [ ] Jeu de donnees : quotas respectes, maquettes montrent le sous-ensemble
- [ ] decisions_comportement.md complet et coherent avec les maquettes
- [ ] Tag `mockups-valides-brique-{N}` pose
- [ ] Verdict PRET ecrit dans reanalyse.md

## Ensuite

→ `brick-code-build` (uniquement sur verdict PRET).
