class Tag < ApplicationRecord
  attr_accessor :count, :user_feeds

  has_many :taggings
  has_many :feeds, through: :taggings

  # tags.name is varchar(255), and first_or_create below would otherwise write
  # a nameless row — one that renders as a blank line in the sidebar, with
  # nothing on screen to rename it back.
  validates :name, presence: true, length: {maximum: 255}

  # Returns nil when the name cannot be used, so the caller can tell the
  # rename did not happen rather than moving taggings onto a junk tag.
  def self.rename(user, old_tag, new_name)
    new_name = new_name.to_s.strip.delete(",")

    new_tag = Tag.where(name: new_name).first_or_create
    return nil unless new_tag.persisted?

    user.taggings.where(tag: old_tag).update_all(tag_id: new_tag.id)

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
