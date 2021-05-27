require "test_helper"

class FeedRefresherReceiverTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @subscription = @user.subscriptions.first
    @feed = @subscription.feed
  end

  test "should create entry" do
    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [build_entry]
    }
    assert_difference "Entry.count", +1 do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  test "should schedule WarmCache job" do
    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [build_entry]
    }

    Sidekiq::Worker.clear_all
  end

  test "should not create entry with existing public_id" do
    public_id = SecureRandom.hex
    entry = @feed.entries.create!(url: "url", public_id: public_id)

    assert FeedbinUtils.public_id_exists?(public_id)
    $redis[:refresher].with do |redis|
      redis.del(public_id)
    end
    assert_not FeedbinUtils.public_id_exists?(public_id)

    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [build_entry(public_id)]
    }
    assert_no_difference "Entry.count" do
      FeedRefresherReceiver.new.perform(params)
    end

    assert FeedbinUtils.public_id_exists?(public_id)
  end

  test "should not create entry with existing public_id_alt" do
    public_id = SecureRandom.hex
    entry = @feed.entries.create!(url: "url", public_id: "#{public_id}_alt")

    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [build_entry(public_id)]
    }
    assert_no_difference "Entry.count" do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  test "should not create entry public_id_alt" do
    entry = build_entry
    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [entry]
    }
    FeedbinUtils.update_public_id_cache(entry["data"]["public_id_alt"], "")
    assert_no_difference "Entry.count" do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  test "should update entry" do
    public_id = SecureRandom.hex
    entry = @feed.entries.create!(url: "url", public_id: public_id)
    update = build_entry(entry.public_id, true)
    params = {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [update]
    }
    FeedRefresherReceiver.new.perform(params)
    update.each do |attribute, value|
      assert_equal value, entry.reload.send(attribute), "entry.#{attribute} didn't match"
    end
  end

  test "should create UpdatedEntry" do
    params = update_params
    @user.unread_entries.delete_all
    assert_difference -> { @user.updated_entries.count }, +1 do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  test "should not create UpdatedEntry muted" do
    params = update_params
    @user.unread_entries.delete_all
    @subscription.update(muted: true)
    assert_no_difference -> { @user.updated_entries.count } do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  test "should not create UpdatedEntry show_updates" do
    params = update_params
    @user.unread_entries.delete_all
    @subscription.update(show_updates: false)
    assert_no_difference -> { @user.updated_entries.count } do
      FeedRefresherReceiver.new.perform(params)
    end
  end

  private

  def build_entry(public_id = SecureRandom.hex, update = false)
    data = {
      "public_id_alt" => public_id + "_alt"
    }
    {
      "author" => SecureRandom.hex,
      "content" => SecureRandom.hex,
      "entry_id" => SecureRandom.hex,
      "public_id" => public_id,
      "title" => SecureRandom.hex,
      "url" => Faker::Internet.url,
      "update" => update,
      "data" => data
    }
  end

  def update_params
    public_id = SecureRandom.hex
    entry = @feed.entries.create!(url: "url", public_id: public_id)
    update = build_entry(entry.public_id, true)
    update["content"] = update["content"] * 10
    {
      "feed" => {
        "id" => @feed.id
      },
      "entries" => [update]
    }
  end
end
