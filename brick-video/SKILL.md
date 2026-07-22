---
name: brick-video
description: "Genere une video de demo automatisee pour une brick. Voix IA (ElevenLabs) + navigation Playwright + merge ffmpeg. Utilise /brick-video pour creer une video de livraison."
---

# Brick Video — Video de demo automatisee

Genere une video de demo avec voix IA synchronisee pour livrer une brick a un client.

## Quand utiliser

- Brick prete a livrer (status implementation ou test)
- Le client a besoin d'une video de demo du resultat
- Apres `/brick-review` pour accompagner la livraison

## Pre-requis

- Le dev server de l'app cible doit tourner (ne PAS le lancer soi-meme)
- Le pipeline video est installe a `~/demo-video/` sur le VPS — c'est une
  INSTALLATION PARTAGEE EN LECTURE SEULE (binaires + node_modules). On n'ecrit
  JAMAIS dedans : chaque app travaille dans SA copie, voir « Repertoire de
  travail » ci-dessous.

## Repertoire de travail : un par app, OBLIGATOIRE

Deux incidents reels (physiotraq puis bigpocket, juillet 2026) : deux agents
tournant en meme temps ont ecrase `~/demo-video/out/voice.mp3` et
`alignment.json` l'un de l'autre — mauvaise voix sur la mauvaise video, heures
perdues. `out/` est un singleton : DEUX PIPELINES NE DOIVENT JAMAIS PARTAGER LE
MEME `out/`.

Avant toute chose, creer la copie de travail DANS le depot de l'app (sous
`tmp/`, deja gitignore par le template Rails) :

```bash
APP_DIR=$(pwd)                      # la racine du depot de l'app
WORK="$APP_DIR/tmp/brick-video"
mkdir -p "$WORK/narratives" "$WORK/out"
cp -a ~/demo-video/src ~/demo-video/remotion ~/demo-video/package.json \
      ~/demo-video/run.sh ~/demo-video/before.js ~/demo-video/shot.js \
      ~/demo-video/measure.js "$WORK/" 2>/dev/null
ln -sfn ~/demo-video/node_modules "$WORK/node_modules"
```

Ensuite TOUT se fait dans `$WORK` : narrative, audio, alignment, rendu. Aucun
chemin `~/demo-video/...` ne doit apparaitre dans tes commandes apres ce bloc
(le `run.sh` copie travaille relativement a son propre dossier). Ces fichiers
sont des artefacts intermediaires : ils ne se COMMITENT jamais (tmp/ est
gitignore, ne pas les sortir de la).
- La cle ElevenLabs est configuree dans les **tenant credentials** du serveur nexrai distant (cle: `elevenlabs_api_key`, categorie: `api_keys`)

## IMPORTANT — Gestion de la cle ElevenLabs

**NE JAMAIS chercher ou lire la cle ElevenLabs localement.** Elle n'existe pas sur ce VPS. Elle est stockee sur le serveur nexrai distant dans `tenant_credentials`, chiffree.

Pour generer l'audio, utiliser **UNIQUEMENT** le MCP tool `elevenlabs_tts_tool(text: "...", voice_id: "...")`. Ce tool :
1. Lit la cle cote serveur (tenant_credentials)
2. Appelle l'API ElevenLabs cote serveur
3. Retourne une URL de telechargement de l'audio + le JSON d'alignment
4. La cle ne transite JAMAIS par l'agent

Si le tool retourne une erreur "cle non configuree", demander a l'utilisateur de l'ajouter via `/super_admin/tenants/:id/credentials`.

## Process

### Phase 1 — Identification de la cible

