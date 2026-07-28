---
name: ecriture-client
description: "Relecture MESUREE de tout texte destine a un client ou ses utilisateurs (emails, messages, guides, textes d'interface, posts) : rubrique notee sur 4 axes, corrections, re-notation. Utilise /ecriture-client avant d'envoyer un texte, ou reference depuis brick-code-guide, brick-daily-video, brick-*-feedback."
---

# Écriture client : relecture mesurée

La checklist anti-signes-IA existe (CLAUDE.md) mais une checklist qu'on ne note pas ne se
respecte pas. Ce skill transforme la relecture en score : on note AVANT d'envoyer, on
corrige tout axe sous 4, on re-note. Un texte qui "sent l'IA" décrédibilise le travail,
même s'il est juste.

## Quand utiliser

- Avant d'envoyer un email, message WhatsApp, message de livraison, post
- Avant de publier un guide (`brick-code-guide`), des textes d'interface, des empty states
- Référencé par les skills feedback et daily-video pour leurs messages sortants

## Étape 1 : détection mécanique (grep, zéro jugement)

Chercher LITTÉRALEMENT dans le texte. Une seule occurrence = correction obligatoire :

- Le tiret cadratin `—` (signe n°1). Remplacer : virgule, parenthèses, deux-points, ou deux phrases.
- FR : "crucial", "primordial", "il est important de noter", "il convient de souligner",
  "en effet" en ouverture, "mettre en lumière", "n'hésitez pas à", "dans un monde où",
  "que ce soit", "En somme", "En conclusion", "au cœur de", "riche de".
- EN : delve, showcase, underscore, pivotal, seamless, leverage, robust, "Here's the kicker".
- Antithèses "ce n'est pas X, c'est Y" / "non seulement… mais aussi".

## Étape 2 : notation (4 axes, 1-5, justifier AVANT de noter)

1. **signes_ia** — 1 : plusieurs détections mécaniques ou structures qui trahissent (triades
   systématiques, question rhétorique en accroche, puces partout avec premier mot en gras,
   emojis de section, paragraphes tous calibrés pareil). 3 : propre mécaniquement mais rythme
   régulier suspect. 5 : phrases de longueurs variées, paragraphes inégaux, rien à signaler.
2. **concret** — 1 : générique, aucun chiffre ni nom ("de nombreuses améliorations").
   3 : quelques faits mais des généralités subsistent. 5 : chiffres, noms, exemples du
   contexte réel du client ; chaque affirmation est vérifiable.
3. **ton** — 1 : plaquette commerciale (superlatifs, enthousiasme forcé, "ravi de").
   3 : correct mais des tournures corporate. 5 : direct, factuel, le ton 5000.dev ;
   vouvoiement espace client, tutoiement canaux perso.
4. **utilite** — 1 : le lecteur ne sait pas quoi faire après lecture. 3 : l'info y est mais
   noyée. 5 : l'essentiel en premier, une action claire, rien de superflu (test : lire à
   voix haute ; si on peut couper une phrase sans perte, la couper).

## Étape 3 : correction et re-notation

- Tout axe < 4 : corriger, puis RE-NOTER le texte corrigé (pas d'envoi sous 16/20).
- Sur un texte long (guide, page), noter section par section : les défauts se cachent dans
  les sections écrites en dernier.
- En cas de doute sur une phrase : la relire à voix haute. Si ça sonne comme une plaquette,
  réécrire.

## Sortie

Le texte final + une ligne de score : `écriture : 18/20 (signes_ia 5, concret 4, ton 5, utilite 4)`.
En dessous de 16 : ne pas envoyer, itérer.
