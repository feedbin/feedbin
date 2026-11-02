module Api
  module V3
    # The account object: plan, settings a client reads or writes, the
    # newsletter address and the page token. Setting names are the API's;
    # SETTINGS maps them onto the hstore keys the web app uses.
    class AccountSerializer
      # API name => [stored key, type]
      SETTINGS = {
        "podcast_sort" => ["podcast_sort_order", :sort],
        "podcast_download_limit" => ["podcast_download_limit", :integer],
        "hide_queue" => ["hide_airshow", :boolean],
        "hide_recently_read" => ["hide_recently_read", :boolean],
        "hide_updated" => ["hide_updated", :boolean],
        "hide_recently_played" => ["hide_recently_played", :boolean]
      }.freeze
      # API value => stored value, for podcast_sort. Stored names are the
      # Playlist sort_order enum's.
      SORTS = {"manual" => "custom", "published_desc" => "newest_first", "published_asc" => "oldest_first"}.freeze
      DEFAULT_DOWNLOAD_LIMIT = 10

      def initialize(user)
        @user = user
      end

      def to_h
        {
          object: "account",
          id: @user.id,
          email: @user.email,
          created_at: @user.created_at.utc.iso8601,
          plan: plan,
          newsletter_address: @user.newsletter_address,
          settings: settings,
          page_token: @user.page_token
        }
      end

      private

      def plan
        {
          id: @user.plan.stripe_id,
          name: @user.plan.name,
          status: status,
          expires_at: @user.expires_at&.utc&.iso8601
        }
      end

      def status
        if @user.suspended || ((@user.timed_plan? || @user.trial_plan?) && @user.expires_at&.past?)
          "expired"
        elsif @user.trial_plan?
          "trial"
        else
          "active"
        end
      end

      def settings
        SETTINGS.to_h do |name, (key, type)|
          value = @user.settings[key]
          [name, case type
                 when :sort then SORTS.key(value) || "manual"
                 when :integer then value.present? ? value.to_i : DEFAULT_DOWNLOAD_LIMIT
                 when :boolean then value == "1"
                 end]
        end
      end
    end
  end
end
