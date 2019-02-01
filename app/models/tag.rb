class Tag < ApplicationRecord
  attr_accessor :count, :user_feeds

  has_many :taggings
  has_many :feeds, through: :taggings

  def self.rename(user, old_tag, new_name)
    new_name = new_name.strip.delete(",")

    new_tag = Tag.where(name: new_name).first_or_create
    user.taggings.where(tag: old_tag).update_all(tag_id: new_tag.id)

    ActionTags.perform_async(user.id, new_tag.id, old_tag.id)

    new_tag
  end

  def self.destroy(user, tag)
    Tagging.where(tag: tag, user: user).destroy_all
    ActionTags.perform_async(user.id, nil, tag.id)
  end
end
