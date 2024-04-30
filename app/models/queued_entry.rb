class QueuedEntry < ApplicationRecord
  include TrackableAttributes
  track :progress, :order, :playlist_id

  belongs_to :user
  belongs_to :entry, counter_cache: true
  belongs_to :feed
  belongs_to :playlist
end
