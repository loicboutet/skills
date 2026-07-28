---
name: brick-design-build
description: "Design system : creer une charte graphique quand le client n'en a pas. Direction artistique ancree metier, process en 3 passes (plan, critique, controle visuel), style guide HTML. Utilise /brick-design-build pour generer un design system."
---

# Brick Design (v2 labo)

Crée un design system complet quand le client n'a pas de charte graphique. Génère un
`style_guide.html` utilisable par les mockups. Posture : tu es le design lead d'un petit
studio connu pour donner à chaque client une identité visuelle qu'on ne peut confondre avec
aucune autre. Le client a déjà refusé des propositions qui sentaient le template. Prends UN
vrai risque esthétique justifiable, et exécute tout le reste avec sobriété.

## Quand utiliser

- Le client n'a pas de charte graphique ; le `style_guide.html` n'existe pas
- L'utilisateur demande de créer un design system

## 1. Collecter les informations

**Identité** : nom, secteur, audience, concurrents/références aimées.
**Préférences** : ambiance, couleur(s) existantes (logo, marque), dark mode souhaité ?
**Fonctionnel** : desktop ou mobile first, densité de données, besoin de charts ?

## 2. Processus obligatoire en 3 passes

### Passe 1 — le plan, avant tout code
1. **Le monde du client** : liste 5 mots de son univers matériel (matériaux, gestes, objets,
   lumière du métier). C'est de là que viennent les choix, pas d'une bibliothèque de styles.
2. **Palette** : 4-6 hex NOMMÉS d'après cet univers (pas "primary" : "chêne-brut", "bleu-lac").
   UNE dominante possédée + accents tranchants. Pas de palette timide étalée. SI LE CLIENT
   NOMME UNE COULEUR ("les bleus du lac"), c'est elle la dominante, pas une interprétation
   voisine. L'accent peut porter du SENS (ex : tout le "hors nomenclature" en orange) : mieux
   qu'un accent décoratif. Un accent qui détonne avec l'univers doit être justifiable.
3. **Typo** : un pairing display/body choisi POUR ce client. Display expressive, body lisible,
   + tabular-nums pour les chiffres. EXTRÊMES : graisses 100/200 contre 800/900, sauts de
   taille 3× et plus, pas du 400 contre 600. ÉCHELLE FERMÉE : 6 tailles max, et on n'en sort pas.
4. **Macrostructure** : décris le layout en une phrase. Refuse la grille cookie-cutter : au
   moins une asymétrie ou une rupture volontaire. INTERDIT : la carte orpheline (grille de 3
   avec 4 éléments, 9e carte seule) — complète la grille ou casse-la volontairement.
5. **Élément signature** : LA chose dont on se souviendra. Une seule. Nomme-la. Elle se
   répète à l'identique sur toutes les pages du site.

### Passe 2 — auto-critique du plan avant de coder
"Aurais-je produit ce plan pour n'importe quel brief similaire ?" Si un choix ressemble au
défaut générique, révise-le. Puis code en suivant le plan exactement.

### Passe 3 — contrôle visuel OBLIGATOIRE après le code
Ouvre chaque page livrée et screenshote-la (desktop 1440×900 ET mobile 390×844, playwright-cli
avec une session nommée, fermée à la fin). Regarde les captures et corrige AVANT de livrer :
- section vide ou effondrée = bloquant ; CHAQUE visuel rend réellement quelque chose (un
  cadre vide là où un visuel est attendu = bloquant, zoome sur les grilles) ;
- chevauchements, débordements, scroll horizontal mobile = bloquant ;
- rythme : 3 sections consécutives de même structure → varie ; jamais plus de 2 bandes pleine
  largeur de même fond à la suite ; page > ~5500px desktop → fusionne ou coupe ;
- TENUE SUR LA LONGUEUR : le niveau de design du hero est le contrat pour toute la page ;
- COHÉRENCE INTER-PAGES : mêmes motifs signature, mêmes règles sur toutes les pages ;
- retire un accessoire (Chanel) : coupe la décoration qui ne sert pas le brief.
RE-SCREENSHOTE après ta DERNIÈRE modification : le contrôle vaut sur l'état final livré.

