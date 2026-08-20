---
name: kamal
description: "Accéder à la PROD d'un projet avec kamal depuis un VPS agent : console, runner, logs, exec — sans registry ni docker login. Utilise /kamal dès qu'il faut lire ou toucher la production (données, comptes, diagnostic), ou qu'une commande kamal échoue. Référencé par brick-code-fix, brick-code-review et brick-daily-triage."
---

# Kamal depuis un VPS agent : accéder à la prod sans se cogner au registry

kamal marche depuis les VPS agents. Quand un agent conclut « kamal n'a pas
accès au registry depuis cette machine (docker login) », il a presque toujours
oublié `--reuse`, ou il n'est pas dans le dossier du projet. Ne JAMAIS en
déduire qu'on n'a pas accès à la prod, ni se rabattre sur les seeds pour
deviner les données réelles.

## La règle d'or : `--reuse`

`kamal app exec` SANS `--reuse` démarre un NOUVEAU container sur le serveur :
docker pull, donc docker login, donc l'erreur registry (le mot de passe n'est
pas dans l'environnement des VPS, et c'est voulu). Avec `--reuse`, kamal
exécute la commande DANS le container qui tourne déjà : aucun registry, aucun
login, rien ne redémarre.

```bash
# Toujours depuis le dossier du projet (celui qui a config/deploy.yml)
cd ~/projects/<slug>

# Une commande ponctuelle
kamal app exec --reuse -q 'bin/rails about' 2>&1 | tail -20

# Lire des données prod (one-liner runner)
kamal app exec --reuse -q 'bin/rails runner "puts User.where(role: :admin).pluck(:email)"' 2>&1 | tail -5

# Console interactive (seulement dans un terminal humain, pas en agent -p)
kamal app exec --interactive --reuse 'bin/rails console'

# Logs de l'app
kamal app logs --lines 200 2>&1 | grep -i error | tail -20
```

Le `2>&1 | tail` est important : kamal préfixe chaque run du boot Rails
complet (Registered tools, ActionCable...), il faut filtrer.

## Ce qui est interdit reste interdit

- `kamal deploy` : JAMAIS à la main. Le deploy passe par GitHub Actions
  (push sur main → prod, push sur staging → staging).
- `kamal app boot|stop|remove` : on ne redémarre pas la prod d'un client
  sans instruction explicite.

## Pièges connus

1. **Arguments tronqués.** `kamal app exec --reuse 'ruby long_script'` tronque
   les arguments longs. Au-delà de quelques centaines de caractères, ne passe
   JAMAIS un script en argument : transfère-le en base64 par morceaux, puis
   exécute le fichier.
   ```bash
   base64 -w0 script.rb | fold -w 2000 > chunks.txt
   kamal app exec --reuse -q 'rm -f /tmp/s.b64'
   while IFS= read -r c || [ -n "$c" ]; do
     kamal app exec --reuse -q "sh -c 'printf %s $c >> /tmp/s.b64'"
   done < chunks.txt
   # TOUJOURS vérifier le checksum avant d'exécuter
   kamal app exec --reuse -q 'sh -c "base64 -d /tmp/s.b64 | md5sum"'   # == md5sum script.rb
   kamal app exec --reuse -q 'sh -c "base64 -d /tmp/s.b64 > /tmp/s.rb && bin/rails runner /tmp/s.rb"'
   ```
2. **Mauvais dossier.** `ERROR: Configuration file not found in .../config/deploy.yml`
   = tu n'es pas dans le dossier du projet. `cd ~/projects/<slug>` d'abord.
   Attention aux commandes composées : chaque `kamal ...` doit partir du bon cwd.
3. **`--interactive` en agent.** Une session `-p`/non interactive ne peut pas
   tenir une console : utilise `bin/rails runner` à la place.
4. **Écritures prod.** Lire est libre. Écrire (update/delete/migrate) demande
   soit une instruction explicite de l'humain, soit un fait confirmé par lui.
   Et `update_columns`/`update_all` plutôt qu'un `update!` qui touche
   `updated_at` quand les fenêtres temporelles comptent (dashboard, stats).
5. **Timeout.** Un runner long : enveloppe avec `timeout 300` côté VPS, et
   découpe le travail (find_each + puts de progression).

## Diagnostic express quand ça échoue quand même

```bash
ls config/deploy.yml            # bon dossier ?
grep -n "^service\|host:" config/deploy.yml | head -3   # bonne cible ?
kamal app details 2>&1 | tail -5                        # accès SSH au serveur ?
```
Si `kamal app details` échoue sur du SSH : la clé du VPS n'a pas accès au
serveur prod de ce projet → remonter à l'humain, ne pas contourner.

## Ensuite

→ diagnostic de bug prod : `/brick-code-fix`. Surveillance post-deploy :
`/brick-code-review` (section smoke test). Les seeds ne décrivent JAMAIS la
prod : pour savoir ce qui existe en prod, on interroge la prod.
