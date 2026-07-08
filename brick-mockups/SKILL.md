---
name: brick-mockups
description: "Phase 2 : creation des vues mockees avec donnees fictives. Index, navigation, partials, layouts. Utilise /brick-mockups pour lancer la phase mockups."
---

# Brick Mockups

Cree les vues mockees du projet. L'objectif : un prototype navigable complet que le client peut parcourir, et dont la structure (layouts, partials, navigation) sera reutilisee a l'identique en implementation.

## Pre-requis

- `doc/memory/data_models.md` existe
- `doc/memory/routes.md` existe
- `doc/memory/user_journeys.md` existe
- `doc/memory/style_guide.html` existe
- README indique `Pret pour MOCKUPS`

## Regles fondamentales

- **JAMAIS de modeles ni de migrations** — uniquement vues et controleurs
- **Tout dans `/mockups/`** namespace (routes, controleurs, vues)
- **Donnees fictives** dans les controleurs (hashes/OpenStruct, pas de DB)
- **Utiliser des partials** pour tout ce qui sera reutilise en implementation
- **Les pages doivent linker entre elles** — on navigue comme dans la vraie app
- **Tailwind CSS** via le gem `tailwindcss-rails` (PAS le CDN)

## Tailwind CSS

### Utiliser le vrai pipeline, pas le CDN

Les mockups utilisent le meme pipeline Tailwind que l'app finale. Pas de CDN.
Ca garantit que les classes custom marchent en implementation.

### Customisation dans `config/tailwind.config.js`

Definir les couleurs, fonts et spacing du style guide ICI (source unique de verite) :

```javascript
module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        primary: '#3B82F6',
        secondary: '#6366F1',
        accent: '#EC4899',
        // Reprendre exactement les couleurs du style_guide.html
      },
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        heading: ['Plus Jakarta Sans', 'sans-serif'],
      },
    },
  },
}
```

### Regles Tailwind

1. **Utility classes en priorite** — directement dans le HTML
2. **Partials pour la reutilisation** — pas `@apply` pour creer des composants
3. **`@apply` uniquement** pour du CSS qu'on ne peut pas exprimer en markup (ex: markdown-content)
4. **Jamais de CSS custom** dans des fichiers separes (sauf `application.tailwind.css`)
5. **Couleurs custom** toujours dans `tailwind.config.js`, jamais en valeurs arbitraires (`bg-[#3B82F6]`)

### Structure CSS

```
app/assets/stylesheets/
  application.tailwind.css    # @tailwind base/components/utilities + @apply si besoin
config/
  tailwind.config.js          # Couleurs, fonts, spacing du style guide
```

### Transition mockups → implementation

Les classes Tailwind sont identiques. La transition se fait par :
1. Copier les partials (meme HTML, memes classes)
2. Les custom colors marchent deja (definies dans tailwind.config.js)
3. Remplacer les donnees fictives par les vrais modeles
4. Rien a changer cote CSS

## Widget de feedback : TOUJOURS verifier qu'il est installe

Le widget de feedback permet au client d'annoter les mockups directement dans le navigateur
(chaque annotation cree une issue dans le tracker nexrai). Sans lui, les retours arrivent
par email/WhatsApp et se perdent. **Verifier sa presence AVANT de presenter les mockups.**

### Verification

