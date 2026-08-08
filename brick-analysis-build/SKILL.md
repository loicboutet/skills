---
name: brick-analysis-build
description: "Phase 1 : analyse des specs, objectif metier signe, jeu de donnees canonique, data models, routes, decisions de comportement, criteres d'acceptance. Utilise /brick-analysis-build pour demarrer l'analyse d'un projet ou d'une nouvelle brick."
---

# Brick Analysis

Analyse les specs et cree la documentation technique avec des criteres d'acceptance tracables.

## Quand utiliser

- Nouveau projet sans README ou avec `Etat: ANALYSIS`
- Nouvelle brick ajoutee au projet

## Process

### 1. Collecter les informations

- Lire les specs fournies (system prompt, fichiers, conversations)
- Si des outils Leexi sont disponibles, recuperer les conversations client
- **Interroger le second cerveau** (`/brain`) sur les domaines du projet AVANT de
  defricher : `brain_tool(action: "search", query: "<mots-cles metier>")`. Traiter
  chaque note comme une piste a recouper (voir sa `confidence`), pas une verite.
- **Toujours demander** : "Y a-t-il des bricks additionnelles ?"
- Demander clarifications si necessaire

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
sous-agent configure sur le modele le plus capable disponible avec effort de
raisonnement maximal ; ne le genere jamais en passant, ni avec un modele economique.**
Les autres sections de ce skill restent au modele par defaut. Le sous-agent suit ces
exercices, dans l'ordre :

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
   consecutives. Chaque cas nomme rejoint le jeu ou une decision d'analyse ecrite.
8. **Personas qui cassent** : 3 personas metier plausibles (la secretaire pressee
   qui double-clique, le comptable pointilleux qui verifie chaque arrondi, le gerant
   qui fait tout depuis son telephone) ; pour chacun, un scenario de donnees qui le
   fait trebucher.
9. **Examen** : relecture finale categorie par categorie, quotas en main.
   **Discernement** : chaque cas limite qui revele une decision non prise remonte en
   decision d'analyse ("gere / hors scope assume / non applicable", motif en une
   ligne, dans decisions_comportement.md), jamais en implementation silencieuse.

#### Regle de propagation

- Les **maquettes** MONTRENT un sous-ensemble representatif (au minimum : les empty
  states, un badge suspendu/archive, une troncature).
- Les **seeds/fixtures** les implementent TOUS.
- La **recette** les exerce TOUS.

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

Pour chaque modele :
- Responsabilites
- Attributs (nom, type, description)
- Relations
- Methodes principales

Inclure un historique des modifications (date + modeles ajoutes/modifies).

### 5. Creer `doc/memory/decisions_comportement.md`

Pour CHAQUE entite du data model, decider par ecrit. Reponses autorisees :
**"gere"** (avec le comportement choisi), **"hors scope assume (ecrit)"**, ou
**"non applicable"**. Aucune case vide. On decide, on ne sur-implemente pas.

```markdown
# Decisions de comportement — Brick #{N}

## Par entite
| Entite | Suppression (bloquer/archiver/cascader + pourquoi) | Etats degrades (desactive/suspendu) |
|--------|-----------------------------------------------------|--------------------------------------|
| Client | archiver (les factures doivent survivre)            | suspendu : jobs recurrents exclus    |

## Transverse
- Responsive : {dans le scope : ecrans vises utilisables a 390 px / hors scope assume (ecrit)}
- Fuseau horaire : {ex : Europe/Paris, config.time_zone}
```

Provenance : audit qualite livraisons 08/2026 — cascades latentes
(`dependent: :destroy` non audite), jobs recurrents sur entreprises suspendues,
mobile jamais ouvert avant livraison.

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

Chaque critere doit etre :
- **Specifique** : pas "ca marche bien" mais "l'utilisateur voit un message de succes"
- **Testable** : peut etre verifie par un test automatise ou manuel
- **Tracable** : reference dans les taches d'implementation (R1 → tache 003)

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

Avant d'ecrire les parcours d'un profil, se representer concretement la situation
reelle et repondre par ecrit :

- A quelle heure il ouvre l'app, sur quel appareil, quelle taille d'ecran
- Ce qu'il faisait juste avant, ce qu'il fera juste apres
- Ce qu'il a d'autre sous les yeux au meme moment (un mail, un tableur, un client
  au telephone, un dossier papier a recopier)
- Combien de temps il a devant lui, et qui peut l'interrompre
- Ce qui se passe pour lui si l'app est indisponible ce jour-la
- A quelle frequence il fait ca : dix fois par jour ou une fois par trimestre

Trois a cinq lignes par profil, en tete de sa section. Si on ne sait pas repondre a
une question, c'est une question a poser au client, jamais a inventer.

Pour chaque parcours :
- **Entree** : comment l'utilisateur arrive
- **Etapes** : chaque action et la reponse attendue
- **Succes** : ou ca mene quand tout va bien
- **Erreurs** : les cas d'erreur et comment on les gere
- **Sortie** : ou l'utilisateur finit

### 9. Verifier `doc/memory/style_guide.html`

- Si fourni : utiliser tel quel
- Si elements fournis : generer
- Si rien : DEMANDER (couleurs, fonts, style)

### 10. Mettre a jour le README.md

```markdown
## Etat du projet
Etat: ANALYSIS COMPLETE

## Documentation
- [x] objectif.md (signe le {date})
- [x] jeu_de_donnees.md
- [x] data_models.md
- [x] decisions_comportement.md
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
- [ ] Decisions de comportement : chaque entite a sa ligne suppression + etats
      degrades ; responsive et fuseau decides ; aucune case vide
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
