class StarredEntry < ApplicationRecord
  belongs_to :user
  belongs_to :feed
  belongs_to :entry, counter_cache: true
  before_create :expire_caches
  before_destroy :expire_caches

  validates_uniqueness_of :user_id, scope: :entry_id

  def self.create_from_owners(user, entry, source = nil)
    create(user_id: user.id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published, source: source)
  end

  def expire_caches
    Rails.cache.delete("#{user_id}:starred_feed")
    true
  end
end
