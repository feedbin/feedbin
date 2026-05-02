require "test_helper"

class TagTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
  end

  test "rename moves taggings from the old tag to the new tag" do
    old_tag = Tag.create!(name: "OldTag")
    @user.taggings.create!(tag: old_tag, feed: @feed)

    Tag.rename(@user, old_tag, "NewTag")

    new_tag = Tag.find_by(name: "NewTag")
    refute_nil new_tag
    assert_equal 0, @user.taggings.where(tag: old_tag).count
    assert_equal 1, @user.taggings.where(tag: new_tag).count
  end

  test "rename strips commas and surrounding whitespace from the new name" do
    old_tag = Tag.create!(name: "Old")
    @user.taggings.create!(tag: old_tag, feed: @feed)

    new_tag = Tag.rename(@user, old_tag, "  No, Commas  ")
    assert_equal "No Commas", new_tag.name
  end

  test "rename reuses an existing tag with the new name" do
    old_tag = Tag.create!(name: "Old")
    existing = Tag.create!(name: "Existing")
    @user.taggings.create!(tag: old_tag, feed: @feed)

    result = Tag.rename(@user, old_tag, "Existing")
    assert_equal existing.id, result.id
  end

  test "destroy removes the user's taggings for the given tag" do
    tag = Tag.create!(name: "ToDelete")
    @user.taggings.create!(tag: tag, feed: @feed)

    Tag.destroy(@user, tag)

    assert_equal 0, @user.taggings.where(tag: tag).count
  end

  test "sourceable returns a Sourceable describing the tag" do
    tag = Tag.create!(name: "Tech")
    sourceable = tag.sourceable

    assert_instance_of Sourceable, sourceable
    assert_equal "tag", sourceable.type
    assert_equal "Tech", sourceable.title
    assert_equal "Tags", sourceable.section
    assert_equal true, sourceable.jumpable
  end
end
