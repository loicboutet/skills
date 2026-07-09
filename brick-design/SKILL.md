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

### 2. Direction artistique : eviter le look template

**Le piege : chaque app qui sort ressemble a la meme app SaaS** (Inter + bleu +
cartes blanches rounded-lg + shadow). C'est le look "genere par IA" de 2023.
Le client paie pour une identite qu'on ne peut pas confondre avec une autre.

Avant de choisir couleurs et typo :

1. **Ancrer le design dans le metier du client.** Le vocabulaire visuel vient de
   son univers : materiaux, objets, codes du secteur. Un cabinet juridique, une
   boite de logistique et un studio de yoga ne partagent AUCUNE direction.
2. **Choisir UN element signature** : la chose dont on se souvient (un traitement
   typo fort, une couleur possedee, un motif, un style de cartes inhabituel).
   Une seule audace, executee proprement — tout le reste sobre et discipline.
3. **Bannir les 3 defauts IA reconnaissables** (sauf demande explicite du client) :
   - fond creme + serif haute + accent terracotta
   - fond quasi-noir + un seul accent vert acide / vermillon
   - look journal : hairlines partout, zero border-radius, colonnes denses

### Tendances actuelles (a doser selon le client)

**Ce qui marche en 2026 — et coute pas cher en Tailwind :**
- **Calm design** : moins de chrome, le whitespace est un outil fonctionnel,
  UNE action primaire par ecran, la typo porte la hierarchie (pas les icones)
- **Une couleur possedee** : une seule teinte signature forte (comme Linear =
  violet, Raycast = rouge-orange) plutot que 3 couleurs vives qui se battent
- **Serif de caractere pour les titres** : les displays serif reviennent en
  force dans le B2B (poids, credibilite), body sans-serif lisible
- **Chiffres tabulaires** pour les tableaux et KPIs (`tabular-nums`)
- **Bento grid** pour les dashboards : compartiments modulaires de tailles
  variees plutot que la grille de cards identiques
- **Dark mode adaptatif** si le client le veut (pas par defaut)
- **Empty states avec de la voix** : une phrase humaine + CTA, pas juste
  "Aucune donnee"

**Ce qui date ou coute trop cher :**
- Degrades pastel partout, glassmorphism lourd (flou epais)
- 3D / WebGL / animations kinetiques (budget perf explose, apport faible)
- Spinners generiques (preferer skeletons contextuels)
- Soupe d'icones : si un label suffit, pas d'icone

### 3. Generer la palette

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
- **UNE couleur signature** (primary) + neutres + couleurs semantiques.
  Secondary/accent discrets, au service de la primary — pas en competition
- **Grays coherents** (une seule echelle de gris, legerement teintee vers la
  primary plutot que gris pur)

### 4. Choisir la typographie

La typo porte la personnalite de la page. **Ne pas reprendre Inter + Plus
Jakarta sur chaque projet** : c'est le duo par defaut qui rend tout identique.
Choisir un pairing specifique au client (Google Fonts, self-hosted) :

- **Display/headings** : une font de caractere, utilisee avec retenue.
  Pistes : Bricolage Grotesque, Space Grotesk, Sora (sans) ; Fraunces,
  Instrument Serif, Newsreader (serif — credibilite B2B)
- **Body** : lisible et neutre (Inter, Figtree, DM Sans, Source Sans 3)
- **Mono / data** : JetBrains Mono, IBM Plex Mono — et `tabular-nums` sur
  tous les chiffres de tableaux/KPIs
- Tailles : scale harmonique (text-sm -> text-2xl), gros titres genereux
- Le pairing display/body EST une decision de design, pas un detail

### 5. Definir les composants

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

### 6. Generer `doc/memory/style_guide.html`

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
- **Ouvrable directement dans le navigateur** (Tailwind CDN pour le preview)
- **Sections clairement separees** avec ancres
- **Copier-collable** : chaque composant avec son code source
- **Inclure un bloc `tailwind.config.js`** a copier dans le projet :

```html
<!--
  TAILWIND CONFIG — copier dans config/tailwind.config.js du projet :

  colors: {
    primary: '#3B82F6',
    secondary: '#6366F1',
    ...
  },
  fontFamily: {
    sans: ['Inter', 'sans-serif'],
    heading: ['Plus Jakarta Sans', 'sans-serif'],
  }
-->
```

Le style_guide.html utilise le CDN pour le preview standalone.
Les mockups et l'implementation utilisent le gem `tailwindcss-rails` avec ces memes couleurs dans `config/tailwind.config.js`.

### 7. Validation

Presenter le style guide a l'utilisateur :
- Montrer le fichier HTML
- Demander validation des couleurs, typo, composants
- Iterer si necessaire

## Validation gate

- [ ] Le design a un element signature et ne ressemble PAS au template SaaS
      generique (Inter + bleu + cartes blanches shadow) ni aux 3 defauts IA
- [ ] La direction est ancree dans le metier du client (justifiable en 1 phrase)
- [ ] Palette de couleurs definie (une signature + neutres + semantiques)
- [ ] Contraste WCAG AA verifie
- [ ] Typographie choisie (headings, body, mono)
- [ ] Composants documentes (boutons, inputs, cartes, tableaux, alerts)
- [ ] Fichier ouvrable standalone dans le navigateur
- [ ] L'utilisateur a valide

## Sortie

`doc/memory/style_guide.html` cree et valide. Continuer avec `/brick-analysis` (si en cours) ou `/brick-mockups`.
