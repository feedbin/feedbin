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

    def parse(data = nil, tag = nil)
      data ||= outlines
      data.each do |node|
        next unless node.name == "outline"
        outline = Outline.new(node, tag).to_h
        if node.children.length > 0
          title = outline[:title] || outline[:text]
          parse(node.children, title)
        else
          @feeds << outline
        end
      end
    end
  end
end
