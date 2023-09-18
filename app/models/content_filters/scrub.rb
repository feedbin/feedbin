module ContentFilters
  TABLE_ELEMENTS = %w[table thead tbody tfoot tr td]

  class Scrub < HTML::Pipeline::Filter
    def call
      doc
        .scrub!(:prune)
        .scrub!(video)
        .scrub!(links)
      if context[:scrub_mode] == :newsletter
        doc.scrub!(tables)
      end
      doc
    end

    def tables
      Loofah::Scrubber.new do |node|
        if TABLE_ELEMENTS.include?(node.name)
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