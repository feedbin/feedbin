module ContentFilters
  class Scrub < HTML::Pipeline::Filter

    NEWSLETTER_ELEMENTS = %w[table thead tbody tfoot tr td center]
    DASHED_ELEMENT_PARENTS = %w[svg math]

    def call
      doc
        .scrub!(custom_elements)
        .scrub!(:prune)
        .scrub!(responsive_svg_duplicates)
        .scrub!(video)
        .scrub!(links)
        .scrub!(iframe)
      if context[:scrub_mode] == :newsletter
        doc.scrub!(newsletter_elements)
      end
      doc
    end

    def custom_elements
      Loofah::Scrubber.new do |node|
        if DASHED_ELEMENT_PARENTS.include?(node.name)
          Loofah::Scrubber::STOP
        elsif node.name.include?("-")
          node.name = "span"
        end
      end
    end

    # Sites often ship a wide and a narrow copy of the same diagram and pick one
    # with a class-based media query. We strip classes, so both would show.
    def responsive_svg_duplicates
      Loofah::Scrubber.new do |node|
        if node.name == "svg" && node.previous_element&.name == "svg"
          node.remove
        end
      end
    end

    def newsletter_elements
      Loofah::Scrubber.new do |node|
        if NEWSLETTER_ELEMENTS.include?(node.name)
          node.name = "div"
          node.keys.each do |attribute|
            node.delete attribute
          end
        end
      end
    end

    def video
      Loofah::Scrubber.new do |node|
        if node.name == "video"
          node["preload"] = "none"
        end
      end
    end

    def iframe
      Loofah::Scrubber.new do |node|
        if node.name == "iframe"
          node["referrerpolicy"] = "strict-origin-when-cross-origin"
        end
      end
    end

    def links
      Loofah::Scrubber.new do |node|
        if node.name == "a" && node["href"] == node.text
          if shortened = node["href"].gsub(/https?:\/\//, "").truncate(40, omission: "…") rescue nil
            node.content = shortened
          end
        end
      end
    end
  end
end