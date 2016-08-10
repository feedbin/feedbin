class UpdateFaviconHash
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.find(user_id)
    hash = get_hash(user)
    user.update_attributes(favicon_hash: hash)
  end

  def get_hash(user)
    feed_ids = user.subscriptions.pluck(:feed_id)
    hosts = Feed.where(id: feed_ids).pluck(:host)
    hosts = hosts.join
    Digest::SHA1.hexdigest(hosts)
  end

end
