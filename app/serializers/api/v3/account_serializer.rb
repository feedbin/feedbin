module Api
  module V3
    class AccountSerializer
      # API name => [stored hstore key, type]
      SETTINGS = {
        "podcast_sort" => ["podcast_sort_order", :sort],
        "podcast_download_limit" => ["podcast_download_limit", :integer],
        "hide_queue" => ["hide_airshow", :boolean],
        "hide_recently_read" => ["hide_recently_read", :boolean],
        "hide_updated" => ["hide_updated", :boolean],
        "hide_recently_played" => ["hide_recently_played", :boolean]
      }.freeze
      # podcast_sort API value => Playlist sort_order enum value.
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
          settings: settings
        }
      end

      private

      def plan
        {
          id: plan_id,
          name: @user.plan.name,
          status: status,
          expires_at: expires_at&.utc&.iso8601,
          billing: billing
        }
      end

      # A store's plan ends when the store says its subscription does.
      def expires_at
        subscription = store_subscription if @user.store_plan?
        return @user.expires_at unless subscription
        subscription.grace? ? subscription.grace_expires_at : subscription.expires_at
      end

      # Who takes the money, and what a Billing page says about it. A store's
      # subscription is described even when it no longer pays for the account,
      # so a lapsed one can say when and why it ended.
      def billing
        subscription = store_subscription
        billing = if @user.web_plan_active? || (subscription.nil? && @user.plan.stripe_id.start_with?("basic-"))
          web_billing
        elsif subscription
          store_billing(subscription)
        else
          no_billing
        end
        # What an app hands the store with a purchase (StoreKit's
        # appAccountToken), so the store's own notice of it names the account.
        billing.merge(account_token: @user.app_account_token)
      end

      # The same keys whoever bills, so a client reads one shape.
      def no_billing
        {source: nil, state: nil, product_id: nil, period: nil, price: nil, renews: false, renews_as: nil, current_period_ends_at: nil, grace_ends_at: nil}
      end

      # The one that pays, else the one that last did.
      def store_subscription
        return @store_subscription if defined?(@store_subscription)
        @store_subscription = @user.store_subscriptions.order(Arel.sql("status IN (0, 1) DESC"), expires_at: :desc).first
      end

      def store_billing(subscription)
        {
          source: subscription.store,
          state: subscription.status,
          product_id: subscription.product_id,
          period: subscription.period,
          price: price(subscription.price, subscription.currency),
          renews: subscription.auto_renew && !subscription.expired? && !subscription.revoked?,
          renews_as: subscription.renews_as,
          current_period_ends_at: subscription.expires_at&.utc&.iso8601,
          grace_ends_at: (subscription.grace_expires_at&.utc&.iso8601 if subscription.grace?)
        }
      end

      def web_billing
        {
          source: "web",
          state: @user.suspended ? "expired" : (@user.billing_issue? ? "retrying" : "active"),
          product_id: nil,
          period: @user.plan.name.downcase.presence_in(%w[monthly yearly]),
          price: price(@user.plan.price, "USD"),
          renews: !@user.suspended,
          renews_as: nil,
          current_period_ends_at: nil,
          grace_ends_at: nil
        }
      end

      def price(amount, currency)
        amount && currency && {amount: format("%.2f", amount), currency: currency}
      end

      # A Stripe id carries a price tier (basic-yearly-3) that changes with
      # pricing; the API names the plan (yearly).
      def plan_id
        @user.plan.stripe_id.delete_prefix("basic-").sub(/-\d+\z/, "").tr("-", "_")
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
