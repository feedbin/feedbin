require "test_helper"

class BackfillChannelImagesTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def channel(id, thumbnails = {"high" => {"url" => "https://yt3.ggpht.com/avatar.jpg"}})
    Embed.youtube_channel.create!(provider_id: id, data: {"snippet" => {"thumbnails" => thumbnails}})
  end

  test "schedules cached channels without requiring a feed or fetching metadata" do
    channel("UCplaylist")
    Embed.youtube_video.create!(provider_id: "video", data: {})

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") { BackfillChannelImages.new.perform }

    jobs = ImageCrawler::Pipeline::Find.jobs
    assert_equal 1, jobs.size
    assert_equal "UCplaylist", jobs.first["args"].first["provider_id"]
    assert_empty BackfillChannelImages.jobs
  end

  test "reruns skip stored avatars but retry channels whose image never landed" do
    channel("UCstored")
    channel("UCfailed")
    create_image_row(provider: :embed_icon, provider_id: "UCstored")
    # The same id under another provider must not suppress an avatar.
    create_image_row(provider: :feed_icon, provider_id: "UCfailed")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      2.times { BackfillChannelImages.new.perform }
    end

    assert_equal ["UCfailed", "UCfailed"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    assert_equal ["UCfailed"], BackfillChannelImages.pending.pluck(:provider_id)
  end

  test "skips absent thumbnails and continues to the next channel" do
    channel("UCempty", {})
    channel("UCvalid")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") { BackfillChannelImages.new.perform }

    assert_equal ["UCvalid"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    assert_equal 2, BackfillChannelImages.pending.count
  end

  test "honors an exclusive resume cursor and inclusive trial cutoff" do
    first = channel("UCfirst")
    last = channel("UClast")
    channel("UClater")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(first.id, last.id)
    end

    assert_equal ["UClast"], ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }
    assert_empty BackfillChannelImages.jobs
  end

  test "continues a full batch with a stable upper bound" do
    records = 501.times.map { |i| channel("UC#{i}") }

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform
      assert_equal 500, ImageCrawler::Pipeline::Find.jobs.size
      continuation = BackfillChannelImages.jobs.shift
      assert_equal [records[499].id, records.last.id, 500, 10], continuation["args"]
      assert continuation["at"]

      channel("UCnew")
      BackfillChannelImages.new.perform(*continuation["args"])
    end

    assert_equal 501, ImageCrawler::Pipeline::Find.jobs.size
    assert_equal 501, ImageCrawler::Pipeline::Find.jobs.map { it["args"].first["provider_id"] }.uniq.size
    assert_empty BackfillChannelImages.jobs
  end

  # The image queues are shared with live crawling, so the operator can
  # restart a flooded run slower without a deploy.
  test "carries the operator's batch size and delay through the chain" do
    3.times { |i| channel("UC#{i}") }

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(0, nil, 2, 60)
    end

    assert_equal 2, ImageCrawler::Pipeline::Find.jobs.size
    continuation = BackfillChannelImages.jobs.shift
    assert_equal [2, 60], continuation["args"].last(2)
    assert_in_delta 60, continuation["at"] - Time.now.to_f, 5
  end

  # limit(0) returns nothing and stops the chain, which is indistinguishable
  # from a finished run.
  test "clamps a batch size that would silently end the run" do
    2.times { |i| channel("UC#{i}") }

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillChannelImages.new.perform(0, nil, 0, 0)
    end

    assert_equal 1, ImageCrawler::Pipeline::Find.jobs.size
    assert_equal 1, BackfillChannelImages.jobs.size
  end

  # NOT IN would hash every embed_icon provider_id per query; a LEFT JOIN
  # anti-join uses index_images_on_provider_and_provider_id instead. The
  # join also puts images.id in scope, so an unqualified "id" is ambiguous.
  test "scopes pending as an anti-join with a qualified id window" do
    sql = BackfillChannelImages.window(1, 2).order(:id).to_sql

    assert_includes sql, "LEFT OUTER JOIN"
    refute_includes sql, "NOT IN"
    assert_includes sql, %("embeds"."id" > 1)
    assert_includes sql, %("embeds"."id" <= 2)
    assert_nothing_raised { BackfillChannelImages.window(1, 2).order(:id).load }
  end

  test "refuses to enqueue without unified storage configured" do
    channel("UCvalid")

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillChannelImages.new.perform }
    end

    assert_empty ImageCrawler::Pipeline::Find.jobs
  end

  test "a failed migration can rerun and store a smaller fallback avatar" do
    channel("UCretry", {
      "high" => {"url" => "https://yt3.ggpht.com/large.jpg"},
      "default" => {"url" => "https://yt3.ggpht.com/small.jpg"}
    })
    stub_request(:get, "https://yt3.ggpht.com/large.jpg").to_return(status: 404)
    stub_request(:get, "https://yt3.ggpht.com/small.jpg").to_return(status: 503)
    stub_request(:put, /test-account\.storage\.example\.com/)

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      Sidekiq::Testing.inline! do
        BackfillChannelImages.new.perform
        assert_nil Image.provider_embed_icon.find_by(provider_id: "UCretry")

        stub_request_file("image.png", "https://yt3.ggpht.com/small.jpg", headers: {content_type: "image/png"})
        BackfillChannelImages.new.perform

        row = Image.provider_embed_icon.find_by!(provider_id: "UCretry")
        assert_equal "https://yt3.ggpht.com/small.jpg", row.url
        assert_equal "200x200", row.variant
        assert_match(/\.png\z/, row.storage_path)
        assert_nil row.feed_id
        assert_no_difference -> { Image.count } do
          BackfillChannelImages.new.perform
        end
      end
    end

    assert_requested :get, "https://yt3.ggpht.com/large.jpg", times: 2
    assert_requested :get, "https://yt3.ggpht.com/small.jpg", times: 2
  end
end