1. Le partial existe : `app/views/mockups/shared/_feedback_widget.html.erb`
   (il est normalement cree automatiquement a la creation du projet, mais les vieux
   projets ne l'ont pas)
2. Il contient un `<script src="https://5000dev.nexrai.ai/feedback-widget.js" ...>`
   avec `data-app-id`, `data-secret` et `data-project` remplis
3. Il est **rendu dans CHAQUE layout mockup** (`mockup_admin`, `mockup_user`, etc.) :

```erb
<%%= render "mockups/shared/feedback_widget" %>
```

### Installation si absent

1. Recuperer l'app id dans `.nexrai/binding.json` a la racine du projet
2. Appeler l'outil MCP `get_feedback_widget` avec cet `app_id` — il retourne le snippet
   `<script>` pret a coller (`mockup_snippet`) et genere le secret si besoin
3. Creer `app/views/mockups/shared/_feedback_widget.html.erb` avec le snippet
4. Ajouter le `render` dans chaque layout mockup (juste avant `</body>`)
5. Verifier dans le navigateur que le launcher du widget apparait sur une page mockup

Pour les mockups : version NON gated (pas de `data-gated`) — le widget est toujours visible.
Guide complet : artefact nexrai `feedback_widget_install` (app 37).

## Scope par brique : marquer ce qui n'est PAS dans la brique courante

Les mockups servent a faire valider le client. S'ils melangent plusieurs briques sans
distinction, le client ne sait pas ce qui sera livre maintenant -> incomprehensions et
retours ("pourquoi ca ne marche pas ?") sur des elements prevus plus tard.

Regles :
- **Limiter les mockups a la brique courante.** Ne pas tout mocker d'un coup.
- **Les elements des briques suivantes restent visibles mais grises + marques** "brique 2"
  / "brique 3", pour montrer la vision sans laisser croire qu'ils sont livres maintenant.
- **L'index `/mockups` indique a quelle brique appartient chaque page.**

```erb
<%% # Element prevu pour une brique ulterieure : grise + badge %>
<div class="relative opacity-50 pointer-events-none">
  <span class="absolute top-2 right-2 text-xs font-medium px-2 py-1 rounded bg-gray-200 text-gray-600">
    Brique 2
  </span>
  <%%= render "mockups/reports/_export_panel" %>
</div>
```

Dans l'index, baliser la portee :

```erb
<li>
  <%%= link_to "Statistiques avancees", mockups_stats_path %>
  <span class="text-xs text-gray-500">(Brique 2)</span>
</li>
```

## Nouveaux elements -> proposer l'ajout aux specs

Pendant le mockup, on ajoute souvent des elements absents des specs (un champ, une page,
une action, une etape de parcours). Les specs sont la source de verite : elles doivent rester
a jour, sinon ecart specs / mockups / implementation.

**Des qu'un element ajoute dans un mockup n'existe pas dans les specs :**
1. Le signaler.
2. **Proposer son ajout dans le bon fichier, au bon endroit** :
   - Nouvel attribut affiche -> `doc/memory/data_models.md` (sur le bon modele)
   - Nouvelle page / action -> `doc/memory/routes.md` (dans le bon namespace)
   - Nouveau comportement verifiable -> `doc/memory/acceptance_criteria.md` (nouveau AC numerote)
   - Nouvelle etape de parcours -> `doc/memory/user_journeys.md` (dans le bon parcours/profil)
3. **Demander validation a l'utilisateur AVANT d'ecrire** dans les specs (jamais en silence).

## Structure des fichiers

```
config/routes.rb
  namespace :mockups do
    # Un controller par ressource, RESTful
    resources :users, only: [:index, :show, :new, :edit]
    resources :posts, only: [:index, :show, :new, :edit]
    root "dashboard#show"
  end

app/controllers/mockups/
  application_controller.rb     # layout selection, donnees partagees
  dashboard_controller.rb
  users_controller.rb
  posts_controller.rb

app/views/layouts/
  mockup_admin.html.erb         # Sidebar + topbar + yield
  mockup_user.html.erb          # Layout user

app/views/mockups/
  index.html.erb                # PAGE INDEX : liste toutes les pages
  dashboard/
    show.html.erb
  users/
    index.html.erb
    show.html.erb
    new.html.erb                # = formulaire creation
    edit.html.erb               # = formulaire edition
    _user_card.html.erb         # PARTIAL reutilisable
    _form.html.erb              # PARTIAL formulaire (shared new/edit)
  posts/
    _post_row.html.erb          # PARTIAL ligne de tableau
    _form.html.erb
```

## Process

### 1. Creer les taches

Dossier : `doc/memory/mockups/tasks/`
Nommage : `{NNN}-{titre}-{etat}.md`
Etats : `todo`, `inprogress`, `done`

Ordre recommande :
1. Layouts (admin, user, etc.)
2. Page index `/mockups` (hub central)
3. Dashboard(s) par profil
4. Pages principales (index, show)
5. Formulaires (new, edit)
6. Pages secondaires
7. Pages systeme : login (si auth), erreurs 404 et 500 (aux couleurs du style guide)

### 2. Layouts

Chaque layout inclut :
- **Sidebar/topbar** avec navigation reelle (liens vers les autres mockups)
- **Breadcrumbs** si pertinent
- **User info** (nom, role, avatar placeholder)
- **Flash messages** zone (pour montrer le pattern)
- **Footer** si necessaire

```erb
<%% # app/views/layouts/mockup_admin.html.erb %>
<!DOCTYPE html>
<html>
<head>
  <%%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
  <%%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
</head>
<body class="bg-gray-50">
  <div class="flex min-h-screen">
    <%%= render "mockups/shared/sidebar" %>
    <main class="flex-1 p-6">
      <%%= render "mockups/shared/topbar" %>
      <%%= yield %>
    </main>
  </div>
</body>
</html>
```

### 3. Page Index (`/mockups`)

Hub central qui liste TOUTES les pages par profil. Le client et le dev l'utilisent pour naviguer.

```erb
<%% # app/views/mockups/index.html.erb %>
<h1>Mockups</h1>

<h2>Admin</h2>
<ul>
  <li><%%= link_to "Dashboard", mockups_root_path %></li>
  <li><%%= link_to "Users", mockups_users_path %></li>
  <li><%%= link_to "User detail", mockups_user_path(1) %></li>
  <li><%%= link_to "New user", new_mockups_user_path %></li>
</ul>

<h2>User</h2>
<ul>
  <li><%%= link_to "Mon profil", mockups_profile_path %></li>
  ...
</ul>
```

### 4. Partials — la cle pour l'implementation

**Regle : tout element repetable ou reutilisable = un partial.**

Les partials creees en mockup seront copiees telles quelles en implementation (en remplacant les donnees fictives par les vraies).

```erb
<%% # app/views/mockups/users/_user_card.html.erb %>
<div class="bg-white rounded-lg shadow p-4 flex items-center gap-4">
  <div class="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center">
    <span class="text-blue-600 font-medium"><%%= user[:initials] %></span>
  </div>
  <div>
    <p class="font-medium"><%%= user[:name] %></p>
    <p class="text-sm text-gray-500"><%%= user[:email] %></p>
  </div>
  <div class="ml-auto">
    <%%= link_to "Voir", mockups_user_path(user[:id]), class: "text-blue-600 text-sm" %>
  </div>
</div>
```

Partials a creer systematiquement :
- `_form.html.erb` — formulaire (partage entre new et edit)
- `_[resource]_card.html.erb` ou `_[resource]_row.html.erb` — element de liste
- `_sidebar.html.erb` — navigation laterale
- `_topbar.html.erb` — barre superieure
- `_empty_state.html.erb` — etat vide avec CTA
- `_flash.html.erb` — messages flash
- `_pagination.html.erb` — si listes paginee
- `_filters.html.erb` — si filtres sur les listes

### 5. Donnees fictives

Dans chaque controleur, creer des donnees realistes :

```ruby
class Mockups::UsersController < Mockups::ApplicationController
  def index
    @users = [
      { id: 1, name: "Marie Dupont", email: "marie@example.com", role: "Admin", initials: "MD", active: true, created_at: "12 mars 2026" },
      { id: 2, name: "Pierre Martin", email: "pierre@example.com", role: "User", initials: "PM", active: true, created_at: "5 avril 2026" },
      { id: 3, name: "Sophie Bernard", email: "sophie@example.com", role: "User", initials: "SB", active: false, created_at: "1 avril 2026" },
    ]
    @stats = { total: 3, active: 2, inactive: 1 }
  end
end
```

Regles :
- Noms francais realistes (pas "John Doe")
- Au moins 3-5 items par liste (montrer la pagination si prevue)
- Inclure un item "vide" ou "inactif" pour montrer les etats
- Les IDs doivent matcher entre les pages (user 1 sur la liste = user 1 sur le detail)

### 6. Navigation entre pages

**Chaque page doit linker vers les pages liees.** Le client doit pouvoir naviguer comme dans la vraie app.

- Liste users → click user → detail user
- Detail user → bouton "Modifier" → formulaire edit
- Formulaire → bouton "Annuler" → retour a la liste
- Sidebar → liens vers toutes les sections
- Breadcrumbs → retour hierarchique

### 7. Etats de page

Pour chaque page, montrer les etats importants :
- **Normal** : avec donnees
- **Vide** : empty state avec message + CTA ("Aucun utilisateur. Creer le premier")
- **Erreur formulaire** : au moins un formulaire avec des erreurs affichees
- **Loading** : skeleton/spinner si pertinent (via commentaire HTML)

## Design challenge

Avant de presenter au client, verifier :
- [ ] Toutes les pages de `routes.md` ont un mockup
- [ ] Toutes les pages linkent entre elles (pas d'impasse)
- [ ] Les donnees affichees correspondent aux attributs de `data_models.md`
- [ ] Le design respecte le `style_guide.html`
- [ ] Les formulaires ont tous les champs du modele

## Verification UX

Avec `doc/memory/user_journeys.md` :
- [ ] Chaque parcours utilisateur est faisable de bout en bout
- [ ] Les etats d'erreur sont visibles
- [ ] Les empty states ont un message + CTA
- [ ] La navigation ne mene jamais a une impasse
- [ ] Les actions destructives ont une confirmation

## Validation gate

Avant de passer a IMPLEMENTATION :
- [ ] Toutes les pages de `routes.md` ont un mockup
- [ ] Le widget de feedback est installe et rendu dans tous les layouts mockup
- [ ] L'index `/mockups` liste toutes les pages
- [ ] Le design est coherent entre les pages
- [ ] Les parcours utilisateurs sont fluides
- [ ] Les partials sont extraites pour la reutilisation
- [ ] L'utilisateur a valide
