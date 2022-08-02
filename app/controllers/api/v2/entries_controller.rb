module Api
  module V2
    class EntriesController < ApiController
      respond_to :json
      before_action :correct_user, only: [:show]
      before_action :limit_ids, only: [:index]
      skip_before_action :authorize, only: [:text]

      def index
        @user = current_user
        if params.key?(:ids)
          allowed_feed_ids = []
          allowed_feed_ids = allowed_feed_ids.concat(@user.starred_entries.select("DISTINCT feed_id").map { |entry| entry.feed_id })
          allowed_feed_ids = allowed_feed_ids.concat(@user.subscriptions.pluck(:feed_id))
          @page_query = Entry.where(id: @ids, feed_id: allowed_feed_ids).page(nil).includes(:feed)
          entries_response "api_v2_entries_url"
        else
          @feed_ids = @user.subscriptions.pluck(:feed_id)
          @page_query = Entry.where(feed_id: @feed_ids).order(created_at: :desc).page(params[:page])
          entries_response "api_v2_entries_url"
        end
      end

      def show
        fresh_when(@entry)
      end

      def text
        entry = Entry.find(params[:id])
        render plain: EntriesHelper.text_format(entry.content), content_type: "text/plain"
      end

      def watch
        @user = current_user
        if @user.can_read_entry?(params[:id])
          @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) { |(feed_id, title), hash|
            hash[feed_id] = title
          }
          @entry = Entry.find(params[:id])
        else
          render_404
        end
      end

      private

      def limit_ids
        if params.key?(:ids)
          @ids = params[:ids].split(",").map { |i| i.to_i }
          if @ids.respond_to?(:count)
            if @ids.count > 100
              status_bad_request([{ids: "Please request less than or equal to 100 ids per request"}])
            end
          end
        end
      end

      def correct_user
        @user = current_user
        @entry = Entry.find(params[:id])
        if !@entry.present?
          status_not_found
        elsif !@user.subscribed_to?(@entry.feed.id)
          status_forbidden
        end
      end
    end
  end
end
