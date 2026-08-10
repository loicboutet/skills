#!/usr/bin/env ruby
# frozen_string_literal: true

# facade_scan.rb — scanner de "façades non branchées" (lab livraison 5000.dev)
#
# Le bug signature du pipeline maquette→code : un élément d'interface qui a
# l'air fonctionnel mais n'est branché sur rien (champ sans name, action
# Stimulus orpheline, lien vers une route inexistante, données en dur héritées
# de la maquette). Ce script les repère, il ne les corrige pas.
#
# Les modes `static` et `crawl` vérifient qu'un contrôle d'interface mène
# quelque part. Les modes `reachability` et `readwrite` vérifient la flèche
# INVERSE : une action serveur / une colonne de base que rien, dans l'interface,
# ne permet de déclencher ou de remplir. Même défaut, vu de l'autre bout.
#
# Usage :
#   ruby facade_scan.rb static       <rails_app_dir> [--json] [--no-boot]
#   ruby facade_scan.rb crawl        <base_url> [--cookie "k=v"] [--json] [--max N]
#   ruby facade_scan.rb reachability <rails_app_dir> [--json] [--no-boot] [--mockups]
#   ruby facade_scan.rb readwrite    <rails_app_dir> [--json] [--mockups]
#
# Sortie : rapport texte groupé par catégorie (fichier:ligne, nom de route ou
# nom de colonne), puis un résumé JSON (comptes par catégorie et par gravité).
# --json = JSON seul. Exit 0 toujours.

require "json"
require "set"
require "uri"
require "net/http"
require "digest"

