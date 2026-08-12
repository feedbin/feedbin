require "test_helper"

class ImageTest < ActiveSupport::TestCase
  test "url_fingerprint_for strips and hashes" do
    assert_equal Digest::MD5.hexdigest("http://example.com/a.jpg"),
      Image.url_fingerprint_for(" http://example.com/a.jpg ")
  end

  test "storage_path_for is sharded by fingerprint prefix" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.webp"),
      Image.storage_path_for("http://example.com/a.jpg")
  end

  test "attach! creates then updates rather than duplicating" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 123,
      feed_id: 1,
      url: "http://example.com/a.jpg",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg"),
      width: 542,
      height: 304,
      bytesize: 10_000,
      placeholder_color: "aabbcc"
    }

    record = nil
    assert_difference -> { Image.count }, +1 do
      record = Image.attach!(attributes)
      Image.attach!(attributes.merge(bytesize: 20_000))
    end

    assert_equal "123", record.provider_id
    assert_equal 20_000, record.reload.bytesize
    assert record.url_fingerprint.present?
  end

  test "with_url_lock yields inside a transaction and accepts dashed fingerprints" do
    yielded = false
    Image.with_url_lock("9e107d9d-372b-b682-6bd8-1d3542a419d6") do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end
end
