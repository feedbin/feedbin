require "test_helper"

class StarredEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @entry = create_feeds(@user, 1).first.entries.first
  end

  test "new_from_owners builds an unsaved StarredEntry from a user and entry" do
    record = StarredEntry.new_from_owners(@user, @entry, "iOS")
    assert_equal @user.id, record.user_id
    assert_equal @entry.feed_id, record.feed_id
    assert_equal @entry.id, record.entry_id
    assert_equal @entry.published, record.published
    assert_equal "iOS", record.source
    assert record.new_record?
  end

  test "create_from_owners persists the record" do
    assert_difference "StarredEntry.count", +1 do
      StarredEntry.create_from_owners(@user, @entry)
    end
  end

  test "uniqueness is enforced on user_id scoped to entry_id" do
    StarredEntry.create_from_owners(@user, @entry)
    duplicate = StarredEntry.new_from_owners(@user, @entry)
    refute duplicate.valid?
  end

  test "expire_caches deletes the user's starred feed cache" do
    cache_key = "#{@user.id}:starred_feed:v2"
    Rails.cache.write(cache_key, "cached value")

    StarredEntry.create_from_owners(@user, @entry)

    assert_nil Rails.cache.read(cache_key)
  end
end
