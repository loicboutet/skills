#!/usr/bin/env ruby
# frozen_string_literal: true

# mockup_scan.rb - qualite de transcription des maquettes
#
#   ruby mockup_scan.rb <rails_app_dir> [options]
#
# Mesure l'HYGIENE d'un dossier app/views/mockups : palette, typographie,
# valeurs arbitraires, duplication, hygiene de contenu, volume. Avec --source,
# confronte en plus les valeurs numeriques et les couleurs produites a celles
# d'une source externe (export Lovable/Figma, CSS, TSX).
#
# Ce que le score NE dit PAS : voir SKILL.md. Un score propre prouve
# l'hygiene, pas la fidelite a la maquette source.

require "json"
require "set"
require "digest"
require "optparse"
require "strscan"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

OPTS = {
  json: false,
  tokens: nil,
  source: nil,
  top: 12,
  max_lines: 400,          # convention de l'atelier : fichiers < 400 lignes
  media_min: 150,          # au-dela, une vue sans @media ni prefixe responsive est suspecte
  dupe_window: 8,          # lignes normalisees consecutives pour un bloc duplique
  delta_e: 4.0,            # seuil de quasi-doublon colorimetrique
  jargon: nil,
  mockups_dir: nil
}

parser = OptionParser.new do |o|
  o.banner = "usage: ruby mockup_scan.rb <rails_app_dir> [options]"
  o.on("--json", "sortie JSON complete")                       { OPTS[:json] = true }
  o.on("--tokens PATH", "tailwind.config.js (sinon autodetecte)") { |v| OPTS[:tokens] = v }
  o.on("--source DIR", "dossier de la source externe (CSS/TSX/HTML)") { |v| OPTS[:source] = v }
  o.on("--top N", Integer, "nb d'ecrans detailles dans le rapport") { |v| OPTS[:top] = v }
  o.on("--max-lines N", Integer, "seuil fichier monstrueux (defaut 400)") { |v| OPTS[:max_lines] = v }
  o.on("--delta-e F", Float, "seuil quasi-doublon couleur (defaut 4.0)") { |v| OPTS[:delta_e] = v }
  o.on("--dupe-window N", Integer, "taille du bloc duplique (defaut 8)") { |v| OPTS[:dupe_window] = v }
  o.on("--jargon LISTE", "motifs de jargon interne, separes par des virgules") { |v| OPTS[:jargon] = v }
  o.on("--mockups DIR", "dossier de maquettes (sinon app/views/mockups)") { |v| OPTS[:mockups_dir] = v }
  o.on("-h", "--help") { puts o; exit 0 }
end
parser.parse!

ROOT = File.expand_path(ARGV[0] || ".")
unless File.directory?(ROOT)
  warn "mockup_scan: #{ROOT} n'est pas un dossier"
  exit 2
end

# ---------------------------------------------------------------------------
# Couleur : parsing, normalisation, distance
# ---------------------------------------------------------------------------

module Color
  HEX  = /#([0-9a-fA-F]{3,8})\b/
  RGB  = /\brgba?\(\s*([0-9.]+)\s*[, ]\s*([0-9.]+)\s*[, ]\s*([0-9.]+)\s*(?:[,\/][^)]*)?\)/i
  HSL  = /\bhsla?\(\s*([0-9.-]+)(?:deg)?\s*[, ]\s*([0-9.]+)%\s*[, ]\s*([0-9.]+)%\s*(?:[,\/][^)]*)?\)/i

  module_function

  # -> [r,g,b] 0..255, ou nil
  def from_hex(h)
    h = h.downcase
    case h.length
    when 3    then h.chars.map { |c| (c * 2).to_i(16) }
    when 4    then h.chars.first(3).map { |c| (c * 2).to_i(16) }
    when 6    then [h[0, 2], h[2, 2], h[4, 2]].map { |c| c.to_i(16) }
    when 8    then [h[0, 2], h[2, 2], h[4, 2]].map { |c| c.to_i(16) }
    end
  end

  def hsl_to_rgb(h, s, l)
    h = h.to_f % 360.0
    s = s.to_f / 100.0
    l = l.to_f / 100.0
    c = (1 - (2 * l - 1).abs) * s
    x = c * (1 - (((h / 60.0) % 2) - 1).abs)
    m = l - c / 2
    r, g, b = case h
              when 0...60    then [c, x, 0]
              when 60...120  then [x, c, 0]
              when 120...180 then [0, c, x]
              when 180...240 then [0, x, c]
              when 240...300 then [x, 0, c]
              else                [c, 0, x]
              end
    [r, g, b].map { |v| ((v + m) * 255).round.clamp(0, 255) }
  end

  # Toutes les couleurs litterales d'un texte -> [[key, rgb], ...]
  def scan_all(text)
    out = []
    text.scan(HEX) { |m| rgb = from_hex(::Regexp.last_match(1)); out << rgb if rgb }
    text.scan(RGB) { |r, g, b| out << [r, g, b].map { |v| v.to_f.round.clamp(0, 255) } }
    text.scan(HSL) { |h, s, l| out << hsl_to_rgb(h, s, l) }
    out
  end

  def key(rgb) = format("#%02x%02x%02x", *rgb)

  # sRGB -> CIE Lab (D65)
  def lab(rgb)
    r, g, b = rgb.map do |v|
      c = v / 255.0
      c > 0.04045 ? (((c + 0.055) / 1.055)**2.4) : c / 12.92
    end
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.00000
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
    f = ->(t) { t > 0.008856 ? Math.cbrt(t) : (7.787 * t) + (16.0 / 116) }
    fx, fy, fz = f[x], f[y], f[z]
    [(116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz)]
  end

  def delta_e(l1, l2)
    Math.sqrt((l1[0] - l2[0])**2 + (l1[1] - l2[1])**2 + (l1[2] - l2[2])**2)
  end
end

# ---------------------------------------------------------------------------
# Decoupage d'un fichier ERB en zones : ce qui est du code, du commentaire,
# du CSS, du texte affiche. Tout le reste du scan en depend : une couleur
# citee dans un commentaire n'est pas une couleur utilisee, un tiret cadratin
# dans un commentaire de dev n'est pas un tiret cadratin montre au client.
# ---------------------------------------------------------------------------

