require "test_helper"

class BackfillChannelImagesTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def channel(id, thumbnails = {"high" => {"url" => "https://yt3.ggpht.com/avatar.jpg"}})
    Embed.youtube_channel.create!(provider_id: id, data: {"snippet" => {"thumbnails" => thumbnails}})
  end

  # The batch that holds an id, in SidekiqHelper's numbering. Sequences do
  # not reset between tests, so the rows can straddle a batch boundary.
  def batches_for(*records)
    records.map { |record| ((record.id - 1) / SidekiqHelper::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*records)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batches_for(*records).each { |batch| BackfillChannelImages.new.perform(batch) }
    end
  end

  test "schedules cached channels without requiring a feed or fetching metadata" do
    playlist = channel("UCplaylist")
    video = Embed.youtube_video.create!(provider_id: "video", data: {})

    perform_batches_for(playlist, video)

    jobs = ImageCrawler::Pipeline::Find.jobs
    assert_equal 1, jobs.size
    assert_equal "UCplaylist", jobs.first["args"].first["provider_id"]
    assert_empty BackfillChannelImages.jobs
  end

  test "reruns skip stored avatars but retry channels whose image never landed" do
    stored = channel("UCstored")
    failed = channel("UCfailed")
    create_image_row(provider: :embed_icon, provider_id: "UCstored")
    # The same id under another provider must not suppress an avatar.
    create_image_row(provider: :feed_icon, provider_id: "UCfailed")

    2.times { perform_batches_for(stored, failed) }

    assert_equal ["UCfailed", "UCfailed"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    assert_equal ["UCfailed"], BackfillChannelImages.pending.pluck(:provider_id)
  end

  test "skips absent thumbnails and continues to the next channel" do
    empty = channel("UCempty", {})
    valid = channel("UCvalid")

    perform_batches_for(empty, valid)

    assert_equal ["UCvalid"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    assert_equal 2, BackfillChannelImages.pending.count
  end

  test "a batch schedules only its own ids" do
    inside = channel("UCinside")
    batch = batches_for(inside).first

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(batch + 1)
      assert_empty ImageCrawler::Pipeline::Find.jobs

      BackfillChannelImages.new.perform(batch)
      assert_equal ["UCinside"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    end
  end

  # The fan-out: one job per batch of embed ids, pushed in one call with
  # `at` timestamps spaced evenly over the spread, so the image queues see
  # a steady rate instead of every download at once.
  test "schedule pushes one job per batch of embed ids, spaced over the spread" do
    first = channel("UCfirst")
    last = channel("UClast")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(nil, true)

      jobs = BackfillChannelImages.jobs
      expected = BackfillChannelImages.new.job_args(Embed.youtube_channel.maximum(:id), Embed.youtube_channel.minimum(:id))
      assert_equal expected, jobs.map { it["args"] }
      assert_includes jobs.map { it["args"].first }, batches_for(first).first
      assert_includes jobs.map { it["args"].first }, batches_for(last).first

      step = BackfillChannelImages::SPREAD.to_f / jobs.size
      jobs.each_with_index do |job, index|
        assert_in_delta Time.now.to_f + (index * step), job["at"], 5
      end

      # Only the backfill jobs: draining Find would download for real.
      BackfillChannelImages.drain
    end

    assert_equal ["UCfirst", "UClast"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }.sort
  end

  test "schedule takes the spread as an argument" do
    channel("UCone")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(nil, true, 3_600)
    end

    jobs = BackfillChannelImages.jobs
    step = 3_600.0 / jobs.size
    assert_in_delta Time.now.to_f, jobs.first["at"], 5
    assert_in_delta Time.now.to_f + ((jobs.size - 1) * step), jobs.last["at"], 5
  end

  test "schedule with no channels pushes nothing" do
    Embed.youtube_video.create!(provider_id: "video", data: {})

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(nil, true)
    end

    assert_empty BackfillChannelImages.jobs
  end

  # NOT IN would hash every embed_icon provider_id per query; a LEFT JOIN
  # anti-join uses index_images_on_provider_and_provider_id instead. The
  # join also puts images.id in scope, so an unqualified "id" is ambiguous.
  test "scopes a batch as an anti-join with a qualified id range" do
    sql = BackfillChannelImages.batch_scope(1).order(:id).to_sql

    assert_includes sql, "LEFT OUTER JOIN"
    refute_includes sql, "NOT IN"
    assert_includes sql, %("embeds"."id" BETWEEN 1 AND #{SidekiqHelper::BATCH_SIZE})
    assert_nothing_raised { BackfillChannelImages.batch_scope(1).order(:id).load }
  end

  test "refuses to enqueue without unified storage configured" do
    valid = channel("UCvalid")

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillChannelImages.new.perform(nil, true) }
      assert_raises(RuntimeError) { BackfillChannelImages.new.perform(batches_for(valid).first) }
    end

    assert_empty BackfillChannelImages.jobs
    assert_empty ImageCrawler::Pipeline::Find.jobs
  end

  test "a failed migration can rerun and store a smaller fallback avatar" do
    retry_channel = channel("UCretry", {
      "high" => {"url" => "https://yt3.ggpht.com/large.jpg"},
      "default" => {"url" => "https://yt3.ggpht.com/small.jpg"}
    })
    stub_request(:get, "https://yt3.ggpht.com/large.jpg").to_return(status: 404)
    stub_request(:get, "https://yt3.ggpht.com/small.jpg").to_return(status: 503)
    stub_request(:put, /test-account\.storage\.example\.com/)

    Sidekiq::Testing.inline! do
      perform_batches_for(retry_channel)
      assert_nil Image.provider_embed_icon.find_by(provider_id: "UCretry")

      stub_request_file("image.png", "https://yt3.ggpht.com/small.jpg", headers: {content_type: "image/png"})
      perform_batches_for(retry_channel)

      row = Image.provider_embed_icon.find_by!(provider_id: "UCretry")
      assert_equal "https://yt3.ggpht.com/small.jpg", row.url
      assert_equal "200x200", row.variant
      assert_match(/\.png\z/, row.storage_path)
      assert_nil row.feed_id
      assert_no_difference -> { Image.count } do
        perform_batches_for(retry_channel)
      end
    end

    assert_requested :get, "https://yt3.ggpht.com/large.jpg", times: 2
    assert_requested :get, "https://yt3.ggpht.com/small.jpg", times: 2
  end
end
