class Playlist < ApplicationRecord
  include TrackableAttributes
  track :title, :sort_order

  belongs_to :user

  enum :sort_order, {custom: 0, newest_first: 1, oldest_first: 2}

  has_many :podcast_subscriptions, dependent: :nullify
  has_many :queued_entries, dependent: :nullify
end
