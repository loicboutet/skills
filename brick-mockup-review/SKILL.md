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

### 1b. Traversee naive du lot (BLOQUANT si un trou de perimetre sort)

Tout le reste de cette review verifie **ce qui est la**. Elle ne peut pas voir ce qui **manque** :
le relecteur deroule la liste des maquettes, la matrice AC part des AC, les parcours partent de
`user_journeys.md` — trois documents ecrits par la meme chaine que les maquettes. Un parcours
qu'on ne peut pas terminer dans le lot est un parcours dont les ecrans manquants seront
**inventes pendant le code**, hors validation client.

**Derouler `~/.claude/skills/recette-naive/SKILL.md`, en MODE MAQUETTE.** La methode y est
entiere : enumeration des types d'utilisateurs, discipline soustractive et son controle de trace,
verificateur distinct obligatoire, verdicts, pieges. Ce qui est propre a ce stade :

- **Le cadre est dit a l'agent** : rien n'est branche, un bouton inerte est normal et ne se
  signale pas. Sans ca, chaque bouton mort remonte comme un bug et le rapport devient illisible.
- **Le hub `/mockups` est interdit** a l'agent ET au verificateur. Il n'existera pas dans le
  produit et rend tout ecran atteignable en un clic : l'oublier fait disparaitre la classe
  « navigabilite » par construction.
- **Le verificateur tranche contre l'inventaire du bloc precedent**, pas contre un comportement.
- **Deux classes en sortie.** Defaut de navigabilite (l'ecran existe, rien n'y mene) : correction
  de maquette. **Trou de perimetre** (l'ecran que le parcours exige n'existe nulle part) :
  **c'est la classe qui commande**, l'ecran doit entrer dans le lot AVANT la validation client,
  sinon il sera dessine pendant le code. C'est pour cette asymetrie de cout que la traversee est
  ici et pas a la reanalyse : un `link_to` se repare a tout moment, un ecran nouveau se revalide.

Rendements mesures (08/2026, deux lots) : navigabilite 24 % et 34 %, perimetre 12 % et 14 %.
Dose : ~950 k jetons par lot, et elle suit le nombre de types d'utilisateurs enumeres.

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
