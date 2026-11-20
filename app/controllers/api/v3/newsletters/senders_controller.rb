module Api
  module V3
    module Newsletters
      # Allowed or blocked is whether the user subscribes to the sender's feed,
      # as on the web.
      class SendersController < ApiController
        before_action :set_sender, only: :update

        def index
          data = senders.order(Arel.sql("lower(name)"), :id).map { serialize(it) }
          return unless stale?(etag: digest(data))
          render_list(data)
        end

        def update
          Subscription.set_subscribed(@user, @sender.feed_id, boolean("subscribed"))
          render json: serialize(@sender)
        end

        private

        def set_sender
          @sender = senders.find(params[:id])
        end

        def senders
          NewsletterSender.where(token: address_ids.keys)
        end

        # {token => address id}, inactive addresses included.
        def address_ids
          @address_ids ||= @user.authentication_tokens.newsletters.pluck(:token, :id).to_h
        end

        def subscribed_feed_ids
          @subscribed_feed_ids ||= @user.subscriptions.pluck(:feed_id).to_set
        end

        def serialize(sender)
          NewsletterSenderSerializer.new(sender, address_id: address_ids[sender.token], subscribed: subscribed_feed_ids.include?(sender.feed_id)).to_h
        end
      end
    end
  end
end
