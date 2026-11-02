module Api
  module V3
    # Saved pages: an entry in the user's Pages feed. Saving runs SavePage in
    # the request, as v2 does; when extraction fails it retries in the
    # background and the entry fills in later.
    class PagesController < ApiController
      PAGES_PER_DAY = 100

      def create
        body = request.request_parameters
        url = body["url"]
        raise invalid("url", "invalid_value", "url must be an http or https URL.") unless web_url?(url)
        title = body["title"]
        raise invalid("title", "invalid_value", "title must be a string.") unless title.nil? || title.is_a?(String)
        return rate_limited unless Throttle.throttle!("v3:pages:#{@user.id}", PAGES_PER_DAY, 1.day)

        entry = begin
          SavePage.new.perform(@user.id, url, title)
        rescue SavePage::MissingPage => exception
          SavePage.perform_async(@user.id, url, title)
          exception.entry
        end
        expand = expansions(EntrySerializer::EXPANSIONS)
        feed = expand.include?("feed") ? FeedSerializer.new(entry.feed).to_h : nil
        render json: EntrySerializer.new(entry, feed: feed, expand: expand).to_h, status: entry.previously_new_record? ? :created : :ok
      end

      # Only an entry in the user's own Pages feed.
      def destroy
        entry = @user.entries.find(params[:id])
        raise ActiveRecord::RecordNotFound unless entry.feed.pages?
        EntryDeleter.new.delete_entries(entry.feed_id, entry.id)
        head :no_content
      end

      private

      def web_url?(url)
        return false unless url.is_a?(String)
        uri = Addressable::URI.parse(url.strip)
        %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
      rescue Addressable::URI::InvalidURIError
        false
      end

      def rate_limited
        response.set_header("Retry-After", 1.day.to_i.to_s)
        render_problem :too_many_requests, "rate_limited",
          title: "Rate limited",
          detail: "The account saved #{PAGES_PER_DAY} pages today. Try again tomorrow."
      end

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "/#{field}", code: code)
      end
    end
  end
end
