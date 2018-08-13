class Transformers
  LISTS = Set.new(%w(ul ol).freeze)
  LIST_ITEM = "li".freeze
  TABLE_ITEMS = Set.new(%w(tr td th).freeze)
  TABLE = "table".freeze
  TABLE_SECTIONS = Set.new(%w(thead tbody tfoot).freeze)

  def iframe_attributes(uri, width, height)
    uri = URI(uri)
    id = Digest::SHA1.hexdigest(uri.to_s)
    attributes = {
      "id" => id,
      "class" => "iframe-placeholder entry-callout system-content",
      "data-iframe-src" => uri.to_s,
      "data-iframe-host" => uri.host,
      "data-iframe-embed-url" => Rails.application.routes.url_helpers.iframe_embeds_path(url: uri.to_s, dom_id: id),
    }
    if width && height
      attributes["data-iframe-width"] = width
      attributes["data-iframe-height"] = height
    end
    attributes
  end

  def iframe_whitelist
    lambda do |env|
      node = env[:node]
      node_name = env[:node_name]
      source = node["src"]

      if node_name != "iframe" || env[:is_whitelisted] || !node.element? || source.nil?
        return
      end

      node["src"] = source.gsub(/^https?:?/, "https:")

      if uri = URI(node["src"]) rescue nil
        replacement = Nokogiri::XML::Element.new("div", node.document)
        width = node["width"] && node["width"].to_i
        height = node["height"] && node["height"].to_i
        attributes = iframe_attributes(uri, width, height)
        attributes.each do |attribute, value|
          replacement.set_attribute(attribute, value)
        end
        node.replace(replacement)
        {:node_whitelist => [replacement]}
      end
    end
  end

  def class_whitelist
    lambda do |env|
      node = env[:node]

      if env[:node_name] != "blockquote" || env[:is_whitelisted] || !node.element? || node["class"].nil?
        return
      end

      allowed_classes = ["twitter-tweet", "instagram-media", "imgur-embed-pub"]

      allowed_attributes = []

      allowed_classes.each do |allowed_class|
        if node["class"].include?(allowed_class)
          node["class"] = allowed_class
          allowed_attributes = ["class", :data]
        end
      end

      whitelist = Feedbin::Application.config.base.dup
      whitelist[:attributes]["blockquote"] = allowed_attributes

      Sanitize.clean_node!(node, whitelist)

      {:node_whitelist => [node]}
    end
  end

  # Top-level <li> elements are removed because they can break out of
  # containing markup.
  def top_level_li
    lambda do |env|
      name, node = env[:node_name], env[:node]
      if name == LIST_ITEM && !node.ancestors.any? { |n| LISTS.include?(n.name) }
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
