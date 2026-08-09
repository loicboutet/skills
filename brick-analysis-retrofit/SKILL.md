---
name: brick-analysis-retrofit
description: "Reconstitue sur un projet ANCIEN les artefacts d'analyse que la chaine actuelle attend et qui n'existaient pas a son demarrage : config.md (derivable), decisions.md (partiellement derivable), objectif.md (brouillon a valider). Rien n'est invente : chaque ligne porte sa source, ce qui n'est pas sourcable devient une question ouverte. Utilise /brick-analysis-retrofit sur un projet livre ou en cours qui n'a pas ces fichiers."
---

# Brick Analysis Retrofit

Une quinzaine de projets clients tournent sans `doc/memory/objectif.md`, `decisions.md`
ni `config.md`. Les skills recents les LISENT (`brick-code-review` deroule le journal de
decisions et confronte le manifeste de config a l'environnement livre ;
`brick-*-feedback` et `brick-daily-triage` arbitrent le scope contre l'objectif signe).
Ce skill les reconstitue, projet par projet, a partir de ce que le depot et le tracker
savent deja.

Le retrofit produit **exactement la meme structure** que `/brick-analysis-build` sur un
projet neuf. Si la structure derive, les skills aval ne s'y retrouvent plus.

## Quand utiliser

- Projet demarre avant que ces artefacts existent, et qui n'en a aucun
- Avant une `brick-code-review` sur un projet ancien (elle reclame les deux journaux)
- Avant de reprendre un projet dormant, ou a une passation

Ne PAS utiliser sur un projet neuf : c'est `/brick-analysis-build` qui les cree.

## La regle qui domine tout le skill

**Interdiction absolue de fabriquer du contenu.**

L'atelier a un incident fondateur : des donnees inventees (compteurs en dur, images
fabriquees) livrees en production chez un client. Un artefact reconstitue qui contient
une decision que personne n'a prise, ou un objectif que le client n'a pas signe, est
**pire que pas d'artefact du tout**, parce que le prochain agent le lira comme une
verite et batira dessus.

Trois etats, pas quatre :

| Etat | Comment on l'ecrit |
|------|--------------------|
| Fait sourcable | Ligne normale, avec sa SOURCE (`fichier:ligne`, `commit abc1234`, `tracker #1756`, `doc/memory/x.md §2`) |
| Manque | Une QUESTION dans la section « Questions ouvertes », jamais une reponse |
| Deduction plausible | N'existe pas. Soit on la source, soit c'est une question. |

Interdit : « probablement », « il a du etre decide que », « par defaut on suppose ».
Une phrase sans source qui n'est pas une question est un bug du retrofit.

**Une source approximative est une source fausse.** Deux fautes, constatees sur la
premiere execution reelle du skill (GesPilot, 09/08/2026) :

- *Le numero de ligne de memoire.* Ecrire `config/deploy.yml:47` quand la cle est a la
  ligne 45 rend la ligne invalidable : le relecteur ouvre, ne trouve pas, et doute de
  tout le fichier. Chaque `fichier:ligne` se COPIE depuis une sortie `grep -n` ou
  `cat -n`, jamais d'apres la lecture d'un extrait. Un intervalle (`:59-68`) est
  acceptable et souvent plus honnete qu'un point.
- *Le compte annonce qui ne correspond pas a la liste.* « 18 autres retours » suivi de
  17 numeros d'issues. Tout nombre annonce dans une phrase doit etre recomptable sur
  l'enumeration qui le suit, sinon on retire le nombre.

## Les trois artefacts, trois natures differentes

| Artefact | Nature | Confiance | Livrable |
|----------|--------|-----------|----------|
| `config.md` | Entierement derivable du code | Elevee | Utilisable tel quel |
| `decisions.md` | Partiellement derivable (docs, tracker, git) | Moyenne | Amorce + questions ouvertes |
| `objectif.md` | NON derivable | Nulle | **Brouillon** a valider par le chef de projet |

---

## Procedure

### 0. Prealables

```bash
cd ~/projects/{projet}
git status --short          # noter l'etat AVANT : le retrofit ne doit rien y changer d'autre
ls doc/memory/              # ne JAMAIS ecraser un fichier existant
```

Si un des trois fichiers existe deja, ne pas le reecrire : le lire, et n'ajouter que ce
qui manque, en le disant en tete de section.

