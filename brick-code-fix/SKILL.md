---
name: brick-code-fix
description: "Correction de bug client : comprendre, reproduire avec un test, corriger, chercher le meme bug ailleurs, re-verifier au navigateur, alimenter la taxonomie de recette. Utilise /brick-code-fix quand un client signale un probleme."
---

# Brick Bugfix

Le client a toujours raison. Chaque bug suit le meme process : comprendre → reproduire → corriger → verifier → generaliser.

## Regle d'or

**Ne jamais dire "ca marche chez moi"**. Si le client dit que c'est casse, c'est casse.
Notre job c'est de comprendre POURQUOI il voit ce qu'il voit.

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
**On comprend** : Le formulaire d'edition de [ressource] ne submit pas,
ou submit mais pas de feedback visible pour l'utilisateur.
**Contexte probable** : [page, profil utilisateur, navigateur si pertinent]
```

Si le retour est flou, poser des questions PRECISES :
- Sur quelle page exactement ?
- Quel compte / quel role ?
- Qu'est-ce qui se passe apres l'action ? (erreur, rien, page blanche ?)
- Est-ce reproductible a chaque fois ?

### 2. Reproduire avec un test

**AVANT de toucher au code**, ecrire un test qui echoue et qui prouve qu'on a compris le bug.

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

Lancer le test :
```bash
rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT echouer. Si le test passe, on n'a pas compris le bug. Recommencer l'etape 1.
Cas particulier : si le bug n'est reproductible QU'AU navigateur (Turbo, Stimulus,
rendu), le test qui reproduit est un SYSTEM test (`test/system/bug_fixes/`), pas un
test d'integration — lecon de l'audit 08/2026 ("form must redirect" invisible en
integration).

### 3. Diagnostiquer

Maintenant qu'on a un test qui reproduit, chercher la cause :

- Lire les logs (`rails test` donne le stacktrace)
- Verifier le controller (params, autorisation, redirect)
- Verifier le modele (validations, callbacks)
- Verifier la vue (form action, turbo frame, CSRF token, `data-action`)
- Verifier les routes (`rails routes | grep ...`)

### 4. Corriger

Ecrire le fix MINIMAL. Pas de refactoring, pas d'ameliorations, juste le fix du bug.

### 5. Chercher le MEME bug ailleurs

Un bug n'est presque jamais unique : le meme pattern a ete copie-colle.
AVANT de verifier, chercher les occurrences soeurs :

- `grep` du pattern fautif sur tout le repo (meme helper, meme partial, meme garde
  manquante, meme `dependent:`, meme bloc non protege par `can?`)
- Regarder en priorite : les partials partages, les autres vues copiees du meme
  mockup, les autres controleurs du meme namespace, les autres mailers/PDF si le
  bug touche une sortie
- Chaque occurrence trouvee = MEME traitement (test qui reproduit + fix) dans le
  meme lot de correction. Lister les occurrences dans le commit.

### 6. Verifier

```bash
rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT passer maintenant.

Puis lancer TOUS les tests pour verifier qu'on n'a rien casse :
```bash
rails test 2>&1 | tail -20
```

**Re-check navigateur si le bug touche l'UI** (vue, Turbo, Stimulus, CSS, PDF affiche,
mail rendu) : ouvrir la page corrigee avec `playwright-cli`, rejouer le parcours
impacte avec les donnees canoniques, screenshot a l'appui. Si le responsive est dans
le scope (decisions_comportement.md), re-verifier aussi a 390 px. Un fix UI valide
uniquement par un test d'integration n'est PAS valide.

### 7. Alimenter la taxonomie de recette

Chaque bug REEL enrichit la taxonomie de recette
(`~/.claude/skills/taxonomie-recette/SKILL.md`, versionnee dans le repo skills
github.com/loicboutet/skills — la mise a jour se pousse dans le REPO, la copie
locale seule est ecrasee au prochain sync) :

- Le bug releve d'une classe existante (T1-T15) → ajouter le cas concret a la
  provenance de la classe, date
- Le bug ne rentre dans aucune classe → creer la classe : nom, methode de
  verification reproductible, provenance (ce bug), date
- Committer la mise a jour de la taxonomie avec le fix

C'est comme ca que la classe sera chassee systematiquement aux briques suivantes :
un bug paye une fois, plus jamais.

### 8. Committer

```
fix: [description courte du bug]

Reported by: [client]
Root cause: [explication technique en 1 ligne]
Occurrences soeurs: [liste, ou "aucune (grep: pattern)"]
Taxonomie: [classe T{n} enrichie / creee]
Test: test/integration/bug_fixes/[test_file].rb
```

Ne PAS push sans demande explicite.

### 9. Confirmation client

- Informer l'utilisateur que le fix est pret
- Attendre que le client confirme que le bug est resolu
- Ne JAMAIS fermer un bug sans confirmation

### Contexte client

Si le bug report est flou, utiliser tous les outils disponibles :
- **Leexi** (si disponible) : chercher les conversations recentes avec le client
- **Conversations nexrai** : relire les echanges dans l'app
- **Screenshots/videos** : demander au client si possible

## Organisation des tests de bug

Tous les tests de bugs vont dans `test/integration/bug_fixes/` (ou
`test/system/bug_fixes/` pour les bugs navigateur). Chaque fichier = un bug report.
On ne les supprime JAMAIS — ils servent de regression tests.

## Anti-patterns

- Corriger sans test → on ne prouve pas qu'on a compris
- Test qui passe avant le fix → on n'a pas reproduit le bug
- Fix qui touche a 10 fichiers → probablement un refactoring deguise
- "Ca ne devrait pas arriver" → ca arrive, le client le voit
- Fix sans chercher les occurrences soeurs → le meme bug reviendra d'une autre page
- Bug UI declare corrige sans re-check navigateur → rien n'est prouve
- Bug corrige sans classe de taxonomie → la lecon est perdue
- Fermer le bug sans que le client confirme → toujours demander confirmation

## Ensuite

→ `brick-code-video` pour filmer le correctif, puis reboucler `brick-code-feedback`.
