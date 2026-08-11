#!/usr/bin/env ruby
# frozen_string_literal: true

# normaliser.rb — la passe de NORMALISATION MECANIQUE, entre la transcription
# en valeurs litterales et la suite de la chaine.
#
# Pourquoi cet outil existe (mesure 08/2026). Demander
# a l'agent qui transcrit de poser des tokens en meme temps qu'il transcrit lui
# fait perdre 15 points de fidelite : il avait la valeur exacte sous les yeux et
# l'interdiction ecrite d'arrondir, et il a arrondi 4 couleurs sur 18 et 7
# longueurs sur 20. Un menu de tokens invite a substituer, meme interdit.
#
# La conclusion n'est pas « pas de tokens », c'est « pas dans la meme passe ».
# Cette passe-ci est CALCULEE, pas redigee :
#
#   - une valeur employee dans PLUSIEURS vues du lot devient un token ;
#     une valeur employee dans UNE SEULE vue reste litterale ;
#   - la substitution remplace une valeur PAR ELLE-MEME nommee. Elle ne peut
#     donc pas arrondir : c'est ce qui la rend sure la ou le prompt echoue ;
#   - les quasi-doublons (deux ors a 2 dE) sont SIGNALES pour arbitrage, jamais
#     fusionnes en silence : fusionner deux ors proches est une decision de
#     design, pas un calcul.
#
# Trois familles, trois regimes :
#
#   | couleur     | egalite stricte de rendu, aucun arrondi                    |
#   | longueur px | egalite stricte. L'accroche a +-1 px de la doctrine design |
#   |             | CHANGE le rendu : elle est SIGNALEE dans le rapport, pas    |
#   |             | appliquee. Arbitrer un pixel est une decision, pas un calcul|
#   | ombre       | egalite stricte sur le vecteur complet ; les niveaux        |
#   |             | d'elevation sont PROPOSES dans le rapport, jamais imposes   |
#
# Il ne reecrit PAS le parsing : `Color` et `ErbDoc` sont charges depuis
# `mockup_scan.rb` (meme lecture hex/rgb/hsl, meme distance Lab, meme decoupage
# de l'ERB en zones). Une couleur citee dans un commentaire n'est pas une
# couleur employee, et cet outil ne la voit pas non plus.
#
# usage :
#   ruby normaliser.rb --charte charte.css --sortie DIR [options] VUE...
#
#   --charte PATH     la charte produite (et relue si elle existe deja)
#   --sortie DIR      ou ecrire les vues normalisees (defaut : en place)
#   --rapport PATH    rapport markdown (defaut : a cote de la charte)
#   --json PATH       le meme rapport en JSON
#   --seuil N         nb de vues a partir duquel une valeur est systemique (2)
#   --prefixe P       prefixe des tokens (defaut `ch`, pour « charte »)
#   --sans-px         ne normalise pas les longueurs
#   --sans-ombre      ne normalise pas les ombres
#   --delta-e F       seuil de quasi-doublon couleur signale (4.0, comme
#                     mockup_scan)
#
# BRUYANT : toute incoherence interne (un total qui ne se recalcule pas depuis
# sa liste, une reecriture qui ne se relit pas a l'identique) arrete l'outil au
# lieu de rendre un resultat a moitie juste.

require "set"
require "optparse"
require "json"
require "strscan"
require "fileutils"
require "tmpdir"

