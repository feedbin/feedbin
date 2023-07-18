namespace :feeds do
    desc "Share Folder to another user"
    task :share_folder, [:user_id, :tag_id] => :environment do |_, args|
      # Verify that this user exist
      user_id = args[:user_id]
      begin
        User.find(user_id)
      rescue => ActiveRecord::RecordNotFound
        puts "\e[31mUser with {user_id : #{user_id}} does not exist} \e[0m"
        exit
      end
      # Verify that tag exist
      tag_id = args[:tag_id]
      begin
        Tag.find(tag_id)
      rescue => ActiveRecord::RecordNotFound
        puts "\e[31mTag with {tag_id : #{tag_id}} does not exist} \e[0m"
        exit
      end

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