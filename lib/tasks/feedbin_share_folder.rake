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
    end
  end