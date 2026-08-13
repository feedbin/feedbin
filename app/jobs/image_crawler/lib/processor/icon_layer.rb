module ImageCrawler
  module Processor
    # Picks the layer to render out of a multi-layer icon source. An .ico
    # carries several sizes; the largest is the one worth scaling, but plenty
    # of sites ship a large layer that is blank, transparent black, or solid
    # white padding around a smaller real icon. Reject those and take the
    # largest of what is left.
    #
    # Shared deliberately: FaviconCrawler::Image keeps running through the
    # whole icon migration, and a forked copy of these heuristics would drift
    # from the one the new presets use.
    class IconLayer
      INVALID_COLORS = [
        -> (color) { color.nil? },
        -> (color) { color == "00000000" },        # opacity bit matters for black
        -> (color) { color.start_with?("ffffff") } # ignore opacity bit for white because the result is white
      ]

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
          .find       { |layer|
            !INVALID_COLORS.any? { |proc| proc.call(color(layer)) }
          }
      end

      private

      def load_layer(page)
        begin
          Vips::Image.new_from_file(@path, page: page)
        rescue Vips::Error
          Vips::Image.new_from_file(@path)
        end
      rescue Vips::Error
        nil
      end

      def color(source)
        hex = nil
        file = ImageProcessing::Vips
          .source(source)
          .resize_to_fill(1, 1, sharpen: false)
          .custom { |image|
            image.tap do |data|
              hex = data.getpoint(0, 0).first(3).map { "%02x" % it }.join
            end
          }
          .call
        file.unlink
        hex
      end
    end
  end
end
