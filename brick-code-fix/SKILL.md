---
name: brick-code-fix
description: "Correction de bug client : regle du defaut connu, comprendre, reproduire avec un test, corriger, chercher le meme bug ailleurs, re-verifier au navigateur, consigner la decision, alimenter la taxonomie de recette et le cahier de recette, surveiller apres deploiement. Utilise /brick-code-fix quand un client signale un probleme."
---

# Brick Bugfix

Le client a toujours raison. Chaque bug suit le meme process : comprendre → reproduire
→ corriger → verifier → generaliser.

> **Modeles et discipline de tour** : ce skill delegue a des sous-agents. Doctrine mesuree,
> commune a toute la chaine, dans `/brick-code-build` (« Repartition des modeles » et
> « Discipline de tour ») : tous les sous-agents en `model: "opus"`, et l'orchestrateur
> n'attend jamais un sous-agent en rendant son tour.

## Regle d'or

**Ne jamais dire "ca marche chez moi"**. Si le client dit que c'est casse, c'est casse.
Notre job c'est de comprendre POURQUOI il voit ce qu'il voit.

## LA REGLE DU DEFAUT CONNU

Ce skill se declenche sur un retour client — mais aussi, et sans exception, des qu'un
defaut de l'une de ces quatre familles est CONSTATE par qui que ce soit, a n'importe
quel moment : **argent** (montant faux, total inexplique, remise du mauvais client),
**permissions** (donnee ou action accessible sans le droit, fuite cross-tenant),
**donnees fausses** (valeur affichee qui ne correspond pas a la base, enregistrement
rattache au mauvais parent), **fuite** (secret ou donnee personnelle exposes).

Deux issues, pas trois : **on corrige**, ou **la livraison ne part pas**. Il n'existe
aucune troisieme voie appelee « consigne », « argumente » ou « a trancher ».
**Interdit** de ranger un tel defaut dans `decisions.md`, `config.md` ou un rapport de
review : **une ligne qui decrit un defaut d'argent ou de permission n'est pas une
decision, c'est un bug ouvert**, et un bug ouvert passe par ici. Un critere de recette
note KO releve du meme traitement, quelle que soit sa famille.

Provenance : audit qualite 08/2026 — un devis emis pour le mauvais client avec la remise
d'un archive (« laisse ouvert et argumente » par la review, livre) ; une mention « FACADE
A TRANCHER » dans `config.md`, cle morte livree.

## Deux regles de decision

- **On decide, on ne demande pas.** Si le fix suppose un choix (quel comportement par
  defaut, quel arrondi, quel libelle, que faire du cas non prevu), on tranche avec un
  defaut motive et on ajoute une ligne a `doc/memory/decisions.md` (date, decision,
  defaut, motif, reversible, « a signaler » si ca touche au QUOI). On ne renvoie une
  question au client que si le bug revele une regle metier qu'aucun defaut raisonnable
  ne peut couvrir, et meme la on propose une reponse.
- **Jamais de fix par fabrication de donnee.** Reparer un ecran vide en y mettant un
  chiffre en dur, une image d'illustration presentee comme reelle, un score par defaut
  ou un exemple de demo : interdit, sans exception. Le bon fix est la vraie donnee, ou
  un **etat vide honnete**.

## Branche

**Demander sur quelle branche travailler** si ce n'est pas precise :
- Bug sur la **prod** (le client le voit en live) → `main`
- Bug sur le **staging** (decouvert pendant le dev) → `staging`

```bash
git branch  # verifier la branche avant de commencer
```

## Process

### 1. Comprendre le retour client

Reformuler le bug en ses propres mots pour prouver qu'on a compris :

```markdown
## Bug report
**Client dit** : "Quand je clique sur Sauvegarder, rien ne se passe"
**On comprend** : Le formulaire d'edition de [ressource] ne submit pas, ou submit
mais pas de feedback visible pour l'utilisateur.
**Contexte probable** : [page, profil utilisateur, navigateur si pertinent]
```

