---
name: brick-mockup-feedback
description: "Traite les retours du client sur les mockups : rassemble tous les canaux (tracker via widget, emails, WhatsApp, Drive partage), verifie pour chaque retour s'il est dans les specs de la brique, corrige les mockups, met a jour les specs si besoin, met a jour le tracker. Utilise /brick-mockup-feedback apres avoir envoye les mockups au client."
---

# Brick Mockup Feedback

Le client a recu les mockups et laisse ses retours (surtout via le widget de feedback, qui cree
des issues dans le tracker). Ce skill boucle : rassembler les retours de TOUS les canaux, trier
par scope, corriger, tenir les specs et le tracker a jour. On repete jusqu'a validation, en
filmant les changements du jour avec `brick-mockup-video`.

## Quand utiliser

- Apres avoir presente les mockups au client (widget de feedback installe).
- A relancer a chaque vague de retours, jusqu'a validation des mockups.

## Pre-requis

- Widget de feedback present sur les mockups (sinon le voir avec `brick-mockup-build`).
- `doc/memory/acceptance_criteria.md` (la reference de scope de la brique).
- MCP : `get_destination_tracker_issues`, `tracker_issue_tool`, `gmail_*`, WhatsApp, `google_drive_*`.

## Process

1. **Rassembler TOUS les retours, pas seulement le tracker :**
   - Tracker : `get_destination_tracker_issues` (les issues creees par le widget).
   - Emails : `gmail_list_emails` / `gmail_read_email` sur les contacts du projet.
   - WhatsApp : les messages recents du client.
   - Drive partage : si un dossier est partage avec le client, `google_drive_search` / lire les
     docs de retours qu'il y aurait deposes.
   Consolider en une liste unique de retours (dedupliquer ce qui revient sur plusieurs canaux).

2. **Pour chaque retour, verifier le scope** contre `acceptance_criteria.md` :
   - **Dans les specs** → corriger le mockup normalement.
   - **Hors specs** → NE PAS implementer en silence. Signaler au chef de projet, citer la spec
     concernee, demander confirmation. Si accepte, documenter le changement de scope (date,
     demande, approuve par, impact sur les criteres) et mettre a jour `acceptance_criteria.md`.
   - **Contredit une spec** → toujours signaler, jamais trancher seul.

3. **Discipline tracker** (OBLIGATOIRE) : passer chaque issue traitee a `in_progress` quand on
   commence, puis `fixed` une fois corrige, ou `waiting_client` si on attend une reponse. Ne
   jamais laisser une issue traitee dans son statut d'origine. Pour les retours venus des autres
   canaux (email/WhatsApp/Drive), creer l'issue correspondante dans le tracker pour tout tracer.

4. **Ne jamais toucher au vrai code ici** : on est en phase mockup, on corrige des vues mockees.

## Validation gate

- [ ] Retours rassembles depuis tracker + emails + WhatsApp + Drive partage
- [ ] Chaque retour classe (dans specs / hors specs / contradiction) et traite en consequence
- [ ] Changements de scope documentes dans `acceptance_criteria.md` et valides
- [ ] Tracker a jour (aucune issue traitee laissee dans son statut d'origine)

## Ensuite

→ `brick-mockup-video` pour filmer les changements du jour et les renvoyer au client. Reboucler
sur `brick-mockup-feedback` a la vague suivante. Mockups valides → `brick-code-build`.
