class Transformers
  LISTS     = Set.new(%w(ul ol).freeze)
  LIST_ITEM = 'li'.freeze
  TABLE_ITEMS = Set.new(%w(tr td th).freeze)
  TABLE = 'table'.freeze
  TABLE_SECTIONS = Set.new(%w(thead tbody tfoot).freeze)

  def iframe_whitelist
    lambda { |env|
      node      = env[:node]
      node_name = env[:node_name]
      source    = node['src']

      if node_name != 'iframe' || env[:is_whitelisted] || !node.element? || source.nil?
        return
      end

      allowed_hosts = [
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.)?
          (?:youtube\.com|youtu\.be|youtube-nocookie\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.|player\.)?
          (?:vimeo\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.)?
          (?:kickstarter\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:embed\.spotify\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:w\.soundcloud\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:view\.vzaar\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:vine\.co)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:e\.)?
          (?:infogr\.am)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.flickr\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:mpora\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:embed-ssl\.ted\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:embed\.itunes\.apple\.com)
        /x,
        /^
          (?:https?:\/\/|\/\/)
          (?:www\.tumblr\.com)
        /x
      ]

      source_allowed = false
      allowed_hosts.each do |host|
        if source =~ host
          source_allowed = true
        end
      end

      return unless source_allowed

      # Force protocol relative url
      node['src'] = source.gsub(/^https?:?/, '')

      # Strip attributes
      Sanitize.clean_node!(node, {
        :elements => %w[iframe],
        :attributes => {
          'iframe'  => %w[allowfullscreen frameborder height src width]
        }
      })

      {:node_whitelist => [node]}
    }
  end

  def class_whitelist
    lambda do |env|
      node = env[:node]

      if env[:node_name] != 'blockquote' || env[:is_whitelisted] || !node.element? || node['class'].nil?
        return
      end

      allowed_classes = ['twitter-tweet', 'instagram-media']

      allowed_attributes = []

      allowed_classes.each do |allowed_class|
        if node['class'].include?(allowed_class)
          node['class'] = allowed_class
          allowed_attributes = ['class', :data]
        end
      end

      whitelist = Feedbin::Application.config.base.dup
      whitelist[:attributes]['blockquote'] = allowed_attributes

      Sanitize.clean_node!(node, whitelist)

      {:node_whitelist => [node]}
    end
  end

  # Top-level <li> elements are removed because they can break out of
  # containing markup.
  def top_level_li
    lambda do |env|
      name, node = env[:node_name], env[:node]
      if name == LIST_ITEM && !node.ancestors.any?{ |n| LISTS.include?(n.name) }
        node.replace(node.children)
      end
    end
  end

  # Table child elements that are not contained by a <table> are removed.
  def table_elements
    lambda do |env|
      name, node = env[:node_name], env[:node]
      if (TABLE_SECTIONS.include?(name) || TABLE_ITEMS.include?(name)) && !node.ancestors.any? { |n| n.name == TABLE }
        node.replace(node.children)
      end
    end
  end

end