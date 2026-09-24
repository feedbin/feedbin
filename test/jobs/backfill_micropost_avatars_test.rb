require "test_helper"

class BackfillMicropostAvatarsTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def micropost_feed(name, marked: true)
    Feed.create!(feed_url: "http://#{name}.example.com/feed.json", custom_icon_format: (marked ? "round" : nil)).tap do |feed|
      feed.entries.create!(
        title: nil, url: "http://#{name}.example.com/1", content: "<p>hi</p>", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: Time.now,
        data: {"author" => {"name" => "Someone", "url" => "http://#{name}.example.com", "avatar" => "http://#{name}.example.com/me.png", "_microblog" => {"username" => "someone"}}}
      )
      Sidekiq::Worker.clear_all
    end
  end

  def batches_for(*records)
    records.map { |record| ((record.id - 1) / SidekiqHelper::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*records)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batches_for(*records).each { |batch| BackfillMicropostAvatars.new.perform(batch) }
    end
  end

  test "pending is every marked micropost feed with an entry lacking a row" do
    todo = micropost_feed("todo")
    done = micropost_feed("done")
    create_image_row(provider: :entry_icon, provider_id: done.entries.first.id.to_s, feed_id: done.id, kind: :avatar, variant: "200x200")
    unmarked = micropost_feed("unmarked", marked: false)
    titled = Feed.create!(feed_url: "http://titled.example.com/feed", custom_icon_format: "round")
    create_entry(titled)

    pending = BackfillMicropostAvatars.pending.where(id: [todo, done, unmarked, titled].map(&:id))

    assert_equal [todo.id], pending.pluck(:id), "the marker is the prefilter, and a titled entry never gets an avatar row, so it keeps no feed pending"
  end

  # One feed's error must not strand the feeds after it in the batch, or
  # send the whole batch back through Sidekiq's retries.
  test "a feed that raises is logged and the batch goes on" do
    bad = micropost_feed("bad")
    good = micropost_feed("good")
    passes = []
    schedule = ->(feed, **) {
      passes << feed.id
      raise "boom" if feed.id == bad.id
      [0, 1]
    }

    ImageCrawler::MicropostAvatar.stub(:schedule, schedule) do
      assert_nothing_raised { perform_batches_for(bad, good) }
    end

    assert_equal [bad.id, good.id], passes
  end

  test "a batch schedules each pending feed off the critical queues" do
    feed = micropost_feed("live")

    perform_batches_for(feed)

    jobs = ImageCrawler::Pipeline::Find.jobs.map { it["args"].first }.select { it["preset_name"] == "micropost_avatar" }
    assert_equal [feed.id], jobs.map { it["feed_id"] }
    assert_equal [false], jobs.map { it["critical"] }
  end

  test "schedule pushes one job per batch of feed ids, spaced over the spread" do
    micropost_feed("first")
    micropost_feed("last")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillMicropostAvatars.new.perform(nil, true)
    end

    jobs = BackfillMicropostAvatars.jobs
    expected = BackfillMicropostAvatars.new.job_args(Feed.maximum(:id), Feed.minimum(:id))
    assert_equal expected.size, jobs.size
    step = BackfillMicropostAvatars::SPREAD.to_f / jobs.size
    [0, jobs.size / 2, jobs.size - 1].each do |index|
      assert_in_delta Time.now.to_f + (index * step), jobs[index]["at"], 5
    end
  end

  test "scopes a batch as an anti-join over entries with a qualified id range" do
    sql = BackfillMicropostAvatars.batch_scope(1).order(:id).to_sql

    assert_includes sql, %("feeds"."settings" ->> 'custom_icon_format' = 'round')
    assert_includes sql, %(EXISTS (SELECT 1 FROM "entries" LEFT OUTER JOIN "images" ON "images"."provider" = 0 AND "images"."provider_id" = CAST("entries"."id" AS text) WHERE "entries"."feed_id" = "feeds"."id" AND ("entries"."title" IS NULL OR "entries"."title" = '') AND "images"."id" IS NULL))
    assert_includes sql, %("feeds"."id" BETWEEN 1 AND #{SidekiqHelper::BATCH_SIZE})
    refute_includes sql, "NOT IN"
    assert_nothing_raised { BackfillMicropostAvatars.batch_scope(1).order(:id).load }
  end

  test "refuses to enqueue without unified storage configured" do
    feed = micropost_feed("valid")

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillMicropostAvatars.new.perform(nil, true) }
      assert_raises(RuntimeError) { BackfillMicropostAvatars.new.perform(batches_for(feed).first) }
    end
  end
end
