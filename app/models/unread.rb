class Unread < ApplicationRecord
  belongs_to :user
  belongs_to :feed
  belongs_to :entry

  self.table_name = "unread_entries"

  def self.new_from_owners(user, entry)
    new(user_id: user.id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published, entry_created_at: entry.created_at)
  end

  def self.create_from_owners(user, entry)
    new_from_owners(user, entry).save
  end
end
