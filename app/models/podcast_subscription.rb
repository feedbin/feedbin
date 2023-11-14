class PodcastSubscription < ApplicationRecord
  include TrackableAttributes
  track :status, :playlist_id,
    :chapter_filter, :chapter_filter_type,
    :download_filter, :download_filter_type

  belongs_to :user
  belongs_to :feed, counter_cache: :subscriptions_count
  belongs_to :playlist
  enum status: {hidden: 0, subscribed: 1, bookmarked: 2}
  enum chapter_filter_type: {include: 0, exclude: 1}, _prefix: :chapter_filter
  enum download_filter_type: {include: 0, exclude: 1}, _prefix: :download_filter

  before_save :update_queued_entries, if: :will_save_change_to_playlist_id?
  before_destroy :removed_queued_entries

  private

  def removed_queued_entries
    user.queued_entries.where(feed_id: feed_id).delete_all
  end

  def update_queued_entries
    user.queued_entries.where(feed_id: feed_id).update_all(playlist_id: playlist_id)
  end

end
