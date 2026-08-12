require "test_helper"

class ImageGarbageCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @url = "http://example.com/shared.jpg"
  end

  def seed_row(provider_id:, url: @url)
    Image.create!(
      provider: :entry_preview,
      provider_id: provider_id.to_s,
      feed_id: 9,
      url: url,
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for(url),
      width: 542, height: 304, bytesize: 12_345,
      placeholder_color: "aabbcc",
      data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/legacy-#{provider_id}.jpg"}
    )
  end

  test "deletes each row's per-entry legacy object regardless of refcount" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      seed_row(provider_id: 2)
      stub_request(:delete, /r2\.cloudflarestorage\.com/).to_return(status: 204)

      assert_difference -> { ImageDeleter.jobs.size }, +1 do
        ImageGarbageCollector.new.perform([1])
      end

      assert_equal ["https://bucket.s3.amazonaws.com/abc/legacy-1.jpg"], ImageDeleter.jobs.last["args"].first
    end
  end

  test "keeps the object while other entries reference it" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      seed_row(provider_id: 2)

      delete = stub_request(:delete, /r2\.cloudflarestorage\.com/).to_return(status: 204)

      assert_difference -> { Image.count }, -1 do
        ImageGarbageCollector.new.perform([1])
      end

      assert_not_requested delete
      assert Image.exists?(provider_id: "2")
    end
  end

  test "deletes the object with the last reference" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      row = seed_row(provider_id: 1)
      delete = stub_request(:delete, "https://test-account.r2.cloudflarestorage.com/images-test/#{row.storage_path}")
        .to_return(status: 204)

      ImageGarbageCollector.new.perform([1])

      assert_requested delete
      assert_equal 0, Image.count
    end
  end

  test "handles entries with both providers and multiple fingerprints" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      other = seed_row(provider_id: 2, url: "http://example.com/other.jpg")
      Image.create!(
        provider: :entry_link_preview, provider_id: "1", feed_id: 9,
        url: "http://example.com/linked.jpg",
        image_fingerprint: SecureRandom.hex(16),
        storage_path: Image.storage_path_for("http://example.com/linked.jpg"),
        width: 542, height: 304, bytesize: 1, placeholder_color: "aabbcc"
      )

      stub_request(:delete, /r2\.cloudflarestorage\.com/).to_return(status: 204)

      ImageGarbageCollector.new.perform([1])

      assert_equal [other.id], Image.pluck(:id)
    end
  end

  test "does nothing without rows" do
    ImageGarbageCollector.new.perform([12345])
  end
end
