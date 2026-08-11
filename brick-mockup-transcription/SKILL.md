---
name: brick-mockup-transcription
description: "Boucle mockup, entree TRANSCRIPTION : porter une source fournie par le client (export Lovable, HTML depose, Figma) en vues de maquette ERB, en valeurs litterales, puis normaliser la charte mecaniquement APRES validation client. Utilise /brick-mockup-transcription quand le client fournit une source d'ecran ; /brick-mockup-build quand il n'y a rien a porter."
---

# Transcrire une source client en maquettes

La boucle mockup a deux entrées. Quand le client n'a rien, on **crée** les vues
(`/brick-mockup-build`). Quand il livre une source (export Lovable, page HTML
déposée sur le Drive, fichier ou exports Figma), on la **porte** : ce n'est pas
une création, c'est un portage, et la source fait autorité sur tout ce qu'elle
montre.

La sortie est la même des deux côtés : des vues dans le namespace `/mockups`,
navigables, avec le widget de feedback, que le client valide et que la reanalyse
contrôle avant le code.

## Quand ce skill, quand `/brick-mockup-build`

| Le client fournit | Skill |
|---|---|
| Un export Lovable (`.tsx` + `index.css` + `tailwind.config.ts`) | **transcription** |
| Une page HTML, une capture SingleFile, un export de maquette | **transcription** |
| Un fichier ou des exports Figma | **transcription** (les PNG servent d'arbitre visuel, jamais de source de valeurs) |
| Des specs, un brief, des captures de son ancien outil | `/brick-mockup-build` |
| Rien | `/brick-mockup-build` |

Un projet mélange souvent les deux : cinq écrans exportés par le client, trois
qu'il faut inventer. Le choix se fait **écran par écran**, pas par projet. Les
écrans inventés suivent `/brick-mockup-build` et sortent déjà avec la charte ;
les écrans portés suivent ce skill.

## Ce que ça vaut

Mesure 08/2026, onze écrans, deux types de source. Le brief de transcription
déployé ici sort à **94,5** sur un écran simple, **88,3** sur un écran moyen et
**80,1** sur un écran dense, et sur deux écrans jamais utilisés pour régler quoi
que ce soit, **82,4** (export Lovable) et **84,4** (page HTML du client). Le
point de départ, les consignes de maquettage de l'atelier qui ne parlent pas de
transcription, était à **48,3**.

Ce que le mètre pèse : ce que la source affichait et qui est perdu, ce que la
source faisait et qui a cessé de fonctionner, ce qui a été ajouté sans qu'on le
demande.

## La règle d'ordre, et pourquoi elle est contre-intuitive

**On transcrit en valeurs littérales. On normalise après, et seulement après la
validation client.**

C'est l'inverse de ce que fait `/brick-mockup-build`, où les couleurs vivent dans
`tailwind.config.js` et où une valeur arbitraire est un défaut. La mesure tranche
dans l'autre sens pour la transcription, et elle est nette :

- avec la charte déjà remplie sous les yeux **et l'interdiction écrite
  d'arrondir**, l'agent qui transcrit arrondit quand même : 4 couleurs sur 18 et
  7 longueurs sur 20, et l'écran perd **15 points** de fidélité. Un menu de
  tokens invite à substituer, même interdit ;
- demander la fidélité et la discipline de charte à la même passe coûte
  **17 couleurs perdues sur 25** ;
- la normalisation faite après coup sur un lot ne perd **aucun dixième de point**
  de fidélité, sur aucun des trois volets, parce qu'elle remplace une valeur
  **par elle-même nommée**. C'est un calcul, pas une consigne, et un calcul ne
  peut pas arrondir.

**Corollaire opérationnel, à tenir.** Le sous-agent qui transcrit ne voit que la
source, ses feuilles de style et la table de libellés. Il ne reçoit **ni**
`style_guide.html`, **ni** `tailwind.config.js`, **ni** `design_tokens.md`, **ni**
les vues déjà transcrites. Lui montrer la charte, c'est payer les 15 points.

La discipline de charte n'est pas abandonnée pour autant, elle est déplacée :
c'est l'étape 6.

## Avant de transcrire : poser les arbitrages de charte

La phase design a lieu quand même. Si le client n'a pas de charte,
`/brick-design-build` la crée, et elle sert d'arbitre en cas de silence de la
source, jamais de correcteur de la source.

Si le client fournit une source, il faut en plus **poser les arbitrages avant de
porter soixante écrans**, parce qu'ils ne se rattrapent pas après. Cas mesuré :
la source pose cinq familles de police (Geist, Playfair Display, Inter, DM Sans,
Cormorant Garamond) et la cliente a fini par tout ramener à Geist. Porter les
cinq est de la fidélité, pas une dérive, mais la question se pose une fois, au
début, pas écran par écran.

Concrètement, à la main pour l'instant : lire le `:root` de la source (ou relever
les valeurs par fréquence si elle n'a pas de variables), lister les familles à
trancher (les polices, les ors proches, les deux encres), poser la question au
client, noter la réponse dans `doc/memory/design_tokens.md`.

**Cette étape n'est pas encore outillée ni validée.** Un mode d'extraction de
design system existe en laboratoire ; ses seuils sont calibrés sur une seule
source, et elle est pathologique. Ne pas la présenter comme une mesure acquise,
ne pas s'en servir comme d'un gate.

## Procédure

Dans les commandes, `$SK` = `~/.claude/skills/outils-recette`.

### 1. Inventorier les sources et fixer le lot

- Où chercher : `doc/clients_files/`, le Drive partagé, le dépôt fourni.
- Un écran = une tâche kanban dans `doc/memory/mockups/tasks/`, même nommage que
  `/brick-mockup-build` (`{NNN}-{titre}-{etat}.md`).
- **Le lot est limité à la brique courante.** Les écrans des briques suivantes
  restent visibles et grisés, comme dans `/brick-mockup-build`.
- Une source qui n'a pas d'écran correspondant dans `doc/memory/routes.md`, ou
  une route sans source : les deux se signalent avant de commencer.

### 2. Préparer l'entrée d'un écran

Ce qui entre :

- le fichier de l'écran, **plus** ses feuilles de style, **plus** les partials et
  composants qu'il importe. Un export React bien découpé n'a presque aucun
  contrôle en dur dans l'écran lui-même : sans les composants enfants, la vue
  transcrite écrit un champ de recherche là où le composant en contient un et son
  bouton ;
- **la table de libellés restreinte à cet écran**, si la source porte ses textes
  par clés (`t('...')`). Relever les clés appelées par CET écran, sortir leurs
  libellés depuis le fichier de traduction de l'export, et passer cette table
  seule. La table entière (73 Ko sur un projet réel) noie l'entrée ; sans table
  du tout, l'écran ressort en clés ou en anglais.

  Piège mesuré : une extraction qui coupe à l'apostrophe française tronque les
  libellés longs, c'est-à-dire exactement ce que le contenu pèse le plus. Un
  écran a gagné 4,8 points rien qu'en réparant sa table. Vérifier à l'œil que les
  libellés à apostrophe sont entiers.

Ce qui n'entre pas : une maquette du même écran produite avant (première
tentative, capture retouchée), la charte, les tokens, les autres vues. La source
fait autorité.

