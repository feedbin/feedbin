require "test_helper"

class RecentlyReadEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @entry = create_feeds(@user, 1).first.entries.first
  end

  test "creating succeeds with user and entry" do
    record = RecentlyReadEntry.new(user: @user, entry: @entry)
    assert record.save
  end

  test "uniqueness is enforced on user_id scoped to entry_id" do
    RecentlyReadEntry.create!(user: @user, entry: @entry)

    duplicate = RecentlyReadEntry.new(user: @user, entry: @entry)
    refute duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "the same entry can be recorded for a different user" do
    RecentlyReadEntry.create!(user: @user, entry: @entry)

    other = RecentlyReadEntry.new(user: users(:ben), entry: @entry)
    assert other.valid?
  end
end
