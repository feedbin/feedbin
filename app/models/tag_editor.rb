class TagEditor
  attr_reader :user, :feed

  def initialize(user, feed)
    @user = user
    @feed = feed
  end

  def taggings
    @taggings ||= user.taggings.where(feed: feed).pluck(:tag_id)
  end

  def tags
    @tags ||= user.feed_tags
  end

  def checked?(tag)
    taggings.include? tag.id
  end
end
