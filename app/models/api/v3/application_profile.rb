module Api
  module V3
    # What an OAuth application's owner says about it: a description, where
    # to find it, how to reach them, and the logo the authorize page shows.
    # The logo is an object in the image store, always re-encoded: nothing an
    # uploader sent is ever served back as it arrived.
    class ApplicationProfile < ApplicationRecord
      self.table_name = "oauth_application_profiles"

      LOGO_SIZE = 256
      LOGO_MAX_BYTES = 5.megabytes
      LOGO_FORMATS = %i[png jpeg gif webp]
      LOGO_HEADERS = {"Content-Type" => "image/png", "Cache-Control" => "max-age=315360000, public, immutable"}.freeze

      normalizes :description, :url, :contact_email, with: -> { it.strip.presence }

      validates :description, length: {maximum: 500}
      validates :url, length: {maximum: 2_000}
      validates :contact_email, length: {maximum: 255}, format: {with: URI::MailTo::EMAIL_REGEXP, message: "is not an email address", allow_nil: true}
      validate :url_is_a_web_address
      validate :logo_file_was_accepted

      before_save { throw :abort unless store_logo }
      after_commit :sweep_replaced_logo, on: [:update, :destroy]

      # The application's profile, unsaved if it has none yet.
      def self.for(application)
        find_or_initialize_by(application_id: application.id)
      end

      # An upload becomes the logo when the profile is saved. One that is not
      # an image we accept fails validation, and the logo stays as it was.
      def logo_file=(upload)
        return unless upload.respond_to?(:path)
        @logo_png = self.class.png(upload)
        @logo_refused = @logo_png.nil?
      end

      def logo?
        logo_storage_path.present?
      end

      # nil without a logo, and where the image host is not set.
      def logo_url
        Image.public_url_for(logo_storage_path)
      end

      def remove_logo
        update!(logo_storage_path: nil) if persisted?
      end

      # Saves the application and this profile of it together, or neither.
      # Both are validated first, so each one's errors are there to show, and
      # the logo is stored before the transaction opens.
      def save_with(application)
        return false unless [application.valid?, valid?].all? && store_logo
        transaction do
          application.save!
          update!(application_id: application.id)
        end
        true
      end

      def self.png(upload)
        return if upload.size > LOGO_MAX_BYTES
        return unless LOGO_FORMATS.include?(ImageFormat.detect(upload.path))

        ImageProcessing::Vips
          .source(upload.path)
          .resize_to_limit(LOGO_SIZE, LOGO_SIZE)
          .call(save: false)
          .write_to_buffer(".png")
      rescue Vips::Error
        nil
      end

      private

      # Puts a pending upload in the image store under a path of its own. A
      # path is never used twice, so a cached logo is never stale and deleting
      # an old one cannot take a newer one with it. False, with an error,
      # when the store does not take it.
      def store_logo
        return true unless @logo_png
        raise Excon::Error, "the image store is not configured" unless Image.storage_configured?

        path = Image.path_for(SecureRandom.hex(16), "png")
        Image.storage_client.put_object(Image.bucket, path, @logo_png, LOGO_HEADERS)
        self.logo_storage_path = path
        @logo_png = nil
        true
      rescue Excon::Error => exception
        ErrorService.notify(exception)
        errors.add(:base, "Logo could not be stored. Try again")
        false
      end

      # SweepStoredImages deletes the paths no images row references, which a
      # logo's never is.
      def sweep_replaced_logo
        replaced = destroyed? ? logo_storage_path : saved_change_to_logo_storage_path&.first
        SweepStoredImages.perform_async([replaced]) if replaced
      end

      # The URL is rendered as a link, so nothing but http and https.
      def url_is_a_web_address
        return if url.nil?
        uri = URI.parse(url)
        errors.add(:base, "URL must start with http:// or https://") unless uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        errors.add(:base, "URL must start with http:// or https://")
      end

      def logo_file_was_accepted
        errors.add(:base, "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB") if @logo_refused
      end
    end
  end
end
