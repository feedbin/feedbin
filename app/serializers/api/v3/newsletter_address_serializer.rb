module Api
  module V3
    class NewsletterAddressSerializer
      def initialize(address)
        @address = address
      end

      # default_tag is newsletter_tag: a tag name, which is what is stored.
      def to_h
        {
          object: "newsletter_address",
          id: @address.id,
          address: @address.title,
          token: @address.token,
          description: @address.description.presence,
          default_tag: @address.newsletter_tag.presence,
          active: @address.active,
          created_at: @address.created_at.utc.iso8601
        }
      end
    end
  end
end
