---
name: brick-daily-triage
description: "Point d'entree quotidien : va voir emails + WhatsApp + Slack + tracker (+ Drive), repere ce qu'il y a a faire, verifie le scope de chaque demande (comme les skills feedback), traite l'actionnable, prepare une reponse sur le canal d'origine, et escalade les points a trancher. Enchaine par defaut sur brick-daily-video, SAUF s'il reste des decisions pour l'humain. Utilise /brick-daily-triage en debut de journee ou pour faire le tour de ce qui est arrive."
---

# Brick Daily Triage — le tour de ce qu'il y a a faire, puis on execute

Un seul point d'entree le matin (ou quand tu veux faire le tour) : ramasser tout
ce qui est arrive sur tous les canaux, trier par scope de brique, traiter
l'actionnable, preparer la reponse au client sur le canal d'ou vient la demande,
et fermer la journee avec le bilan video. C'est le pendant matin de
`brick-daily-video` (le bilan du soir).

## Quand utiliser

- Debut de journee, ou pour faire le point sur ce qui est arrive du client.
- Apres une periode sans regarder les canaux (retour de week-end, etc.).

## Le principe

Ramasser → trier par scope → executer l'actionnable → repondre sur le bon canal →
escalader les points a trancher → bilan. **Regle d'or : on n'agit JAMAIS en
silence sur ce qui sort du scope ou demande une decision. Ces items remontent a
l'humain, et on n'enchaine PAS sur la video tant qu'ils ne sont pas tranches.**

## 1. Ramasser (tous les canaux), en gardant le canal d'origine

Meme collecte que `brick-mockup-feedback` / `brick-code-feedback`, mais on
**tague chaque item avec son canal d'origine** (sert a la reponse en etape 4) :

- **Tracker** : `get_destination_tracker_issues` (issues nouvelles / ouvertes /
  assignees, dont celles creees par le widget de feedback).
- **Emails** : `gmail_list_emails` / `gmail_read_email` sur les contacts du projet.
- **WhatsApp** : messages recents du client.
- **Slack** : `slack_tool` (action accounts, puis history sur les canaux du
  projet avec `oldest` = dernier passage ; search pour retrouver un fil).
  Lecture seule pendant le triage : jamais d'action send ici.
- **Drive partage** : docs de retours deposes (`google_drive_search`).
- **Bricks terminées non envoyées** : `brick_tool` — toute brique en statut
  `finished` depuis plus de 2 jours (le planning l'affiche en rouge « prête
  depuis N j ») remonte comme DECISION pour l'humain : « prête depuis N jours,
  toujours pas envoyée au client — j'envoie ? ». C'est le raté sharifunding
  du 21-25/08 : 4 jours prête sans que personne n'envoie.

Consolider et **dedupliquer** (meme demande sur deux canaux = une entree, mais on
retient TOUS ses canaux d'origine). Pour tout retour venu hors tracker
(email/WhatsApp/Drive), **creer l'issue tracker correspondante** pour tout tracer.

## 2. Trier chaque item par scope (regle des skills feedback)

Contre `doc/memory/acceptance_criteria.md` (+ les specs), classer chaque item :

- **Actionnable in-scope** → file d'execution (etape 3).
- **Point a trancher** → hors scope, contredit une spec, ambigu, ou decision
  produit / priorite. **On n'agit pas.** (regle Gilfoyle : hors-spec → signaler +
  citer la spec + demander confirmation ; contradiction → toujours signaler.)

Classer aussi le **type** de l'actionnable, ca decide du skill a appliquer :
bug (`brick-code-fix`), retour mockup (`brick-mockup-feedback`), retour code
(`brick-code-feedback`), simple question (souvent un point a trancher, ou une
reponse a preparer sans code).

## 3. Le gate de decision (le coeur de ce skill)

- **S'il y a des points a trancher** → on les prepare (voir etape 4 : la reponse
  sur le canal d'origine porte la question) et **on s'arrete la sur ces items**.
  On peut traiter en parallele l'actionnable clairement independant, mais **on
  n'enchaine PAS sur `brick-daily-video`** tant qu'une decision est en attente :
  le bilan serait premature et incomplet.
- **Si tout est clair** → executer l'actionnable, puis enchainer sur le bilan.