### 3. Transcrire : un écran, un sous-agent, un brief

Le brief est `brief-transcription.md`, à côté de ce fichier. **Il se passe mot
pour mot**, c'est lui qui est mesuré.

```
Sous-agent, contexte :
  - le contenu de ~/.claude/skills/brick-mockup-transcription/brief-transcription.md
  - la source de l'écran et ses feuilles
  - la table de libellés de l'écran
  - le chemin de sortie : app/views/mockups/<...>.html.erb
Rien d'autre.
```

- **Un écran par sous-agent, jamais deux.** Coût mesuré : 60 à 75 000 jetons pour
  un écran simple, environ 137 000 pour un écran dense.
- La vue sort dans le namespace `/mockups` comme les autres : contrôleur de
  maquette, données fictives en tête (celles de la source, pas des inventées),
  layout du projet, widget de feedback rendu par le layout.
- La vue porte la feuille de style de la source dans un bloc `<style>` de la vue,
  sous une classe racine de page. C'est plus court et plus fidèle que de
  re-dériver chaque règle en classes utilitaires, et le `<style>` inline sera
  résorbé à l'étape 6.

### 4. Contrôler la sortie, écran par écran

Avant de marquer la tâche `done`, trois contrôles outillés.

**Les interactions, d'abord.** C'est le défaut le plus fréquent et le plus cher :
l'affordance est recopiée, le comportement est perdu. Une page de connexion dont
le choix de rôle, les deux connexions externes et l'œil du mot de passe étaient
quatre bascules ressort avec huit liens, elle a l'air complète et elle ne fait
plus rien.