## 3. Interdits nommés (les tells IA, aucun sauf demande explicite du client)

- Inter par défaut, et Space Grotesk "le nouveau Inter". Une font par défaut = une pensée par défaut.
- Gradient bleu→violet, et tout gradient décoratif non demandé.
- Trois/quatre cards identiques en ligne avec icône au-dessus ; trio numéroté "01/02/03" à
  icônes filaires ; FAQ centrée générique.
- Border grise 1px + shadow-sm sur chaque carte ; nesting de containers.
- Hero "gros chiffre + petit label + Get Started" ; copy creuse type "Build faster".
- Fond crème + serif + terracotta ; near-black + accent acide ; broadsheet hairlines radius-0.
- Spacing métronomique ; emoji dans l'UI ; icônes décoratives éparpillées ; dark mode non demandé.
Test final élément par élément : "choisi, ou par défaut ?"

## 4. Règles d'exécution (MUST/NEVER)

- MUST : le hero est une thèse — la chose la plus caractéristique du métier du client (une
  matière, un geste, une preuve), jamais à moitié vide : les deux colonnes travaillées.
- MUST : rythme vertical INÉGAL, hiérarchie DANS chaque section : un H2 domine visiblement
  son bloc. Y compris DANS les listes : cinq lignes au même poids = pas de hiérarchie ; sur
  un listing long (10+), ruptures de poids visuel toutes les 4-6 lignes.
- MUST : dans une grille de fiches, les rangées restent alignées (réserve la hauteur des
  surtitres variables ; les bas de cartes d'une même rangée s'alignent).
- MUST : hiérarchie portée par la typo, pas par les icônes ; `text-balance` titres,
  `text-pretty` paragraphes, `tabular-nums` sur toute donnée chiffrée alignée.
- MUST : tokens centralisés (tailwind.config) : AUCUNE couleur ad hoc dans le markup ;
  2 variantes de bouton max ; contrôles de formulaire stylés (jamais de widgets natifs bruts).
- MUST : contraste WCAG AA (4.5:1) VÉRIFIÉ AU CALCUL, surtout texte clair sur bandes colorées.
- MUST : l'accent est RATIONNÉ (action principale + une sémantique ; >5 occurrences par
  écran = il ne signale plus rien).
- MUST : tous les états : hover, focus visible, empty state avec phrase humaine + action,
  erreur à côté de l'action.
- MUST : aucun placeholder visible ("emplacement réservé") : texte neutre présentable +
  `<!-- À VALIDER CLIENT -->`. La page a toujours l'air finie.
- Visuels SVG (mockups sans photos) : abstrait composé OU dessin au trait technique
  (élévation, plan, schéma coté). JAMAIS de faux photoréalisme ni de texture naïve.
- NEVER : letter-spacing modifié sans raison ; h-screen (h-dvh) ; ombres et radius mélangés
  sans échelle.
- Copy = matériau de design : vocabulaire du métier réel, chiffres du brief, voix active,
  verbes précis ("Demander un devis", pas "Commencer").

## 5. Générer `doc/memory/style_guide.html`

Un HTML standalone (Tailwind CDN pour le preview) qui documente : palette (hex nommés),
typographie (rôles, échelle fermée), boutons (2 variantes + états), formulaires (contrôles
stylés, erreurs), cartes/fiches, tableaux (tabular-nums), alerts/flash, navigation, empty
states, l'élément signature avec sa règle d'usage, et le bloc `tailwind.config.js` à copier.
Sections ancrées, composants copier-collables.

## Validation gate

- [ ] Élément signature nommé + palette ancrée métier (justifiable en 1 phrase)
- [ ] Aucun des interdits nommés ; test "choisi ou par défaut" passé
- [ ] Contraste AA vérifié au calcul (y compris accent et bandes colorées)
- [ ] Échelle typo fermée (6 tailles), pairing display/body, tabular-nums
- [ ] Composants documentés avec états ; contrôle visuel par screenshot effectué
- [ ] L'utilisateur a validé

## Ensuite

→ `brick-design-review`, puis `brick-mockup-build` (qui applique ces mêmes règles d'exécution
et la passe 3 de contrôle visuel à chaque mockup).
