require "test_helper"

class ImageTest < ActiveSupport::TestCase
  test "url_fingerprint_for strips and hashes url and variant" do
    assert_equal Digest::MD5.hexdigest("542x304|http://example.com/a.jpg"),
      Image.url_fingerprint_for(" http://example.com/a.jpg ", "542x304")
  end

  test "the same url at different variants has different identities" do
    refute_equal Image.url_fingerprint_for("http://example.com/a.jpg", "542x304"),
      Image.url_fingerprint_for("http://example.com/a.jpg", "200x200")
    refute_equal Image.storage_path_for("http://example.com/a.jpg", "542x304"),
      Image.storage_path_for("http://example.com/a.jpg", "200x200")
  end

  test "storage_path_for is sharded by fingerprint prefix" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg", "542x304")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.webp"),
      Image.storage_path_for("http://example.com/a.jpg", "542x304")
  end

  test "attach! creates then updates rather than duplicating" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 123,
      feed_id: 1,
      url: "http://example.com/a.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg", "542x304"),
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

  test "attach! recovers when it loses the insert race inside a transaction" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 321,
      feed_id: 1,
      url: "http://example.com/race.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/race.jpg", "542x304"),
      width: 542,
      height: 304,
      bytesize: 10_000,
      placeholder_color: "aabbcc"
    }
    Image.attach!(attributes)

    original = Image.method(:find_by)
    calls = 0
    misser = ->(*args, **kwargs) do
      calls += 1
      calls == 1 ? nil : original.call(*args, **kwargs)
    end

    record = nil
    Image.stub(:find_by, misser) do
      Image.transaction do
        record = Image.attach!(attributes.merge(bytesize: 20_000))
      end
    end

    assert_equal 20_000, record.bytesize
    assert_equal 1, Image.where(provider: attributes[:provider], provider_id: "321").count
  end

  test "with_storage_lock yields inside a transaction" do
    yielded = false
    Image.with_storage_lock("9e1/9e107d9d372bb6826bd81d3542a419d6.webp") do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end

  test "with_storage_locks takes many locks in one acquisition" do
    yielded = false
    paths = [
      "9e1/9e107d9d372bb6826bd81d3542a419d6.webp",
      "abc/abcdef00000000000000000000000000.png",
      "abc/abcdef00000000000000000000000000.png"
    ]
    Image.with_storage_locks(paths) do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end

  test "storage_path_for defaults to webp and accepts an extension" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg", "32x32")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.webp"),
      Image.storage_path_for("http://example.com/a.jpg", "32x32")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.png"),
      Image.storage_path_for("http://example.com/a.jpg", "32x32", "png")
  end

  test "content_storage_path_for keys on the bytes, not the url" do
    fingerprint = Digest::MD5.hexdigest("some original bytes")
    expected = Digest::MD5.hexdigest("32x32|#{fingerprint}")

    assert_equal File.join(expected[0..2], "#{expected}.png"),
      Image.content_storage_path_for(fingerprint, "32x32", "png")

    refute_equal Image.content_storage_path_for(fingerprint, "32x32", "png"),
      Image.content_storage_path_for(fingerprint, "200x200", "png")
  end

  # A fingerprint read back from the uuid column comes out dashed. Nothing
  # round-trips it today, but the two forms must still hash to the same
  # path or the next caller that does round-trip it silently fragments
  # storage.
  test "content_storage_path_for treats dashed and undashed fingerprints as the same identity" do
    dashed = SecureRandom.uuid
    undashed = dashed.delete("-")

    assert_equal Image.content_storage_path_for(undashed, "200x200", "jpg"),
      Image.content_storage_path_for(dashed, "200x200", "jpg")
  end
end
