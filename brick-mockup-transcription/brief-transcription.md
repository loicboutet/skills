# Transcrire une source externe en vue de maquette

Tu transcris **un écran** livré par le client (export Lovable `.tsx` + sa CSS,
page HTML déposée sur le Drive, capture SingleFile) en **une vue de maquette
ERB**. Ce n'est pas une création : c'est un portage. La source fait autorité sur
tout ce qu'elle montre.

## La règle qui commande toutes les autres

**Tout ce que la source montre doit se retrouver dans la maquette. Rien
d'autre.** Une transcription se juge sur trois écarts mesurables : ce que la
source affichait et que tu as perdu, ce que la source faisait et que tu as
cessé de faire, ce que tu as ajouté sans qu'on te le demande.

## 1. Inventorier avant d'écrire

Avant la première ligne de ERB, relève dans la source :

1. **Les interactions**, une par une, avec leur verbe : bascule (onglet, switch,
   révélation, accordéon, modale), navigation (lien vers une autre page),
   soumission, saisie, sélection, filtre, tri, recherche, lecture de média.
2. **Les textes**, tous : titres, sous-titres, libellés de champ, placeholders,
   textes de bouton, messages d'aide, messages d'erreur, mentions légales,
   textes des états vides.
3. **Les valeurs** : chiffres, montants, pourcentages, dates, compteurs.
4. **Le vocabulaire visuel** : couleurs, tailles, rayons, ombres, polices.

Cet inventaire est ton cahier des charges. Tu ne rends pas la liste, tu la
tiens pendant que tu écris.

## 2. Les interactions se portent, elles ne se remplacent pas

C'est le défaut le plus fréquent et le plus coûteux : l'affordance est
recopiée, le comportement est perdu. Une page de connexion dont le choix de
rôle, les deux connexions externes et l'œil du mot de passe étaient quatre
bascules ressort avec huit liens de navigation. Elle a l'air complète et elle ne
fait plus rien.

- **Un contrôle de la source garde son verbe.** Une bascule reste une bascule.
  Ne la transforme jamais en lien, en paramètre d'URL (`?role=`, `?etat=`) ni en
  page séparée : le client valide un comportement, pas une capture.
- **Un contrôle dessiné mais mort ne compte pas.** Un bouton sans gestionnaire
  est un dessin de bouton. Chaque interaction de la source doit être réellement
  branchée dans la maquette : contrôleur Stimulus, `<details>`/`<summary>`,
  `<dialog>`, ou un `<script>` local à la page si c'est plus court. Un lien porte
  un `href` réel, un champ porte un `name`, un formulaire porte une `action`.
- **Un groupe d'options est un groupe de bascules.** Onglets, segments, filtres
  en pastilles, sélecteur de rôle : chaque option est un bouton branché qui
  change l'état de la page. Aucune ne devient un lien, aucune ne devient une
  page.
- **N'ajoute pas d'interaction que la source n'a pas.** Pas de barre de
  démonstration d'états, pas de menu inventé, pas de lien de navigation qui
  n'existait pas. Chaque contrôle en trop dégrade autant la note qu'un contrôle
  manquant.
- **Ne dédouble pas un contrôle.** Un même geste, un seul contrôle. Si tu écris
  deux fois la même action (le lien du logo et un bouton de retour qui vont au
  même endroit) alors que la source ne le fait qu'une fois, tu as inventé une
  interaction.

**Contrôle de sortie, obligatoire avant de rendre.** Reprends ton inventaire,
puis relis ton propre fichier et compte tes contrôles par verbe : combien de
bascules, combien de navigations, combien de soumissions, combien de saisies,
combien de sélections. Les deux comptes doivent coïncider verbe par verbe. Un
lien de trop pèse autant qu'une bascule perdue. Corrige avant de rendre.

## 3. Le style se porte par valeurs, pas par tokens

La source EST la référence visuelle. Elle a des valeurs littérales : reprends-les.

- **Porte la feuille de style de la source** dans un bloc `<style>` de la vue,
  portée par une classe racine de page (`.page-<ecran>`), en gardant ses noms de
  classes. C'est plus court, plus fidèle et plus relisible que de re-dériver
  chaque règle en classes utilitaires.
- **Recopie les valeurs exactes** : chaque code couleur, chaque taille en px,
  chaque rayon, chaque ombre, chaque graisse. `#b8975a` ne devient pas
  « la couleur or de la charte ». Une valeur estimée à l'œil est une valeur
  fausse.
- **Ne substitue pas la police.** Si la source appelle une police, la maquette
  appelle la même.
- **N'ajoute pas de couleurs** que la source n'utilise pas. Si un état manque
  (une erreur, un état désactivé), reprends la couleur la plus proche déjà
  présente dans la source plutôt que d'en inventer une.
- La charte du projet sert d'**arbitre en cas de silence de la source**, jamais
  de correcteur de la source.

## 4. Le texte se recopie, il ne se réécrit pas

- **Reprends les libellés au mot près**, dans la langue de la source. Ne
  reformule pas, ne raccourcis pas, ne « rends pas plus clair ».
- Pour un export dont les textes vivent dans une table de traduction, la table
  des clés appelées t'est fournie : c'est elle qui porte les libellés, sers-t'en.
- **Transcris chaque variante en entier.** Si un bloc a trois versions selon le
  rôle, l'onglet ou l'état, les trois versions sont écrites dans la page, et le
  contrôle en révèle une. Ne garde pas seulement celle qui s'affiche par défaut,
  et ne laisse pas les deux autres à un calcul côté serveur : le client doit
  pouvoir les voir en cliquant.
- **Les messages d'état sont du contenu.** Succès, échec, champ obligatoire,
  délai dépassé, chargement, liste vide, quota atteint : ces phrases sont dans la
  source (souvent dans le code des gestionnaires, ou dans la table de
  traduction), donc elles sont dans la maquette. Prévois la zone qui les
  affiche et écris-les, une par ligne. Un écran qui ne montre que son cas
  nominal fait valider une moitié d'écran.
- **Les valeurs d'exemple attachées à une variante suivent leur variante** :
  l'adresse type du placeholder, la citation et sa signature, le badge, le
  sous-titre. Elles changent avec l'option choisie, reprends-les toutes.
- **Ne fabrique pas de valeurs.** Les chiffres, montants et dates de démonstration
  sont déjà dans la source : reprends les siens. N'invente un jeu de données que
  si la source n'en montre aucun.

## 5. Ne pas enfler

Une maquette plus longue que sa source est un signal d'alarme : tu as ajouté.
Le volume attendu est du même ordre que celui de la source, souvent inférieur
(une boucle ERB remplace dix cartes répétées). Si tu dépasses, c'est que tu as
inventé une section, dupliqué un bloc au lieu d'en faire un partial, ou empilé
des états de démonstration.

## 6. Ce que tu rends

- Le ou les fichiers de vue demandés, rien d'autre.
- Aucun commentaire de justification, aucun compte rendu, aucun récapitulatif.
- Une seule exception : si la source est muette sur un point que tu es obligé de
  trancher (une route de destination, une couleur d'état absente), pose la
  question **en commentaire ERB** à l'endroit exact du choix, en une ligne.
