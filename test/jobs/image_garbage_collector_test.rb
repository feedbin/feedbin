require "test_helper"

class ImageGarbageCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @url = "http://example.com/shared.jpg"
  end

  # Rows sharing a url_fingerprint also share their legacy S3 object, so the
  # default legacy url is keyed by url, not by provider_id.
  def seed_row(provider_id:, url: @url, legacy_storage_url: nil, provider: :entry_preview)
    Image.create!(
      provider: provider,
      provider_id: provider_id.to_s,
      feed_id: 9,
      url: url,
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for(url, "542x304"),
      width: 542, height: 304, bytesize: 12_345,
      placeholder_color: "aabbcc",
      data: {"legacy_storage_url" => legacy_storage_url || "https://bucket.s3.amazonaws.com/abc/#{Digest::MD5.hexdigest(url)}.jpg"}
    )
  end

  def stub_batch_delete
    stub_request(:post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete")
      .to_return(status: 200, body: "<DeleteResult/>", headers: {content_type: "application/xml"})
  end

  test "keeps the objects while other entries reference them" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      seed_row(provider_id: 2)

      batch = stub_batch_delete

      assert_difference -> { Image.count }, -1 do
        assert_no_difference -> { ImageDeleter.jobs.size } do
          ImageGarbageCollector.new.perform([1])
        end
      end

      assert_not_requested batch
      assert Image.exists?(provider_id: "2")
    end
  end

  test "deletes orphaned objects in one batched call" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      row_one = seed_row(provider_id: 1)
      row_two = seed_row(provider_id: 1, url: "http://example.com/other.jpg", provider: :entry_link_preview)
      batch = stub_batch_delete

      ImageGarbageCollector.new.perform([1])

      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(row_one.storage_path) && request.body.include?(row_two.storage_path)
      end
      assert_equal 0, Image.count
    end
  end

  test "deletes the shared legacy object only with the last reference" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      legacy_url = "https://bucket.s3.amazonaws.com/abc/shared-legacy.jpg"
      seed_row(provider_id: 1, legacy_storage_url: legacy_url)
      seed_row(provider_id: 2, legacy_storage_url: legacy_url)
      stub_batch_delete

      assert_no_difference -> { ImageDeleter.jobs.size } do
        ImageGarbageCollector.new.perform([1])
      end

      assert_difference -> { ImageDeleter.jobs.size }, +1 do
        ImageGarbageCollector.new.perform([2])
      end

      assert_equal [legacy_url], ImageDeleter.jobs.last["args"].first
    end
  end

  test "handles entries with both providers and multiple fingerprints" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
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

      stub_batch_delete

      ImageGarbageCollector.new.perform([1])

      assert_equal [other.id], Image.pluck(:id)
    end
  end

  test "does nothing without rows" do
    assert_no_difference -> { ImageDeleter.jobs.size } do
      ImageGarbageCollector.new.perform([12345])
    end
  end

  # Two URLs serving identical bytes are one stored object. Refcounting by url
  # would delete it while the other row still points at it.
  test "keeps an object shared by two different urls until the last row goes" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      shared_path = Image.storage_path_for(@url, "542x304")
      one = seed_row(provider_id: 1)
      Image.create!(
        provider: :entry_preview, provider_id: "2", feed_id: 9,
        url: "http://example.com/a-different-url.jpg",
        variant: "542x304", image_fingerprint: one.image_fingerprint,
        storage_path: shared_path,
        width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc"
      )
      batch = stub_batch_delete

      ImageGarbageCollector.new.perform([1])
      assert_not_requested batch

      ImageGarbageCollector.new.perform([2])
      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(shared_path)
      end
    end
  end

  # Episode artwork is provider entry_icon and is owned by the entry, so
  # deleting the entry must take the row and its object. entry_images
  # deliberately excludes entry_icon -- Dedupe and ReuseRules rely on that --
  # so the collector needs its own, wider scope.
  test "collects an entry's icon row along with its preview rows" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      icon_url = "http://example.com/cover.jpg"
      icon = Image.create!(
        provider: :entry_icon, provider_id: "1", feed_id: 9,
        url: icon_url, variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg"),
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )
      stub_batch_delete

      assert_difference -> { Image.count }, -1 do
        ImageGarbageCollector.new.perform([1])
      end

      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(icon.storage_path)
      end
    end
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
