---
name: rails-models
description: "Creer des modeles Rails 8 : migrations, validations, scopes, associations, callbacks. Utilise /rails-models pour generer ou reviser un modele."
---

# Rails Models

Guide pour creer des modeles Rails 8 propres et idiomatiques.

## Ordre dans le modele

```ruby
class User < ApplicationRecord
  # 1. Includes/Extends
  include Searchable

  # 2. Constants
  ROLES = %w[admin manager user].freeze

  # 3. Associations
  belongs_to :organization
  has_many :posts, dependent: :destroy
  has_one :profile, dependent: :destroy

  # 4. Validations
  validates :email, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }

  # 5. Scopes
  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }
  scope :recent, -> { order(created_at: :desc) }

  # 6. Callbacks (avec parcimonie)
  before_validation :normalize_email
  after_create_commit :send_welcome_email

  # 7. Enums
  enum :status, { draft: 0, published: 1, archived: 2 }

  # 8. Class methods
  def self.search(query)
    where("name ILIKE ?", "%#{query}%")
  end

  # 9. Instance methods
  def full_name
    "#{first_name} #{last_name}"
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end
end
```

## Migrations

Toujours utiliser le generateur :
```bash
rails generate migration CreateUsers name:string email:string:uniq role:string active:boolean
rails generate migration AddOrganizationToUsers organization:references
rails generate migration AddIndexToUsersEmail
```

### Bonnes pratiques
- `null: false` pour les champs obligatoires
- `default:` pour les booleens et enums
- `index: true` pour les foreign keys et champs de recherche
- `foreign_key: true` pour les references

## Associations

```ruby
# Un-a-plusieurs
has_many :posts, dependent: :destroy
belongs_to :author, class_name: "User"

# Plusieurs-a-plusieurs
has_many :taggings, dependent: :destroy
has_many :tags, through: :taggings

# Polymorphique
has_many :comments, as: :commentable
belongs_to :commentable, polymorphic: true
```

## Validations

```ruby
# Presence + format
validates :email, presence: true,
                  format: { with: URI::MailTo::EMAIL_REGEXP }

# Conditionnel
validates :bio, length: { maximum: 500 }, if: :published?

# Custom
validate :end_date_after_start_date

private

def end_date_after_start_date
  return unless start_date && end_date
  errors.add(:end_date, "must be after start date") if end_date <= start_date
end
```

## Scopes vs Class Methods

- **Scope** : chainable, retourne toujours une relation
- **Class method** : pour la logique complexe ou qui retourne autre chose

## SQLite (Rails 8)

- Solid Queue pour les jobs
- Solid Cache pour le cache
- Solid Cable pour Action Cable
- Pas besoin de Redis/PostgreSQL pour la plupart des apps
