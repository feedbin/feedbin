require "test_helper"

class ImageReplacementCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  def stub_batch_delete
    stub_request(:post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete")
      .to_return(status: 200, body: "<DeleteResult/>", headers: {content_type: "application/xml"})
  end

  def seed_row(storage_path)
    Image.create!(
      provider: :feed_icon, provider_id: SecureRandom.hex, feed_id: 9,
      url: "http://example.com/favicon.ico", variant: "32x32",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: storage_path,
      width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
    )
  end

  test "deletes an object nothing references any more" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      stub_batch_delete
      orphan = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")

      ImageReplacementCollector.new.perform([orphan])

      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(orphan)
      end
    end
  end

  # Two hosts can serve byte-identical icons. Replacing one host's icon must
  # not delete the object the other host is still pointing at.
  test "keeps an object another row still references" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      batch = stub_batch_delete
      shared = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")
      seed_row(shared)

      ImageReplacementCollector.new.perform([shared])

      assert_not_requested batch
    end
  end

  test "does nothing with no paths" do
    assert_nothing_raised do
      ImageReplacementCollector.new.perform([])
    end
  end
end
