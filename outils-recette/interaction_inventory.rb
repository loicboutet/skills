#!/usr/bin/env ruby
# frozen_string_literal: true

# interaction_inventory.rb — inventaire des INTERACTIONS d'un ecran, comparable
# entre quatre formats qui ne se ressemblent pas : composant React (.tsx/.jsx),
# page HTML avec son JavaScript, maquette ERB, vue applicative Rails.
#
# EMPLACEMENT DEFINITIF : ~/.claude/skills/outils-recette/. Il vit ici pour
# l'instant parce que ~/.claude/skills est resynchronise depuis le depot
# loicboutet/skills et efface tout ajout local. A pousser sur ce depot.
#
# Pourquoi cet outil. mockup_scan inventory compare les BLOCS (ce qui est
# affiche). style_diff compare les PIXELS. Ni l'un ni l'autre ne dit si le
# filtre de la source existe encore dans la maquette, ni si le bouton qu'on
# voit ouvre vraiment quelque chose. C'est pourtant le defaut dominant :
# l'affordance est recopiee, le comportement est perdu.
#
# Regle centrale : une interaction VISIBLE mais NON BRANCHEE compte comme
# ABSENTE. Un bouton sans gestionnaire n'est pas une interaction, c'est un
# dessin de bouton.
#
# usage:
#   ruby interaction_inventory.rb <fichier_ou_dossier> [--json] [--kind auto|react|html|erb]
#   ruby interaction_inventory.rb compare --reference PATH --candidate PATH [--json]
#
# Limites assumees, a lire avant d'y croire :
#   - analyse statique de motifs, pas une execution. Un handler pose par une
#     delegation d'evenement generique (document.addEventListener sur un
#     selecteur calcule) est vu comme non branche : FAUX NEGATIF possible. Le
#     depot tasteseller en contient (onclick inline manipulant style.display).
#   - un `data-controller` Stimulus dont le controleur n'existe pas est vu
#     comme branche : FAUX POSITIF possible. Croiser avec facade_scan.
#   - l'appariement se fait sur le libelle visible du controle. Un libelle
#     retraduit ou reformule entre la source et la cible casse la paire ; la
#     sortie liste alors la meme interaction des deux cotes. Regarder les
#     exemples avant de conclure.

require "json"
require "optparse"
require "set"

VERBS = %w[navigate submit toggle select filter sort search input move media].freeze

mode = ARGV.first == "compare" ? :compare : :scan
ARGV.shift if mode == :compare

opts = { json: false, kind: "auto", reference: nil, candidate: nil, target: nil }
OptionParser.new do |o|
  o.on("--json") { opts[:json] = true }
  o.on("--kind K") { |v| opts[:kind] = v }
  o.on("--reference PATH") { |v| opts[:reference] = v }
  o.on("--candidate PATH") { |v| opts[:candidate] = v }
  o.on("-h", "--help") { puts o; exit }
end.parse!
opts[:target] = ARGV.shift if mode == :scan

EXTS = %w[.erb .html .htm .tsx .jsx .js .ts .vue].freeze

def files_under(path)
  p = File.expand_path(path.to_s)
  return [p] if File.file?(p)
  Dir.glob(File.join(p, "**", "*")).select { |f| File.file?(f) && EXTS.include?(File.extname(f).downcase) }
end

def kind_of(file, forced)
  return forced unless forced == "auto"
  case File.extname(file).downcase
  when ".tsx", ".jsx", ".vue" then "react"
  when ".erb" then "erb"
  when ".js", ".ts" then "script"
  else "html"
  end
end

