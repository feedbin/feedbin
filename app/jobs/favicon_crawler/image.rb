module FaviconCrawler
  class Image

    INVALID_COLORS = ["00000000", "ffffffff", nil]

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
        .filter_map { load_layer(_1) }
        .uniq       { _1.size }
        .sort_by    { _1.size.first * -1 }
        .find       { !INVALID_COLORS.include?(color(_1)) }
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
            hex = data.getpoint(0, 0).map { "%02x" % _1 }.join
          end
        }
        .call
      file.unlink
      hex
    end
  end
end