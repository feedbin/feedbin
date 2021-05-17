class Transformers
  LISTS = Set.new(%w[ul ol].freeze)
  LIST_ITEM = "li".freeze
  TABLE_ITEMS = Set.new(%w[tr td th].freeze)
  TABLE = "table".freeze
  TABLE_SECTIONS = Set.new(%w[thead tbody tfoot].freeze)
  VIDEO = "video".freeze

  def class_allowlist
    lambda do |env|
      node = env[:node]

      if env[:node_name] != "blockquote" || env[:is_allowlisted] || !node.element? || node["class"].nil?
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

      Sanitize.node!(node, Sanitize::Config.merge(Sanitize::Config::BASIC, attributes: {"blockquote" => allowed_attributes}))

      {node_allowlist: [node]}
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

  def video
    lambda do |env|
      name, node = env[:node_name], env[:node]
      if name == VIDEO
        node["preload"] = "none"
      end
    end
  end
end
