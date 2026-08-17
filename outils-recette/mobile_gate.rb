#!/usr/bin/env ruby
# frozen_string_literal: true

# mobile_gate.rb -- le verrou mobile avant tout verdict de livraison.
#
# Pourquoi cet outil existe.
# `style_diff` mesure deja les champs ecrases (`control-crushed`), les
# controles retrecis (`control-shrunk`) et le contenu coupe (`clip-*`,
# `overflow-*`), et il les classe bloquants. Les skills disent en gras de ne
# jamais conclure "conforme" sur le seul `scrollWidth`. Et pourtant, banc
# modeles du 16-17/08/2026 : deux livraisons sur trois ont ete rendues avec des
# champs de prix a 18 px sur mobile, l'une d'elles avec 26 `control-crushed`
# bloquants dans son propre rapport style_diff au moment du verdict READY. La
# regle etait ecrite ; la lecture du rapport ne l'etait pas.
#
# Ce script LIT le `resume.json` (et les `paires/*.json`) produits par
# style_diff et rend un verdict binaire sur les seules classes qui mesurent la
# saisie mobile. Il ne juge pas la parite de style (`missing`, `style`, `box`,
# `added`...), qui reste au jugement du reviewer et produit beaucoup de
# mis-appariements. Il ne peut donc pas etre contourne par "trop de bruit".
#
# Usage, mode RAPPORT (review, apres style_diff) :
#   ruby ~/.claude/skills/outils-recette/mobile_gate.rb doc/memory/brick-1/parite/
#
# Usage, mode DIRECT (reanalyse des maquettes, ou n'importe quel lot d'ecrans
# servis : on mesure les pages elles-memes, sans paire ni style_diff) :
#   ruby ~/.claude/skills/outils-recette/mobile_gate.rb --urls urls.txt [--session nom]
#   (urls.txt : une URL absolue par ligne ; les lignes vides et # sont ignorees ;
#    utilise playwright-cli, une session dediee, fermee a la fin)
#
#   -> exit 0 : la gate passe, on peut ecrire le verdict
#   -> exit 1 : la gate REFUSE, un verdict READY / PRET est interdit
#   -> exit 2 : rien de mesurable (rapport absent, URLs injoignables) = REFUS
#
# La ligne a coller dans review.md / reanalyse.md est la derniere de stdout.

require "json"
require "open3"
require "shellwords"

# ---------------------------------------------------------------------------
# Mode DIRECT : mesurer des ecrans a 390 px via playwright-cli.
# Trois mesures par ecran, celles que les skills prescrivent a la main :
#   1. bord droit REEL (element le plus a droite hors position: fixed, hors
#      conteneur a defilement horizontal declare)  -> doit etre <= 390
#   2. conteneurs NON defilants qui coupent (scrollWidth > clientWidth sans
#      overflow-x auto|scroll)                       -> doit etre vide
#   3. champs de saisie visibles sous 24 px de large -> doit etre vide
# `document.documentElement.scrollWidth` est releve mais NE DECIDE RIEN.
# ---------------------------------------------------------------------------
MEASURE_JS = <<~JS.gsub(/\s+/, " ").strip
  (() => {
    const okEl = (e) => {
      const s0 = getComputedStyle(e);
      if (s0.position === 'fixed' || s0.animationName !== 'none') return false;
      for (let p = e.parentElement; p && p !== document.body; p = p.parentElement) {
        const s = getComputedStyle(p);
        if (['auto','scroll'].includes(s.overflowX) || s.position === 'fixed' || s.animationName !== 'none') return false;
      }
      return true;
    };
    let right = 0, rightLbl = null;
    for (const e of document.querySelectorAll('body *')) {
      const r = e.getBoundingClientRect();
      if (r.width <= 0 || !okEl(e)) continue;
      if (r.right > right) { right = r.right; rightLbl = e.tagName.toLowerCase() + (e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\\s+/).slice(0,3).join('.') : ''); }
    }
    /* Conteneurs qui COUPENT : un bloc de layout dont le contenu depasse sans
       defilement declare. On exclut ce qui coupe par construction ou par choix
       typographique : les controles de formulaire (le scrollWidth interne d'un
       select natif depasse toujours), le texte inline et les titres tronques
       en ellipse (text-overflow), et tout ce qui vit dans un conteneur qui
       defile. Ce qui reste = un tableau ou une grille rognes en silence. */
    const TEXTY = new Set(['h1','h2','h3','h4','h5','h6','p','span','a','label','td','th','li','small','strong','em','b','i','code','pre','time','dt','dd']);
    const CTRL = new Set(['input','select','textarea','button','option','optgroup']);
    const inScroller = (e) => { for (let p = e.parentElement; p && p !== document.body; p = p.parentElement) { if (['auto','scroll'].includes(getComputedStyle(p).overflowX)) return true; } return false; };
    const clips = [...document.querySelectorAll('div, section, main, article, form, table, ul, ol, nav, aside, header, footer, fieldset, figure')]
      .filter(e => {
        const c = getComputedStyle(e);
        if (['auto','scroll'].includes(c.overflowX)) return false;
        if (e.scrollWidth <= e.clientWidth + 8 || e.clientWidth <= 24) return false;
        if (inScroller(e)) return false;
        return true;
      })
      .slice(0, 12)
      .map(e => ({ el: e.tagName.toLowerCase() + (typeof e.className === 'string' && e.className ? '.' + e.className.trim().split(/\\s+/).slice(0,3).join('.') : ''), sw: e.scrollWidth, cw: e.clientWidth }));
    const hidden = (e) => { const c = getComputedStyle(e); const cls = e.className || ''; const r = e.getBoundingClientRect(); return c.opacity === '0' || (c.clipPath && c.clipPath !== 'none') || /sr-only|visually-hidden/.test(cls) || (r.width <= 2 && r.height <= 2); };
    const fields = [...document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=hidden]), select, textarea')]
      .filter(e => e.getBoundingClientRect().width > 0 && !hidden(e))
      .map(e => ({ n: e.name || e.id || e.type, w: Math.round(e.getBoundingClientRect().width) }))
      .filter(f => f.w < 24);
    return { right: Math.round(right), rightLbl, clips, fields, doc: document.documentElement.scrollWidth };
  })()
