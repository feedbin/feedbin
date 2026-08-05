module Opml
  class Parser

    attr_reader :feeds

    def self.parse(*args)
      instance = new(*args)
      instance.parse
      instance.feeds
    end

    def initialize(xml)
      @xml = xml
      @feeds = []
    end

    def outlines
      @outlines ||= Nokogiri::XML.parse(@xml).css("body").children
    end

    # OPML's rule is that an outline carrying an xmlUrl is a subscription;
    # nesting is orthogonal to that. Classifying on node.children counted the
    # whitespace between a paired <outline></outline> as a child and dropped
    # the feed, which is every feed in the file for a producer that writes
    # them that way.
    def parse(data = nil, tag = nil)
      data ||= outlines
      data.each do |node|
        next unless node.name == "outline"
        outline = Outline.new(node, tag).to_h

        @feeds << outline if outline[:xml_url].present?

        nested = node.element_children.select { _1.name == "outline" }
        if nested.any?
          title = outline[:title] || outline[:text]
          parse(nested, title)
        end
      end
    end
  end
end
