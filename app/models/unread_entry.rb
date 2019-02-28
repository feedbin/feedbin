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
    new_from_owners(user, entry).save
  end

  def self.sort_preference(sort)
    if sort == "ASC"
      order("published ASC")
    else
      order("published DESC")
    end
  end
end
