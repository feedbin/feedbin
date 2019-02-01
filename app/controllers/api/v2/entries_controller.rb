module Api
  module V2
    class EntriesController < ApiController
      include RedisCache

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
          @entries = Entry.where(id: @ids, feed_id: allowed_feed_ids).page(nil).includes(:feed)
          entries_response "api_v2_entries_url"
        elsif params.key?(:starred) && params[:starred] == "true"
          page = if params[:page]
            params[:page].to_i
          else
            1
          end
          @starred_entries = @user.starred_entries.select(:entry_id).order("created_at DESC").page(page)
          if params.key?(:per_page)
            @starred_entries = @starred_entries.per_page(params[:per_page].to_i)
          end
          @entries = Entry.where(id: @starred_entries.map { |starred_entry| starred_entry.entry_id }).includes(:feed)
          entries_response "api_v2_entries_url"
        else
          sorted_set_response
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

      def sorted_set_response
        begin
          since = Time.parse(params[:since])
          since = "(%10.6f" % since.to_f
        rescue TypeError
          since = "-inf"
        end

        cache_key = [since, params[:starred], params[:read]]
        cache_key = Digest::SHA1.hexdigest(cache_key.join(":"))
        cache_key = "user:#{@user.id}:sorted_entry_ids:#{cache_key}"

        entry_ids = get_cached_entry_ids(cache_key, FeedbinUtils::FEED_ENTRIES_CREATED_AT_KEY, since, params[:read], params[:starred])
        pagination = build_pagination(entry_ids)

        if entry_ids.blank?
          @entries = []
        elsif pagination[:page] <= 0 || pagination[:paged_entry_ids][pagination[:page_index]].nil?
          status_not_found
        else
          @entries = Entry.where(id: pagination[:paged_entry_ids][pagination[:page_index]]).includes(:feed).order(created_at: :desc)
          links_header(pagination[:will_paginate], "api_v2_entries_url")
        end
      end
    end
  end
end
