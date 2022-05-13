class QueuedEntry < ApplicationRecord
  include TrackableAttributes
  track :progress, :order

  belongs_to :user
  belongs_to :entry, counter_cache: true
  belongs_to :feed
end
