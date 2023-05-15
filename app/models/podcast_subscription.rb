class PodcastSubscription < ApplicationRecord
  include TrackableAttributes
  track :status, :playlist_id

  belongs_to :user
  belongs_to :feed, counter_cache: :subscriptions_count
  belongs_to :playlist
  enum status: {hidden: 0, subscribed: 1, bookmarked: 2}

  before_destroy :removed_queued_entries

  private

  def removed_queued_entries
    QueuedEntry.where(user_id: user_id, feed_id: feed_id).delete_all
  end

end