Recuperer aussi l'identite du projet (`app_id`, slug) : `README.md`, `CLAUDE.md`, ou
`get_destination_profile`. L'`app_id` sert au tracker et se lit souvent dans les
adresses de creation d'issues (`mockup-feedback+app{ID}@5000.dev`).

### 1. Inventaire des sources, avant d'ecrire quoi que ce soit

```bash
find doc -type f -name '*.md' | sort
git log --format='%h|%ad|%s' --date=short | wc -l
ls config/environments config/deploy*.yml .github/workflows .kamal 2>/dev/null
```

Ecrire la liste des sources trouvees. Un projet qui n'a ni `doc/memory/*.md` ni tracker
donnera un `decisions.md` quasi vide : c'est un resultat honnete, pas un echec, et il
faut le dire au chef de projet plutot que de meubler.

---

### 2. `doc/memory/config.md` — le manifeste, entierement derivable

C'est la partie mecanique. Elle se fait au grep, et son resultat est fiable.

#### 2.1 Collecter les LECTURES (qui consomme quoi)

```bash
grep -rn 'ENV\[\|ENV\.fetch' --include='*.rb' --include='*.yml' --include='*.erb' \
  app config lib db script bin
grep -rn 'credentials\.dig\|credentials\.config\|application\.credentials' \
  --include='*.rb' --include='*.yml' app config lib
grep -n '^ENV\|^ARG' Dockerfile
```

Ignorer le bruit de gabarit Rails : `config/boot.rb` (`BUNDLE_GEMFILE`), les blocs
commentes de `config/storage.yml`, les commentaires de `config/puma.rb`.

#### 2.2 Collecter les ECRITURES (qui fournit quoi, par environnement)

```bash
cat config/deploy.yml                 # env.clear + env.secret = prod
cat config/deploy.*.yml               # une destination Kamal par environnement
cat .kamal/secrets
grep -n 'secrets\.' .github/workflows/*
sed -n '1,60p' config/environments/development.rb
```

**Piege Kamal a ne pas rater** : un fichier de destination (`config/deploy.staging.yml`)
est **fusionne** sur `config/deploy.yml`, il ne le remplace pas. Une cle absente du
fichier staging n'est pas absente en staging : elle est **heritee de la production**.
C'est exactement comme ca qu'un DSN d'erreurs de prod se retrouve a collecter les erreurs
de staging.

#### 2.3 Les credentials chiffres : les CLES, jamais les valeurs

Seulement si `config/master.key` existe ou si `RAILS_MASTER_KEY` est dans l'env :

```bash
bin/rails runner 'def walk(h, p = []) = h.each { |k, v| v.is_a?(Hash) ? walk(v, p + [k]) : puts((p + [k]).join(".")) }; walk(Rails.application.credentials.config)'
```

Cette commande imprime les **chemins de cles** (`postmark.api_token`) et aucune valeur.
Ne jamais lancer `bin/rails credentials:show` a l'ecran : il deverse les secrets en clair
dans le transcript.

Si la cle maitre est absente (frequent : elle n'est pas dans le depot, et c'est bien),
lister les cles ATTENDUES par le code (le grep de 2.1) et ecrire en face
« contenu non verifiable depuis ce poste, cle maitre absente ». C'est un fait, pas un
trou.

#### 2.4 Les trois croisements qui trouvent les vrais defauts

Faire les trois, dans l'ordre. C'est la valeur du fichier.

1. **Cle posee, lue nulle part** : elle figure dans `deploy*.yml`, les workflows ou le
   Dockerfile, et aucun `ENV[...]` ne la lit. Soit un reliquat, soit un consommateur
   supprime.
2. **Cle lue, posee nulle part** : le code fait `ENV["X"]` et aucun fichier de
   deploiement ne la fournit. Verifier alors ce que vaut le defaut : un `ENV.fetch("X",
   "…")` avec un defaut faux est une panne silencieuse ; un `ENV["X"]` sans defaut
   desactive une fonction sans le dire.
3. **Deux endroits qui pretendent fournir la meme chose.** Le defaut le plus couteux, et
   celui qui a fait qu'un envoi d'e-mails serait tombe en production. Chercher :
   - un reglage lu UNE FOIS au boot et un ecran d'administration qui prétend le piloter ;
   - un `ENV.fetch("HOST", "…")` dont le defaut doit rester egal au `proxy.host` de Kamal
     (deux verites a tenir synchrones a la main) ;
   - une valeur heritee par fusion Kamal alors que l'environnement en voudrait une autre.

#### 2.5 Format (identique a `/brick-analysis-build`, plus une colonne Source)

