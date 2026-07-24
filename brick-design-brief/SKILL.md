---
name: brick-design-brief
description: "Premiere etape du design : envoyer au client le formulaire Drive de brief de marque (logo, couleurs, typo, references, ton) pour recuperer la source, avant de construire la charte. Utilise /brick-design-brief quand le client n'a pas de charte."
---

# Brick Design Brief

Envoie au client le formulaire de brief de marque et collecte sa source, AVANT de construire
la charte. C'est un pas asynchrone : on envoie, le client remplit plus tard, on revient avec
`brick-design-build`.

## Quand utiliser

- Le client n'a pas de charte graphique et il faut la creer.
- Tout debut de l'etape design, avant `brick-design-build`.

## Pre-requis

- Le formulaire Drive de brief de marque (gabarit 5000.dev). MCP `google_drive_*` pour le
  copier/partager, `gmail_*` ou WhatsApp pour transmettre le lien.
- L'email / le canal du client (sinon demander au chef de projet).

## Process

1. Copier le gabarit de brief dans un dossier Drive partage avec le client (`google_drive_copy_file`
   + `google_drive_share_file`), ou reutiliser le formulaire existant du projet.
2. Envoyer le lien au client avec un message court et concret : ce qu'on attend (logo vectoriel,
   couleurs, typo, 2-3 sites qu'il aime, ton de marque) et pourquoi (construire sa charte).
   Texte sans signe IA (pas de tiret cadratin, pas de superlatif).
3. **Rendre la main** : on attend le retour du client. Noter dans le kanban que le design est
   en attente de brief.
4. A la reception, verifier que la source est exploitable (logo net, couleurs precises). Si un
   element cle manque, relancer avant de builder.

## Validation gate

- [ ] Formulaire de brief partage dans un dossier Drive accessible au client
- [ ] Message envoye sur le bon canal, sans jargon ni signe IA
- [ ] Source recue et exploitable (logo, couleurs, typo au minimum)

## Ensuite

→ `brick-design-build` : recuperer la source et construire la charte.