class ErbDoc
  Span = Struct.new(:kind, :text, :line)

  attr_reader :spans, :src, :path

  def initialize(path, src)
    @path = path
    @src = src
    @spans = []
    lex!
  end

  def lex!
    s = StringScanner.new(@src)
    line = 1
    push = lambda do |kind, text|
      @spans << Span.new(kind, text, line)
      line += text.count("\n")
    end

    until s.eos?
      if (m = s.scan(/<%#.*?%>/m))
        push.call(:erb_comment, m)
      elsif (m = s.scan(/<%=?-?(?:[^%]|%(?!>))*-?%>/m))
        push.call(:erb_code, m)
      elsif (m = s.scan(/<!--.*?-->/m))
        push.call(:html_comment, m)
      elsif (m = s.scan(%r{<style\b[^>]*>.*?</style>}mi))
        push.call(:css, m)
      elsif (m = s.scan(%r{<script\b[^>]*>.*?</script>}mi))
        push.call(:js, m)
      elsif (m = s.scan(/<[^<>]*>/m))
        push.call(:tag, m)
      elsif (m = s.scan(/[^<]+/m))
        push.call(:text, m)
      else
        push.call(:text, s.getch)
      end
    end
  end

  def of(*kinds) = @spans.select { |sp| kinds.include?(sp.kind) }

  # CSS reellement applique : blocs <style> + valeurs d'attributs style=""
  def css_text
    parts = of(:css).map { |sp| sp.text }
    style_attrs.each { |_l, v| parts << v }
    parts.join("\n")
  end

  # [[line, valeur, dynamique?], ...]
  def style_attrs
    return @style_attrs if @style_attrs

    @style_attrs = []
    of(:tag).each do |sp|
      off = 0
      sp.text.scan(/style\s*=\s*(["'])(.*?)\1/m) do
        val = ::Regexp.last_match(2)
        idx = sp.text.index(::Regexp.last_match(0), off) || 0
        off = idx + 1
        @style_attrs << [sp.line + sp.text[0, idx].count("\n"), val, val.include?("<%")]
      end
    end
    @style_attrs
  end

  # Classes CSS declarees dans les attributs class="" (ERB compris)
  def class_values
    return @class_values if @class_values

    @class_values = []
    of(:tag).each do |sp|
      sp.text.scan(/class\s*=\s*(["'])(.*?)\1/m) do
        @class_values << [sp.line, ::Regexp.last_match(2)]
      end
    end
    of(:erb_code).each do |sp|
      sp.text.scan(/class:\s*(["'])(.*?)\1/m) do
        @class_values << [sp.line, ::Regexp.last_match(2)]
      end
    end
    @class_values
  end

  # Un litteral Ruby n'est pas forcement du texte montre : chemins de partials,
  # helpers de route, listes de classes Tailwind, donnees de path SVG. On les
  # ecarte, sinon `render "mockups/shared/..."` remonte comme du jargon visible.
  SVG_PATH = /\A[MmLlHhVvCcSsQqTtAaZz0-9,.\s+-]+\z/
  IDENTIFIER = %r{\A[\w/.\-#:%\[\]@]+\z}

  def self.display_like?(lit)
    t = lit.strip
    return false if t.empty?
    return false if t.length > 4 && t.match?(SVG_PATH) && t.match?(/[A-Za-z]/)
    return false if t.match?(IDENTIFIER) && !t.match?(/\s/)

    toks = t.split(/\s+/)
    if toks.size >= 2 && t.match?(%r{\A[a-z0-9\-:/\[\]#%._ ]+\z})
      hyphenish = toks.count { |w| w.include?("-") || w.include?(":") }
      return false if hyphenish * 2 >= toks.size
    end
    true
  end

  # Texte reellement montre a l'ecran : noeuds texte + litteraux Ruby
  # (les maquettes de l'atelier posent leurs donnees fictives en tete de vue)
  def visible_runs
    return @visible_runs if @visible_runs

    runs = []
    of(:text).each do |sp|
      sp.text.split("\n").each_with_index do |l, i|
        t = l.strip
        runs << [sp.line + i, t] unless t.empty?
      end
    end
    of(:erb_code).each do |sp|
      body = sp.text.sub(/\A<%=?-?/, "").sub(/-?%>\z/, "")
      # on ignore les lignes de commentaire Ruby
      body.split("\n").each_with_index do |l, i|
        next if l.strip.start_with?("#")

        l.scan(/(["'])((?:\\.|(?!\1).)*)\1/m) do
          lit = ::Regexp.last_match(2)
          next unless ErbDoc.display_like?(lit)

          runs << [sp.line + i, lit]
        end
      end
    end
    @visible_runs = runs.sort_by(&:first)
  end

  def line_count = @src.count("\n") + 1
end

# ---------------------------------------------------------------------------
# Tokens de la charte
# ---------------------------------------------------------------------------

class Tokens
  attr_reader :colors, :sources, :custom_props, :font_families

  def initialize(root, explicit)
    @colors = {}          # key -> rgb
    @sources = []
    @custom_props = Set.new
    @font_families = Set.new

    candidates = []
    candidates << explicit if explicit
    candidates += %w[
      tailwind.config.js config/tailwind.config.js tailwind.config.ts
      app/assets/tailwind/application.css app/assets/stylesheets/application.tailwind.css
    ].map { |p| File.join(root, p) }
    candidates += Dir[File.join(root, "app/assets/stylesheets/*.css")]
    candidates += Dir[File.join(root, "doc/memory/style_guide.html")]

    candidates.uniq.each do |p|
      next unless p && File.file?(p)

      txt = File.read(p, encoding: "UTF-8", invalid: :replace, undef: :replace)
      before = @colors.size
      Color.scan_all(txt).each { |rgb| @colors[Color.key(rgb)] ||= rgb }
      txt.scan(/--([a-zA-Z0-9_-]+)\s*:/) { @custom_props << ::Regexp.last_match(1) }
      txt.scan(/font-?[fF]amily\s*[:=]\s*[\[(]?\s*['"]([^'"]+)['"]/) { @font_families << ::Regexp.last_match(1) }
      @sources << [rel(p, root), @colors.size - before]
    end

    @lab = @colors.transform_values { |rgb| Color.lab(rgb) }
  end

  def rel(p, root) = p.sub(%r{\A#{Regexp.escape(root)}/?}, "")

  def known?(key) = @colors.key?(key)

  # tolerance : une couleur a moins de 1.5 dE d'un token EST le token
  def near_token?(rgb)
    l = Color.lab(rgb)
    @lab.each_value { |tl| return true if Color.delta_e(l, tl) < 1.5 }
    false
  end

  def empty? = @colors.empty?
end

# ---------------------------------------------------------------------------
# Analyse d'un fichier
# ---------------------------------------------------------------------------

TW_FONT_SCALE_REM = [0.75, 0.875, 1.0, 1.125, 1.25, 1.5, 1.875, 2.25, 3.0, 3.75, 4.5, 6.0, 8.0].freeze

# Glyphes qui tiennent lieu d'asset : etoiles, coches, pictogrammes, drapeaux.
# Les fleches typographiques (← → ↑ ↓) sont volontairement HORS scope : dans les
# maquettes de l'atelier elles servent de « retour », pas de succedane d'icone,
# et les compter noie le signal (le cas sain en avait 40 pour 1 vrai emoji).
EMOJI_RE = /[\u{1F300}-\u{1FAFF}\u{1F000}-\u{1F0FF}\u{1F1E6}-\u{1F1FF}\u{2600}-\u{27BF}\u{2B50}\u{2B55}\u{FE0F}]/

# Jargon interne : noms d'outils, vocabulaire de fabrication, noms de fichiers
# source. Pas « mockup »/« maquette » : dans un namespace `mockups/` ces mots
# sont partout dans les chemins et ne disent rien de ce que voit le client.
DEFAULT_JARGON = [
  "lovable", "figma", "sketch", "shadcn", "storybook",
  "design system", "designsystem", "design tokens", "styleguide", "style guide",
  "pixel-perfect", "pixel perfect", "wireframe",
  "lorem ipsum", "todo:", "tbd", "fixme",
  ".tsx", ".jsx", ".scss", "index.css"
].freeze

class FileReport
  attr_reader :path, :rel, :doc, :lines
  attr_accessor :findings

  def initialize(path, rel, doc)
    @path = path
    @rel = rel
    @doc = doc
    @lines = doc.line_count
    @findings = []
  end

  def add(cat, msg, count, lines: [], severity: 1)
    @findings << { category: cat, message: msg, count: count, lines: lines.first(6), severity: severity }
  end

  def count_of(cat) = @findings.select { |f| f[:category] == cat }.sum { |f| f[:count] }
end

class Scanner
  attr_reader :files, :tokens, :root

  def initialize(root, opts)
    @root = root
    @opts = opts
    @jargon = (opts[:jargon] ? opts[:jargon].split(",").map { |s| s.strip.downcase } : DEFAULT_JARGON)
                .reject(&:empty?)
    @tokens = Tokens.new(root, opts[:tokens])
    @files = []
    @notes = []
  end

  attr_reader :notes

  def mockups_dir
    @mockups_dir ||= begin
      d = @opts[:mockups_dir] ? File.expand_path(@opts[:mockups_dir]) : File.join(@root, "app/views/mockups")
      d
    end
  end

  def collect_files
    unless File.directory?(mockups_dir)
      @notes << "Pas de dossier de maquettes (#{rel(mockups_dir)}). Rien a mesurer : ce n'est pas un feu vert."
      return []
    end
    Dir[File.join(mockups_dir, "**", "*")].select { |p| File.file?(p) && p =~ /\.(erb|html|haml|slim)\z/ }.sort
  end

  def rel(p) = p.sub(%r{\A#{Regexp.escape(@root)}/?}, "")

  def run
    paths = collect_files
    docs = paths.map do |p|
      src = File.read(p, encoding: "UTF-8", invalid: :replace, undef: :replace)
      FileReport.new(p, rel(p), ErbDoc.new(p, src))
    end
    @files = docs
    if docs.empty?
      @palette = { usage: {}, unknown: {}, clusters: [], local_props: {} }
      @dupes = []
      return self
    end
    if @tokens.empty?
      @notes << "Aucune charte lue (pas de tailwind.config.js ni de feuille de style exploitable) : " \
                "« couleurs hors charte » est alors a lire comme « couleurs en dur », sans reference."
    end

    analyse_palette(docs)
    docs.each do |fr|
      analyse_typography(fr)
      analyse_arbitrary(fr)
      analyse_hygiene(fr)
      analyse_volume(fr)
    end
    analyse_duplication(docs)
    self
  end

  # --- 1. Palette -----------------------------------------------------------

  attr_reader :palette

  def analyse_palette(docs)
    usage = Hash.new { |h, k| h[k] = { rgb: nil, count: 0, files: Hash.new(0) } }
    local_props = Hash.new { |h, k| h[k] = [] }

    docs.each do |fr|
      # une couleur ne compte que si elle est appliquee : CSS, attributs, classes,
      # markup. Jamais depuis un commentaire.
      applied = fr.doc.of(:css, :tag, :js, :erb_code).map(&:text).join("\n")
      Color.scan_all(applied).each do |rgb|
        k = Color.key(rgb)
        e = usage[k]
        e[:rgb] = rgb
        e[:count] += 1
        e[:files][fr.rel] += 1
      end
      fr.doc.of(:css).each do |sp|
        sp.text.scan(/--([a-zA-Z0-9_-]+)\s*:/) { local_props[::Regexp.last_match(1)] << fr.rel }
      end
    end

    unknown = usage.reject { |k, e| @tokens.known?(k) || @tokens.near_token?(e[:rgb]) }
    clusters = near_duplicate_clusters(usage)

    @palette = {
      usage: usage,
      unknown: unknown,
      clusters: clusters,
      local_props: local_props
    }

    # remontee par fichier
    docs.each do |fr|
      unk = unknown.select { |_k, e| e[:files].key?(fr.rel) }
      if unk.size.positive?
        top = unk.sort_by { |_k, e| -e[:files][fr.rel] }.first(6).map { |k, e| "#{k}x#{e[:files][fr.rel]}" }
        fr.add(:palette, "#{unk.size} couleurs hors charte (#{top.join(' ')})", unk.size, severity: 2)
      end
      involved = clusters.flat_map { |c| c[:colors] }.select { |k| usage[k][:files].key?(fr.rel) }
      if involved.size >= 2
        fr.add(:palette, "#{involved.size} couleurs prises dans un quasi-doublon de charte", involved.size, severity: 2)
      end
      props = local_props.select { |_n, fs| fs.include?(fr.rel) }
      if props.size >= 5
        fr.add(:palette, "#{props.size} custom properties CSS definies dans la vue elle-meme", props.size, severity: 1)
      end
    end
  end

  # Regroupement par GRAINE, pas par proche-en-proche. Une union-find sur les
  # paires enchaine de fil en aiguille et finit par mettre le blanc et l'or dans
  # le meme paquet. Ici : la couleur la plus employee sert de reference, et on
  # lui rattache celles qui sont a moins de dE d'ELLE. Le diametre du groupe
  # reste borne, et le groupe se lit « voici la couleur, voici ses sosies ».
  def near_duplicate_clusters(usage)
    keys = usage.keys.sort_by { |k| -usage[k][:count] }
    labs = keys.to_h { |k| [k, Color.lab(usage[k][:rgb])] }
    thr = @opts[:delta_e]
    taken = Set.new
    clusters = []

    keys.each do |seed|
      next if taken.include?(seed)

      taken << seed
      ls = labs[seed]
      variants = keys.select do |k|
        !taken.include?(k) && Color.delta_e(ls, labs[k]) < thr
      end
      next if variants.empty?

      variants.each { |k| taken << k }
      group = [seed] + variants.sort_by { |k| -usage[k][:count] }
      clusters << {
        seed: seed,
        colors: group,
        hits: group.sum { |k| usage[k][:count] },
        files: group.flat_map { |k| usage[k][:files].keys }.uniq
      }
    end
    clusters.sort_by { |c| [-c[:hits], -c[:colors].size] }
  end

  # --- 2. Typographie -------------------------------------------------------

  attr_reader :typo

  def analyse_typography(fr)
    css = fr.doc.css_text.gsub("&quot;", '"').gsub("&#39;", "'")
    fams = Set.new
    css.scan(/font-family\s*:\s*([^;}\n]+)/i) do
      raw = ::Regexp.last_match(1)
      first = raw.split(",").first.to_s.strip.gsub(/["']/, "")
      next if first.empty? || first.include?("&") || first.include?("<")
      next if first.start_with?("var(", "inherit", "initial", "unset")

      fams << first
    end
    fr.doc.class_values.each do |_l, v|
      v.scan(/\bfont-\[([^\]]+)\]/) { fams << ::Regexp.last_match(1).tr("_", " ").split(",").first.to_s.strip }
    end

    sizes = Set.new
    off = []
    css.scan(/font-size\s*:\s*([0-9.]+)(px|rem|em)/i) do
      v, unit = ::Regexp.last_match(1).to_f, ::Regexp.last_match(2).downcase
      rem = unit == "px" ? v / 16.0 : v
      sizes << format("%.4g%s", v, unit)
      off << format("%.4g%s", v, unit) unless TW_FONT_SCALE_REM.any? { |s| (s - rem).abs < 0.005 }
    end
    fr.doc.class_values.each do |_l, cv|
      cv.scan(/\btext-\[([0-9.]+)(px|rem)\]/) do
        v, unit = ::Regexp.last_match(1).to_f, ::Regexp.last_match(2)
        rem = unit == "px" ? v / 16.0 : v
        sizes << "#{::Regexp.last_match(1)}#{unit}"
        off << "#{::Regexp.last_match(1)}#{unit}" unless TW_FONT_SCALE_REM.any? { |s| (s - rem).abs < 0.005 }
      end
    end

    fr.instance_variable_set(:@fams, fams)
    fr.instance_variable_set(:@sizes, sizes)

    fr.add(:typo, "#{fams.size} familles de police dans un seul ecran (#{fams.to_a.sort.join(', ')})",
           fams.size, severity: 2) if fams.size >= 3
    if off.uniq.size >= 3
      fr.add(:typo, "#{off.uniq.size} tailles de police hors echelle (#{off.uniq.sort.first(6).join(' ')})",
             off.uniq.size, severity: 1)
    end
  end

  def all_font_families
    @files.flat_map { |fr| (fr.instance_variable_get(:@fams) || Set.new).to_a }.uniq.sort
  end

  def all_font_sizes
    @files.flat_map { |fr| (fr.instance_variable_get(:@sizes) || Set.new).to_a }.uniq
  end

  # --- 3. Valeurs arbitraires ----------------------------------------------

  def analyse_arbitrary(fr)
    statics = fr.doc.style_attrs.reject { |_l, _v, dyn| dyn }
    dynamics = fr.doc.style_attrs.select { |_l, _v, dyn| dyn }
    if statics.size.positive?
      fr.add(:arbitraire, "#{statics.size} attributs style=\"...\" en dur",
             statics.size, lines: statics.map(&:first), severity: 2)
    end
    fr.instance_variable_set(:@dyn_styles, dynamics.size)

    arb = []
    fr.doc.class_values.each do |l, v|
      v.scan(/(?<![\w\[])((?:[a-z-]+:)*[a-z-]+-\[[^\]\s]+\])/) { arb << [l, ::Regexp.last_match(1)] }
    end
    if arb.size >= 5
      fr.add(:arbitraire, "#{arb.size} classes Tailwind arbitraires [..] (#{arb.map(&:last).uniq.first(4).join(' ')})",
             arb.size, lines: arb.map(&:first), severity: 1)
    end
    fr.instance_variable_set(:@arb, arb)

    blocks = fr.doc.of(:css)
    if blocks.any?
      css_lines = blocks.sum { |sp| sp.text.count("\n") + 1 }
      fr.add(:arbitraire,
             "#{blocks.size} bloc(s) <style> inline, #{css_lines} lignes de CSS dans la vue",
             css_lines, lines: blocks.map(&:line), severity: 3)
      fr.instance_variable_set(:@css_lines, css_lines)
    end
  end

  # --- 4. Duplication -------------------------------------------------------

  attr_reader :dupes

  EXACT_NORM = ->(t) { t.gsub(/\s+/, " ") }
  # « quasi identique » : meme structure, textes et nombres neutralises, et pour
  # une ligne CSS le selecteur retire. Sans ce dernier point, deux feuilles de
  # style recopiees a l'identique sous deux prefixes de page (`.page-a .x{...}`
  # / `.page-b .x{...}`) ne se ressemblent plus sur une seule ligne.
  FUZZY_NORM = lambda do |t|
    t = t.gsub(/\s+/, " ").gsub(/>[^<>]*</, "><").gsub(/\d+(?:\.\d+)?/, "#")
    t = t.sub(/\A\s*\.[^{}<>]*\{/, "{") if t.include?("{") && !t.include?("<")
    t
  end

  def normalized_lines(fr, norm)
    out = []
    fr.doc.src.each_line.with_index(1) do |l, i|
      t = l.strip
      next if t.empty?
      next if t.start_with?("<%#", "<!--", "//", "/*", "*")

      out << [i, norm.call(t)]
    end
    out
  end

  # Fenetres glissantes hachees, regroupees par jeu de fichiers concernes.
  def dupe_groups(docs, norm, min_chars, kind)
    win = @opts[:dupe_window]
    index = Hash.new { |h, k| h[k] = [] }

    docs.each do |fr|
      lines = normalized_lines(fr, norm)
      next if lines.size < win

      (0..(lines.size - win)).each do |i|
        slice = lines[i, win]
        body = slice.map(&:last).join("\n")
        next if body.length < min_chars     # un bloc trop maigre n'est pas un partial

        index[Digest::SHA1.hexdigest(body)] << [fr.rel, slice.first.first, slice.last.first]
      end
    end

    merged = {}
    index.each do |_h, occ|
      files = occ.map(&:first).uniq
      next if files.size < 2

      sig = files.sort.join("|")
      merged[sig] ||= { files: files.sort, windows: [] }
      merged[sig][:windows] << occ
    end

    merged.map do |sig, m|
      covered = Hash.new { |h, k| h[k] = Set.new }
      m[:windows].each { |occ| occ.each { |f, l0, l1| (l0..l1).each { |l| covered[f] << l } } }
      block_lines = covered.values.map(&:size).min || 0
      {
        kind: kind,
        files: m[:files],
        signature: sig,
        occurrences: m[:files].size,
        block_lines: block_lines,
        recoverable: block_lines * (m[:files].size - 1),
        covered: covered,
        zones: covered.transform_values { |ls| contiguous(ls) }
      }
    end.select { |d| d[:block_lines] >= win }
  end

  def contiguous(set)
    ranges = []
    set.to_a.sort.each do |l|
      if ranges.any? && l == ranges.last[1] + 1
        ranges.last[1] = l
      else
        ranges << [l, l]
      end
    end
    ranges
  end

  def analyse_duplication(docs)
    exact = dupe_groups(docs, EXACT_NORM, 200, :identique)
    exact_sigs = exact.map { |d| d[:signature] }.to_set
    fuzzy = dupe_groups(docs, FUZZY_NORM, 250, :quasi).reject { |d| exact_sigs.include?(d[:signature]) }

    @dupes = (exact + fuzzy).sort_by { |d| -d[:recoverable] }

    @dupes.each do |d|
      d[:files].each do |f|
        fr = docs.find { |x| x.rel == f }
        next unless fr

        others = d[:files] - [f]
        zones = d[:zones][f].size
        fr.add(:duplication,
               "#{d[:block_lines]} lignes #{d[:kind] == :quasi ? 'quasi identiques' : 'identiques'} " \
               "a #{others.size} autre(s) ecran(s) en #{zones} zone(s) " \
               "(#{others.first(3).join(', ')}#{others.size > 3 ? '...' : ''}) : candidat partial",
               d[:block_lines], lines: d[:zones][f].map(&:first), severity: 2)
      end
    end
  end

  # --- 5. Hygiene -----------------------------------------------------------

  def navbar_z
    @navbar_z ||= begin
      zs = @files.select { |fr| fr.rel =~ /nav|topbar|header|sidebar/i }
                 .flat_map { |fr| fr.doc.css_text.scan(/z-index\s*:\s*(\d+)/).flatten.map(&:to_i) }
      zs.max || 100
    end
  end

  def analyse_hygiene(fr)
    # emoji et glyphes de remplacement, dans le texte affiche seulement
    emo = fr.doc.visible_runs.flat_map do |l, t|
      t.scan(EMOJI_RE).map { |g| [l, g] }
    end
    if emo.any?
      fr.add(:hygiene, "#{emo.size} emoji/glyphe a la place d'un asset (#{emo.map(&:last).uniq.first(5).join(' ')})",
             emo.size, lines: emo.map(&:first), severity: 2)
    end

    # Tiret cadratin : uniquement au milieu d'une PHRASE. Le tiret « valeur
    # vide » d'un tableau et le tiret separateur d'un titre court sont des
    # conventions typographiques, pas la signature d'un texte ecrit par une IA.
    dashes = fr.doc.visible_runs.select do |_l, t|
      next false unless t.include?("—") || t.include?("–")
      next false unless t =~ /\S\s[—–]\s\S/

      t.split(/\s+/).size >= 8
    end
    if dashes.any?
      fr.add(:hygiene, "#{dashes.size} tiret(s) cadratin dans du texte affiche",
             dashes.size, lines: dashes.map(&:first), severity: 1)
    end

    # jargon interne visible
    jarg = fr.doc.visible_runs.flat_map do |l, t|
      d = t.downcase
      @jargon.select { |j| d.include?(j) }.map { |j| [l, j, t[0, 70]] }
    end
    if jarg.any?
      fr.add(:hygiene, "#{jarg.size} occurrence(s) de jargon interne visible (#{jarg.map { |x| x[1] }.uniq.first(4).join(', ')})",
             jarg.size, lines: jarg.map(&:first), severity: 3)
    end

    # <a> imbrique
    nested = nested_anchors(fr.doc)
    fr.add(:hygiene, "#{nested.size} <a> imbrique dans un <a> (HTML invalide)", nested.size,
           lines: nested, severity: 3) if nested.any?

    # responsive absent
    css = fr.doc.css_text
    has_media = css.include?("@media")
    has_bp = fr.doc.class_values.any? { |_l, v| v =~ /\b(sm|md|lg|xl|2xl|mobile|tablet|desktop):/ }
    if fr.lines >= @opts[:media_min] && !has_media && !has_bp
      fr.add(:hygiene, "aucun responsive (#{fr.lines} lignes, ni @media ni prefixe de breakpoint)", 1, severity: 2)
    end

    # z-index au-dessus de la navbar. Une modale plein ecran a le DROIT de
    # passer par-dessus : on ecarte les selecteurs qui se nomment comme telles,
    # sinon la remontee est du bruit sur tous les projets.
    unless fr.rel =~ /nav|topbar|header/i
      over = []
      fr.doc.css_text.scan(/([^{}]+)\{([^{}]*)\}/m) do
        sel, body = ::Regexp.last_match(1).to_s, ::Regexp.last_match(2).to_s
        next if sel =~ /overlay|modal|dialog|drawer|sheet|popover|popup|toast|lightbox|backdrop|\bnav\b/i

        body.scan(/z-index\s*:\s*(\d+)/) do
          z = ::Regexp.last_match(1).to_i
          over << z if z > navbar_z
        end
      end
      over += fr.doc.class_values.flat_map { |_l, v| v.scan(/\bz-\[(\d+)\]/).flatten.map(&:to_i) }
                .select { |z| z > navbar_z }
      if over.any?
        fr.add(:hygiene,
               "#{over.size} z-index au-dessus de la navbar hors modale (#{over.uniq.sort.reverse.first(4).join(' ')} > #{navbar_z})",
               over.size, severity: 2)
      end
    end
  end

  def nested_anchors(doc)
    depth = 0
    hits = []
    doc.of(:tag).each do |sp|
      t = sp.text
      if t =~ %r{\A</\s*a\b}i
        depth -= 1 if depth.positive?
      elsif t =~ /\A<\s*a\b/i && t !~ %r{/>\z}
        hits << sp.line if depth.positive?
        depth += 1
      end
    end
    hits
  end

  # --- 6. Volume ------------------------------------------------------------

  def analyse_volume(fr)
    return unless fr.lines > @opts[:max_lines]

    fr.add(:volume, "#{fr.lines} lignes (convention de l'atelier : < #{@opts[:max_lines]})",
           fr.lines - @opts[:max_lines], severity: 2)
  end
end

# ---------------------------------------------------------------------------
# Comparaison avec la source externe (--source)
# ---------------------------------------------------------------------------

class SourceDiff
  SRC_EXT = %w[.css .scss .sass .tsx .ts .jsx .js .html .htm].freeze

  attr_reader :stats

  def initialize(dir, scanner)
    @dir = File.expand_path(dir)
    @scanner = scanner
  end

  def numbers(text)
    h = Hash.new(0)
    text.scan(/(?<![\w.-])(\d{2,4})px\b/) { h[::Regexp.last_match(1).to_i] += 1 }
    h
  end

  def run
    files = Dir[File.join(@dir, "**", "*")].select { |p| File.file?(p) && SRC_EXT.include?(File.extname(p).downcase) }
    if files.empty?
      @stats = { error: "aucun fichier source exploitable dans #{@dir}" }
      return self
    end

    src_txt = files.map { |p| File.read(p, encoding: "UTF-8", invalid: :replace, undef: :replace) }.join("\n")
    src_colors = Hash.new(0)
    Color.scan_all(src_txt).each { |rgb| src_colors[Color.key(rgb)] += 1 }
    src_px = numbers(src_txt)

    out_colors = @scanner.palette[:usage].transform_values { |e| e[:count] }
    out_px = Hash.new(0)
    @scanner.files.each do |fr|
      applied = fr.doc.of(:css, :tag, :js).map(&:text).join("\n")
      numbers(applied).each { |v, c| out_px[v] += c }
    end

    missing_colors = src_colors.reject { |k, _| out_colors.key?(k) }
                               .sort_by { |_k, c| -c }
    extra_colors   = out_colors.reject { |k, _| src_colors.key?(k) }
                               .sort_by { |_k, c| -c }
    missing_px = src_px.reject { |v, _| out_px.key?(v) }.sort_by { |_v, c| -c }
    extra_px   = out_px.reject { |v, _| src_px.key?(v) }.sort_by { |_v, c| -c }

    # le detecteur de « valeur estimee au lieu de mesuree » : une valeur du rendu
    # proche d'une valeur de la source sans lui etre egale
    # ecart >= 2px : a 1px pres c'est un arrondi de rendu, pas une estimation.
    near = extra_px.filter_map do |v, c|
      cand = src_px.keys.select { |s| (s - v).abs >= 2 && (s - v).abs <= [(v * 0.15).round, 40].min }
      next if cand.empty?

      best = cand.min_by { |s| (s - v).abs }
      { rendered: v, source: best, gap: (best - v).abs, hits: c }
    end.sort_by { |h| [-h[:hits], -h[:gap]] }

    @stats = {
      source_files: files.size,
      source_colors: src_colors.size,
      rendered_colors: out_colors.size,
      missing_colors: missing_colors,
      extra_colors: extra_colors,
      source_px: src_px.size,
      rendered_px: out_px.size,
      missing_px: missing_px,
      extra_px: extra_px,
      near_misses: near
    }
    self
  end
end

# ---------------------------------------------------------------------------
# Score de derive
# ---------------------------------------------------------------------------

class Score
  WEIGHTS = { palette: 25, typo: 10, arbitraire: 20, duplication: 15, hygiene: 20, volume: 10 }.freeze

  attr_reader :detail, :total

  def initialize(scanner, opts)
    @s = scanner
    @opts = opts
    compute
  end

  def kilo(n, lines) = lines.positive? ? (n * 1000.0 / lines) : 0.0

  def ramp(value, full)
    return 0.0 if full <= 0

    [[value / full.to_f, 0.0].max, 1.0].min
  end

  def compute
    files = @s.files
    total_lines = files.sum(&:lines)
    @detail = {}

    if files.empty? || total_lines.zero?
      @detail = WEIGHTS.transform_values { 0.0 }
      @total = 0.0
      return
    end

    pal = @s.palette
    # 1 couleur hors charte pour 40 lignes = plafond
    unknown_rate = kilo(pal[:unknown].size, total_lines)
    cluster_colors = pal[:clusters].sum { |c| c[:colors].size }
    cluster_rate = kilo(cluster_colors, total_lines)
    local_rate = kilo(pal[:local_props].size, total_lines)
    @detail[:palette] = WEIGHTS[:palette] *
                        (0.5 * ramp(unknown_rate, 12.0) + 0.3 * ramp(cluster_rate, 10.0) + 0.2 * ramp(local_rate, 4.0))

    fams = @s.all_font_families.size
    off_sizes = files.sum { |fr| fr.count_of(:typo) }
    @detail[:typo] = WEIGHTS[:typo] *
                     (0.6 * ramp([fams - 2, 0].max, 4.0) + 0.4 * ramp(kilo(off_sizes, total_lines), 8.0))

    style_attrs = files.sum { |fr| fr.doc.style_attrs.count { |_l, _v, dyn| !dyn } }
    arb_classes = files.sum { |fr| (fr.instance_variable_get(:@arb) || []).size }
    css_lines = files.sum { |fr| fr.instance_variable_get(:@css_lines).to_i }
    @detail[:arbitraire] = WEIGHTS[:arbitraire] *
                           (0.35 * ramp(kilo(style_attrs, total_lines), 20.0) +
                            0.25 * ramp(kilo(arb_classes, total_lines), 30.0) +
                            0.40 * ramp(css_lines.to_f / total_lines, 0.30))

    # Deux lectures : le volume total recuperable, et la taille du plus gros
    # bloc. Un projet sain a toujours quelques en-tetes de 10 lignes en double ;
    # un panneau de 300 lignes recopie tel quel est d'une autre nature.
    recoverable = @s.dupes.sum { |d| d[:recoverable] }
    biggest = @s.dupes.map { |d| d[:block_lines] }.max || 0
    @detail[:duplication] = WEIGHTS[:duplication] *
                            (0.6 * ramp(recoverable.to_f / total_lines, 0.10) +
                             0.4 * ramp(biggest, 150.0))

    # Deux poids : ce qui casse la page ou trahit l'atelier (emoji a la place
    # d'un asset, jargon interne visible, <a> imbrique, responsive absent,
    # z-index par-dessus la navbar) pese lourd ; le tiret cadratin, qui est une
    # question de relecture, pese peu.
    hard = files.sum { |fr| fr.findings.select { |f| f[:category] == :hygiene && f[:severity] >= 2 }.sum { |f| f[:count] } }
    soft = files.sum { |fr| fr.findings.select { |f| f[:category] == :hygiene && f[:severity] < 2 }.sum { |f| f[:count] } }
    blocking = files.sum { |fr| fr.findings.count { |f| f[:category] == :hygiene && f[:severity] >= 3 } }
    @detail[:hygiene] = WEIGHTS[:hygiene] *
                        (0.60 * ramp(kilo(hard, total_lines), 4.0) +
                         0.20 * ramp(kilo(soft, total_lines), 15.0) +
                         0.20 * ramp(blocking, 10.0))

    big_lines = files.select { |fr| fr.lines > @opts[:max_lines] }.sum(&:lines)
    @detail[:volume] = WEIGHTS[:volume] * ramp(big_lines.to_f / total_lines, 0.60)

    @total = @detail.values.sum
  end

  def verdict
    case @total
    when 0...12  then "PROPRE"
    when 12...28 then "A SURVEILLER"
    when 28...50 then "DERIVE NETTE"
    else "TRANSCRIPTION A REPRENDRE"
    end
  end
end

# ---------------------------------------------------------------------------
# Rapport
# ---------------------------------------------------------------------------

SEV_LABEL = { 3 => "!!", 2 => "! ", 1 => "  " }.freeze

def file_weight(fr)
  fr.findings.sum { |f| f[:severity] * Math.log(1 + f[:count]) }
end

scanner = Scanner.new(ROOT, OPTS).run

if scanner.files.empty?
  if OPTS[:json]
    puts JSON.pretty_generate({ root: ROOT, files: 0, notes: scanner.notes })
  else
    puts "mockup_scan — #{ROOT}"
    scanner.notes.each { |n| puts "  #{n}" }
    puts "  Aucun fichier de maquette analyse." if scanner.notes.empty?
  end
  exit 0
end

score = Score.new(scanner, OPTS)
srcdiff = OPTS[:source] ? SourceDiff.new(OPTS[:source], scanner).run : nil

total_lines = scanner.files.sum(&:lines)
pal = scanner.palette

if OPTS[:json]
  payload = {
    root: ROOT,
    mockups_dir: scanner.rel(scanner.mockups_dir),
    notes: scanner.notes,
    score: { total: score.total.round(1), verdict: score.verdict,
             detail: score.detail.transform_values { |v| v.round(1) },
             weights: Score::WEIGHTS },
    volume: {
      files: scanner.files.size,
      lines: total_lines,
      over_threshold: scanner.files.select { |fr| fr.lines > OPTS[:max_lines] }
                             .sort_by { |fr| -fr.lines }.map { |fr| { file: fr.rel, lines: fr.lines } },
      threshold: OPTS[:max_lines]
    },
    palette: {
      distinct: pal[:usage].size,
      token_sources: scanner.tokens.sources.map { |p, n| { file: p, colors: n } },
      tokens: scanner.tokens.colors.size,
      unknown: pal[:unknown].sort_by { |_k, e| -e[:count] }
                            .map { |k, e| { color: k, hits: e[:count], files: e[:files].size } },
      near_duplicate_clusters: pal[:clusters].map do |c|
        { seed: c[:seed], colors: c[:colors], hits: c[:hits], files: c[:files].size }
      end,
      local_custom_properties: pal[:local_props].map { |n, fs| { name: n, files: fs.uniq } }
    },
    typography: {
      families: scanner.all_font_families,
      sizes: scanner.all_font_sizes.sort
    },
    arbitrary: {
      style_attributes_static: scanner.files.sum { |fr| fr.doc.style_attrs.count { |_l, _v, d| !d } },
      style_attributes_dynamic: scanner.files.sum { |fr| fr.instance_variable_get(:@dyn_styles).to_i },
      arbitrary_classes: scanner.files.sum { |fr| (fr.instance_variable_get(:@arb) || []).size },
      inline_style_blocks: scanner.files.count { |fr| fr.doc.of(:css).any? },
      inline_css_lines: scanner.files.sum { |fr| fr.instance_variable_get(:@css_lines).to_i }
    },
    duplication: scanner.dupes.map do |d|
      { kind: d[:kind], files: d[:files], block_lines: d[:block_lines], recoverable: d[:recoverable],
        zones: d[:zones].transform_values { |rs| rs.map { |a, b| "#{a}-#{b}" } } }
    end,
    files: scanner.files.sort_by { |fr| -file_weight(fr) }.map do |fr|
      { file: fr.rel, lines: fr.lines, weight: file_weight(fr).round(2), findings: fr.findings }
    end,
    source_diff: srcdiff&.stats
  }
  puts JSON.pretty_generate(payload)
  exit 0
end

# --- rapport texte ----------------------------------------------------------

out = []
out << "mockup_scan — #{scanner.rel(scanner.mockups_dir)} (#{ROOT})"
out << "=" * 78
scanner.notes.each { |n| out << "  #{n}" }

over = scanner.files.select { |fr| fr.lines > OPTS[:max_lines] }.sort_by { |fr| -fr.lines }
out << ""
out << format("Volume     : %d fichiers, %d lignes, %d au-dessus de %d lignes (%d lignes concernees)",
              scanner.files.size, total_lines, over.size, OPTS[:max_lines], over.sum(&:lines))
out << format("Palette    : %d couleurs distinctes, %d hors charte, %d prises dans %d quasi-doublons",
              pal[:usage].size, pal[:unknown].size,
              pal[:clusters].sum { |c| c[:colors].size }, pal[:clusters].size)
tok_src = scanner.tokens.sources.reject { |_p, n| n.zero? }.sort_by { |_p, n| -n }
out << format("Charte lue : %d couleurs depuis %d fichier(s)%s",
              scanner.tokens.colors.size, tok_src.size,
              tok_src.empty? ? " — AUCUNE source de charte trouvee" : " : #{tok_src.first(4).map { |p, n| "#{p}(#{n})" }.join(', ')}#{tok_src.size > 4 ? ", +#{tok_src.size - 4}" : ''}")
out << format("Typo       : %d familles (%s), %d tailles distinctes",
              scanner.all_font_families.size,
              scanner.all_font_families.first(6).join(", "),
              scanner.all_font_sizes.size)
static_styles = scanner.files.sum { |fr| fr.doc.style_attrs.count { |_l, _v, d| !d } }
dyn_styles = scanner.files.sum { |fr| fr.instance_variable_get(:@dyn_styles).to_i }
arb_classes = scanner.files.sum { |fr| (fr.instance_variable_get(:@arb) || []).size }
css_files = scanner.files.select { |fr| fr.doc.of(:css).any? }
css_lines = scanner.files.sum { |fr| fr.instance_variable_get(:@css_lines).to_i }
out << format("Arbitraire : %d style=\"\" en dur (+%d dynamiques, tolerés), %d classes [..], %d blocs <style> sur %d fichiers = %d lignes de CSS",
              static_styles, dyn_styles, arb_classes, css_files.size, scanner.files.size, css_lines)
recoverable = scanner.dupes.sum { |d| d[:recoverable] }
out << format("Duplication: %d blocs partages entre plusieurs ecrans, %d lignes recuperables en partials",
              scanner.dupes.size, recoverable)
hyg_total = scanner.files.sum { |fr| fr.count_of(:hygiene) }
out << format("Hygiene    : %d signalements sur %d fichiers",
              hyg_total, scanner.files.count { |fr| fr.count_of(:hygiene).positive? })

out << ""
out << format("SCORE DE DERIVE : %.1f / 100  —  %s", score.total, score.verdict)
score.detail.each do |k, v|
  bar = "#" * (v.round.clamp(0, 40))
  out << format("   %-12s %5.1f / %-3d %s", k, v, Score::WEIGHTS[k], bar)
end
out << "   (0 = hygiene irreprochable. Le score ne dit rien de la fidelite a la source.)"

# palette detaillee
if pal[:clusters].any?
  out << ""
  out << "-- Quasi-doublons de charte (dE < #{OPTS[:delta_e]}) ------------------------"
  pal[:clusters].first(10).each do |c|
    variants = c[:colors] - [c[:seed]]
    out << format("   %s (%d usages) <- %s%s   [%d fichiers]",
                  c[:seed], pal[:usage][c[:seed]][:count],
                  variants.first(5).map { |k| "#{k}x#{pal[:usage][k][:count]}" }.join(" "),
                  variants.size > 5 ? " +#{variants.size - 5}" : "",
                  c[:files].size)
  end
  out << "   ... #{pal[:clusters].size - 10} autres groupes" if pal[:clusters].size > 10
end

if pal[:unknown].any?
  out << ""
  out << "-- Couleurs hors charte, les plus utilisees --------------------------------"
  pal[:unknown].sort_by { |_k, e| -e[:count] }.first(12).each do |k, e|
    out << format("   %-10s %4d usages  %2d fichiers  (ex: %s)", k, e[:count], e[:files].size,
                  e[:files].max_by { |_f, c| c }.first)
  end
  out << "   ... #{pal[:unknown].size - 12} autres couleurs hors charte" if pal[:unknown].size > 12
end

if scanner.dupes.any?
  out << ""
  out << "-- Duplication : candidats a l'extraction en partial -----------------------"
  scanner.dupes.first(10).each do |d|
    out << format("   %d lignes %s x %d ecrans, %d recuperables",
                  d[:block_lines], d[:kind] == :quasi ? "quasi identiques" : "identiques",
                  d[:occurrences], d[:recoverable])
    d[:zones].sort.first(4).each do |f, rs|
      shown_r = rs.sort_by { |a, b| a - b }.first(3).map { |a, b| "#{a}-#{b}" }.join(", ")
      out << format("        %s  %d zone(s) : %s%s", f, rs.size, shown_r, rs.size > 3 ? ", ..." : "")
    end
    out << format("        ... et %d autres fichiers", d[:zones].size - 4) if d[:zones].size > 4
  end
  out << "   ... #{scanner.dupes.size - 10} autres blocs" if scanner.dupes.size > 10
end

out << ""
out << "-- Ecrans les plus problematiques ------------------------------------------"
ranked = scanner.files.sort_by { |fr| -file_weight(fr) }
shown = ranked.select { |fr| fr.findings.any? }.first(OPTS[:top])
if shown.empty?
  out << "   (aucun ecran ne remonte de signalement)"
else
  shown.each do |fr|
    out << format("%s  (%d lignes)", fr.rel, fr.lines)
    fr.findings.sort_by { |f| -f[:severity] }.each do |f|
      loc = f[:lines].any? ? "  L#{f[:lines].first(4).join(',')}" : ""
      out << format("   %s %-11s %s%s", SEV_LABEL[f[:severity]], f[:category], f[:message], loc)
    end
  end
  rest = ranked.count { |fr| fr.findings.any? } - shown.size
  out << "   ... #{rest} autres ecrans avec des signalements (--top pour en voir plus)" if rest.positive?
end

clean = scanner.files.count { |fr| fr.findings.empty? }
out << ""
out << format("%d fichiers sur %d ne remontent rien.", clean, scanner.files.size)

if srcdiff
  st = srcdiff.stats
  out << ""
  out << "-- Comparaison a la source (#{OPTS[:source]}) -------------------------------"
  if st[:error]
    out << "   #{st[:error]}"
  else
    out << "   INDICATIF. Une valeur absente ici peut vivre dans un fichier source non lu,"
    out << "   ou avoir ete volontairement changee. A lire comme une piste, pas un verdict."
    out << format("   %d fichiers source lus. Couleurs : %d dans la source, %d dans le rendu.",
                  st[:source_files], st[:source_colors], st[:rendered_colors])
    out << format("   %d couleurs de la source absentes du rendu, %d couleurs du rendu absentes de la source.",
                  st[:missing_colors].size, st[:extra_colors].size)
    out << format("   Valeurs px : %d distinctes dans la source, %d dans le rendu ; %d de la source absentes, %d du rendu absentes de la source.",
                  st[:source_px], st[:rendered_px], st[:missing_px].size, st[:extra_px].size)
    if st[:near_misses].any?
      out << ""
      out << "   Valeurs proches sans etre egales (estimation probable au lieu de mesure) :"
      st[:near_misses].first(15).each do |n|
        out << format("      rendu %dpx  vs source %dpx  (ecart %d, %d usages)",
                      n[:rendered], n[:source], n[:gap], n[:hits])
      end
      out << format("      ... %d autres", st[:near_misses].size - 15) if st[:near_misses].size > 15
    end
    if st[:missing_colors].any?
      out << ""
      out << "   Couleurs de la source jamais reprises (top) :"
      st[:missing_colors].first(10).each { |k, c| out << format("      %-10s %d occurrences dans la source", k, c) }
    end
  end
end

puts out.join("\n")
