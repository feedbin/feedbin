module AccountMigrator
  class Setup
    include Sidekiq::Worker
    sidekiq_options queue: :utility_critical

    def perform(migration_id)
      @migration = AccountMigration.find(migration_id)
      client = ApiClient.new(@migration.api_token)
      streams = client.streams_list
      @migration.update(fw_streams: streams)
      subscriptions = client.subscriptions_list
      subscriptions.dig("feeds").natural_sort_by {|feed| feed["title"] }.each do |feed|
        @migration.account_migration_items.create!(fw_feed: feed)
      end
      @migration.processing!
    rescue ApiClient::Error, HTTP::Error => exception
      failed! "Feed Wrangler API Error: #{exception.message}"
    rescue => exception
      failed! "Unknown migration error."
      raise exception unless Rails.env.production?
    end

    def failed!(message)
      @migration.message = message
      @migration.failed!
    end
  end
end