def clean_label(s)
  return nil if s.nil?
  t = s.dup
  t.gsub!(/<%[-=]?.*?-?%>/m, " ")
  t.gsub!(/\{[^{}]*\}/m, " ")
  t.gsub!(%r{<svg\b.*?</svg>}mi, " ")
  t.gsub!(/<[^>]*>/m, " ")
  t.gsub!(/&[a-z#0-9]+;/i, " ")
  t = t.gsub(/\s+/, " ").strip.downcase
  t = t.tr("àâäáãåéèêëíìîïóòôöõúùûüçñ", "aaaaaaeeeeiiiiooooouuuucn")
  t = t.gsub(/[^a-z0-9 %€\/]/, " ").gsub(/\s+/, " ").strip
  return nil if t.empty?
  t.split(" ").first(4).join(" ")
end

COMPONENT_VERBS = {
  /\b(dialog|modal|alertdialog|sheet|drawer|popover|hovercard|collapsible|accordion|dropdownmenu|menubar|contextmenu|disclosure)\b/i => "toggle",
  /\b(tabs?|tabslist|tabstrigger|segmented|togglegroup|switch|checkbox|radiogroup|combobox|listbox|select)\b/i => "select",
  /\b(carousel|slider|resizable|sortable|draggable|reorder|swiper)\b/i => "move",
  /\b(video|audioplayer|player|lightbox|reactplayer|muxplayer)\b/i => "media",
  /\b(command|searchbar|autocomplete)\b/i => "search",
  /\b(datatable|sortableheader)\b/i => "sort",
  /\b(pagination|paginator)\b/i => "navigate"
}.freeze

def verb_from_name(name)
  return nil if name.nil?
  COMPONENT_VERBS.each { |re, v| return v if name =~ re }
  nil
end

def verb_from_label(label, fallback)
  return fallback if label.nil?
  case label
  when /\bfiltr|\bfilter/ then "filter"
  when /\btri\b|\btrier|\bsort|classer/ then "sort"
  when /recherch|search|chercher/ then "search"
  when /\bvoir|ouvrir|afficher|detail|consulter|\bopen\b/ then "toggle"
  when /suivant|precedent|next|prev/ then "navigate"
  when /lire|play|regarder|pitch|ecouter/ then "media"
  else fallback
  end
end

Item = Struct.new(:verb, :label, :wired, :evidence, :file, :line, keyword_init: true)

REACT_HANDLER = /\bon(?:Click|Change|Submit|Input|KeyDown|KeyUp|Select|Toggle|ValueChange|OpenChange|CheckedChange|Drag\w*|Drop|Play)\s*=/
HTML_HANDLER  = /\bon(?:click|change|submit|input|keydown|keyup|toggle|play)\s*=/i
STIMULUS      = /\bdata-action\s*=/
TURBO         = /\bdata-turbo-(?:frame|method|stream|confirm)\s*=/

def scan_react(src, file)
  items = []
  src.scan(/<([A-Za-z][\w.]*)((?:[^<>]|"[^"]*"|'[^']*'|\{[^{}]*\})*)>/m) do
    tag = Regexp.last_match(1)
    attrs = Regexp.last_match(2).to_s
    line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
    wired = attrs.match?(REACT_HANDLER)
    label = clean_label(attrs[/\b(?:aria-label|placeholder|title|label)\s*=\s*["']([^"']+)["']/, 1])
    low = tag.downcase

    if %w[a link navlink].include?(low)
      href = attrs[/\b(?:href|to)\s*=\s*["']([^"']+)["']/, 1]
      next if href.nil? || href.strip.empty?
      items << Item.new(verb: "navigate", label: label, wired: href.strip != "#",
                        evidence: "<#{tag} href=#{href[0, 30]}>", file: file, line: line)
      next
    end
    if low == "form"
      items << Item.new(verb: "submit", label: label, wired: attrs.match?(/onSubmit|action=/),
                        evidence: "<#{tag}>", file: file, line: line)
      next
    end
    if %w[input textarea].include?(low)
      t = attrs[/\btype\s*=\s*["']([^"']+)["']/, 1].to_s.downcase
      v = %w[checkbox radio].include?(t) ? "select" : (t == "search" ? "search" : "input")
      items << Item.new(verb: v, label: label,
                        wired: wired || attrs.match?(/\bvalue\s*=\s*\{|\bname\s*=/),
                        evidence: "<#{tag} type=#{t}>", file: file, line: line)
      next
    end
    vname = verb_from_name(tag)
    if vname
      items << Item.new(verb: vname, label: label, wired: true,
                        evidence: "<#{tag}> (composant #{vname})", file: file, line: line)
      next
    end
    next unless wired || low == "button"
    items << Item.new(verb: verb_from_label(label, "toggle"), label: label, wired: wired,
                      evidence: "<#{tag}>", file: file, line: line)
  end

  src.scan(%r{<(button|Button)([^>]*)>(.*?)</\1>}m) do
    attrs = Regexp.last_match(2).to_s
    inner = Regexp.last_match(3).to_s
    line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
    label = clean_label(inner) || clean_label(attrs[/aria-label\s*=\s*["']([^"']+)["']/, 1])
    next if label.nil?
    items << Item.new(verb: verb_from_label(label, "toggle"), label: label,
                      wired: attrs.match?(REACT_HANDLER),
                      evidence: "<button>#{label}</button>", file: file, line: line)
  end
  items
end

def scan_html(src, file, erb: false)
  items = []
  has_js = src.match?(/<script/i) || src.include?("addEventListener")
  delegated = (src.scan(/querySelectorAll?\(\s*['"]([^'"]+)['"]/).flatten +
               src.scan(/getElementById\(\s*['"]([^'"]+)['"]/).flatten.map { |i| "##{i}" }).to_set

  src.scan(/<(a|button|form|input|select|textarea|details|summary|dialog|video|audio)\b((?:[^<>"']|"[^"]*"|'[^']*')*)>/mi) do
    tag = Regexp.last_match(1).downcase
    attrs = Regexp.last_match(2).to_s
    line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
    label = clean_label(attrs[/\b(?:aria-label|placeholder|title|alt|value)\s*=\s*["']([^"']+)["']/, 1])
    tokens = attrs.scan(/\b(?:id|class)\s*=\s*["']([^"']+)["']/).flatten.join(" ").split(/\s+/)
    deleg = tokens.any? { |c| delegated.include?(".#{c}") || delegated.include?("##{c}") }
    wired = attrs.match?(HTML_HANDLER) || attrs.match?(STIMULUS) || attrs.match?(TURBO) || deleg

    case tag
    when "a"
      href = attrs[/\bhref\s*=\s*["']([^"']*)["']/, 1].to_s
      real = !href.strip.empty? && href.strip != "#" && !href.start_with?("javascript:void")
      items << Item.new(verb: "navigate", label: label, wired: real || (erb && attrs.include?("<%=")) || wired,
                        evidence: "<a href=\"#{href[0, 40]}\">", file: file, line: line)
    when "form"
      items << Item.new(verb: "submit", label: label,
                        wired: attrs.match?(/\baction\s*=/) || attrs.match?(HTML_HANDLER) || erb,
                        evidence: "<form>", file: file, line: line)
    when "input", "textarea"
      t = attrs[/\btype\s*=\s*["']([^"']+)["']/, 1].to_s.downcase
      v = %w[checkbox radio].include?(t) ? "select" : (t == "search" ? "search" : "input")
      v = "submit" if %w[submit button].include?(t)
      items << Item.new(verb: v, label: label, wired: attrs.match?(/\bname\s*=/) || wired,
                        evidence: "<input type=#{t}>", file: file, line: line)
    when "select"
      items << Item.new(verb: "select", label: label, wired: attrs.match?(/\bname\s*=/) || wired,
                        evidence: "<select>", file: file, line: line)
    when "details", "summary", "dialog"
      items << Item.new(verb: "toggle", label: label, wired: true,
                        evidence: "<#{tag}> (natif)", file: file, line: line)
    when "video", "audio"
      items << Item.new(verb: "media", label: label,
                        wired: attrs.match?(/\bsrc\s*=/) || src.include?("<source"),
                        evidence: "<#{tag}>", file: file, line: line)
    when "button"
      items << Item.new(verb: "toggle", label: label, wired: wired,
                        evidence: "<button>", file: file, line: line)
    end
  end

  src.scan(%r{<(button|a)\b((?:[^<>"']|"[^"]*"|'[^']*')*)>(.*?)</\1>}mi) do
    tag = Regexp.last_match(1).downcase
    attrs = Regexp.last_match(2).to_s
    inner = Regexp.last_match(3).to_s
    line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
    label = clean_label(inner)
    next if label.nil?
    tokens = attrs.scan(/\b(?:id|class)\s*=\s*["']([^"']+)["']/).flatten.join(" ").split(/\s+/)
    deleg = tokens.any? { |c| delegated.include?(".#{c}") || delegated.include?("##{c}") }
    if tag == "a"
      href = attrs[/\bhref\s*=\s*["']([^"']*)["']/, 1].to_s
      items << Item.new(verb: "navigate", label: label,
                        wired: (!href.strip.empty? && href.strip != "#") || (erb && attrs.include?("<%=")),
                        evidence: "<a>#{label}</a>", file: file, line: line)
    else
      items << Item.new(verb: verb_from_label(label, "toggle"), label: label,
                        wired: attrs.match?(HTML_HANDLER) || attrs.match?(STIMULUS) || attrs.match?(TURBO) || deleg,
                        evidence: "<button>#{label}</button>", file: file, line: line)
    end
  end

  if erb
    src.scan(/\b(link_to|button_to|form_with|form_for|search_form_for)\b[^\n]*/) do
      helper = Regexp.last_match(1)
      frag = Regexp.last_match(0)
      line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
      label = clean_label(frag[/["']([^"']{2,60})["']/, 1])
      v = helper == "link_to" ? "navigate" : "submit"
      items << Item.new(verb: verb_from_label(label, v), label: label, wired: true,
                        evidence: helper, file: file, line: line)
    end
    src.scan(/data-controller\s*=\s*["']([^"']+)["']/) do
      line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
      Regexp.last_match(1).split(/\s+/).each do |n|
        v = verb_from_name(n) || verb_from_label(n.tr("-", " "), "toggle")
        items << Item.new(verb: v, label: clean_label(n.tr("-", " ")), wired: true,
                          evidence: "data-controller=#{n}", file: file, line: line)
      end
    end
  end

  if items.empty? && !has_js
    items << Item.new(verb: "toggle", label: nil, wired: false,
                      evidence: "page sans aucun script ni controle", file: file, line: 0)
  end
  items
end

def scan_file(file, forced_kind)
  src = File.read(file, encoding: "UTF-8", invalid: :replace, undef: :replace, replace: "")
  case kind_of(file, forced_kind)
  when "react" then scan_react(src, file)
  when "erb" then scan_html(src, file, erb: true)
  when "script" then []
  else scan_html(src, file, erb: false)
  end
end

def inventory(path, kind)
  files = files_under(path)
  seen = {}
  files.flat_map { |f| scan_file(f, kind) }.each do |it|
    key = "#{it.verb}|#{it.label}"
    if seen[key] then seen[key].wired ||= it.wired else seen[key] = it end
  end
  { files: files.size, items: seen.values }
end

def summarize(inv)
  by_verb = Hash.new { |h, k| h[k] = { "total" => 0, "branchees" => 0, "decoratives" => 0 } }
  inv[:items].each do |it|
    b = by_verb[it.verb]
    b["total"] += 1
    it.wired ? b["branchees"] += 1 : b["decoratives"] += 1
  end
  { "fichiers" => inv[:files], "total" => inv[:items].size,
    "branchees" => inv[:items].count(&:wired),
    "decoratives" => inv[:items].reject(&:wired).size, "par_verbe" => by_verb }
end

def item_json(it)
  { "verbe" => it.verb, "libelle" => it.label, "branchee" => !!it.wired,
    "preuve" => it.evidence, "fichier" => it.file, "ligne" => it.line }
end

if mode == :scan
  abort "usage: interaction_inventory.rb <chemin> [--json]" unless opts[:target]
  inv = inventory(opts[:target], opts[:kind])
  out = summarize(inv).merge("interactions" => inv[:items].map { |i| item_json(i) })
  if opts[:json]
    puts JSON.pretty_generate(out)
  else
    puts "#{out['total']} interactions (#{out['branchees']} branchees, #{out['decoratives']} decoratives)"
    out["par_verbe"].sort_by { |_, v| -v["total"] }.each do |verb, v|
      puts format("  %-9s %3d  (%d branchees, %d decoratives)", verb, v["total"], v["branchees"], v["decoratives"])
    end
  end
  exit 0
end

abort "usage: interaction_inventory.rb compare --reference PATH --candidate PATH" unless opts[:reference] && opts[:candidate]

ref = inventory(opts[:reference], opts[:kind])
cand = inventory(opts[:candidate], opts[:kind])
cand_effective = cand[:items].select(&:wired)
ref_wired = ref[:items].select(&:wired)

def soft_match?(a, b)
  return false unless a.verb == b.verb
  return true if a.label == b.label
  return false if a.label.nil? || b.label.nil?
  a.label.include?(b.label) || b.label.include?(a.label)
end

matched_ref = []
matched_cand = []
ref_wired.each do |r|
  m = cand_effective.find { |c| !matched_cand.include?(c) && soft_match?(r, c) }
  next unless m
  matched_ref << r
  matched_cand << m
end

manquantes = ref_wired - matched_ref
inventees = cand_effective - matched_cand
regressions = cand[:items].reject(&:wired).select { |c| manquantes.any? { |r| soft_match?(r, c) } }

result = {
  "reference" => summarize(ref),
  "candidate" => summarize(cand),
  "correspondances" => matched_ref.size,
  "manquantes" => manquantes.size,
  "inventees" => inventees.size,
  "regressions_decoratives" => regressions.size,
  "rappel" => ref_wired.empty? ? 1.0 : (matched_ref.size.to_f / ref_wired.size).round(4),
  "precision" => cand_effective.empty? ? 1.0 : (matched_cand.size.to_f / cand_effective.size).round(4),
  "detail_manquantes" => manquantes.first(50).map { |i| item_json(i) },
  "detail_inventees" => inventees.first(50).map { |i| item_json(i) },
  "detail_regressions_decoratives" => regressions.first(50).map { |i| item_json(i) }
}

if opts[:json]
  puts JSON.pretty_generate(result)
else
  puts "rappel #{(result['rappel'] * 100).round(1)} % · precision #{(result['precision'] * 100).round(1)} %"
  puts "#{result['correspondances']} correspondances · #{result['manquantes']} manquantes · #{result['inventees']} inventees"
  puts "#{result['regressions_decoratives']} dessinees mais mortes"
  manquantes.first(15).each { |i| puts "  MANQUE  #{i.verb} « #{i.label} »" }
end
