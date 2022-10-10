module AccountMigrator
  class ImportFeed
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(item_id)
      @item = AccountMigrationItem.find(item_id)
      @migration = @item.account_migration
      @user = @migration.user
      @client = ApiClient.new(@migration.api_token)

      starred_items = @client.feed_items_list(params: {feed_id: @item.fw_feed&.dig("feed_id"), starred: true})

      feeds = begin
        FeedFinder.feeds(@item.fw_feed&.dig("feed_url"), import_mode: true)
      rescue Feedkit::Error => exception
        @item.message = "No feed found: #{exception.message}"
        []
      end

      @feed = feeds.first

      if @feed.blank? && starred_items.present?
        @feed = Feed.create(
          title: @item.fw_feed&.dig("title")&.strip,
          feed_url: @item.fw_feed&.dig("feed_url")&.strip,
          site_url: @item.fw_feed&.dig("site_url")&.strip,
        )
        @item.message = nil
      end

      if @feed.present?
        @user.subscriptions.create_with(title: @item.fw_feed&.dig("title")).find_or_create_by(feed: @feed)
      else
        failed! @item.message || "No feed found."
        return
      end

      message = ""
      message += import_starred(starred_items)
      message += import_unreads

      if @migration.streams.respond_to?(:[])
        if names = @migration.streams[@item.fw_feed&.dig("feed_id")]
          @feed.tag(names, @user, false)
        end
      end

      @item.message = message
      @item.complete!

      mark_complete
    rescue ApiClient::Error => exception
      failed! "API Error: #{exception.message}"
      mark_complete
    rescue => exception
      failed! "Unknown error"
      raise exception
    end

    def mark_complete
      @migration.with_lock do
        unless @migration.account_migration_items.where(status: :pending).exists?
          @migration.complete!
        end
      end
    end

    def import_starred(feed_items)
      entries = existing_entries(feed_items).to_a
      existing = entries.map(&:public_id)

      feed_items.each do |item|
        data = build_entry(item)
        next if existing.include?(data[:public_id])
        entry = @feed.entries.create!(data)
        entries.push(entry)
      end

      records = entries.map do |entry|
        StarredEntry.new_from_owners(@user, entry)
      end

      result = StarredEntry.import(records, validate: false, on_duplicate_key_ignore: true)

      expected_count = feed_items.count
      actual_count = result.ids.count

      build_message(expected_count, actual_count, "starred")
    end

    def build_entry(feed_item)
      {
        title:               feed_item.dig("title")&.strip,
        url:                 feed_item.dig("url")&.strip,
        author:              feed_item.dig("author")&.strip,
        content:             feed_item.dig("body")&.strip,
        published:           Time.at(feed_item.dig("published_at"))&.utc,
        updated:             Time.at(feed_item.dig("updated_at"))&.utc,
        entry_id:            generated?(feed_item) ? nil : feed_item.dig("guid"),
        public_id:           public_id(feed_item),
        source:              "import",
        skip_mark_as_unread: true,
      }
    end

    def import_unreads
      feed_items = @client.feed_items_list(params: {feed_id: @item.fw_feed&.dig("feed_id"), read: false}, limit: 400)

      @user.unread_entries.where(feed: @feed).delete_all

      entries = existing_entries(feed_items)

      records = entries.map do |entry|
        UnreadEntry.new_from_owners(@user, entry)
      end

      result = UnreadEntry.import(records, validate: false, on_duplicate_key_ignore: true)
      expected_count = feed_items.count
      actual_count = result.ids.count

      build_message(expected_count, actual_count, "unread")
    end

    def existing_entries(feed_items)
      ids = feed_items.map {|feed_item| public_id(feed_item) }
      entries = @feed.entries.where(public_id: ids)
    end

    def build_message(expected_count, actual_count, type)
      expected_count_formatted = ActiveSupport::NumberHelper.number_to_delimited(expected_count)
      actual_count_formatted = ActiveSupport::NumberHelper.number_to_delimited(actual_count)
      "Matched #{actual_count_formatted} of #{expected_count_formatted} #{type} #{'articles'.pluralize(expected_count_formatted)}. "
    end

    def failed!(message)
      @item.message = message
      @item.failed!
    end

    def public_id(feed_item)
      parts = []
      parts.push(@feed.feed_url)
      if generated?(feed_item)
        parts.push(feed_item["url"])
        parts.push(Time.at(feed_item["published_at"]).utc.iso8601)
        parts.push(feed_item["title"])
      else
        parts.push(feed_item["guid"])
      end
      Digest::SHA1.hexdigest(parts.compact.join)
    end

    def generated?(feed_item)
      guid = feed_item["guid"]
      url = feed_item["url"]
      title = feed_item["title"]

      return false if guid.nil? || url.nil? || title.nil?

      guid = guid.sub(url, "")

      return true if guid.length > 0 && title.start_with?(guid)

      return false
    end

  end
end