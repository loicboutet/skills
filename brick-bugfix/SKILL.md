---
name: brick-bugfix
description: "Correction de bug client : comprendre le retour, reproduire avec un test, corriger, verifier. Utilise /brick-bugfix quand un client signale un probleme."
---

# Brick Bugfix

Le client a toujours raison. Chaque bug suit le meme process : comprendre → reproduire → corriger → verifier.

## Regle d'or

**Ne jamais dire "ca marche chez moi"**. Si le client dit que c'est casse, c'est casse. Notre job c'est de comprendre POURQUOI il voit ce qu'il voit.

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

    patch user_profile_path, params: {
      profile: { name: "Updated Name" }
    }

    assert_redirected_to user_profile_path
    follow_redirect!
    assert_select ".flash-notice", text: /mis a jour/i

    # Verifier que la donnee est bien sauvee
    assert_equal "Updated Name", users(:client_user).reload.profile.name
  end
end
```

Lancer le test :
```bash
rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT echouer. Si le test passe, on n'a pas compris le bug. Recommencer l'etape 1.

### 3. Diagnostiquer

Maintenant qu'on a un test qui reproduit, chercher la cause :

- Lire les logs (`rails test` donne le stacktrace)
- Verifier le controller (params, autorisation, redirect)
- Verifier le modele (validations, callbacks)
- Verifier la vue (form action, turbo frame, CSRF token)
- Verifier les routes (`rails routes | grep ...`)

### 4. Corriger

Ecrire le fix MINIMAL. Pas de refactoring, pas d'ameliorations, juste le fix du bug.

### 5. Verifier

```bash
rails test test/integration/bug_fixes/save_button_test.rb 2>&1 | head -30
```

Le test DOIT passer maintenant.

Puis lancer TOUS les tests pour verifier qu'on n'a rien casse :
```bash
rails test 2>&1 | tail -20
```

### 6. Committer

```
fix: [description courte du bug]

Reported by: [client]
Root cause: [explication technique en 1 ligne]
Test: test/integration/bug_fixes/[test_file].rb
```

Ne PAS push sans demande explicite.

### 7. Confirmation client

- Informer l'utilisateur que le fix est pret
- Attendre que le client confirme que le bug est resolu
- Ne JAMAIS fermer un bug sans confirmation

### Contexte client

Si le bug report est flou, utiliser tous les outils disponibles :
- **Leexi** (si disponible) : chercher les conversations recentes avec le client
- **Conversations nexrai** : relire les echanges dans l'app
- **Screenshots/videos** : demander au client si possible

## Organisation des tests de bug

Tous les tests de bugs vont dans `test/integration/bug_fixes/`. Chaque fichier = un bug report. On ne les supprime JAMAIS — ils servent de regression tests.

## Anti-patterns

- Corriger sans test → on ne prouve pas qu'on a compris
- Test qui passe avant le fix → on n'a pas reproduit le bug
- Fix qui touche a 10 fichiers → probablement un refactoring deguise
- "Ca ne devrait pas arriver" → ca arrive, le client le voit
- Fermer le bug sans que le client confirme → toujours demander confirmation
