class TagEditor
  attr_reader :user, :feed, :taggings

  def initialize(taggings:, user:, feed:)
    @taggings = taggings[feed&.id] || []
    @user = user
    @feed = feed
  end

  def tags
    @tags ||= user.feed_tags
  end

  def checked?(tag)
    taggings.include? tag.id
  end

  def self.taggings(user)
    user.taggings.group(:feed_id).pluck(:feed_id, "array_agg(tag_id)").to_h
  end
end
