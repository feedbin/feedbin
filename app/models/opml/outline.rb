module Opml
  class Outline
    def initialize(node, tag)
      @node = node
      @tag = tag
    end

    def to_h
      Hash.new.tap do |hash|
        @node.attributes.each do |name, attribute|
          hash[name.underscore.to_sym] = attribute.value
        end
        hash[:tag] = @tag
      end
    end
  end
end