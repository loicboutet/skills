---
name: rails-testing
description: "Strategie et guide de tests Rails 8 : Minitest, fixtures, integration, system tests. Utilise /rails-testing pour ecrire ou debugger des tests."
---

# Rails Testing

Strategie et guide de tests pour les projets Rails 8 / nexrai.

## Strategie

### La regle d'or

**Chaque critere d'acceptance = un test d'integration.**

```
acceptance_criteria.md          →  tests
─────────────────────────────      ─────
R1/AC1.1: User peut s'inscrire →  test/integration/registration_test.rb
R1/AC1.2: Email de confirmation → test/integration/registration_test.rb
R2/AC2.1: Admin voit la liste   → test/integration/admin/users_test.rb
Bug #42: Bouton save casse      → test/integration/bug_fixes/save_button_test.rb
```

### Pyramide de tests

| Type | Quand | Quoi | Volume |
|------|-------|------|--------|
| **Integration** | Chaque AC + chaque bug | Request → response → DB | ~80% |
| **Model** | Validations critiques, scopes, methodes business | Logique metier isolee | ~15% |
| **System** | Parcours complexes (JS/Turbo) | UX end-to-end avec navigateur | ~5% |

### Ce qu'on teste

- Chaque critere d'acceptance (obligatoire)
- Validations de modeles (presence, unicite, format)
- Scopes et methodes business
- Autorisations (un user ne peut pas acceder aux pages admin)
- Cas d'erreur importants (formulaire invalide, 404, pas autorise)
- Bugs clients (test de regression, jamais supprime)

### Ce qu'on ne teste PAS

- Les vues directement (couvert par les tests d'integration)
- Les getters/setters triviaux
- Rails lui-meme (associations standard, callbacks simples)
- Le code genere (scaffolds, migrations)
- Les services externes (mocker a la frontiere)

### Quand ecrire les tests

| Phase | Tests |
|-------|-------|
| `/brick-implementation` | Test chaque AC au fur et a mesure du dev |
| `/brick-bugfix` | Test qui echoue AVANT le fix (obligatoire) |
| `/brick-review` | Verifier la couverture, lancer la suite complete |

## Philosophie

- **Tester le comportement, pas l'implementation**
- **Fixtures > factories** (Rails way)
- **Tests d'integration > tests unitaires isoles**
- **Pas de mocks** sauf pour les services externes
- **Test names = phrases lisibles** qui decrivent le comportement attendu

## Types de tests

### Integration tests (~80% des tests)

Le coeur de la strategie. Chaque test simule un parcours reel.

```ruby
# test/integration/posts_test.rb
class PostsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:loic)
    sign_in @user
  end

  # R1/AC1.1: User peut creer un post
  test "user creates a post successfully" do
    assert_difference("Post.count") do
      post posts_path, params: { post: { title: "New", body: "Content" } }
    end
    assert_redirected_to post_path(Post.last)
    follow_redirect!
    assert_select ".flash-notice"
  end

  # R1/AC1.2: Le titre est obligatoire
  test "user sees error when title is blank" do
    post posts_path, params: { post: { title: "", body: "Content" } }
    assert_response :unprocessable_entity
    assert_select ".field-error", /can't be blank/
  end

  # R2/AC2.1: Un user ne voit que ses posts
  test "user only sees own posts" do
    get posts_path
    assert_select ".post", count: @user.posts.count
  end

  # Authorization
  test "non-admin cannot access admin posts" do
    get admin_posts_path
    assert_redirected_to root_path
  end
end
```

### Turbo Stream tests

```ruby
test "create returns turbo stream with new message" do
  post messages_path, params: { message: { content: "Hello" } },
       headers: { "Accept" => "text/vnd.turbo-stream.html" }
  assert_response :success
  assert_match "turbo-stream", response.body
  assert_match "messages", response.body
end
```

### Model tests (~15%)

Seulement la logique business, validations critiques et scopes.

```ruby
class UserTest < ActiveSupport::TestCase
  test "requires email" do
    user = User.new(name: "Test")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test ".active returns only active users" do
    assert_includes User.active, users(:loic)
    assert_not_includes User.active, users(:inactive)
  end

  test "normalizes email on save" do
    user = User.create!(name: "Test", email: "  LOUD@EMAIL.COM  ")
    assert_equal "loud@email.com", user.email
  end
end
```

### System tests (~5%)

Pour les parcours qui dependent de JS/Turbo (interactions navigateur).

```ruby
class OnboardingFlowTest < ApplicationSystemTestCase
  test "new user completes onboarding" do
    sign_in users(:new_user)
    visit root_path

    # Step 1: Profile
    fill_in "Name", with: "John"
    click_on "Suivant"

    # Step 2: Preferences
    check "Notifications email"
    click_on "Terminer"

    assert_text "Bienvenue John"
    assert_current_path dashboard_path
  end
end
```

### Bug fix tests (regression)

Vont dans `test/integration/bug_fixes/`. Jamais supprimes.

```ruby
# test/integration/bug_fixes/save_button_test.rb
class SaveButtonBugTest < ActionDispatch::IntegrationTest
  # Bug reported by: Client X, 2026-04-10
  # Root cause: missing CSRF token on Turbo form
  test "user can save edited profile" do
    sign_in users(:client_user)
    patch user_profile_path, params: { profile: { name: "Updated" } }
    assert_redirected_to user_profile_path
    assert_equal "Updated", users(:client_user).reload.profile.name
  end
end
```

## Fixtures

```yaml
# test/fixtures/users.yml
loic:
  name: Loic
  email: loic@example.com
  role: admin
  active: true

inactive:
  name: Inactive User
  email: inactive@example.com
  role: user
  active: false
```

Regles :
- Noms significatifs (pas `user_1`)
- Minimum de donnees necessaires
- Relations via le nom de la fixture
- ERB pour les donnees dynamiques

## Commandes

```bash
# Un fichier
rails test test/integration/posts_test.rb 2>&1 | head -50

# Un test specifique (par numero de ligne)
rails test test/integration/posts_test.rb:15 2>&1 | head -30

# Tous les tests d'un dossier
rails test test/integration/ 2>&1 | head -50

# Suite complete (avant livraison)
rails test 2>&1 | tail -20
```

## Checklist pre-livraison

```bash
rails test 2>&1 | tail -5
```

- [ ] 0 failures, 0 errors
- [ ] Chaque AC a au moins un test
- [ ] Les bugs fixes ont des regression tests
- [ ] Pas de tests skipped sans raison documentee
