class Tag < ApplicationRecord
  attr_accessor :count, :user_feeds

  has_many :taggings
  has_many :feeds, through: :taggings

  def self.rename(user, old_tag, new_name)
    new_name = new_name.strip.delete(",")

    new_tag = Tag.where(name: new_name).first_or_create

    unless new_tag.id == old_tag.id
      # taggings has no unique index, so a feed carrying both tags would end up
      # with two rows for the destination tag and count twice in the sidebar.
      duplicate_feed_ids = user.taggings.where(tag: old_tag).select(:feed_id)
      user.taggings.where(tag: new_tag, feed_id: duplicate_feed_ids).delete_all
      user.taggings.where(tag: old_tag).update_all(tag_id: new_tag.id)
    end

    Search::ActionTags.perform_async(user.id, new_tag.id, old_tag.id)

    new_tag
  end

  def self.destroy(user, tag)
    Tagging.where(tag: tag, user: user).destroy_all
    Search::ActionTags.perform_async(user.id, nil, tag.id)
  end

  def sourceable
    Sourceable.new(
      type: self.class.name,
      id: id,
      title: name,
      section: "Tags",
      jumpable: true
    )
  end
end
