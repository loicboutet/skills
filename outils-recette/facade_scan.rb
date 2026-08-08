#!/usr/bin/env ruby
# frozen_string_literal: true

# facade_scan.rb — scanner de "façades non branchées" (lab livraison 5000.dev)
#
# Le bug signature du pipeline maquette→code : un élément d'interface qui a
# l'air fonctionnel mais n'est branché sur rien (champ sans name, action
# Stimulus orpheline, lien vers une route inexistante, données en dur héritées
# de la maquette). Ce script les repère, il ne les corrige pas.
#
# Usage :
#   ruby facade_scan.rb static <rails_app_dir> [--json] [--no-boot]
#   ruby facade_scan.rb crawl  <base_url> [--cookie "k=v"] [--json] [--max N]
#
# Sortie : rapport texte groupé par catégorie (fichier:ligne ou URL), puis un
# résumé JSON (comptes par catégorie). --json = JSON seul. Exit 0 toujours.

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
  ],

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
}.freeze

ERB_EXPR = "E"  # marqueur d'un <%= ... %>
ERB_STMT = "S"  # marqueur d'un <% ... %> / <%# ... %>

Finding = Struct.new(:category, :location, :detail)

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
  }.freeze

  def initialize(mode, target)
    @mode = mode
    @target = target
    @findings = []
    @notes = []
  end

  def add(category, location, detail = nil)
    @findings << Finding.new(category, location, detail)
  end

  def note(msg) = @notes << msg

  def counts
    CATEGORIES.keys.each_with_object({}) do |cat, h|
      n = @findings.count { |f| f.category == cat }
      h[cat] = n if n.positive?
    end
  end

  def summary
    { "mode" => @mode, "target" => @target, "counts" => counts,
      "total" => @findings.size, "notes" => @notes }
  end

  def print_text
    puts "facade_scan — mode #{@mode} — #{@target}"
    @notes.each { |n| puts "note: #{n}" }
    puts
    if @findings.empty?
      puts "Aucune façade détectée."
    end
    CATEGORIES.each do |cat, label|
      items = @findings.select { |f| f.category == cat }
      next if items.empty?
      puts "## #{label} (#{items.size})"
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
    return false unless File.executable?(File.join(@app_dir, "bin/rails"))
    out = IO.popen(["timeout", CONFIG[:rails_routes_timeout].to_s, "bin/rails", "routes"],
                   chdir: @app_dir, err: File::NULL, &:read) rescue ""
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
# CLI
# ---------------------------------------------------------------------------
def usage!
  warn <<~TXT
    usage:
      ruby facade_scan.rb static <rails_app_dir> [--json] [--no-boot]
      ruby facade_scan.rb crawl  <base_url> [--cookie "k=v"]... [--json] [--max N]
  TXT
  exit 0
end

mode, target = ARGV[0], ARGV[1]
usage! unless %w[static crawl].include?(mode) && target

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
  end
rescue StandardError => e
  report.note("erreur du scanner : #{e.class} #{e.message}")
end

report.print_text unless json_only
puts JSON.pretty_generate(report.summary)
exit 0
