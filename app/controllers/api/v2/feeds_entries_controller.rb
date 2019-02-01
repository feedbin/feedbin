module Api
  module V2
    class FeedsEntriesController < ApiController
      respond_to :json
      before_action :correct_user

      def index
        @user = current_user
        @entries = Entry.where(feed_id: params[:feed_id]).includes(:feed).order("entries.created_at DESC").page(params[:page])
        if params.key?(:per_page)
          @entries = @entries.per_page(params[:per_page])
        end
        entries_response "api_v2_feed_entries_url"
      end

      def show
        fresh_when(@entry)
      end

      private

      def correct_user
        if params[:action] == "index"
          if !Feed.where(id: params[:feed_id]).present?
            status_not_found
          elsif !current_user.subscribed_to?(params[:feed_id])
            status_forbidden
          end
        elsif params[:action] == "show"
          @entry = Entry.find(params[:id])
          if !@entry.present?
            status_not_found
          elsif !current_user.subscribed_to?(@entry.feed_id)
            status_forbidden
          end
        end
      end
    end
  end
end
