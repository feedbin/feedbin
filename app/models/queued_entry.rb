class QueuedEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry, counter_cache: true
  belongs_to :feed
end
