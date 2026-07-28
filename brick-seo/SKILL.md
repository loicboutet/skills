---
name: brick-seo
description: "SEO transverse pour toute brique avec pages publiques : ciblage requetes, head complet, JSON-LD, contenu citable (GEO), puis implementation Rails (sitemap Kamal, staging noindex, CWV) et checklist review. Utilise /brick-seo en phase mockup ET en phase code des qu'un projet a une partie publique."
---

# Brick SEO

Toute page PUBLIQUE d'un projet client doit être construite pour être trouvée : par Google,
et par les moteurs IA (ChatGPT, Perplexity, AI Overviews) qui lisent le HTML brut. Le SEO
n'est pas une couche qu'on ajoute après : il se joue dans la structure de la page au moment
où on l'écrit. Ce skill s'applique en phase MOCKUP (structure et contenu) puis en phase CODE
(implémentation Rails), et alimente la checklist de `/brick-code-review`.

Un site server-rendered Rails/Hotwire part avec un avantage structurel : le HTML complet est
dans la réponse serveur, lisible par Googlebot ET par les crawlers IA qui n'exécutent pas le JS.

## Quand utiliser

- La brique contient des pages publiques (vitrine, catalogue, annonces, blog, pages services)
- En phase mockup : appliquer la section "Phase mockup" en écrivant les vues
- En phase code : appliquer la section "Phase code (Rails 8 / Kamal)"
- Avant livraison : dérouler la checklist review

## Avant d'écrire : 30 secondes de ciblage

Pour chaque page publique, formule la requête cible principale (métier + ville pour du local,
besoin + qualificatif sinon) et 2-3 requêtes secondaires. La page doit répondre à CETTE
requête. Une requête = UNE page : ne répète pas la même section sur deux pages (cannibalisation),
chaque page garde son angle et linke vers l'autre.

## Phase mockup : la structure de page

### Le head, complet, sur CHAQUE page (pas seulement l'accueil)
- `<title>` : 50-60 caractères, unique par page, l'essentiel d'abord (mot-clé + ville),
  la marque à la fin. Ex : `Cuisiniste sur mesure à Rennes | Atelier Roussel`.
- `<meta name="description">` : 140-160 caractères, unique, répond à l'intention + un fait
  concret (prix, délai, note d'avis) + appel à l'action factuel.
- `<link rel="canonical">` : URL absolue https, auto-référente.
- `<html lang="fr">`, `<meta charset="utf-8">` en premier, viewport.
- Open Graph : og:title, og:description, og:image (URL absolue), og:url, og:type +
  `<meta name="twitter:card" content="summary_large_image">`.

### Données structurées JSON-LD (dans le head) : règle du "chaque page"
- Le bloc Organization/LocalBusiness (sous-type LE PLUS PRÉCIS : HomeAndConstructionBusiness,
  Physiotherapy, ProfessionalService, EmploymentAgency…) avec name, address complet, telephone,
  openingHoursSpecification, geo, priceRange, aggregateRating si avis réels, est présent sur
  CHAQUE page publique (via un @graph commun), pas seulement l'accueil.
- Le NAP (nom, adresse, téléphone) apparaît AUSSI en texte dans le footer de CHAQUE page,
  identique au caractère près au JSON-LD. Si le brief ne fournit pas le NAP, ne l'invente
  JAMAIS (une adresse inventée publiée = incohérence NAP durable chez Google), et n'affiche
  JAMAIS "[adresse à compléter]" dans la page : le footer montre uniquement ce qu'on a
  (ex : "Paris" + email), le manque est signalé en `<!-- À VALIDER CLIENT -->` et dans la
  note de livraison, et le NAP est absent du JSON-LD tant qu'il est incomplet.
- Pages profondes → + BreadcrumbList. Listings → + ItemList ; offres d'emploi → JobPosting
  (Google for Jobs : hiringOrganization nommé + description par offre, jamais "confidentiel"
  en masse) ; produits → Product ; FAQ → FAQPage (plus de rich result depuis mai 2026 mais
  ×2,7 de citations par les moteurs IA).

### Structure du contenu
- UN SEUL `<h1>` : la requête cible reformulée naturellement (pas le nom de la marque seul).
- Hiérarchie Hn sans saut. Formule des H2/H3 en questions quand c'est naturel
  ("Combien coûte une cuisine sur mesure ?") : les moteurs IA matchent les questions.
- Réponse d'abord : les 150-200 premiers mots du main répondent à la requête principale.
  Sous chaque H2, un premier paragraphe autonome de 40-75 mots qui se suffit à lui-même.
- Au moins une liste ou un tableau substantiel (les tableaux sont cités 4× plus par les IA).
- FAQ : 4-6 vraies questions sur les pages piliers, mini-FAQ (3) même sur les listings,
  toujours avec le schema FAQPage.
- Sémantique HTML5 : un seul `<main>`, header/nav/footer, article/section.
- Chiffres précis du brief plutôt que des généralités. Tout chiffre de marché externe est
  SOURCÉ ET DATÉ ("1 900 € brut en moyenne (observatoire de la branche, 2026)").
- Ancrage temporel : dates visibles ("Mis à jour le…", dates des annonces), phrases
  comparatives datées quand c'est pertinent : c'est ce qui se fait citer.
- Une question de DÉCISION couverte (comparatif matériau A vs B, fourchettes par gamme,
  indépendant vs chaîne) : le contenu qui déclenche le devis et que les IA citent.
- Fiches d'objets (réalisations, annonces, soins) : données citables par fiche (date, lieu,
  budget/fourchette, durée, particularité résolue), pas de simples légendes.
