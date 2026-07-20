---
name: brick-review
description: "Pre-livraison : cahier de recette, suite de tests, gap analysis, pixel match, UX, securite. Utilise /brick-review avant de livrer une brick au client."
---

# Brick Review

Validation pre-livraison d'une brick. La review commence par l'ecriture du
CAHIER DE RECETTE, puis la suite de tests qui le fait passer, puis les checks
complementaires.

## Quand utiliser

- Avant de livrer une brick au client
- Avant de passer a la brick suivante
- Quand l'utilisateur demande un check global

## Scope check

Avant la review, verifier qu'on n'a pas implemente de features hors spec :
- [ ] Tout le code implemente correspond a un critere d'acceptance
- [ ] Pas de features "bonus" non demandees
- [ ] Les changements de scope sont documentes dans les specs

## Process

### 1. Cahier de recette (AVANT les tests)

**Fichier standardise : `doc/memory/brick-{N}/recette.md`** (un par brick ;
mettre a jour l'existant si la brick evolue, ne jamais en creer un deuxieme).

Le cahier de recette liste TOUT ce qui doit etre vrai pour livrer, en
criteres courts, testables, traces. C'est lui qui pilote la suite de tests,
pas l'inverse. L'ecrire AVANT d'ecrire ou completer les tests.

#### Format

```markdown
# Recette — Brick #{N} : {nom}

Perimetre : {ce que couvre cette recette}
Hors perimetre : {explicitement exclu, avec raison}
Legende : ✅ = test automatise (chemin du test) · 🖐 = verification manuelle

## 1. {Domaine fonctionnel}

| ID | Critere | AC lie | Test |
|----|---------|--------|------|
| R{N}-1.1 | Un {role} peut {action} et voit {resultat} | AC1.2 | ✅ spec/... |
| R{N}-1.2 | {cas limite} ne {casse pas / ne fuit pas} | — | ✅ spec/... |

## Limites connues de l'environnement de test
- {ce qui n'est testable qu'a la main, et pourquoi}

## Criteres de sortie
La recette est passee quand : tous les ✅ sont verts, tous les 🖐 verifies,
aucune ligne sans statut.
```

Regles de redaction (issues des standards UAT) :
- **Un critere = un objectif verifiable**, formule en langage metier
  ("le client voit ses factures triees"), pas en termes techniques
  ("le scope .recent fonctionne"). Precondition et resultat attendu
  implicites ou explicites, jamais ambigus.
- **Chaque critere d'acceptance (doc/memory/acceptance_criteria.md) doit
  apparaitre** dans au moins un critere de recette (tracabilite AC ↔ recette
  ↔ test). Un critere de recette sans AC = cas technique/tordu, colonne AC
  a "—".
- **Chaque critere happy path appelle son negatif** : si "peut creer X",
  alors "ne peut pas creer X invalide / sans droit".
- IDs stables `R{N}-section.item` : on ne renumerote jamais, on ajoute.

#### Taxonomie des cas tordus — a passer SYSTEMATIQUEMENT

Pour chaque feature de la brick, derouler cette checklist et creer un
critere pour chaque cas pertinent (c'est la qu'on trouve les vrais bugs) :

1. **Securite / cloisonnement**
   - IDOR : acceder a la ressource d'un autre (id devine dans l'URL)
   - Cross-tenant / cross-compte : donnees d'un autre client invisibles
   - Roles : chaque role interdit est effectivement refuse (y compris
     non connecte) ; params/tokens forges rejetes proprement
   - Mass assignment : champs sensibles non permis dans les forms
   - **EXCEPTION mockups** : les vues sous `/mockups` (namespace `mockups/`)
     sont volontairement accessibles sans authentification. C'est un choix
     assume (reference visuelle statique, sans donnees reelles). Ne PAS le
     signaler comme faille : ne verifier l'authentification/le cloisonnement
     que sur les vues finales implementees, jamais sur `/mockups`.
2. **Etats degrades**
   - Collection vide, association nil, ressource orpheline ou archivee
   - Session/reference perimee (objet supprime apres coup) → fallback, pas de 500
   - Service externe down / mal configure → degradation propre
3. **Donnees limites**
   - Apostrophes, quotes, unicode, HTML dans les champs texte (injection/echappement)
   - Casse des emails, espaces parasites
   - Bornes : dates limites (annee precedente, fuseau), montants a virgule
     francaise, longueurs max, 0 et negatifs
4. **Idempotence / re-jeu**
   - Double soumission du meme formulaire
   - Re-creation apres suppression/annulation
   - Meme action re-jouee = pas de doublon ni de facturation double
5. **Flux transverses**
   - Emails : envoyes, au bon destinataire, avec des LIENS SUR LE BON HOST
   - Jobs asynchrones : enqueues avec les bons arguments
   - Fichiers : upload, download, types interdits
6. **i18n / formats**
   - Dates affichees au format attendu (locale fr vs env de test)
   - Messages d'erreur comprehensibles cote client

### 2. Suite de tests : faire passer la recette

Ecrire ou completer les tests pour que CHAQUE critere ✅ de la recette ait
son test, puis iterer jusqu'au vert :

