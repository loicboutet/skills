---
name: recette-naive
description: "Traversee par des agents qui ne savent RIEN du produit : on enumere les types d'utilisateurs, on leur donne une persona, un objectif metier et rien d'autre, et un verificateur distinct tranche leurs abandons. Attrape la classe « la fonction marche et personne ne la trouve », que ni le cahier de recette ni les parcours connus ne peuvent voir. Deroulee par /brick-mockup-review (mode maquette) et /brick-code-review (mode application). Utilise /recette-naive pour lancer une traversee naive sur un lot de maquettes ou une app livree."
---

# Recette naive — traverser sans rien savoir

Tout le reste de nos reviews verifie **ce qui est la**. Le cahier de recette porte l'URL, le
compte, le geste et l'observation attendue de chaque ligne ; la matrice AC ↔ maquette part des
AC ; les parcours navigues partent de `user_journeys.md`. Ces documents ont ete ecrits par la
meme chaine que le produit. **Rien dans la chaine ne peut donc etre surpris** : on verifie « le
critere est-il satisfait », jamais « quelqu'un qui ne sait rien y arrive-t-il ».

Cette methode est le seul endroit du process ou l'on mesure la seconde question.

**Mesure, banc livraison, passes p5 et p6 (08/2026), deux projets par passe.** Sur app livree :
rendement 30 % et 55 %, **33 defauts reels dont 33 sur 34 absents des rapports de recette de ces
projets**, et les deux bras ne se recouvrent qu'en **UN point** sur tout le corpus. Sur maquettes :
navigabilite 24 % et 34 %, trous de perimetre 12 % et 14 %.


> **Modeles et discipline de tour** : ce skill delegue a des sous-agents. Doctrine mesuree,
> commune a toute la chaine, dans `/brick-code-build` (« Repartition des modeles » et
> « Discipline de tour ») : tous les sous-agents en `model: "opus"`, et l'orchestrateur
> n'attend jamais un sous-agent en rendant son tour.

## Deux modes

| | **Mode maquette** (`/brick-mockup-review`, avant le client) | **Mode application** (`/brick-code-review`, section 7b) |
|---|---|---|
| Ce qui est normal | tout est mocke : un bouton inerte ne se signale pas | rien n'est mocke : un bouton inerte est un defaut |
| Le verificateur tranche contre | l'inventaire des maquettes | le depot et l'app lancee |
| Classes rendues | navigabilite **et** trou de perimetre | defaut reel |
| URL de depart | l'ecran d'accueil du role (jamais l'ecran de connexion, il est inerte) | l'ecran de connexion, avec des identifiants |
| Comptes | aucun a provisionner (lots en GET seuls, agents parallelisables) | **un compte par run**, ou runs serialises |

Le reste est commun, et c'est le reste qui compte.

## 0. Enumerer les types d'utilisateurs (fait par l'ORCHESTRATEUR, pas par l'agent naif)

**On ne choisit pas les personas a l'intuition, on les enumere.** C'est l'etape qui repare le
trou mesure a la passe p6 : le bras ne predisait **aucun** des ecrans que le code a inventes, et
la raison etait structurelle — **21 des 30 ecrans inventes etaient le back-office
d'administration, qui n'est dans aucun QUOI, donc dans aucun objectif derive du QUOI**. Un type
d'utilisateur qu'on n'enumere pas est une surface entiere qui n'est jamais traversee.

Sources a croiser, toutes lues **par l'orchestrateur** :
- les profils de `user_journeys.md` ;
- les namespaces et contraintes de role de `routes.md` (`/admin`, `/app`, espace client…) ;
- les roles du data model et les comptes du jeu de donnees canonique ;
- les roles que le produit cree sans qu'on y pense : **l'administrateur interne**, le premier
  utilisateur d'un compte vide, l'invite a droits restreints, l'utilisateur d'un second tenant.

Rendre la liste, explicitement, avant de lancer quoi que ce soit :

| Type d'utilisateur | D'ou il sort | Traverse ? | Objectifs |
|---|---|---|---|
| Gerant d'entreprise | user_journeys, jeu canonique | OUI | 2 |
| Employe (droits restreints) | routes.md, roles du modele | OUI | 1 |
| Administrateur interne | namespace /admin | OUI | 1 |

- **Chaque type enumere a au moins un objectif**, et **chaque objectif se joue en deux tirages**.
- **Un type non traverse se declare** dans le rapport, avec sa raison. Le silence n'est pas une
  couverture.
- La dose monte donc avec le nombre de types : c'est voulu, une surface non traversee est une
  surface ou l'on inventera.

**Enumerer les TYPES n'est pas deriver les OBJECTIFS des AC.** Le type, c'est *qui* ; l'objectif,
c'est *ce qu'il veut faire*, et il se derive du **QUOI** (`doc/memory/objectif.md`), jamais de la
liste des AC ni de la liste des maquettes — des objectifs tires des AC rediffuseraient la
conception qu'on cherche justement a retirer. Pour un type absent du QUOI (l'administrateur
interne, typiquement), l'objectif se derive de **la raison d'etre du role** : « tu dois pouvoir
regler un litige signale par un client », pas d'une liste d'ecrans.

