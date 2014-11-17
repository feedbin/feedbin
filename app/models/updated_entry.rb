class UpdatedEntry < ActiveRecord::Base
  belongs_to :user
  belongs_to :entry
  belongs_to :feed

  def self.new_from_owners(user, entry)
    new(user_id: user.id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published, updated: entry.updated)
  end

  def self.create_from_owners(user, entry)
    new_from_owners(user, entry).save
  end

end
