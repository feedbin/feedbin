namespace :feeds do
    desc "Share Folder to another user"
    task share_folder: :environment do
      # PRIMERA QUERY
      result = User.select('users.id', 'users.email', 'tags.id AS tag_id', 'tags.name AS tags_name')
              .where(id: 2)
              .joins(:tags)

      #result.each do |user|
      #  print "{\e[31mID: #{user.id}\e[0m, \e[31mEmail\e[0m: #{user.email}, \e[31mtag_id\e[0m: #{user.tag_id}, \e[31mtags.name\e[0m: #{user.tags_name}}\n"
      #end
      #puts "#{result.length}"

      # SEGUNDA QUERY
      result = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id as feed_id").joins("JOIN taggings ON tags.id=1 AND tags.id=taggings.tag_id JOIN feeds
        ON taggings.feed_id=feeds.id")
      #result.each do |user|
      #    print "{\e[31mtags.id\e[0m: #{user.tags_id}, \e[31mfeed_title\e[0m: #{user.feed_title}, \e[31mfeed_id\e[0m: #{user.feed_id}}\n"
      #end
      #puts "#{result.length}"

      # TERCERA QUERY
      result = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id AS feed_id", "entries.id AS entries_id").joins("JOIN taggings ON tags.id=1 AND tags.id=taggings.tag_id JOIN feeds ON taggings.feed_id=feeds.id JOIN entries ON feeds.id=entries.feed_id")

      result.each do |user|
        print "{\e[31mtags.id\e[0m: #{user.tags_id}, \e[31mfeed_title\e[0m: #{user.feed_title}, \e[31mfeed_id\e[0m: #{user.feed_id}, \e[31mentries_id\e[0m: #{user.entries_id}}\n"
      end
      puts "#{result.length}"

      #Next querys... all inserts !! 

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