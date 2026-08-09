#!/usr/bin/env ruby
# frozen_string_literal: true

# pairs_gen.rb — fabrique le pairs.json de style_diff.js pour un projet Rails.
#
#   ruby pairs_gen.rb <rails_app_dir> [--out pairs.json] [--base http://127.0.0.1:3000]
#                                     [--no-boot] [--quiet]
#
# Ce qu'il fait, dans l'ordre :
#   1. lit les routes (`bin/rails routes`, repli sur config/routes.rb) ;
#   2. énumère les vues de app/views/mockups/** et leur donne leur URL ;
#   3. cherche l'écran applicatif correspondant (même contrôleur sans le
#      préfixe mockups, même action) et ne garde la paire que si la route
#      existe VRAIMENT ;
#   4. résout les identifiants des routes à segment dynamique (base de dev,
#      repli sur db/seeds.rb) ;
#   5. extrait les comptes de démonstration de db/seeds.rb et le formulaire de
#      connexion des vues, pour remplir le bloc `auth`.
#
# Une maquette sans écran réel n'est PAS une paire : elle part dans la clé
# `non_appariees` avec sa raison. C'est une information de recette à part
# entière (maquette validée jamais implémentée).
#
# Le fichier produit se relit et se corrige à la main : c'est un point de
# départ, pas un oracle. Les limites connues sont en fin de SKILL.md.

require "json"
require "set"
require "open3"
require "tmpdir"

VERBS = %w[GET POST PUT PATCH DELETE].freeze

# Pages système des maquettes dont l'équivalent applicatif ne porte pas le même
# nom. On cherche la route par motif sur le chemin, pas par contrôleur.
SYSTEM_ALIASES = [
  { match: /\A(login|sign_?in|connexion)\z/, path: %r{/(sessions?|sign_?in|login|connexion)(/new)?\z}, public: true },
  { match: /\A(forgot_password|password_reset|mot_de_passe_oublie)\z/, path: %r{/passwords?/(forgot|new|reset)}, public: true },
  { match: /\A(signup|sign_?up|registration|inscription)\z/, path: %r{/(sign_?up|registrations?/new|inscription)\z}, public: true }
].freeze

# Actions de maquette qui n'ont, par construction, aucun écran applicatif.
NO_APP_COUNTERPART = {
  /\A(error_404|not_found|error_500|server_error|error)\z/ => "page d'erreur : rendue par Rails, pas par un contrôleur applicatif",
  /\A(activation|invitation)\z/ => "écran d'activation : atteint par un jeton d'e-mail, pas par une URL stable"
}.freeze

# Chemins applicatifs accessibles sans session : la paire est jouée en anonyme.
PUBLIC_PATH = %r{\A/(sessions?|sign_?in|sign_?up|login|logout|connexion|passwords?|invitations?|users/(sign|password|confirmation))}i

TENANT_KEYS = %w[company_id account_id organization_id tenant_id team_id].freeze

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

