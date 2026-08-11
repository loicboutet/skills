#!/usr/bin/env ruby
# frozen_string_literal: true

# charte_scan.rb — audit MECANIQUE d'une charte (`charte/style_guide.html` +
# `charte/tailwind.config.js`), pour l'etape de review qui precede les mockups.
#
# Pourquoi cet outil existe (mesure C6, 08/2026). Le consommateur d'ecran
# n'applique pas les regles qu'on lui ecrit : il imite l'artefact qu'on lui
# donne. Les deux chartes les plus sales de la passe C6 (71 et 112 classes
# arbitraires) ont donne les deux ecrans les plus sales (51 et 41), dans deux
# bras differents et a 56 % et 97 % de couverture. La proprete de la charte est
# donc un levier, et un levier ne sert que s'il est MESURE, pas apprecie.
#
# Il ne reecrit rien : `Color` (hex/rgb/hsl, distance CIELAB) et `ErbDoc`
# (decoupage code / commentaire / CSS / texte) sont charges depuis
# `mockup_scan.rb`, exactement comme `normaliser.rb` le fait. Le score de derive
# et les grappes de quasi-doublons viennent de `mockup_scan.rb --json`, la
# couverture de `charte_score.py`. Ce que charte_scan ajoute, c'est la LISTE
# actionnable : quelle classe, a quelle ligne, quelle valeur, quel token
# proposer. Un compteur ne se corrige pas ; une ligne, si.
#
# usage :
#   ruby charte_scan.rb <dossier_charte | style_guide.html> [options]
#     --json            sortie JSON complete
#     --tokens PATH     tailwind.config.js (sinon <dossier>/tailwind.config.js)
#     --delta-e F       seuil de quasi-doublon couleur (defaut 4.0, comme mockup_scan)
#     --sans-couverture ne pas appeler charte_score.py
#
# BRUYANT. Toute impossibilite de mesurer arrete l'outil avec un code de sortie
# non nul et un message sur stderr. Il n'existe aucun chemin par lequel un
# fichier illisible, un mockup_scan en echec ou un HTML sans un seul attribut
# `class` ressorte en « rien detecte » : c'est la panne qu'on a payee trois fois
# sur ce banc (facade_scan silencieux, scrollWidth faux vert, alpha des ombres).

require "json"
require "set"
require "optparse"
require "strscan"