## 4. Executer + preparer la reponse sur le canal d'origine

**Executer** — un sous-agent par item actionnable (regle CLAUDE.md :
l'orchestrateur delegue, 1 sous-agent par appel), chacun applique le skill adapte
(`brick-code-feedback` / `brick-mockup-feedback` / `brick-code-fix`) avec la
discipline tracker (`in_progress` au demarrage → `fixed` / `waiting_client`),
tests verts avant `fixed`, commit sans push. L'orchestrateur garde le ramassage +
tri (avant) et la synthese + les reponses + le bilan (apres).

**Repondre sur le canal d'ou vient la demande** — pour chaque item (traite OU a
trancher), preparer la reponse au client selon son origine :

- **Origine email** → **brouillon Gmail** sur le fil (`gmail_create_draft_reply`,
  sinon `gmail_create_draft`). Ne PAS envoyer : brouillon a relire.
- **Origine WhatsApp** → **message WhatsApp pret a envoyer** (texte prepare sur le
  WhatsApp du projet). Ne PAS envoyer sans validation.
- **Origine Slack** → **message pret a envoyer** (texte prepare, canal + thread_ts
  notes). Ne PAS envoyer sans validation : `slack_tool` action send ecrit SOUS LE
  NOM de Loic.
- **Origine tracker / widget** → commentaire sur l'issue (`tracker_comment_tool`)
  + statut a jour ; le detail visuel part dans le bilan `brick-daily-video`.

Contenu de la reponse : ce qui a ete fait (ou la question a trancher), court,
ton 5000.dev. **Relu contre la checklist anti-IA du prompt** (pas de tiret
cadratin, pas de vocabulaire IA, pas de triades). **Tous les envois sortants sont
des brouillons confirmes avant envoi** (message sortant vers le client).

## 5. Enchainer (ou pas)

- **Des points a trancher en attente** → presenter la synthese (quoi, quel canal,
  quelle spec concernee, quelle decision attendue) + les brouillons de reponse
  correspondants. **S'arreter la.** Pas de video.
- **Rien a trancher, des changements produits** → `brick-daily-video` (bilan
  chapitre + message recap au client).
- **Rien a faire** → le dire (journee calme), pas de video.

## Todos : ce qui reste a l'humain part dans `todo_tool`

Chaque point a trancher, chaque reponse client a valider, chaque envoi (facture,
contrat, acces) que tu ne peux pas faire toi-meme devient une todo via l'outil
MCP `todo_tool` (action `create`) : titre « <Client> : <quoi> », notes = le
contexte en une phrase + la source (ID du mail, canal). La todo est rattachee
d'office a l'app/assistant de la session ; pour une autre app, `target:
"app:<id>"` (ids via `app_tool list`). `todo_tool list` AVANT de creer : pas de
doublon, on complete la note existante (`update`). Jamais de todo pour ce que
tu as fait ou peux faire toi-meme.

**Accès prod** : toute lecture ou vérification en production passe par kamal
depuis le dossier du projet — voir `/kamal` (règle d'or : `kamal app exec --reuse`,
jamais de deploy manuel, jamais les seeds pour deviner les données prod).

## Validation gate

- [ ] Tous les canaux ramasses (tracker + emails + WhatsApp + Slack + Drive), canal
      d'origine garde pour chaque item
- [ ] Retours hors-tracker traces en issues
- [ ] Chaque item classe : actionnable in-scope / point a trancher, + type
- [ ] Points a trancher jamais agis en silence, spec citee, remontes a l'humain
- [ ] Chaque point a trancher / suite humaine posee dans `todo_tool` (sans doublon)
- [ ] Actionnable traite via le bon skill, tracker a jour, tests verts, commit sans push
- [ ] Reponse preparee sur le canal d'origine (brouillon email / message WhatsApp ou Slack /
      commentaire tracker), relue anti-IA, confirmee avant envoi
- [ ] Enchainement `brick-daily-video` UNIQUEMENT si aucun point a trancher en attente

## Ensuite

- Points a trancher → l'humain decide, puis relancer `brick-daily-triage` (ou le
  skill cible) sur les items debloques.
- Sinon → `brick-daily-video` a produit le bilan du jour. Fin de journee.