JS

def pw(session, *args)
  cmd = ["playwright-cli", "-s=#{session}", *args]
  out, err, st = Open3.capture3(*cmd)
  [out, err, st.success?]
end

def measure_urls(urls, session)
  results = []
  first = true
  urls.each do |url|
    if first
      _o, err, ok = pw(session, "open", url)
      first = false
    else
      _o, err, ok = pw(session, "goto", url)
    end
    unless ok
      results << { url: url, error: "chargement impossible (#{err.to_s.lines.last.to_s.strip})" }
      next
    end
    pw(session, "resize", "390", "844")
    out, err, ok = pw(session, "--json", "eval", MEASURE_JS)
    unless ok
      results << { url: url, error: "eval impossible (#{err.to_s.lines.last.to_s.strip})" }
      next
    end
    begin
      wrapper = JSON.parse(out)
      data = wrapper["result"]
      data = JSON.parse(data) if data.is_a?(String)
      results << { url: url }.merge(data.transform_keys(&:to_sym))
    rescue JSON::ParserError
      results << { url: url, error: "sortie playwright-cli illisible" }
    end
  end
  results
ensure
  pw(session, "close")
end

if ARGV[0] == "--urls"
  list = ARGV[1]
  session = (i = ARGV.index("--session")) ? ARGV[i + 1] : "mobile-gate-#{Process.pid}"
  unless list && File.file?(list)
    warn "usage: mobile_gate.rb --urls <fichier d'URLs> [--session nom]"
    exit 2
  end
  urls = File.readlines(list, chomp: true).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
  if urls.empty?
    warn "REFUS : aucune URL dans #{list}."
    puts "## Mobile (gate) : AUCUN ECRAN -- verdict interdit"
    exit 2
  end
  res = measure_urls(urls, session)
  errors = res.select { |r| r[:error] }
  bad = []
  puts "mobile_gate -- mode direct, #{urls.size} ecrans a 390 px, #{errors.size} en erreur"
  res.each do |r|
    if r[:error]
      puts "  ERREUR  #{r[:url]} : #{r[:error]}"
      next
    end
    issues = []
    issues << "bord droit #{r[:right]}px (#{r[:rightLbl]})" if r[:right].to_i > 390
    issues << "#{r[:clips].size} conteneur(s) qui coupent : #{r[:clips].first(3).map { |c| "#{c['el'] || c[:el]} #{c['sw'] || c[:sw]}/#{c['cw'] || c[:cw]}" }.join(', ')}" if r[:clips].to_a.any?
    issues << "#{r[:fields].size} champ(s) ecrase(s) : #{r[:fields].first(4).map { |f| "#{f['n'] || f[:n]}=#{f['w'] || f[:w]}px" }.join(', ')}" if r[:fields].to_a.any?
    if issues.any?
      bad << r
      puts "  REFUS   #{r[:url]}  (document #{r[:doc]}px)"
      issues.each { |i| puts "            - #{i}" }
    else
      puts "  ok      #{r[:url]}"
    end
  end
  if errors.size == urls.size
    puts "## Mobile (gate) : AUCUN ECRAN MESURE (serveur ? URLs ?) -- verdict interdit"
    exit 2
  elsif bad.empty? && errors.empty?
    puts "## Mobile (gate) : PASSE -- #{urls.size} ecrans a 390 px, bord droit <= 390, 0 conteneur qui coupe, 0 champ ecrase"
    exit 0
  else
    parts = []
    parts << "#{bad.size} ecran(s) en defaut" if bad.any?
    parts << "#{errors.size} non mesure(s)" if errors.any?
    puts "## Mobile (gate) : REFUS -- #{parts.join(', ')} -- verdict interdit tant que ce n'est pas corrige et re-mesure"
    exit 1
  end
