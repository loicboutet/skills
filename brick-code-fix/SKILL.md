---
name: brick-code-fix
description: "Correction de bug client : comprendre, reproduire avec un test, corriger, chercher le meme bug ailleurs, re-verifier au navigateur, consigner la decision, alimenter la taxonomie de recette, surveiller apres deploiement. Utilise /brick-code-fix quand un client signale un probleme."
---

# Brick Bugfix

Le client a toujours raison. Chaque bug suit le meme process : comprendre → reproduire
→ corriger → verifier → generaliser.

## Regle d'or

**Ne jamais dire "ca marche chez moi"**. Si le client dit que c'est casse, c'est casse.
Notre job c'est de comprendre POURQUOI il voit ce qu'il voit.

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
se passe apres l'action, reproductible ou non). Ce sont les seules questions utiles :
tout ce qui releve du COMMENT se tranche.

### 2. Reproduire avec un test

**AVANT de toucher au code**, ecrire un test qui echoue et qui prouve qu'on a compris.

```ruby
# test/integration/bug_fixes/save_button_test.rb
class SaveButtonBugTest < ActionDispatch::IntegrationTest
  test "user can save edited profile" do
    sign_in users(:client_user)
    patch user_profile_path, params: { profile: { name: "Updated Name" } }
    assert_redirected_to user_profile_path
    follow_redirect!
    assert_select ".flash-notice", text: /mis a jour/i
    assert_equal "Updated Name", users(:client_user).reload.profile.name
  end
end
```

```bash
bin/rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT echouer. Si le test passe, on n'a pas compris le bug : recommencer l'etape 1.
Cas particulier : si le bug n'est reproductible QU'AU navigateur (Turbo, Stimulus,
rendu), le test qui reproduit est un SYSTEM test (`test/system/bug_fixes/`), pas un
test d'integration — lecon de l'audit qualite 08/2026 ("form must redirect" invisible
en integration).

### 3. Diagnostiquer

- Lire les logs (`rails test` donne le stacktrace)
- Verifier le controller (params, autorisation, redirect)
- Verifier le modele (validations, callbacks)
- Verifier la vue (form action, turbo frame, CSRF token, `data-action`)
- Verifier les routes (`bin/rails routes | grep ...`)
- Si le bug depend d'un reglage d'environnement (host, cle, fuseau, provider) :
  confronter `doc/memory/config.md` a l'environnement reel — la cle est-elle definie,
  et le consommateur nomme la lit-il vraiment ?

### 4. Corriger

Ecrire le fix MINIMAL. Pas de refactoring, pas d'ameliorations, juste le fix du bug.
Si le fix change un reglage d'environnement, mettre `config.md` a jour dans le meme
commit (cle, consommateur, valeur par environnement).

### 5. Chercher le MEME bug ailleurs

Un bug n'est presque jamais unique : le meme pattern a ete copie-colle.

- `grep` du pattern fautif sur tout le repo (meme helper, meme partial, meme garde
  manquante, meme `dependent:`, meme bloc non protege par `can?`)
- Regarder en priorite : les partials partages, les autres vues copiees du meme mockup,
  les autres controleurs du meme namespace, les autres mailers/PDF si le bug touche une sortie
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
avec les donnees canoniques, screenshot a l'appui. Si le responsive est dans le scope
(`decisions.md`), re-verifier aussi a 390 px. Un fix UI valide uniquement par un test
d'integration n'est PAS valide.

Si le fix touche une migration ou les seeds : rejouer une base fraiche
(`bin/rails db:drop db:prepare db:seed`, classe T16).

### 7. Alimenter la taxonomie de recette

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

### 8. Committer

```
fix: [description courte du bug]

Reported by: [client]
Root cause: [explication technique en 1 ligne]
Occurrences soeurs: [liste, ou "aucune (grep: pattern)"]
Decision: [ligne ajoutee a decisions.md, ou "aucune"]
Taxonomie: [classe T{n} enrichie / creee]
Test: test/integration/bug_fixes/[test_file].rb
```

Ne PAS push sans demande explicite.

### 9. Apres deploiement du fix

Un fix deploye en prod **rearme la surveillance** : relever GlitchTip a +1 h et +24 h
(`glitchtip_list_issues`, `glitchtip_issue_detail` sur toute issue nouvelle), et rejouer
au navigateur le parcours corrige sur l'URL reelle. Une erreur nouvelle = un nouveau
passage par ce skill.

### 10. Confirmation client

- Informer l'utilisateur que le fix est pret
- Attendre que le client confirme que le bug est resolu
- Ne JAMAIS fermer un bug sans confirmation
- Mettre l'issue tracker a jour (`tracker_issue_tool`, action `move`) : `in_progress`
  au demarrage, `fixed` apres confirmation

### Contexte client

Si le bug report est flou : **Leexi** (conversations recentes), **conversations nexrai**,
screenshots/videos demandes au client.

## Organisation des tests de bug

Tous les tests de bugs vont dans `test/integration/bug_fixes/` (ou
`test/system/bug_fixes/` pour les bugs navigateur). Chaque fichier = un bug report.
On ne les supprime JAMAIS : ce sont des tests de regression.

## Anti-patterns

- Corriger sans test → on ne prouve pas qu'on a compris
- Test qui passe avant le fix → on n'a pas reproduit le bug
- Fix qui touche a 10 fichiers → probablement un refactoring deguise
- "Ca ne devrait pas arriver" → ca arrive, le client le voit
- Fix sans chercher les occurrences soeurs → le meme bug reviendra d'une autre page
- Bug UI declare corrige sans re-check navigateur → rien n'est prouve
- Ecran repare avec une donnee inventee → faute grave, jamais un fix
- Question renvoyee au client la ou un defaut motive suffisait
- Bug corrige sans classe de taxonomie → la lecon est perdue
- Fermer le bug sans que le client confirme → toujours demander confirmation

## Ensuite

→ `brick-code-video` pour filmer le correctif, puis reboucler `brick-code-feedback`.
