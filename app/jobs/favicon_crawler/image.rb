module FaviconCrawler
  class Image

    INVALID_COLORS = [
      -> (color) { color.nil? },
      -> (color) { color == "00000000" },        # opacity bit matters for black
      -> (color) { color.start_with?("ffffff") } # ignore opacity bit for white because the result is white
    ]


    def self.resize(*args)
      new(*args).resize
    end

    def resize
      image = best_layer

      return unless image.present?

      ImageProcessing::Vips
        .source(image)
        .resize_to_fit(32, 32)
        .saver(strip: true)
        .convert("png")
        .call
    end

    private

    def initialize(path)
      @path = path
    end

    def best_layer
      (0..4)
        .filter_map { load_layer(it) }
        .uniq       { it.size }
        .sort_by    { it.size.first * -1 }
        .find       { |layer|
          !INVALID_COLORS.any? { |proc| proc.call(color(layer)) }
        }
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