# --- Color / ErbDoc / Tokens, charges depuis mockup_scan.rb -----------------
SCAN = [
  File.join(__dir__, "mockup_scan.rb"),
  File.expand_path("~/.claude/skills/outils-recette/mockup_scan.rb"),
  File.expand_path("~/.nexrai/skills/outils-recette/mockup_scan.rb")
].find { |p| File.file?(p) }
abort "charte_scan: mockup_scan.rb introuvable" unless SCAN
HEAD = File.read(SCAN)[/\A(.*?)^# -{10,}\n# Analyse d'un fichier/m, 1]
abort "charte_scan: mockup_scan.rb, marqueur de fin d'entete introuvable" unless HEAD

OPT = { json: false, tokens: nil, delta_e: 4.0, couverture: true }
rest = OptionParser.new do |o|
  o.banner = "usage: ruby charte_scan.rb <dossier_charte|style_guide.html> [options]"
  o.on("--json")                  { OPT[:json] = true }
  o.on("--tokens PATH")           { |v| OPT[:tokens] = v }
  o.on("--delta-e F", Float)      { |v| OPT[:delta_e] = v }
  o.on("--sans-couverture")       { OPT[:couverture] = false }
  o.on("-h", "--help")            { puts o; exit 0 }
end.parse(ARGV.dup)

cible = rest[0] or abort "usage: ruby charte_scan.rb <dossier_charte|style_guide.html> [--json]"
cible = File.expand_path(cible)
abort "charte_scan: #{cible} n'existe pas" unless File.exist?(cible)

DIR   = File.directory?(cible) ? cible : File.dirname(cible)
GUIDE = if File.directory?(cible)
          g = Dir[File.join(cible, "*.html")].sort
          abort "charte_scan: aucun .html dans #{cible}" if g.empty?
          g
        else
          [cible]
        end
TOKENS_PATH = OPT[:tokens] || File.join(DIR, "tailwind.config.js")

ARGV.replace([DIR])                     # mockup_scan lit ARGV[0] comme racine
eval(HEAD, TOPLEVEL_BINDING, SCAN, 1)   # rubocop:disable Security/Eval

%w[Color ErbDoc Tokens].each do |k|
  abort "charte_scan: #{k} absent de l'entete de mockup_scan.rb" unless Object.const_defined?(k)
end

# ---------------------------------------------------------------------------
# 0. Lecture
# ---------------------------------------------------------------------------

DOCS = GUIDE.map do |p|
  src = File.read(p, encoding: "UTF-8", invalid: :replace, undef: :replace)
  abort "charte_scan: #{p} est vide" if src.strip.empty?
  [File.basename(p), ErbDoc.new(p, src), src]
end

# Garde-fou anti-scan-muet : une charte, c'est du HTML avec des classes.
total_class_attrs = DOCS.sum { |_n, d, _s| d.class_values.size }
if total_class_attrs.zero?
  warn "charte_scan: 0 attribut class=\"\" lu dans #{GUIDE.join(', ')} — le lexer n'a rien vu."
  warn "charte_scan: c'est une panne d'outil, pas une charte propre. Verifier l'encodage / le HTML."
  exit 3
end

TOK = File.file?(TOKENS_PATH) ? Tokens.new(DIR, TOKENS_PATH) : nil
warn "charte_scan: #{TOKENS_PATH} absent — la colonne « hors token » sera vide" if TOK.nil?

# ---------------------------------------------------------------------------
# 1. Classes arbitraires : la liste, pas le compteur
#     meme regex que mockup_scan (analyse_arbitrary), meme perimetre
# ---------------------------------------------------------------------------

ARB_RE = /(?<![\w\[])((?:[a-z-]+:)*[a-z-]+-\[[^\]\s]+\])/

arb = Hash.new { |h, k| h[k] = { count: 0, lignes: [], fichiers: Set.new } }
DOCS.each do |name, doc, _src|
  doc.class_values.each do |l, v|
    v.scan(ARB_RE) do
      c = ::Regexp.last_match(1)
      e = arb[c]
      e[:count] += 1
      e[:lignes] << l
      e[:fichiers] << name
    end
  end
end
arb_total = arb.values.sum { |e| e[:count] }

# La valeur enfermee dans les crochets : c'est elle qu'il faut nommer.
def valeur_de(classe) = classe[/\[([^\]]+)\]/, 1]

# ---------------------------------------------------------------------------
# 2. style="" en dur (les dynamiques <%= %> sont tolerees, comme mockup_scan)
# ---------------------------------------------------------------------------

styles = []
DOCS.each do |name, doc, _src|
  doc.style_attrs.each do |l, v, dyn|
    next if dyn

    styles << { fichier: name, ligne: l, valeur: v.gsub(/\s+/, " ").strip }
  end
end

# ---------------------------------------------------------------------------
# 3. Valeurs employees et non nommees
#     couleurs appliquees absentes de la config, et valeurs litterales posees
#     dans les classes arbitraires (longueurs, tailles, poids...)
# ---------------------------------------------------------------------------

usage = Hash.new { |h, k| h[k] = { rgb: nil, count: 0 } }
DOCS.each do |_name, doc, _src|
  applied = doc.of(:css, :tag, :js, :erb_code).map(&:text).join("\n")
  Color.scan_all(applied).each do |rgb|
    e = usage[Color.key(rgb)]
    e[:rgb] = rgb
    e[:count] += 1
  end
end

hors_token = if TOK
               usage.reject { |k, e| TOK.known?(k) || TOK.near_token?(e[:rgb]) }
                    .map { |k, e| { couleur: k, occurrences: e[:count] } }
                    .sort_by { |h| -h[:occurrences] }
             else
               []
             end

# custom properties CSS definies dans le guide lui-meme : une valeur nommee
# hors de la config est une valeur que l'aval ne peut pas consommer.
props_locales = Hash.new(0)
DOCS.each do |_name, doc, _src|
  doc.of(:css).each do |sp|
    sp.text.scan(/--([a-zA-Z0-9_-]+)\s*:/) { props_locales[::Regexp.last_match(1)] += 1 }
  end
end
props_locales.reject! { |n, _| TOK && TOK.custom_props.include?(n) }

valeurs_litterales = arb.map { |c, e| { classe: c, valeur: valeur_de(c), occurrences: e[:count] } }
                        .sort_by { |h| -h[:occurrences] }

