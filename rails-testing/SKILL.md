---
name: rails-testing
description: "Tests Rails 8 : Minitest, fixtures, system tests, test patterns. Utilise /rails-testing pour ecrire ou debugger des tests."
---

# Rails Testing

Guide pour ecrire des tests Rails 8 avec Minitest.

## Philosophie

- **Tester le comportement, pas l'implementation**
- **Fixtures > factories** (Rails way)
- **Tests d'integration > tests unitaires isoles**
- **Pas de mocks** sauf pour les services externes
- **Tester les happy paths + les cas d'erreur importants**

## Types de tests

### Model tests
```ruby
class UserTest < ActiveSupport::TestCase
  test "valid user" do
    user = users(:loic)
    assert user.valid?
  end

  test "requires email" do
    user = User.new(name: "Test")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "email must be unique" do
    existing = users(:loic)
    user = User.new(email: existing.email)
    assert_not user.valid?
  end
end
```

### Controller tests (integration)
```ruby
class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:loic)
    sign_in @user  # helper Devise
  end

  test "index" do
    get posts_path
    assert_response :success
    assert_select "h1", "Posts"
  end

  test "create post" do
    assert_difference("Post.count") do
      post posts_path, params: { post: { title: "New", body: "Content" } }
    end
    assert_redirected_to post_path(Post.last)
  end

  test "unauthorized access" do
    sign_out @user
    get posts_path
    assert_redirected_to new_user_session_path
  end
end
```

### Turbo Stream tests
```ruby
test "create returns turbo stream" do
  post messages_path, params: { message: { content: "Hello" } },
       headers: { "Accept" => "text/vnd.turbo-stream.html" }
  assert_response :success
  assert_match "turbo-stream", response.body
  assert_match "messages", response.body
end
```

### System tests (avec Capybara)
```ruby
class PostFlowTest < ApplicationSystemTestCase
  test "creating a post" do
    sign_in users(:loic)
    visit posts_path

    click_on "New Post"
    fill_in "Title", with: "My Post"
    fill_in "Body", with: "Content here"
    click_on "Create"

    assert_text "My Post"
    assert_text "Post was successfully created"
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

dev:
  name: Developer
  email: dev@example.com
  role: user
```

### Regles fixtures
- Noms significatifs (pas `user_1`)
- Minimum de donnees (juste ce qui est necessaire)
- Utiliser ERB pour les donnees dynamiques
- Relations via le nom de la fixture

## Commandes

```bash
# Un fichier
rails test test/models/user_test.rb 2>&1 | head -50

# Un test specifique
rails test test/models/user_test.rb:15 2>&1 | head -50

# Tous les tests d'un dossier
rails test test/models/ 2>&1 | head -50

# Tous les tests
rails test 2>&1 | head -100
```

## Patterns courants

### Test de scope
```ruby
test ".active returns only active users" do
  active = users(:loic)    # active: true in fixture
  inactive = users(:dev)   # active: false in fixture
  
  result = User.active
  assert_includes result, active
  assert_not_includes result, inactive
end
```

### Test de callback
```ruby
test "normalizes email on save" do
  user = User.create!(name: "Test", email: "  LOUD@EMAIL.COM  ")
  assert_equal "loud@email.com", user.email
end
```

### Test de job
```ruby
test "enqueues welcome email" do
  assert_enqueued_with(job: WelcomeEmailJob) do
    User.create!(name: "Test", email: "test@example.com")
  end
end
```
