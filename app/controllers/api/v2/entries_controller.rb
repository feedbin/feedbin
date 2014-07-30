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
          entries_response 'api_v2_entries_url'
        elsif params.has_key?(:starred) && 'true' == params[:starred]
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
          entries_response 'api_v2_entries_url'
        elsif !params.has_key?(:since)
          feed_ids = @user.subscriptions.pluck(:feed_id)
          @entries = Entry.where(feed_id: feed_ids).includes(:feed).order("entries.created_at DESC").page(params[:page])
          if params.has_key?(:per_page)
            @entries = @entries.per_page(params[:per_page])
          end
          entries_response 'api_v2_entries_url'
        else
          sorted_set_response
        end
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

      def sorted_set_response
        since = Time.parse(params[:since])
        since = "(%10.6f" % since.to_f

        cache_key = [since, params[:starred], params[:read]]
        cache_key = Digest::SHA1.hexdigest(cache_key.join(':'))
        cache_key = "user:#{@user.id}:sorted_entry_ids:#{cache_key}"

        entry_ids = get_entry_ids(cache_key, since, params[:read], params[:starred])

        if params[:page]
          page = params[:page].to_i
        else
          page = 1
        end

        if params[:per_page]
          per_page = params[:per_page].to_i
        else
          per_page = WillPaginate.per_page
        end

        pages = entry_ids.each_slice(per_page).to_a
        next_page = page + 1
        previous_page = page - 1

        current_page_index = page - 1
        if entry_ids.blank?
          @entries = []
        elsif page <= 0 || pages[current_page_index].nil?
          status_not_found
        else
          @entries = Entry.where(id: pages[current_page_index]).includes(:feed)
          @entries.map { |entry|
            entry.content = ContentFormatter.api_format(entry.content, entry)
            entry
          }
          collection = OpenStruct.new(
            total_pages: pages.length,
            next_page: pages[next_page] ? next_page : nil,
            previous_page: (previous_page > 0) ? previous_page : nil
          )
          links_header(collection, 'api_v2_entries_url')
        end
      end

      def get_entry_ids(cache_key, since, read, starred)
        key_exists, entry_ids = $redis.multi do
          $redis.exists(cache_key)
          $redis.lrange(cache_key, 0, -1)
        end

        unless key_exists

          feed_ids = @user.subscriptions.pluck(:feed_id)

          keys = feed_ids.map do |feed_id|
            Feedbin::Application.config.redis_feed_entries_created_at % feed_id
          end

          scores = $redis.pipelined do
            keys.each do |key|
              $redis.zrangebyscore(key, since, "+inf", with_scores: true)
            end
          end

          scores = scores.flatten(1)
          scores = scores.sort_by {|score| score[1]}.reverse

          entry_ids = scores.map {|(feed_id, _)| feed_id.to_i}

          if 'false' == starred
            starred_entry_ids = @user.starred_entries.pluck(:entry_id)
            entry_ids = entry_ids - starred_entry_ids
          end

          if ['true', 'false'].include?(read)
            unread_entry_ids = @user.unread_entries.pluck(:entry_id)
            if 'false' == read
              entry_ids = entry_ids & unread_entry_ids
            elsif 'true' == read
              entry_ids = entry_ids - unread_entry_ids
            end
          end

          cache_entry_ids(cache_key, entry_ids)
        end

       entry_ids.map(&:to_i)
      end

      def cache_entry_ids(cache_key, entry_ids)
        if entry_ids.present?
          $redis.multi do
            $redis.del(cache_key)
            $redis.rpush(cache_key, entry_ids)
            $redis.expire(cache_key, 2.minutes.to_i)
          end
        end
      end

    end
  end
end