end

# ---------------------------------------------------------------------------
# Mode RAPPORT : lire la sortie de style_diff.
# ---------------------------------------------------------------------------

GATED_KINDS = {
  "control-crushed" => "champ de saisie ecrase (< 24 px, plus saisissable)",
  "control-shrunk"  => "controle nettement plus petit qu'en maquette",
  "clip-implicite"  => "contenu coupe par un overflow implicite (tableau rogne en silence)",
  "clip-declare"    => "contenu coupe par un overflow-x: clip|hidden declare",
  "clip-reste"      => "contenu coupe (residuel)",
  "overflow-el"     => "element qui deborde du viewport",
  "overflow-doc"    => "document qui deborde du viewport"
}.freeze

MOBILE_VIEWPORTS = %w[mobile 390].freeze

dir = ARGV[0]
if dir.nil? || dir.strip.empty?
  warn "usage: mobile_gate.rb <dossier de sortie de style_diff>"
  exit 2
end

resume_path = File.join(dir, "resume.json")
unless File.file?(resume_path)
  warn "REFUS : #{resume_path} absent. style_diff n'a pas ete lance sur cette livraison, ou sa sortie machine n'a pas ete conservee. Relancer style_diff avec --out #{dir} AVANT tout verdict."
  puts "## Mobile (gate) : NON MESURE -- verdict READY interdit"
  exit 2
end

begin
  resume = JSON.parse(File.read(resume_path))
rescue JSON::ParserError => e
  warn "REFUS : #{resume_path} illisible (#{e.message})."
  puts "## Mobile (gate) : RAPPORT ILLISIBLE -- verdict READY interdit"
  exit 2
end

# Les viewports mesures. Sans viewport mobile, la mesure n'a pas eu lieu.
viewports = Array(resume["viewports"]).map { |v| v["name"].to_s }
mobile_vp = viewports.find { |n| MOBILE_VIEWPORTS.any? { |m| n.downcase.include?(m) } }
unless mobile_vp
  warn "REFUS : aucun viewport mobile dans le rapport (viewports : #{viewports.join(', ')}). Relancer style_diff avec le viewport 390."
  puts "## Mobile (gate) : VIEWPORT MOBILE ABSENT -- verdict READY interdit"
  exit 2
end

# Les ecrans non mesures (erreur de chargement) ne sont pas des conformites.
errors = Array(resume["errors"]).select { |e| e["viewport"].to_s == mobile_vp }

# On lit les findings detailles dans paires/*.json (le resume ne porte que des
# comptes par severite, pas par kind).
pairs_dir = File.join(dir, "paires")
found = Hash.new { |h, k| h[k] = [] }
measured_pairs = 0
Dir.glob(File.join(pairs_dir, "*.json")).sort.each do |f|
  entry = JSON.parse(File.read(f)) rescue next
  vp = (entry["viewports"] || {})[mobile_vp]
  next unless vp
  measured_pairs += 1
  Array(vp["findings"]).each do |x|
    kind = x["kind"].to_s
    next unless GATED_KINDS.key?(kind)
    found[kind] << { pair: entry["name"] || File.basename(f, ".json"), element: x["element"], app: x["app"], message: x["message"] }
  end
end

if measured_pairs.zero?
  warn "REFUS : aucune paire mesuree en #{mobile_vp} dans #{pairs_dir}. Le rapport est vide ou tronque."
  puts "## Mobile (gate) : AUCUNE PAIRE MESUREE -- verdict READY interdit"
  exit 2
end

total = found.values.sum(&:size)
puts "mobile_gate -- viewport #{mobile_vp}, #{measured_pairs} ecrans mesures, #{errors.size} en erreur"
GATED_KINDS.each do |kind, label|
  n = found[kind].size
  next if n.zero?
  puts "  #{n.to_s.rjust(3)}  #{kind.ljust(16)} #{label}"
  found[kind].first(8).each { |h| puts "        - #{h[:pair]} : #{h[:element]} (#{h[:app]})" }
  puts "        ... et #{n - 8} de plus" if n > 8
end
errors.first(5).each { |e| puts "  ERREUR de mesure : #{e['pair']} -- #{e['error']}" }

if total.zero? && errors.empty?
  puts "## Mobile (gate) : PASSE -- #{measured_pairs} ecrans a #{mobile_vp}, 0 champ ecrase, 0 contenu coupe, 0 debordement"
  exit 0
else
  reasons = []
  reasons << "#{total} constat(s) bloquant(s) de saisie mobile" if total.positive?
  reasons << "#{errors.size} ecran(s) non mesure(s)" if errors.any?
  puts "## Mobile (gate) : REFUS -- #{reasons.join(', ')} -- verdict READY interdit tant que ce n'est pas corrige et re-mesure"
  exit 1
end