1. Utiliser le MCP tool `app_tool(action: "list")` pour lister les apps
2. Utiliser `brick_tool(action: "list", app_id: X)` pour lister les bricks
3. Confirmer avec l'utilisateur quelle brick on filme
4. Identifier :
   - L'URL du dev server de l'app (demander a l'utilisateur)
   - Les credentials de demo (user externe, password)
   - Les fonctionnalites a montrer dans la video

### Phase 2 — Exploration et scenarisation

1. Utiliser **la CLI `playwright-cli`** (voir le skill `playwright`) pour explorer l'app cible :
   - Naviguer chaque ecran du parcours
   - Identifier les selecteurs CSS de chaque action
   - Valider que le parcours fonctionne de bout en bout
   - Noter les temps de chargement

2. Ecrire la narration :
   - Francais, ton professionnel mais accessible
   - Phrases courtes (3-5 secondes chacune)
   - ~15 etapes maximum pour une video de ~70 secondes
   - Chaque phrase correspond a UNE action dans l'app

3. Generer le fichier `$WORK/narratives/{slug}.json`

### Voix

**TOUJOURS** utiliser la voix ElevenLabs Rudy `wufFsVwuYBePWKO6dMMN` avec le
modele `eleven_v3`, sauf demande contraire explicite de l'utilisateur.
C'est la meme voix et le meme modele que /brick-promo-video : toutes les
videos livrees au client ont ainsi un rendu voix identique (eleven_v3 est
aussi bien plus expressif que multilingual_v2).

### Format du fichier narrative

```json
{
  "target": "http://app-url:port",
  "voice_id": "wufFsVwuYBePWKO6dMMN",
  "model_id": "eleven_v3",
  "language": "fr",
  "viewport": { "width": 1536, "height": 900 },
  "steps": [
    {
      "say": "Texte prononce pendant cette etape.",
      "do": { "action": "click", "selector": "..." }
    }
  ]
}
```

### Actions disponibles pour `do`

| Action | Params | Description |
|--------|--------|-------------|
| `goto` | `url` | Navigation initiale (**step 0 uniquement**) |
| `click` | `selector`, `waitForUrl` (opt) | Clic avec deplacement de curseur visible |
| `fill` | `selector`, `value` | Remplir un champ (le curseur se deplace vers le champ) |
| `select` | `selector`, `value` | Choisir une option dans un `<select>` |
| `hover` | `selector` | Survoler un element |
| `press` | `key` | Appuyer sur une touche clavier |
| `dragTo` | `from`, `to`, `moveUrl`, `moveStatus` | Drag visuel avec ghost card + appel API |
| `wait` | `ms` | Pause (pour decrire l'ecran sans action) |

---

## REGLES CRITIQUES DE SCENARISATION

Ces regles sont le resultat de nombreuses iterations. Les ignorer produit une video cassee.

### 1. PAS de `goto` apres le step 0

Le premier step DOIT etre un `goto` vers la page initiale (ex: page de login).
**Tous les steps suivants DOIVENT naviguer par clic** sur des liens ou boutons visibles.

❌ MAUVAIS :
```json
{ "say": "Passons au kanban.", "do": { "action": "goto", "url": "/kanban" } }
```

✅ BON :
```json
{ "say": "Passons au kanban.", "do": { "action": "click", "selector": "a[href='/projects/1/kanban']", "waitForUrl": "**/kanban" } }
```

Pourquoi : un `goto` change l'URL sans interaction visible. Le client ne voit pas de clic, c'est pas naturel.

### 2. Toujours utiliser `waitForUrl` pour les clics de navigation

Quand un clic provoque un changement de page, ajouter `waitForUrl` avec un glob pattern.
Le pipeline attend la nouvelle URL avant de continuer, et re-initialise le curseur sur la nouvelle page.

```json
{ "do": { "action": "click", "selector": "a[href='/dashboard']", "waitForUrl": "**/dashboard" } }
```

Sans `waitForUrl`, le curseur disparait apres la navigation (bug Turbo Rails 8).

### 3. Selecteurs `<input type="submit">` vs `<button>`

Rails genere souvent des `<input type="submit">` au lieu de `<button>`.
Verifier dans le HTML source ou via `playwright-cli snapshot` (skill `playwright`).

❌ NE MARCHE PAS si c'est un `<input>` :
```json
{ "selector": "button[type=submit]" }
```

✅ CORRECT :
```json
{ "selector": "input[type=submit][value='Sign in']" }
```

Toujours verifier le type reel de l'element avant d'ecrire le selecteur.

### 4. Sidebar et menus depliants

Si un lien est dans un menu replié (ex: sidebar "Projets" avec un dropdown),
il faut d'abord cliquer pour ouvrir le menu, PUIS cliquer le lien.

Exemple pour un sidebar avec `data-controller="sidebar-collapse"` :
```json
[
  { "say": "Ouvrons notre projet.", "do": { "action": "click", "selector": "button[data-action*='sidebar-collapse#toggle']" } },
  { "say": "Passons au kanban.", "do": { "action": "click", "selector": "a[href='/projects/1/kanban']", "waitForUrl": "**/kanban" } }
]
```

### 5. Drag and drop — ghost card + API

Le drag-and-drop HTML5 natif ne fonctionne pas en headless Playwright.
Le pipeline utilise une technique de **ghost card** : il clone visuellement la carte,
la deplace avec le curseur, puis appelle l'API backend pour effectuer le deplacement reel.

```json
{
  "do": {
    "action": "dragTo",
    "from": "[data-kanban-target='card'][data-id='1']",
    "to": "[data-kanban-target='column'][data-status='in_progress']",
    "moveUrl": "/projects/1/issues/1/move",
    "moveStatus": "in_progress"
  }
}
```

- `from` : selecteur CSS de la carte a deplacer
- `to` : selecteur CSS de la colonne cible
- `moveUrl` : endpoint PATCH de l'API backend pour deplacer la carte
- `moveStatus` : nouveau statut a envoyer dans le body JSON `{ status: "..." }`

Le pipeline :
1. Deplace le curseur vers la carte (25 steps lisses)
2. Clone la carte en overlay avec ombre portee + rotation 3°
3. Rend la carte originale semi-transparente (opacity 0.3)
4. Deplace le curseur + ghost vers la colonne cible (120 steps lents)
5. Supprime le ghost
6. Appelle PATCH `moveUrl` avec `{ status: moveStatus }`
7. Recharge la page pour montrer le resultat final

**IMPORTANT** : `moveUrl` et `moveStatus` sont OBLIGATOIRES pour le drag.
Sans eux, le pipeline tente un `locator.dragTo()` natif qui echoue en headless.

### 6. Selecteurs avec `.first()` implicite

Le pipeline utilise `.first()` sur tous les selecteurs. S'il y a plusieurs matches,
le premier element visible est utilise. Preferer des selecteurs specifiques :

```json
"selector": "a.bg-indigo-600[href$='/issues/new']"
```
plutot que :
```json
"selector": "a[href$='/issues/new']"
```

### 7. Multi-tenant et subdomains

Pour les apps multi-tenant avec resolution par subdomain, utiliser `lvh.me` en dev :
```json
"target": "http://demo.lvh.me:3002"
```
`lvh.me` resolve vers 127.0.0.1 et permet le routing par subdomain en local.

### 8. Formulaires Rails — selecteurs types

```
Email :     input[type=email]
Password :  input[type=password]
Text :      input[name='model[field]']
Textarea :  textarea[name='model[field]']
Select :    select[name='model[field]']
Submit :    input[type=submit][value='Texte du bouton']
```

### 9. Narration — concatenation des phrases

Toutes les phrases `say` sont concatenees en un seul texte, envoye a ElevenLabs en un appel.
L'alignment retourne les timestamps par caractere. Le pipeline calcule l'offset de chaque phrase
dans le texte concatene pour determiner quand declencher chaque action.

Consequence : les phrases doivent etre ecrites comme un texte fluide qui se lit naturellement a voix haute.

Si la narration totale depasse 3000 caracteres (plafond ElevenLabs par requete),
le TTS doit etre decoupe puis recolle — voir Etape 2, « Textes longs ». En
dessous, UN SEUL appel : prosodie continue et alignement natif.

### 10. Scroll pour montrer le contenu sous le fold

Les pages ont souvent du contenu sous le fold (invisible sans scroll).
Si un formulaire, un tableau ou une section importante est en bas de page,
ajouter un step `hover` sur un element en bas ou un step de scroll :

```json
{ "say": "Voyons le reste de la page.", "do": { "action": "hover", "selector": "footer" } }
```

Ou utiliser un selecteur en bas de page pour que le curseur s'y deplace (le pipeline scrolle automatiquement pour rendre l'element visible).

**Toujours verifier via `playwright-cli snapshot` (skill `playwright`)** si la page a du contenu en dessous du viewport. Si oui, prevoir un ou deux steps pour scroller et montrer ce contenu.

### 11. Validation des formulaires AVANT le script

**REGLE CRITIQUE** : avant d'ecrire le script de creation d'un objet (issue, projet, etc.),
**TOUJOURS verifier via `playwright-cli` quels champs sont requis** dans le formulaire.

Methode :
1. Naviguer sur la page du formulaire via MCP
2. Faire un snapshot et lire TOUS les champs
3. Identifier les champs marques `required` ou `*`
4. S'assurer que le script remplit TOUS les champs obligatoires

❌ MAUVAIS — on remplit 2 champs sur 4 obligatoires et le submit echoue :
```json
[
  { "do": { "action": "fill", "selector": "input[name='issue[url]']", "value": "https://..." } },
  { "do": { "action": "click", "selector": "input[type=submit]" } }
]
```

✅ BON — on a verifie le formulaire et on remplit tout :
```json
[
  { "do": { "action": "fill", "selector": "input[name='issue[url]']", "value": "https://..." } },
  { "do": { "action": "fill", "selector": "textarea[name='issue[description]']", "value": "Description detaillee..." } },
  { "do": { "action": "select", "selector": "select[name='issue[type]']", "value": "bug" } },
  { "do": { "action": "select", "selector": "select[name='issue[priority]']", "value": "high" } },
  { "do": { "action": "click", "selector": "input[type=submit]" } }
]
```

**Apres le submit, verifier via MCP que l'objet a ete cree** (naviguer vers la page de detail ou la liste). Si le submit a echoue silencieusement (erreurs de validation), le reste de la video sera incohérent.

### 12. Timing et actions lentes

Si une action est lente (chargement de page, animation), la phrase qui l'introduit
doit etre suffisamment longue pour couvrir le temps de chargement.

Si une page met 2s a charger, la phrase doit durer au moins 3s.
Ajouter des mots si necessaire : "Et nous voici maintenant sur le tableau de bord, qui rassemble..." plutot que "Voici le dashboard."

---

## Phase 3 — Production

### Etape 1 : Reset des donnees de demo

Si necessaire, reset les donnees avant de filmer (pour avoir un etat propre).
Utiliser `bin/rails runner` pour creer/reset les données de demo.

### Etape 2 : Generer l'audio via MCP

1. Concatener tous les `say` des steps en un texte unique, separes par un espace
2. Appeler le MCP tool :
   ```
   elevenlabs_tts_tool(text: "Bonjour et bienvenue... Connectez-vous...", voice_id: "wufFsVwuYBePWKO6dMMN", model_id: "eleven_v3")
   ```
3. Le tool retourne :
   - Une **audio URL** (chemin ActiveStorage)
   - Le **alignment JSON** (timestamps par caractere)
4. Telecharger l'audio :
   ```bash
   curl -o "$WORK/out/voice.mp3" "$PLATFORM_API_URL{audio_url}"
   ```
5. Sauver l'alignment dans un fichier :
   ```bash
   cat > "$WORK/out/alignment.json" << 'EOF'
   { "characters": [...], "character_start_times_seconds": [...], "character_end_times_seconds": [...] }
   EOF
   ```

#### ⚠️ Textes longs : quand decouper le TTS (et quand ne PAS le faire)

Historique important : en juillet 2026, des appels TTS de plus de ~700
caracteres semblaient « bloques 30 minutes » puis echouaient. Deux agents en ont
conclu que eleven_v3 etait lent ou casse. **C'etait faux** : deux proxys de
l'infra (kamal-proxy puis Thruster) coupaient toute reponse depassant 30 s, et
le client MCP attendait ensuite 1800 s dans le vide. Corrige le 2026-07-22 et
verifie en conditions reelles : 1400 caracteres passent en ~40 s, en un seul
appel.

Performances reelles de eleven_v3 via le tool : ~30-45 s pour 1400-2000
caracteres. C'est normal (l'endpoint renvoie l'audio ET l'alignement par
caractere). Un appel qui depasse 5 minutes sans reponse n'est PAS une lenteur
du modele : c'est une regression d'infra, signale-le au lieu de conclure que le
modele est mort ou de descendre a des morceaux de 650 caracteres.

