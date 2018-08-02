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

      # Force protocol relative url
      node['src'] = source.gsub(/^https?:?/, '')

      if uri = URI(node["src"]) rescue nil
        replacement = Nokogiri::XML::Element.new("div", node.document)
        replacement["class"] = "iframe-placeholder"
        replacement["data-behavior"] = "iframe_placeholder"
        replacement["data-iframe-src"] = uri.to_s
        replacement["data-iframe-host"] = uri.host

        width = node["width"] && node["width"].to_i
        height = node["height"] && node["height"].to_i
        if height && width
          replacement["data-iframe-width"] = width
          replacement["data-iframe-height"] = height
        end

        node.replace(replacement)
        {:node_whitelist => [replacement]}
      end
    }
  end

  def class_whitelist
    lambda do |env|
      node = env[:node]

      if env[:node_name] != 'blockquote' || env[:is_whitelisted] || !node.element? || node['class'].nil?
        return
      end

      allowed_classes = ['twitter-tweet', 'instagram-media', 'imgur-embed-pub']

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