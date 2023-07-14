namespace :feeds do
    desc "Share Folder to another user"
    task :share_folder, [:user_id, :id_tags] => :environment do |_, args|
      id_tags = args[:id_tags]
      user_id = args[:user_id]
      puts "--------- #{id_tags}"
      puts "--------- #{user_id}"
      # PRIMERA QUERY
      get_all_tags = User.select('users.id', 'users.email', 'tags.id AS tag_id', 'tags.name AS tags_name')
              .where(id: 3)
              .joins(:tags)

      get_all_tags.each do |user|
        print "{\e[31mID: #{user.id}\e[0m, \e[31mEmail\e[0m: #{user.email}, \e[31mtag_id\e[0m: #{user.tag_id}, \e[31mtags.name\e[0m: #{user.tags_name}}\n"
      end
      puts "#{get_all_tags.length}"

      # SEGUNDA QUERY
      #feeds_ids = []
      #result = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id as feed_id").joins("JOIN taggings ON tags.id=#{id_tags} AND tags.id=taggings.tag_id JOIN feeds
      #  ON taggings.feed_id=feeds.id")
      #result.each do |user|
      #  print "{\e[31mtags.id\e[0m: #{user.tags_id}, \e[31mfeed_title\e[0m: #{user.feed_title}, \e[31mfeed_id\e[0m: #{user.feed_id}}\n"
      #end
      # Save all feed_id
      feed_id = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id as feed_id").joins("JOIN taggings ON tags.id=#{id_tags} AND tags.id=taggings.tag_id JOIN feeds
        ON taggings.feed_id=feeds.id").pluck(:feed_id)
      puts "feed_id = #{feed_id}"

      # Subscribe 
        
      # TERCERA QUERY
      #result = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id AS feed_id", "entries.id AS entries_id").joins("JOIN taggings ON tags.id=1 AND tags.id=taggings.tag_id JOIN feeds ON taggings.feed_id=feeds.id JOIN entries ON feeds.id=entries.feed_id")
      entries_id = Tag.select("tags.id AS tags_id", "feeds.title AS feed_title", "feeds.id AS feed_id", "entries.id AS entries_id").joins("JOIN taggings ON tags.id=#{id_tags} AND tags.id=taggings.tag_id JOIN feeds ON taggings.feed_id=feeds.id JOIN entries ON feeds.id=entries.feed_id").pluck("entries.id")
      puts "entries_id = #{entries_id}"
      #result.each do |user|
      #  print "{\e[31mtags.id\e[0m: #{user.tags_id}, \e[31mfeed_title\e[0m: #{user.feed_title}, \e[31mfeed_id\e[0m: #{user.feed_id}, \e[31mentries_id\e[0m: #{user.entries_id}}\n"
      #end
      #puts "#{result.length}"



      #Next querys... all inserts !! 

    end
  end