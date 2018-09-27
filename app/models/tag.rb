class Tag < ApplicationRecord
  attr_accessor :count, :user_feeds

  has_many :taggings
  has_many :feeds, through: :taggings

  def self.rename(user, old_tag, new_name)
    new_name = new_name.strip.gsub(",", "")

    user_taggings = user.taggings.where(tag: old_tag)

    ActiveRecord::Base.transaction do
      new_tag = Tag.where(name: new_name).first_or_create
      user_taggings.update_all(tag_id: new_tag.id)
    end

    ActionTags.perform_async(user.id, new_tag.id, old_tag.id)

    new_tag
  end

end