```markdown
# Manifeste de configuration — {projet}

> Reconstitue le {date} par /brick-analysis-retrofit, a partir du code du depot
> (commit {sha}). Derive mecaniquement : confiance elevee.
> Aucune valeur de secret n'y figure.

| Cle | Consommateur (fichier:ligne) | dev | staging | prod | Si absente | Source |
|-----|------------------------------|-----|---------|------|------------|--------|

## Credentials chiffres (cles seulement)

## Reglages d'environnement qui valent configuration

| Reglage | Valeur | Fichier:ligne | Motif ecrit dans le code |

Tout ce qui se comporte comme un reglage sans passer par une variable d'environnement :
`config.time_zone`, les interceptors de mailer, la methode de livraison en dev, les
timeouts d'un service externe, le planning `config/recurring.yml`. Un lecteur qui cherche
« pourquoi les rappels partent a 6 h » cherche dans le manifeste, pas dans les
initializers. Le motif se RECOPIE du commentaire de code, il ne se reformule pas.

## Points suspects
### 1. {titre} — {gravite}
{constat, avec les deux fichiers:lignes qui se contredisent}

## Questions ouvertes
- {ce que le code ne dit pas : qui detient le compte, quelle valeur en prod}
```

---

### 3. `doc/memory/decisions.md` — partiellement derivable

On ne reinvente pas l'histoire du projet. Trois gisements sourcables, et rien d'autre.

#### 3.1 Les documents `doc/memory/` existants

```bash
grep -rn 'Changement de scope\|Journal de scope\|Arbitrage\|Decision\|Écarté\|Retenu' \
  doc/memory --include='*.md' | head -60
```

Ce qui compte : les blocs « Changement de scope » d'`acceptance_criteria.md` (ils portent
date, demande, origine, impact : c'est deja une decision au format), un `arbitrages.md`
ou un `review.md` de brique, les sections de decisions d'une `analyse.md`. Reprendre la
formulation d'origine, ne pas la reecrire.

#### 3.2 Le tracker : `later_brick` et `rejected`

Ce sont des decisions au sens strict : quelqu'un a decide de ne pas faire, ou de
repousser. Charger le schema (`ToolSearch` : `select:mcp__nexrai__tracker_issue_tool`),
retrouver le projet par son nom via `tracker_project_tool(action: "list", search: "…")`,
puis :

```
tracker_issue_tool(action: "list", tracker_project_id: "{id}", status: "later_brick", limit: "50")
tracker_issue_tool(action: "list", tracker_project_id: "{id}", status: "rejected",    limit: "50")
```

**La liste tronque les descriptions et n'affiche pas les notes internes.** Le motif de la
decision est presque toujours dans `internal_notes`, qui n'apparait qu'avec
`action: "get"`. Faire un `get` par issue retenue. C'est le poste de cout principal du
skill : compter une trentaine d'appels sur un projet bavard.

**Depouillement partiel : autorise, mais declare.** Sur un projet bavard, le budget
n'ira pas au bout des `get`. Priorite : les `rejected` d'abord (un refus porte toujours un
motif), puis les `later_brick` qui touchent au perimetre contractuel. Ce qui reste ne
disparait pas en silence : il part dans une section **« Non depouille »** qui **enumere
tous les numeros d'issues** restants, et la question correspondante va en questions
ouvertes, adressee a l'analyse de la brique suivante. Le compte annonce doit egaler le
nombre de numeros listes. Un retrofit honnete qui dit « 17 issues non lues, les voici »
vaut mieux qu'un retrofit qui resume 17 issues sans les avoir ouvertes.

Ne pas remonter les issues `fixed` (ce sont des corrections, pas des decisions) sauf si
leurs notes internes tranchent explicitement une regle metier.

#### 3.3 L'historique git, quand un message explique un choix

```bash
git log --format='%h|%ad|%s%n%b%n---' --date=short | \
  grep -iE -B2 'ecart|écart|retenu|plutot|plutôt|au lieu de|on a choisi|decide|décidé'
```

Ne retenir que les messages qui **expliquent** un choix (« X plutot que Y parce que… »),
pas ceux qui decrivent un travail. Le commentaire de code adjacent est souvent la vraie
source : beaucoup de projets de l'atelier documentent la decision juste au-dessus de la
ligne concernee (`config/application.rb`, les initializers). Ce commentaire est une
source recevable, avec son `fichier:ligne`.

#### 3.4 Ce qu'on N'ecrit PAS

