class UpdatedEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry
  belongs_to :feed

  def self.new_from_owners(user_id, entry)
    new(user_id: user_id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published, updated: entry.updated)
  end

  def self.create_from_owners(user_id, entry)
    new_from_owners(user_id, entry).save
  end
end
