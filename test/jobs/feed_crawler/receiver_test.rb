require "test_helper"

module FeedCrawler
  class ReceiverTest < ActiveSupport::TestCase
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
        Receiver.new.perform(params)
      end
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
        Receiver.new.perform(params)
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
        Receiver.new.perform(params)
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
        Receiver.new.perform(params)
      end
    end

    test "should update entry" do
      public_id = SecureRandom.hex
      entry = @feed.entries.create!(url: "url", public_id: public_id, content: "content")
      update = build_entry(entry.public_id, true)
      params = {
        "feed" => {
          "id" => @feed.id
        },
        "entries" => [update]
      }
      Receiver.new.perform(params)
      update.except("update").each do |attribute, value|
        assert_equal value, entry.reload.send(attribute), "entry.#{attribute} didn't match"
      end
    end

    test "should not create original nil content" do
      entry = @feed.entries.create!(url: "url", public_id: SecureRandom.hex, content: nil)
      update = build_entry(entry.public_id, true)
      params = {
        "feed" => {
          "id" => @feed.id
        },
        "entries" => [update]
      }
      Receiver.new.perform(params)
      assert_nil entry.reload.original
    end

    test "should create UpdatedEntry" do
      params = update_params
      @user.unread_entries.delete_all
      assert_difference -> { @user.updated_entries.count }, +1 do
        Receiver.new.perform(params)
      end
    end

    test "should not create UpdatedEntry muted" do
      params = update_params
      @user.unread_entries.delete_all
      @subscription.update(muted: true)
      assert_no_difference -> { @user.updated_entries.count } do
        Receiver.new.perform(params)
      end
    end

    test "should not create UpdatedEntry show_updates" do
      params = update_params
      @user.unread_entries.delete_all
      @subscription.update(show_updates: false)
      assert_no_difference -> { @user.updated_entries.count } do
        Receiver.new.perform(params)
      end
    end

    # The Sidekiq path JSON round-trips the payload, so the keys arrive as
    # strings. The import path calls perform in-process and the keys stay
    # symbols, which made every lookup here miss.
    test "should update entry given symbol keys" do
      public_id = SecureRandom.hex
      entry = @feed.entries.create!(url: "url", public_id: public_id, content: "content")
      update = build_entry(entry.public_id, true).deep_symbolize_keys
      params = {
        feed: {id: @feed.id},
        entries: [update]
      }

      assert_no_difference "Entry.count" do
        Receiver.new.perform(params)
      end

      assert_equal update[:title], entry.reload.title
    end

    test "should not create a duplicate entry given symbol keys" do
      public_id = SecureRandom.hex
      entry = build_entry(public_id).deep_symbolize_keys
      params = {
        feed: {id: @feed.id},
        entries: [entry]
      }
      FeedbinUtils.update_public_id_cache(entry[:data][:public_id_alt], "")

      assert_no_difference "Entry.count" do
        Receiver.new.perform(params)
      end
    end

    # Once per crawl with new posts, never per entry: the pass dedupes their
    # avatar urls. The new entries themselves decide, not the parser's feed
    # marker, and the pass covers only them.
    test "starts the avatar pass for the micropost entries a crawl creates" do
      Sidekiq::Worker.clear_all
      params = {"feed" => {"id" => @feed.id}, "entries" => [build_micropost, build_micropost, build_entry]}

      Receiver.new.perform(params)

      microposts = Entry.where(public_id: params["entries"].first(2).map { it["public_id"] }).pluck(:id)
      job = ImageCrawler::MicropostAvatar.jobs.sole
      assert_equal @feed.id, job["args"][0]
      assert_equal microposts.sort, job["args"][2].sort
    end

    test "does not start the avatar pass for titled entries or a crawl with no new entries" do
      Sidekiq::Worker.clear_all
      Receiver.new.perform({"feed" => {"id" => @feed.id}, "entries" => [build_entry]})
      assert_empty ImageCrawler::MicropostAvatar.jobs

      micropost = build_micropost
      @feed.entries.create!(url: "url", public_id: micropost["public_id"])
      $redis[:refresher].with { |redis| redis.del(micropost["public_id"]) }
      Receiver.new.perform({"feed" => {"id" => @feed.id}, "entries" => [micropost]})
      assert_empty ImageCrawler::MicropostAvatar.jobs
    end

    # The stored feed_icon row outranks options, so a new icon url (a
    # Mastodon account's new avatar) is only fetched if the crawl that
    # brings it asks. An unchanged url is not asked for again.
    test "schedules the feed icon only when a crawl changes the feed's icon url" do
      @feed.update!(options: {"image" => {"url" => "http://example.com/old.png"}})
      Sidekiq::Worker.clear_all

      Receiver.new.perform({"feed" => {"id" => @feed.id, "options" => {"image" => {"url" => "http://example.com/old.png"}}}})
      assert_empty ImageCrawler::FeedIcon.jobs

      Receiver.new.perform({"feed" => {"id" => @feed.id, "options" => {"image" => {"url" => "http://example.com/new.png"}}}})
      assert_equal [@feed.id], ImageCrawler::FeedIcon.jobs.map { it["args"].first }
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

    def build_micropost
      entry = build_entry
      entry["data"]["author"] = {"name" => "Someone", "avatar" => "https://micro.example/a.png", "_microblog" => {"username" => "someone"}}
      entry.merge("title" => nil)
    end

    def update_params
      public_id = SecureRandom.hex
      entry = @feed.entries.create!(url: "url", public_id: public_id, content: "content")
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
end