`/brick-analysis-build` exige, pour chaque entite du data model, une ligne « suppression »
et une ligne « etats degrades ». **En retrofit, on ne remplit ces tableaux qu'a partir du
code observe** (`dependent: :destroy`, `dependent: :restrict_with_error`, un scope
`active`), avec la ligne du modele en source. Une entite dont le code ne dit rien laisse
la case a « non observe », et la question part dans la section ouverte. On ne decide pas
retroactivement a la place de celui qui a code.

#### 3.5 Format

```markdown
# Journal de decisions — {projet}

> Amorce le {date} par /brick-analysis-retrofit. Les entrees anterieures sont
> RECONSTITUEES a partir de sources ecrites ; chacune porte la sienne. Ce qui n'a
> pas de source est en « Questions ouvertes », jamais en decision.

## Regles
{les 5 regles de /brick-analysis-build, recopiees telles quelles}

## Decisions reconstituees
| Date | Decision (la question tranchee) | Defaut retenu | Motif | Reversible | A signaler | Source |
|------|--------------------------------|---------------|-------|------------|------------|--------|

## Non depouille
{les numeros d'issues laisses de cote, tous listes, avec la raison et le moment ou on
les reprendra}

## Decisions par entite, observees dans le code
| Entite | Suppression (observee) | Etats degrades (observes) | Source |
|--------|------------------------|---------------------------|--------|

## Questions ouvertes (aucune source trouvee)
- {formulees comme des questions, adressees au chef de projet}

## A partir d'ici, le journal se remplit au fil de l'eau
Le retrofit amorce, il ne comble pas. Toute decision prise apres le {date} s'ajoute
ci-dessous au format normal, sans colonne Source (la source, c'est la ligne elle-meme).

| Date | Decision | Defaut retenu | Motif | Reversible | A signaler |
|------|----------|---------------|-------|------------|------------|
```

---

### 4. `doc/memory/objectif.md` — un BROUILLON, jamais un fait

Le QUOI signe est un artefact **commercial**. Aucun depot git ne le contient. Le skill
produit un brouillon, et le dit en toutes lettres, en premiere ligne du fichier.

Sources acceptables, par ordre de force :

1. le contrat ou l'annexe de perimetre s'il est cite dans `doc/memory/` (avec sa
   reference : date, article, identifiant du document) ;
2. `acceptance_criteria.md` (le COMMENT), dont on remonte au QUOI par regroupement ;
3. les echanges client accessibles (comptes rendus d'appel, artefacts de cadrage) ;
4. le README du projet.

Le brouillon reste dans le format de `/brick-analysis-build` (5 a 15 lignes de QUOI
metier, criteres de succes client, signature), avec deux ajouts obligatoires :

```markdown
# Objectif — Brick #{N} : {nom}

> **BROUILLON — a valider par le chef de projet, non signe.**
> Reconstitue le {date} par /brick-analysis-retrofit a partir des sources listees
> en bas. Tant qu'il n'est pas valide, les skills aval doivent le traiter comme une
> HYPOTHESE, pas comme le contrat : il ne peut pas servir a refuser une demande client.
> {Si la brique est deja livree :} La brique a ete LIVREE avant que ce document existe.
> Ecrit apres coup, il risque de decrire ce qui a ete fait plutot que ce qui avait ete
> promis. A confronter au contrat avant signature.

## Ce que la brique doit rendre possible (QUOI)
## Criteres de succes client
## Sources du brouillon
| Affirmation | Source |

## Ou ce brouillon extrapole
- {chaque point ou l'on a regroupe, reformule, ou comble un blanc}

## Signature
NON SIGNE. A valider par : {chef de projet}. Date : —
```

La section « Ou ce brouillon extrapole » n'est jamais vide. Si elle l'est, c'est qu'on
n'a pas cherche : remonter au QUOI depuis des criteres techniques est **toujours** une
extrapolation, et le perimetre reel signe peut etre plus large que ce qui a ete livre.

---

### 5. `doc/memory/jeu_de_donnees.md` — optionnel, seulement si des seeds existent

Si le projet a `db/seeds.rb`, `db/seeds/` ou `test/fixtures/*.yml` exploitables, proposer
d'amorcer le fichier en decrivant le jeu **EXISTANT**, avec cet avertissement en tete :

> Ceci decrit le jeu de donnees EXISTANT du projet, releve dans les seeds et fixtures.
> Ce n'est PAS le jeu canonique complet au sens de /brick-analysis-build : il n'a pas ete
> genere par le protocole (partitions, quotas, premortem).

Puis passer les categories du contenu minimal de `/brick-analysis-build` (personas,
etats difficiles, argent aux bornes, chaines hostiles, temps, volumes, multi-tenant) et
**signaler celles qui sont absentes**. Les signaler, pas les inventer : un cas limite
ajoute au document mais absent des seeds ferait croire a une couverture qui n'existe pas.

---

### 6. Mettre a jour le README du projet

Ajouter les trois fichiers a la checklist de documentation, avec leur statut reel :

```markdown
- [x] config.md (reconstitue le {date}, derive du code)
- [x] decisions.md (amorce le {date}, {N} decisions sourcees, {M} questions ouvertes)
- [ ] objectif.md (BROUILLON, non signe — a valider)
```

### 7. Rendre la main. Rien n'est commite automatiquement.

Le skill **ecrit les fichiers, point**. Pas de `git add`, pas de `git commit`. Le chef de
projet relit, **surtout `objectif.md`**, et commite lui-meme. Un brouillon d'objectif
commite sans relecture devient, au commit suivant, un objectif tout court.

Terminer par un compte rendu court : ce qui a ete trouve, ce qui ne l'a pas ete, et la
liste des questions ouvertes qui attendent une reponse humaine.

---

## Validation gate

- [ ] Les trois fichiers existent dans `doc/memory/` (ou ont ete completes sans ecrasement)
- [ ] `config.md` : chaque cle a un consommateur `fichier:ligne`, aucune valeur de secret
      n'apparait, et les trois croisements de 2.4 ont ete faits (lue-non-posee,
      posee-non-lue, double fourniture)
