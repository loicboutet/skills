---
name: brick-code-feedback
description: "Traite les retours du client sur la livraison : rassemble tous les canaux (tracker via widget, emails, WhatsApp, Drive partage), verifie pour chaque retour s'il est dans les specs, code (ou delegue a /brick-code-fix pour les bugs), met a jour les specs et le tracker. Utilise /brick-code-feedback apres une livraison."
---

# Brick Code Feedback

Meme boucle que `brick-mockup-feedback`, mais sur le vrai code apres livraison. Le client teste
en prod (ou en garantie), laisse ses retours (widget → tracker, plus emails/WhatsApp/Drive). On
rassemble, on trie par scope, on corrige, on tient specs et tracker a jour, on filme les
changements du jour.

## Quand utiliser

- Apres une livraison de brick (statut `test` / garantie, ou en prod).
- A relancer a chaque vague de retours client.

## Pre-requis

- Widget de feedback present sur l'app livree.
- `doc/memory/acceptance_criteria.md` et les tests existants.
- MCP : `get_destination_tracker_issues`, `tracker_issue_tool`, `gmail_*`, WhatsApp, `google_drive_*`.

## Process

1. **Rassembler TOUS les retours** (pas seulement le tracker) :
   - Tracker : `get_destination_tracker_issues`.
   - Emails : `gmail_list_emails` / `gmail_read_email` sur les contacts du projet.
   - WhatsApp : messages recents du client.
   - Drive partage : docs de retours deposes par le client (`google_drive_search`).
   Consolider et dedupliquer.

2. **Pour chaque retour, verifier le scope** contre `acceptance_criteria.md` :
   - **Dans les specs** → corriger. Si c'est un bug, appliquer la methode `brick-code-fix`
     (reproduire par un test, corriger, verifier). Si c'est un ajustement in-scope, coder + test.
   - **Hors specs** → ne pas implementer en silence : signaler, citer la spec, demander
     confirmation. Si accepte, documenter le changement de scope et mettre a jour
     `acceptance_criteria.md` (nouveau critere ou modification).
   - **Contredit une spec** → toujours signaler.

3. **Discipline tracker** (OBLIGATOIRE) : `in_progress` au demarrage, puis `fixed` ou
   `waiting_client`. Creer une issue tracker pour les retours venus des autres canaux, pour
   tout tracer. Chaque correction reference le critere d'acceptance concerne.

4. **Commiter apres chaque tache**, ne pas push sans demande explicite. Tests verts avant de
   marquer `fixed`.

## Validation gate

- [ ] Retours rassembles depuis tracker + emails + WhatsApp + Drive partage
- [ ] Chaque retour classe (dans specs / hors specs / contradiction) et traite
- [ ] Bugs traites par la methode `brick-code-fix` (test qui reproduit)
- [ ] Changements de scope documentes et valides
- [ ] Tests verts, tracker a jour, commits propres

## Ensuite

→ `brick-code-video` pour filmer un changement urgent tout de suite. En fin de journee,
`brick-daily-video` assemble TOUS les changements du jour (mockup + code) en un bilan chapitre et
l'envoie au client avec un message recap. Reboucler a la vague suivante.
