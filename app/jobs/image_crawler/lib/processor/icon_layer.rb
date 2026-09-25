module ImageCrawler
  module Processor
    # Picks the layer to render out of a multi-layer icon source. An .ico
    # carries several sizes; the largest is the one worth scaling, but plenty
    # of sites ship a large layer that is blank, transparent black, or solid
    # white padding around a smaller real icon. Reject those and take the
    # largest of what is left.
    class IconLayer
      # Returns a Vips::Image, or nil when nothing in the source is usable.
      def self.best(path)
        new(path).best
      end

      def initialize(path)
        @path = path
      end

      def best
        (0..4)
          .filter_map { load_layer(it) }
          .uniq       { it.size }
          .sort_by    { it.size.first * -1 }
          .find       { !blank?(it) }
      end

      private

      # Blank is every pixel transparent, whatever colour sits under the
      # alpha, or white at any opacity, which renders as white. Opaque black
      # stays: plenty of logos are black. sRGB first, so the bands are always
      # red, green, blue and then alpha when there is one.
      def blank?(layer)
        red, green, blue, alpha = Processed.average(layer.colourspace(:srgb))
        alpha == 0 || [red, green, blue].all?(255)
      end

      def load_layer(page)
        begin
          Vips::Image.new_from_file(@path, page: page)
        rescue Vips::Error
          Vips::Image.new_from_file(@path)
        end
      rescue Vips::Error
        nil
      end
    end
  end
end
