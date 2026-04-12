---
name: rails-hotwire
description: "Construire des features Hotwire : Turbo Frames, Turbo Streams, Stimulus controllers. Utilise /rails-hotwire pour implementer une feature interactive."
---

# Rails Hotwire Feature Builder

Guide pour construire des features interactives avec Hotwire (Turbo + Stimulus).

## Decision Tree

```
Besoin d'interactivite?
├── Navigation entre pages → Turbo Drive (gratuit, rien a faire)
├── Mise a jour d'une section de page → Turbo Frame
├── Mise a jour temps reel (multi-users) → Turbo Stream via Action Cable
├── Mise a jour apres form submit → Turbo Stream response
├── Comportement UI (toggle, modal, tabs) → Stimulus controller
└── Animation/transition → CSS + Stimulus (data-transition)
```

## Turbo Frames

### Quand utiliser
- Formulaire inline (edit in place)
- Lazy loading d'une section
- Navigation dans un panneau (tabs, sidebar)
- Pagination sans reload

### Pattern
```erb
<%%= turbo_frame_tag "post_#{post.id}" do %>
  <%%= render post %>
<%% end %>
```

Controller : render normal, Turbo extrait le frame automatiquement.

### Lazy loading
```erb
<%%= turbo_frame_tag "comments", src: post_comments_path(@post), loading: :lazy do %>
  <p>Chargement...</p>
<%% end %>
```

## Turbo Streams

### Quand utiliser
- Mise a jour de PLUSIEURS elements apres une action
- Broadcast temps reel a tous les utilisateurs
- Ajout/suppression dans une liste

### Depuis le controller (reponse)
```ruby
respond_to do |format|
  format.turbo_stream do
    render turbo_stream: [
      turbo_stream.prepend("messages", partial: "messages/message", locals: { message: @message }),
      turbo_stream.update("message_count", "#{@messages.count} messages")
    ]
  end
  format.html { redirect_to @conversation }
end
```

### Broadcast depuis le modele (temps reel)
```ruby
class Message < ApplicationRecord
  after_create_commit -> {
    broadcast_prepend_to conversation, target: "messages"
  }
  after_destroy_commit -> {
    broadcast_remove_to conversation
  }
end
```

Vue : s'abonner au stream
```erb
<%%= turbo_stream_from @conversation %>
```

## Stimulus

### Quand utiliser
- Toggle visibility (dropdown, modal, accordion)
- Form validation cote client
- Copier dans le presse-papier
- Auto-submit de formulaires
- Interactions avec des APIs externes

### Pattern minimal
```javascript
// app/javascript/controllers/toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  toggle() {
    this.contentTarget.classList.toggle("hidden")
  }
}
```

```erb
<div data-controller="toggle">
  <button data-action="toggle#toggle">Menu</button>
  <div data-toggle-target="content" class="hidden">
    Content
  </div>
</div>
```

### Regles Stimulus
- 1 controller = 1 responsabilite
- Pas de fetch/AJAX dans Stimulus (utiliser Turbo)
- Nommer les controllers par comportement (toggle, clipboard, auto-submit)
- Utiliser `values` pour la configuration, `targets` pour les elements DOM

## Patterns courants

### Flash messages qui disparaissent
Stimulus auto-remove controller + CSS transition.

### Formulaire inline
Turbo Frame autour du show + lien "edit" qui pointe vers le form.

### Liste temps reel
Turbo Stream broadcast + `turbo_stream_from` dans la vue.

### Modal
Stimulus controller + Turbo Frame pour le contenu.

### Tabs
Turbo Frame avec liens qui changent le `src`.

### Infinite scroll
Stimulus controller qui observe l'intersection + Turbo Frame pour les pages.
