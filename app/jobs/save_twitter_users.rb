class SaveTwitterUsers
  include Sidekiq::Worker

  def perform(entry_id)
    entry = Entry.find(entry_id)
    [].tap do |array|
      array.push(entry.tweet.main_tweet)
      array.push(entry.tweet.main_tweet.quoted_status) if entry.tweet.main_tweet.quoted_status?
    end.each do |tweet|
      store(tweet.user)
    end
  rescue ActiveRecord::RecordNotFound
  end

  private

  # The model has no uniqueness validation, so the row a concurrent worker
  # writes between our SELECT and our INSERT comes back from the driver as
  # RecordNotUnique. Every entry quoting or replying to an author races for
  # that author's row, so take the winner's and refresh it.
  def store(user)
    data = user.to_h
    if stored = TwitterUser.where_lower(screen_name: user.screen_name).take
      stored.update(data: data)
    else
      TwitterUser.create(screen_name: user.screen_name, data: data)
    end
  rescue ActiveRecord::RecordNotUnique
    TwitterUser.where_lower(screen_name: user.screen_name).take&.update(data: data)
  end
end