Si le retour est flou, poser des questions PRECISES (page exacte, compte/role, ce qui
se passe apres l'action, reproductible ou non) ; sinon aller chercher le contexte
(**Leexi** pour les conversations recentes, conversations nexrai, screenshots ou videos
demandes au client). Ce sont les seules questions utiles : tout ce qui releve du COMMENT
se tranche.

### 2. Reproduire avec un test

**AVANT de toucher au code**, ecrire un test qui echoue et qui prouve qu'on a compris :
une assertion sur l'effet REEL attendu (redirection, flash, valeur relue en base), pas
sur un code de retour seul.

```ruby
# test/integration/bug_fixes/save_button_test.rb
test "user can save edited profile" do
  sign_in users(:client_user)
  patch user_profile_path, params: { profile: { name: "Updated Name" } }
  assert_redirected_to user_profile_path
  assert_equal "Updated Name", users(:client_user).reload.profile.name
end
```

```bash
bin/rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT echouer. S'il passe, on n'a pas compris le bug : recommencer l'etape 1.
Cas particulier : si le bug n'est reproductible QU'AU navigateur (Turbo, Stimulus,
rendu), le test qui reproduit est un SYSTEM test (`test/system/bug_fixes/`), pas un
test d'integration — lecon de l'audit qualite 08/2026 ("form must redirect" invisible
en integration).

### 3. Diagnostiquer

- Lire les logs (`rails test` donne le stacktrace)
- Verifier le controller (params, autorisation, redirect)
- Verifier le modele (validations, callbacks)
- Verifier la vue (form action, turbo frame, CSRF token, `data-action`, option vide d'un
  select qui porte de l'argent ou un droit)
- Verifier les routes (`bin/rails routes | grep ...`)
- Si le bug depend d'un reglage d'environnement (host, cle, fuseau, provider) :
  confronter `doc/memory/config.md` a l'environnement reel — la cle est-elle definie,
  et le consommateur nomme la lit-il vraiment ?

### 4. Corriger

Ecrire le fix MINIMAL. Pas de refactoring, pas d'ameliorations, juste le fix du bug.
Si le fix change un reglage d'environnement, mettre `config.md` a jour dans le meme
commit (cle, consommateur, valeur par environnement).

Si le fix touche une vue copiee d'une maquette et que la maquette porte le meme defaut
(debordement a 390 px, select sans option vide), **corriger les DEUX cotes** : la
maquette est fausse, la parite doit rester vraie, et la correction est signalee au client.

### 5. Chercher le MEME bug ailleurs

Un bug n'est presque jamais unique : le meme pattern a ete copie-colle.

- `grep` du pattern fautif sur tout le repo (meme helper, meme partial, meme garde
  manquante, meme `dependent:`, meme bloc non protege par `can?`)
- Regarder en priorite : les partials partages, les autres vues copiees du meme mockup,
  les autres controleurs du meme namespace, les autres mailers/PDF si le bug touche une sortie
- Si le bug est de la famille **« moitie du chemin faite »** (colonne ecrite que personne
  ne lit, colonne lue que personne ne saisit), la recherche des soeurs se fait a l'outil :
  ```bash
  ruby ~/.claude/skills/outils-recette/facade_scan.rb readwrite .
  ```
- Chaque occurrence trouvee = MEME traitement (test qui reproduit + fix) dans le meme
  lot de correction. Lister les occurrences dans le commit.

### 6. Verifier

```bash
bin/rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
bin/rails test 2>&1 | tail -20
```

Le test cible DOIT passer, et la suite complete rester verte.

**Re-check navigateur si le bug touche l'UI** (vue, Turbo, Stimulus, CSS, PDF affiche,
mail rendu) : ouvrir la page corrigee avec `playwright-cli`, rejouer le parcours impacte
avec les donnees canoniques, screenshot a l'appui, et **mesurer a 390 px** — bord droit
de l'element le plus a droite <= 390 (hors conteneur a defilement horizontal declare,
hors `position: fixed`, hors element anime), aucun conteneur non defilant en
debordement, aucun champ de saisie sous 120 px. Jamais un verdict sur le seul
`document.documentElement.scrollWidth` : un `overflow-x: clip|hidden` sur `body` le rend
toujours egal a la largeur du viewport. Un fix UI valide uniquement par un test
d'integration n'est PAS valide.

Si le fix touche une migration ou les seeds : rejouer une base fraiche en TROIS
invocations separees (`db:drop`, puis `db:prepare`, puis `db:seed`), verifier la taille
du fichier de base et compter les enregistrements — enchainees, les seeds ecrivent dans
un fichier efface et la commande reussit sur une base vide (classe T16).

### 7. Alimenter la taxonomie ET le cahier de recette

Chaque bug REEL enrichit la taxonomie de recette
(`~/.claude/skills/taxonomie-recette/SKILL.md`, versionnee dans le repo skills
github.com/loicboutet/skills — la mise a jour se pousse dans le REPO, la copie
locale seule est ecrasee au prochain sync) :

- Le bug releve d'une classe existante (T1-T19) → ajouter le cas concret a la
  provenance de la classe, date
- Le bug ne rentre dans aucune classe → creer la classe : nom, methode de
  verification reproductible, provenance (ce bug), date
- Committer la mise a jour de la taxonomie avec le fix

C'est comme ca que la classe sera chassee systematiquement aux briques suivantes : un
bug paye une fois, plus jamais.

**Et une ligne de plus dans le cahier de recette de la brique**
(`doc/memory/brick-{N}/recette.md`), au format rejouable : URL, compte, geste,
observation attendue. Un test de regression prouve le serveur ; cette ligne prouve que
le client, lui, verra la chose corrigee.

### 8. Committer

```
fix: [description courte du bug]

Reported by: [client]
Root cause: [explication technique en 1 ligne]
Occurrences soeurs: [liste, ou "aucune (grep: pattern)"]
Decision: [ligne ajoutee a decisions.md, ou "aucune"]
Taxonomie: [classe T{n} enrichie / creee] — Recette: [ID du critere ajoute]
Test: test/integration/bug_fixes/[test_file].rb
```

Ne PAS push sans demande explicite.

### 9. Apres deploiement du fix

Un fix deploye en prod **rearme la surveillance** : relever GlitchTip a +1 h et +24 h
(`glitchtip_list_issues`, `glitchtip_issue_detail` sur toute issue nouvelle), et rejouer
au navigateur le parcours corrige sur l'URL reelle. Une erreur nouvelle = un nouveau
passage par ce skill.

### 10. Statut, et qui ferme

- Mettre l'issue tracker a jour (`tracker_issue_tool`, action `move`) : `in_progress`
  au demarrage, **`fixed` des que le correctif est deploye et re-verifie sur l'URL
  reelle** (etape 9). `fixed` = « corrige et en ligne », c'est le bout du travail
  de l'agent, il le pose lui-meme, sans attendre personne.
- Informer l'utilisateur, en une ligne, que le fix est en ligne (quoi, ou, comment
  re-verifier).
- La FERMETURE de l'issue (le client a constate que c'est resolu) est le geste de
  l'utilisateur, apres validation du client. L'agent ne la demande pas, ne la fait
  pas, ne la relance pas. Si le client revient dessus, c'est un nouveau passage par
  ce skill, pas une reouverture a negocier.

## Organisation des tests de bug

Tous les tests de bugs vont dans `test/integration/bug_fixes/` (ou
`test/system/bug_fixes/` pour les bugs navigateur). Chaque fichier = un bug report.
On ne les supprime JAMAIS : ce sont des tests de regression.

## Anti-patterns

- Defaut d'argent ou de permission « consigne » quelque part au lieu d'etre corrige
- Corriger sans test → on ne prouve pas qu'on a compris
- Test qui passe avant le fix → on n'a pas reproduit le bug
- Fix qui touche a 10 fichiers → probablement un refactoring deguise
- "Ca ne devrait pas arriver" → ca arrive, le client le voit
- Fix sans chercher les occurrences soeurs → le meme bug reviendra d'une autre page
- Bug UI declare corrige sans re-check navigateur → rien n'est prouve
- Ecran repare avec une donnee inventee → faute grave, jamais un fix
- Question renvoyee au client la ou un defaut motive suffisait
- Bug corrige sans classe de taxonomie ni ligne de recette → la lecon est perdue
- Fermer le bug soi-meme → NON. Le statut `fixed` dit « corrige et deploye », c'est le
  bout du travail de l'agent. La FERMETURE (client satisfait) est le geste de
  l'utilisateur, apres validation du client ; l'agent ne la demande pas, ne la fait
  pas, ne la relance pas

**Accès prod** : toute lecture ou vérification en production passe par kamal
depuis le dossier du projet — voir `/kamal` (règle d'or : `kamal app exec --reuse`,
jamais de deploy manuel, jamais les seeds pour deviner les données prod).

## Ensuite

→ `brick-code-video` pour filmer le correctif, puis reboucler `brick-code-feedback`.
