class PodcastClearUnused
  include Sidekiq::Worker

  def perform
    PodcastSubscription.hidden.where("created_at < ?", 1.month.ago).find_each do |subscription|
      subscription.destroy unless subscription.queued_entries.exists?
    end
  end
end


