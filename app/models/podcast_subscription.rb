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

  def download_filter_terms
    download_filter
      .to_s
      .downcase
      .split(",")
      .map(&:strip)
      .reject(&:blank?)
  end

  def filtered?(subject)
    subject = subject.to_s.downcase
    return false if download_filter_terms.empty?
    found_match = download_filter_terms.any? { subject.include?(_1) }
    if download_filter_include?
      found_match ? false : true
    elsif download_filter_exclude?
      found_match ? true : false
    else
      false
    end
  end

  private

  def removed_queued_entries
    user.queued_entries.where(feed_id: feed_id).delete_all
  end

  def update_queued_entries
    user.queued_entries.where(feed_id: feed_id).update_all(playlist_id: playlist_id)
  end

end