Regle : UN SEUL appel tant que le texte tient sous **3000 caracteres** (c'est
le plafond ElevenLabs par requete pour v3). Un seul appel = prosodie continue,
alignement natif, zero couture. Ne decouper qu'au-dela, et alors :

1. **Couper sur des frontieres de phrase** (fin de `.`/`!`/`?`), pas au milieu
   d'un mot. Viser des morceaux de ~1500-1800 caracteres (pas 400-500 : trop de
   morceaux = plus de coutures audibles et plus d'alignements a fusionner).
2. **Un appel `elevenlabs_tts_tool` par morceau**, meme voice_id / model_id.
3. **Recoller les mp3** dans l'ordre (ffmpeg concat).
4. **Fusionner les alignments** : decaler les `character_start/end_times_seconds`
   de chaque morceau de la duree cumulee des morceaux precedents, puis
   concatener les tableaux `characters` + timestamps. C'est cet alignment fusionne
   qui va dans `out/alignment.json` — le pipeline en depend pour caler les
   actions.
5. Pour limiter la cassure de prosodie aux coutures (l'intonation « repart a
   froid » a chaque morceau), garder les phrases entieres dans un meme morceau
   quand c'est possible.

Un texte de narration de ~15 steps courts passe en general en un seul appel :
ne decouper que si c'est reellement long.

