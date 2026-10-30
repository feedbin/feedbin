module Api
  module V3
    # The image object: one stored rendition on Feedbin's image host.
    class ImageSerializer
      def initialize(image)
        @image = image
      end

      def to_h
        {
          kind: @image.kind,
          url: @image.public_url,
          width: @image.width,
          height: @image.height,
          size_in_bytes: @image.bytesize,
          placeholder_color: @image.placeholder_color.presence&.then { "##{_1}" },
          source_url: @image.final_url || @image.url,
          fingerprint: Image.normalize_fingerprint(@image.image_fingerprint)
        }
      end
    end
  end
end
