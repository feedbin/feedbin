class TouchFeeds
  include Sidekiq::Worker

  def perform(host)
    Feed.where(host: host).update_all(updated_at: Time.now)
  end
end
