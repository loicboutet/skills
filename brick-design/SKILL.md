---
name: brick-design
description: "Design system : creer une charte graphique quand le client n'en a pas. Couleurs, typo, composants, style guide HTML. Utilise /brick-design pour generer un design system."
---

# Brick Design

Cree un design system complet quand le client n'a pas de charte graphique. Genere un `style_guide.html` utilisable par les mockups.

## Quand utiliser

- Le client n'a pas de charte graphique
- Le `style_guide.html` n'existe pas
- L'utilisateur demande de creer un design system

## Process

### 1. Collecter les informations

Poser ces questions au client/utilisateur :

**Identite**
- Nom du projet/entreprise ?
- Secteur d'activite ?
- Audience cible (age, profil, tech-savvy?) ?
- Concurrents / sites de reference qu'ils aiment ?

**Preferences visuelles**
- Ambiance : professionnel / moderne / fun / minimaliste / premium ?
- Couleur(s) existante(s) (logo, marque) ?
- Dark mode souhaite ?

**Fonctionnel**
- Desktop-first ou mobile-first ?
- Beaucoup de donnees/tableaux ou plutot contenu narratif ?
- Besoin de graphiques/charts ?

### 2. Generer la palette

A partir des reponses, creer une palette Tailwind :

```
Primary    : couleur principale (CTA, liens, accents)
Secondary  : couleur complementaire
Accent     : couleur de highlight
Neutral    : gris pour texte, bordures, fonds
Success    : vert
Warning    : orange
Danger     : rouge
Background : fond de page
Surface    : fond de cartes/panels
```

Regles :
- **Contraste WCAG AA minimum** (4.5:1 pour le texte)
- **Max 3 couleurs vives** (primary + secondary + accent)
- **Grays coherents** (une seule echelle de gris)

### 3. Choisir la typographie

- **Headings** : font distinctive (Inter, Plus Jakarta Sans, Cal Sans...)
- **Body** : font lisible (Inter, System UI, Geist...)
- **Mono** : pour le code (JetBrains Mono, Fira Code...)
- Tailles : scale harmonique (text-sm, text-base, text-lg, text-xl, text-2xl)

### 4. Definir les composants

Creer les patterns de base :

**Navigation**
- Sidebar ou topbar ?
- Breadcrumbs ?
- Mobile : hamburger ou bottom nav ?

**Cartes**
- Shadow ou border ?
- Rounded corners (rounded-lg standard)
- Padding (p-4 ou p-6)

**Formulaires**
- Input style (border, fond, focus ring)
- Label position (top ou inline)
- Boutons (filled, outline, ghost)
- Messages d'erreur (inline ou toast)

**Tableaux**
- Striped ou hover ?
- Pagination style
- Actions row (boutons ou dropdown)

**Feedback**
- Flash messages (banner top ou toast corner)
- Loading states (spinner, skeleton, shimmer)
- Empty states (illustration + CTA)

### 5. Generer `doc/memory/style_guide.html`

Un fichier HTML standalone qui montre :
- Palette de couleurs avec codes hex
- Typographie (headings, body, mono)
- Boutons (primary, secondary, danger, ghost, sizes)
- Formulaires (inputs, selects, checkboxes, erreurs)
- Cartes et panels
- Tableaux
- Alerts et flash messages
- Navigation (sidebar + topbar)
- Empty states
- Loading states

Le fichier doit etre :
- **Ouvrable directement dans le navigateur** (pas de dependances)
- **Tailwind via CDN** pour les classes
- **Sections clairement separees** avec ancres
- **Copier-collable** : chaque composant avec son code source

### 6. Validation

Presenter le style guide a l'utilisateur :
- Montrer le fichier HTML
- Demander validation des couleurs, typo, composants
- Iterer si necessaire

## Sortie

`doc/memory/style_guide.html` cree et valide. L'analyse peut continuer.
