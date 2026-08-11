---
name: brick-design-review
description: "Relecture MESUREE de la charte produite par /brick-design-build, avant de s'appuyer dessus pour les mockups : audit mecanique a l'outil (charte_scan), nettoyage des valeurs hors token, puis les controles humains (fidelite au brief, contraste, coherence des composants). Utilise /brick-design-review apres /brick-design-build, avant /brick-mockup-build."
---

# Brick Design Review

Relit la charte produite par `brick-design-build` avant de la figer comme reference des
mockups. Ce n'est pas une refonte, et ce n'est plus un controle a l'oeil : la moitie du
travail est mecanique et se mesure.

## Pourquoi cette etape existe (mesure du banc, aout 2026)

La charte est le SEUL artefact que recoit l'agent qui construira les ecrans. Et il ne lit pas
les regles qu'on lui ecrit : **il imite le code qu'on lui donne**. Une charte qui pose ses
valeurs entre crochets (`font-[800]`, `max-w-[1200px]`) ou dans un `style=` autorise la meme
chose dans tous les ecrans qui la lisent ; une charte ecrite au token les discipline.

C'est mesure, pas suppose : voir `~/skill-lab-candidates/lab/journal.md`, passes C6 et C7.

## Quand utiliser

- Juste apres `brick-design-build`, avant `brick-mockup-build`.
- Aussi sur une charte heritee (projet ancien, charte fournie par le client) avant de
  construire dessus.

## Pre-requis

- `doc/memory/style_guide.html` et le `tailwind.config.js` du projet.
- La source du brief (`brick-design-brief`) pour confronter charte et attentes client.

## Process

### 1. Audit mecanique (a l'outil, jamais a l'oeil)

```bash
ruby ~/.claude/skills/outils-recette/charte_scan.rb doc/memory/   # ou le dossier charte/
```

Il sort la liste actionnable, pas un compteur : quelle classe arbitraire a quelle ligne,
quel `style=`, quelle valeur non nommee, quelles couleurs a moins de 4 ΔE l'une de l'autre,
et les trous de couverture. Chaque ligne du rapport est un point a traiter.

### 2. Nettoyer, dans cet ordre

- **Classes arbitraires `[..]`** : la valeur entre crochets devient un token nomme dans
  `tailwind.config.js` et la classe consomme le token ; ou, si un token rend deja cette
  valeur, la classe devient celle du token.
- **`style=` en dur** : meme traitement, rien ne reste dans un attribut `style`.
- **Quasi-doublons de couleur** : deux couleurs a moins de 4 ΔE ne se distinguent pas a
  l'oeil. L'audit les SIGNALE ; il ne dit pas quoi en faire.
  **Regarder d'abord leurs ROLES.** Deux valeurs indiscernables qui font le meme travail
  (deux gris de bordure, deux crans voisins d'une meme echelle) sont un token : on garde
  la plus employee et on bascule ses usages. Deux valeurs indiscernables qui portent des
  roles DIFFERENTS (une surface de page et une teinte d'etat de succes, un survol de ligne
  et un fond de carte) ne se fusionnent JAMAIS : c'est l'une d'elles qui doit s'eloigner,
  sinon l'ecart semantique disparait de l'ecran. Defaut paye par le banc en C7 : un
  relecteur a fusionne `beton-50` (fond de page), `reseda-50` (survol) et `service-50`
  (succes), tous a moins de 4 ΔE ; le fond de page est devenu vert pale et l'alerte de
  succes a perdu son contour. Fusionner est une decision de design, jamais un calcul.
- **Valeurs non nommees** : couleur appliquee absente des tokens, custom property CSS
  definie dans le guide et pas dans la config.

**Nommer n'est pas arrondir.** Une valeur nommee doit rendre exactement ce qu'elle rendait.
Le vocabulaire des nouveaux tokens prolonge celui de la charte, il ne le remplace pas.

### 3. Les controles qui restent humains

1. **Fidelite au brief** : couleurs, typo et ton correspondent a ce que le client a fourni.
2. **Accessibilite** : contraste texte/fond suffisant (WCAG AA), etats focus visibles,
   tailles lisibles. Si une fusion de quasi-doublons a change un rapport de contraste,
   il se recalcule.
3. **Coherence des composants** : boutons, champs, cartes, alertes homogenes et
   reutilisables.
4. **Deux themes si prevu** (clair/sombre) : les deux tiennent, pas une inversion naive.
5. Signaler au client un choix de fond a trancher ; ne pas le trancher seul.

### 4. Verifier que le rendu n'a pas bouge

Capture du style guide avant / apres (`playwright-cli`), comparaison. Un gain d'hygiene paye
par une perte visuelle n'est pas un gain. Corriger si quelque chose a casse.

### 5. Rejouer l'audit et consigner

Relancer `charte_scan.rb` et coller le verdict final dans le journal de decisions du projet.

## Ce que cette etape n'est PAS

- **Pas une refonte.** Le parti pris visuel, la structure du guide, ses sections et ses
  composants ne changent pas. Si le diff depasse une dizaine de pourcents des lignes
  d'origine, c'est qu'on a recommence la charte au lieu de la relire : reprendre.
- **Pas un comblement de trous.** Les trous de couverture releves par l'audit se signalent ;
  les combler est le travail de `brick-design-build`, pas de sa relecture.
- **Pas un paragraphe de bonnes pratiques ecrit dans la charte.** Mesure du banc : ecrire les
  regles dans le style guide ne change rien a ce que fait l'agent d'aval. Ce qui le change,
  c'est le code qu'il a sous les yeux.

## Validation gate

- [ ] `charte_scan.rb` : 0 classe arbitraire, 0 `style=` en dur, 0 couleur hors token
- [ ] Chaque grappe de quasi-doublons arbitree : fusionnee si meme role, ecartee si roles
      differents, jamais laissee telle quelle sans decision ecrite
- [ ] Charte fidele au brief client
- [ ] Contraste AA respecte (recalcule apres toute fusion), focus visibles
- [ ] Composants coherents et reutilisables
- [ ] Rendu avant/apres compare, rien de casse
- [ ] Diff reste de l'ordre de la relecture, pas de la reecriture
- [ ] Trous de couverture signales, choix de fond signales au client

## Ensuite

→ `brick-mockup-build` : construire les mockups sur cette charte.
