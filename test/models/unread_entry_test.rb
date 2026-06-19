require "test_helper"
require "minitest/stub_any_instance"

class UnreadEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @entry = create_feeds(@user, 1).first.entries.first
    # An unread is created automatically when the feed/entry is set up; start
    # each test from a clean slate so create_from_owners is exercised directly.
    UnreadEntry.where(user: @user, entry: @entry).delete_all
  end

  test "create_from_owners persists the record" do
    assert_difference "UnreadEntry.count", +1 do
      UnreadEntry.create_from_owners(@user, @entry)
    end
  end

  test "create_from_owners returns the existing record when a concurrent insert wins the race" do
    original = UnreadEntry.create_from_owners(@user, @entry)
    assert_predicate original, :persisted?

    # Simulate the check-then-insert race: the uniqueness validation passes
    # (as it would when a concurrent request hasn't committed yet) but the DB
    # unique index rejects the duplicate INSERT. create_or_find_by recovers by
    # returning the row the winning request already committed.
    result = UnreadEntry.stub_any_instance(:valid?, true) do
      assert_nothing_raised do
        UnreadEntry.create_from_owners(@user, @entry)
      end
    end

    assert_predicate result, :persisted?
    assert_equal original.id, result.id
    assert_equal 1, UnreadEntry.where(user: @user, entry: @entry).count
  end
end
