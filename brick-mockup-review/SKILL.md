---
name: brick-mockup-review
description: "Verifie qu'une serie de mockups en cours de validation respecte les regles de process (scope par brique, partials, sync specs, outil de capture). Utilise /brick-mockup-review avant de presenter les mockups au client."
---

# Brick Mockup Review

Controle qualite des mockups AVANT presentation au client. Verifie que les regles de process
sont appliquees, synchronise les mockups avec les specs, et confirme que l'outil de capture
de feedback est en place. A lancer sur des mockups en cours de validation.

## Quand utiliser

- Mockups crees (via `/brick-mockup-build`) et prets a etre montres au client
- Reprise d'une serie de mockups existante dont on veut verifier la conformite
- Avant chaque presentation client d'un lot de mockups

## Pre-requis

- Les mockups existent dans `app/views/mockups/`
- `doc/memory/routes.md`, `data_models.md`, `acceptance_criteria.md`, `user_journeys.md` existent
- `doc/memory/style_guide.html` existe

## Process

Pour chaque check : lister ce qui est OK, ce qui est A CORRIGER. Ne rien corriger silencieusement.

### 1. Couverture (mockups vs routes)

Comparer `doc/memory/routes.md` avec les vues de `app/views/mockups/` :
- [ ] Chaque route a un mockup correspondant
- [ ] L'index `/mockups` liste TOUTES les pages

#### Liens entrants : l'inventaire, hub exclu

Le controle actuel n'a pas de definition operante, et il a ete implemente comme un `grep` de
`href="#"`. C'est la mesure des liens **sortants** morts. Elle ne dit rien de la question qui
compte : **depuis l'ecran d'accueil de son role, l'utilisateur peut-il atteindre cet ecran en
cliquant ?** (Mesure 08/2026 : une review a ecrit « Aucune impasse (0 `href="#"`) ✅ » sur un lot
ou l'ecran de modification d'un devis et la vue employe n'avaient aucun lien entrant. Le lot est
parti au client ainsi, et 4 utilisateurs sur 8 ont cherche la vue employe.)

**La regle capitale, sans laquelle le controle ne mesure rien : le hub `/mockups` ne compte pas.**
C'est un index de revue interne ; il n'existera pas dans le produit et il rend tout ecran
atteignable en un clic. Le lien « Hub mockups » pose dans les gabarits non plus.

Produire l'inventaire des liens entrants, hub exclu :

```bash
bin/rails routes | grep mockups | awk '{print $2, $3}' | grep GET | sort -u > /tmp/routes.txt
python3 $SK/mockup_inventory.py http://localhost:{port} /tmp/routes.txt /mockups \
  doc/memory/mockups/inventaire.md
```

Il rend, pour chaque ecran route du namespace : URL, titre, liens sortants **avec leur libelle**,
boutons, et **liens entrants hub exclu**. Tout ecran marque « AUCUN » est un **candidat
orphelin**.

- [ ] Chaque candidat orphelin est traite : soit on ajoute le lien entrant, soit on ecrit
      pourquoi il n'en a pas besoin (page d'erreur, ecran atteint par un lien d'e-mail
      d'activation, ecran de demonstration assume).
- [ ] **Un « AUCUN » n'est jamais un verdict.** Un chemin porte par un `<button>` Stimulus est
      invisible a un collecteur de `href` : chaque candidat se tranche **au navigateur**, en
      essayant de l'atteindre. (Mesure 08/2026 : deux ecrans de comparaison sortis « AUCUN »
      etaient atteignables par des cases a cocher Stimulus annoncees en clair sur la page. C'est
      le seul point sur lequel trois arbitres ont diverge.)
- [ ] Le controle est **rejoue apres les corrections de la boucle mockup** : une correction cree
      des orphelins. (Mesure 08/2026 : un bloc « Pense-bete » ajoute apres le releve des parcours
      n'a jamais ete renavigue, et son « Voir tout → » mene a un ecran qui ne contient aucune de
      ses lignes.)

Ordre de grandeur observe : 5 candidats orphelins sur 52 ecrans, 11 sur 51.

---