```bash
rails test 2>&1 | tail -20
```

- [ ] Chaque critere ✅ de la recette pointe vers un test qui existe
- [ ] Chaque test cite son ID de recette en commentaire (`# R{N}-1.2`)
- [ ] Tous les tests passent, aucun skip sans raison
- [ ] Les criteres 🖐 sont verifies a la main (navigateur) et coches
- [ ] Si un test revele un bug → le corriger fait partie de la review
      (le test reste comme regression)

Ne JAMAIS affaiblir un critere pour faire passer un test : si le
comportement reel est different du critere, c'est soit un bug (fix), soit
un changement de scope (documenter dans les specs, puis ajuster la recette).

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

### 4. Pixel match (conformite aux mockups)

Le respect des mockups est LE point critique cote client. Pour chaque page implementee,
la comparer a son mockup de reference (`app/views/mockups/...`), section par section.

Generer un tableau des differences :

```markdown
## Pixel match - Brick #X

| Page implementee | Mockup de reference | Differences detectees | Statut |
|------------------|---------------------|------------------------|--------|
| users/index      | mockups/users/index | aucune                 | OK     |
| users/show       | mockups/users/show  | bouton "Modifier" deplace dans le header | A CORRIGER |
```

Verifier :
- [ ] Chaque page a un mockup de reference correspondant
- [ ] Markup HTML / classes Tailwind identiques au mockup (seule la liaison de donnees change)
- [ ] Aucune section ajoutee / retiree / reordonnee par rapport au mockup
- [ ] Aucun faux objet (hash / OpenStruct) restant dans un controleur reel
- [ ] Toute difference est soit corrigee, soit justifiee par une mise a jour de spec documentee

**Toute ligne "A CORRIGER" non justifiee bloque la livraison** (verdict NEEDS FIXES).

### 5. Review UX

Verifier les parcours utilisateurs de `doc/memory/user_journeys.md` :
- [ ] Chaque parcours est fonctionnel de bout en bout
- [ ] Les etats d'erreur sont geres (formulaire invalide, 404, etc.)
- [ ] Les messages flash sont presents et clairs
- [ ] La navigation est coherente

### 6. Review Code (vanilla Rails)

- [ ] Controllers < 7 actions (sinon extraire)
- [ ] Pas de logique business dans les controllers
- [ ] Modeles avec validations
- [ ] Pas de JS custom quand Turbo/Stimulus suffit
- [ ] Pas de N+1 queries (utiliser `includes`)
- [ ] Fichiers < 400 lignes

### 7. Repetition : repasser les points de friction

On ne relit pas toute la brick avec la meme attention. Les bugs et les
mauvaises decisions sont concentres la ou le dev a coince, pas dans le CRUD
qui est sorti tout seul. Reconstituer la liste des points de friction a
partir des taches (`doc/memory/brick-{N}/tasks/`), des commits et de
l'historique de la conversation :

- endroits ou un test a echoue plusieurs fois avant de passer
- code reecrit, deplace ou renomme en cours de route
- decisions prises sous contrainte de temps, ou notees "a verifier plus tard"
- TODO / FIXME / commentaires d'excuse laisses dans le code
- fichiers les plus remanies sur la brick :
  `git diff --stat {base}..HEAD | sort -k3 -n | tail -10`
- endroits ou il a fallu demander de l'aide a l'utilisateur

Pour chacun, relire le code a froid et se poser une seule question : est-ce
que c'est la solution qu'on choisirait maintenant, en sachant ce qu'on sait
a la fin de la brick ? Ce qui reste douteux devient une ligne du rapport
(section Issues), pas un souvenir.

### 8. Security check

(Les cas de securite de la taxonomie sont deja dans la recette avec leurs
tests ; ici on verifie le socle.)
- [ ] Strong parameters sur tous les controllers
- [ ] Autorisation verifiee (l'utilisateur a acces a la ressource)
- [ ] Pas de donnees sensibles dans les logs
- [ ] CSRF protection active

> Rappel : l'acces libre aux vues `/mockups` (sans authentification) est un
> choix delibere et accepte, pas une faille. Ne pas le remonter dans le rapport.

### 9. Rapport

Generer un rapport dans `doc/memory/brick-{N}/review.md` :

```markdown
# Review Brick #X - [Date]

## Recette: X/Y criteres passes (✅ automatises: A, 🖐 manuels: M)
## Tests: X/Y passing
## Acceptance criteria: X/Y couverts par la recette
## Pixel match: X/Y pages conformes
## Points de friction repasses: X (dont Y encore douteux)
## Gaps: [liste]
## Issues: [liste]
## Bugs trouves par la recette: [liste — c'est un bon signe, pas un mauvais]
## Verdict: READY / NEEDS FIXES
```

## Sortie

Si READY → informer l'utilisateur, pret a livrer. Le cahier de recette est
un LIVRABLE : il peut etre partage au client comme preuve de couverture.
Si NEEDS FIXES → lister les fixes. Pour chaque fix, utiliser `/brick-bugfix`
(test qui reproduit → fix → verify), puis re-derouler la recette.
