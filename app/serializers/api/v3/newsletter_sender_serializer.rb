module Api
  module V3
    class NewsletterSenderSerializer
      # address_id: the newsletter address the sender wrote to.
      # subscribed: whether the user subscribes to the sender's feed.
      def initialize(sender, address_id:, subscribed:)
        @sender = sender
        @address_id = address_id
        @subscribed = subscribed
      end

      def to_h
        {
          object: "newsletter_sender",
          id: @sender.id,
          name: @sender.name,
          email: @sender.email,
          address_id: @address_id,
          feed_id: @sender.feed_id,
          subscribed: @subscribed
        }
      end
    end
  end
end
