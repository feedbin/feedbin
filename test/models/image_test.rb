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
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.jpg"),
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

  # The second pass finds the row the racing writer inserted and updates it in
  # place, rather than inserting a duplicate or raising. The violation is
  # simulated rather than provoked: no attach! call site runs inside an outer
  # transaction any more, so in production save!'s own transaction rolls the
  # failed insert back and the retry sees a clean connection -- but a test
  # cannot reproduce that, because transactional fixtures put one around every
  # test and a real duplicate insert would poison it.
  test "attach! recovers when it loses the insert race" do
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
    # The row the racing writer inserted, which the first find_by misses.
    Image.attach!(attributes)

    original_find_by = Image.method(:find_by)
    lookups = 0
    misser = ->(*args, **kwargs) do
      lookups += 1
      (lookups == 1) ? nil : original_find_by.call(*args, **kwargs)
    end

    # Stands in for the insert that loses the race. Returned for every new,
    # not just the first, so a second pass that tried to insert again would
    # exhaust the retry and fail this test rather than pass it quietly.
    saboteur = Image.new
    def saboteur.save!(**) = raise(ActiveRecord::RecordNotUnique, "duplicate key")

    record = nil
    Image.stub(:find_by, misser) do
      Image.stub(:new, saboteur) do
        record = Image.attach!(attributes.merge(bytesize: 20_000))
      end
    end

    assert_equal 2, lookups, "the retry re-runs the lookup"
    assert_equal 20_000, record.bytesize
    assert_equal 1, Image.where(provider: attributes[:provider], provider_id: "321").count
  end

  # One retry, not an open loop: a violation that survives the second pass is
  # something the retry cannot fix, and spinning on it would hang the job.
  test "attach! raises rather than looping when the unique violation persists" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 654,
      feed_id: 1,
      url: "http://example.com/persistent.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/persistent.jpg", "542x304"),
      width: 542,
      height: 304,
      bytesize: 10_000,
      placeholder_color: "aabbcc"
    }

    saves = 0
    saboteur = Image.new
    saboteur.define_singleton_method(:save!) do |**|
      saves += 1
      raise ActiveRecord::RecordNotUnique, "duplicate key"
    end

    Image.stub(:find_by, ->(*) { nil }) do
      Image.stub(:new, saboteur) do
        assert_raises(ActiveRecord::RecordNotUnique) { Image.attach!(attributes) }
      end
    end

    assert_equal 2, saves, "one retry, then raise"
  end

  test "storage_path_for defaults to jpg and accepts an extension" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg", "32x32")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.jpg"),
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

  # A uuid column reads back dashed; every fingerprint we compute is 32 bare
  # hex characters. Comparing them directly is silently always false, which
  # would make every icon look changed on every crawl -- the exact cost
  # content-addressing exists to avoid.
  test "same_fingerprint? compares a dashed uuid against a bare hex digest" do
    bare = Digest::MD5.hexdigest("icon bytes")
    dashed = [bare[0, 8], bare[8, 4], bare[12, 4], bare[16, 4], bare[20, 12]].join("-")

    assert Image.same_fingerprint?(dashed, bare)
    assert Image.same_fingerprint?(bare, dashed)
    assert Image.same_fingerprint?(dashed.upcase, bare)
    refute Image.same_fingerprint?(bare, Digest::MD5.hexdigest("other bytes"))
    refute Image.same_fingerprint?(nil, bare)
    refute Image.same_fingerprint?(bare, "")
  end
end
