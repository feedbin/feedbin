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

  test "tier 4 trial user can choose the $7 and $70 plans" do
    @user.update_columns(price_tier: 4, plan_id: plans(:trial).id)

    stripe_ids = @user.available_plans.map(&:stripe_id)

    assert_equal ["basic-yearly-4", "basic-monthly-4"], stripe_ids
  end

  test "existing subscriptions are keyed by feed id" do
    feed = @user.feeds.first
    subscription = @user.subscriptions.where(feed: feed).take!

    existing = @user.existing_subscriptions([feed])

    assert_equal subscription, existing[feed.id]
    assert existing.include?(feed.id)
  end

  test "existing subscriptions are keyed by the url a subscribed feed redirects to" do
    searched = feeds(:daring_fireball)
    redirected = @user.feeds.where.not(id: searched.id).first
    redirected.update!(redirected_to: searched.feed_url)
    @user.subscriptions.where(feed: searched).destroy_all
    subscription = @user.subscriptions.where(feed: redirected).take!

    existing = @user.existing_subscriptions([searched])

    assert_equal subscription, existing[searched.feed_url]
    assert existing.include?(searched.feed_url)
    refute existing.include?(searched.id)
  end

  test "existing subscriptions is empty without feeds to search" do
    assert_equal({}, @user.existing_subscriptions([]))
  end

  test "find_by_email matches regardless of case or surrounding space" do
    assert_equal @user, User.find_by_email("  #{@user.email.upcase}  ")
  end

  test "find_by_email is nil for an address no one has" do
    assert_nil User.find_by_email("nobody@example.com")
  end

  test "find_by_email is nil for bytes that are not valid UTF-8" do
    assert_nil User.find_by_email("\xC3\x28#{@user.email}".b)
  end

  test "find_by_email is nil for anything that is not a string" do
    assert_nil User.find_by_email(nil)
    assert_nil User.find_by_email(email: @user.email)
  end
end
