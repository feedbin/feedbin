module ContentFilters
  class Scrub < HTML::Pipeline::Filter

    NEWSLETTER_ELEMENTS = %w[table thead tbody tfoot tr td center]
    DASHED_ELEMENT_PARENTS = %w[svg math]

    def call
      doc
        .scrub!(custom_elements)
        .scrub!(:prune)
        .scrub!(video)
        .scrub!(links)
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
          node.name = "div"
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