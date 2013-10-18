module Api
  module V2
    class EntriesController < ApiController

      respond_to :json
      before_action :correct_user, only: [:show]
      before_action :limit_ids, only: [:index]

      def index
        @user = current_user
        if params.has_key?(:ids)
          allowed_feed_ids = []
          allowed_feed_ids = allowed_feed_ids.concat(@user.starred_entries.select('DISTINCT feed_id').map {|entry| entry.feed_id})
          allowed_feed_ids = allowed_feed_ids.concat(@user.subscriptions.pluck(:feed_id))
          @entries = Entry.where(id: @ids, feed_id: allowed_feed_ids).page(nil).includes(:feed)
        elsif params.has_key?(:starred)  && 'true' == params[:starred]
          if params[:page]
            page = params[:page].to_i
          else
            page = 1
          end
          @starred_entries = @user.starred_entries.select(:entry_id).order("created_at DESC").page(page)
          if params.has_key?(:per_page)
            @starred_entries = @starred_entries.per_page(params[:per_page].to_i)
          end
          @entries = Entry.where(id: @starred_entries.map {|starred_entry| starred_entry.entry_id }).includes(:feed)
        else
          @entries = @user.entries.includes(:feed).order("entries.created_at DESC").page(params[:page])
          if params.has_key?(:per_page)
            @entries = @entries.per_page(params[:per_page])
          end
        end
        entries_response 'api_v2_entries_url'
      end

      def show
        fresh_when(@entry)
      end

      private

      def limit_ids
        if params.has_key?(:ids)
          @ids = params[:ids].split(',').map {|i| i.to_i }
          if @ids.respond_to?(:count)
            if @ids.count > 100
              status_bad_request([{ids: 'Please request less than or equal to 100 ids per request'}])
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