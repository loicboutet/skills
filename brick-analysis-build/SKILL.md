---
name: brick-analysis-build
description: "Phase 1 : analyse des specs, objectif metier signe, jeu de donnees canonique, data models, routes, journal de decisions avec matrice CRUD par entite, manifeste de config, criteres d'acceptance. Utilise /brick-analysis-build pour demarrer l'analyse d'un projet ou d'une nouvelle brick."
---

# Brick Analysis

Analyse les specs et cree la documentation technique avec des criteres d'acceptance tracables.

## Quand utiliser

- Nouveau projet sans README ou avec `Etat: ANALYSIS`
- Nouvelle brick ajoutee au projet

## Principe directeur (vaut pour toute la phase)

**Calculer plutot que declarer, decider plutot que demander.**
Le client connait le QUOI ; le COMMENT est notre travail. On ne pose presque jamais
de question : on tranche avec un defaut motive, on consigne dans `decisions.md`, et on
signale a la livraison les rares decisions qui touchent au QUOI. Une seule interdiction
absolue : fabriquer une DONNEE (voir plus bas).

> **Modeles et discipline de tour** : ce skill delegue a des sous-agents (jeu de donnees,
> notamment). Doctrine mesuree, commune a toute la chaine, dans `/brick-code-build`
> (« Repartition des modeles » et « Discipline de tour ») : tous les sous-agents en
> `model: "opus"`, et l'orchestrateur n'attend jamais un sous-agent en rendant son tour.

## Process

### 1. Collecter les informations

- Lire les specs fournies (system prompt, fichiers, conversations)
- Si des outils Leexi sont disponibles, recuperer les conversations client
- **Interroger le second cerveau** (`/brain`) sur les domaines du projet AVANT de
  defricher : `brain_tool(action: "search", query: "<mots-cles metier>")`. Traiter
  chaque note comme une piste a recouper (voir sa `confidence`), pas une verite.
- **Toujours demander** : "Y a-t-il des bricks additionnelles ?"
- Toute autre inconnue se tranche (voir 5), elle ne se demande pas.

### 2. Creer `doc/memory/objectif.md` — le QUOI

C'est LE document que le client valide en debut de brique. 5 a 15 lignes, pas plus.

```markdown
# Objectif — Brick #{N} : {nom}

## Ce que la brique doit rendre possible (QUOI)
{3-8 lignes d'objectif METIER : ce que le client pourra faire qu'il ne peut pas
faire aujourd'hui. Zero technique, zero ecran.}

## Criteres de succes client
- {ce que le client constatera de ses propres yeux pour dire "c'est livre"}

## Signature
Valide par : {nom} le {date}. Immuable sans avenant.
```

Regles :
- **Immuable une fois signe.** Toute modification = avenant, jamais une edition silencieuse.
- `acceptance_criteria.md` est le COMMENT : mutable, versionne, avec journal de scope.
- **Regle d'arbitrage** (reprise par les skills feedback/triage) : une demande qui sert
  le QUOI est due, on la fait (en mettant a jour maquettes + specs). Une demande hors
  du QUOI part en later_brick ou avenant, reponse au client qui cite l'objectif signe.

### 3. Creer `doc/memory/jeu_de_donnees.md` — le jeu de donnees canonique

UN seul jeu de donnees pour tout le pipeline : maquettes, seeds/fixtures, recette,
videos. Tous les agents se representent le meme flux d'information. Interdit
d'inventer d'autres donnees de demo en aval.

Le jeu de donnees est COMPLET : cas nominaux ET cas limites, systematiquement.
C'est lui qui porte les cas limites, pas du code speculatif.

#### Contenu minimal — chaque cas ETIQUETE avec ce qu'il exerce

