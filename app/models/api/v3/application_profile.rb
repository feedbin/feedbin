module Api
  module V3
    # What an OAuth application's owner says about it: a description, where
    # to find it, how to reach them, and the logo the authorize page shows.
    # The logo is always re-encoded: nothing an uploader sent is ever served
    # back as it arrived.
    class ApplicationProfile < ApplicationRecord
      self.table_name = "oauth_application_profiles"

      LOGO_SIZE = 256
      LOGO_MAX_BYTES = 5.megabytes
      LOGO_FORMATS = %i[png jpeg gif webp]

      normalizes :description, :url, :contact_email, with: -> { it.strip.presence }

      validates :description, length: {maximum: 500}
      validates :url, length: {maximum: 2_000}
      validates :contact_email, length: {maximum: 255}, format: {with: URI::MailTo::EMAIL_REGEXP, message: "is not an email address", allow_nil: true}
      validate :url_is_a_web_address
      validate :logo_file_was_accepted

      # Everything but the logo's bytes, which only the logo itself needs.
      scope :without_logo, -> { select(column_names - ["logo"]) }

      # The application's profile, unsaved if it has none yet.
      def self.for(application)
        find_or_initialize_by(application_id: application.id)
      end

      # An upload becomes the logo when the profile is saved. One that is not
      # an image we accept fails validation, and the logo stays as it was.
      def logo_file=(upload)
        return unless upload.respond_to?(:path)
        @logo_refused = false
        if (png = self.class.png(upload))
          assign_attributes(logo: png, logo_updated_at: Time.current)
        else
          @logo_refused = true
        end
      end

      def logo?
        logo_updated_at.present?
      end

      def remove_logo
        update!(logo: nil, logo_updated_at: nil) if persisted?
      end

      # Saves the application and this profile of it together, or neither.
      # Both are validated first, so each one's errors are there to show.
      def save_with(application)
        return false unless [application.valid?, valid?].all?
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
