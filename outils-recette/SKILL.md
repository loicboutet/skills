---
name: outils-recette
description: Les deux outils de recette de l'atelier, utilisables sur n'importe quel projet Rails a n'importe quelle phase - style_diff.js (ecart maquette/application, propriete par propriete, remplace la revue pixel a l'oeil) et facade_scan.rb (controles d'interface non branches). Utilise /outils-recette pendant une recette, une review pre-livraison ou un audit.
---

# Outils de recette

Deux scripts autonomes, deposes avec ce skill dans `~/.claude/skills/outils-recette/`.
Ils ne remplacent pas la recette, ils suppriment le travail d'oeil qu'un humain
faisait mal : ils sortent une liste d'ecarts concrets, on ne juge que le residu.

## style_diff.js — ecart maquette / application

Compare les STYLES CALCULES des deux cotes, element par element, au lieu de
comparer des pixels. Sort la propriete qui differe, pas une image rouge.

```bash
node ~/.claude/skills/outils-recette/style_diff.js --pairs pairs.json --out doc/memory/brick-{N}/parite/
```

`pairs.json` liste des paires `{name, mockup_url, app_url}` plus les options
(viewports, auth, allowlist). Modele complet : `pairs.example.json` a cote.
Options : `--only <motif>`, `--viewport mobile`, `--fail-on bloquant|majeur|mineur`,
`--headed`. Sortie : `index.html` autonome (filtres par gravite), un JSON par
paire, `resume.json`. Code de sortie non nul s'il reste des ecarts hors tolerance,
donc utilisable comme gate.

Detecte en plus, et ce sont les deux qui coutent le plus cher en livraison :
- le **debordement horizontal** par viewport (mobile 390 px surtout) ;
- les **feuilles de style etrangeres** chargees a cote des notres (un export
  Lovable ou Figma qui cohabite avec le design system : c'est ce qui a deforme
  une application entiere pendant des semaines).

Ce qu'il ne voit pas : un seul etat par page (ni survol, ni focus, ni modale, ni
formulaire en erreur), ni le contraste, ni la taille des cibles tactiles. Les
positions sont volontairement tolerantes (un decalage isole de 3 px passe).
La precision monte quand les deux cotes affichent les MEMES donnees : c'est la
raison d'etre du jeu de donnees canonique (`doc/memory/jeu_de_donnees.md`).

## facade_scan.rb — controles non branches

Chasse la facade : l'element qui a l'air de marcher et n'est relie a rien. C'est
le defaut signature du pipeline maquette vers code.

```bash
ruby ~/.claude/skills/outils-recette/facade_scan.rb static .            # analyse des vues
ruby ~/.claude/skills/outils-recette/facade_scan.rb crawl http://localhost:3000 --cookie "..."
ruby ~/.claude/skills/outils-recette/facade_scan.rb static . --json     # resume machine
```

Mode `static` : champs de formulaire sans `name`, `data-controller`/`data-action`
pointant vers un controleur Stimulus inexistant, `data-action` pose sur un element
inerte, liens morts (`href="#"`), helpers de route inconnus, nombres en dur
suspects dans les vues. Mode `crawl` : 404/500, champs sans `name` dans le DOM
rendu, formulaires sans action, boutons non branches. `app/views/mockups` est
exclu (c'est la reference, elle a le droit d'etre inerte).

Toujours code de sortie 0 : c'est un rapport, pas un gate. Beaucoup de reglages
et l'allowlist sont en tete de script.

### La fleche inverse : `reachability` et `readwrite`

`static` et `crawl` verifient qu'un controle mene quelque part. Ces deux modes
verifient l'inverse : ce que le serveur sait faire, et que l'interface ne permet
pas de declencher ni de remplir.

```bash
ruby ~/.claude/skills/outils-recette/facade_scan.rb reachability .            # routes sans geste
ruby ~/.claude/skills/outils-recette/facade_scan.rb readwrite .               # colonnes en sens unique
ruby ~/.claude/skills/outils-recette/facade_scan.rb reachability . --mockups  # phase maquettes
ruby ~/.claude/skills/outils-recette/facade_scan.rb readwrite . --mockups
```

`reachability` confronte les routes (`bin/rails routes`, repli sur
`config/routes.rb` avec `--no-boot`) aux gestes des vues : `form_with`,
`button_to`, `link_to` avec `turbo_method`, `formaction`, `<form action>`.
Bloquant : action non-GET qu'aucun geste ne vise, et route declaree vers une
action inexistante. Info : page GET vers laquelle aucun lien ne mene, et action
atteinte seulement par du JS (le verbe n'est alors pas verifiable).

`readwrite` confronte chaque colonne de `db/schema.rb` a ses lectures (vue,
helper, mailer, PDF, requete) et a ses ecritures (`permit`/`expect`, champ de
formulaire, affectation, seed). Sort la colonne **lue mais jamais saisissable**
et la colonne **saisie mais jamais lue** : deux facades symetriques. Bloquant si
la colonne part dans un document sortant (PDF, e-mail).

`--mockups` cadre les deux sur la phase maquettes, avant le code : les routes
prevues face aux gestes de `app/views/mockups`, et les champs de
`doc/memory/data_models.md` face a ce que les maquettes affichent et saisissent.
C'est la que ca coute le moins cher de corriger.

Limites connues : une lecture dont le receveur n'est pas identifiable compte pour
toutes les tables portant la colonne (le rapport le signale) ; une ecriture qui
passe par un attribut virtuel autre que `<colonne>_input` echappe au scan ; en
mode maquettes le rapprochement se fait sur les noms, un champ nomme autrement
dans la maquette que dans `data_models.md` remonte comme absent.

## Quand s'en servir

- Pendant `/brick-code-review` : `style_diff` sur toutes les pages de la brique
  (le rapport devient le rapport de parite envoye au client via
  `~/.nexrai/bin/nexrai-parite`), `facade_scan` sur l'ensemble du projet.
- En fin de lot pendant `/brick-code-build` : les deux, en vitesse, sur les pages
  du lot.
- Sur un projet deja livre : les deux, tels quels. Ils ne demandent aucune
  installation et ne modifient rien.
- Apres un `/brick-code-fix` qui touche une vue : `style_diff --only <page>`.

## Verite d'usage

Sur une livraison reelle dont la review avait conclu « pixel match 32 pages,
32/32 conformes », `style_diff` a trouve 157 ecarts, dont un debordement mobile
sur 14 pages sur 15 et une pastille de notification cassee par un conteneur Turbo
Stream, invisible sur une capture. Un rapport sans ecart veut dire quelque chose ;
un oeil humain qui dit « c'est conforme » ne veut rien dire.
