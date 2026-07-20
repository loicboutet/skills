---
name: playwright
description: "Piloter un navigateur depuis le terminal avec playwright-cli : explorer une page, cliquer, remplir, capturer, inspecter le reseau. Remplace l'ancien MCP Playwright. Utilise /playwright, ou reference depuis brick-video, brick-mockup-review et brick-review."
---

# Playwright en ligne de commande

On pilote le navigateur avec **`playwright-cli`**, pas avec un serveur MCP.

## Pourquoi la CLI et plus le MCP

Le serveur MCP Playwright lance Chrome avec `handleSIGINT` et `handleSIGTERM` a
`false` et n'installe aucun handler de nettoyage. Quand la session de l'agent se
termine, le serveur meurt mais **Chrome survit indefiniment**. Sur un VPS
partage, les orphelins s'accumulent : on a mesure **40 processus pour 8,2 Go**,
le plus vieux depuis 28 heures, sur une machine qui n'a que 30 Go. C'est la
cause des « Playwright MCP deconnecte » que remontaient les agents.

La CLI resout ca : ses sessions sont **nommees, listables et fermables**.

## Les commandes

```bash
playwright-cli -s=<session> open <url>     # ouvre le navigateur sur une page
playwright-cli -s=<session> goto <url>     # navigue
playwright-cli -s=<session> snapshot       # arbre d'accessibilite avec des `ref`
playwright-cli -s=<session> find <texte>   # cherche dans le snapshot
playwright-cli -s=<session> click <ref>    # clique (utiliser le ref du snapshot)
playwright-cli -s=<session> fill <ref> <texte>
playwright-cli -s=<session> eval "() => document.title"
playwright-cli -s=<session> screenshot
playwright-cli -s=<session> close          # FERME TA SESSION QUAND TU AS FINI
```

Aussi disponibles, absents du MCP : inspection reseau (`requests`, `request`,
`response-body`), mocking (`route`), cookies et localStorage, onglets
(`tab-new`, `tab-select`), `pdf`, enregistrement video.

`playwright-cli --help` liste tout, `playwright-cli <commande> --help` detaille.

## Regles

**Toujours nommer sa session** avec `-s=<nom>`. Sans nom, plusieurs agents se
retrouvent dans le meme navigateur et se marchent dessus : l'un navigue sous les
pieds de l'autre. Un nom parlant et unique, par exemple `-s=mockup-review-42`.
On peut aussi poser `PLAYWRIGHT_CLI_SESSION` dans l'environnement plutot que
repeter le drapeau.

**Toujours fermer sa session** avec `close` quand le travail est fini. C'est ce
qui evite de recreer le probleme qu'on vient de supprimer. En cas de doute :

```bash
playwright-cli list        # que tourne-t-il en ce moment ?
playwright-cli close-all   # ferme proprement toutes les sessions
playwright-cli kill-all    # force, pour les restes zombies
```

**Ne pas relancer un `open` sur une session deja ouverte** : la session garde son
etat (page courante, cookies) entre deux commandes, c'est tout l'interet.
Enchaine les commandes, ne reouvre pas.

## Ce qui est deja configure

Le `--no-sandbox` est injecte automatiquement par un wrapper
(`/usr/local/bin/playwright-cli`), qui pointe la config globale
`/opt/nexrai/playwright-cli.config.json`. Sans lui, Chrome ne peut pas creer de
namespace PID dans le conteneur et le daemon meurt au demarrage. Il n'y a donc
rien a passer a la main, et **il ne faut pas** ajouter `--no-sandbox` soi-meme.

Si tu vois `Failed to move to new namespace ... Operation not permitted`, c'est
que le wrapper n'a pas ete pris : verifie que `which playwright-cli` renvoie
bien `/usr/local/bin/playwright-cli` et non `/usr/bin/playwright-cli`.

## Plusieurs agents en parallele

C'est supporte et verifie : deux sessions nommees, ouvertes en meme temps,
gardent chacune leur page sans interference. Chaque session coute environ
**287 Mo**, donc ferme la tienne : trois sessions actives et visibles valent
mieux que trente orphelines.

## Pour du repetable, ecris un script

La CLI est faite pour l'exploration pas a pas. Pour une capture reproductible ou
un parcours rejoue a l'identique (le pipeline video par exemple), un script
Node avec le module `playwright` reste plus adapte : il demarre, fait son
travail, et sort.
