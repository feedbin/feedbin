require "test_helper"

class BackfillFeedIconsTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def feed(name, options)
    Feed.create!(feed_url: "http://#{name}.example.com/feed", options: options).tap do
      # Feed create enqueues the live crawlers; this test counts only what
      # the backfill enqueues.
      Sidekiq::Worker.clear_all
    end
  end

  # The batch that holds an id, in SidekiqHelper's numbering. Sequences do
  # not reset between tests, so the rows can straddle a batch boundary.
  def batches_for(*records)
    records.map { |record| ((record.id - 1) / SidekiqHelper::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*records)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batches_for(*records).each { |batch| BackfillFeedIcons.new.perform(batch) }
    end
  end

  def scheduled_feed_ids
    ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
  end

  test "pending is every feed with a legacy source and no feed_icon row, podcasts excluded" do
    icon = feed("icon", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    avatar = feed("avatar", {"json_feed" => {"author" => {"avatar" => "http://example.com/me.png"}}})
    image = feed("image", {"image" => {"url" => "http://example.com/logo.png"}})
    create_entry(image).update!(title: nil)
    # An RSS image on a feed with titled entries is an article feed's
    # banner: the job would decline it, so the set leaves it out, and so
    # does a feed with no entries at all.
    banner = feed("banner", {"image" => {"url" => "http://example.com/banner.png"}})
    create_entry(banner).update!(title: "An article")
    empty = feed("empty", {"image" => {"url" => "http://example.com/logo.png"}})
    podcast = feed("podcast", {"itunes_image" => "http://example.com/cover.jpg", "json_feed" => {"icon" => "http://example.com/icon.png"}})
    stored = feed("stored", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    create_image_row(provider: :feed_icon, provider_id: stored.id.to_s, feed_id: stored.id, kind: :site_icon, variant: "200x200")
    # The same feed id under another provider must not count as stored.
    create_image_row(provider: :embed_icon, provider_id: icon.id.to_s, feed_id: nil, kind: :avatar, variant: "200x200")
    feed("none", {})

    pending = BackfillFeedIcons.pending.where(id: [icon, avatar, image, banner, empty, podcast, stored].map(&:id))

    assert_equal [icon.id, avatar.id, image.id].sort, pending.pluck(:id).sort
  end

  # An empty icon passes the SQL's null test, so the feed reaches the job,
  # which declines it: source_for reads a blank value as no source.
  test "a batch schedules its pending feeds off the critical queues and declines the rest" do
    icon = feed("icon", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    blank = feed("blank", {"json_feed" => {"icon" => ""}})
    assert_includes BackfillFeedIcons.pending.pluck(:id), blank.id

    perform_batches_for(icon, blank)

    assert_equal [icon.id], scheduled_feed_ids
    assert_equal [false], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["critical"] }
    assert_empty BackfillFeedIcons.jobs
  end

  test "reruns skip stored icons but retry feeds whose image never landed" do
    stored = feed("stored", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    failed = feed("failed", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    create_image_row(provider: :feed_icon, provider_id: stored.id.to_s, feed_id: stored.id, kind: :site_icon, variant: "200x200")

    2.times { perform_batches_for(stored, failed) }

    assert_equal [failed.id, failed.id], scheduled_feed_ids
  end

  test "a batch schedules only its own ids" do
    inside = feed("inside", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    batch = batches_for(inside).first

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFeedIcons.new.perform(batch + 1)
      assert_empty ImageCrawler::Pipeline::Find.jobs

      BackfillFeedIcons.new.perform(batch)
      assert_equal [inside.id], scheduled_feed_ids
    end
  end

  # The fan-out: one job per batch of feed ids, pushed in one call with `at`
  # timestamps spaced evenly over the spread, so the image queues see a
  # steady rate instead of every download at once.
  test "schedule pushes one job per batch of feed ids, spaced over the spread" do
    first = feed("first", {"json_feed" => {"icon" => "http://example.com/icon.png"}})
    last = feed("last", {"json_feed" => {"icon" => "http://example.com/icon.png"}})

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFeedIcons.new.perform(nil, true)

      jobs = BackfillFeedIcons.jobs
      expected = BackfillFeedIcons.new.job_args(Feed.maximum(:id), Feed.minimum(:id))
      assert_equal expected.size, jobs.size
      assert_equal expected.first, jobs.first["args"]
      assert_equal expected.last, jobs.last["args"]
      assert_includes jobs.map { it["args"].first }, batches_for(first).first
      assert_includes jobs.map { it["args"].first }, batches_for(last).first

      # Three points, not every job: the fixture ids put ~170k batches in
      # the range, and the spacing is linear, so first, middle, and last
      # prove it.
      step = BackfillFeedIcons::SPREAD.to_f / jobs.size
      [0, jobs.size / 2, jobs.size - 1].each do |index|
        assert_in_delta Time.now.to_f + (index * step), jobs[index]["at"], 5
      end

      # Only the two batches that hold this test's feeds: the fixtures carry
      # hashed ids near 10^9, so draining every batch in the range would run
      # hundreds of thousands of empty pending queries.
      batches_for(first, last).each { |batch| BackfillFeedIcons.new.perform(batch) }
    end

    assert_equal [first.id, last.id].sort, scheduled_feed_ids.sort
  end

  test "schedule takes the spread as an argument" do
    feed("one", {"json_feed" => {"icon" => "http://example.com/icon.png"}})

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFeedIcons.new.perform(nil, true, 3_600)
    end

    jobs = BackfillFeedIcons.jobs
    step = 3_600.0 / jobs.size
    assert_in_delta Time.now.to_f, jobs.first["at"], 5
    assert_in_delta Time.now.to_f + ((jobs.size - 1) * step), jobs.last["at"], 5
  end

  # NOT IN would hash every feed_icon provider_id per query; a LEFT JOIN
  # anti-join uses index_images_on_provider_and_provider_id instead. The
  # join casts feeds.id to text (provider_id is text) and puts images.id in
  # scope, so an unqualified "id" is ambiguous. The json projections are
  # Arel, never a string fragment.
  test "scopes a batch as an anti-join with a qualified id range and json projections" do
    sql = BackfillFeedIcons.batch_scope(1).order(:id).to_sql

    assert_includes sql, %(LEFT OUTER JOIN "images" ON "images"."provider" = 3 AND "images"."provider_id" = CAST("feeds"."id" AS text))
    assert_includes sql, %("images"."id" IS NULL)
    refute_includes sql, "NOT IN"
    assert_includes sql, %("feeds"."id" BETWEEN 1 AND #{SidekiqHelper::BATCH_SIZE})
    assert_includes sql, %("feeds"."options" -> 'json_feed' ->> 'icon' IS NOT NULL)
    assert_includes sql, %("feeds"."options" -> 'json_feed' -> 'author' ->> 'avatar' IS NOT NULL)
    assert_includes sql, %("feeds"."options" -> 'image' ->> 'url' IS NOT NULL AND EXISTS (SELECT 1 FROM "entries" WHERE "entries"."feed_id" = "feeds"."id") AND NOT (EXISTS (SELECT 1 FROM "entries" WHERE "entries"."feed_id" = "feeds"."id" AND "entries"."title" IS NOT NULL AND "entries"."title" != '')))
    assert_includes sql, %("feeds"."options" ->> 'itunes_image' IS NULL)
    assert_nothing_raised { BackfillFeedIcons.batch_scope(1).order(:id).load }
  end

  test "refuses to enqueue without unified storage configured" do
    valid = feed("valid", {"json_feed" => {"icon" => "http://example.com/icon.png"}})

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillFeedIcons.new.perform(nil, true) }
      assert_raises(RuntimeError) { BackfillFeedIcons.new.perform(batches_for(valid).first) }
    end

    assert_empty BackfillFeedIcons.jobs
    assert_empty ImageCrawler::Pipeline::Find.jobs
  end
end
