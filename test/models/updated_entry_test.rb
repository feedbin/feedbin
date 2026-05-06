require "test_helper"

class UpdatedEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @entry = create_feeds(@user, 1).first.entries.first
  end

  test "new_from_owners builds an UpdatedEntry from a user_id and entry" do
    record = UpdatedEntry.new_from_owners(@user.id, @entry)
    assert_equal @user.id, record.user_id
    assert_equal @entry.feed_id, record.feed_id
    assert_equal @entry.id, record.entry_id
    assert_equal @entry.published, record.published
    assert_nil @entry.updated
    assert_nil record.updated
    assert record.new_record?
  end

  test "create_from_owners persists the record" do
    assert_difference "UpdatedEntry.count", +1 do
      UpdatedEntry.create_from_owners(@user.id, @entry)
    end
  end
end