# ---------------------------------------------------------------------------
# 4. Quasi-doublons de couleur (ΔE CIELAB) — meme regroupement par graine que
#     mockup_scan / normaliser : la couleur la plus employee sert de reference.
# ---------------------------------------------------------------------------

def grappes(usage, seuil)
  keys = usage.keys.sort_by { |k| -usage[k][:count] }
  labs = keys.to_h { |k| [k, Color.lab(usage[k][:rgb])] }
  taken = Set.new
  out = []
  keys.each do |seed|
    next if taken.include?(seed)

    taken << seed
    variants = keys.select { |k| !taken.include?(k) && Color.delta_e(labs[seed], labs[k]) < seuil }
    next if variants.empty?

    variants.each { |k| taken << k }
    out << {
      reference: seed,
      sosies: variants.sort_by { |k| -usage[k][:count] }.map do |k|
        { couleur: k, delta_e: Color.delta_e(labs[seed], labs[k]).round(2), occurrences: usage[k][:count] }
      end
    }
  end
  out
end

clusters = grappes(usage, OPT[:delta_e])

# ---------------------------------------------------------------------------
# 5. Derive et couverture : delegues, pas reecrits
# ---------------------------------------------------------------------------

def sh(cmd)
  out = IO.popen(cmd, err: [:child, :out], &:read)
  [out, $?.exitstatus]
end

scan_cmd = ["ruby", SCAN, DIR, "--mockups", DIR, "--json", "--delta-e", OPT[:delta_e].to_s]
scan_cmd += ["--tokens", TOKENS_PATH] if File.file?(TOKENS_PATH)
raw, code = sh(scan_cmd)
abort "charte_scan: mockup_scan a echoue (#{code}) :\n#{raw[0, 800]}" unless code.zero?
begin
  ms = JSON.parse(raw)
rescue JSON::ParserError => e
  abort "charte_scan: sortie mockup_scan illisible (#{e.message}) :\n#{raw[0, 800]}"
end

# Coherence entre les deux lectures : si mon compte de classes arbitraires ne
# retombe pas sur celui de mockup_scan, l'un des deux ment. On s'arrete.
ms_arb = ms.dig("arbitrary", "arbitrary_classes")
if ms_arb != arb_total
  abort "charte_scan: incoherence, #{arb_total} classes arbitraires ici contre #{ms_arb} " \
        "pour mockup_scan sur le meme dossier. Corriger l'outil avant de lire un chiffre."
end
ms_style = ms.dig("arbitrary", "style_attributes_static")
if ms_style != styles.size
  abort "charte_scan: incoherence, #{styles.size} style= ici contre #{ms_style} pour mockup_scan."
end

couverture = nil
if OPT[:couverture]
  cs = [
    File.join(__dir__, "charte_score.py"),
    File.expand_path("~/.claude/skills/outils-recette/charte_score.py"),
    File.expand_path("~/.nexrai/skills/outils-recette/charte_score.py"),
    File.expand_path("~/skill-lab-candidates/lab/creation/harness/charte_score.py")
  ].find { |p| File.file?(p) }
  if cs
    # charte_score.py attend le dossier CANDIDAT (qui contient charte/)
    cand = File.basename(DIR) == "charte" ? File.dirname(DIR) : DIR
    out, c = sh(["python3", cs, cand])
    if c.zero?
      begin
        j = JSON.parse(out)[0]
        couverture = {
          pct: j["couverture_pct"], n: j["couverture_n"], total: j["couverture_total"],
          manques: j["manques"]
        }
      rescue StandardError => e
        warn "charte_scan: couverture illisible (#{e.message})"
      end
    else
      warn "charte_scan: charte_score.py a echoue (#{c})"
    end
  end
end

# ---------------------------------------------------------------------------
# Sortie
# ---------------------------------------------------------------------------

