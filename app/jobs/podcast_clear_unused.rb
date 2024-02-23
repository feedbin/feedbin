class PodcastClearUnused
  include Sidekiq::Worker

  def perform
    PodcastSubscription.hidden.find_each do |subscription|
      next if subscription.created_at.after?(1.day.ago)
      unless subscription.queued_entries.exists?
        subscription.destroy
      end
    end
  end
end


