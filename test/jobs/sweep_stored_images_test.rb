require "test_helper"

class SweepStoredImagesTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @url = "http://example.com/shared.jpg"
  end

  def stub_batch_delete
    stub_request(:post, "https://test-account.storage.example.com/images-test/?delete")
      .to_return(status: 200, body: "<DeleteResult/>", headers: {content_type: "application/xml"})
  end

  # Rows sharing a url_fingerprint also share their legacy object, so the
  # default legacy url is keyed by url, not by provider_id.
  def seed_row(provider_id:, url: @url, legacy_storage_url: nil, provider: :entry_preview)
    create_image_row(
      provider: provider,
      provider_id: provider_id,
      url: url,
      data: {"legacy_storage_url" => legacy_storage_url || "https://bucket.s3.amazonaws.com/abc/#{Digest::MD5.hexdigest(url)}.jpg"}
    )
  end

  def seed_icon_row(storage_path)
    create_image_row(
      provider: :feed_icon,
      provider_id: SecureRandom.hex,
      url: "http://example.com/favicon.ico",
      variant: "32x32",
      original_fingerprint: SecureRandom.hex(16),
      storage_path: storage_path,
      width: 32, height: 32, bytesize: 500
    )
  end

  test "deletes an object nothing references any more" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      stub_batch_delete
      orphan = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")

      SweepStoredImages.new.perform([orphan])

      assert_requested :post, "https://test-account.storage.example.com/images-test/?delete", times: 1 do |request|
        request.body.include?(orphan)
      end
    end
  end

  # Two hosts can serve byte-identical icons. Replacing one host's icon must
  # not delete the object the other host is still pointing at.
  test "keeps an object another row still references" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batch = stub_batch_delete
      shared = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")
      seed_icon_row(shared)

      SweepStoredImages.new.perform([shared])

      assert_not_requested batch
    end
  end

  test "does nothing with no paths" do
    assert_nothing_raised do
      SweepStoredImages.new.perform([])
    end
  end

  # The deferral is the whole design: the sweep runs a quarter of an hour after
  # the rows went away, and anything that re-referenced the path in the
  # meantime keeps its object. Nothing else covers the interleaving the
  # advisory locks used to serialize.
  test "leaves a path that was re-referenced after the rows were deleted" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batch = stub_batch_delete
      row = seed_row(provider_id: 1)
      path = row.storage_path
      row.delete

      seed_row(provider_id: 2)

      SweepStoredImages.new.perform([path])

      assert_not_requested batch
    end
  end

  # The legacy counterpart, and the race the deferral exists to close: without
  # it the legacy object would be deleted while a row written milliseconds
  # later still pointed at it.
  test "leaves a legacy object that was re-referenced after the rows were deleted" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      stub_batch_delete
      legacy_url = "https://bucket.s3.amazonaws.com/abc/shared-legacy.jpg"
      row = seed_row(provider_id: 1, legacy_storage_url: legacy_url)
      path = row.storage_path
      row.delete

      seed_row(provider_id: 2, legacy_storage_url: legacy_url)

      assert_no_difference -> { ImageDeleter.jobs.size } do
        SweepStoredImages.new.perform([path], [legacy_url])
      end
    end
  end

  test "keeps the objects while other entries reference them" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      row = seed_row(provider_id: 1)
      seed_row(provider_id: 2)
      legacy_url = row.data["legacy_storage_url"]
      row.delete

      batch = stub_batch_delete

      assert_no_difference -> { ImageDeleter.jobs.size } do
        SweepStoredImages.new.perform([row.storage_path], [legacy_url])
      end

      assert_not_requested batch
    end
  end

  test "deletes orphaned objects in one batched call" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      one = Image.storage_path_for(@url, "542x304")
      two = Image.storage_path_for("http://example.com/other.jpg", "542x304")
      batch = stub_batch_delete

      SweepStoredImages.new.perform([one, two])

      assert_requested batch, times: 1
      assert_requested :post, "https://test-account.storage.example.com/images-test/?delete", times: 1 do |request|
        request.body.include?(one) && request.body.include?(two)
      end
    end
  end

  test "deletes the shared legacy object only with the last reference" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      stub_batch_delete
      legacy_url = "https://bucket.s3.amazonaws.com/abc/shared-legacy.jpg"
      one = seed_row(provider_id: 1, legacy_storage_url: legacy_url)
      two = seed_row(provider_id: 2, legacy_storage_url: legacy_url)
      path = one.storage_path

      one.delete
      assert_no_difference -> { ImageDeleter.jobs.size } do
        SweepStoredImages.new.perform([path], [legacy_url])
      end

      two.delete
      assert_difference -> { ImageDeleter.jobs.size }, +1 do
        SweepStoredImages.new.perform([path], [legacy_url])
      end

      assert_equal [legacy_url], ImageDeleter.jobs.last["args"].first
    end
  end

  # Two URLs serving identical bytes are one stored object. Refcounting by url
  # would delete it while the other row still points at it.
  test "keeps an object shared by two different urls until the last row goes" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      shared_path = Image.storage_path_for(@url, "542x304")
      one = seed_row(provider_id: 1)
      two = Image.create!(
        provider: :entry_preview, provider_id: "2", feed_id: 9,
        url: "http://example.com/a-different-url.jpg",
        variant: "542x304", image_fingerprint: one.image_fingerprint,
        storage_path: shared_path,
        width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc"
      )
      batch = stub_batch_delete

      one.delete
      SweepStoredImages.new.perform([shared_path])
      assert_not_requested batch

      two.delete
      SweepStoredImages.new.perform([shared_path])
      assert_requested :post, "https://test-account.storage.example.com/images-test/?delete", times: 1 do |request|
        request.body.include?(shared_path)
      end
    end
  end

  # Content-addressed rows never go through Dedupe, so each carries its own
  # per-row legacy_storage_url even though the show and the episode share one
  # storage_path -- unlike entry previews, where every row sharing a path
  # carries the identical legacy_storage_url. Sweeping the episode must queue
  # its own legacy object even though the path survives via the show's row.
  test "deletes an episode's own legacy object when a surviving show row shares its storage_path" do
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      fingerprint = SecureRandom.hex(16)
      shared_path = Image.content_storage_path_for(fingerprint, "200x200", "jpg")
      episode_legacy = "https://bucket.s3.amazonaws.com/abc/episode-itunes.jpg"
      show_legacy = "https://bucket.s3.amazonaws.com/abc/show-itunes.jpg"

      Image.create!(
        provider: :feed_icon, provider_id: "9", feed_id: 9,
        url: "http://example.com/show-cover.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16), original_fingerprint: fingerprint,
        storage_path: shared_path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc",
        data: {"legacy_storage_url" => show_legacy}
      )
      batch = stub_batch_delete

      assert_difference -> { ImageDeleter.jobs.size }, +1 do
        SweepStoredImages.new.perform([shared_path], [episode_legacy])
      end

      assert_equal [episode_legacy], ImageDeleter.jobs.last["args"].first
      assert_not_requested batch
      assert Image.exists?(storage_path: shared_path)
    end
  end
end
