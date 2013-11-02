class StarredEntry < ActiveRecord::Base
  belongs_to :user
  belongs_to :feed
  belongs_to :entry, counter_cache: true

  validates_uniqueness_of :user_id, scope: :entry_id

  def self.create_from_owners(user, entry)
    create(user_id: user.id, feed_id: entry.feed_id, entry_id: entry.id, published: entry.published)
  end

  def self.sort_preference(sort)
    if sort == 'ASC'
      order("published ASC")
    else
      order("published DESC")
    end
  end

end
