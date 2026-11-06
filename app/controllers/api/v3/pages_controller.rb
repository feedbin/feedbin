module Api
  module V3
    class PagesController < ApiController
      PAGES_PER_DAY = 100

      before_action :set_page, only: :destroy

      def create
        url = web_url("url")
        title = optional_string("title")
        return status_rate_limited(retry_after: 1.day, detail: "The account saved #{PAGES_PER_DAY} pages today. Try again tomorrow.") unless Throttle.throttle!("v3:pages:#{@user.id}", PAGES_PER_DAY, 1.day)

        entry, created = store_page(url, title)
        render json: serialize_entries([entry]).first, status: created ? :created : :ok
      end

      def destroy
        EntryDeleter.new.delete_entries(@page.feed_id, @page.id)
        head :no_content
      end

      private

      def set_page
        @page = @user.entries.find(params[:id])
        raise ActiveRecord::RecordNotFound unless @page.feed.pages? && @user.subscriptions.generated.exists?(feed_id: @page.feed_id)
      end

      # Checked before saving: SavePage can save a new entry twice, clearing previously_new_record?.
      # => [entry, created]
      def store_page(url, title)
        existed = Entry.exists?(public_id: SavePage.public_id_for(@user, url))
        entry = begin
          SavePage.new.perform(@user.id, url, title)
        rescue SavePage::MissingPage => exception
          SavePage.perform_async(@user.id, url, title)
          exception.entry
        end
        [entry, !existed]
      end

      def web_url(field)
        url = body[field]
        uri = Addressable::URI.parse(url.strip) if url.is_a?(String)
        raise invalid(field, "invalid_value", "#{field} must be an http or https URL.") unless uri && %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
        url
      rescue Addressable::URI::InvalidURIError
        raise invalid(field, "invalid_value", "#{field} must be an http or https URL.")
      end
    end
  end
end
