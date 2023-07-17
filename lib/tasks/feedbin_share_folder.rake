namespace :feeds do
    desc "Share Folder to another user"
    task :share_folder, [:user_id, :tag_id] => :environment do |_, args|
      user_id = args[:user_id]
      tag_id = args[:tag_id]

      # Selects all feeds on specific tag
      feeds_ids = Tag.find(tag_id).feeds.pluck(:id)
      #puts "{\e[31mfeeds_ids\e[0m #{feeds_ids}}"

      # Insert operations
      feeds_ids.each do |feed_id|
        Subscription.new(user_id: user_id, feed_id: feed_id).save # Subcribe to all new feeds
        Tagging.new(feed_id: feed_id, user_id: user_id, tag_id: tag_id).save # Insert new feed to the folder
      end

      # View all entries for specific TAG
      entries = Entry.where(feed_id: Tag.find(tag_id).feeds.pluck(:id)).pluck(:id, :feed_id)
      #puts "\e[31mEntries id\e[0m {#{entries}}"

      # Mark all this new entries like unread
      entries.each do |entry_id, feed_id|
        UnreadEntry.new(user_id: user_id, feed_id: feed_id, entry_id: entry_id, published: Time.now, entry_created_at: Time.now ).save
      end
    end
  end