- [ ] **Toute page d'index/liste a une pagination visible** (partial
      `mockups/shared/_pagination` ou equivalent « Charger plus »). Verifier en
      listant les vues : `grep -rL "pagination" app/views/mockups --include="index*.html.erb"`
      — chaque fichier remonte par ce grep est une liste sans pagination a corriger.
      Une liste avec 3 lignes fictives et pas de pagination = a refaire (15-25
      lignes + pagination), sinon le client valide une page irrealiste

**Pages systeme obligatoires** (souvent oubliees car absentes de `routes.md`) :
- [ ] Page de **connexion** (login) si l'app a de l'authentification
      (+ inscription / mot de passe oublie si prevus dans les specs)
- [ ] Pages d'**erreur** : 404 (introuvable) et 500 (erreur interne),
      aux couleurs du style guide (pas les pages Rails par defaut)
- [ ] Ces pages figurent dans l'index `/mockups` et respectent le layout adapte
      (login = layout minimal, pas la sidebar admin)

### 1b. Traversee naive du lot : quelqu'un qui ne sait rien peut-il finir son travail ?

Toute la suite de cette review verifie **ce qui est la**. Elle ne peut pas voir ce qui **manque** :
un relecteur deroule la liste des maquettes, la matrice AC ↔ maquette part des AC, les parcours
navigues partent de `user_journeys.md`. Ces trois documents ont ete ecrits par la meme chaine que
les maquettes. Un parcours qu'on ne peut pas terminer dans le lot est un parcours dont les ecrans
manquants seront **inventes pendant le code**, hors validation client.

Cette section est le seul endroit du process ou quelqu'un traverse le lot **sans le connaitre**.

#### La discipline est SOUSTRACTIVE

On lance des sous-agents a qui l'on donne **exactement quatre choses** :

1. une **persona** (qui il est, son metier, qu'il n'est pas informaticien, que personne ne l'a
   forme) ;
2. un **objectif metier formule comme une personne le dirait**, derive du **QUOI**
   (`doc/memory/objectif.md`), **jamais des AC ni de la liste des maquettes** ;
3. le **cadre du stade maquette**, mot pour mot : « ce sont des ecrans dessines, **rien n'est
   branche** — un formulaire ne s'enregistre pas, une recherche ne cherche pas, un bouton
   d'action ne produit rien. C'est normal, ne le signale pas. » ;
