namespace :feeds do
    desc "Share Folder to another user"
    task :share_folder, [:user_id, :id_tags] => :environment do |_, args|
      user_id = args[:user_id]
      id_tag = args[:id_tags]
      puts "{\e[31mid_tag: #{id_tag}\e[0m}"
      puts "{\e[31muser_id: #{user_id}\e[0m}"

      # Selects all feeds on specific tag
      feeds_ids = Tag.find(id_tag).feeds.pluck(:id)
      puts "{\e[31mfeeds_ids\e[0m #{feeds_ids}}"

      # View all entries for specific TAG
      entries = Entry.where(feed_id: Tag.find(id_tag).feeds.pluck(:id)).pluck(:id)
      puts "\e[31mEntries id\e[0m {#{entries}}"

      # Insert operations
      feeds_ids.each do |feed_id|
        Subscription.new(user_id: user_id, feed_id: feed_id).save # Subcribe to all new feeds
        Tagging.new(feed_id: feed_id, user_id: user_id, tag_id: id_tag).save # Insert new feed to the folder
      end
    end
  end