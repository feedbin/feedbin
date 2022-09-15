class TouchFeeds
  include Sidekiq::Worker

  def perform(host)
    Feed.where(host: host).select(:id).find_in_batches do |feeds|
      Feed.where(id: feeds.map(&:id)).update_all(updated_at: Time.now)
    end
  end
end
