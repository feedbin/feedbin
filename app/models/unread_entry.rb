class UnreadEntry < ApplicationRecord
  belongs_to :user
  belongs_to :feed
  belongs_to :entry

  self.table_name = "unreads"

  validates_uniqueness_of :user_id, scope: :entry_id

  def self.new_from_owners(user, entry)
    new(user_id: user.id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published, entry_created_at: entry.created_at)
  end

  def self.create_from_owners(user, entry)
    # Look up / insert by the columns the unique index covers so that a
    # concurrent request which wins the race is recovered via find_by rather
    # than raising RecordNotUnique. The remaining attributes are only applied
    # on the create path.
    create_or_find_by(user_id: user.id, entry_id: entry.id) do |unread_entry|
      unread_entry.feed_id = entry.feed_id
      unread_entry.published = entry.published
      unread_entry.entry_created_at = entry.created_at
    end
  end

  def self.sort_preference(sort)
    if sort == "ASC"
      order("published ASC")
    else
      order("published DESC")
    end
  end
end
