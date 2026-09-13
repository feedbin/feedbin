require "test_helper"

class ImageTest < ActiveSupport::TestCase
  # A row copied from the proxy's cache, keyed by the MD5 of its url, the
  # legacy remote_files key. Tweet avatars and embed profile images resolve
  # here: legacy data with no crawler.
  test "avatar_url resolves a copied row by the url's fingerprint" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      url = "https://pbs.twimg.com/profile_images/1/me.jpg"
      row = create_image_row(provider: :remote_file, provider_id: RemoteFile.fingerprint(url), feed_id: nil, kind: :avatar, url: url, variant: "200x200")

      assert_equal "https://images.example.com/#{row.storage_path}", Image.avatar_url(url)
      assert_nil Image.avatar_url("https://pbs.twimg.com/profile_images/2/other.jpg")
      assert_nil Image.avatar_url(nil)
    end
  end

  # The entry list resolves the page's tweet avatars in one query and hands
  # the map down as a local, keyed by url. A url with no row is absent.
  test "avatars_for_entries maps the page's tweet avatar urls in one query" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      feed = feeds(:daring_fireball)
      tweet = create_entry(feed)
      tweet.update!(data: {"tweet" => load_tweet("one")})
      url = tweet.tweet_avatar_urls.first
      row = create_image_row(provider: :remote_file, provider_id: RemoteFile.fingerprint(url), feed_id: nil, kind: :avatar, url: url, variant: "200x200")
      plain = create_entry(feed)

      map = nil
      statements = capture_sql { map = Image.avatars_for_entries([tweet, plain]) }

      assert_equal "https://images.example.com/#{row.storage_path}", map[url]
      assert_equal 1, statements.count { it.match?(/FROM "images"/i) }
      assert_empty Image.avatars_for_entries([plain])
    end
  end

  # The one reader of kind for layout: a person or a channel renders in a
  # round frame, everything else in a square one.
  test "icon_format is round for an avatar and square for every other kind" do
    assert_equal "round", create_image_row(kind: :avatar).icon_format
    assert_equal "square", create_image_row(kind: :cover_art, provider_id: "2").icon_format
    assert_equal "square", create_image_row(kind: :site_icon, provider_id: "3").icon_format
    assert_equal "square", create_image_row(kind: :poster, provider_id: "4").icon_format
  end

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

  # kind is the second axis next to provider: provider keys the row, kind
  # says what the picture is. Same enum style so the two read alike.
  test "kind is an enum in the provider style" do
    assert_equal({"cover_art" => 0, "avatar" => 1, "site_icon" => 2, "poster" => 3}, Image.kinds)
    assert create_image_row(kind: :avatar).kind_avatar?
  end

  # NOT NULL with a default: the ADD COLUMN is a catalog change on a big
  # table rather than a rewrite. The default is poster because entry
  # previews are most of the table, so the backfill rewrites the fewest rows.
  test "kind is not null and defaults to poster" do
    column = Image.columns_hash.fetch("kind")
    assert_not column.null
    assert_equal "3", column.default.to_s
    assert_equal "poster", Image.new.kind
  end

  # The column default exists for the migration, not for callers: a row
  # written without a kind would silently be a poster.
  test "attach! requires kind" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 123,
      feed_id: 1,
      url: "http://example.com/a.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg", "542x304"),
      width: 542,
      height: 304,
      bytesize: 10_000,
      placeholder_color: "aabbcc"
    }

    assert_raises(KeyError) { Image.attach!(attributes) }
    assert_equal "poster", Image.attach!(attributes.merge(kind: :poster)).kind
  end

  test "attach! creates then updates rather than duplicating" do
    attributes = {
      kind: :poster,
      provider: Image.providers[:entry_preview],
      provider_id: 123,
      feed_id: 1,
      url: "http://example.com/a.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
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

  # The second pass finds the row the racing writer inserted and updates it.
  # The violation is simulated: a real duplicate insert would poison the
  # transactional fixture wrapping every test.
  test "attach! recovers when it loses the insert race" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 321,
      kind: :poster,
      feed_id: 1,
      url: "http://example.com/race.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
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
      kind: :poster,
      feed_id: 1,
      url: "http://example.com/persistent.jpg",
      variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
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

  test "fingerprints match the cross-language vectors" do
    assert_equal "bdc0d7ea3e0ff6b06d908b58ba09a6e8",
      Image.url_fingerprint_for("https://example.com/image.jpg", "542x304")
    assert_equal "bdc/bdc0d7ea3e0ff6b06d908b58ba09a6e8.jpg",
      Image.storage_path_for("https://example.com/image.jpg", "542x304")
    assert_equal "5c6/5c6f8ef92541100b5a8c292b203f6b89.jpg",
      Image.content_storage_path_for("0123456789abcdef0123456789abcdef", "200x200", "jpg")
    assert_equal "131/1317d9d2047d41d90a3023e08d721a1b.jpg",
      Image.storage_path_for("https://example.com/other.png", "542x304")
  end

  # After the legacy read removal the unified store is the only image path,
  # so a production boot without its two switches must fail here rather
  # than blank every image on the host.
  test "check_unified_config! raises in production when the bucket is blank" do
    production = ActiveSupport::StringInquirer.new("production")
    error = assert_raises(RuntimeError) do
      Image.check_unified_config!(env: production, vars: {"UNIFIED_BUCKET_IMAGES" => "", "UNIFIED_IMAGE_HOST" => "https://images.example.com"})
    end
    assert_match(/UNIFIED_BUCKET_IMAGES/, error.message)
  end

  test "check_unified_config! raises in production when the host is blank" do
    production = ActiveSupport::StringInquirer.new("production")
    error = assert_raises(RuntimeError) do
      Image.check_unified_config!(env: production, vars: {"UNIFIED_BUCKET_IMAGES" => "images", "UNIFIED_IMAGE_HOST" => nil})
    end
    assert_match(/UNIFIED_IMAGE_HOST/, error.message)
  end

  test "check_unified_config! passes in production with both set, and never checks elsewhere" do
    production = ActiveSupport::StringInquirer.new("production")
    development = ActiveSupport::StringInquirer.new("development")
    assert_nil Image.check_unified_config!(env: production, vars: {"UNIFIED_BUCKET_IMAGES" => "images", "UNIFIED_IMAGE_HOST" => "https://images.example.com"})
    assert_nil Image.check_unified_config!(env: development, vars: {})
  end

  # The icon family's readers call public_url on whatever record resolved
  # (an images row, or a favicons row during the cutover) and never inspect
  # its class. Nil until UNIFIED_IMAGE_HOST is set, like unified_url.
  test "public_url is the unified url of the storage path" do
    row = create_image_row

    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      assert_equal "https://images.example.com/#{row.storage_path}", row.public_url
    end

    with_env("UNIFIED_IMAGE_HOST" => nil) do
      assert_nil row.public_url
    end
  end

  # Pages entries key on their own host, so no feed preload reaches them:
  # the entry list resolves the whole collection in one query and hands the
  # map down as a local. Keyed by lower-cased host, whatever case the entry
  # url carries. A host with no row is simply absent from the map.
  test "favicons_for_entries maps pages hosts to their rows in one query" do
    feed = Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "P", feed_type: :pages)
    entries = 3.times.map { |index|
      create_entry(feed).tap { it.update!(url: "http://Site#{index}.example.com/article") }
    }
    rows = entries.map { create_favicon_row(it.hostname.downcase) }
    missing = create_entry(feed).tap { it.update!(url: "http://missing.example.com/article") }

    map = nil
    statements = capture_sql { map = Image.favicons_for_entries(entries + [missing]) }

    assert_equal rows, entries.map { map[it.hostname.downcase] }
    assert_nil map["missing.example.com"]
    assert_equal 1, statements.count { it.match?(/FROM "images"/i) }
    assert_empty statements.select { it.match?(/FROM "favicons"/i) }
  end

  test "favicons_for_entries ignores entries whose feed is not pages" do
    feed = create_feeds(users(:ben)).first
    entry = create_entry(feed)
    create_favicon_row(entry.hostname.downcase)

    assert_equal({}, Image.favicons_for_entries([entry]))
  end
end