- Preuve sociale citable : verbatim daté et situé + prénom > note "4,8/5" répétée.
- E-E-A-T : preuves nominatives (diplômes, années, affiliations) sur les pages d'expertise ;
  infos pratiques locales (accès, parking, transports, délais) sur les pages locales.
- Longue traîne prévue dans le maillage (formation, "comment devenir X", reconversion,
  prix moyens) : liens normaux, sans mention "(à venir)".

### Cohérence (les moteurs et les clients la vérifient)
- COHÉRENCE FACTUELLE : chaque fait n'a qu'une seule version entre sections et entre pages.
- COHÉRENCE DES NOMBRES ET DATES : compte annoncé = compte affiché = valeur JSON-LD ; ordre
  déclaré ("du plus récent") = ordre réel = ItemListOrder ; "cette année" compatible avec les
  dates affichées ; la pagination raconte la même histoire que les totaux.
- Anti-bourrage : une même expression clé ≤ 4-5 fois par page, synonymes naturels du métier.
- RÈGLE DES DONNÉES MANQUANTES : ni inventer, ni "emplacement réservé" / "à confirmer" en
  pleine page. Texte neutre plausible + `<!-- À VALIDER CLIENT : … -->` + liste des points à
  valider dans la note de livraison. La page a toujours l'air finie.
- Jamais de jargon interne sur une page publique ("brique 2", "maquette de démonstration") :
  le hors-brique se marque par le badge overlay standard, pas dans la copy.
- Écriture : jamais de tiret cadratin ni de formule d'IA. Un humain du métier.

### Images et liens
- alt descriptif (alt="" si décorative), width/height TOUJOURS (CLS).
- Image héros : jamais loading="lazy", fetchpriority="high". Le reste : loading="lazy".
- Ancres descriptives ("Voir nos cuisines en chêne", jamais "cliquez ici"/"en savoir plus").
- Pagination : liens `<a href="?page=2">` réels, canonical auto-référent PAR page (JAMAIS
  tout vers la page 1), title différencié "… - page 2".

### Le SEO ne doit JAMAIS aplatir le design
Le contenu SEO (FAQ, tableaux, paragraphes-réponses) fait partie de la direction artistique :
FAQ en accordéons stylés, tableaux traités comme des composants, densité répartie dans le
rythme des sections. Un bloc de texte plat plaqué en bas de page = raté.

### Mythes morts (ne plus faire)
meta keywords, densité de mots-clés, rel next/prev, AMP, 300 mots minimum, changefreq/priority,
redirection de masse vers l'accueil, bourrage de la même requête dans chaque titre.

## Phase code (Rails 8 / Kamal)

### Helpers (pas de gem sauf OG avancé → gem meta-tags)

```ruby
# app/helpers/seo_helper.rb
module SeoHelper
  def page_title(title = nil)
    content_for(:title, title) if title
    [content_for(:title), "NomClient"].compact.join(" · ")
  end

  def meta_description(text = nil)
    content_for(:meta_description, text.to_s.truncate(160)) if text
    content_for(:meta_description) || "Description par défaut."
  end

  def canonical_url(url = nil)
    content_for(:canonical, url) if url
    content_for(:canonical) || url_for(only_path: false, params: {})
  end

  def json_ld(data)
    tag.script(raw(data.compact.to_json), type: "application/ld+json")
  end
end
```