result = {
  "charte" => DIR,
  "fichiers" => GUIDE.map { |p| { fichier: File.basename(p), lignes: File.read(p).count("\n") + 1 } },
  "derive" => { "total" => ms.dig("score", "total"), "verdict" => ms.dig("score", "verdict"),
                "detail" => ms["score"]["detail"] },
  "classes_arbitraires" => {
    "total" => arb_total,
    "distinctes" => arb.size,
    "liste" => arb.sort_by { |_c, e| -e[:count] }.map do |c, e|
      { classe: c, valeur: valeur_de(c), occurrences: e[:count],
        lignes: e[:lignes].sort.uniq.first(20), fichiers: e[:fichiers].to_a }
    end
  },
  "style_en_dur" => { "total" => styles.size, "liste" => styles },
  "valeurs_non_nommees" => {
    "couleurs_hors_token" => hors_token,
    "custom_properties_locales" => props_locales.map { |n, c| { nom: n, occurrences: c } },
    "litteraux_dans_classes" => valeurs_litterales
  },
  "quasi_doublons" => { "seuil_delta_e" => OPT[:delta_e], "grappes" => clusters },
  "couverture" => couverture,
  "tokens" => { "fichier" => (File.file?(TOKENS_PATH) ? TOKENS_PATH : nil),
                "couleurs" => TOK ? TOK.colors.size : 0 }
}

if OPT[:json]
  puts JSON.pretty_generate(result)
  exit 0
end

def bandeau(t) = puts("\n#{t}\n#{'-' * t.length}")

puts "charte_scan — #{DIR}"
puts "=" * 78
puts format("Derive        : %.1f / 100  (%s)", result["derive"]["total"], result["derive"]["verdict"])
puts "Fichiers      : #{result['fichiers'].map { |f| "#{f[:fichier]} (#{f[:lignes]} l.)" }.join(', ')}"
puts "Tokens lus    : #{result['tokens']['couleurs']} couleurs depuis #{TOKENS_PATH}" if TOK
if couverture
  puts "Couverture    : #{couverture[:n]}/#{couverture[:total]} (#{couverture[:pct]} %)"
end

bandeau "1. Classes arbitraires  (#{arb_total} occurrences, #{arb.size} distinctes)"
if arb_total.zero?
  puts "   aucune."
else
  result["classes_arbitraires"]["liste"].each do |h|
    puts format("   %-34s x%-3d  L%s", h[:classe], h[:occurrences], h[:lignes].join(","))
  end
  puts "\n   -> chaque valeur entre crochets doit devenir un token nomme dans tailwind.config.js,"
  puts "      ou disparaitre au profit d'un token existant. Une valeur inline dans la charte"
  puts "      autorise la meme chose dans tous les ecrans qui la lisent."
end

bandeau "2. style=\"\" en dur  (#{styles.size})"
if styles.empty?
  puts "   aucun."
else
  styles.first(40).each { |s| puts format("   %s:%-5d %s", s[:fichier], s[:ligne], s[:valeur][0, 90]) }
  puts "   ... et #{styles.size - 40} autres" if styles.size > 40
end

bandeau "3. Valeurs non nommees"
puts "   couleurs appliquees absentes des tokens : #{hors_token.size}"
hors_token.first(20).each { |h| puts format("     %s  x%d", h[:couleur], h[:occurrences]) }
puts "   custom properties CSS definies dans le guide : #{props_locales.size}"
props_locales.first(20).each { |n, c| puts format("     --%s  x%d", n, c) }
puts "   valeurs litterales enfermees dans une classe [..] : #{valeurs_litterales.size} distinctes"
valeurs_litterales.first(15).each { |h| puts format("     %-24s <- %s", h[:valeur].to_s, h[:classe]) }

bandeau "4. Quasi-doublons de couleur  (ΔE < #{OPT[:delta_e]}, CIELAB)"
if clusters.empty?
  puts "   aucun."
else
  clusters.each do |c|
    puts "   #{c[:reference]} (reference, x#{usage[c[:reference]][:count]})"
    c[:sosies].each { |s| puts format("     ~ %s  ΔE %.2f  x%d", s[:couleur], s[:delta_e], s[:occurrences]) }
  end
  puts "\n   -> deux couleurs a moins de #{OPT[:delta_e]} ΔE ne se distinguent pas a l'oeil :"
  puts "      c'est UN token, pas deux. Fusionner est une decision de design, jamais un calcul."
end

if couverture && couverture[:manques] && !couverture[:manques].empty?
  bandeau "5. Trous de couverture  (#{couverture[:manques].size})"
  couverture[:manques].each { |m| puts "   #{m}" }
end

puts
puts "Verdict mecanique : #{arb_total} classes arbitraires, #{styles.size} style= en dur, " \
     "#{clusters.size} grappe(s), #{hors_token.size} couleur(s) hors token."
