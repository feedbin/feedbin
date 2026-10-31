module ContentFilters
  # Each pass here selects with XPath so the tree walk happens in libxml and
  # Ruby only sees the matches. A Loofah scrubber visits every node from Ruby;
  # as scrubbers, the four small passes together cost more than the sanitizer.
  class Scrub < HTML::Pipeline::Filter
    NEWSLETTER_ELEMENTS = %w[table thead tbody tfoot tr td center]
    DASHED_ELEMENT_PARENTS = %w[svg math]

    # svg and math are namespaced in an HTML5 parse, so they are matched by
    # local name. descendant-or-self rather than .// because a fragment's
    # top-level nodes fall out of a .// query that carries a predicate.
    CUSTOM_ELEMENTS = "./descendant-or-self::*[contains(local-name(), '-')]" \
      "[not(ancestor::*[#{DASHED_ELEMENT_PARENTS.map { "local-name()='#{it}'" }.join(" or ")}])]"
    NEWSLETTER_ELEMENTS_XPATH = NEWSLETTER_ELEMENTS.map { ".//#{it}" }.join(" | ")

    # Everything Loofah's prune decides on, in document order: elements are
    # kept and sanitized or removed with their contents, comments go, and a
    # CDATA section (only foreign content has them) is escaped to text.
    PRUNE = "./descendant-or-self::* | ./descendant-or-self::comment()"
    CDATA = "./descendant::*[local-name()='svg' or local-name()='math']//text()"

    def call
      custom_elements
      # Attributes drops every style attribute afterwards, and prune would
      # first run each one through a CSS parser: on newsletters that was most
      # of the formatting time.
      doc.xpath(".//@style").each(&:unlink)
      prune
      video
      links
      iframe
      newsletter_elements if context[:scrub_mode] == :newsletter
      doc
    end

    # The same decisions as doc.scrub!(:prune), whose scrubber recurses from
    # Ruby through every node and builds a NodeSet of each one's children:
    # that walk was half of its time. The sanitizing of each element is still
    # Loofah's. An element under a removed one is visited too, detached,
    # which changes nothing.
    def prune
      doc.xpath(PRUNE).each do |node|
        if !node.element?
          node.remove
        elsif Loofah::HTML5::Scrub.allowed_element?(node.name)
          Loofah::HTML5::Scrub.scrub_attributes(node)
        else
          node.remove
        end
      end
      doc.xpath(CDATA).each do |node|
        next unless node.cdata?
        node.before(Loofah::HTML5::Scrub.cdata_escape(node))
        node.remove
      end
    end

    # An unknown dashed element would be pruned with its contents, so it
    # becomes a span first. SVG and MathML have dashed elements of their own.
    def custom_elements
      doc.xpath(CUSTOM_ELEMENTS).each do |node|
        node.name = "span"
      end
    end

    def newsletter_elements
      doc.xpath(NEWSLETTER_ELEMENTS_XPATH).each do |node|
        node.name = "div"
        node.keys.each do |attribute|
          node.delete attribute
        end
      end
    end

    def video
      doc.xpath(".//video").each do |node|
        node["preload"] = "none"
      end
    end

    def iframe
      doc.xpath(".//iframe").each do |node|
        node["referrerpolicy"] = "strict-origin-when-cross-origin"
      end
    end

    def links
      doc.xpath(".//a").each do |node|
        next unless node["href"] == node.text
        if shortened = node["href"].gsub(/https?:\/\//, "").truncate(40, omission: "…") rescue nil
          node.content = shortened
        end
      end
    end
  end
end