- [ ] `decisions.md` : **chaque ligne du tableau a une source non vide**. Une ligne sans
      source est une invention : la deplacer en question ouverte.
- [ ] `decisions.md` se termine par la section « a partir d'ici, au fil de l'eau »
- [ ] `objectif.md` porte « BROUILLON — non signe » en premiere ligne, a sa table de
      sources, et sa section « ou ce brouillon extrapole » n'est pas vide
- [ ] Aucun « probablement », « sans doute », « il a du etre » dans les trois fichiers
      (`grep -inE 'probablement|sans doute|il a du|on suppose' doc/memory/{config,decisions,objectif}.md`)
- [ ] **Cinq references tirees au hasard ont ete rouvertes** (`sed -n '{n}p' {fichier}`) et
      pointent bien la ligne annoncee. Une seule qui derape : reverifier toutes celles du
      meme fichier, elles ont ete ecrites de memoire
- [ ] Chaque nombre annonce en toutes lettres (« N decisions », « N issues reportees »)
      egale le nombre d'elements de la liste qui le suit
- [ ] `git status` ne montre que les fichiers ecrits par le retrofit, rien d'autre
- [ ] Rien n'est commite ; le compte rendu et les questions ouvertes sont remontes

## Cout

Une passe par projet, et on ne la refait pas. Le gros du temps part dans les `get`
d'issues du tracker (3.2) et dans la lecture des documents de brique existants. A partir
de la, les fichiers vivent au fil de l'eau : `brick-code-build` ajoute au manifeste,
`brick-*-feedback` et `brick-code-fix` ajoutent au journal. Relancer le retrofit sur un
projet deja traite ne rapporterait rien et risquerait d'ecraser des entrees reelles.

Provenance : execute une premiere fois sur GesPilot le 09/08/2026 (une quinzaine de
projets clients tournent sans ces trois fichiers). Rendement observe sur ce projet :
`config.md` a sorti cinq points suspects dont un defaut reel (le staging emet ses erreurs
dans le projet GlitchTip de la production, etiquetees `production`) ; `decisions.md` a
retrouve 23 decisions sourcees, toutes issues d'un document ecrit ; `objectif.md` n'a
rien pu etablir que le chef de projet n'ait a valider. Les deux fautes de cette passe
(numeros de ligne ecrits de memoire, compte annonce faux) sont devenues les deux garde-fous
de la section « une source approximative est une source fausse ».

## Ensuite

→ `brick-code-review` si le projet est en phase code (elle deroule `decisions.md` ligne a
ligne et confronte `config.md` a l'environnement livre : c'est la que le retrofit paie).

→ `brick-analysis-review` si le projet repart sur une nouvelle brique : l'analyse
existante se relit alors avec les trois fichiers en main, et le brouillon d'`objectif.md`
se fait valider a ce moment-la.