Au moins un objectif du lot est un parcours **en deux etapes** (creer puis retrouver, envoyer
puis suivre, publier puis repondre).

## 1. La discipline est SOUSTRACTIVE

Ce qui decide de ce qu'un agent voit n'est pas la consigne, c'est **ce qu'on lui met sous les
yeux**. Un testeur qui a lu `routes.md` ne peut pas ne pas trouver la page. (Meme mecanique que
la regle des 15 points de `/brick-mockup-transcription`, et que la propriete mesuree sur les
chartes : le consommateur imite l'artefact qu'on lui donne.)

On lance donc des sous-agents a qui l'on donne **exactement quatre choses** :

1. une **persona** : qui il est, son metier, qu'il n'est pas informaticien, que personne ne l'a
   forme ;
2. son **objectif metier, formule comme une personne le dirait** (« tu viens de recevoir tes
   identifiants, tu veux encaisser la seance d'hier ») ;
3. le **cadre**, mot pour mot — en mode maquette : « ce sont des ecrans dessines, **rien n'est
   branche** : un formulaire ne s'enregistre pas, une recherche ne cherche pas, un bouton
   d'action ne produit rien. C'est normal, ne le signale pas. » ;
4. l'**URL de depart** (voir le tableau des deux modes) et, en mode application, ses identifiants.

**Et rien d'autre.** Ni criteres d'acceptance, ni routes, ni parcours, ni data model, ni
maquettes, ni acces au depot.

Regles a ecrire dans le brief de chaque agent :
- aucun outil de lecture de fichier (Read / Grep / Glob), aucune commande shell hors
  `playwright-cli` ;
- **aucune URL tapee en dehors de celle de depart.** Tout se trouve en cliquant. Ne pas trouver
  un ecran est un **constat a rapporter**, pas un obstacle a contourner ;
- aucune adresse « logique » devinee (`/admin`, `/settings`, `/quotes/new`), meme bloque ;
- en mode maquette, **le hub `/mockups` et le lien « Hub mockups » sont interdits d'usage** :
  ils n'existeront pas dans le produit. « Si tu y atterris, reviens en arriere. » Sans cette
  regle, la classe « navigabilite » disparait par construction ;
- budget ~50 commandes de navigateur en mode maquette, ~70 en mode application ; trois tours en
  rond au meme endroit = abandon a consigner.

**Faire respecter la soustraction, pas seulement l'ecrire.** Apres chaque run, relire le
transcript du sous-agent et verifier qu'il n'a lu aucun fichier du depot, lance aucune commande
hors `playwright-cli` et tape aucune autre URL que celle de depart. Un run qui a triche est
**jete, pas rattrape**. (Sur 33 runs mesures : 0 triche — mais c'est le controle qui rend la
mesure defendable, pas la declaration de l'agent sur lui-meme.)

## 2. Ce que l'agent rend

Pas un tableau de conformite. **Un recit :**

1. objectif atteint OUI / PARTIELLEMENT / NON, en une phrase ;
2. le chemin reellement suivi, ecran par ecran (titre + adresse affichee), avec le nombre de clics ;
3. les **points de friction**, numerotes : ou il etait, ce qu'il cherchait, ce qu'il **s'attendait**
   a trouver, ce qu'il a trouve a la place, ce qu'il a essaye, les clics perdus ;
4. les **abandons** : ce qu'il n'a pas pu faire du tout, l'ecran exact ou il a renonce, et — en
   mode maquette — **s'il a vu l'ecran manquant ailleurs ou nulle part** ;
5. ce qui lui a paru clair et bien fait (ce n'est pas une chasse aux sorcieres) ;
6. les libelles et messages mal compris, cites mot pour mot.

Consigne finale : « ne fais aucune hypothese sur la cause technique ; decris ce que tu vois, pas
ce que tu supposes. »

## 3. Le verificateur : indissociable, jamais optionnel

**Un agent qui se perd n'est pas la preuve qu'un humain se perd.** 28 a 31 % des signalements en
mode application, 9 a 14 % en mode maquette, ne tiennent pas l'examen — et surtout **l'agent est
incapable de savoir lesquels** : ses erreurs les plus confiantes venaient de **deux tirages
independants, avec preuves chiffrees a l'appui**. Sans verificateur, cette methode produit 45 a
70 % de bruit.

Chaque friction et chaque abandon passe donc devant un **sous-agent verificateur distinct**,
celui-la avec le depot et l'app (ou l'inventaire des maquettes) sous les yeux. Deux questions,
dans cet ordre :

1. **L'ecran vise existe-t-il ?** (mode maquette : dans le lot. Mode application : dans l'app.)
2. Si oui : **un chemin cliquable y mene-t-il, depuis un ecran que l'utilisateur pouvait
   atteindre au moment ou il etait bloque, et ce chemin est-il annonce** — le libelle dit-il ce
   qu'il fait, dans les mots du metier ? Un chemin qui n'existe qu'en connaissant l'URL, ou
   (mode maquette) qui ne passe que par le hub, ne compte pas.

Verdicts, et ceux-la seulement :

- **DEFAUT DE NAVIGABILITE** (mode maquette) / **DEFAUT REEL** (mode application) — l'ecran
  existe, aucun chemin n'y mene de la ou l'utilisateur etait, ou le chemin existe et son libelle
  ne l'annonce pas. En mode application il rejoint le cahier de recette au statut KO et
  **commande le verdict** (regle du defaut connu).
- **TROU DE PERIMETRE** (mode maquette) — l'ecran que le parcours exige **n'existe nulle part
  dans le lot**. Dire en une phrase ce qu'il devrait contenir. **C'est la classe qui commande** :
  un ecran nouveau doit entrer dans le lot **avant** la validation client, sinon il sera dessine
  pendant le code, hors validation.
- **NORMAL — MAQUETTE MOCKEE** (mode maquette) — controle inerte, formulaire qui n'enregistre
  pas, recherche qui ne cherche pas, alors qu'un autre chemin visible mene au meme endroit.
- **INCOMPETENCE DE L'AGENT** — le chemin existait, annonce, la ou quelqu'un qui cherche cette
  chose regarderait. Citer le fichier de vue et le libelle exact.
- **INDECIDABLE** — jugement de gout, decision produit non documentee, champ manquant sur un
  ecran existant. Remonte comme question, pas comme bug.
- **ARTEFACT DE MESURE** — deux runs ont ecrit sur le meme compte, une donnee est apparue sans
  que l'agent l'ait creee.
- **HORS PERIMETRE ANNONCE** — element grise ou badge « Brique N ». **Attention** : si la
  fonction est reellement implementee, ou si l'ecran est dans le lot courant, et qu'elle est
  pourtant inatteignable ou annoncee indisponible, ce n'est pas hors perimetre, c'est un defaut.

Le verificateur rend un tableau — `Ref | ce que l'utilisateur cherchait | ecran present (fichier)
| chemin (source + libelle) | annonce ? | verdict | preuve en une ligne | vu par N agents` — plus
le ou les **rendements** (defauts / signalements arbitrables) et une **note de severite honnete**
(« j'ai classe large ou serre, voici les items limites »).

**Il fusionne les doublons entre objectifs.** Ce n'est pas cosmetique : sans fusion le
denominateur double et le rendement se divise par deux.

**Un rendement cumule sous 20 % veut dire que les objectifs etaient mal calibres** : on les
refait, on ne publie pas la liste.

## 4. Pieges de mise en oeuvre, tous payes en mesure

- **Deux tirages par objectif au minimum.** 12 des 34 defauts d'une passe n'ont ete vus que par
  un agent sur deux. Le doublage sert une seconde fois : il demasque un **rapport entier de faux
  positifs** (les trois incompetences d'un lot venaient toutes du meme agent, sur un bandeau
  d'actions qu'il n'avait jamais regarde). Un troisieme tirage, mesure, n'apporte plus que du
  confirmatoire.
- **Un compte par run, ou runs serialises** (mode application). Deux agents sur le meme compte
  produisent des devis en double, des compteurs qui bougent, des relances deja datees du jour :
  12 faux signalements sur un seul projet. Sans objet en mode maquette (GET seuls, verifie :
  16 agents en parallele sans interference).
- **Ne pas inventer de premisse.** Un objectif qui suppose un etat absent du jeu canonique
  (« une annonce est hors ligne, un compte est bloque ») fait echouer l'agent pour une raison
  qui n'est pas le produit.
- **Le hub interdit des deux cotes** (mode maquette) : a l'agent (« ne l'utilise jamais ») et au
  verificateur (« un chemin qui n'existe que par le hub ne compte pas »). Oublier le second
  annule la mesure.
- **Faire ecrire le livrable tot.** Un verificateur qui lit tout avant d'ecrire ne rend rien :
  qu'il pose le squelette de son fichier des son deuxieme appel d'outil et le remplisse au fil
  de l'eau, avec un budget d'appels explicite.

## 5. Ce que cette methode ne remplace pas

Elle est **complementaire**, pas substituable : sur tout le corpus mesure, les deux bras ne se
recouvrent qu'en **un seul point**. L'agent naif ne voit **rien** de ce qui exige :

- une **specification** — fuite de montants, patronyme revele sans double accord, perimetre d'un
  agregat, document joint sans ecran de saisie. Il a lu un tableau de bord faux de 3 000 € et l'a
  trouve excellent. Il ne sait pas ce qui **devrait** etre la, il ne bute que sur ce que son
  objectif exige ;
- un **second role ou un champ forge** — fuites cross-tenant, jeton en clair dans les logs. Deux
  agents etaient sur un compte sans droit facturation, ont vu le bouton interdit, et ne l'ont pas
  clique ;
- un **instrument** — mobile 390 px (41 pages debordaient dans un lot, **aucun** des 17 recits ne
  le mentionne), parite maquette, PDF relu, e-mail expedie ;
- la **vraisemblance** — 38 chiffres fabriques dans un lot, dont une adresse produite par une
  table de rues ecrite dans la vue, et une timeline generique que les agents ont **louee** ;
- le **code** — cle stockee jamais lue, colonne morte, 500 latent, promesse d'interaction sans
  mecanique nommee ;
- l'**argent et le droit** — 12 selecteurs preselectionnes qui feraient partir un devis au nom du
  mauvais client. Un selecteur preselectionne **facilite** la vie de l'utilisateur naif : il ne le
  gene jamais.

**Et une limite a annoncer sans la maquiller : la methode ne predit pas les ecrans que le code
inventera.** Mesuree contre deux applications livrees, sur 30 ecrans construits sans maquette :
**0 predit**. C'est ce constat qui a impose l'enumeration des types d'utilisateurs (section 0) ;
le gain attendu de cette correction est **estime, pas encore mesure**.

## Ligne a ajouter au rapport de la review appelante

```
## Recette naive: T types d'utilisateurs enumeres, U traverses (non traverses: [liste + raison])
##   — N runs (U personas x P objectifs derives du QUOI x 2 tirages), verificateur distinct OUI/NON
##   — bruts: A, arbitrables: B, defauts: C (rendement C/B) [maquette: navigabilite / perimetre separes]
##   — soustraction verifiee sur les N traces: 0 lecture du depot, 0 URL tapee hors URL de depart
##   — [maquette] trous de perimetre: [liste] → ecrans a dessiner AVANT la presentation au client
```

## Dose

Mesuree : ~500 k jetons par brique en mode application (3 runs + 1 verificateur), ~950 k par lot
en mode maquette (4 objectifs x 2 tirages + 1 verificateur). **Ces doses supposaient des personas
choisies a l'intuition** ; avec l'enumeration de la section 0 la dose suit le nombre de types
enumeres, un objectif minimum par type, deux tirages chacun.

## Ensuite

→ mode maquette : les trous de perimetre repartent en correction de maquette **avant** le client,
et la gate de `brick-mockup-reanalyse` verifie qu'ils sont fermes.
→ mode application : les defauts rejoignent le cahier de recette au statut KO et commandent le
verdict de `brick-code-review`.
