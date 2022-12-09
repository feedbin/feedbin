class SaveTwitterUsers
  include Sidekiq::Worker

  def perform(entry_id)
    entry = Entry.find(entry_id)
    [].tap do |array|
      array.push(entry.tweet.main_tweet)
      array.push(entry.tweet.main_tweet.quoted_status) if entry.tweet.main_tweet.quoted_status?
    end.each do |tweet|
      twitter_user = TwitterUser.where_lower(screen_name: tweet.user.screen_name).take || TwitterUser.create(screen_name: tweet.user.screen_name, data: tweet.user.to_h)
      twitter_user.update(data: tweet.user.to_h)
    end
  rescue ActiveRecord::RecordNotFound
  end
end
