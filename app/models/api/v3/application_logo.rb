module Api
  module V3
    # The image an OAuth application shows on the authorize page. Small enough
    # to live in the database, and always re-encoded: nothing an uploader sent
    # is ever served back as it arrived.
    class ApplicationLogo < ApplicationRecord
      self.table_name = "oauth_application_logos"

      SIZE = 256
      MAX_BYTES = 5.megabytes
      FORMATS = %i[png jpeg gif webp]

      def self.for(application)
        find_by(application_id: application.id)
      end

      # Returns the logo, or nil when the upload is not an image we accept.
      def self.replace(application, upload)
        data = png(upload) or return
        logo = find_or_initialize_by(application_id: application.id)
        logo.update!(data: data)
        logo
      end

      def self.png(upload)
        return if upload.size > MAX_BYTES
        return unless FORMATS.include?(ImageFormat.detect(upload.path))

        ImageProcessing::Vips
          .source(upload.path)
          .resize_to_limit(SIZE, SIZE)
          .call(save: false)
          .write_to_buffer(".png")
      rescue Vips::Error
        nil
      end
      private_class_method :png
    end
  end
end
