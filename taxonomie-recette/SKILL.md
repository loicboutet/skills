---
name: taxonomie-recette
description: "Taxonomie de reference des classes de bugs (T1-T15) a chasser SYSTEMATIQUEMENT a chaque recette, chacune avec sa methode de verification et sa provenance (le bug reel qui l'a payee). Deroulee integralement par /brick-code-review, alimentee par /brick-code-fix a chaque bug reel. Utilise /taxonomie-recette pour charger les classes pendant une recette ou un bugfix."
---

# Taxonomie de recette — v1 (2026-08-08)

Classes de bugs a chasser SYSTEMATIQUEMENT a chaque `brick-code-review`, chacune avec
sa methode de verification. Fichier VERSIONNE dans le repo skills
(github.com/loicboutet/skills, `taxonomie-recette/SKILL.md`), deploye en
`~/.claude/skills/taxonomie-recette/SKILL.md`. Toute mise a jour se committe dans le
REPO (la copie locale est ecrasee au prochain sync).

Regles de vie :
- On AJOUTE, on ne renumerote jamais. Chaque ajout est date.
- Chaque classe a : une methode de verification reproductible + sa provenance
  (le bug reel qui l'a payee).
- **Alimentation** : `brick-code-fix` ajoute chaque bug reel a sa classe (ou cree la
  classe manquante). Un bug paye une fois, chasse pour toujours.
- **Usage** : `brick-code-review` deroule TOUTES les classes ; une classe non
  pertinente = ligne "non applicable" justifiee dans la recette, jamais un silence.

Les references "gesproj" renvoient aux defauts du projet pilote de l'audit qualite
livraisons 08/2026 (identifiants A1-F2 de l'audit).

## T1 — Argent

Verifier : avoirs plafonnes au montant facture et non encaissables ; totaux
IDENTIQUES entre tous les ecrans (dashboard = fiche = liste = export) ; remises
presentes sur TOUS les documents, PDF COMPRIS ; document facture immuable (y
compris par PATCH direct) ; montants a virgule francaise ; bornes 0 € / negatif /
> 1 M€ (largeur d'affichage).
Methode : requetes hostiles directes (PATCH/POST sur les bornes), comparaison
chiffree ecran par ecran avec le jeu canonique, OUVRIR le PDF genere et comparer
au HTML ligne a ligne.
Provenance : Gespilot (devis modifiable par URL apres facturation, avoir > facture,
CA different selon l'ecran) ; gesproj A6 (remise globale affichee en HTML, omise du PDF).

## T2 — Permissions par URL directe

Verifier : chaque action interdite tentee par URL sous chaque role ET non connecte
(GET + verbe d'ecriture) ; IDOR (id devine) ; cross-tenant (donnees du second
tenant du jeu canonique inaccessibles) ; etats interdits (editer un devis facture).
Methode : requetes directes avec la session de chaque persona, attendu = refus
propre + donnee inchangee ; tests d'integration "autre entreprise introuvable".
Provenance : Gespilot (devis modifiable par URL) ; classe securite/cloisonnement
historique de brick-code-review ; gesproj B3 tenu par cette methode.

## T3 — Permissions par blocs d'affichage

Verifier : chaque donnee sensible (CA, marges, encours, salaires, coordonnees)
INVISIBLE pour chaque role qui n'y a pas droit, sur CHAQUE page qui l'affiche :
fiche, liste, dashboard, export, PDF, mail. Le controle pense pour le menu ne
protege pas la fiche.
Methode : se connecter avec chaque persona restreint du jeu canonique, ouvrir les
pages une a une, chercher la donnee a l'oeil (et au grep du HTML rendu).
Provenance : gesproj B1 (commercial billing:none lisait "Encours" et "Total facture"
sur la fiche client — blocs non gardes par `can?(:billing)`).

## T4 — Facade : affiche ↔ saisissable

Verifier : chaque champ rendu (HTML, PDF, mail) a un chemin de saisie UI complet
(formulaire + `permit`) OU une decision ecrite disant d'ou vient la donnee
(calculee, importee, seedee). Et l'inverse : champ saisi jamais affiche = a questionner.
Methode : matrice champ par champ de la reanalyse rejouee sur le code : pour chaque
colonne lue dans une vue, trouver son input ET sa ligne de `permit` ; creer
l'enregistrement DEPUIS l'UI et verifier la sortie complete.
Provenance : gesproj C1 (postal_code imprime sur factures + PDF, absent du form et du
permit) ; Gespilot (51 cas affiches sans etre saisissables, 35 colonnes mensongeres) ;
educxa (recherche affichee qui n'existait pas) ; Tastellers (compteurs en dur).

## T5 — Facade : cle de config saisie = cle utilisee

Verifier : toute cle/credential/parametre saisissable en UI est LU par le code qui
s'en sert reellement au moment de l'usage (envoi, appel API).
Methode : suivre le fil ecran → stockage → point d'usage ; changer la valeur en UI
et prouver que le comportement change (ou que l'envoi lit bien ce stockage).
Provenance : gesproj C4 (ecran /admin/api_keys stockait un ApiCredential postmark jamais
lu ; la prod expediait via `credentials.dig(:postmark,:api_token)`).

## T6 — Suppressions & cascades

Verifier : pour chaque entite, la suppression JOUE la decision d'analyse
(bloquer / archiver / cascader) et n'emporte rien d'imprevisible ; auditer les
`dependent: :destroy` latents ; supprimer un enfant ne detruit pas le parent metier.
Methode : jouer chaque suppression depuis l'UI sur les cas "archive avec affaire
liee" du jeu canonique ; `grep dependent:` et confronter chaque occurrence a
`decisions_comportement.md`.
Provenance : gesproj D3 (`Client has_many :invoices, dependent: :destroy` latent malgre
l'archivage doux) ; decisions de comportement de l'audit 08/2026.

## T7 — Dates & fuseau

Verifier : suite de tests verte a J, J+3 et J+90 (shim d'horloge / `travel_to`) ;
fixtures et seeds en dates RELATIVES uniquement ; `config.time_zone` defini ;
libelles et regroupements corrects pour l'entite de l'annee precedente et
l'echeance qui traverse mois/annee (jeu canonique).
Methode : rejouer la suite avec horloge decalee ; ouvrir les ecrans de dates avec
les cas temporels du jeu.
Provenance : audit 08/2026 (fixtures de dates qui explosent a J+3, CI muette 8 jours) ;
gesproj F2/D1 tenus grace a ce controle.

## T8 — Etats degrades

Verifier : compte desactive (plus de mails, plus d'acces), entite suspendue
(EXCLUE des jobs recurrents et des envois), collection vide (empty state prevu),
association nil, ressource orpheline/archivee au milieu d'un parcours, service
externe down → degradation propre, jamais de 500.
Methode : jouer les parcours avec les cas "difficiles" du jeu canonique (suspendu
avec recurrence programmee, desactive, invitation en attente) ; declencher les jobs.
Provenance : gesproj D2 (`GenerateRecurringInvoicesJob` n'excluait pas les entreprises
suspendues) ; classe etats degrades historique de brick-code-review.

## T9 — Idempotence

Verifier : **un GET n'ecrit JAMAIS** (aucune creation/mutation dans une action
d'affichage) ; double soumission du meme formulaire = pas de doublon ; action
re-jouee = pas de double facturation ; re-creation apres suppression OK.
Methode : grep des ecritures dans les actions index/show ; compter les
enregistrements avant/apres un double submit (system test double-clic).
Provenance : classe idempotence/re-jeu historique de brick-code-review ; regle
"un GET n'ecrit jamais" ajoutee a l'audit 08/2026 (persona "secretaire pressee
qui double-clique").

## T10 — Mobile 390 px

Verifier (si responsive DANS le scope, cf. `decisions_comportement.md`) : ecrans
cles a 390 px sans scroll horizontal (`scrollWidth` <= 390), formulaires
utilisables, tableaux geres (scroll interne ou reflow prevu par la maquette).
Methode : `playwright-cli resize 390 844` + `eval "document.documentElement.scrollWidth"`
sur chaque ecran cle + captures dans le rapport de parite.
Si "hors scope assume (ecrit)" : verifier que c'est ecrit, capturer pour trace.
Provenance : gesproj E1 (contacts a 1264 px dans 390) ; Gespilot ET educxa ("personne
n'avait jamais ouvert l'app en 390 px").

## T11 — Dev / prod

Verifier : APP_HOST configure (liens des mails sur le host reel, pas app.5000.dev) ;
pages legales / footer existent ; `/mockups` NON expose en prod (mais jamais
supprime du repo) ; aucun compte/mot de passe en dur (migrations, seeds joues en
prod, superadmin "secret") ; widget feedback gated.
Methode : grep des hosts en dur et des credentials ; lire la config par env ;
curl des routes footer et /mockups sur l'env cible.
Provenance : Tastellers ET educxa (mails pointant sur app.5000.dev) ; Gespilot
(superadmin `secret5000` actif en prod, /mockups expose) ; gesproj B4 tenu.

## T12 — i18n & formats

Verifier : AUCUN "translation missing" sur aucune page ; dates au format locale
fr ; messages d'erreur comprehensibles cote client (pas d'anglais technique).
Methode : crawl de toutes les pages connectees + grep "translation missing" dans
le HTML rendu ; ouvrir les formulaires en erreur.
Provenance : classe i18n/formats historique de brick-code-review, elargie a
l'audit 08/2026.

## T13 — E-mails

Verifier : chaque mail HABILLE marque blanche (layout, logo/couleurs du tenant,
pas le scaffold "styles need to be inline") ; bon destinataire ; liens sur le bon
host ; contenu rendu depuis le template prevu (pas un `simple_format` brut).
Methode : generer chaque mail reel (previews / test qui capture `deliveries`),
OUVRIR le HTML produit, verifier layout + liens + variables.
Provenance : gesproj E3 (layout mailer scaffold vide, zero habillage tenant) ;
gesproj C3 tenu ; audit APP_HOST.

## T14 — Donnees limites

Verifier : apostrophes, accents, unicode et HTML dans les champs texte (echappement,
pas d'injection) ; textes tres longs tronques proprement ; casse des emails et
espaces parasites ; bornes numeriques (0, negatif, longueur max).
Methode : exercer les chaines hostiles du jeu canonique ("O'Brien & Ça Frères",
texte long, entree HTML) depuis l'UI et verifier chaque sortie (liste, fiche, PDF, mail).
Provenance : classe donnees limites historique de brick-code-review ; chaines
hostiles du jeu canonique.

## T15 — Flux asynchrones & fichiers

Verifier : jobs enqueues avec les bons arguments (et pas pour les entites
suspendues, cf. T8) ; uploads/downloads OK, types interdits refuses ; PDF generes
nommes correctement (un avoir ne s'appelle pas FAC-...).
Methode : tests d'integration sur `enqueued_jobs` ; upload reel depuis l'UI ;
telecharger chaque type de document et lire son nom + son titre.
Provenance : classe flux transverses historique de brick-code-review ; gesproj D5
(PDF d'avoir nomme `FAC-2026-0005.pdf`).

## Journal des versions

- **v1 — 2026-08-08** : creation. Classes issues de : l'audit qualite livraisons
  08/2026 (Gespilot, Tastellers, educxa), le projet pilote gesproj de ce meme
  audit (68/100, echecs B1/C1/C4/E1/A7/E3), et l'ancienne liste inline de
  brick-code-review (versee ici : securite/cloisonnement → T2, etats
  degrades → T8, donnees limites → T14, idempotence → T9, flux
  transverses → T13/T15, i18n → T12).
