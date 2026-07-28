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
   **Si la brique a des pages publiques**, ajouter au document la section "Votre visibilite"
   (voir ci-dessous) : c'est le meme aller-retour client, autant tout collecter d'un coup.
2. Envoyer le lien au client avec un message court et concret : ce qu'on attend (logo vectoriel,
   couleurs, typo, 2-3 sites qu'il aime, ton de marque) et pourquoi (construire sa charte).
   Texte sans signe IA (pas de tiret cadratin, pas de superlatif).
3. **Rendre la main** : on attend le retour du client. Noter dans le kanban que le design est
   en attente de brief.
4. A la reception, verifier que la source est exploitable (logo net, couleurs precises). Si un
   element cle manque, relancer avant de builder.

## Section "Votre visibilite" (si pages publiques) — la matiere SEO se collecte ICI

Sans ces donnees, le SEO tourne a vide (placeholders, chiffres invérifiables). Les demander
au meme moment que la marque, en langage client :

- **Vos coordonnees exactes** : raison sociale, adresse complete, telephone, horaires,
  EXACTEMENT comme sur votre fiche Google (au caractere pres).
- **Vos avis** : lien vers la fiche Google / plateforme d'avis + 2-3 avis dont vous etes
  fier qu'on peut citer (avec prenom et date).
- **Vos preuves** : diplomes, certifications, labels, affiliations, annees d'experience,
  chiffres cles (realisations/an, clients, note moyenne).
- **Vos prix** : prix d'appel et fourchettes par gamme/prestation (ce qu'on peut afficher).
- **Acces pratique** : parking, transports, acces PMR, delais typiques (devis, premier RDV).
- **Ce que vos clients tapent dans Google** pour vous trouver (3-5 exemples), et 2-3
  questions qu'ils posent toujours avant d'acheter.

## Validation gate

- [ ] Formulaire de brief partage dans un dossier Drive accessible au client
- [ ] Si pages publiques : section "Votre visibilite" incluse dans le formulaire
- [ ] Message envoye sur le bon canal, sans jargon ni signe IA
- [ ] Source recue et exploitable (logo, couleurs, typo au minimum ; NAP et preuves si
      pages publiques — sinon relancer, ne jamais inventer ces donnees)

## Ensuite

→ `brick-design-build` : recuperer la source et construire la charte.
