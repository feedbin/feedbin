module Api
  module V3
    # The attachment object, in JSON Feed's shape: a file the entry carries,
    # such as a podcast episode's audio.
    class AttachmentSerializer
      KINDS = %w[audio video image].freeze
      DOCUMENT_TYPES = %w[application/pdf application/epub+zip text/plain].freeze

      def initialize(url:, mime_type:, size_in_bytes: nil, duration_in_seconds: nil, chapters: nil)
        @url = url
        @mime_type = mime_type
        @size_in_bytes = size_in_bytes
        @duration_in_seconds = duration_in_seconds
        @chapters = chapters
      end

      def to_h
        {
          url: @url,
          mime_type: @mime_type,
          kind: kind,
          title: nil,
          size_in_bytes: @size_in_bytes,
          duration_in_seconds: @duration_in_seconds,
          chapters: @chapters
        }
      end

      private

      def kind
        type = @mime_type.to_s.downcase
        major = type.split("/").first
        return major if KINDS.include?(major)
        return "document" if DOCUMENT_TYPES.include?(type)
        "other"
      end
    end
  end
end
