require "test_helper"

class ImageGarbageCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @url = "http://example.com/shared.jpg"
  end

  # Rows sharing a url_fingerprint also share their legacy S3 object, so the
  # default legacy url is keyed by url, not by provider_id.
  def seed_row(provider_id:, url: @url, legacy_storage_url: nil, provider: :entry_preview)
    create_image_row(
      provider: provider,
      provider_id: provider_id,
      url: url,
      data: {"legacy_storage_url" => legacy_storage_url || "https://bucket.s3.amazonaws.com/abc/#{Digest::MD5.hexdigest(url)}.jpg"}
    )
  end

  # The collector deletes rows and hands both object lists on. Whether an
  # object survives is the sweep's decision, made fifteen minutes later against
  # the rows that exist then -- see sweep_stored_images_test.rb.
  def scheduled_sweep
    SweepStoredImages.jobs.last
  end

  test "deletes the rows and schedules a sweep for their objects" do
    row_one = seed_row(provider_id: 1)
    row_two = seed_row(provider_id: 1, url: "http://example.com/other.jpg", provider: :entry_link_preview)

    assert_difference -> { Image.count }, -2 do
      assert_difference -> { SweepStoredImages.jobs.size }, +1 do
        ImageGarbageCollector.new.perform([1])
      end
    end

    paths, legacy_urls = scheduled_sweep["args"]
    assert_equal [row_one.storage_path, row_two.storage_path].sort, paths.sort
    assert_equal [row_one.data["legacy_storage_url"], row_two.data["legacy_storage_url"]].sort, legacy_urls.sort
  end

  test "schedules the sweep a quarter of an hour out" do
    seed_row(provider_id: 1)

    ImageGarbageCollector.new.perform([1])

    assert_in_delta (Time.now + ImageGarbageCollector::SWEEP_DELAY).to_f, scheduled_sweep["at"], 5
  end

  # Only this entry's rows go, and only this entry's objects are handed to the
  # sweep. Another entry's row sharing the path is what keeps the object alive,
  # and that check belongs to the sweep -- but the path still has to reach it.
  test "sweeps a shared path while another entry still references it" do
    row = seed_row(provider_id: 1)
    seed_row(provider_id: 2)

    assert_difference -> { Image.count }, -1 do
      ImageGarbageCollector.new.perform([1])
    end

    assert Image.exists?(provider_id: "2")
    assert_equal [row.storage_path], scheduled_sweep["args"].first
  end

  test "handles entries with both providers and multiple fingerprints" do
    seed_row(provider_id: 1)
    other = seed_row(provider_id: 2, url: "http://example.com/other.jpg")
    Image.create!(
      provider: :entry_link_preview, provider_id: "1", feed_id: 9,
      url: "http://example.com/linked.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/linked.jpg", "542x304"),
      width: 542, height: 304, bytesize: 1, placeholder_color: "aabbcc"
    )

    ImageGarbageCollector.new.perform([1])

    assert_equal [other.id], Image.pluck(:id)
  end

  test "does nothing without rows" do
    assert_no_difference -> { SweepStoredImages.jobs.size } do
      ImageGarbageCollector.new.perform([12345])
    end
  end

  # Episode artwork is provider entry_icon and is owned by the entry, so
  # deleting the entry must take the row and hand on its object. entry_images
  # deliberately excludes entry_icon -- Dedupe and ReuseRules rely on that --
  # so the collector needs its own, wider scope.
  test "collects an entry's icon row along with its preview rows" do
    icon = Image.create!(
      provider: :entry_icon, provider_id: "1", feed_id: 9,
      url: "http://example.com/cover.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )

    assert_difference -> { Image.count }, -1 do
      ImageGarbageCollector.new.perform([1])
    end

    assert_equal [icon.storage_path], scheduled_sweep["args"].first
  end

  # The narrow scope is load-bearing elsewhere: widening it would let an icon
  # crawl dedupe onto an entry-preview row. Asserted behaviourally rather than
  # by inspecting where_values_hash, which holds cast enum integers.
  test "entry_images excludes icon rows while entry_owned includes them" do
    icon = Image.create!(
      provider: :entry_icon, provider_id: "77", feed_id: 9,
      url: "http://example.com/cover.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )

    refute_includes Image.entry_images, icon
    assert_includes Image.entry_owned, icon
  end
end
