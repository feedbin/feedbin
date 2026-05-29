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

  test "reactivate_billing! un-suspends, activates subscriptions, and reopens an unpaid account" do
    @user.update(suspended: true)
    @user.subscriptions.update_all(active: false)
    reopened_with = nil

    Billing::Customer.stub(:retrieve, OpenStruct.new(unpaid?: true)) do
      Billing::Subscription.stub(:reopen_account, ->(id) { reopened_with = id }) do
        @user.reactivate_billing!
      end
    end

    refute @user.reload.suspended
    assert @user.subscriptions.all?(&:active)
    assert_equal @user.customer_id, reopened_with
  end

  test "reactivate_billing! does not reopen the account when the customer is not unpaid" do
    @user.update(suspended: true)
    reopen_called = false

    Billing::Customer.stub(:retrieve, OpenStruct.new(unpaid?: false)) do
      Billing::Subscription.stub(:reopen_account, ->(_id) { reopen_called = true }) do
        @user.reactivate_billing!
      end
    end

    refute @user.reload.suspended
    refute reopen_called
  end
end
