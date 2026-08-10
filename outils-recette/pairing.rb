# frozen_string_literal: true

# pairing.rb — l'appariement maquette ↔ écran applicatif, en un seul endroit.
#
# Extrait de pairs_gen.rb, qui l'utilisait pour apparier des ROUTES. Le mode
# `inventory` de mockup_scan.rb apparie des FICHIERS DE VUE avec exactement les
# mêmes règles. Deux outils qui apparient différemment finiraient par ne pas
# parler de la même paire ; il n'y a donc qu'une implémentation, et les deux la
# chargent.
#
# Un « item » est n'importe quel Hash qui répond à :controller et :action
# (une route de `bin/rails routes`, ou une vue `app/views/<controller>/<action>`).

module Pairing
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

  # Actions REST qui rendent « la » page d'une ressource : c'est par elles qu'une
  # maquette `mockups/talent/dashboard` retrouve `talent/dashboard#index`.
  LEAF_ACTIONS = %w[index show].freeze

  module_function

  def strip_mockup(controller) = controller.to_s.sub(%r{\Amockups/?}, "")

  # URL de la maquette : la convention REST quand la route n'est pas connue.
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

  # Premier segment de chaque contrôleur de maquette (hors « mockups ») : ce sont
  # les namespaces que l'application est censée conserver. Ils interdisent
  # d'apparier /mockups/dashboard avec /admin/dashboard.
  def namespaces(mockup_items)
    mockup_items.map { |v| strip_mockup(v[:controller]).split("/").first }.compact.uniq.to_set
  end

  # Cherche l'écran applicatif : même contrôleur privé du préfixe « mockups »,
  # éventuellement précédé d'un scope (`scope module: :app`). On refuse un
  # préfixe qui est lui-même un namespace de maquette (admin, settings…) : c'est
  # ce qui apparierait le tableau de bord entreprise avec celui du superadmin.
  #
  # `leaf:` ajoute la forme la plus courante entre une maquette et une vraie
  # application : la maquette met tout l'écran dans UN fichier
  # (`mockups/talent/dashboard`), l'application lui donne son contrôleur
  # (`talent/dashboard#index`). Sans cette règle, le tableau de bord n'a pas de
  # paire alors qu'il en a une, évidente. Désactivé par défaut : pairs_gen
  # apparie des routes et garde son comportement d'origine.
  def candidates(items, ctrl_base, action, forbidden, leaf: false)
    base_segments = ctrl_base.split("/")
    ok_prefix = lambda do |prefix|
      prefix.none? { |seg| forbidden.include?(seg) && !base_segments.include?(seg) }
    end

    items.filter_map do |it|
      c = it[:controller].to_s
      next if c.start_with?("mockups/") || c == "mockups"
      if it[:action] == action
        if c == ctrl_base
          { item: it, score: 0 }
        elsif c.end_with?("/#{ctrl_base}")
          prefix = c[0...-(ctrl_base.size + 1)].split("/")
          { item: it, score: prefix.size } if ok_prefix.call(prefix)
        end
      elsif leaf && LEAF_ACTIONS.include?(it[:action].to_s)
        # `mockups/talent/profile` → `talent/profiles#show` : la maquette parle
        # au singulier de l'objet montre, Rails met la ressource au pluriel.
        leafed = leaf_forms(ctrl_base, action).find { |l| c == l || c.end_with?("/#{l}") }
        next unless leafed
        if c == leafed
          { item: it, score: 10 }
        else
          prefix = c[0...-(leafed.size + 1)].split("/")
          { item: it, score: 10 + prefix.size } if ok_prefix.call(prefix)
        end
      end
    end.sort_by { |c| [ c[:score], sort_key(c[:item]) ] }
  end

  # Départage deux candidats de même score : la route la plus courte (règle
  # d'origine de pairs_gen), ou à défaut le chemin de fichier, pour que deux
  # exécutions rendent le même verdict.
  def sort_key(item)
    item[:path] ? [ item[:path].to_s.length, item[:path].to_s ] : [ 0, item[:file].to_s ]
  end

  def no_counterpart(action) = NO_APP_COUNTERPART.find { |re, _| action.to_s =~ re }&.last

  def leaf_forms(ctrl_base, action)
    [ action, pluralize(action) ].uniq.map { |a| "#{ctrl_base}/#{a}" }
  end

  def pluralize(word)
    case word
    when /(s|x|z|ch|sh)\z/ then "#{word}es"
    when /[^aeiou]y\z/ then word.sub(/y\z/, "ies")
    else "#{word}s"
    end
  end
end
