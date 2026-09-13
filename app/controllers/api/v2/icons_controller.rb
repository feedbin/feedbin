module Api
  module V2
    class IconsController < ApiController
      respond_to :json

      def index
        feed_ids = current_user.subscriptions.pluck(:feed_id)
        hosts = Feed.where(id: feed_ids).distinct.pluck(:host).compact
        rows = Image.provider_website_favicon.where(provider_id: hosts)
        @icons = rows.filter_map { |record|
          {host: record.provider_id, url: record.public_url} if record.public_url
        }
      end
    end
  end
end
