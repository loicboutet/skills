---
name: brain
description: "Second cerveau cross-projet : chercher (recall) une connaissance métier réutilisable AVANT de bosser un sujet, et distiller (capture) une conclusion en fin de tâche. Notes rangées par domaine, partagées entre tous les projets, via l'outil MCP brain_tool. Utilise /brain quand un projet touche un sujet métier qu'on a déjà creusé (réglementation, intégration, auth, un métier récurrent...)."
---

# Brain — le second cerveau cross-projet

Ce qu'on apprend sur un projet (la réglementation d'une marketplace, un piège
d'intégration BoldSign, comment on fait le multi-tenant...) ne doit pas mourir
avec le projet. Le brain le garde, rangé par **domaine** (pas par projet), et le
ressort au projet suivant qui touche le même sujet. Accès via l'outil MCP
`brain_tool` ; consultation/curation humaine sur `/brain_notes`.

## Deux gestes, à deux moments

### 1. RECALL — avant de creuser un sujet
Dès qu'un projet touche un sujet métier déjà rencontré, **cherche le brain
AVANT** de repartir de zéro :

```
brain_tool(action: "search", query: "marketplace tva reglementation")
brain_tool(action: "get", id: 42)   # lire le contenu complet d'un hit
```

- Cherche par mots-clés métier + `domain` si tu le connais.
- **Traite chaque note comme une PISTE à revérifier, pas une vérité** : regarde
  `confidence` (high/medium/low/to_verify) et la date. Une note `to_verify` ou
  vieille se recoupe avant d'être réutilisée. Le recall te fait gagner le
  défrichage, pas la validation.
- Si rien ne remonte, c'est normal (le corpus se construit) : c'est à toi de
  créer la note en fin de tâche.

### 2. CAPTURE — en fin de tâche / de recherche
Quand tu as tiré une **conclusion réutilisable** (une recherche réglementaire,
une décision d'archi qui vaut pour d'autres projets, un piège d'intégration),
distille-la en UNE note propre :

```
brain_tool(action: "create",
  title: "TVA sur les marketplaces UE",
  domain: "reglementation",
  tags: "marketplace, tva, oss",
  confidence: "high",
  content: "Seuil OSS 10 000€/an cumulé UE : en dessous, TVA du pays du vendeur ;
            au-dessus, TVA du pays du client, déclarée via le guichet OSS. ...")
```

- **Distille, ne dumpe pas.** Une note = une conclusion auto-portante, lisible et
  actionnable telle quelle sur un futur projet, sans le contexte de celui-ci. Pas
  un copier-coller de conversation.
- **Rangée par domaine, pas par projet.** Le titre et le contenu parlent du SUJET
  (« TVA marketplaces »), jamais du client (« ce qu'on a fait pour X »).
- **Upsert par slug** : recréer avec le même titre met à jour la note existante
  (pas de doublon). Complète/corrige une note plutôt que d'en empiler des variantes.
- La **provenance** (le projet courant) est tracée automatiquement.
- Mets un `confidence` honnête : `to_verify` pour une piste non recoupée, `high`
  pour du solide et vérifié.

## Ce qui fait qu'un second cerveau NE pourrit pas

- **Capture disciplinée** : une note distillée en fin de tâche, pas un dump de
  tout. Le bruit tue le rappel.
- **Recall câblé** : `brick-analysis-build` cherche le brain sur les domaines du
  projet au démarrage — le rappel est automatique, pas un dossier qu'on espère
  rouvrir.
- **Anti-pourriture** : `confidence` + date + provenance. On réutilise en
  recoupant, jamais en gobant. Si une note se révèle fausse, on la corrige
  (update) ou on l'archive (`action: "archive"`).

## Quand utiliser

- Un projet touche un domaine métier récurrent (réglementation, un secteur, une
  intégration tierce, un pattern d'archi) → RECALL au démarrage.
- Tu viens de conclure une recherche ou une décision qui resservira → CAPTURE.
- Curation humaine (relire, corriger la confiance, archiver le périmé) → `/brain_notes`.

## Ensuite

→ le recall nourrit `brick-analysis-build` (criteres, archi). La capture se fait
en fin de brick ou après une recherche. Rien à filmer, rien à livrer au client :
c'est de la connaissance interne.