# ---------------------------------------------------------------------------
# Réglages / allowlists — à ajuster par projet si le rapport est trop bruyant.
# ---------------------------------------------------------------------------
CONFIG = {
  # Sous-répertoires de app/views exclus du scan statique (les maquettes n'ont
  # pas à être branchées, c'est le principe).
  excluded_view_dirs: %w[mockups],

  # Extensions de vues scannées.
  view_glob: "**/*.html*.erb",

  # Helpers *_path/*_url qui ne sont PAS des routes (assets & co).
  helper_allowlist: %w[
    image_path image_url asset_path asset_url audio_path audio_url
    video_path video_url font_path font_url javascript_path stylesheet_path
    path_to_asset path_to_image polymorphic_path polymorphic_url url_for
  ] + %w[
    session password registration confirmation unlock
  ].flat_map { |r| [ r, "new_#{r}", "edit_#{r}", "destroy_#{r}", "cancel_#{r}" ] }
    .flat_map { |r| [ "#{r}_path", "#{r}_url" ] },   # helpers Devise portés par le scope

  # Types d'input jamais concernés par "contrôle sans name".
  ignored_input_types: %w[submit button reset image],

  # Lignes ignorées par l'heuristique "nombre en dur" (regex sur la ligne texte).
  numeric_line_allowlist: [
    /©|&copy;/i,          # mentions copyright
    /\A\s*\z/,            # lignes vides
  ],
  # Nombres ignorés par l'heuristique (regex sur le nombre lui-même).
  numeric_value_allowlist: [
    /\A(19|20)\d{2}\z/,   # années seules (copyright, mentions légales)
  ],
  # Unités/contextes qui suivent un nombre légitime dans du texte d'aide
  # ("14 chiffres", "512 px", "30 derniers jours"). Les montants (€, %) restent
  # signalés : c'est justement le résidu de maquette typique.
  numeric_unit_after: /\A\s*(px\b|[kmg]o\b|octets?\b|caract|chiffre|jour|mois\b|ans?\b|heure|minute|seconde|derni|×|x\d)/i,
  numeric_context_before: /(?:[×x@\/]|n°\s*|ex\.\s*[\w-]*)\z/i,
  # Plafond d'affichage texte par catégorie (le JSON garde le compte exact).
  max_shown_per_category: 40,

  # Crawl : pages max, liens jamais suivis (déconnexion, destructifs).
  crawl_max_pages: 150,
  crawl_skip_href: [/sign_out|logout|deconnexion/i, /\Amailto:|\Atel:|\Ajavascript:/i],

  # Timeout (s) pour `bin/rails routes` en mode static.
  rails_routes_timeout: 90,

  # -------------------------------------------------------------------------
  # Mode reachability — routes qu'aucun geste d'utilisateur n'a à atteindre.
  # -------------------------------------------------------------------------
  # Contrôleurs jamais pilotés depuis l'interface (framework, moteurs montés,
  # authentification générée).
  reach_skip_controller: [
    %r{\Arails/}, %r{\Aactive_storage/}, %r{\Aaction_mailbox/}, %r{\Aaction_text/},
    %r{\Aturbo/}, %r{\Adevise/}, %r{\Aletter_opener_web/}, %r{\Amission_control/},
    %r{\Asolid_queue/}, %r{\Asidekiq/}, %r{\Aactive_admin/},
  ],
  # Chemins légitimement sans geste : webhooks, callbacks OAuth, API, santé,
  # PWA/service worker, fichiers bien connus.
  reach_skip_path: [
    %r{\A/rails/}, %r{\A/up(\.|\z|\()}, %r{\A/api/}, %r{\A/api\z},
    %r{/webhooks?(/|\z|\()}, %r{/callbacks?(/|\z|\()}, %r{/callback(/|\z|\()},
    %r{\A/auth/}, %r{\A/oauth}, %r{/oauth/}, %r{\A/\.well-known}, %r{/healthz?(\.|\z|\()},
    %r{\A/cable}, %r{\A/letter_opener}, %r{\A/sidekiq}, %r{\A/jobs},
    %r{manifest\.json}, %r{service-?worker}, %r{\A/robots}, %r{\A/sitemap},
    %r{\A/users/}, %r{\A/user/(sign|password|confirmation|unlock)},
  ],
  # Actions qu'on n'exige jamais d'atteindre par un lien (pages d'entrée, cibles
  # d'e-mail ou de redirection).
  reach_get_entry_actions: %w[],
  # Vues supplémentaires scannées pour les gestes (en plus de app/views).
  reach_gesture_dirs: %w[app/views app/components app/javascript app/controllers app/mailers app/helpers],

  # -------------------------------------------------------------------------
  # Mode readwrite — colonnes légitimement invisibles côté interface.
  # -------------------------------------------------------------------------
  rw_skip_tables: [
    /\Aactive_storage_/, /\Aaction_text_/, /\Aaction_mailbox_/, /\Asolid_/,
    /\Aar_internal_metadata\z/, /\Aschema_migrations\z/, /\Asessions\z/,
    /\Ataggings?\z/, /\Afriendly_id_slugs\z/, /\Aversions\z/, /\Apghero_/,
  ],
  # Colonnes techniques : jamais ni lues ni saisies « pour de vrai ».
  rw_skip_columns: [
    /\Aid\z/, /\A(created|updated)_at\z/, /_id\z/, /\Alock_version\z/,
    /_count\z/, /_type\z/, /\Aslug\z/, /\Aposition\z/, /\Auuid\z/,
    # authentification / Devise / has_secure_password
    /\Aencrypted_password\z/, /\Apassword_digest\z/, /\Areset_password_/,
    /\Aremember_created_at\z/, /\Asign_in_count\z/, /\A(current|last)_sign_in_/,
    /\Aconfirm(ation|ed)_/, /\Aunconfirmed_/, /\Afailed_attempts\z/,
    /\Aunlock_token\z/, /\Alocked_at\z/, /_token\z/, /_digest\z/,
    # cache / audit / traces
    /\Acached_/, /_cache\z/, /\Aip_address\z/, /\Auser_agent\z/,
    /\Aendpoint\z/, /\Ametadata\z/, /\Adata\z/, /\Asettings\z/,
  ],
  # Répertoires dont l'écriture ne compte PAS comme une saisie utilisateur
  # (jeux de données, pas gestes d'interface).
  rw_data_only_dirs: %w[db/seeds db/seeds.rb db/migrate test spec features],

  # -------------------------------------------------------------------------
  # Détecteur « colonne alimentée UNIQUEMENT par les seeds ».
  # -------------------------------------------------------------------------
  # Fichiers de données qui ne tournent JAMAIS chez le client : ce qu'ils
  # écrivent n'existe que sur le poste du développeur (`db:seed` ne se rejoue
  # pas en production, les fixtures encore moins).
  rw_seed_paths: [ %r{\Adb/seeds\.rb\z}, %r{\Adb/seeds/}, %r{\A(test|spec)/fixtures/} ],
  # Fichiers de données REJOUABLES en production : une tâche rake lancée au
  # déploiement, une migration de données. Une colonne alimentée là n'est pas
  # une façade, c'est un import. Les fichiers de seeds qu'une tâche rake
  # require / appelle basculent dans ce seau (cas réel : `lib/tasks/ontology.rake`
  # qui exécute `db/seeds/ontology/import.rb`).
  rw_replayable_paths: [ %r{\Alib/tasks/}, %r{\Adb/migrate/}, %r{\Adb/data/} ],
  # Surfaces où une colonne est réellement VUE par l'utilisateur final : c'est
  # là que l'écart dev/prod se transforme en mensonge à l'écran.
  rw_render_surface: %r{\Aapp/(views|helpers|mailers|components|serializers|presenters)/},
  # Sous-dossiers de app/views qui ne sont pas le produit livré (maquettes,
  # exports d'outils de design) : y lire une colonne ne prouve rien.
  rw_not_shipped_dirs: %w[mockups lovable figma design_system styleguide],
  # Fichiers qui produisent un document sortant : une colonne lue là et jamais
  # saisissable est bloquante (le client reçoit un document faux).
  rw_outgoing_path: /mailer|_mail\b|pdf|prawn|wicked|document_template|renderer|\/documents?\//i,
  # Tableaux markdown de doc/memory/data_models.md (mode --mockups).
  rw_doc_models: "doc/memory/data_models.md",
  # Phase maquettes : une maquette AFFICHE toujours un total et un numéro de
  # document, elle ne les saisit jamais — ce n'est pas une façade.
  rw_mockup_skip_columns: [ /\Atotal_/, /_cents\z/, /\Anumber\z/, /\Aslug\z/ ],
  # Modèles jamais montés en écran de saisie (journal, technique).
  rw_skip_models: [ /audit/i, /\ASession\z/, /PushSubscription/i, /\AApiCredential\z/ ],
  # Mots trop génériques pour rapprocher un champ du modèle d'un token de maquette.
  rw_fuzzy_stopwords: %w[name value type kind id date at on of line the la le],
  # Qualificatifs qui ne changent pas la nature du champ : `vat` dans la maquette
  # vaut bien `vat_rate` du modèle, alors que `quote` ne vaut pas `quote_prefix`.
  rw_fuzzy_qualifiers: %w[rate cents amount value input],
}.freeze

ERB_EXPR = "E"  # marqueur d'un <%= ... %>
ERB_STMT = "S"  # marqueur d'un <% ... %> / <%# ... %>

Finding = Struct.new(:category, :location, :detail, :severity)

# Corps d'un tag HTML, robuste aux ">" dans les valeurs d'attributs
# (data-action="change->auto-submit#submit").
TAG_BODY = /(?:[^>"']|"[^"]*"|'[^']*')*/

class Report
  CATEGORIES = {
    "control_without_name"     => "Contrôles de formulaire sans name (façade de champ)",
    "missing_stimulus"         => "Référence à un controller Stimulus inexistant",
    "inert_data_action"        => "data-action sur élément non interactif sans événement explicite",
    "dead_link"                => "Liens href=\"#\" ou vides",
    "hardcoded_number"         => "Nombres en dur suspects (héritage maquette ? heuristique, faux positifs attendus)",
    "unknown_route_helper"     => "Helper de route introuvable dans les routes",
    "http_error"               => "Pages en erreur HTTP (>= 400)",
    "form_without_action"      => "Formulaires sans action",
    "button_not_wired"         => "Boutons hors formulaire sans branchement",
    # --- reachability ------------------------------------------------------
    "route_without_action"     => "Route déclarée vers une action qui n'existe pas",
    "write_route_unreachable"  => "Action non-GET qu'aucun geste d'interface ne déclenche",
    "write_route_js_only"      => "Action non-GET atteinte seulement par du JS (branchement non vérifiable)",
    "get_route_orphan"         => "Page GET vers laquelle aucun lien ne mène (page d'entrée légitime ? à vérifier)",
    # --- readwrite ---------------------------------------------------------
    "column_seed_only"         => "Colonne affichée mais alimentée par les seuls seeds/fixtures (vide ou figée chez un vrai utilisateur)",
    "column_read_not_writable" => "Colonne lue mais jamais saisissable (l'utilisateur voit sans pouvoir renseigner)",
    "column_written_not_read"  => "Colonne saisie mais jamais lue (l'utilisateur remplit dans le vide)",
    "column_displayed_only"    => "Colonne affichée, alimentée par le code seul (dérivée ? ou saisie manquante)",
    "column_dead"              => "Colonne ni lue ni écrite nulle part",
    "field_absent_from_mockups" => "Champ du modèle absent des maquettes (ni affiché ni saisi)",
  }.freeze

  # Gravité par catégorie. nil = catégories historiques (static/crawl), imprimées
  # comme avant, sans en-tête de gravité.
  SEVERITIES = {
    "route_without_action"      => "bloquant",
    "write_route_unreachable"   => "bloquant",
    "column_seed_only"          => "bloquant",
    "column_read_not_writable"  => "majeur",
    "column_written_not_read"   => "majeur",
    "field_absent_from_mockups" => "majeur",
    "write_route_js_only"       => "info",
    "get_route_orphan"          => "info",
    "column_displayed_only"     => "info",
    "column_dead"               => "info",
  }.freeze

  SEVERITY_ORDER = %w[bloquant majeur info].freeze

  def initialize(mode, target)
    @mode = mode
    @target = target
    @findings = []
    @notes = []
  end

  def add(category, location, detail = nil, severity: nil)
    @findings << Finding.new(category, location, detail, severity || SEVERITIES[category])
  end

  def note(msg) = @notes << msg

  # Tous les compteurs ci-dessous sont RECOMPTÉS depuis `@findings`, la liste
  # même qui est imprimée. Aucun n'est incrémenté au fil de l'eau : un total
  # tenu à part finit toujours par raconter autre chose que sa liste (un cahier
  # de recette a déjà annoncé 672 critères pour 111 lignes écrites).
  # Les seaux « autre » et « sans_gravite » existent pour que la somme des
  # parties soit TOUJOURS égale au total, y compris si une catégorie ou une
  # gravité est ajoutée plus tard sans être déclarée en tête de fichier.
  def counts
    h = CATEGORIES.keys.each_with_object({}) do |cat, acc|
      n = @findings.count { |f| f.category == cat }
      acc[cat] = n if n.positive?
    end
    other = @findings.count { |f| !CATEGORIES.key?(f.category) }
    h["autre"] = other if other.positive?
    h
  end

  def severity_counts
    h = SEVERITY_ORDER.each_with_object({}) do |sev, acc|
      n = @findings.count { |f| f.severity == sev }
      acc[sev] = n if n.positive?
    end
    # Les catégories historiques (static/crawl) n'ont pas de gravité : sans ce
    # seau, la somme de `by_severity` était inférieure au `total` sans le dire.
    rest = @findings.count { |f| !SEVERITY_ORDER.include?(f.severity) }
    h["sans_gravite"] = rest if rest.positive?
    h
  end

  def summary
    out = { "mode" => @mode, "target" => @target, "counts" => counts,
            "total" => @findings.size, "notes" => @notes }
    sev = severity_counts
    out["by_severity"] = sev unless sev.empty?
    # Garde-fou : si un jour un compteur cesse de dériver de la liste, le
    # rapport le dit lui-même au lieu de mentir en silence.
    checks = { "counts" => counts.values.sum, "by_severity" => sev.values.sum }
    divergent = checks.reject { |_, v| v == @findings.size }
    out["incoherence"] = divergent.map { |k, v| "#{k} totalise #{v} pour #{@findings.size} constat(s)" } if divergent.any?
    out
  end

  def print_text
    puts "facade_scan — mode #{@mode} — #{@target}"
    @notes.each { |n| puts "note: #{n}" }
    puts
    puts "Aucune façade détectée." if @findings.empty?
    # Catégories historiques (sans gravité) d'abord, puis groupées par gravité.
    print_categories(CATEGORIES.keys, nil)
    SEVERITY_ORDER.each do |sev|
      next unless @findings.any? { |f| f.severity == sev }
      puts "=== #{sev.upcase} ==="
      puts
      print_categories(CATEGORIES.keys, sev)
    end
    # Filet : un constat dont la catégorie ou la gravité n'est pas déclarée en
    # tête de fichier serait compté sans jamais être imprimé. Il l'est ici.
    leftovers = @findings.reject do |f|
      CATEGORIES.key?(f.category) && (f.severity.nil? || SEVERITY_ORDER.include?(f.severity))
    end
    unless leftovers.empty?
      puts "## Autres constats (#{leftovers.size})"
      leftovers.first(CONFIG[:max_shown_per_category]).each do |f|
        puts "  [#{f.category}/#{f.severity.inspect}] #{f.location}#{f.detail ? "  #{f.detail}" : ''}"
      end
      puts
    end
    puts "Total : #{@findings.size} constat(s) — recompté sur la liste imprimée ci-dessus, pas tenu à part."
    summary["incoherence"]&.each { |m| puts "INCOHÉRENCE DE COMPTAGE : #{m}" }
  end

  private

  def print_categories(cats, severity)
    cats.each do |cat|
      items = @findings.select { |f| f.category == cat && f.severity == severity }
      next if items.empty?
      puts "## #{CATEGORIES[cat]} (#{items.size})"
      shown = items.first(CONFIG[:max_shown_per_category])
      shown.each do |f|
        line = "  #{f.location}"
        line += "  #{f.detail}" if f.detail
        puts line
      end
      rest = items.size - shown.size
      puts "  … et #{rest} de plus (voir le compte JSON)" if rest.positive?
      puts
    end
  end
end

# ---------------------------------------------------------------------------
# Mode static
# ---------------------------------------------------------------------------
class StaticScanner
  def initialize(app_dir, report, boot: true)
    @app_dir = File.expand_path(app_dir)
    @report = report
    @boot = boot
  end

  def run
    views = view_files
    if views.empty?
      @report.note("aucune vue ERB à scanner sous app/views (hors #{CONFIG[:excluded_view_dirs].join(', ')})")
      return
    end
    controllers = stimulus_controllers
    route_helpers = known_route_helpers
    @view_locals = collect_view_locals(views)
    views.each { |path| scan_view(path, controllers, route_helpers) }
  end

  # Identifiants *_path/*_url qui sont en réalité des variables locales de vue
  # (assignation ERB `event_path = ...` ou local de partial `cta_path:`) :
  # à ne pas confondre avec des helpers de route.
  def collect_view_locals(views)
    locals = Set.new
    views.each do |path|
      src = File.read(path)
      src.scan(/\b(\w+_(?:path|url))\s*=(?![=>~])/) { |m| locals << m[0] }
      src.scan(/\b(\w+_(?:path|url)):(?!:)/)        { |m| locals << m[0] }
      src.scan(/:(\w+_(?:path|url))\s*=>/)          { |m| locals << m[0] }
    end
    locals
  end

  private

  def rel(path) = path.sub("#{@app_dir}/", "")

  def view_files
    base = File.join(@app_dir, "app/views")
    return [] unless Dir.exist?(base)
    excluded = CONFIG[:excluded_view_dirs].map { |d| File.join(base, d) + "/" }
    Dir.glob(File.join(base, CONFIG[:view_glob])).sort.reject do |f|
      excluded.any? { |ex| f.start_with?(ex) }
    end
  end

  # --- Stimulus -----------------------------------------------------------
  def stimulus_controllers
    base = File.join(@app_dir, "app/javascript/controllers")
    ids = Set.new
    Dir.glob(File.join(base, "**/*_controller.js")).each do |f|
      id = f.sub("#{base}/", "").sub(/_controller\.js\z/, "")
      ids << id.gsub("/", "--").tr("_", "-")
    end
    @report.note("aucun controller Stimulus trouvé sous app/javascript/controllers") if ids.empty? && Dir.exist?(base)
    ids
  end

  # --- Routes -------------------------------------------------------------
  def known_route_helpers
    helpers = Set.new(CONFIG[:helper_allowlist])
    # Helpers maison (app/helpers) qui finissent en _path/_url.
    Dir.glob(File.join(@app_dir, "app/helpers/**/*.rb")).each do |f|
      File.read(f).scan(/def\s+(\w+_(?:path|url))\b/) { |m| helpers << m[0] }
    end
    booted = @boot && helpers_from_rails_routes(helpers)
    if booted
      @report.note("routes résolues via `bin/rails routes`")
      @route_mode = :exact
    else
      @report.note("`bin/rails routes` indisponible : heuristique sur config/routes.rb (moins fiable)")
      @route_mode = :heuristic
      @route_words = route_words_from_routes_rb
    end
    helpers
  end

  def helpers_from_rails_routes(helpers)
    out = Src.rails_routes(@app_dir).to_s
    prefixes = out.scan(/^\s*([a-z]\w*)\s+(?:GET|POST|PATCH|PUT|DELETE)\s/).flatten
    return false if prefixes.empty?
    prefixes.each { |p| helpers << "#{p}_path" << "#{p}_url" }
    helpers << "root_path" << "root_url" if out.match?(/^\s*root\s/)
    true
  end

  # Fallback : mots plausibles extraits de config/routes.rb. Un helper est
  # jugé plausible si chacun de ses mots apparaît dans les routes (avec
  # singulier/pluriel naïfs). Beaucoup moins fiable que bin/rails routes.
  def route_words_from_routes_rb
    words = Set.new(%w[new edit root rails turbo blob representation service
                       disposition redirect proxy conductor mailbox])
    file = File.join(@app_dir, "config/routes.rb")
    return words unless File.exist?(file)
    src = File.read(file)
    # devise_for engendre des helpers dynamiques (session_path, new_registration_path…).
    if src.include?("devise_for")
      %w[session registration password confirmation unlock omniauth authorize
         sign in out up user cancel resend verify].each { |w| words.merge(word_variants(w)) }
    end
    src.scan(/[:"'\/]([a-z][a-z0-9_]*)/) do |m|
      token = m[0]
      [token, *token.split("_")].each do |w|
        words.merge(word_variants(w))
      end
    end
    words
  end

  # Variantes singulier/pluriel naïves : taxes → taxe, tax ; companies → company.
  def word_variants(w)
    v = [w, "#{w}s"]
    v << w.sub(/ies\z/, "y") if w.end_with?("ies")
    if w.end_with?("s") && !w.end_with?("ss")
      v << w.sub(/s\z/, "")
      v << w.sub(/es\z/, "") if w.end_with?("es")
    end
    v
  end

  def route_helper_known?(helper, helpers)
    return true if helpers.include?(helper)
    return false if @route_mode == :exact
    # Heuristique : tous les mots du helper existent dans routes.rb.
    body = helper.sub(/_(path|url)\z/, "")
    body.split("_").all? { |w| @route_words.include?(w) }
  end

  # --- Scan d'une vue -----------------------------------------------------
  def scan_view(path, controllers, route_helpers)
    raw = File.read(path)
    # Version sans commentaires ERB (un helper cité dans un <%# %> n'est pas
    # un appel), sauts de ligne conservés pour les numéros de ligne.
    raw = raw.gsub(/<%#.*?%>/m) { |m| "\n" * m.count("\n") }
    # Version "placeholder" : les tags ERB deviennent des marqueurs, en
    # conservant les sauts de ligne (les numéros de ligne restent justes).
    ph = raw.gsub(/<%(=?).*?%>/m) do
      marker = Regexp.last_match(1) == "=" ? ERB_EXPR : ERB_STMT
      marker + "\n" * Regexp.last_match(0).count("\n")
    end

    check_controls_without_name(path, ph)
    check_stimulus(path, raw, ph, controllers)
    check_inert_data_action(path, ph)
    check_dead_links(path, raw, ph)
    check_hardcoded_numbers(path, ph)
    check_route_helpers(path, raw, route_helpers)
  end

  def each_tag(content, names)
    content.scan(/<(#{names})\b#{TAG_BODY}>/im) do
      m = Regexp.last_match
      line = content[0...m.begin(0)].count("\n") + 1
      yield m[0], line
    end
  end

  def attrs_of(tag)
    tag.scan(/([\w-]+)\s*=\s*("[^"]*"|'[^']*')/).to_h { |k, v| [k.downcase, v[1..-2]] }
  end

  def check_controls_without_name(path, ph)
    each_tag(ph, "input|select|textarea") do |tag, line|
      next if tag.include?(ERB_EXPR)                 # attrs dynamiques : indécidable
      attrs = attrs_of(tag)
      next if CONFIG[:ignored_input_types].include?(attrs["type"].to_s.downcase)
      next if attrs.key?("name") || attrs.key?("disabled") || tag.match?(/\bdisabled\b/i)
      next if attrs.key?("data-action")              # branché côté Stimulus
      @report.add("control_without_name", "#{rel(path)}:#{line}", snippet(tag))
    end
  end

  def check_stimulus(path, raw, ph, controllers)
    return if controllers.nil?
    seen = {}
    record = lambda do |id, line, origin|
      id = id.strip
      return if id.empty? || id.include?("") || id.include?("<%")
      return if controllers.include?(id) || seen["#{id}:#{line}"]
      seen["#{id}:#{line}"] = true
      @report.add("missing_stimulus", "#{rel(path)}:#{line}", "controller \"#{id}\" (#{origin})")
    end
    scan_with_lines(ph, /data-controller\s*=\s*["']([^"']*)["']/i) do |val, line|
      val.split(/\s+/).each { |id| record.call(id, line, "data-controller") }
    end
    scan_with_lines(ph, /data-action\s*=\s*["']([^"']*)["']/i) do |val, line|
      stimulus_action_targets(val).each { |id| record.call(id, line, "data-action") }
    end
    # Côté Ruby : data: { controller: "...", action: "..." }
    scan_with_lines(raw, /\bcontroller(?::|\s*=>)\s*["']([\w\s-]+)["']/) do |val, line|
      val.split(/\s+/).each { |id| record.call(id, line, "data: controller") }
    end
    scan_with_lines(raw, /\baction(?::|\s*=>)\s*["']([^"']*#[^"']*)["']/) do |val, line|
      stimulus_action_targets(val).each { |id| record.call(id, line, "data: action") }
    end
  end

  def stimulus_action_targets(value)
    value.split(/\s+/).filter_map do |token|
      next unless token.include?("#")
      part = token.include?("->") ? token.split("->").last : token
      part.split("#").first
    end
  end

  def check_inert_data_action(path, ph)
    each_tag(ph, "div|span|p|li|td|th|tr|section|article|ul|i") do |tag, line|
      attrs = attrs_of(tag)
      action = attrs["data-action"]
      next if action.nil? || action.include?("")
      inert = action.split(/\s+/).reject { |t| t.include?("->") }
      next if inert.empty?
      tagname = tag[/\A<(\w+)/, 1]
      @report.add("inert_data_action", "#{rel(path)}:#{line}",
                  "<#{tagname} data-action=\"#{action}\"> : pas d'événement par défaut sur <#{tagname}>")
    end
  end

  def check_dead_links(path, raw, ph)
    each_tag(ph, "a") do |tag, line|
      attrs = attrs_of(tag)
      href = attrs["href"]
      next unless href == "#" || href == ""
      next if attrs.key?("data-action") || attrs.key?("data-controller")
      @report.add("dead_link", "#{rel(path)}:#{line}", snippet(tag))
    end
    scan_with_lines(raw, /link_to\b[^\n]*?,\s*["'](#)["']/) do |_val, line|
      @report.add("dead_link", "#{rel(path)}:#{line}", "link_to ..., \"#\"")
    end
  end

  def check_hardcoded_numbers(path, ph)
    text = ph.dup
    # Vider scripts, styles et commentaires HTML en gardant les sauts de ligne.
    [%r{<script\b.*?</script>}im, %r{<style\b.*?</style>}im, /<!--.*?-->/m,
     %r{</?[a-zA-Z!]#{TAG_BODY}>}m].each do |re|
      text = text.gsub(re) { |m| "\n" * m.count("\n") }
    end
    text.each_line.with_index(1) do |line_text, lineno|
      next if line_text.include?(ERB_EXPR)  # interpolation sur la ligne : ok
      next if CONFIG[:numeric_line_allowlist].any? { |re| line_text.match?(re) }
      nums = []
      line_text.scan(/\b\d{2,}\b/) do
        m = Regexp.last_match
        next if CONFIG[:numeric_value_allowlist].any? { |re| m[0].match?(re) }
        next if m.post_match.match?(CONFIG[:numeric_unit_after])
        next if m.pre_match.match?(CONFIG[:numeric_context_before])
        nums << m[0]
      end
      next if nums.empty?
      @report.add("hardcoded_number", "#{rel(path)}:#{lineno}",
                  "#{nums.uniq.join(', ')} dans « #{line_text.strip[0, 60]} »")
    end
  end

  def check_route_helpers(path, raw, helpers)
    scan_with_lines(raw, /(?<![.\w:'"\[`])([a-z]\w*_(?:path|url))\b(?![:'"\]`])/) do |helper, line|
      next if @view_locals.include?(helper)          # variable locale, pas un helper
      next if route_helper_known?(helper, helpers)
      @report.add("unknown_route_helper", "#{rel(path)}:#{line}", helper)
    end
  end

  def scan_with_lines(content, regex)
    content.scan(regex) do
      m = Regexp.last_match
      yield m[1], content[0...m.begin(0)].count("\n") + 1
    end
  end

  def snippet(tag) = tag.gsub(/\s+/, " ")[0, 90]
end

# ---------------------------------------------------------------------------
# Mode crawl
# ---------------------------------------------------------------------------
class CrawlScanner
  def initialize(base_url, report, cookies: [], max_pages: CONFIG[:crawl_max_pages])
    require "nokogiri"
    @base = URI(base_url)
    @report = report
    @cookie = cookies.join("; ")
    @max_pages = max_pages
  end

  def run
    queue = [[@base.to_s, "(départ)"]]
    visited = Set.new
    @seen_bodies = Set.new
    while (entry = queue.shift)
      url, referrer = entry
      break if visited.size >= @max_pages
      next if visited.include?(url)
      visited << url
      status, body, effective = fetch(url)
      if status.nil?
        @report.add("http_error", url, "injoignable (depuis #{referrer})")
        next
      end
      @report.add("http_error", url, "HTTP #{status} (depuis #{referrer})") if status >= 400
      next unless status < 400 && body && html?(body)
      doc = Nokogiri::HTML(body)
      # Même contenu déjà audité sous une autre URL (/ vs /index) : liens
      # quand même suivis, findings pas dupliqués.
      fresh = @seen_bodies.add?(Digest::MD5.hexdigest(body))
      audit_page(effective || url, doc) if fresh
      extract_links(effective || url, doc).each do |link|
        queue << [link, url] unless visited.include?(link)
      end
    end
    @report.note("#{visited.size} page(s) visitée(s), plafond #{@max_pages}")
  end

  private

  def html?(body) = body.lstrip.start_with?("<")

  def fetch(url, redirects = 5)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: 10, read_timeout: 15) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Cookie"] = @cookie unless @cookie.empty?
      http.request(req)
    end
    if res.is_a?(Net::HTTPRedirection) && redirects.positive? && res["location"]
      loc = URI.join(url, res["location"]).to_s
      return [res.code.to_i, nil, nil] unless internal?(loc)
      return fetch(loc, redirects - 1)
    end
    [res.code.to_i, res.body, url]
  rescue StandardError
    [nil, nil, nil]
  end

  def internal?(url)
    u = URI(url)
    u.host == @base.host && (u.port || u.default_port) == (@base.port || @base.default_port)
  rescue StandardError
    false
  end

  def extract_links(page_url, doc)
    doc.css("a[href]").filter_map do |a|
      href = a["href"].to_s.strip
      next if href.empty? || href.start_with?("#")
      next if CONFIG[:crawl_skip_href].any? { |re| href.match?(re) }
      next if a["data-turbo-method"] || a["data-method"]  # jamais de GET destructif
      abs = URI.join(page_url, href).to_s.split("#").first rescue next
      abs if internal?(abs)
    end.uniq
  end

  def audit_page(url, doc)
    doc.css("input, select, textarea").each do |el|
      next if CONFIG[:ignored_input_types].include?(el["type"].to_s.downcase)
      next if el["name"] && !el["name"].empty?
      next if el["disabled"] || el["data-action"]
      @report.add("control_without_name", url, "<#{el.name} type=#{el['type'] || '?'} id=#{el['id'] || '-'}>")
    end
    doc.css("form").each do |form|
      next if form["action"] && !form["action"].empty?
      @report.add("form_without_action", url, "<form id=#{form['id'] || '-'} class=#{(form['class'] || '-')[0, 40]}>")
    end
    doc.css("button").each do |btn|
      next if btn.ancestors("form").any? || btn["form"]
      next if btn["data-action"] || btn["onclick"] || btn["popovertarget"] || btn["commandfor"]
      next if btn.ancestors("details").any?
      @report.add("button_not_wired", url, "<button> « #{btn.text.strip[0, 40]} »")
    end
    doc.css("a").each do |a|
      href = a["href"]
      next unless href == "#" || href == ""
      next if a["data-action"] || a["data-controller"]
      @report.add("dead_link", url, "« #{a.text.strip[0, 40]} »")
    end
  end
end

# ---------------------------------------------------------------------------
# Boîte à outils commune aux modes reachability / readwrite
# ---------------------------------------------------------------------------
module Src
  module_function

  # Commentaires Ruby en début de ligne (les annotations de schéma en tête de
  # modèle listent TOUTES les colonnes : sans ce nettoyage, tout est « lu »).
  def strip_ruby_comments(src)
    src = src.gsub(/^=begin.*?^=end/m) { |m| "\n" * m.count("\n") }
    src.gsub(/^([ \t]*)#.*$/) { Regexp.last_match(1) }
  end

  def strip_erb_comments(src)
    src.gsub(/<%#.*?%>/m) { |m| "\n" * m.count("\n") }
       .gsub(/<!--.*?-->/m) { |m| "\n" * m.count("\n") }
  end

  # Un `# …` en début de ligne DANS un `<% %>` est un commentaire Ruby, pas du
  # HTML. Sans ce nettoyage, la note qui explique pourquoi une façade a été
  # retirée fait croire que la façade est toujours là (constaté : le commentaire
  # « users.last_active_at n'est écrit que par les seeds » relevé comme lecture).
  def strip_erb_ruby_comments(src)
    src.gsub(/<%[^%]*(?:%(?!>)[^%]*)*%>/m) do |tag|
      tag.gsub(/^([ \t]*)#[^\n]*$/) { Regexp.last_match(1) }
    end
  end

  def clean(path)
    src = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
    src = strip_erb_ruby_comments(strip_erb_comments(src)) if path.end_with?(".erb")
    src = strip_ruby_comments(src) if path.end_with?(".rb", ".rake")
    src
  rescue StandardError
    ""
  end

  def line_of(src, index) = src[0...index].count("\n") + 1

  # `bin/rails routes` dans l'app cible. L'environnement du process courant est
  # nettoyé : lancé depuis un autre Ruby (rbenv, bundler), l'app hériterait de la
  # mauvaise version et ne booterait pas alors qu'elle boote très bien à la main.
  def rails_routes(app_dir)
    return nil unless File.executable?(File.join(app_dir, "bin/rails"))
    env = { "RUBYOPT" => nil, "RUBYLIB" => nil, "GEM_HOME" => nil, "GEM_PATH" => nil,
            "BUNDLE_GEMFILE" => nil, "BUNDLE_PATH" => nil, "BUNDLE_BIN_PATH" => nil,
            "BUNDLER_VERSION" => nil, "RBENV_VERSION" => nil, "RBENV_DIR" => nil }
    env["PATH"] = ENV["RBENV_ORIG_PATH"] if ENV["RBENV_ORIG_PATH"]
    out = IO.popen(env, [ "timeout", CONFIG[:rails_routes_timeout].to_s, "bin/rails", "routes" ],
                   chdir: app_dir, err: File::NULL, &:read)
    out.to_s.strip.empty? ? nil : out
  rescue StandardError
    nil
  end

  def pluralize(word)
    return word if word.empty?
    case word
    when /y\z/  then word.sub(/y\z/, "ies")
    when /(s|x|z|ch|sh)\z/ then "#{word}es"
    else "#{word}s"
    end
  end

  def singularize(word)
    case word
    when /ies\z/ then word.sub(/ies\z/, "y")
    when /(s|x|z|ch|sh)es\z/ then word.sub(/es\z/, "")
    when /ss\z/ then word
    when /s\z/ then word.sub(/s\z/, "")
    else word
    end
  end

  def underscore(word)
    word.gsub("::", "/").gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  end

  # Portée d'une expression : du début du geste à la fin du tag ERB, ou de la
  # ligne logique en Ruby pur. Assez large pour attraper les options sur
  # plusieurs lignes, assez courte pour ne pas avaler la suite du fichier.
  def expression_span(src, start, erb:, max: 700)
    limit = [start + max, src.length].min
    if erb
      stop = src.index("%>", start)
      stop = stop ? [stop + 2, limit].min : limit
    else
      stop = start
      depth = 0
      # 24 lignes, pas 8 : `solicitations.new(` ouvrait un hash de 9 lignes et
      # les 3 dernières colonnes tombaient hors fenêtre, donc « jamais écrites ».
      # La vraie borne reste `max` (en caractères), pas le nombre de lignes.
      24.times do
        eol = src.index("\n", stop) || src.length
        chunk = src[stop...eol]
        depth += chunk.count("(") - chunk.count(")")
        stop = eol + 1
        break if depth <= 0 && !chunk.rstrip.end_with?(",")
        break if stop >= limit
      end
      stop = [stop, limit].min
    end
    src[start...stop].to_s
  end
end

Route = Struct.new(:prefix, :verb, :path, :controller, :action, :source) do
  def endpoint = controller && action ? "#{controller}##{action}" : "(#{source})"
  def to_s = "#{verb} #{path}"
end

# ---------------------------------------------------------------------------
# Chargement des routes : `bin/rails routes` sinon lecture de config/routes.rb
# ---------------------------------------------------------------------------
class RouteLoader
  RESOURCE_ACTIONS = {
    "index"   => [ "GET",    :collection ],
    "create"  => [ "POST",   :collection ],
    "new"     => [ "GET",    :new ],
    "edit"    => [ "GET",    :edit ],
    "show"    => [ "GET",    :member ],
    "update"  => [ "PATCH",  :member ],
    "destroy" => [ "DELETE", :member ],
  }.freeze

  attr_reader :source

  def initialize(app_dir, report, boot: true)
    @app_dir = app_dir
    @report = report
    @boot = boot
  end

  def routes
    @routes ||= begin
      list = @boot ? from_rails_routes : nil
      if list && !list.empty?
        @source = :rails
        @report.note("routes résolues via `bin/rails routes` (#{list.size})")
      else
        list = from_routes_rb
        @source = :routes_rb
        @report.note("`bin/rails routes` indisponible : lecture directe de config/routes.rb (#{list.size} routes, fidélité moindre)")
      end
      list
    end
  end

  private

  def from_rails_routes
    out = Src.rails_routes(@app_dir)
    out && parse_rails_routes(out)
  end

  def parse_rails_routes(out)
    list = []
    last_prefix = nil
    last_path = nil
    out.each_line do |line|
      break if line.start_with?("Routes for ")   # moteurs montés : hors périmètre
      m = line.match(/^\s*([a-z0-9_]*)\s+((?:GET|POST|PATCH|PUT|DELETE|HEAD|OPTIONS)(?:\|[A-Z]+)*)\s+(\S+)\s+(.+?)\s*$/)
      next unless m
      prefix, verbs, path, endpoint = m.captures
      path = path.sub(/\(\.:format\)\z/, "")
      target = endpoint.split(/\s+/).first.to_s
      ctrl, action = target.match(/\A([\w\/]+)#(\w+)\z/)&.captures
      # `rails routes` n'imprime le préfixe que sur la première ligne d'un
      # groupe : les verbes suivants du même chemin le partagent.
      if prefix.empty?
        prefix = (path == last_path ? last_prefix : nil)
      else
        last_prefix = prefix
        last_path = path
      end
      verbs.split("|").each do |verb|
        list << Route.new(prefix, verb, path, ctrl, action, ctrl ? :rails : :rails_special)
      end
    end
    list
  end

  # --- Repli : lecture de config/routes.rb ---------------------------------
  # Sous-ensemble du DSL : namespace, scope "chemin", resources/resource (avec
  # only/except/param/controller), member/collection, verbes explicites, root.
  def from_routes_rb
    file = File.join(@app_dir, "config/routes.rb")
    return [] unless File.exist?(file)
    src = Src.strip_ruby_comments(File.read(file))
    @list = []
    @stack = []            # contextes ouverts
    src.each_line { |line| parse_routes_line(line.strip) }
    @list
  end

  def parse_routes_line(line)
    return if line.empty?
    if line == "end"
      @stack.pop
      return
    end
    opens = line.end_with?(" do") || line.end_with?("do")

    case line
    when /\Anamespace\s+:(\w+)/
      push(kind: :namespace, name: Regexp.last_match(1), opens: opens)
    when /\Ascope\s+["'](\w+)["']/
      push(kind: :scope_path, name: Regexp.last_match(1), opens: opens)
    when /\A(?:scope|constraints|concern|authenticate|authenticated|direct|resolve)\b/
      push(kind: :ignore, name: nil, opens: opens)
    when /\Aresources?\s+:(\w+)/
      declare_resource(line, opens)
    when /\A(member|collection)\b/
      push(kind: Regexp.last_match(1).to_sym, name: nil, opens: opens)
    when /\Aroot\b/
      target = line[/(?:to:\s*)?["']([\w\/]+#\w+)["']/, 1]
      ctrl, action = target.to_s.split("#")
      add_route("GET", current_path, name_prefix + "root", ctrl && namespaced(ctrl), action)
    when /\A(get|post|patch|put|delete)\b/
      declare_verb(line)
      push(kind: :ignore, name: nil, opens: opens) if opens
    when /\Adevise_for|\Amount\b/
      nil                                             # allowlistés de toute façon
    else
      push(kind: :ignore, name: nil, opens: opens) if opens
    end
  end

  def push(kind:, name:, opens:, extra: {})
    @stack << { kind: kind, name: name }.merge(extra) if opens
  end

  def declare_resource(line, opens)
    plural = line[/\Aresources?\s+:(\w+)/, 1]
    singular_route = line.start_with?("resource ")
    only = line[/only:\s*\[([^\]]*)\]/, 1]&.scan(/\w+/)
    only ||= [ line[/only:\s*:(\w+)/, 1] ].compact.presence_or_nil
    except = line[/except:\s*\[([^\]]*)\]/, 1]&.scan(/\w+/) || []
    ctrl_override = line[/controller:\s*["':]?([\w\/]+)["']?/, 1]

    actions = RESOURCE_ACTIONS.keys
    actions -= %w[index] if singular_route
    actions = actions & only if only
    actions -= except
    singular = singular_route ? plural : Src.singularize(plural)
    controller = namespaced(ctrl_override || plural)

    actions.each do |action|
      verb, kind = RESOURCE_ACTIONS[action]
      add_route(verb, resource_path(plural, singular_route, kind),
                resource_prefix(plural, singular, kind), controller, action)
      add_route("PUT", resource_path(plural, singular_route, kind),
                resource_prefix(plural, singular, kind), controller, action) if action == "update"
    end
    push(kind: :resource, name: plural, opens: opens,
         extra: { singular: singular, controller: controller })
  end

  def declare_verb(line)
    verb = line[/\A(\w+)/, 1].upcase
    ctx = @stack.last && %i[member collection].include?(@stack.last[:kind]) ? @stack.last[:kind] : nil
    ctx ||= line[/on:\s*:(\w+)/, 1]&.to_sym
    name = line[/\A\w+\s+:(\w+)/, 1] || line[/\A\w+\s+["']([\w\/:\-]+)["']/, 1]
    return unless name
    target = line[/(?:to:\s*|=>\s*)["']([\w\/]+#\w+)["']/, 1]
    as = line[/as:\s*:?["']?(\w+)/, 1]

    if ctx
      res = @stack.reverse.find { |c| c[:kind] == :resource }
      return unless res
      base = ctx == :member ? res[:singular] : res[:name]
      prefix = "#{name}_#{name_prefix(skip_last_resource: true)}#{base}"
      path = ctx == :member ? "#{current_path(skip_last_resource: true)}/#{res[:name]}/:id/#{name}" :
                              "#{current_path(skip_last_resource: true)}/#{res[:name]}/#{name}"
      ctrl = res[:controller]
      action = name
    else
      prefix = as ? name_prefix + as : name_prefix + name.gsub(/[\/:]/, "_").squeeze("_")
      path = "#{current_path}/#{name}"
      ctrl, action = target.to_s.split("#")
      ctrl = ctrl ? namespaced(ctrl) : nil
    end
    add_route(verb, path, prefix, ctrl, action)
  end

  def add_route(verb, path, prefix, controller, action)
    @list << Route.new(prefix, verb, path.sub(%r{//+}, "/"), controller, action, :routes_rb)
  end

  # Contexte courant -------------------------------------------------------
  def namespaces = @stack.select { |c| %i[namespace scope_path].include?(c[:kind]) }.map { |c| c[:name] }

  def parent_resources(skip_last: false)
    res = @stack.select { |c| c[:kind] == :resource }
    res = res[0...-1] if skip_last && !res.empty?
    res
  end

  def name_prefix(skip_last_resource: false)
    parts = namespaces + parent_resources(skip_last: skip_last_resource).map { |r| r[:singular] }
    parts.empty? ? "" : parts.join("_") + "_"
  end

  def current_path(skip_last_resource: false)
    parts = namespaces.map { |n| "/#{n}" }
    parent_resources(skip_last: skip_last_resource).each { |r| parts << "/#{r[:name]}/:#{r[:singular]}_id" }
    parts.join
  end

  def namespaced(ctrl)
    ns = namespaces
    ctrl.include?("/") || ns.empty? ? ctrl : (ns + [ ctrl ]).join("/")
  end

  def resource_path(plural, singular_route, kind)
    base = "#{current_path}/#{plural}"
    case kind
    when :member then singular_route ? base : "#{base}/:id"
    when :new    then "#{base}/new"
    when :edit   then singular_route ? "#{base}/edit" : "#{base}/:id/edit"
    else base
    end
  end

  def resource_prefix(plural, singular, kind)
    case kind
    when :member then "#{name_prefix}#{singular}"
    when :new    then "new_#{name_prefix}#{singular}"
    when :edit   then "edit_#{name_prefix}#{singular}"
    else "#{name_prefix}#{plural}"
    end
  end
end

class Array
  def presence_or_nil = empty? ? nil : self
end

# ---------------------------------------------------------------------------
# Index des gestes d'interface (ce que l'utilisateur peut réellement déclencher)
# ---------------------------------------------------------------------------
class GestureIndex
  GESTURES = {
    "form_with" => %w[POST PATCH PUT],
    "form_for"  => %w[POST PATCH PUT],
    "form_tag"  => %w[POST],
    "button_to" => %w[POST],
    "link_to"   => %w[GET],
    "redirect_to" => %w[GET],
  }.freeze

  attr_reader :helpers, :literals, :js_helpers, :js_literals

  def initialize(app_dir, files)
    @app_dir = app_dir
    @files = files
    @helpers = Hash.new { |h, k| h[k] = Hash.new { |g, v| g[v] = [] } } # base => verb => [loc]
    @literals = []                                                       # [path, verb, loc]
    @js_helpers = Set.new
    @js_literals = Set.new
    @mentions = Set.new                                                  # tout helper cité, quel que soit le contexte
    build
  end

  def reaches_helper?(prefix, verb)
    return false if prefix.nil?
    verbs = @helpers[prefix]
    return false if verbs.empty?
    verbs.key?(verb) || (%w[PATCH PUT].include?(verb) && (verbs.key?("PATCH") || verbs.key?("PUT")))
  end

  def helper_locations(prefix, verb)
    (@helpers[prefix][verb] + (%w[PATCH PUT].include?(verb) ? @helpers[prefix]["PATCH"] + @helpers[prefix]["PUT"] : [])).uniq
  end

  # Pour une page GET, toute citation du helper suffit : un tableau de liens
  # construit dans un helper ou un partial reste un chemin d'accès réel.
  def mentions_helper?(prefix) = !prefix.nil? && (@mentions.include?(prefix) || !@helpers[prefix].empty?)

  def reaches_literal?(route_path, verb)
    re = path_regex(route_path)
    @literals.any? { |p, v, _| v == verb && p.match?(re) } ||
      (%w[PATCH PUT].include?(verb) && @literals.any? { |p, v, _| %w[PATCH PUT].include?(v) && p.match?(re) })
  end

  def js_reaches?(route_path)
    re = path_regex(route_path)
    @js_literals.any? { |p| p.match?(re) }
  end

  def path_regex(route_path)
    body = route_path.split("/").map { |seg| seg.start_with?(":") || seg.start_with?("*") ? "[^/]+" : Regexp.escape(seg) }.join("/")
    /\A#{body}\z/
  end

  private

  def rel(path) = path.sub("#{@app_dir}/", "")

  def build
    @files.each do |path|
      src = Src.clean(path)
      next if src.empty?
      src.scan(/(?<![.\w:'"\[`])(\w+_(?:path|url))\b/) { @mentions << base(Regexp.last_match(1)) }
      erb = path.end_with?(".erb")
      if path.end_with?(".js", ".ts")
        scan_js(path, src)
      else
        scan_ruby_gestures(path, src, erb)
        scan_formaction(path, src)
        scan_html_gestures(path, src) if erb
        scan_js_wiring(path, src)
      end
    end
  end

  def scan_ruby_gestures(path, src, erb)
    src.scan(/\b(#{GESTURES.keys.join('|')})\b/) do
      m = Regexp.last_match
      helper = m[1]
      span = Src.expression_span(src, m.begin(0), erb: erb)
      line = Src.line_of(src, m.begin(0))
      loc = "#{rel(path)}:#{line}"
      verbs = explicit_verbs(span) || GESTURES[helper]
      targets(span).each { |t| record(t, verbs, loc) }
      model_targets(span).each { |t, vs| record(t, verbs & vs, loc) } if helper.start_with?("form")
    end
  end

  # `<button type="submit" formaction="<%= x_path %>" formmethod="post">` :
  # un vrai geste, invisible pour qui ne cherche que form_with / button_to.
  def scan_formaction(path, src)
    src.scan(/formaction\s*=\s*["']([^"']*)["']/i) do
      m = Regexp.last_match
      value = m[1]
      window = src[[ m.begin(0) - 200, 0 ].max, 500].to_s
      verb = (window[/formmethod\s*=\s*["'](\w+)["']/i, 1] || "post").upcase
      loc = "#{rel(path)}:#{Src.line_of(src, m.begin(0))}"
      value.scan(/(\w+_(?:path|url))\b/) { |h| record([ :helper, base(h[0]) ], [ verb ], loc) }
      record([ :literal, value.split("?").first ], [ verb ], loc) if value.start_with?("/")
    end
  end

  # `data-…-url-value="<%= x_path %>"` ou `data: { url: x_path }` : le geste
  # part du JS, on ne peut pas prouver le verbe — on le note comme tel.
  def scan_js_wiring(path, src)
    # Le contenu capture est fige AVANT les scans imbriques : ceux-ci ecrasent
    # Regexp.last_match, et le lire apres donnait nil.scan (le scanner levait,
    # l'exception etait avalee et le rapport annoncait « aucune facade »).
    src.scan(/data-[\w-]*(?:url|path|src|endpoint)[\w-]*\s*=\s*"([^"]*)"/i) do |caps|
      val = Array(caps).first.to_s
      val.scan(/(\w+_(?:path|url))\b/) { |h| @js_helpers << base(h[0]) }
      val.scan(%r{\A(/[\w\-/.]*)}) { |p| @js_literals << p[0] }
    end
    src.scan(/\bdata:\s*\{([^{}]*)\}/m) do |caps|
      val = Array(caps).first.to_s
      val.scan(/\b(?:url|path|src|endpoint)\w*:\s*[^,}]*?(\w+_(?:path|url))\b/) { |h| @js_helpers << base(h[0]) }
    end
  end

  def scan_js(path, src)
    src.scan(/\b(?:fetch|axios(?:\.\w+)?)\s*\(/) do
      m = Regexp.last_match
      span = src[m.begin(0), 400].to_s
      verb = span[/method:\s*["'](\w+)["']/, 1]&.upcase || "GET"
      span.scan(/["'`](\/[\w\-\/.]*)/) { |p| @js_literals << p[0] }
      @js_literals << "*" if verb # présence d'appels JS : signal générique
    end
    src.scan(/(\w+_(?:path|url))\b/) { |h| @js_helpers << base(h[0]) }
  end

  def scan_html_gestures(path, src)
    src.scan(/<a\b#{TAG_BODY}>/im) do
      m = Regexp.last_match
      tag = m[0]
      href = tag[/href\s*=\s*"([^"]*)"/, 1] || tag[/href\s*=\s*'([^']*)'/, 1]
      next if href.nil? || href.empty? || href.start_with?("#", "mailto:", "tel:", "javascript:")
      verb = (tag[/data-turbo-method\s*=\s*["'](\w+)["']/, 1] || "get").upcase
      @literals << [ href.split("?").first, verb, "#{rel(path)}:#{Src.line_of(src, m.begin(0))}" ] if href.start_with?("/")
    end
    src.scan(/<form\b#{TAG_BODY}>/im) do
      m = Regexp.last_match
      tag = m[0]
      action = tag[/action\s*=\s*"([^"]*)"/, 1]
      next if action.nil? || action.empty? || !action.start_with?("/")
      verb = (tag[/method\s*=\s*["'](\w+)["']/, 1] || "post").upcase
      @literals << [ action.split("?").first, verb, "#{rel(path)}:#{Src.line_of(src, m.begin(0))}" ]
    end
  end

  # Le verbe peut être écrit en dur (`method: :delete`) ou calculé
  # (`method: credential ? :patch : :post`) : on relève TOUS les verbes cités
  # dans l'expression. Verbe illisible = on retombe sur le défaut du geste.
  def explicit_verbs(span)
    values = span.scan(/\b(?:turbo_)?method(?::|\s*=>)\s*([^,\n]*)/).flatten +
             span.scan(/data-turbo-method\s*=\s*["']([^"']*)["']/i).flatten
    return nil if values.empty?
    verbs = values.flat_map { |v| v.scan(/\b(get|post|patch|put|delete)\b/i) }.flatten.map(&:upcase).uniq
    verbs.empty? ? nil : verbs
  end

  def targets(span)
    out = []
    span.scan(/(?<![.\w:'"\[`])(\w+_(?:path|url))\b/) { |h| out << [ :helper, base(h[0]) ] }
    span.scan(/["'](\/[\w\-\/.]*)["']/) { |p| out << [ :literal, p[0] ] }
    out.uniq
  end

  # `form_with model: [ :app, @client ]` ne nomme aucun helper : on reconstitue
  # les préfixes candidats (création au pluriel, mise à jour au singulier).
  def model_targets(span)
    spec = span[/\bmodel:\s*(\[[^\]]*\]|@?[\w.]+)/, 1] || span[/\Aform_for[( ]\s*(\[[^\]]*\]|@?[\w.]+)/, 1]
    return [] if spec.nil?
    tokens = spec.tr("[]", "").split(",").map { |t| t.strip.sub(/\A[@:]/, "").split(".").first.to_s }
                 .reject { |t| t.empty? || t == "nil" }
    return [] if tokens.empty?
    last = Src.singularize(tokens.pop)
    parents = tokens.map { |t| Src.singularize(t) }
    stem = (parents + [ last ]).join("_")
    plural_stem = (parents + [ Src.pluralize(last) ]).join("_")
    [ [ [ :helper, plural_stem ], %w[POST] ], [ [ :helper, stem ], %w[PATCH PUT] ] ]
  end

  def record(target, verbs, loc)
    return if verbs.nil? || verbs.empty?
    kind, value = target
    verbs.each do |verb|
      if kind == :helper
        @helpers[value][verb] << loc
      else
        @literals << [ value, verb, loc ]
      end
    end
  end

  def base(helper) = helper.sub(/_(path|url)\z/, "")
end

# ---------------------------------------------------------------------------
# Mode reachability
# ---------------------------------------------------------------------------
class ReachabilityScanner
  def initialize(app_dir, report, boot: true, mockups: false)
    @app_dir = File.expand_path(app_dir)
    @report = report
    @boot = boot
    @mockups = mockups
  end

  def run
    routes = RouteLoader.new(@app_dir, @report, boot: @boot).routes
    routes = scope(routes)
    if routes.empty?
      @report.note("aucune route applicative à analyser")
      return
    end
    @report.note("#{routes.size} route(s) applicative(s) retenue(s) après allowlist")
    gestures = GestureIndex.new(@app_dir, gesture_files)
    @report.note("gestes relevés dans #{gesture_files.size} fichier(s) (#{@mockups ? 'app/views/mockups' : 'app/views hors mockups'})")

    missing = check_missing_actions(routes)
    js_controllers = js_wired_controllers(routes, gestures)
    check_writes(routes, gestures, missing, js_controllers)
    check_gets(routes, gestures, missing)
  end

  private

  def scope(routes)
    routes = routes.reject { |r| r.controller.nil? }               # redirect / mount : pas d'action
    routes = if @mockups
      mock = routes.select { |r| r.controller.start_with?("mockups/") }
      mock.empty? ? routes : mock
    else
      routes.reject { |r| r.controller.start_with?("mockups/") }
    end
    routes.reject do |r|
      CONFIG[:reach_skip_controller].any? { |re| r.controller.match?(re) } ||
        CONFIG[:reach_skip_path].any? { |re| r.path.match?(re) }
    end.uniq { |r| [ r.verb, r.path, r.controller, r.action ] }
  end

  def gesture_files
    @gesture_files ||= begin
      dirs = CONFIG[:reach_gesture_dirs].map { |d| File.join(@app_dir, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**/*.{erb,rb,js,html}")) }
      base = File.join(@app_dir, "app/views/mockups")
      if @mockups
        files.select { |f| f.start_with?(base) } .presence_or_nil ||
          Dir.glob(File.join(@app_dir, "app/views/**/*.erb"))
      else
        files.reject { |f| f.start_with?(base) || f.include?("/controllers/mockups/") }
      end.sort
    end
  end

  # --- Route déclarée, action absente -------------------------------------
  def check_missing_actions(routes)
    missing = Set.new
    routes.each do |route|
      next if route.action.nil?
      next if action_defined?(route.controller, route.action)
      missing << [ route.controller, route.action ]
      @report.add("route_without_action", "#{route.verb} #{route.path}",
                  "#{route.controller}##{route.action} : ni méthode publique ni gabarit")
    end
    missing
  end

  def action_defined?(controller, action)
    file = controller_file(controller)
    return true if file.nil?                       # contrôleur hors app/ : non jugeable
    return true if Dir.glob(File.join(@app_dir, "app/views", controller, "#{action}.*")).any?
    chain(file).any? { |src| src.match?(/^\s*def\s+#{Regexp.escape(action)}\b/) }
  end

  def controller_file(controller)
    path = File.join(@app_dir, "app/controllers", "#{controller}_controller.rb")
    File.exist?(path) ? path : nil
  end

  # Contrôleur + ses parents + les concerns inclus (une action peut y vivre).
  def chain(file, seen = Set.new)
    return [] if file.nil? || seen.include?(file)
    seen << file
    src = Src.clean(file)
    out = [ src ]
    parent = src[/\bclass\s+[\w:]+\s*<\s*([\w:]+)/, 1]
    if parent && !parent.start_with?("ActionController", "ApplicationController::")
      out.concat(chain(File.join(@app_dir, "app/controllers", "#{Src.underscore(parent)}.rb"), seen)) if parent != "ApplicationController"
      out.concat(chain(File.join(@app_dir, "app/controllers/application_controller.rb"), seen)) if parent == "ApplicationController"
    end
    src.scan(/^\s*include\s+([\w:]+)/) do |mod|
      %w[app/controllers/concerns app/models/concerns].each do |dir|
        f = File.join(@app_dir, dir, "#{Src.underscore(mod[0])}.rb")
        out.concat(chain(f, seen)) if File.exist?(f)
      end
    end
    out
  end

  # --- Branchement JS : le geste existe mais on ne peut pas le prouver ------
  def js_wired_controllers(routes, gestures)
    by_prefix = routes.group_by(&:prefix)
    ctrls = Set.new
    gestures.js_helpers.each { |h| by_prefix[h]&.each { |r| ctrls << r.controller } }
    routes.each { |r| ctrls << r.controller if gestures.js_reaches?(r.path) }
    ctrls
  end

  def check_writes(routes, gestures, missing, js_controllers)
    routes.reject { |r| r.verb == "GET" }.each do |route|
      next if missing.include?([ route.controller, route.action ])
      next if gestures.reaches_helper?(route.prefix, route.verb)
      next if gestures.reaches_literal?(route.path, route.verb)
      detail = "#{route.controller}##{route.action}"
      if js_controllers.include?(route.controller)
        @report.add("write_route_js_only", "#{route.verb} #{route.path}",
                    "#{detail} — helper cité dans un attribut data/JS, verbe non vérifiable")
      else
        @report.add("write_route_unreachable", "#{route.verb} #{route.path}",
                    "#{detail} — aucun form_with/button_to/link_to turbo_method ne la vise")
      end
    end
  end

  def check_gets(routes, gestures, missing)
    routes.select { |r| r.verb == "GET" }.each do |route|
      next if missing.include?([ route.controller, route.action ])
      next if route.prefix.to_s.end_with?("root") || route.path == "/"
      next if gestures.mentions_helper?(route.prefix)
      next if gestures.reaches_literal?(route.path, "GET")
      @report.add("get_route_orphan", "GET #{route.path}",
                  "#{route.controller}##{route.action} — aucun lien trouvé (entrée directe, redirection ou lien d'e-mail ?)")
    end
  end
end

# ---------------------------------------------------------------------------
# Mode readwrite
# ---------------------------------------------------------------------------
Column = Struct.new(:table, :name, :type, :default)

class ReadWriteScanner
  WRITE_NAMES = "update_all|update_columns?|update!?|create_with|create!?|new|build|" \
                "assign_attributes|insert_all!?|upsert_all|find_or_create_by!?|find_or_initialize_by"
  QUERY_NAMES = "where|order|reorder|group|having|pluck|select|joins|includes|" \
                "find_by!?|exists\\?|count|sum|average|maximum|minimum"

  def initialize(app_dir, report, mockups: false)
    @app_dir = File.expand_path(app_dir)
    @report = report
    @mockups = mockups
  end

  def run
    @mockups ? run_mockups : run_code
  end

  private

  def rel(path) = path.sub("#{@app_dir}/", "")

  # =========================== phase code =================================
  def run_code
    columns = schema_columns
    if columns.empty?
      @report.note("db/schema.rb introuvable ou vide : rien à comparer")
      return
    end
    @report.note("#{columns.size} colonne(s) métier retenue(s) dans db/schema.rb")
    @tables = columns.map(&:table).uniq
    @names = columns.map(&:name).to_set
    # Une colonne dont le nom n'existe QUE dans une table peut être attribuée
    # sans risque même quand le receveur est illisible. Les homonymes (`icon`
    # sur deux tables) n'ont pas ce luxe : ils ne partent jamais en bloquant.
    tally = Hash.new(0)
    columns.each { |c| tally[c.name] += 1 }
    @unique_names = tally.select { |_, n| n == 1 }.keys.to_set

    corpus = build_corpus
    @report.note("#{corpus[:code].size} fichier(s) de code, " \
                 "#{corpus[:seed].size} de seeds/fixtures, " \
                 "#{corpus[:replayable].size} rejouable(s) en production (rake, migrations)")

    idx = { code: build_index(corpus[:code], seed: false),
            seed: build_index(corpus[:seed], seed: true),
            replayable: build_index(corpus[:replayable], seed: true),
            data: build_index(corpus[:data], seed: false) }
    columns.each { |col| classify(col, idx) }
  end

  # Occurrences retenues pour une colonne : celles attribuées à sa table, plus
  # celles dont le receveur est illisible (on préfère taire une façade que d'en
  # inventer une sur une homonymie de colonne).
  def for_column(bucket, col)
    (bucket[col.name] || []).select { |o| o[:table].nil? || o[:table] == col.table }
  end

  def schema_columns
    file = File.join(@app_dir, "db/schema.rb")
    return [] unless File.exist?(file)
    cols = []
    table = nil
    Src.clean(file).each_line do |line|
      if (m = line.match(/create_table\s+["'](\w+)["']/))
        table = m[1]
        table = nil if CONFIG[:rw_skip_tables].any? { |re| m[1].match?(re) }
        next
      end
      next if table.nil?
      if (m = line.match(/\A\s*t\.(\w+)\s+["'](\w+)["']/))
        type, name = m.captures
        next if type == "index"
        next if CONFIG[:rw_skip_columns].any? { |re| name.match?(re) }
        cols << Column.new(table, name, type, line[/\bdefault:\s*("[^"]*"|[^,\s]+)/, 1])
      end
      table = nil if line.strip == "end"
    end
    cols
  end

  # Trois seaux, parce que « écrit quelque part » ne veut rien dire tant qu'on
  # ne sait pas si ce quelque part tourne chez le client :
  #   code       — l'application elle-même ;
  #   seed       — db/seeds*, fixtures : jamais joué en production ;
  #   replayable — lib/tasks/*.rake, migrations : joué au déploiement.
  # Le reste (tests) sert seulement à dire « alimentée par … » dans le texte.
  def build_corpus
    code = Dir.glob(File.join(@app_dir, "app/**/*.{rb,erb}")) +
           Dir.glob(File.join(@app_dir, "lib/**/*.rb"))
    code = code.reject { |f| f.include?("/views/mockups/") || f.include?("/controllers/mockups/") }
    code = code.reject { |f| replayable_path?(rel(f)) }

    data = Dir.glob(File.join(@app_dir, "db/seeds*/**/*.{rb,yml}")) + Dir.glob(File.join(@app_dir, "db/seeds.rb")) +
           Dir.glob(File.join(@app_dir, "db/migrate/*.rb")) + Dir.glob(File.join(@app_dir, "db/data/**/*.rb")) +
           Dir.glob(File.join(@app_dir, "lib/tasks/**/*.{rake,rb}")) +
           Dir.glob(File.join(@app_dir, "{test,spec}/**/*.{rb,yml}"))
    data = data.uniq.sort.map { |f| [ f, Src.clean(f) ] }

    replayable = data.select { |f, _| replayable_path?(rel(f)) }
    promoted = promoted_by_tasks(replayable, data)
    seed = data.select { |f, _| CONFIG[:rw_seed_paths].any? { |re| rel(f).match?(re) } && !promoted.include?(f) }

    { code: code.sort.map { |f| [ f, Src.clean(f) ] },
      seed: seed,
      replayable: replayable + data.select { |f, _| promoted.include?(f) },
      data: data }
  end

  def replayable_path?(relpath) = CONFIG[:rw_replayable_paths].any? { |re| relpath.match?(re) }

  # Un fichier de seeds qu'une tâche rake `require` (ou dont elle appelle la
  # constante) n'est plus un seed : c'est un import, rejouable en production.
  # Cas réel : `lib/tasks/ontology.rake` → `db/seeds/ontology/import.rb`.
  def promoted_by_tasks(replayable, data)
    tasks_src = replayable.select { |f, _| rel(f).start_with?("lib/tasks/") }.map { |_, s| s }.join("\n")
    return Set.new if tasks_src.empty?

    wanted = Set.new
    tasks_src.scan(/(?:require|require_relative|load)[\s(]+[^\n]*?["']([\w\-.\/]+)["']/) { wanted << Regexp.last_match(1) }
    constants = tasks_src.scan(/\b([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)\s*\.\s*[a-z_]/).flatten.to_set

    data.filter_map do |file, src|
      relf = rel(file)
      next if replayable_path?(relf)
      stem = relf.sub(/\.\w+\z/, "")
      hit = wanted.any? { |w| stem.end_with?(w.sub(/\.\w+\z/, "")) }
      hit ||= src.scan(/^\s*(?:module|class)\s+([A-Z][A-Za-z0-9_]*)/).flatten
                 .any? { |c| constants.any? { |k| k == c || k.start_with?("#{c}::") } }
      file if hit
    end.to_set
  end

  # Un identifiant de receveur (`Invoice`, `@client`, `invoices`) ramené à une
  # table. nil = non identifiable : l'occurrence compte alors pour toutes les
  # tables (on préfère taire une façade que d'en inventer une).
  def table_for(token, tables)
    return nil if token.nil? || token.empty?
    t = Src.underscore(token.sub(/\A@+/, ""))
    return t if tables.include?(t)
    p = Src.pluralize(t)
    return p if tables.include?(p)
    s = Src.singularize(t)
    tables.include?(s) ? s : nil
  end

  def classify(col, idx)
    code_index = idx[:code]
    reads = for_column(code_index[:read], col)
    writes = for_column(code_index[:write], col)
    user = for_column(code_index[:user], col)
    seed_writes = for_column(idx[:seed][:write], col)
    replay_writes = for_column(idx[:replayable][:write], col)
    data = for_column(idx[:data][:write], col) + for_column(idx[:data][:read], col)

    real_reads = reads.reject { |o| o[:presence_only] }
    # Citer de préférence une lecture dont le receveur a pu être rattaché à la
    # table : sinon on montre au lecteur une ligne qui parle d'un modèle voisin.
    sure = real_reads.select { |o| o[:table] == col.table }
    cited = (sure.first || real_reads.first)
    hedge = sure.empty? && !real_reads.empty? ? " [receveur non identifié : à confirmer]" : ""
    read = !real_reads.empty?
    displayed = real_reads.any? { |o| o[:file].include?("/views/") || o[:file].include?("/helpers/") }
    outgoing = sure.find { |o| o[:file].match?(CONFIG[:rw_outgoing_path]) } ||
               real_reads.find { |o| o[:file].match?(CONFIG[:rw_outgoing_path]) }
    name = "#{col.table}.#{col.name}"

    if user.any? || writes.any?
      return if read
      how = user.any? ? "saisie en #{user.first[:file]}:#{user.first[:line]}" : "écrite en #{writes.first[:file]}:#{writes.first[:line]}"
      why = reads.empty? ? "jamais lue nulle part" : "lue seulement en test de présence (#{reads.first[:file]}:#{reads.first[:line]})"
      @report.add("column_written_not_read", name, "#{how} — #{why}")
    elsif read
      origin = data.any? ? "alimentée seulement par #{data.first[:file]}" : "jamais écrite par l'application"
      where = "lue en #{cited[:file]}:#{cited[:line]}#{hedge}"
      surface = seed_only_surface(real_reads, col)
      if surface && seed_writes.any? && replay_writes.empty?
        seed = seed_writes.find { |o| o[:table] == col.table } || seed_writes.first
        frozen = col.default ? "figée à la valeur par défaut (#{col.default})" : "vide"
        @report.add("column_seed_only", name,
                    "lue en #{surface[:file]}:#{surface[:line]}, écrite seulement par #{seed[:file]}:#{seed[:line]} " \
                    "— aucun formulaire, aucun code applicatif, aucune tâche rake ni migration ne l'alimente : " \
                    "#{frozen} chez un vrai utilisateur, juste chez le développeur",
                    severity: "bloquant")
      elsif outgoing
        @report.add("column_read_not_writable", name,
                    "#{where} (document sortant : #{outgoing[:file]}:#{outgoing[:line]}) — #{origin}, aucun permit ni champ de formulaire",
                    severity: "bloquant")
      elsif displayed || data.any?
        @report.add("column_read_not_writable", name,
                    "#{where} — #{origin}, aucun permit ni champ de formulaire")
      else
        @report.add("column_displayed_only", name, "#{where} — aucun écran de saisie")
      end
    elsif data.empty?
      @report.add("column_dead", name, "ni lue, ni saisie, ni alimentée par un seed")
    end
  end

  # Lecture qui vaut « l'utilisateur final voit ce champ à l'écran », et qui
  # vaut assez pour un verdict BLOQUANT. Trois exigences, chacune payée par un
  # faux positif observé :
  #   - une vraie surface de rendu (vue, helper, mailer, PDF), pas un
  #     contrôleur ni un service : `Skill.category` lu dans un service ne se
  #     voit pas, et une colonne peut n'être qu'un critère de tri ;
  #   - pas une maquette : `app/views/mockups`, `lovable`, `figma` ne sont pas
  #     le produit livré ;
  #   - un accès d'attribut ou de requête (`x.col`, `pluck(:col)`), jamais un
  #     `hash[:col]` : `mission_domain(mission)[:icon]` est un Hash, pas la
  #     colonne `icon` — c'est ce qui remontait deux fois, une par table ;
  #   - un receveur RÉSOLU à la table de la colonne. Le repli « nom de colonne
  #     unique dans le schéma » suffisait pour la catégorie majeure, pas pour
  #     un bloquant : `zone.lead` (association vers un membre d'équipe) se
  #     faisait passer pour `skill_card_templates.lead`, seule colonne `lead`
  #     du schéma. Prix payé : une colonne toujours lue via un receveur
  #     anonyme (`f.object.x`, `d&.x`) reste dans la catégorie majeure.
  def seed_only_surface(real_reads, col)
    return nil unless col.table
    real_reads.find do |o|
      o[:table] == col.table &&
        %i[attr query].include?(o[:kind]) &&
        o[:file].match?(CONFIG[:rw_render_surface]) &&
        CONFIG[:rw_not_shipped_dirs].none? { |d| o[:file].include?("/#{d}/") }
    end
  end

  # --- Index : un seul passage par fichier, colonnes reconnues au vol -------
  RECEIVER = /(?:@{0,2}[A-Za-z_]\w*(?:\s*&?\.\s*[A-Za-z_]\w*)*)/
  FIELD_HELPERS = /(?:\w*_field|select|check_box|radio_button|text_area|collection_select|
                     collection_check_boxes|collection_radio_buttons|date_select|time_select|
                     datetime_select|rich_text_area|label|hidden_field|file_field)/x

  def build_index(files, seed: false)
    idx = { read: Hash.new { |h, k| h[k] = [] },
            write: Hash.new { |h, k| h[k] = [] },
            user: Hash.new { |h, k| h[k] = [] } }
    files.each do |file, src|
      scan_file(idx, file, src)
      scan_data_file(idx, file, src) if seed
    end
    idx
  end

  # Un fichier de seeds ou une fixture, c'est de la donnée pure : `last_active_at:`
  # y est une écriture de colonne, même quand le constructeur est un helper maison
  # (`seed_user!(…)`) que la détection d'écriture normale ne connaît pas. Ce
  # passage-là n'est JAMAIS appliqué au code applicatif, où `total:` peut être
  # tout autre chose.
  def scan_data_file(idx, file, src)
    lines = LineMap.new(src)
    relf = rel(file)
    yaml = file.end_with?(".yml", ".yaml")
    re = yaml ? /^[ \t]+([a-z_]\w*):[ \t]*(?!$)/ : /(?<![\w:.])([a-z_]\w*):[ \t]*(?![\s:])/
    src.scan(re) do
      m = Regexp.last_match
      next unless @names.include?(m[1])
      idx[:write][m[1]] << { file: relf, line: lines.at(m.begin(0)),
                             table: nil, presence_only: false, kind: :data }
    end
  end

  def scan_file(idx, file, src)
    lines = LineMap.new(src)
    relf = rel(file)
    own = own_table(file)
    scopes = form_scopes(src)
    add = lambda do |bucket, name, offset, receiver, presence = false, kind = :attr|
      # `end_on_input`, `paid_on_input` : attributs virtuels de saisie qui
      # écrivent la vraie colonne. Saisir le virtuel, c'est saisir la colonne.
      if bucket == :user && name.to_s.end_with?("_input") && @names.include?(name.sub(/_input\z/, ""))
        add.call(bucket, name.sub(/_input\z/, ""), offset, receiver, presence, kind)
      end
      next unless @names.include?(name)
      table = resolve_table(receiver, own)
      # `tenant_scope(Invoice).new(...)` : le receveur n'est pas un identifiant,
      # la classe est juste à côté.
      table ||= nearby_constant_table(src, offset)
      idx[bucket][name] << { file: relf, line: lines.at(offset),
                             table: table, presence_only: presence, kind: kind }
    end

    # --- lectures ---------------------------------------------------------
    # Chaîne d'appels `a.b.c` : chaque maillon intermédiaire est une lecture
    # d'attribut. Le dernier ne compte que s'il n'est ni un appel avec arguments
    # (`SERVICES.key?(x)` est un Hash, pas une colonne `key`) ni une affectation.
    # Le lookbehind écarte les chaînes pointées qui ne sont pas du code :
    # `t(".fields.lead")` ressemble trait pour trait à `objet.fields.lead` et
    # faisait passer la clé i18n `lead` pour une lecture de colonne.
    src.scan(/(?<![."'\w])@{0,2}[A-Za-z_]\w*(?:\s*&?\.\s*[a-z_]\w*[?!]?)+/) do
      m = Regexp.last_match
      parts = m[0].split(/\s*&?\.\s*/)
      # `x.col == y` reste une lecture ; `x.col = y` et `x.col(arg)` non.
      last_is_call = src[m.end(0), 3].to_s.match?(/\A\s*\(|\A\s*=(?![=~>])/) || m[0].end_with?("(")
      parts.each_with_index do |raw, i|
        next if i.zero?
        name = raw.sub(/[?!]\z/, "")
        next if i == parts.size - 1 && (last_is_call || raw.end_with?("!"))
        nxt = parts[i + 1]
        presence = !nxt.nil? && %w[blank? present? nil? empty?].include?(nxt)
        add.call(:read, name, m.begin(0), parts[i - 1], presence)
      end
    end
    src.scan(/(#{RECEIVER})?\s*&?\.?\s*\[\s*:([a-z_]\w*)\s*\]/o) { add.call(:read, Regexp.last_match(2), Regexp.last_match.begin(0), Regexp.last_match(1), false, :index) }
    src.scan(/(#{RECEIVER})\s*&?\.\s*(?:dig|fetch)\(\s*:([a-z_]\w*)/o) { add.call(:read, Regexp.last_match(2), Regexp.last_match.begin(0), Regexp.last_match(1), false, :index) }
    src.scan(/(#{RECEIVER})\s*\.\s*(?:#{QUERY_NAMES})(?:\s*\.\s*not)?\s*\(/o) do
      m = Regexp.last_match
      span = Src.expression_span(src, m.end(0) - 1, erb: false, max: 400)
      span.scan(/:([a-z_]\w*)\b|\b([a-z_]\w*):/) { add.call(:read, Regexp.last_match(1) || Regexp.last_match(2), m.begin(0), m[1], false, :query) }
    end
    # Dans app/models/<modele>.rb, l'attribut s'appelle sans receveur.
    if own
      src.scan(/(?<![.:@\w])([a-z_]\w*)\b(?!\s*[:=]|\w)/) do
        m = Regexp.last_match
        add.call(:read, m[1], m.begin(0), nil) if @names.include?(m[1])
      end
    end

    # --- écritures --------------------------------------------------------
    # `self.applied_at ||= Time.current` est une écriture : sans le `||=`, quatre
    # colonnes remplies par un `before_validation` passaient pour des façades.
    assign = /\s*(?:\|\||&&|\*\*|[-+*\/%])?=(?![=~>])/
    src.scan(/(#{RECEIVER})\s*&?\.\s*([a-z_]\w*)#{assign}/o) { add.call(:write, Regexp.last_match(2), Regexp.last_match.begin(0), Regexp.last_match(1)) }
    src.scan(/(#{RECEIVER})?\s*\[\s*:([a-z_]\w*)\s*\]#{assign}/o) { add.call(:write, Regexp.last_match(2), Regexp.last_match.begin(0), Regexp.last_match(1)) }
    src.scan(/(#{RECEIVER})?\s*\.?\s*(?:write_attribute|update_columns?|update_attribute|increment!?|decrement!?|toggle!?)\(\s*:([a-z_]\w*)/o) do
      add.call(:write, Regexp.last_match(2), Regexp.last_match.begin(0), Regexp.last_match(1))
    end
    src.scan(/(#{RECEIVER})?\s*\.?\s*\b(?:#{WRITE_NAMES})\s*\(/o) do
      m = Regexp.last_match
      next if m[0].match?(/\.\s*(?:#{QUERY_NAMES})\s*\(/o)
      span = Src.expression_span(src, m.end(0) - 1, erb: false, max: 900)
      span.scan(/\b([a-z_]\w*):\s/) { add.call(:write, Regexp.last_match(1), m.begin(0), m[1]) }
    end
    # `attrs = { salary_expectation_min: … } … @profile.update(attrs.compact)` :
    # le hash d'attributs monté dans une variable reste une écriture. Sans ça,
    # deux colonnes saisies à l'onboarding passaient pour des façades.
    src.scan(/(?<![\w.:])([a-z_]\w*)\s*=\s*\{/) do
      m = Regexp.last_match
      var = Regexp.escape(m[1])
      next unless src.match?(/\b(?:#{WRITE_NAMES})\s*\(?\s*#{var}\b/o)
      span = Src.expression_span(src, m.end(0) - 1, erb: false, max: 1200)
      span.scan(/\b([a-z_]\w*):\s/) { add.call(:write, Regexp.last_match(1), m.begin(0), nil) }
    end

    # --- saisies utilisateur ---------------------------------------------
    # `permit(...)` (Rails ≤ 7) et `params.expect(model: [ ... ])` (Rails 8).
    src.scan(/\b(?:permit!?|expect!?)\s*\(/) do
      m = Regexp.last_match
      span = Src.expression_span(src, m.end(0) - 1, erb: false, max: 1600)
      before = src[[ m.begin(0) - 120, 0 ].max...m.begin(0)].to_s
      model = before[/require\(\s*:(\w+)/, 1] || before[/params\[:(\w+)\]/, 1] ||
              span[/\A\(\s*(\w+):\s*\[/, 1]
      # `bank_accounts_attributes: [ %i[iban bic] ]` : ces champs-là sont ceux du
      # modèle imbriqué, pas ceux du modèle racine.
      permit_segments(span, model).each do |seg_model, text|
        text.scan(/:([a-z_]\w*)/) { add.call(:user, Regexp.last_match(1), m.begin(0), seg_model) }
        text.scan(/%[wi]\[([^\]]*)\]/) { Regexp.last_match(1).split.each { |n| add.call(:user, n.delete(":"), m.begin(0), seg_model) } }
        text.scan(/\*\s*([A-Z][\w:]*)/) do                     # permit(*ATTRIBUTES)
          const = Regexp.last_match(1).split("::").last
          src.scan(/#{const}\s*=\s*%[wi]\[([^\]]*)\]/m) { Regexp.last_match(1).split.each { |n| add.call(:user, n.delete(":"), m.begin(0), seg_model) } }
        end
      end
    end
    src.scan(/params\s*(?:\[\s*:(\w+)\s*\]|\.\s*dig\(\s*:(\w+)\s*),?\s*[\[(]?\s*:([a-z_]\w*)/) do
      m = Regexp.last_match
      add.call(:user, m[3], m.begin(0), m[1] || m[2])
    end
    src.scan(/name\s*=\s*["'](?:(\w+)\[([a-z_]\w*)\]|([a-z_]\w*))["']/) do
      m = Regexp.last_match
      add.call(:user, m[2] || m[3], m.begin(0), m[1])
    end
    src.scan(/\.\s*#{FIELD_HELPERS}\s*[( ]\s*:([a-z_]\w*)/o) do
      m = Regexp.last_match
      add.call(:user, m[1], m.begin(0), scopes.enclosing(m.begin(0)))
    end
    # Helpers `*_tag` : formulaires sans modèle (`number_field_tag :open_salary_min`).
    # Un contrôle qui porte le nom de la colonne, c'est l'utilisateur qui la tape.
    src.scan(/\b\w*(?:field|area|select|box|button)_tag\s*[( ]\s*:([a-z_]\w*)/) do
      m = Regexp.last_match
      add.call(:user, m[1], m.begin(0), nil)
    end
  end

  # Portée d'un `f.text_field :x` : le modèle du form_with / fields_for qui
  # précède, sinon rien (le champ compterait alors pour toutes les tables).
  def form_scopes(src)
    scopes = []
    src.scan(/\b(?:form_with|form_for|fields_for|fields)\b/) do
      m = Regexp.last_match
      span = Src.expression_span(src, m.begin(0), erb: src.include?("<%"))[0, 300].to_s
      token = span[/\bmodel:\s*(?:\[[^\]]*,)?\s*@?([\w]+)/, 1] ||
              span[/\bscope:\s*:(\w+)/, 1] ||
              span[/\b(?:fields_for|fields|form_for)\s*\(?\s*:?@?(\w+)/, 1]
      scopes << [ m.begin(0), token ] if token
    end
    Scopes.new(scopes)
  end

  class Scopes
    def initialize(list) = @list = list
    def enclosing(offset)
      hit = nil
      @list.each { |o, t| hit = t if o <= offset }
      hit
    end
  end

  class LineMap
    def initialize(src)
      @offsets = [ 0 ]
      src.each_char.with_index { |c, i| @offsets << i + 1 if c == "\n" }
    end

    def at(offset)
      lo = 0
      hi = @offsets.size - 1
      while lo < hi
        mid = (lo + hi + 1) / 2
        @offsets[mid] <= offset ? lo = mid : hi = mid - 1
      end
      lo + 1
    end
  end

  # `app/models/invoice.rb` → table `invoices` : dans ce fichier, `self.x = ` et
  # les appels d'attribut sans receveur parlent forcément de cette table.
  def own_table(file)
    m = file.match(%r{/app/models/(\w+)\.rb\z})
    return nil unless m
    t = Src.pluralize(m[1])
    @tables.include?(t) ? t : nil
  end

  def permit_segments(span, model)
    segments = []
    cursor = model
    pos = 0
    span.scan(/(\w+)_attributes:\s*/) do
      mm = Regexp.last_match
      segments << [ cursor, span[pos...mm.begin(0)].to_s ]
      cursor = mm[1]
      pos = mm.end(0)
    end
    segments << [ cursor, span[pos..].to_s ]
    segments
  end

  def nearby_constant_table(src, offset)
    window = src[[ offset - 60, 0 ].max, 100].to_s
    window.scan(/\b([A-Z][A-Za-z]+)\b/) do
      t = table_for(Regexp.last_match(1), @tables)
      return t if t
    end
    nil
  end

  # `JobTitle.canonical.ordered.pluck(:category)` : la table est portée par le
  # PREMIER maillon, pas par le dernier. On remonte la chaîne de droite à gauche
  # et on prend le premier maillon qui nomme une table — sinon des lectures
  # parfaitement identifiables restaient « receveur non identifié ».
  def resolve_table(receiver, own)
    token = receiver.to_s[/(\w+)\z/, 1]
    return own if token.nil? || %w[self params f form].include?(token)
    segments = receiver.to_s.split(/\s*&?\.\s*/).reject(&:empty?)
    segments.reverse_each do |seg|
      t = table_for(seg, @tables)
      return t if t
    end
    own_or_nil(token, own)
  end

  # `self.total_ht_cents = …` dans un concern : receveur inconnu, table inconnue.
  def own_or_nil(_token, _own) = nil

  # =========================== phase maquettes =============================
  def run_mockups
    fields = doc_fields
    if fields.empty?
      @report.note("aucun champ lisible dans #{CONFIG[:rw_doc_models]} (tableaux `| Nom | Type | Description |`)")
      return
    end
    views = Dir.glob(File.join(@app_dir, "app/views/mockups/**/*.erb")).sort
    if views.empty?
      @report.note("aucune maquette sous app/views/mockups")
      return
    end
    @model_tokens = fields.map { |m, _, _| Src.underscore(m) }
                          .flat_map { |t| [ t, Src.pluralize(t), *t.split("_") ] }.to_set
    shown, captured = mockup_tokens(views)
    @report.note("#{fields.size} champ(s) documentés, #{shown.size} token(s) affichés et #{captured.size} saisis dans #{views.size} maquette(s)")

    fields.each do |model, field, line|
      loc = "#{model}.#{field}"
      doc = "#{CONFIG[:rw_doc_models]}:#{line}"
      is_shown = match_token?(field, shown)
      is_captured = match_token?(field, captured)
      if is_shown && !is_captured
        @report.add("column_read_not_writable", loc,
                    "#{doc} — affiché dans les maquettes, aucun contrôle de saisie relié à ce champ " \
                    "(écran de saisie manquant, ou champ de maquette rempli en dur)")
      elsif is_captured && !is_shown
        @report.add("column_written_not_read", loc, "#{doc} — saisi dans les maquettes, affiché nulle part")
      elsif !is_shown && !is_captured
        @report.add("field_absent_from_mockups", loc, "#{doc} — ni affiché ni saisi : écran manquant ou champ à retirer du modèle")
      end
    end
  end

  def doc_fields
    file = File.join(@app_dir, CONFIG[:rw_doc_models])
    return [] unless File.exist?(file)
    out = []
    model = nil
    in_table = false
    File.readlines(file).each_with_index do |line, i|
      if (m = line.match(/\A###\s+(\w+)/))
        model = CONFIG[:rw_skip_models].any? { |re| m[1].match?(re) } ? nil : m[1]
        in_table = false
        next
      end
      if line.match?(/\A\|\s*Nom\s*\|/i)
        in_table = true
        next
      end
      if line.match?(/\A\|[\s\-:|]+\|\s*\z/)
        next
      end
      unless line.start_with?("|")
        in_table = false
        next
      end
      next unless in_table && model
      cells = line.split("|").map(&:strip)
      names, type = cells[1].to_s, cells[2].to_s
      next if type.match?(/references|ActiveStorage|has_/i)
      expand_names(names).each do |n|
        next if CONFIG[:rw_skip_columns].any? { |re| n.match?(re) }
        next if CONFIG[:rw_mockup_skip_columns].any? { |re| n.match?(re) }
        out << [ model, n, i + 1 ]
      end
    end
    out.uniq { |m, n, _| [ m, n ] }
  end

  # « address_line1/2, postal_code, city » → quatre champs.
  def expand_names(cell)
    cell.gsub(/[`*]/, "").split(",").flat_map do |part|
      part = part.strip
      next [] unless part.match?(/\A[a-z][\w\/]*\z/)
      if part.include?("/")
        head, *rest = part.split("/")
        [ head ] + rest.map { |r| r.match?(/\A\d+\z/) ? head.sub(/\d+\z/, r) : r }
      else
        [ part ]
      end
    end.uniq
  end

  def mockup_tokens(views)
    shown = Set.new
    captured = Set.new
    views.each do |path|
      src = Src.clean(path)
      # Affichage : accès aux données fictives (hash de maquette).
      src.scan(/\[\s*:(\w+)\s*\]/) { shown << Regexp.last_match(1) }
      src.scan(/\bdig\(\s*:(\w+)/)  { shown << Regexp.last_match(1) }
      src.scan(/\bfetch\(\s*:(\w+)/) { shown << Regexp.last_match(1) }
      # Saisie : nom/id du contrôle, ou donnée liée à l'intérieur du contrôle.
      src.scan(/name\s*=\s*["'](?:\w+\[)?(\w+)\]?["']/) { captured << Regexp.last_match(1) }
      [ /\bfor\s*=\s*["'](\w+)["']/, /\bid\s*=\s*["'](\w+)["']/ ].each do |re|
        src.scan(re) do
          v = Regexp.last_match(1)
          captured << v
          captured << v.split("_", 2).last if v.include?("_")
        end
      end
      src.scan(/<(input|select|textarea)\b#{TAG_BODY}>/im) do
        m = Regexp.last_match
        span = element_span(src, m.begin(0), m[1])
        span.scan(/\[\s*:(\w+)\s*\]|\bdig\(\s*:(\w+)/) { captured << (Regexp.last_match(1) || Regexp.last_match(2)) }
        span.scan(/\.\w*(?:field|select|area|box|button)\s*[( ]\s*:(\w+)/) { captured << Regexp.last_match(1) }
      end
    end
    shown.merge(captured)     # ce qui est saisi est aussi montré (valeur pré-remplie)
    [ shown, captured ]
  end

  def element_span(src, start, tag)
    if tag.downcase == "input"
      src[start, (src.index(">", start) || start) - start + 1].to_s
    else
      stop = src.index("</#{tag}", start) || (start + 800)
      src[start...[ stop, src.length ].min].to_s
    end
  end

  # Rapprochement tolérant mais pas laxiste : `vat_rate` ↔ `vat` (suite de mots
  # incluse), mais PAS `invoice_prefix` ↔ `invoice_number` (mots en commun sans
  # inclusion : deux champs différents).
  def match_token?(field, tokens)
    return true if tokens.include?(field)
    base = field.sub(/_(cents|id)\z/, "")
    return true if tokens.include?(base)
    words = base.split("_")
    tokens.any? do |t|
      tw = t.sub(/_(cents|id)\z/, "").split("_")
      contiguous?(words, tw) || contiguous?(tw, words)
    end
  end

  # `short` apparaît-il tel quel, dans l'ordre et d'un seul tenant, dans `long` ?
  def contiguous?(short, long)
    return false if short.empty? || short.size > long.size
    if short.size == 1
      w = short.first
      return false if w.length < 3 || CONFIG[:rw_fuzzy_stopwords].include?(w)
      # `vat` vaut `vat_rate`, `address` vaut `address_line1` — mais un nom de
      # modèle (`quote`) ne vaut pas `quote_prefix` : c'est le porteur, pas le champ.
      return false if @model_tokens.include?(w)
      return long.first == w
    end
    (0..(long.size - short.size)).any? { |i| long[i, short.size] == short }
  end
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def usage!
  warn <<~TXT
    usage:
      ruby facade_scan.rb static       <rails_app_dir> [--json] [--no-boot]
      ruby facade_scan.rb crawl        <base_url> [--cookie "k=v"]... [--json] [--max N]
      ruby facade_scan.rb reachability <rails_app_dir> [--json] [--no-boot] [--mockups]
      ruby facade_scan.rb readwrite    <rails_app_dir> [--json] [--mockups]
  TXT
  exit 0
end

MODES = %w[static crawl reachability readwrite].freeze
mode, target = ARGV[0], ARGV[1]
usage! unless MODES.include?(mode) && target

json_only = ARGV.include?("--json")
cookies = ARGV.each_cons(2).select { |a, _| a == "--cookie" }.map(&:last)
max = (i = ARGV.index("--max")) ? ARGV[i + 1].to_i : CONFIG[:crawl_max_pages]

report = Report.new(mode, target)
begin
  case mode
  when "static"
    unless Dir.exist?(target)
      report.note("répertoire introuvable : #{target}")
    else
      StaticScanner.new(target, report, boot: !ARGV.include?("--no-boot")).run
    end
  when "crawl"
    CrawlScanner.new(target, report, cookies: cookies, max_pages: max).run
  when "reachability", "readwrite"
    unless Dir.exist?(target)
      report.note("répertoire introuvable : #{target}")
    else
      mockups = ARGV.include?("--mockups")
      report.note("cadrage maquettes (--mockups)") if mockups
      if mode == "reachability"
        ReachabilityScanner.new(target, report, boot: !ARGV.include?("--no-boot"), mockups: mockups).run
      else
        ReadWriteScanner.new(target, report, mockups: mockups).run
      end
    end
  end
rescue StandardError => e
  report.note("SCAN INTERROMPU : #{e.class} #{e.message} — le rapport est INCOMPLET, ne pas le lire comme un feu vert")
  warn "facade_scan : SCAN INTERROMPU (#{e.class}: #{e.message})"
  warn e.backtrace.first(5).join("\n")
  @scan_aborted = true
end

report.print_text unless json_only
puts JSON.pretty_generate(report.summary)
exit(@scan_aborted ? 2 : 0)