```bash
ruby $SK/interaction_inventory.rb compare --reference <source> --candidate <vue.html.erb>
```

Chaque interaction de la source doit être dans la vue **et branchée** : un bouton
sans gestionnaire compte comme absent. Un contrôle en trop pèse autant qu'un
contrôle manquant.

**Les valeurs, ensuite.**

```bash
ruby $SK/mockup_scan.rb <rails_app_dir> --source <dossier de la source>
```

Ce qui compte ici n'est pas le score d'hygiène (il va être mauvais, c'est normal,
les valeurs sont littérales et le `<style>` est inline) mais la liste des
**valeurs proches sans être égales** : c'est le détecteur de « estimée au lieu de
mesurée ». Cas réel : une colonne transcrite à `302px` là où la source écrit
`grid-template-columns: 1fr 300px`.

**Le rendu, enfin.** Si la source est une page HTML, elle se sert telle quelle
(`python3 -m http.server` dans son dossier) : on écrit une paire à la main dans
`pairs.json` (`base_mockup` = la source servie, `base_app` = le serveur de dev,
format dans `$SK/pairs.example.json`, `pairs_gen.rb` ne sait pas apparier une
source externe) et `style_diff.js` compare les styles calculés aux deux
viewports. Si c'est un export React, il n'y a pas de rendu de référence sans
lancer le projet source : contrôle à la capture (`/playwright`, 1440 et 390 px)
et `mockup_scan --source`.

**Le volume est un signal.** Une vue plus longue que sa source veut dire qu'on a
ajouté : une section inventée, un bloc dupliqué au lieu d'un partial, une barre
de démonstration d'états. Sur une source dense de 1 042 lignes, une bonne
transcription rend environ 1 100 lignes de vue, pas 1 650.

### 5. Faire valider par le client

Chaîne inchangée : `/brick-mockup-review` (contrôle de process avant client),
`/brick-mockup-video` (une vidéo chapitrée), `/brick-mockup-feedback` pour les
retours, et on recommence.

**Rien n'est normalisé tant que le client n'a pas validé.** Ce qu'il valide,
c'est le rendu littéral, celui qui reproduit sa source.

### 6. Après validation : normaliser le lot

Une seule passe, sur le **lot entier**, jamais écran par écran :

```bash
ruby $SK/normaliser.rb --charte doc/memory/charte_normalisee.css \
     --sortie app/views/mockups --rapport /tmp/normalisation.md \
     --json /tmp/normalisation.json --seuil 3 app/views/mockups/<lot>/
```

- **Le seuil monte avec la taille du lot.** 3 pour un lot de 7 écrans (la charte
  tient alors en 68 tokens). À seuil 2 sur le même lot, elle fait 124 tokens et
  ne se stabilise pas : elle gagne encore 16 tokens au septième écran. Sur une
  trentaine d'écrans, monter au-dessus de 3 et vérifier que le compte de tokens
  se stabilise.
