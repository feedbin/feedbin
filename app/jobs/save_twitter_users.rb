class SaveTwitterUsers
  include Sidekiq::Worker

  def perform(entry_id)
    entry = Entry.find(entry_id)
    array = []
    array.push(entry.tweet.main_tweet)
    array.push(entry.tweet.main_tweet.quoted_status) if entry.tweet.main_tweet.quoted_status?

    array.each do |tweet|
      screen_name = tweet.user.screen_name
      data = tweet.user.to_h
      twitter_user = TwitterUser.where_lower(screen_name: screen_name).take || TwitterUser.create(screen_name: screen_name, data: data)
      twitter_user.update(data: data)

      embed = Embed.twitter_user.create_with(data: data).find_or_create_by(provider_id: screen_name)
      embed.update(data: data)
    end
  rescue ActiveRecord::RecordNotFound
  end
end