# --- Color / ErbDoc, charges depuis mockup_scan.rb --------------------------
SCAN = [
  File.expand_path("~/.claude/skills/outils-recette/mockup_scan.rb"),
  File.expand_path("~/.nexrai/skills/outils-recette/mockup_scan.rb")
].find { |p| File.file?(p) }
abort "normaliser.rb : mockup_scan.rb introuvable" unless SCAN
HEAD = File.read(SCAN)[/\A(.*?)^# -{10,}\n# Analyse d'un fichier/m, 1]
abort "normaliser.rb : mockup_scan.rb, marqueur de fin d'entete introuvable" unless HEAD

OPT = {
  charte: nil, sortie: nil, rapport: nil, json: nil, seuil: 2,
  prefixe: "ch", px: true, ombre: true, delta_e: 4.0
}
rest = OptionParser.new do |o|
  o.on("--charte PATH")   { |v| OPT[:charte] = v }
  o.on("--sortie DIR")    { |v| OPT[:sortie] = v }
  o.on("--rapport PATH")  { |v| OPT[:rapport] = v }
  o.on("--json PATH")     { |v| OPT[:json] = v }
  o.on("--seuil N", Integer)     { |v| OPT[:seuil] = v }
  o.on("--prefixe P")            { |v| OPT[:prefixe] = v }
  o.on("--sans-px")              { OPT[:px] = false }
  o.on("--sans-ombre")           { OPT[:ombre] = false }
  o.on("--delta-e F", Float)     { |v| OPT[:delta_e] = v }
end.parse(ARGV.dup)

abort "usage: normaliser.rb --charte charte.css [--sortie DIR] VUE..." if OPT[:charte].nil? || rest.empty?

VUES = rest.flat_map { |p| File.directory?(p) ? Dir[File.join(p, "*.erb")].sort : [p] }
           .select { |p| File.file?(p) }
abort "normaliser.rb : aucune vue a normaliser" if VUES.empty?

ARGV.replace([Dir.pwd])                 # mockup_scan lit ARGV[0] comme racine
eval(HEAD, TOPLEVEL_BINDING, SCAN, 1)   # rubocop:disable Security/Eval

PREF = OPT[:prefixe]
VAR_CHARTE = /var\(\s*--#{Regexp.escape(PREF)}-([A-Za-z0-9_-]+)\s*\)/

# ---------------------------------------------------------------------------
# 1. Valeurs : identite de RENDU, et graphie canonique
#
# Deux graphies qui rendent la meme chose sont la meme valeur (`#FFF` et
# `#ffffff`, `rgba(0,0,0,.08)` et `rgba(0, 0, 0, 0.08)`). C'est ce qui autorise
# a substituer sans changer un pixel. Deux valeurs qui rendent differemment ne
# sont JAMAIS confondues, meme a 0,5 dE.
# ---------------------------------------------------------------------------

COULEUR_RE = /#[0-9a-fA-F]{3,8}\b|\brgba?\([^()]*\)|\bhsla?\([^()]*\)/
PX_RE      = /(?<![\w.#$-])(\d{1,4}(?:\.\d+)?)px\b/

module Valeur
  module_function

  # texte d'une couleur -> [r, g, b, a] ou nil
  def couleur_rgba(txt)
    t = txt.strip
    if t.start_with?("#")
      h = t[1..].downcase
      case h.length
      when 3 then return h.chars.map { |c| (c * 2).to_i(16) } + [1.0]
      when 4 then return h[0, 3].chars.map { |c| (c * 2).to_i(16) } + [(h[3] * 2).to_i(16) / 255.0]
      when 6 then return [h[0, 2], h[2, 2], h[4, 2]].map { |c| c.to_i(16) } + [1.0]
      when 8 then return [h[0, 2], h[2, 2], h[4, 2]].map { |c| c.to_i(16) } + [h[6, 2].to_i(16) / 255.0]
      else return nil
      end
    end
    inner = t[/\(([^()]*)\)/, 1] or return nil
    parts = inner.split(%r{[,/]}).map(&:strip).reject(&:empty?)
    parts = parts.first.split(/\s+/) + parts[1..].to_a if parts.size < 3
    return nil if parts.size < 3

    alpha = parts[3] ? alpha_de(parts[3]) : 1.0
    return nil if alpha.nil?

    if t.downcase.start_with?("hsl")
      h = parts[0].sub(/deg\z/, "").to_f
      s = parts[1].delete("%").to_f
      l = parts[2].delete("%").to_f
      rgb = Color.hsl_to_rgb(h, s, l)
    else
      rgb = parts[0, 3].map do |v|
        v.end_with?("%") ? (v.delete("%").to_f * 2.55).round.clamp(0, 255) : v.to_f.round.clamp(0, 255)
      end
    end
    rgb + [alpha]
  end

  def alpha_de(v)
    return nil unless v.match?(/\A[0-9.%]+\z/)

    v.end_with?("%") ? v.delete("%").to_f / 100.0 : v.to_f
  end

  # la graphie que la charte porte pour cette valeur
  def couleur_texte(rgba)
    r, g, b, a = rgba
    return format("#%02x%02x%02x", r, g, b) if (a - 1.0).abs < 1e-9

    "rgba(#{r}, #{g}, #{b}, #{format('%g', a.round(4))})"
  end

  def couleur_cle(rgba)
    r, g, b, a = rgba
    format("couleur:%d,%d,%d,%.4f", r, g, b, a)
  end

  def px_cle(n) = "px:#{format('%g', n)}"
  def px_texte(n) = "#{format('%g', n)}px"

  # une ombre est un vecteur, pas une valeur : on canonicalise couche par couche
  def ombre_canon(val)
    couches = decoupe_virgules(val).map do |couche|
      c = couche.strip.gsub(/\s+/, " ")
      c = c.gsub(COULEUR_RE) { |m| (rgba = couleur_rgba(m)) ? couleur_texte(rgba) : m }
      c.gsub(/(?<![\w.#-])0px\b/, "0").downcase.gsub(/#([0-9a-f]{6})/) { "##{Regexp.last_match(1)}" }
    end
    couches.join(", ")
  end

  # decoupe sur les virgules de premier niveau (les rgba() en contiennent)
  def decoupe_virgules(val)
    out = []
    prof = 0
    cur = +""
    val.each_char do |ch|
      case ch
      when "(" then prof += 1; cur << ch
      when ")" then prof -= 1; cur << ch
      when ","
        if prof.zero?
          out << cur
          cur = +""
        else
          cur << ch
        end
      else cur << ch
      end
    end
    out << cur
    out.reject { |s| s.strip.empty? }
  end
end

# forme « rendu-canonique » d'un texte : c'est l'invariant que la
# normalisation promet de ne pas changer.
def canon_rendu(txt)
  txt.gsub(COULEUR_RE) do |m|
    rgba = Valeur.couleur_rgba(m)
    rgba ? Valeur.couleur_texte(rgba) : m
  end.gsub(PX_RE) { "#{format('%g', Regexp.last_match(1).to_f)}px" }
end

# ---------------------------------------------------------------------------
# 2. Les zones ou une valeur est APPLIQUEE
#
# `ErbDoc` decoupe deja le fichier en code ERB, commentaires, CSS, balises,
# texte. On ne touche qu'a deux choses : le contenu des blocs `<style>` et la
# valeur des attributs `style=""`. Jamais un commentaire (ce n'est pas
# applique), jamais le bloc `<% %>` de donnees fictives (ce n'est pas du style),
# jamais un `<script>` (un `var()` dans une comparaison JS ne veut rien dire),
# jamais un attribut de presentation SVG (`fill="#A38543"` n'accepte pas
# `var()`). Ces deux derniers cas sont comptes et NOMMES dans le rapport comme
# valeurs laissees litterales : ils ne disparaissent pas, ils sont declares.
# ---------------------------------------------------------------------------

Zone = Struct.new(:debut, :fin, :genre)

def zones_appliquees(src)
  doc = ErbDoc.new("x", src)
  zones = []
  off = 0
  doc.spans.each do |sp|
    case sp.kind
    when :css
      corps = sp.text[/\A<style\b[^>]*>/m]
      d = off + (corps ? corps.length : 0)
      f = off + sp.text.length - (sp.text[%r{</style>\s*\z}mi]&.length || 0)
      zones << Zone.new(d, f, :css) if f > d
    when :tag
      pos = 0
      while (m = sp.text.match(/style\s*=\s*(["'])(.*?)\1/m, pos))
        zones << Zone.new(off + m.begin(2), off + m.end(2), :attr)
        pos = m.end(0)
      end
    end
    off += sp.text.length
  end
  zones
end

# applique un bloc a chaque zone appliquee et rend le source reecrit
def transformer(src)
  zones = zones_appliquees(src)
  out = +""
  prev = 0
  zones.each do |z|
    out << src[prev...z.debut]
    out << yield(src[z.debut...z.fin], z.genre)
    prev = z.fin
  end
  out << src[prev..].to_s
  out
end

# --- protection : ce qui, dans une zone, n'est pas une valeur CSS ------------
NUL = 0.chr

# Masquage de ce qui, dans une zone de style, n'est pas une valeur : code ERB,
# chaines, url(), var(). Deux masquages s'imbriquent (une url contient une
# chaine) et deux instances coexistent (la zone, puis la valeur d'une seule
# declaration) : chaque instance porte donc sa propre etiquette et ne restitue
# QUE ses masques. Sans ca, la seconde instance rendrait les masques de la
# premiere avec son magasin a elle, et le fichier sortirait corrompu.
class Protection
  @@suivant = 0

  def initialize
    @store = []
    @@suivant += 1
    @tag = @@suivant
    @motif = /#{NUL}#{@tag}-(\d+)#{NUL}/
  end

  def masquer(txt, *regexes)
    regexes.reduce(txt) do |t, re|
      t.gsub(re) do |m|
        @store << m
        "#{NUL}#{@tag}-#{@store.size - 1}#{NUL}"
      end
    end
  end

  def rendre(txt)
    8.times do
      break unless txt.match?(@motif)

      txt = txt.gsub(@motif) do
        j = Regexp.last_match(1).to_i
        raise "Protection : masque #{j} inconnu" if @store[j].nil?

        @store[j]
      end
    end
    raise "Protection : masque non restitue" if txt.match?(@motif)

    txt
  end
end

ERB_RE   = /<%.*?%>/m
# Une chaine CSS ne traverse pas une fin de ligne. Sans cette borne, la moindre
# apostrophe francaise ouvre une fausse chaine qui court jusqu'a la suivante :
# mesure faite le 11/08, le commentaire `/* Selecteur d'annonce */` masquait
# 21 declarations d'un coup, qui ressortaient non normalisees.
CHAINE_RE = /"[^"\n]*"|'[^'\n]*'/
# … et les commentaires sont masques AVANT les chaines, pour la meme raison.
COMMENT_CSS_RE = %r{/\*.*?\*/}m
URL_RE   = /\burl\([^)]*\)/i
VAR_RE   = /\bvar\(\s*--[A-Za-z0-9_-]+\s*(?:,[^()]*)?\)/

# parcourt les declarations `prop: valeur` d'une zone.
# Le motif exige un terminateur `;` ou `}` : un prelude de media query
# (`@media (max-width:900px){`) n'en a pas, il est donc naturellement saute.
# C'est voulu : `var()` est interdit dans une media query.
DECL_RE = /(^|[;{}\s])([-A-Za-z_][\w-]*)(\s*:\s*)([^;{}]*?)(?=\s*[;}])/m

def parcourir_declarations(zone_txt, genre)
  p = Protection.new
  # Masque AVANT le decoupage en declarations : une `url(data:image/svg+xml;…)`
  # porte un point-virgule qui couperait la declaration en deux, et une chaine
  # (`content: "#fff"`) n'est pas une valeur de style.
  txt = p.masquer(zone_txt, ERB_RE, COMMENT_CSS_RE, CHAINE_RE, URL_RE)
  txt += "}" if genre == :attr    # l'attribut style="" n'a pas d'accolade fermante
  res = txt.gsub(DECL_RE) do
    pre, prop, sep, val = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3), Regexp.last_match(4)
    "#{pre}#{prop}#{sep}#{yield(prop.downcase, val)}"
  end
  res = res[0..-2] if genre == :attr
  p.rendre(res)
end

# ---------------------------------------------------------------------------
# 3. Relevé : qui emploie quoi, et dans combien de vues
# ---------------------------------------------------------------------------

class Releve
  attr_reader :emplois, :fichiers, :textes, :familles, :hors_perimetre

  def initialize
    @emplois = Hash.new(0)                       # cle -> nb d'emplois
    @fichiers = Hash.new { |h, k| h[k] = Hash.new(0) }  # cle -> {fichier => n}
    @textes = {}                                 # cle -> graphie canonique
    @familles = {}                               # cle -> :couleur / :px / :ombre
    @hors_perimetre = Hash.new { |h, k| h[k] = Hash.new(0) } # motif -> {valeur => n}
  end

  def note(cle, texte, famille, fichier, n = 1)
    @emplois[cle] += n
    @fichiers[cle][fichier] += n
    @textes[cle] ||= texte
    @familles[cle] ||= famille
  end

  def hors(motif, valeur, n = 1)
    @hors_perimetre[motif][valeur] += n
  end

  def systemiques(seuil) = @emplois.keys.select { |k| @fichiers[k].size >= seuil }.sort_by { |k| [-@fichiers[k].size, -@emplois[k], k] }
  def propres(seuil)     = @emplois.keys.reject { |k| @fichiers[k].size >= seuil }.sort_by { |k| [-@emplois[k], k] }
end

# alias locaux d'une vue : `--ts-gold: #A38543` puis 30 `var(--ts-gold)`.
# Sans cette resolution, l'or de cette vue compterait 1 emploi au lieu de 31.
def alias_locaux(src, charte_valeurs)
  decl = {}
  transformer(src) do |zone, genre|
    parcourir_declarations(zone, genre) do |prop, val|
      decl[prop] = val.strip if prop.start_with?("--")
      val
    end
    zone
  end
  resolus = {}
  decl.each_key do |nom|
    v = decl[nom]
    5.times do
      break unless (m = v.to_s.match(/\Avar\(\s*(--[A-Za-z0-9_-]+)\s*\)\z/))

      cible = m[1]
      v = decl[cible] || charte_valeurs[cible]
      break if v.nil?
    end
    resolus[nom] = v
  end
  resolus
end

def cle_de_valeur(txt, famille)
  case famille
  when :couleur
    rgba = Valeur.couleur_rgba(txt)
    rgba ? [Valeur.couleur_cle(rgba), Valeur.couleur_texte(rgba)] : nil
  when :px
    n = txt.to_f
    [Valeur.px_cle(n), Valeur.px_texte(n)]
  when :ombre
    c = Valeur.ombre_canon(txt)
    [c.empty? ? nil : "ombre:#{c}", c]
  end
end

OMBRE_PROPS = %w[box-shadow text-shadow -webkit-box-shadow -moz-box-shadow].freeze
VAR_SEULE = /\Avar\(\s*--[A-Za-z0-9_-]+\s*\)\z/

# Une ombre deja portee par un token : la valeur ENTIERE est un `var()`.
# Le test doit etre sur la valeur entiere et pas sur « contient un var » :
# `box-shadow: 0 1px 0 var(--ch-c-ffffff-a40) inset` contient un var sans etre
# tokenisee, et la confondre avec une ombre tokenisee faisait disparaitre la
# couleur du comptage a la relance.
def ombre_tokenisee?(val) = val.strip.match?(VAR_SEULE)

# Developpe les `var(--ch-…)` d'une valeur : c'est ce qui rend la cle d'une
# ombre stable entre la premiere execution (valeurs litterales) et les
# suivantes (valeurs deja nommees).
def developper(val, charte_valeurs)
  5.times do
    break unless val.match?(VAR_CHARTE)

    remplace = false
    val = val.gsub(/\bvar\(\s*(--[A-Za-z0-9_-]+)\s*\)/) do
      v = charte_valeurs[Regexp.last_match(1)]
      if v
        remplace = true
        v
      else
        Regexp.last_match(0)
      end
    end
    break unless remplace
  end
  val
end

# releve d'une vue. `phase` vaut :ombre (1er passage) ou :valeur (2e passage).
def relever(src, fichier, rel, charte_valeurs, phase, litteraux_seuls: false)
  aliases = alias_locaux(src, charte_valeurs)

  compter_var = lambda do |val, ctx|
    val.scan(/\bvar\(\s*(--[A-Za-z0-9_-]+)/) do
      nom = Regexp.last_match(1)
      cible = charte_valeurs[nom] || aliases[nom]
      next if cible.nil?

      fam = famille_de(cible, ctx)
      next if fam.nil?

      cv = cle_de_valeur(cible, fam)
      rel.note(cv[0], cv[1], fam, fichier) if cv && cv[0]
    end
  end

  transformer(src) do |zone, genre|
    parcourir_declarations(zone, genre) do |prop, val|
      if phase == :ombre
        if OMBRE_PROPS.include?(prop) && !val.strip.empty?
          cv = cle_de_valeur(developper(val, charte_valeurs), :ombre)
          rel.note(cv[0], cv[1], :ombre, fichier) if cv && cv[0]
        end
      else
        next val if OMBRE_PROPS.include?(prop) && ombre_tokenisee?(val)

        p2 = Protection.new
        compter_var.call(val, :auto) unless litteraux_seuls
        v = p2.masquer(val, VAR_RE)
        v.scan(COULEUR_RE) do |m|
          cv = cle_de_valeur(m, :couleur)
          rel.note(cv[0], cv[1], :couleur, fichier) if cv && cv[0]
        end
        if OPT[:px]
          v.scan(PX_RE) do
            cv = cle_de_valeur(Regexp.last_match(1), :px)
            rel.note(cv[0], cv[1], :px, fichier) if cv && cv[0]
          end
        end
      end
      val
    end
  end
  nil
end

# de quelle famille est la valeur pointee par un var() ?
def famille_de(txt, ctx)
  t = txt.to_s.strip
  return :ombre if ctx == :ombre

  return :couleur if t.match?(/\A(?:#[0-9a-fA-F]{3,8}|rgba?\([^()]*\)|hsla?\([^()]*\))\z/)
  return :px if t.match?(/\A-?\d{1,4}(?:\.\d+)?px\z/)

  nil
end

# ---------------------------------------------------------------------------
# 4. Reecriture
# ---------------------------------------------------------------------------

def reecrire(src, tokens, phase, compte, charte_valeurs = {})
  transformer(src) do |zone, genre|
    parcourir_declarations(zone, genre) do |prop, val|
      if phase == :ombre
        if OMBRE_PROPS.include?(prop) && !val.strip.empty? && !ombre_tokenisee?(val)
          cv = cle_de_valeur(developper(val, charte_valeurs), :ombre)
          if cv && (nom = tokens[cv[0]])
            compte[cv[0]] += 1
            next "var(--#{PREF}-#{nom})"
          end
        end
        val
      else
        next val if OMBRE_PROPS.include?(prop) && ombre_tokenisee?(val)

        p2 = Protection.new
        v = p2.masquer(val, VAR_RE)
        v = v.gsub(COULEUR_RE) do |m|
          cv = cle_de_valeur(m, :couleur)
          if cv && cv[0] && (nom = tokens[cv[0]])
            compte[cv[0]] += 1
            "var(--#{PREF}-#{nom})"
          else
            m
          end
        end
        if OPT[:px]
          v = v.gsub(PX_RE) do |m|
            cv = cle_de_valeur(Regexp.last_match(1), :px)
            if cv && cv[0] && (nom = tokens[cv[0]])
              compte[cv[0]] += 1
              "var(--#{PREF}-#{nom})"
            else
              m
            end
          end
        end
        p2.rendre(v)
      end
    end
  end
end

# ---------------------------------------------------------------------------
# 5. Nommage — stable d'une execution a l'autre
#
# On reprend le nom que la charte porte deja (relance), sinon le nom que les
# vues declarent elles-memes pour cette valeur (`--ts-gold` -> `gold`, le
# prefixe d'ecran saute), sinon un nom derive de la valeur.
# ---------------------------------------------------------------------------

def noms_declares(vues_src)
  h = Hash.new { |x, k| x[k] = Hash.new(0) }
  vues_src.each_value do |src|
    transformer(src) do |zone, genre|
      parcourir_declarations(zone, genre) do |prop, val|
        if prop.start_with?("--") && !prop.start_with?("--#{PREF}-")
          fam = famille_de(val, :auto)
          if fam
            cv = cle_de_valeur(val.strip, fam)
            h[cv[0]][prop.sub(/\A--/, "")] += 1 if cv && cv[0]
          end
        end
        val
      end
      zone
    end
  end
  h
end

def nom_pour(cle, famille, texte, declares, pris)
  base = nil
  if (d = declares[cle]) && !d.empty?
    brut = d.max_by { |n, c| [c, -n.length] }.first
    base = brut.sub(/\A[a-z]{1,4}-/, "")
    base = brut if base.empty?
  end
  base ||= case famille
           when :couleur
             rgba = Valeur.couleur_rgba(texte)
             hex = format("%02x%02x%02x", *rgba[0, 3])
             rgba[3] >= 1.0 ? "c-#{hex}" : "c-#{hex}-a#{(rgba[3] * 100).round}"
           when :px    then "len-#{texte.sub('px', '')}"
           when :ombre then "elev-1"
           end
  base = base.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-").sub(/\A-/, "").sub(/-\z/, "")
  base = "t" if base.empty?
  return base unless pris.key?(base)

  i = 2
  i += 1 while pris.key?("#{base}-#{i}")
  "#{base}-#{i}"
end

# ---------------------------------------------------------------------------
# 6. Grappes a arbitrer — signalees, jamais fusionnees
#
# Meme geste que `mockup_scan.rb#near_duplicate_clusters` : regroupement PAR
# GRAINE (la couleur la plus employee attire ses sosies), pas de proche en
# proche, sinon le blanc et l'or finissent dans le meme paquet.
# ---------------------------------------------------------------------------

def grappes_couleur(rel, seuil_de)
  keys = rel.emplois.keys.select { |k| rel.familles[k] == :couleur }
              .sort_by { |k| [-rel.emplois[k], k] }
  rgba = keys.to_h { |k| [k, Valeur.couleur_rgba(rel.textes[k])] }
  labs = keys.to_h { |k| [k, Color.lab(rgba[k][0, 3])] }
  # On ne compare QUE des couleurs de meme opacite. Sans ca, `#ffffff` et
  # `rgba(255,255,255,.4)` sortent a 0 dE et la liste d'arbitrage se remplit de
  # faux doublons : deux alphas differents sont deux valeurs voulues, pas une
  # hesitation entre deux ors.
  taken = Set.new
  grappes = []
  keys.each do |seed|
    next if taken.include?(seed)

    taken << seed
    voisins = keys.select do |k|
      !taken.include?(k) && (rgba[k][3] - rgba[seed][3]).abs < 0.005 &&
        Color.delta_e(labs[seed], labs[k]) < seuil_de
    end
    next if voisins.empty?

    voisins.each { |k| taken << k }
    grappes << {
      graine: rel.textes[seed],
      ecart_max: voisins.map { |k| Color.delta_e(labs[seed], labs[k]).round(2) }.max,
      membres: ([seed] + voisins).map do |k|
        { valeur: rel.textes[k], emplois: rel.emplois[k], ecrans: rel.fichiers[k].size,
          fichiers: rel.fichiers[k].keys.sort,
          ecart: Color.delta_e(labs[seed], labs[k]).round(2) }
      end
    }
  end
  grappes.sort_by { |g| -g[:membres].sum { |m| m[:emplois] } }
end

def grappes_px(rel, tol)
  vals = rel.emplois.keys.select { |k| rel.familles[k] == :px }
            .map { |k| [rel.textes[k].sub("px", "").to_f, k] }.sort
  paires = []
  vals.each_with_index do |(v, k), i|
    vals[(i + 1)..].to_a.each do |(v2, k2)|
      break if (v2 - v) > tol

      paires << { a: rel.textes[k], b: rel.textes[k2], ecart: (v2 - v).round(2),
                  emplois_a: rel.emplois[k], emplois_b: rel.emplois[k2] }
    end
  end
  paires.sort_by { |p| -(p[:emplois_a] + p[:emplois_b]) }
end

# niveaux d'elevation PROPOSES : groupement sur la geometrie seule (x, y, flou,
# etalement), la teinte est une decision ecrite, pas une moyenne.
def niveaux_ombre(rel)
  keys = rel.emplois.keys.select { |k| rel.familles[k] == :ombre }
  geoms = Hash.new { |h, g| h[g] = [] }
  keys.each do |k|
    g = rel.textes[k].gsub(COULEUR_RE, "").gsub(/\s+/, " ").strip
    geoms[g] << k
  end
  geoms.map do |g, ks|
    { geometrie: g, emplois: ks.sum { |k| rel.emplois[k] },
      ecrans: ks.flat_map { |k| rel.fichiers[k].keys }.uniq.size,
      teintes: ks.map { |k| { valeur: rel.textes[k], emplois: rel.emplois[k] } }.sort_by { |t| -t[:emplois] } }
  end.sort_by { |n| -n[:emplois] }
end

# ---------------------------------------------------------------------------
# 7. Deroule
# ---------------------------------------------------------------------------

def bam(msg)
  warn "normaliser.rb : ARRET — #{msg}"
  exit 3
end

srcs = VUES.to_h { |p| [p, File.read(p, encoding: "UTF-8")] }
noms_fichiers = VUES.to_h { |p| [p, File.basename(p)] }
bam("deux vues portent le meme nom de fichier") if noms_fichiers.values.uniq.size != noms_fichiers.size

# charte existante (relance) : on reprend ses noms et ses valeurs
charte_nom_valeur = {}
if File.file?(OPT[:charte])
  File.read(OPT[:charte], encoding: "UTF-8").scan(/(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/) do
    charte_nom_valeur[Regexp.last_match(1)] = Regexp.last_match(2).strip
  end
end

declares = noms_declares(srcs)
# les noms deja pris par la charte existante ne sont pas re-attribuables
pris = charte_nom_valeur.keys.filter_map { |n| n[/\A--#{Regexp.escape(PREF)}-(.+)\z/, 1] }.to_h { |n| [n, :charte] }
tokens = {}          # cle de valeur -> nom court
info = {}            # cle -> {famille, texte, emplois, fichiers}

# --- phase 1 : les ombres ---------------------------------------------------
etats = srcs.dup
if OPT[:ombre]
  rel1 = Releve.new
  etats.each { |p, s| relever(s, noms_fichiers[p], rel1, charte_nom_valeur, :ombre) }
  sys1 = rel1.systemiques(OPT[:seuil])
  sys1.each do |k|
    nom = charte_nom_valeur.key(rel1.textes[k])&.sub(/\A--#{Regexp.escape(PREF)}-/, "")
    nom = nil unless nom && charte_nom_valeur.key?("--#{PREF}-#{nom}")
    nom ||= nom_pour(k, :ombre, rel1.textes[k], declares, pris)
    pris[nom] = k
    tokens[k] = nom
    info[k] = { famille: :ombre, texte: rel1.textes[k], emplois: rel1.emplois[k], fichiers: rel1.fichiers[k] }
  end
  compte1 = Hash.new(0)
  etats = etats.to_h { |p, s| [p, reecrire(s, tokens, :ombre, compte1, charte_nom_valeur)] }
  info.each_key { |k| info[k][:substitutions] = compte1[k] }
end

# --- phase 2 : couleurs et longueurs ---------------------------------------
# La charte deja ecrite (relance) sert a resoudre les `var(--ch-…)` que les vues
# portent DEJA : sans elle, un alias local qui pointe sur un token de la charte
# ne serait plus resolu et les comptes changeraient d'une execution a l'autre.
charte_valeurs = charte_nom_valeur.merge(tokens.to_h { |k, n| ["--#{PREF}-#{n}", info[k][:texte]] })
rel2 = Releve.new
etats.each { |p, s| relever(s, noms_fichiers[p], rel2, charte_valeurs, :valeur) }
sys2 = rel2.systemiques(OPT[:seuil])
sys2.each do |k|
  next if tokens.key?(k)

  fam = rel2.familles[k]
  nom = charte_nom_valeur.key(rel2.textes[k])&.sub(/\A--#{Regexp.escape(PREF)}-/, "")
  nom = nil unless nom && charte_nom_valeur.key?("--#{PREF}-#{nom}")
  nom ||= nom_pour(k, fam, rel2.textes[k], declares, pris)
  pris[nom] = k
  tokens[k] = nom
  info[k] = { famille: fam, texte: rel2.textes[k], emplois: rel2.emplois[k], fichiers: rel2.fichiers[k] }
end
compte2 = Hash.new(0)
finaux = etats.to_h { |p, s| [p, reecrire(s, tokens, :valeur, compte2)] }
info.each_key { |k| info[k][:substitutions] = (info[k][:substitutions] || 0) + compte2[k] }

# --- controle de COMPLETUDE : plus aucune valeur tokenisee en dur ------------
# Le controle de relecture ci-dessous prouve que rien n'a bouge ; celui-ci
# prouve que le travail a ete fait. Une valeur qui a un token et qui reste
# ecrite en dur a un endroit substituable est un trou de l'outil : on ne
# s'arrete pas (le fichier produit reste juste) mais on le dit fort et on
# l'ecrit dans le rapport.
fuites = Releve.new
finaux.each { |p, s| relever(s, noms_fichiers[p], fuites, {}, :valeur, litteraux_seuls: true) }
restes = fuites.emplois.keys.select { |k| tokens.key?(k) }
unless restes.empty?
  warn "normaliser.rb : ATTENTION — #{restes.size} valeur(s) tokenisee(s) restent ecrites en dur :"
  restes.first(10).each { |k| warn "  #{fuites.textes[k]} x#{fuites.emplois[k]} dans #{fuites.fichiers[k].keys.join(', ')}" }
end

# --- controle : la reecriture doit se relire a l'identique ------------------
# On redeveloppe chaque `var(--ch-x)` par sa valeur et on compare a l'original,
# a la graphie de rendu pres. Si un seul caractere de style a bouge, on s'arrete :
# c'est la garantie que la fidelite ne PEUT pas changer.
valeurs_par_nom = tokens.to_h { |k, n| ["--#{PREF}-#{n}", info[k][:texte]] }
# Les deux cotes sont redeveloppes : a la relance, l'entree porte DEJA des
# `var(--ch-…)`, et ne developper que la sortie ferait echouer un controle qui
# n'a rien vu de faux.
redevelopper = lambda do |txt, ou|
  5.times do
    break unless txt.match?(VAR_CHARTE)

    txt = txt.gsub(VAR_CHARTE) do
      nom = "--#{PREF}-#{Regexp.last_match(1)}"
      bam("token inconnu au controle : #{nom} dans #{ou}") if valeurs_par_nom[nom].nil?
      valeurs_par_nom[nom]
    end
  end
  txt
end
finaux.each do |p, s|
  attendu = canon_rendu(redevelopper.call(srcs[p], p))
  obtenu  = canon_rendu(redevelopper.call(s, p))
  next if attendu == obtenu

  # on laisse de quoi diagnostiquer : un controle qui echoue sans montrer ou
  # oblige a le refaire a la main.
  trace = File.join(Dir.tmpdir, "normaliser-controle")
  FileUtils.mkdir_p(trace)
  File.write(File.join(trace, "#{File.basename(p)}.attendu"), attendu)
  File.write(File.join(trace, "#{File.basename(p)}.obtenu"), obtenu)
  bam("la reecriture de #{p} ne se relit pas a l'identique (voir #{trace}/)")
end

# --- totaux recalcules depuis les listes ------------------------------------
par_famille = Hash.new(0)
tokens.each_key { |k| par_famille[info[k][:famille]] += 1 }
bam("total des tokens incoherent") if par_famille.values.sum != tokens.size

# --- ecriture ---------------------------------------------------------------
dest = lambda do |p|
  OPT[:sortie] ? File.join(OPT[:sortie], File.basename(p)) : p
end
FileUtils.mkdir_p(OPT[:sortie]) if OPT[:sortie]
finaux.each { |p, s| File.write(dest.call(p), s) }

ordre = { couleur: 0, px: 1, ombre: 2 }
lignes = []
lignes << "/* Charte normalisee — #{VUES.size} vues, seuil #{OPT[:seuil]} vue(s)."
lignes << "   Produite par normaliser.rb : chaque token porte la valeur EXACTE"
lignes << "   qu'employaient les vues, aucune n'a ete arrondie ni fusionnee."
lignes << "   #{par_famille[:couleur]} couleurs, #{par_famille[:px]} longueurs, #{par_famille[:ombre]} ombres. */"
lignes << ":root {"
tokens.keys.sort_by { |k| [ordre[info[k][:famille]], -info[k][:fichiers].size, -info[k][:emplois], k] }.each do |k|
  i = info[k]
  lignes << format("  %-26s %s;  /* %d vues, %d emplois */", "--#{PREF}-#{tokens[k]}:", i[:texte],
                   i[:fichiers].size, i[:emplois])
end
lignes << "}"
File.write(OPT[:charte], lignes.join("\n") + "\n")

# --- rapport ---------------------------------------------------------------
propres = rel2.propres(OPT[:seuil]).reject { |k| tokens.key?(k) }
rapport = {
  vues: VUES.map { |p| { fichier: noms_fichiers[p], lignes: srcs[p].count("\n") + 1 } },
  seuil: OPT[:seuil],
  tokens: tokens.keys.sort_by { |k| [ordre[info[k][:famille]], -info[k][:fichiers].size, -info[k][:emplois]] }.map do |k|
    { nom: "--#{PREF}-#{tokens[k]}", famille: info[k][:famille], valeur: info[k][:texte],
      ecrans: info[k][:fichiers].size, emplois: info[k][:emplois],
      substitutions: info[k][:substitutions],
      fichiers: info[k][:fichiers].sort_by { |_f, n| -n }.to_h }
  end,
  litterales: propres.map do |k|
    { valeur: rel2.textes[k], famille: rel2.familles[k], emplois: rel2.emplois[k],
      fichiers: rel2.fichiers[k].keys.sort }
  end,
  grappes_couleur: grappes_couleur(rel2, OPT[:delta_e]),
  voisinage_px: grappes_px(rel2, 1),
  niveaux_ombre_proposes: OPT[:ombre] ? niveaux_ombre(rel1) : [],
  fuites: restes.map { |k| { valeur: fuites.textes[k], emplois: fuites.emplois[k], fichiers: fuites.fichiers[k].keys.sort } }
}
File.write(OPT[:json], JSON.pretty_generate(rapport)) if OPT[:json]

md = []
md << "# Normalisation mecanique — rapport"
md << ""
md << "#{VUES.size} vues, seuil systemique : une valeur employee dans **#{OPT[:seuil]} vues ou plus**."
md << "Substitution par egalite stricte de rendu : aucune valeur n'est arrondie."
md << ""
md << "## Tokens crees (#{rapport[:tokens].size})"
md << ""
md << "| token | famille | valeur | vues | emplois | substitutions | fichiers |"
md << "|---|---|---|--:|--:|--:|---|"
rapport[:tokens].each do |t|
  md << "| `#{t[:nom]}` | #{t[:famille]} | `#{t[:valeur]}` | #{t[:ecrans]} | #{t[:emplois]} | #{t[:substitutions]} | #{t[:fichiers].map { |f, n| "#{f} x#{n}" }.join(', ')} |"
end
md << ""
md << "## Valeurs laissees litterales (#{rapport[:litterales].size})"
md << ""
md << "Employees dans une seule vue : elles restent dans la vue, telles quelles."
md << ""
md << "| valeur | famille | emplois | vue |"
md << "|---|---|--:|---|"
rapport[:litterales].sort_by { |l| -l[:emplois] }.first(60).each do |l|
  md << "| `#{l[:valeur]}` | #{l[:famille]} | #{l[:emplois]} | #{l[:fichiers].join(', ')} |"
end
md << ""
md << "reste #{[rapport[:litterales].size - 60, 0].max} lignes, voir le JSON." if rapport[:litterales].size > 60
md << ""
md << "## Grappes a arbitrer (#{rapport[:grappes_couleur].size})"
md << ""
md << "Des couleurs a moins de #{OPT[:delta_e]} dE l'une de l'autre. **Elles n'ont pas ete fusionnees** :"
md << "fusionner deux ors proches est une decision de design, pas un calcul. A trancher"
md << "avec le client, puis a appliquer par une recherche-remplacement."
md << ""
rapport[:grappes_couleur].each do |g|
  md << "- graine `#{g[:graine]}` (ecart max #{g[:ecart_max]} dE)"
  g[:membres].each { |m| md << "  - `#{m[:valeur]}` — #{m[:emplois]} emplois, #{m[:ecrans]} vues, #{m[:ecart]} dE — #{m[:fichiers].join(', ')}" }
end
md << ""
md << "## Longueurs voisines a +-1 px (#{rapport[:voisinage_px].size})"
md << ""
md << "Ce qu une accroche a +-1 px absorberait. **Elle change le rendu**, elle n est"
md << "donc pas appliquee : c est une decision de design, a prendre et a ecrire."
md << ""
rapport[:voisinage_px].first(30).each do |p|
  md << "- `#{p[:a]}` (#{p[:emplois_a]}) / `#{p[:b]}` (#{p[:emplois_b]}) — #{p[:ecart]} px d'ecart"
end
md << ""
md << "## Valeurs tokenisees restees en dur (#{rapport[:fuites].size})"
md << ""
md << "Doit valoir zero. Ce qui apparait ici est un trou de l'outil, pas une regle."
md << "Ne comptent pas : les longueurs d'un prelude `@media` (`var()` y est interdit)"
md << "et les valeurs negatives (`-var()` n'est pas du CSS), qui restent litterales"
md << "par necessite."
md << ""
rapport[:fuites].each { |f| md << "- `#{f[:valeur]}` x#{f[:emplois]} — #{f[:fichiers].join(', ')}" }
md << ""
md << "## Niveaux d'elevation PROPOSES (#{rapport[:niveaux_ombre_proposes].size})"
md << ""
md << "Groupes sur la geometrie seule (x, y, flou, etalement). La teinte et l'alpha d'un"
md << "niveau sont une decision ecrite, pas une moyenne : rien n'est impose ici."
md << ""
rapport[:niveaux_ombre_proposes].first(20).each_with_index do |n, i|
  md << "- niveau #{i + 1} : `#{n[:geometrie]}` — #{n[:emplois]} emplois, #{n[:ecrans]} vues, #{n[:teintes].size} teinte(s)"
  n[:teintes].first(4).each { |t| md << "  - `#{t[:valeur]}` x#{t[:emplois]}" }
end
md << ""
File.write(OPT[:rapport] || OPT[:charte].sub(/\.css\z/, "") + "-rapport.md", md.join("\n"))

warn "charte : #{OPT[:charte]} — #{tokens.size} tokens (#{par_famille[:couleur]} couleurs, #{par_famille[:px]} longueurs, #{par_famille[:ombre]} ombres)"
warn "vues   : #{finaux.size} reecrites#{OPT[:sortie] ? " dans #{OPT[:sortie]}" : ' en place'}, controle de relecture OK"
warn "reste  : #{propres.size} valeurs litterales (une seule vue), #{rapport[:grappes_couleur].size} grappes a arbitrer"