- **Vérifier que le rendu n'a pas bougé** : rejouer le contrôle de l'étape 4 sur
  deux ou trois écrans du lot. La mesure dit zéro point perdu ; le contrôle
  confirme que c'est vrai sur CE lot.
- **Arbitrer ce que le rapport signale** : les grappes de quasi-doublons (deux
  ors à 3,75 ΔE), l'accroche à ±1 px, les niveaux d'élévation proposés. L'outil
  ne les applique pas, parce que fusionner deux ors est une décision de design.
  Ce qui est tranché part dans `doc/memory/design_tokens.md` et, si le client est
  concerné, dans la boucle de retours.
- **Verser la charte** produite dans le style guide du projet et dans
  `config/tailwind.config.js`, pour que la phase code hérite d'une source unique.
- **Commit séparé**, jamais mélangé à une correction de contenu : la
  normalisation doit rester relisible comme une passe mécanique.

Ce que l'outil ne touche pas : le JavaScript, les attributs de présentation SVG,
le bloc de données fictives. Documentation complète dans `/outils-recette`.

## Ce que la transcription ne sait pas faire

À dire avant, pas après, parce que ça change l'estimation.

- **Le texte des très grosses sources.** Au-delà d'environ 50 Ko de source dense
  en fiches répétées (un annuaire de 24 profils, un tableau de bord empilant les
  listes), le rappel de libellés tombe entre 12 et 38 %. Sur ces écrans, prévoir
  une passe de reprise du contenu à la main. Une source longue mais pas dense en
  fiches ne pose pas ce problème : 99 % de rappel mesuré sur 75 Ko de HTML.
- **Les composants importés.** La vue écrit ce que le composant contient
  vraiment ; si le composant n'a pas été fourni au sous-agent, il devine. Voir
  l'étape 2.
- **Figma en PNG.** Aucune valeur exacte n'en sort. Arbitre visuel, pas source.
- **Les états que la source ne montre pas.** Les messages d'erreur, l'état vide,
  le quota atteint sont souvent dans le code des gestionnaires ou dans la table
  de libellés : le brief demande de les écrire. S'ils n'existent nulle part, ils
  se créent, et c'est une décision à signaler, pas une transcription.

## Validation gate

Avant de présenter au client :

- [ ] Chaque écran de la brique a sa source identifiée, ou est marqué « créé »
      et passé par `/brick-mockup-build`
- [ ] `interaction_inventory` : aucune interaction de la source absente, aucune
      interaction en trop, aucun contrôle dessiné mais mort
- [ ] `mockup_scan --source` : aucune valeur « proche sans être égale » non
      justifiée
- [ ] Rendu contrôlé (style_diff si la source est servable, capture 1440 et
      390 px sinon)
- [ ] Aucun écran plus long que sa source sans raison écrite
- [ ] Les vues sont dans `/mockups`, navigables, widget de feedback rendu
- [ ] Les arbitrages de charte ont été posés au client (polices, familles de
      couleurs proches)

Après validation client, avant de passer au code :

- [ ] `normaliser.rb` passé sur le lot entier, seuil adapté à sa taille
- [ ] Rendu re-contrôlé après normalisation
- [ ] Grappes signalées arbitrées et notées
- [ ] Charte versée dans le style guide et `tailwind.config.js`

## Ensuite

→ `/brick-mockup-review` puis `/brick-mockup-video` pour la validation client
(boucle avec `/brick-mockup-feedback`).

→ Après validation : l'étape 6 de ce skill (normalisation), **puis**
`/brick-mockup-reanalyse`. Dans cet ordre : la reanalyse pose le tag
`mockups-valides-brique-{N}`, il doit porter les vues telles qu'elles partent
au code.
