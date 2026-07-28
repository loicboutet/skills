---
name: brain
description: "Second cerveau cross-projet : chercher (recall) une connaissance métier réutilisable AVANT de bosser un sujet, et distiller (capture) une conclusion en fin de tâche. Notes ATOMIQUES (un concept), titre = affirmation, TL;DR en tête, rangées par domaine et reliées entre elles, via l'outil MCP brain_tool. Utilise /brain quand un projet touche un sujet métier déjà creusé (réglementation, intégration, auth, un métier récurrent...)."
---

# Brain — le second cerveau cross-projet

Ce qu'on apprend sur un projet (la réglementation d'une marketplace, un piège
BoldSign, comment on fait le multi-tenant...) ne doit pas mourir avec le projet.
Le brain le garde, rangé par **domaine**, relié en graphe, et le ressort au
projet suivant qui touche le même sujet. Accès agents via l'outil MCP
`brain_tool` ; consultation/curation humaine sur `/brain_notes` (liste + graphe).

Structure inspirée des méthodes éprouvées (Zettelkasten / evergreen notes
d'Andy Matuschak, CODE/progressive summarization de Tiago Forte), adaptées à un
corpus **lu par des agents** : ce qui compte, c'est qu'une note se comprenne et
se réutilise seule, des mois plus tard, sans le contexte du projet d'origine.

## L'anatomie d'une bonne note (le cœur)

1. **Atomique — un concept par note.** Si une note couvre deux idées, coupe-la
   en deux. Une idée par note ressort mieux à la recherche et se relie plus
   finement. (« Seuil OSS TVA marketplaces » et « Facturation en marque
   blanche » = deux notes, pas une.)
2. **Titre = une affirmation, pas un sujet.** Le titre énonce la conclusion, il
   se lit comme une phrase réutilisable.
   - ❌ `TVA marketplaces`  → ✅ `TVA marketplace UE : sous 10 000€/an, TVA du vendeur ; au-delà, TVA du client via OSS`
   - Un hit de recherche doit se comprendre **au titre seul**.
3. **TL;DR en première ligne.** La ligne 1 du contenu = le take-away en une
   phrase (progressive summarization). Le détail suit. Ainsi l'agent (ou toi)
   sous pression a l'essentiel sans tout relire.
4. **Auto-portante et concept-orientée.** La note parle du **sujet**, jamais du
   client (« ce qu'on a fait pour X »). Elle inclut le « pourquoi » et la source
   quand ça compte, pour être réutilisable hors de son projet d'origine.
5. **Reliée > rangée.** Les liens priment sur la hiérarchie (associative
   ontologies). Mets des `[[références]]` vers les notes voisines dans le
   contenu : ça tisse le graphe et fait ressortir la connaissance par proximité.
   Le `domain` et les `tags` restent des poignées légères de recherche, pas des
   dossiers rigides.
6. **Confiance honnête = maturité de la note.** `to_verify` pour une capture
   brute non recoupée (une « fleeting note »), `low`/`medium` en cours de
   consolidation, `high` pour du solide et vérifié (une « permanent note »). La
   confiance dit à l'agent suivant combien recouper avant de réutiliser.

## RECALL — avant de creuser un sujet

Dès qu'un projet touche un sujet métier déjà rencontré, **cherche le brain
AVANT** de repartir de zéro :

```
brain_tool(action: "search", query: "marketplace tva reglementation")
brain_tool(action: "get", id: 42)   # contenu complet + notes liées
```

- Cherche par mots-clés métier + `domain` si tu le connais.
- **Chaque note est une PISTE à recouper, pas une vérité** : regarde `confidence`
  et la date. Le recall te fait gagner le défrichage, pas la validation.
- Suis les `[[liens]]` : une note en amène une autre (la force du graphe).
- Rien ne remonte ? Normal, le corpus se construit — c'est à toi de créer la
  note en fin de tâche.

## CAPTURE — en fin de tâche / de recherche

Quand tu tires une **conclusion réutilisable**, distille-la selon l'anatomie
ci-dessus :

```
brain_tool(action: "create",
  title: "TVA marketplace UE : seuil OSS 10 000€/an, au-delà TVA du pays client",
  domain: "reglementation",
  tags: "marketplace, tva, oss",
  confidence: "high",
  content: "TL;DR : sous 10 000€/an de ventes UE cumulées, TVA du pays du
            vendeur ; au-delà, TVA du pays du client, déclarée via le guichet
            unique OSS.\n\nDétail : ... Source : ... Voir [[Facturation marque blanche]].")
```

- **Distille, ne dumpe pas.** Une note = une conclusion nette, pas un
  copier-coller de conversation.
- **Upsert par slug** : recréer avec le même titre **met à jour** la note (pas de
  doublon). On **complète/corrige** une note existante plutôt que d'empiler des
  variantes — une note evergreen évolue dans le temps.
- **Découpe si ça déborde** : deux idées → deux `create`, reliées par `[[...]]`.
- La **provenance** (projet courant) est tracée automatiquement. Mets un
  `confidence` honnête.
- Promeus une note quand elle a servi et tenu : `to_verify` → `high` via `update`.

## Ce qui empêche un second cerveau de pourrir

- **Capture disciplinée** : une note atomique distillée, pas un dump. Le bruit
  tue le rappel.
- **Recall câblé** : `brick-analysis-build` interroge le brain sur les domaines
  du projet au démarrage — automatique, pas un dossier qu'on espère rouvrir.
- **Densité de liens** : plus de `[[références]]` = un graphe qui ressort la
  connaissance par proximité au lieu d'un tas plat.
- **Anti-pourriture** : `confidence` + date + provenance. On réutilise en
  recoupant. Une note fausse se **corrige** (`update`) ou s'**archive**
  (`action: "archive"`), jamais on l'empile.

## Quand utiliser

- Un projet touche un domaine récurrent (réglementation, secteur, intégration
  tierce, pattern d'archi) → RECALL au démarrage.
- Tu viens de conclure une recherche/décision qui resservira → CAPTURE atomique.
- Curation humaine (relire, corriger la confiance, relier, archiver) →
  `/brain_notes` (liste + graphe).

## Ensuite

→ le recall nourrit `brick-analysis-build` (critères, archi). La capture se fait
en fin de brick ou après une recherche. Connaissance interne : rien à filmer,
rien à livrer au client.