### Etape 2bis : Musique de fond (optionnel)

Pour une musique de fond calee sur la duree de la video, utiliser le MCP tool
`elevenlabs_music_tool(prompt: "...", duration_seconds: N)` :
- `duration_seconds` = duree exacte de la video (10 a 300 s)
- retourne une URL audio a telecharger en curl + `bpm`/`beat_offsets`
  (pour caler les cuts sur les temps forts ; peuvent etre null)
- CACHE : un appel identique renvoie la meme musique sans refacturer —
  reutiliser le meme prompt pour toutes les videos d'une meme app garde
  une identite sonore coherente
- quota 10 generations/jour ; la cle ElevenLabs reste cote serveur

### Etape 2ter : Effets sonores (optionnel)

Pour des bruitages ponctuels (whoosh de transition, clic, notification,
apparition d'element), utiliser `elevenlabs_sfx_tool(prompt: "...")` :
- `duration_seconds` optionnel (0.5 a 22 s) ; omis = ElevenLabs choisit
- `prompt_influence` 0.0-1.0 (haut = plus fidele au prompt)
- meme CACHE que la musique (un effet identique n'est pas refacture) ;
  reutiliser les memes prompts pour une banque d'effets coherente
- retourne une URL audio a poser sur la timeline aux temps voulus

### Etape 3 : Lancer le pipeline

```bash
bash "$WORK/run.sh" "$WORK/narratives/{slug}.json"
```

Le pipeline detecte `out/voice.mp3` + `out/alignment.json` et skip le TTS.
Il lance Playwright, enregistre la video, et merge avec ffmpeg.

### Etape 4 : Verifier

- `$WORK/out/output.mp4` existe
- Pas de fichiers `out/error-step-*.png` (sinon les selecteurs sont faux)
- Extraire des frames pour valider :
  ```bash
  ffmpeg -ss 10 -i "$WORK/out/output.mp4" -frames:v 1 /tmp/check.png
  ```
- Si des steps ont echoue, corriger les selecteurs et relancer

### Phase 4 — Publication

Chaque brick a une **liste de videos** : une video par changement demande par
le client. Le `title` decrit le changement filme (ex: "Filtre de recherche
sur le kanban"). Il est OBLIGATOIRE et sert de cle de remplacement :
re-uploader avec le MEME title remplace l'ancienne version (l'asset Mux de
l'ancienne est supprime automatiquement cote plateforme — ne PAS s'en
occuper, la facture Mux ne s'accumule pas).

1. Uploader la video vers nexrai :
```bash
curl -X POST \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -F "video=@$WORK/out/output.mp4" \
  -F "title=Description courte du changement filme" \
  $PLATFORM_API_URL/api/v1/bricks/{brick_id}/delivery_video
```

2. La reponse contient `video_url` : la **page publique de visionnage**
   (player Mux en streaming + stats de visionnage remontees dans Mux Data).
   **C'est CE lien qu'on transmet au client** — jamais l'URL du fichier brut.
   La page marche immediatement (lecture directe le temps que Mux encode,
   puis bascule sur le player Mux automatiquement).

3. Lister les videos existantes de la brick (pour verifier ou retrouver un lien) :
```bash
curl -H "Authorization: Bearer $MCP_TOKEN" \
  $PLATFORM_API_URL/api/v1/bricks/{brick_id}/videos
```

4. Optionnel : mettre a jour le statut de la brick :
```
brick_tool(action: "update", id: BRICK_ID, status: "test")
```

Les stats de visionnage (vues, taux de completion, ou le client a decroche)
sont dans le dashboard Mux (mux.com) — utile pour savoir si le client a
regarde la demo avant un call.

## Validation gate

- [ ] Video generee sans erreurs de steps
- [ ] Voix synchronisee avec les actions a l'ecran
- [ ] Curseur visible tout au long de la video (y compris apres chaque navigation)
- [ ] Cercle rouge au clic visible
- [ ] Ghost card visible pendant le drag-and-drop (si applicable)
- [ ] Pas d'ecran blanc au debut de la video
- [ ] Video uploadee avec un `title` decrivant le changement
- [ ] Page publique de visionnage ouverte et verifiee (lien a envoyer au client)
- [ ] Voix = wufFsVwuYBePWKO6dMMN (Rudy, modele eleven_v3 — comme /brick-promo-video)

## Troubleshooting

| Symptome | Cause | Fix |
|----------|-------|-----|
| Curseur disparait apres un clic | Manque `waitForUrl` sur un clic de navigation | Ajouter `waitForUrl` avec le bon pattern |
| Ecran blanc au debut | Rare, le pipeline pre-charge la page | Verifier que step 0 est bien un `goto` |
| Step echoue (timeout) | Selecteur incorrect ou element invisible | Verifier via `playwright-cli snapshot`, ajuster le selecteur |
| Drag ne deplace pas la carte | Manque `moveUrl`/`moveStatus` | Ajouter l'endpoint API + le statut cible |
| Ghost card sans mouvement visible | Steps de mouvement trop peu | Deja configure a 120 steps, ne pas toucher |
| Audio desynchronise | Phrase trop courte pour une action lente | Allonger la phrase ou ajouter un step `wait` avant |
| Submit ne marche pas | `button[type=submit]` mais c'est un `<input>` | Utiliser `input[type=submit][value='...']` |
| Navigation pas declenchee | Lien dans un menu replié | Ajouter un step pour ouvrir le menu d'abord |
| Contenu important pas visible | Page plus haute que le viewport | Ajouter un step `hover` sur un element en bas pour scroller |
| Submit echoue silencieusement | Champs requis non remplis | Verifier TOUS les champs obligatoires via MCP avant d'ecrire le script |
| Objet pas cree apres submit | Validation Rails a echoue | Verifier les `required`, `minlength`, format attendu dans le snapshot MCP |