4. l'**URL de depart** : **l'ecran d'accueil de son role**, pas l'ecran de connexion. (Un lot de
   maquettes a le droit d'avoir un formulaire de connexion inerte : le hub y remplace
   l'authentification. Partir de la connexion bloque tous les runs au premier clic.)

**Et rien d'autre.** Ni criteres d'acceptance, ni routes, ni parcours, ni data model, ni acces au
depot.

Regles ecrites dans le brief de chaque agent :
- aucun outil de lecture de fichier (Read / Grep / Glob), aucune commande shell hors
  `playwright-cli` ;
- **aucune URL tapee en dehors de celle de depart.** Ne pas trouver un ecran est un **constat a
  rapporter**, pas un obstacle a contourner ;
- **le hub des maquettes et le lien « Hub mockups » sont interdits d'usage** : ils n'existeront
  pas dans le produit. « Si tu y atterris, reviens en arriere. » Sans cette regle, la classe
  « navigabilite » disparait par construction ;
- budget ~50 commandes de navigateur ; trois tours en rond au meme endroit = abandon a consigner.

**Ce qui est normal et ce qui est a signaler**, a ecrire dans le brief, sinon chaque bouton mort
remonte comme un bug :
- un bouton qui ne reagit pas **alors qu'un autre chemin visible mene a l'ecran suivant** →
  normal, ne pas signaler ;
- un ecran necessaire, **qui existe**, que **rien ne permet d'atteindre en cliquant** depuis la ou
  il etait → a signaler ;
- un libelle sur lequel il n'aurait pas clique parce qu'il ne dit pas ce qu'il fait → a signaler ;
- un ecran dont son travail a besoin et qu'il **ne voit nulle part** → a signaler, en disant ce
  qu'il devrait contenir et a quel moment il manque ;
- une promesse ecrite (compteur, bandeau, « vous recevrez… ») sans aucune suite visible → a
  signaler.

**Faire respecter la soustraction, pas seulement l'ecrire.** Apres chaque run, relire le
transcript et verifier 0 lecture du depot, 0 commande hors `playwright-cli`, 0 URL tapee. Un run
qui a triche est **jete, pas rattrape**. (Sur 17 runs mesures : 0 violation.)

**Ce que le stade maquette economise, et c'est verifie** : les lots n'exposent que des routes GET,
les donnees sont en dur dans les controleurs de maquette, rien ne s'ecrit. **Pas de comptes a
provisionner, pas de runs a serialiser, aucun artefact de labo a ecarter.** 16 agents ont
travaille en parallele sur les memes ecrans sans se voir.

#### Ce que l'agent rend

Pas un tableau de conformite. **Un recit** : objectif atteint OUI / PARTIELLEMENT / NON ; le
chemin reellement suivi ecran par ecran (titre + adresse) avec le nombre de clics ; les **points
de friction** numerotes (ou il etait, ce qu'il cherchait, ce qu'il **s'attendait** a trouver, ce
qu'il a trouve, les clics perdus) ; les **abandons**, et pour chacun **s'il a vu l'ecran manquant
ailleurs ou nulle part** ; ce qui lui a paru clair ; les libelles mal compris, cites mot pour mot.

Consigne finale : « ne fais aucune hypothese sur la cause technique ; decris ce que tu vois. »

#### Le verificateur : indissociable, et il tranche contre l'INVENTAIRE

**Un agent qui se perd n'est pas la preuve qu'un humain se perd.** 9 % a 14 % des signalements
arbitrables ne tiennent pas l'examen — et surtout, l'agent est **incapable de savoir lesquels** :
deux agents ont declare « la comparaison n'existe nulle part » sur un ecran qui existe et qu'un
troisieme a atteint.

Chaque friction et chaque abandon passe donc devant un **sous-agent verificateur distinct**, avec
le depot, l'inventaire du bloc A et le lot navigable sous les yeux. Deux questions, dans cet
ordre :

1. **L'ecran vise existe-t-il dans le lot ?**
2. Si oui : **un chemin cliquable y mene-t-il, depuis un ecran que l'utilisateur pouvait
   atteindre au moment ou il etait bloque, et ce chemin est-il annonce** (le libelle dit ce qu'il
   fait, dans les mots du metier) ? Un chemin qui n'existe que par le hub ou en connaissant l'URL
   ne compte pas.

**Six verdicts, et six seulement :**

- **DEFAUT DE NAVIGABILITE** — l'ecran **existe** dans le lot, aucun chemin cliquable n'y mene de
  la ou l'utilisateur etait, ou le chemin existe et son libelle ne l'annonce pas. → correction de
  maquette, a faire avant le client.
- **TROU DE PERIMETRE** — l'ecran que le parcours exige **n'existe nulle part dans le lot**. Dire
  en une phrase ce qu'il devrait contenir. → **c'est la classe qui commande** : un ecran nouveau
  doit entrer dans le lot **avant** la validation client, sinon il sera dessine pendant le code.
- **NORMAL — MAQUETTE MOCKEE** — controle inerte, formulaire qui n'enregistre pas, recherche qui
  ne cherche pas, alors qu'un autre chemin visible mene au meme endroit. Ne compte pas.
- **INCOMPETENCE DE L'AGENT** — le chemin existait, annonce, la ou quelqu'un qui cherche cette
  chose regarderait. Citer le fichier de vue et le libelle exact.
- **INDECIDABLE** — jugement de gout, incoherence du jeu de donnees, libelle mal compris, champ
  manquant sur un ecran existant, decision produit non documentee. → remonte comme question.
- **HORS PERIMETRE ANNONCE** — element grise ou badge « Brique N ». **Attention** : si l'ecran
  est dans le lot courant et pourtant inatteignable, ce n'est pas hors perimetre, c'est un defaut
  de navigabilite.

Le verificateur rend un tableau — `Ref | ce que l'utilisateur cherchait | ecran present dans le
lot ? (fichier) | chemin (source + libelle) | annonce ? | verdict | preuve en une ligne | vu par
N agents` — plus **deux rendements separes** (navigabilite / arbitrables et perimetre /
arbitrables) et une note de severite honnete. Un rendement cumule sous 20 % veut dire que les
objectifs etaient mal calibres : on les refait, on ne publie pas la liste.

**Il fusionne les doublons entre objectifs.** Ce n'est pas cosmetique : sans fusion, le
denominateur double et le rendement se divise par deux.

#### Quatre pieges de mise en œuvre, tous payes en mesure

- **Deux tirages par objectif au minimum.** 5 des 12 defauts d'un lot n'ont ete vus que par un
  agent sur deux. Et le doublage sert une seconde fois : il demasque un **rapport entier de faux
  positifs** (les trois incompetences d'un lot venaient toutes du meme agent, sur un bandeau
  d'actions qu'il n'avait jamais regarde). Un troisieme tirage, mesure, n'apporte plus que du
  confirmatoire.
- **Objectifs cales sur ce que le lot represente.** Un objectif qui suppose un ecran absent du lot
  fait echouer l'agent pour une raison qui n'est pas le produit.
- **Le hub interdit des deux cotes.** A l'agent (« ne l'utilise jamais ») et au verificateur (« un
  chemin qui n'existe que par le hub ne compte pas »). Oublier le second annule la mesure.
- **Faire ecrire le livrable tot.** Un verificateur qui lit tout avant d'ecrire ne rend rien :
  qu'il pose le squelette du fichier des son deuxieme appel d'outil et le remplisse au fil de
  l'eau, avec un budget d'appels explicite.

#### Ce que cette section ne remplace pas

Elle est **complementaire**, pas substituable. Le bras naif ne voit **rien** de ce qui exige :

- un **instrument** — les 41 pages d'un lot qui debordaient a 390 px, dont des tableaux coupes en
  silence : les 17 recits travaillent a un seul viewport et **aucun** ne mentionne le mobile ;
- une **specification** — archivage d'un contact absent, documents joints sans ecran de saisie :
  un agent naif ne sait pas ce qui **devrait** etre la, il ne bute que sur ce que son objectif
  exige ;
- de la **vraisemblance** — les 38 chiffres fabriques d'un lot, dont une adresse client produite
  par une table de rues ecrite dans la vue, et une timeline generique que les agents ont
  **louee** ;
- le **code** — les 35 promesses d'interaction sans mecanique nommee, indiscernables d'un bouton
  en attente d'implementation ;
- l'**argent et le droit** — les 12 selecteurs preselectionnes qui feraient partir un devis au nom
  du mauvais client. Un selecteur preselectionne **facilite** la vie de l'utilisateur naif : il ne
  le gene jamais.

Et une limite qu'il faut annoncer sans la maquiller : **le bras ne predit pas les ecrans que le
code inventera.** Mesure contre deux applications livrees, sur 30 ecrans construits sans maquette,
**0 PREDIT, 3 APPROCHE, 22 hors de portee du protocole**. La raison est structurelle : 21 de ces
30 ecrans sont le back-office d'administration, qui n'est dans aucun QUOI, donc dans aucun
objectif derive du QUOI. Si le lot a une surface d'administration, il faut **jouer une persona
d'administrateur en plus** (+2 runs), et savoir que meme la, le gain est estime et non mesure.

### 2. Scope par brique (marquage)

Le client doit comprendre d'un coup d'oeil ce qui est livre maintenant vs plus tard :
- [ ] Les elements des briques suivantes sont grises + badge "Brique 2" / "Brique 3"
- [ ] L'index `/mockups` indique la brique de chaque page
- [ ] Aucun element hors brique courante presente comme livrable sans marquage

### 3. Synchronisation mockups vers specs (CRITIQUE)

Pendant le mockup, on ajoute souvent des elements qui ne sont pas (encore) dans les specs :
un champ, une page, une action, une etape de parcours. Les specs sont la source de verite --
elles doivent rester a jour, sinon ecart specs / mockups / implementation.

Pour chaque element present dans un mockup mais absent des specs :

1. **Le lister** (quoi, sur quelle page).
2. **Proposer l'ajout dans le bon fichier de specs, au bon endroit** :
   - Nouvel attribut affiche -> `data_models.md` (sur le bon modele)
   - Nouvelle page / nouvelle action -> `routes.md` (dans le bon namespace)
   - Nouveau comportement verifiable -> `acceptance_criteria.md` (nouveau AC, numerote)
   - Nouvelle etape de parcours -> `user_journeys.md` (dans le bon parcours/profil)
3. **Demander validation a l'utilisateur AVANT d'ecrire** dans les specs. Ne jamais
   ajouter aux specs silencieusement (cf. regle "Specs = source de verite").

Verifier aussi l'inverse :
- [ ] Tout element des specs (champ, page, parcours) a bien un mockup -> sinon, gap a signaler

Sortie de cette etape : une liste "Elements mockup absents des specs -> proposition d'ajout"
soumise a l'utilisateur.

### 4. Outil interne de capture de feedback

L'outil interne de capture (screenshot + URL + commentaire) sert au client a remonter ses
retours directement depuis les mockups. Verifier qu'il est bien applique :
- [ ] L'outil de capture est integre dans les layouts mockups (present sur chaque page)
- [ ] Il capture bien l'**URL** de la page en plus du screenshot et du commentaire
- [ ] Verification comportementale : naviguer sur 1-2 pages (`playwright-cli`, voir le skill `playwright`), declencher une
      capture, confirmer que screenshot + URL + commentaire partent correctement
- [ ] Aucun mockup n'echappe a l'outil (verifier les layouts admin ET user)

**Installation** : le widget est centralise dans nexrai (app 37). Pour l'integrer
(mockup OU vraie appli), recuperer l'`app_id` + le `secret` via l'outil MCP
`get_feedback_widget(app_id: <ton_app_id>)` (marche aussi sur les projets anciens :
il genere le secret si absent) puis coller le snippet `<script>` retourne.
Guide complet : artefact nexrai `feedback_widget_install` (app 37) —
"Widget de feedback 5000.dev — Guide d'installation".

### 5. Conformite technique

- [ ] Tout est dans le namespace `/mockups` (routes, controleurs, vues)
- [ ] Aucun modele ni migration (donnees fictives dans les controleurs uniquement)
- [ ] Partials extraites pour tout element repetable / reutilisable (cf. `/brick-mockup-build`)
- [ ] Tailwind via le pipeline `tailwindcss-rails` (PAS le CDN)
- [ ] Couleurs custom dans `tailwind.config.js`, jamais en arbitraire (`bg-[#3B82F6]`)
- [ ] Pas de CSS custom hors `application.tailwind.css`

### 6. Conformite au style guide & UX

Avec `doc/memory/style_guide.html` et `doc/memory/user_journeys.md` :
- [ ] Design coherent entre les pages, respecte le style guide
- [ ] Chaque parcours utilisateur est faisable de bout en bout
- [ ] Empty states avec message + CTA
- [ ] Etats d'erreur (formulaire invalide) visibles au moins une fois
- [ ] Actions destructives avec confirmation

### 7. Rapport

Generer `doc/memory/mockups/review.md` :

```markdown
# Mockup Review - [Date]

## Couverture: X/Y pages (vs routes.md)
## Inventaire liens entrants (hub exclu): X ecrans, Y candidats orphelins, Z tranches au navigateur
## Traversee naive: N runs (M personas x P objectifs derives du QUOI), verificateur distinct OUI/NON
##   — bruts: A, arbitrables: B, navigabilite: C (C/B), perimetre: D (D/B)
##   — soustraction verifiee sur les N traces: 0 lecture du depot, 0 URL tapee hors URL de depart
##   — trous de perimetre: [liste] → ecrans a dessiner AVANT la presentation au client
## Pages systeme: login OK/manquant, 404 OK/manquant, 500 OK/manquant
## Scope brique: OK / marquages manquants [liste]
## Sync specs: N elements a ajouter aux specs [liste + proposition]
## Outil capture: OK / NON integre [details]
## Technique & style: OK / issues [liste]

## A CORRIGER avant client:
- [liste priorisee]

## Verdict: PRET POUR CLIENT / A CORRIGER
```

## Sortie

- **PRET POUR CLIENT** -> informer l'utilisateur, mockups presentables.
- **A CORRIGER** -> lister les corrections. Les corrections de mockups passent par
  `/brick-mockup-build` (jamais modifier les specs sans validation, cf. etape 3).

## Ensuite

→ `brick-mockup-video` : filmer les parcours pour la validation client.
