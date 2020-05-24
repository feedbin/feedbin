require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should filter by subscription" do
    @user.inspect
    ids = @user.entries.limit(1).pluck(:id)
    assert_equal(ids, @user.can_read_filter(ids))
    @user.subscriptions.delete_all
    assert_equal([], @user.can_read_filter(ids))
  end

  test "should filter by starred entries" do
    @user.inspect
    entry = @user.entries.limit(1).first
    @user.subscriptions.delete_all

    ids = [entry.id]

    assert_equal([], @user.can_read_filter(ids))

    StarredEntry.create_from_owners(@user, entry)

    assert_equal(ids, @user.can_read_filter(ids))
  end

  test "should filter by recently read entries" do
    @user.inspect
    entry = @user.entries.limit(1).first
    @user.subscriptions.delete_all

    ids = [entry.id]

    assert_equal([], @user.can_read_filter(ids))

    @user.recently_read_entries.create!(entry: entry)

    assert_equal(ids, @user.can_read_filter(ids))
  end

  test "should filter by recently played entries" do
    @user.inspect
    entry = @user.entries.limit(1).first
    @user.subscriptions.delete_all

    ids = [entry.id]

    assert_equal([], @user.can_read_filter(ids))

    @user.recently_played_entries.create!(entry: entry)

    assert_equal(ids, @user.can_read_filter(ids))
  end
end