def usage
  warn <<~TXT
    Usage : ruby pairs_gen.rb <rails_app_dir> [options]

      --out <fichier>   destination (défaut : pairs.json dans le répertoire courant)
      --base <url>      base des deux côtés (défaut : http://127.0.0.1:3000)
      --no-boot         ne lance pas `bin/rails routes` (repli textuel, moins fiable)
      --quiet           pas de trace sur stderr
  TXT
  exit 2
end

app_dir = nil
out_file = "pairs.json"
base_url = "http://127.0.0.1:3000"
no_boot = false
quiet = false

argv = ARGV.dup
until argv.empty?
  a = argv.shift
  case a
  when "--out"     then out_file = argv.shift or usage
  when "--base"    then base_url = argv.shift or usage
  when "--no-boot" then no_boot = true
  when "--quiet"   then quiet = true
  when "-h", "--help" then usage
  else
    usage if a.start_with?("-") || app_dir
    app_dir = a
  end
end
usage unless app_dir
app_dir = File.expand_path(app_dir)
abort "Répertoire introuvable : #{app_dir}" unless File.directory?(app_dir)
abort "Pas une application Rails (config/routes.rb absent) : #{app_dir}" unless File.file?(File.join(app_dir, "config/routes.rb"))
base_url = base_url.sub(%r{/\z}, "")

WARNINGS = []
LOG = ->(msg) { warn(msg) unless quiet }
def warn!(msg) = WARNINGS << msg

# ---------------------------------------------------------------------------
# 1. Routes
# ---------------------------------------------------------------------------

# On efface l'environnement Ruby du script avant d'appeler les commandes de
# l'application. Lancé depuis un autre répertoire, rbenv fige SA version dans
# l'environnement (RBENV_DIR, RUBYLIB, PATH réécrit) : l'application démarre
# alors avec le mauvais Ruby et rend un `Bundler::GemNotFound` trompeur, qui
# ressemble à un projet cassé. Le fils doit relire le .ruby-version du projet,
# comme un shell ouvert dedans.
CHILD_ENV = begin
  env = %w[RBENV_VERSION RBENV_DIR RBENV_HOOK_PATH RUBYOPT RUBYLIB
           BUNDLE_GEMFILE BUNDLE_PATH GEM_HOME GEM_PATH].to_h { |k| [ k, nil ] }
  env["PATH"] = ENV["RBENV_ORIG_PATH"] if ENV["RBENV_ORIG_PATH"]
  env.freeze
end

def run_with_timeout(cmd, dir, seconds)
  out = +""
  err = +""
  status = nil
  Open3.popen3(CHILD_ENV, cmd, chdir: dir) do |stdin, stdout, stderr, wait|
    stdin.close
    reader = Thread.new { out << stdout.read }
    reader_e = Thread.new { err << stderr.read }
    unless wait.join(seconds)
      Process.kill("KILL", wait.pid) rescue nil
      reader.kill
      reader_e.kill
      return [ nil, "délai dépassé (#{seconds}s)" ]
    end
    reader.join
    reader_e.join
    status = wait.value
  end
  status&.success? ? [ out, nil ] : [ nil, err.to_s.lines.first(5).join.strip ]
end

def parse_routes(text)
  routes = []
  text.each_line do |line|
    toks = line.strip.split(/\s+/)
    vi = toks.index { |t| VERBS.include?(t) }
    next unless vi
    path = toks[vi + 1]
    ca = toks[vi + 2]
    next unless path&.start_with?("/")
    next unless ca && ca =~ %r{\A[a-z0-9_/]+#[a-z0-9_]+\z}
    ctrl, act = ca.split("#")
    routes << { verb: toks[vi], path: path, controller: ctrl, action: act }
  end
  routes.uniq
end

# Repli sans boot : on ne peut pas connaître les chemins réels, seulement les
# contrôleurs cités dans config/routes.rb. Suffisant pour dire « cet écran
# existe probablement », pas pour fabriquer une URL sûre.
def fallback_controllers(app_dir)
  src = File.read(File.join(app_dir, "config/routes.rb"))
  names = Set.new
  src.scan(/resources?\s+:(\w+)/) { |m| names << m[0] }
  src.scan(/to:\s*["']([a-z0-9_\/]+)#/) { |m| names << m[0] }
  src.scan(/controller:\s*:(\w+)/) { |m| names << m[0] }
  names
end

routes = []
routes_ok = false
unless no_boot
  LOG.call("· lecture des routes (bin/rails routes)…")
  text, err = run_with_timeout("bin/rails routes", app_dir, 120)
  if text
    routes = parse_routes(text)
    routes_ok = !routes.empty?
  end
  warn!("`bin/rails routes` a échoué (#{err}) : URL applicatives déduites par convention, à vérifier une par une.") unless routes_ok
end
warn!("Généré avec --no-boot : les URL ne sont pas confrontées aux routes réelles.") if no_boot

get_routes = routes.select { |r| r[:verb] == "GET" }
# Les routes du produit, maquettes exclues : c'est le seul jeu où chercher un
# écran applicatif. Sans ce filtre, /mockups/login s'apparie avec lui-même.
app_get_routes = get_routes.reject { |r| r[:controller] == "mockups" || r[:controller].start_with?("mockups/") }

def clean_path(path)
  path.gsub(/\(\.:format\)/, "").gsub(/\([^()]*\)/, "").sub(%r{(?<=.)/\z}, "")
end

def path_params(path) = clean_path(path).scan(/:(\w+)/).flatten

# ---------------------------------------------------------------------------
# 2. Vues de maquette
# ---------------------------------------------------------------------------

mockups_dir = File.join(app_dir, "app/views/mockups")
unless File.directory?(mockups_dir)
  warn!("Aucun répertoire app/views/mockups : rien à apparier (projet sans maquettes servies, ou maquettes ailleurs).")
end

views = Dir.glob(File.join(mockups_dir, "**/*.html*.erb")).sort
views.reject! { |f| File.basename(f).start_with?("_") }          # partials
views.reject! { |f| f.include?("/layouts/") }

mockup_views = views.map do |file|
  rel = file.sub("#{app_dir}/app/views/", "")
  ctrl = File.dirname(rel)
  action = File.basename(rel).split(".").first
  { file: rel, controller: ctrl, action: action }
end
LOG.call("· #{mockup_views.size} vue(s) de maquette")

# Premier segment de chaque contrôleur de maquette (hors « mockups ») : ce sont
# les namespaces que l'application est censée conserver. Ils interdisent
# d'apparier /mockups/dashboard avec /admin/dashboard.
mockup_namespaces = mockup_views
  .map { |v| v[:controller].sub(%r{\Amockups/?}, "").split("/").first }
  .compact.uniq.to_set

# ---------------------------------------------------------------------------
# 3. Appariement
# ---------------------------------------------------------------------------

# URL de la maquette : la route si elle existe, sinon la convention REST.
def conventional_path(ctrl, action)
  base = "/" + ctrl
  case action
  when "index"  then base
  when "show"   then "#{base}/:id"
  when "new"    then "#{base}/new"
  when "edit"   then "#{base}/:id/edit"
  else "#{base}/#{action}"
  end
end

def find_route(get_routes, ctrl, action)
  get_routes.find { |r| r[:controller] == ctrl && r[:action] == action }
end

# Cherche l'écran applicatif : même contrôleur privé du préfixe « mockups »,
# éventuellement précédé d'un scope (`scope module: :app`). On refuse un
# préfixe qui est lui-même un namespace de maquette (admin, settings…) : c'est
# ce qui apparierait le tableau de bord entreprise avec celui du superadmin.
def app_candidates(get_routes, ctrl_base, action, forbidden)
  ctrl_base_segments = ctrl_base.split("/")
  get_routes.filter_map do |r|
    next unless r[:action] == action
    c = r[:controller]
    next if c.start_with?("mockups/") || c == "mockups"
    if c == ctrl_base
      { route: r, score: 0 }
    elsif c.end_with?("/#{ctrl_base}")
      prefix = c[0...-(ctrl_base.size + 1)].split("/")
      next if prefix.any? { |seg| forbidden.include?(seg) && !ctrl_base_segments.include?(seg) }
      { route: r, score: prefix.size }
    end
  end.sort_by { |c| [ c[:score], c[:route][:path].length ] }
end

def system_alias(get_routes, action)
  SYSTEM_ALIASES.each do |al|
    next unless action =~ al[:match]
    hit = get_routes.find { |r| clean_path(r[:path]) =~ al[:path] }
    return hit if hit
  end
  nil
end

pairs_raw = []
unmatched = []

mockup_views.each do |v|
  ctrl = v[:controller]
  action = v[:action]
  ctrl_base = ctrl.sub(%r{\Amockups/?}, "")

  # Le hub des maquettes n'a pas d'équivalent : c'est notre propre sommaire.
  if ctrl_base.empty? || ctrl_base == "home"
    unmatched << { maquette: v[:file], raison: "hub des maquettes, pas un écran du produit" }
    next
  end

  mroute = routes_ok ? find_route(get_routes, ctrl, action) : nil
  mockup_path = mroute ? clean_path(mroute[:path]) : conventional_path(ctrl, action)
  if routes_ok && mroute.nil?
    unmatched << { maquette: v[:file], raison: "vue de maquette sans route : la page n'est pas atteignable, même en maquette" }
    next
  end

  skip = NO_APP_COUNTERPART.find { |re, _| action =~ re }
  if skip
    unmatched << { maquette: v[:file], url_maquette: mockup_path, raison: skip[1] }
    next
  end

  aroute = nil
  if routes_ok
    cands = app_candidates(app_get_routes, ctrl_base, action, mockup_namespaces)
    aroute = cands.first&.dig(:route)
    aroute ||= system_alias(app_get_routes, action)
    if cands.size > 1 && cands[0][:score] == cands[1][:score]
      warn!("Écran applicatif ambigu pour #{v[:file]} : #{cands.first(3).map { |c| clean_path(c[:route][:path]) }.join(', ')} — la première a été retenue.")
    end
  end

  if routes_ok && aroute.nil?
    unmatched << { maquette: v[:file], url_maquette: mockup_path,
                   raison: "aucune route applicative pour #{ctrl_base}##{action} : maquette validée jamais implémentée (ou renommée)" }
    next
  end

  app_path = aroute ? clean_path(aroute[:path]) : conventional_path(ctrl_base, action)

  pairs_raw << {
    view: v[:file], controller_base: ctrl_base, action: action,
    mockup_path: mockup_path, app_path: app_path,
    model_key: ctrl_base.split("/").last
  }
end

# ---------------------------------------------------------------------------
# 4. Identifiants des routes à segment dynamique
# ---------------------------------------------------------------------------

seeds_files = Dir.glob(File.join(app_dir, "db/seeds.rb")) + Dir.glob(File.join(app_dir, "db/seeds/**/*.rb"))
seeds_src = seeds_files.map { |f| File.read(f) rescue "" }.join("\n")

needs_id = pairs_raw.select { |p| path_params(p[:app_path]).any? }
resolved_ids = {}

if needs_id.any?
  hard = needs_id.reject { |p| path_params(p[:app_path]) == [ "id" ] }
  hard.each do |p|
    unmatched << { maquette: p[:view], url_maquette: p[:mockup_path], url_app: p[:app_path],
                   raison: "paramètre dynamique non résolu (#{path_params(p[:app_path]).join(', ')}) : à ouvrir à la main" }
  end
  pairs_raw -= hard
  needs_id -= hard

  keys = needs_id.map { |p| p[:model_key] }.uniq
  if keys.any? && !no_boot && routes_ok
    demo_email = seeds_src[/["']([\w.+-]+@[\w.-]+\.\w+)["']/, 1]
    script = <<~RUBY
      require "json"
      keys = #{keys.inspect}
      tenant_keys = #{TENANT_KEYS.inspect}
      demo_email = #{demo_email.inspect}
      tenant = nil
      begin
        if demo_email && defined?(User)
          col = User.column_names.find { |c| c =~ /\\Aemail(_address)?\\z/ }
          u = col ? User.find_by(col => demo_email) : nil
          key = u && tenant_keys.find { |k| User.column_names.include?(k) }
          tenant = [ key, u.public_send(key) ] if key && u.public_send(key)
        end
      rescue StandardError
      end
      out = {}
      keys.each do |k|
        begin
          klass = k.classify.constantize
          scope = klass.all
          if tenant && klass.column_names.include?(tenant[0])
            scoped = klass.where(tenant[0] => tenant[1])
            scope = scoped if scoped.exists?
          end
          out[k] = scope.order(:id).limit(1).pluck(:id).first
        rescue NameError
          out[k] = "SANS_MODELE"
        rescue StandardError
          out[k] = nil
        end
      end
      puts "PAIRS_GEN_IDS " + JSON.generate(out)
    RUBY
    path = File.join(Dir.tmpdir, "pairs_gen_ids_#{Process.pid}.rb")
    File.write(path, script)
    LOG.call("· résolution des identifiants (bin/rails runner)…")
    text, err = run_with_timeout("bin/rails runner #{path}", app_dir, 120)
    File.delete(path) rescue nil
    if text && (line = text[/PAIRS_GEN_IDS (\{.*\})/, 1])
      resolved_ids = JSON.parse(line)
    else
      warn!("`bin/rails runner` a échoué (#{err}) : identifiants déduits des seeds (id 1), à vérifier.")
    end
  end

  keep = []
  needs_id.each do |p|
    key = p[:model_key]
    id = nil
    raison = nil
    if resolved_ids.key?(key)
      case resolved_ids[key]
      when "SANS_MODELE"
        raison = "identifiant non résolu : aucun modèle ne correspond à « #{key} » (à ouvrir à la main)"
      when nil
        raison = "aucun enregistrement en base pour #{key} : seeds non jouées, ou l'écran n'existe que vide"
      else
        id = resolved_ids[key]
      end
    else
      # Sans accès à la base : on ne pose l'identifiant 1 que si les seeds
      # créent bien ce modèle.
      id = 1 if seeds_src =~ /\b#{Regexp.escape(key.sub(/s\z/, ""))}\w*\b/i
      raison = "identifiant non résolu pour #{key} (base non interrogée, rien dans db/seeds.rb)" unless id
    end
    if id.nil?
      unmatched << { maquette: p[:view], url_maquette: p[:mockup_path], url_app: p[:app_path], raison: raison }
      next
    end
    p = p.dup
    p[:app_path] = p[:app_path].gsub(":id", id.to_s)
    p[:mockup_path] = p[:mockup_path].gsub(/:\w+/, "1")   # la maquette ignore l'identifiant
    keep << p
  end
  pairs_raw = (pairs_raw - needs_id) + keep
end

# Une maquette peut encore porter un segment dynamique que l'app n'a pas.
pairs_raw.each { |p| p[:mockup_path] = p[:mockup_path].gsub(/:\w+/, "1") }
pairs_raw.sort_by! { |p| p[:app_path] }

# ---------------------------------------------------------------------------
# 5. Comptes de démonstration (db/seeds.rb)
# ---------------------------------------------------------------------------

# Découpe grossière en instructions : on recolle les lignes tant que les
# parenthèses ne sont pas équilibrées (les appels de seeds tiennent souvent sur
# quatre lignes).
def statements(src)
  out = []
  buf = +""
  depth = 0
  src.each_line do |line|
    stripped = line.sub(/#.*\z/, "")
    buf << line
    depth += stripped.count("(") - stripped.count(")")
    if depth <= 0
      out << buf
      buf = +""
      depth = 0
    end
  end
  out << buf unless buf.strip.empty?
  out
end

password_consts = {}
seeds_src.scan(/^\s*([A-Z][A-Z0-9_]*PASSWORD[A-Z0-9_]*)\s*=\s*(["'])(.+?)\2/) { |n, _, v| password_consts[n] = v }
default_password = password_consts.find { |k, _| k =~ /DEMO/ }&.last || password_consts.values.first

EMAIL_RE = /["']([\w.+-]+@[\w.-]+\.\w{2,})["']/

accounts = []
statements(seeds_src).each do |st|
  next unless st =~ /user/i
  next if st =~ /password:\s*nil/
  email = st[EMAIL_RE, 1]
  next unless email
  pwd = st[/password:\s*["'](.+?)["']/, 1]
  pwd ||= password_consts[st[/password:\s*([A-Z][A-Z0-9_]*)/, 1]]
  pwd ||= default_password
  next unless pwd
  role = st[/role:\s*["':]?(\w+)/, 1]
  role ||= "admin" if st =~ /admin:\s*true/
  accounts << { email: email, password: pwd, role: role }
end
accounts.uniq! { |a| a[:email] }

# Un profil par rôle (le premier compte rencontré). Sans rôle, la partie locale
# de l'e-mail sert de nom.
auth = {}
accounts.each do |a|
  name = (a[:role] || a[:email].split("@").first).gsub(/[^\w]/, "_")
  next if auth.key?(name)
  auth[name] = a
end
warn!("Aucun compte de démonstration trouvé dans db/seeds.rb : le bloc `auth` est vide, les écrans privés ne seront pas comparés.") if auth.empty?

# ---------------------------------------------------------------------------
# 6. Formulaire de connexion
# ---------------------------------------------------------------------------

login_view = nil
candidates = Dir.glob(File.join(app_dir, "app/views/**/*.html*.erb")).reject { |f| f.include?("/mockups/") }.sort
candidates = candidates.select { |f| File.read(f) =~ /type=["']password["']|password_field/ }
preferred = candidates.select { |f| f =~ %r{/(sessions?|logins?|sign_?in|connexions?)/} }
excluded = %r{(reset|forgot|invitation|activation|registration|password)s?/}
login_view = preferred.first || candidates.reject { |f| f =~ excluded }.first || candidates.first

login_url = nil
fill = []
submit = "button[type=submit]"

if login_view
  src = File.read(login_view)
  rel = login_view.sub("#{app_dir}/", "")
  ctrl = File.dirname(rel).sub("app/views/", "")
  act = File.basename(rel).split(".").first
  r = routes_ok ? find_route(get_routes, ctrl, act) : nil
  login_url = r ? clean_path(r[:path]) : nil

  selector = lambda do |tag|
    id = tag[/\bid=["']([^"']+)["']/, 1]
    nm = tag[/\bname=["']([^"']+)["']/, 1]
    next "##{id}" if id
    next "[name=\"#{nm}\"]" if nm
    nil
  end
  inputs = src.scan(/<input\b[^>]*>/)
  pwd_tag = inputs.find { |t| t =~ /type=["']password["']/ }
  id_tag = inputs.find { |t| t =~ /type=["'](email|text)["']/ && t =~ /email|login|username|identifiant/i }
  id_tag ||= inputs.find { |t| t =~ /type=["'](email|text)["']/ }

  if pwd_tag && id_tag && selector.call(pwd_tag) && selector.call(id_tag)
    fill = [ [ selector.call(id_tag), :EMAIL ], [ selector.call(pwd_tag), :PASSWORD ] ]
  else
    warn!("Formulaire de connexion repéré dans #{rel} mais champs illisibles (helpers Rails ?) : complète `auth.*.fill` à la main.")
  end
  submit = "input[type=submit]" if src !~ /<button[^>]*type=["']submit["']/ && src =~ /<input[^>]*type=["']submit["']/
  warn!("Route de connexion introuvable pour #{rel} : renseigne `auth.*.url` à la main.") unless login_url
else
  warn!("Aucun formulaire de connexion trouvé dans app/views : le bloc `auth` est incomplet, les écrans privés ne seront pas comparés.")
end

# Page d'arrivée attendue après connexion : un chemin qui se termine par
# « dashboard » (ou accueil/home). Sert de garde-fou : sans elle, une connexion
# ratée produit un rapport plein d'écarts inventés.
dashboards = app_get_routes.map { |r| clean_path(r[:path]) }
  .select { |p| p =~ %r{/(dashboard|accueil|home)\z} }.uniq
admin_dash = dashboards.find { |p| p =~ %r{\A/(admin|super)} }
plain_dash = dashboards.find { |p| p !~ %r{\A/(admin|super)} }

super_name = auth.keys.find { |k| k =~ /super/i }
admin_name = auth.keys.find { |k| k =~ /\Aadmin/i && k != super_name }
default_profile = admin_name || auth.keys.find { |k| k != super_name } || auth.keys.first

auth_block = {}
auth.each do |name, a|
  expect = if name == super_name then admin_dash
  else (plain_dash || dashboards.first)
  end
  entry = {
    "url" => login_url || "",
    "fill" => fill.map { |sel, kind| [ sel, kind == :EMAIL ? a[:email] : a[:password] ] },
    "submit" => submit
  }
  entry["expect_url"] = expect if expect
  auth_block[name] = entry
end

# ---------------------------------------------------------------------------
# 7. Écriture
# ---------------------------------------------------------------------------

def humanize(path)
  segs = clean_path(path).split("/").reject(&:empty?)
  segs.shift if %w[app mockups].include?(segs.first)
  segs.map { |s| s =~ /\A\d+\z/ ? "fiche" : s.tr("_", " ") }.join(" · ")
end

pairs = pairs_raw.map do |p|
  entry = { "name" => humanize(p[:app_path]).capitalize,
            "mockup_url" => p[:mockup_path], "app_url" => p[:app_path] }
  if p[:app_path] =~ PUBLIC_PATH
    entry["auth_profile"] = nil
  elsif super_name && p[:app_path] =~ %r{\A/(admin|super)}
    entry["auth_profile"] = super_name
  end
  entry
end

# Deux maquettes différentes peuvent viser le même écran (index et une variante
# de démonstration) : on garde la première, on signale les autres.
seen = {}
pairs.each do |p|
  key = [ p["mockup_url"], p["app_url"] ]
  if seen[key]
    warn!("Paire en double ignorée : #{p['name']} (#{p['app_url']})")
  else
    seen[key] = p
  end
end
pairs = seen.values

# Les noms doivent rester uniques : `--only` filtre dessus.
counts = Hash.new(0)
pairs.each do |p|
  counts[p["name"]] += 1
  p["name"] = "#{p['name']} (#{counts[p['name']]})" if counts[p["name"]] > 1
end

commentaire = [
  "Généré par pairs_gen.rb le #{Time.now.strftime('%Y-%m-%d %H:%M')} depuis #{app_dir}.",
  "Relire avant usage : les paires sont déduites des routes, pas validées à l'œil."
]
commentaire.concat(WARNINGS.map { |w| "AVERTISSEMENT : #{w}" })

doc = {
  "_commentaire" => commentaire,
  "base_mockup" => base_url,
  "base_app" => base_url,
  "viewports" => [
    { "name" => "desktop", "width" => 1440, "height" => 900 },
    { "name" => "mobile", "width" => 390, "height" => 844 }
  ],
  "tolerances" => { "font" => 0, "line_height" => 0.5, "tracking" => 0.2, "spacing" => 1, "box" => 2, "offset" => 8 },
  "root_selector" => "body",
  "ignore_selectors" => [],
  "mask_selectors" => [],
  "foreign_css_allow" => [],
  "auth" => auth_block,
  "default_auth_profile" => default_profile,
  "allowlist" => [],
  "pairs" => pairs,
  "non_appariees" => unmatched.sort_by { |u| u[:maquette].to_s }.map { |u| u.transform_keys(&:to_s) }
}

File.write(out_file, JSON.pretty_generate(doc) + "\n")

unless quiet
  warn "· #{pairs.size} paire(s), #{unmatched.size} maquette(s) non appariée(s), #{auth_block.size} profil(s) → #{out_file}"
  WARNINGS.each { |w| warn "  ! #{w}" }
end