- **Personas** : un par profil/role (nom complet, email, role, droits exacts), dont
  un persona PAR niveau de droit restreint (il servira aux tests de permissions par
  blocs d'affichage).
- **Etats difficiles du cycle de vie** : contact archive AVEC une affaire liee
  (exerce suppression/cascade), entreprise suspendue avec une facture recurrente
  programmee, compte utilisateur desactive, invitation en attente jamais acceptee.
- **Argent aux bornes** : document a 0 €, avoir (negatif), montant qui exerce les
  arrondis TVA multi-taux, remise a 0 % et au maximum autorise, un total qui depasse
  le million (largeur d'affichage).
- **Chaines hostiles** : nom avec apostrophe et accents ("O'Brien & Ça Frères"),
  texte tres long qui doit tronquer, entree contenant des caracteres HTML (exerce
  l'echappement).
- **Temps** : une entite creee l'annee precedente (exerce libelles de date et
  regroupements), une echeance qui traverse le mois et l'annee, un evenement
  "aujourd'hui" relatif a l'horloge simulee. JAMAIS de date en dur : relatives uniquement.
- **Volumes** : une liste a 0 element (empty state), une a 1, une qui pagine.
- **Multi-tenant** : un second tenant avec des donnees miroirs reconnaissables
  (une fuite d'isolation devient visible a l'oeil).

#### Protocole de generation (exercices)

Le jeu de donnees est un livrable d'analyse critique : **delegue sa generation a un
sous-agent configure sur le modele `opus` avec effort de
raisonnement maximal ; ne le genere jamais en passant, ni avec un modele economique.**

Le sous-agent suit ces exercices, dans l'ordre :

1. **Composition de lieu** appliquee aux donnees : avant de generer une entite, se
   placer dans la scene reelle (lundi 8h, le bureau de Martin Charpente, la pile de
   factures, le telephone qui sonne). Chaque donnee doit pouvoir exister dans cette
   scene (un devis a un chantier, une adresse, un delai realiste). Pas de lorem
   ipsum chiffre.
2. **Partitions d'abord, instances ensuite** : enumerer les partitions d'equivalence
   de chaque entite (etats du cycle de vie, plages de montants, plages de dates,
   volumes, roles) AVANT toute instance. Puis pour chaque partition numerique/date :
   minimum, maximum, juste-dedans, juste-dehors, zero, negatif, vide.
3. **Quotas** : au moins un cas par categorie du contenu minimal ci-dessus. Une
   categorie a zero = generation refusee, on recommence.
4. **Agere contra** : les cas qu'on hesite a inclure parce qu'ils compliquent tout
   (l'avoir partiel sur facture partiellement payee, le contact archive au milieu
   d'un parcours) sont precisement ceux qui doivent y etre. **Indifference** : aucun
   privilege au happy path, le cas laid recoit le meme soin de realisme.
5. **Application des sens** : derouler chaque parcours en "voyant" l'ecran avec ces
   donnees : que voit exactement l'utilisateur, qu'est-ce qui deborde, se tronque,
   s'affiche vide ? Ce que cet exercice revele, les maquettes devront le montrer.
6. **Repetition** (relecture de completude) : reprendre la meme matiere une seconde
   fois a froid, avec interdiction de proposer des retraits : "liste uniquement ce
   qui MANQUE, categorie par categorie". Pas de relecture adversariale : elle degrade
   la completude. Cette relecture ajoute, ne retire jamais.
7. **Premortem itere** : "L'application a eu un bug en production cause par un cas
   de donnees absent de ce jeu. Nomme ce cas." Repeter jusqu'a deux reponses vides
   consecutives. Chaque cas nomme rejoint le jeu ou une decision ecrite.
8. **Personas qui cassent** : 3 personas metier plausibles (la secretaire pressee
   qui double-clique, le comptable pointilleux qui verifie chaque arrondi, le gerant
   qui fait tout depuis son telephone) ; pour chacun, un scenario de donnees qui le
   fait trebucher.
9. **Examen** : relecture finale categorie par categorie, quotas en main.
   **Discernement** : chaque cas limite qui revele une decision non prise remonte en
   entree de `decisions.md` ("gere / hors scope assume / non applicable", motif en
   une ligne), jamais en implementation silencieuse.

#### Regle de propagation

- Les **maquettes** MONTRENT un sous-ensemble representatif (au minimum : les empty
  states, un badge suspendu/archive, une troncature).
- Les **seeds/fixtures** les implementent TOUS.
- La **recette** les exerce TOUS.

#### Regle de fabrication : une donnee de seed doit ressembler a ce que l'application PRODUIT

Une donnee ecrite « a la main » dans les seeds (statut pose directement, dates
finalisees a la creation, numero attribue sans passer par la sequence) peut etre dans
un etat que l'application ne fabrique JAMAIS. La recette qui rejoue tout sur cette
donnee passe, et le chemin reel n'est pas exerce. Mesure sur le banc modeles
(16-17/08/2026) : l'avoir du seed etait ecrit `sent` ; ceux que l'application creait
naissaient `draft` avec une date de finalisation, et le calcul du CA ne comptait que
les `sent`. Recette verte, chiffre d'affaires faux sur tout avoir reel, invisible.

Donc, dans le jeu canonique et dans les seeds qui l'implementent :
- **Chaque entite a cycle de vie est produite par le meme chemin que l'application**
  (le service, la transition, le job) ou, si c'est trop lourd, dans l'etat EXACT que ce
  chemin produit (memes statuts, memes horodatages, memes champs derives). Interdit de
  poser un statut « final » directement si l'app passe par un etat intermediaire.
- **Le jeu prevoit un exemplaire « ne du produit »** par entite d'argent ou de droit
  (une facture, un avoir, un reglement, une invitation crees a la recette PAR
  L'INTERFACE, pas par les seeds), et le cahier de recette porte au moins un critere
  qui compare les agregats AVANT/APRES cette creation. C'est ce critere qui aurait vu
  le trou de CA.
- Un ecart entre « donnee de seed » et « donnee produite » est un defaut connu de la
  famille donnees fausses : il se corrige, il ne se consigne pas.

#### Format

```markdown
# Jeu de donnees canonique — {projet}

## Personas
| Persona | Email | Role | Droits | Exerce |
|---------|-------|------|--------|--------|
| Claire Fontaine | claire@exemple.fr | Admin | tout | nominal |
| Karim Benali | karim@exemple.fr | Commercial | billing: none | permissions d'affichage |

## {Entite}
| Champ | Enreg. 1 | Enreg. 2 | Enreg. 3 |
|-------|----------|----------|----------|
| nom | O'Brien & Ça Frères | ... | ... |
| total | 1 240 350,50 € | 0,00 € | ... |
| statut | active | archivee (affaire liee) | ... |
| Exerce | largeur, apostrophe | borne zero | cascade |
```

### 4. Creer `doc/memory/data_models.md`

Pour chaque modele : responsabilites, attributs (nom, type, description), relations,
methodes principales. Inclure un historique des modifications (date + modeles
ajoutes/modifies).

### 5. Creer `doc/memory/decisions.md` — le journal de decisions UNIQUE

Un seul fichier pour toute la vie du projet. Il absorbe ce qui s'appelait
`decisions_comportement.md` : ne PAS creer de second fichier de decisions.

#### Regles (a recopier en tete du fichier)

- **Inconnue sur le COMMENT** (technique, ergonomie, structure, nommage, defaut d'un
  champ) → on decide, on consigne, on ne remonte RIEN.
- **Inconnue sur le QUOI** (regle metier, montant, droit, obligation legale) → on
  decide QUAND MEME avec un defaut motive, on coche « a signaler », et c'est presente
  a la livraison comme un choix explique. JAMAIS comme une question.
- **Fabriquer une DONNEE est interdit, sans exception** : compteur en dur, image
  inventee, score bidon, texte de demo presente comme reel, moyenne calculee sur du
  vide. C'est la SEULE interdiction absolue du projet. A la place : **etat vide
  honnete** ("aucune donnee pour l'instant") ou la donnee reelle, rien d'autre.
- **Ce journal n'accueille JAMAIS un defaut constate.** Une ligne qui decrit un bug
  d'argent, de permission, de donnee fausse ou de fuite n'est pas une decision, c'est
  un bug ouvert : il se corrige (regle du defaut connu, `brick-code-build`).
- **Chaque decision consignee devient un critere de recette** : le cahier de recette
  (ecrit a la reanalyse) tire une ligne par decision, et `brick-code-review` exige une
  preuve pour chacune.
- On AJOUTE, on ne reecrit jamais une entree passee.

#### Format

```markdown
# Journal de decisions — {projet}

## Regles
{les 6 regles ci-dessus, recopiees}

## Matrice CRUD — une ligne par entite du data model (phase ANALYSIS)
| Entite | Creer (qui, conditions) | Modifier (qui, jusqu'a quand) | Supprimer | Archiver | Etats degrades |
|--------|-------------------------|-------------------------------|-----------|----------|----------------|
| Client | admin, commercial | admin, commercial | non offert (les factures doivent survivre) | offert, admin | suspendu : jobs recurrents exclus |
| Devis  | admin, commercial | tant que brouillon | offert, admin, si non facture | remplace par « perdu » (motif) | — |

## Decisions d'analyse — transverses
- Responsive : {dans le scope : ecrans vises utilisables a 390 px / hors scope assume (ecrit)}
- Fuseau horaire : {ex : Europe/Paris, config.time_zone}
- {toute autre decision structurante prise en analyse}

## Journal courant (une ligne par decision, ajoutee au fil du projet)
| Date | Decision (la question tranchee) | Defaut retenu | Motif (1 ligne) | Reversible | A signaler |
|------|--------------------------------|---------------|-----------------|------------|------------|
| 2026-08-08 | Delai de validite d'un devis | 30 jours | usage du BTP, modifiable en config | oui | oui (QUOI) |
| 2026-08-08 | Tri par defaut de la liste clients | nom A→Z | le plus previsible | oui | non |
```

La matrice CRUD est **obligatoire et complete** : chaque entite du data model a sa
ligne, chaque case une reponse — **"offert"** (avec qui et sous quelles conditions),
**"non offert"** (motif en une ligne), ou **"remplace par l'archivage"** / par un
changement d'etat metier nomme. Case vide = analyse non finie.

Elle est le contrat de la brique sur les gestes destructifs : ce qui y est « offert »
DOIT avoir un bouton dans les maquettes puis dans l'app (verifie a la reanalyse et a la
review) ; ce qui n'y est pas ne doit exister ni en route, ni en action, ni en bouton.
Les etats degrades gardent leur colonne (compte desactive, entreprise suspendue : ce qui
s'arrete) ; "non applicable" accepte s'il est ecrit.

Provenance : audit qualite 08/2026 — neuf actions `destroy` ecrites et testees sans
aucun bouton, une route DELETE vers une action inexistante ; cascades latentes
(`dependent: :destroy` non audite), jobs recurrents sur entreprises suspendues, mobile
jamais ouvert avant livraison ; Tastellers (compteurs en dur "127 connexions" sur le
dashboard d'un vrai client).

### 5b. Amorcer `doc/memory/config.md` — le manifeste de configuration

Une ligne par variable d'environnement / cle / reglage d'environnement, avec son
**consommateur nomme** (le fichier de code qui la LIT) et sa valeur attendue PAR
environnement. En analyse on amorce avec ce que les specs imposent deja (host des
mails, fuseau, services externes cites). Chaque tache de code qui en introduit une
l'ajoute ; `brick-code-review` confronte le manifeste a l'environnement livre.

```markdown
# Manifeste de configuration — {projet}
| Cle | Consommateur (fichier:ligne) | dev | staging | prod | Si absente |
|-----|------------------------------|-----|---------|------|------------|
| APP_HOST | config/environments/production.rb (default_url_options) | localhost:3000 | {slug}-staging.5000.dev | {slug}.5000.dev | mails avec liens morts |
```

Ce manifeste decrit ce qui EST branche. Une cle sans consommateur reel n'y figure pas
sous forme de note ou de « facade a trancher » : c'est un bug, il se corrige.

Provenance : audit qualite 08/2026 — APP_HOST absent (mails pointant sur app.5000.dev
chez Tastellers ET educxa), superadmin en dur en prod chez Gespilot, cle Postmark
soigneusement stockee derriere un ecran de config et jamais lue a l'envoi.

### 6. Creer `doc/memory/routes.md`

Regles :
- Un namespace par profil (`/admin/`, `/users/`, etc.)
- JAMAIS `/analysis` ET `/dashboard` pour le meme profil
- Max 3-5 actions rapides par ressource
- TOUJOURS des routes pour gerer les cles API
- JAMAIS de routes monitoring systeme
- Si la brique a des pages PUBLIQUES : noter pour chacune sa requete cible SEO
  (metier + ville en local, besoin + qualificatif sinon) directement dans routes.md,
  et collecter aupres du client les donnees que le SEO exigera (NAP exact, avis/verbatims,
  diplomes/preuves, acces/parking, fourchettes de prix) — cf. `/brick-seo`

### 7. Creer `doc/memory/acceptance_criteria.md` — le COMMENT

Chaque feature a des criteres testables et tracables.

```markdown
# Acceptance Criteria

## Feature: [Nom]
### Requirements
- R1: [Description]
  - [ ] AC1.1: [Critere verifiable]
  - [ ] AC1.2: [Critere verifiable]

## Journal de scope
| Date | Demande | Origine | Impact |
```

Chaque critere doit etre **specifique** (pas "ca marche bien" mais "l'utilisateur voit
un message de succes"), **testable** (verifiable par un test automatise ou manuel) et
**tracable** (reference dans les taches d'implementation : R1 → tache 003).

#### Rattachement : chaque feature sert une fin

Passer la liste des features envisagees une par une, nommer l'AC que chacune sert,
et l'ECRIRE. Une feature sans AC n'est pas un bonus : soit elle revele un AC
manquant (l'ajouter et le tracer), soit elle est hors scope (le dire a l'utilisateur
avant de la mettre dans les mockups). Chaque AC doit lui-meme servir le QUOI de
`objectif.md` — un AC qui ne sert pas l'objectif est a questionner.

### 8. Creer `doc/memory/user_journeys.md`

Definir les parcours utilisateurs cles. Chaque parcours = un chemin complet dans
l'app, joue par un PERSONA NOMME du jeu de donnees canonique (jamais un profil
abstrait) : c'est ce parcours exact que les maquettes montreront, que le system
test deroulera et que la video filmera.

#### Composition de lieu (a faire AVANT d'ecrire les parcours)

Se representer concretement la situation reelle et repondre par ecrit :

- A quelle heure il ouvre l'app, sur quel appareil, quelle taille d'ecran
- Ce qu'il faisait juste avant, ce qu'il fera juste apres
- Ce qu'il a d'autre sous les yeux au meme moment (un mail, un tableur, un client
  au telephone, un dossier papier a recopier)
- Combien de temps il a devant lui, et qui peut l'interrompre
- Ce qui se passe pour lui si l'app est indisponible ce jour-la
- A quelle frequence il fait ca : dix fois par jour ou une fois par trimestre

Trois a cinq lignes par profil, en tete de sa section. Si on ne sait pas repondre a
une question, c'est une question a poser au client, jamais a inventer.

Pour chaque parcours : **Entree** (comment l'utilisateur arrive), **Etapes** (chaque
action et la reponse attendue), **Succes** (ou ca mene quand tout va bien),
**Erreurs** (les cas d'erreur et comment on les gere), **Sortie** (ou il finit).

### 9. Verifier `doc/memory/style_guide.html`

- Si fourni : utiliser tel quel
- Si elements fournis : generer
- Si rien : DEMANDER (couleurs, fonts, style) — c'est une des rares vraies questions

### 10. Mettre a jour le README.md

```markdown
## Etat du projet
Etat: ANALYSIS COMPLETE

## Documentation
- [x] objectif.md (signe le {date})
- [x] jeu_de_donnees.md
- [x] data_models.md
- [x] decisions.md (matrice CRUD complete)
- [x] config.md (amorce)
- [x] routes.md
- [x] acceptance_criteria.md
- [x] user_journeys.md
- [x] style_guide.html

Pret pour MOCKUPS
```

## Validation gate

Avant de passer a MOCKUPS, verifier :
- [ ] `objectif.md` existe, 5-15 lignes de QUOI metier, signe par le client
- [ ] Jeu de donnees : quotas respectes (au moins un cas par categorie, chaque cas
      etiquete), genere par le protocole (partitions, repetition, premortem, examen)
- [ ] `decisions.md` : regles recopiees ; **matrice CRUD complete** (creer / modifier /
      supprimer / archiver x qui + conditions, chaque case renseignee) ; etats degrades
      par entite ; responsive et fuseau decides ; aucune case vide ; aucune decision
      laissee sous forme de question ouverte
- [ ] `config.md` amorce (au minimum APP_HOST et le fuseau, avec consommateur nomme)
- [ ] Tous les modeles ont des relations coherentes
- [ ] Les routes couvrent toutes les features des specs
- [ ] Chaque feature a au moins 2 criteres d'acceptance
- [ ] Chaque feature envisagee est rattachee a un AC nomme (aucune orpheline)
- [ ] Les parcours couvrent tous les profils, joues par des personas nommes
- [ ] Chaque profil a sa composition de lieu, sans trou invente
- [ ] Le style guide est defini (sinon lancer `/brick-design-build`)
- [ ] L'utilisateur a valide

## Ensuite

→ `brick-analysis-review` (relire l'analyse). Puis `brick-design-brief` si le client
n'a pas de charte, sinon `brick-mockup-build` (les maquettes utilisent le jeu de
donnees canonique, rien d'autre).