Dans le layout (head) : title, description, canonical, OG rendus sur CHAQUE page. Turbo 8
merge le head : une meta conditionnelle absente d'une réponse est SUPPRIMÉE au merge → les
meta communes vivent dans le layout, toujours. Garder `data-turbo-track: "reload"`. Jamais de
contenu SEO dans un Turbo Frame lazy (absent du HTML initial).

### Slugs : friendly_id + history dès le départ sur tout contenu public

```ruby
friendly_id :title, use: [:slugged, :history]
# controller show :
redirect_to @record, status: :moved_permanently if request.path != record_path(@record)
```

### Redirections
- www→apex : `constraints(host: /^www\./)` + redirect 301 dans routes.rb, ET les 2 hosts
  dans proxy.hosts de config/deploy.yml.
- Tout déplacement définitif : `status: :moved_permanently` (le défaut Rails est 302 !).
- Record supprimé : vrai 404/410 (jamais rescue → redirect root = soft 404).
- 1 seul saut de redirection maximum.

### Pagination (Pagy)
Canonical auto-référent par page, strip des params de tri, title "… - page 2", vrais liens.
Infinite scroll : garder les liens ?page=N dans le HTML.

### Performance (Core Web Vitals : LCP <2,5s, INP <200ms, CLS <0,1)
- `fresh_when` sur show/index publics (`public: true` UNIQUEMENT si page anonyme sans formulaire).
- Russian doll caching sur les listes publiques (`render collection cached: true`, touch: true).
- Images : variants WebP + width/height partout ; héros eager + fetchpriority=high ;
  le reste lazy. `preload_link_tag` sur la police woff2 self-hosted (pas 3 requêtes Google
  Fonts cross-origin en prod).
- Cibles : CSS purgé < 20 Ko gz, TTFB < 500 ms, DOM < 1500 nœuds.

### robots.txt + sitemap sur Kamal
- robots.txt DYNAMIQUE (route) : staging → `Disallow: /` ; prod → Disallow /admin + ligne
  `Sitemap:`. Ne PAS bloquer GPTBot/PerplexityBot/ClaudeBot/OAI-SearchBot (les bloquer =
  disparaître des réponses des moteurs IA).
- gem sitemap_generator, génération AU BUILD (filesystem éphémère Kamal) :
  `.kamal/hooks/pre-build` → `RAILS_MASTER_KEY=$(cat config/master.key) bin/rails sitemap:refresh:no_ping`
  Vérifier que public/sitemap* n'est ni dans .dockerignore ni .gitignore.
- Soumettre le sitemap à Google Search Console ET Bing Webmaster Tools (Bing alimente
  ChatGPT). GSC : propriété Domaine, TXT via `gandi_create_dns_record`, puis
  `google_search_console_manage_sitemap`.

### Staging jamais indexé
```ruby
# ApplicationController — les 2 envs tournent en RAILS_ENV=production → flag d'env
before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") if ENV["APP_STAGE"] == "staging" }
```
`APP_STAGE: staging` dans config/deploy.staging.yml (env: clear:). + robots.txt dynamique.

## Checklist review (à dérouler dans /brick-code-review)

- [ ] Chaque page publique : title unique 50-60c, meta description unique, canonical
- [ ] curl staging → X-Robots-Tag: noindex présent ; curl prod → ABSENT
- [ ] robots.txt prod : pas de Disallow: /, ligne Sitemap, bots IA non bloqués
- [ ] sitemap.xml.gz accessible en prod, soumis GSC + Bing
- [ ] JSON-LD valide (validator.schema.org) sur home + 1 page de chaque gabarit
- [ ] NAP identique au caractère près JSON-LD / footer / (fiche Google si existante)
- [ ] 404 réel sur URL bidon (pas 200, pas redirect home)
- [ ] Test d'intégration : unicité des <title> des pages publiques
- [ ] Image héros : pas de loading=lazy, fetchpriority=high ; toutes images width/height
- [ ] Redirections www/http : 1 seul saut
- [ ] Aucun contenu public dans un Turbo Frame lazy
- [ ] Cohérence nombres/dates (comptes annoncés = affichés = JSON-LD)
- [ ] Aucun placeholder visible, aucun jargon interne, aucun tiret cadratin

## Ensuite

→ Phase mockup : retour à `brick-mockup-review`. Phase code : retour à `brick-code-review`.
