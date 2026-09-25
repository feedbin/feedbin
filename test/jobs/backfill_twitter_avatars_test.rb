require "test_helper"

class BackfillTwitterAvatarsTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  test "twitter_rows holds both Twitter hosts on either scheme and nothing else" do
    kept = [
      remote_file("https://pbs.twimg.com/profile_images/1/a.jpg"),
      remote_file("http://pbs.twimg.com/profile_images/2/b.jpg"),
      remote_file("https://abs.twimg.com/sticky/default_profile_images/default_profile.png"),
      remote_file("http://abs.twimg.com/sticky/default_profile_images/default_profile_2.png")
    ]
    remote_file("https://micro.blog/someone/avatar.jpg")
    remote_file("https://pbs.twimg.com.evil.example/profile_images/3/c.jpg")

    assert_equal kept.map(&:id).sort, BackfillTwitterAvatars.twitter_rows.pluck(:id).sort
  end

  test "pending leaves out a row that already has its twitter_avatar image" do
    copied = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
    waiting = remote_file("https://pbs.twimg.com/profile_images/2/b.jpg")
    create_image_row(provider: :twitter_avatar, provider_id: TwitterAvatar.fingerprint(copied.original_url), feed_id: nil, kind: :avatar, url: copied.original_url, variant: "400x400")

    assert_equal [waiting.id], BackfillTwitterAvatars.pending.pluck(:id)
  end

  # NOT IN is never planned as an anti-join; the LEFT JOIN is.
  test "pending is an anti-join" do
    sql = BackfillTwitterAvatars.pending.to_sql

    assert_includes sql, "LEFT OUTER JOIN"
    refute_includes sql, "NOT IN"
  end

  test "batch_for and batch_range agree" do
    assert_equal 1, BackfillTwitterAvatars.batch_for(1)
    assert_equal 1, BackfillTwitterAvatars.batch_for(250)
    assert_equal 2, BackfillTwitterAvatars.batch_for(251)
    assert_equal 251..500, BackfillTwitterAvatars.batch_range(2)
  end

  test "the kickoff pushes one job per batch from the first id to the last" do
    remote_file("https://pbs.twimg.com/profile_images/1/a.jpg", id: 1_000_001)
    remote_file("https://pbs.twimg.com/profile_images/2/b.jpg", id: 1_000_600)

    BackfillTwitterAvatars.new.perform(nil, true)

    first = BackfillTwitterAvatars.batch_for(1_000_001)
    last = BackfillTwitterAvatars.batch_for(1_000_600)
    assert_equal (first..last).zip, BackfillTwitterAvatars.jobs.map { it["args"] }
  end

  test "the kickoff on an empty table pushes nothing" do
    RemoteFile.delete_all

    BackfillTwitterAvatars.new.perform(nil, true)

    assert_empty BackfillTwitterAvatars.jobs
  end

  test "a batch copies a JPEG unchanged and writes its row" do
    stored do
      url = "https://pbs.twimg.com/profile_images/1/a.jpg"
      row = remote_file(url)
      bytes = File.binread(support_file("image.jpeg"))
      stub_request(:get, row.storage_url).to_return(body: bytes)
      fingerprint = Digest::MD5.hexdigest(bytes)
      path = Image.content_storage_path_for(fingerprint, "400x400", "jpg")
      put = stub_request(:put, store_url(path)).with(body: bytes, headers: {"Content-Type" => "image/jpeg"})

      assert_equal [1, 0], BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(row.id))

      assert_requested put
      image = Image.provider_twitter_avatar.find_by!(provider_id: TwitterAvatar.fingerprint(url))
      assert_equal url, image.url
      assert image.kind_avatar?
      assert_equal "400x400", image.variant
      assert_equal path, image.storage_path
      assert_equal fingerprint, Image.normalize_fingerprint(image.image_fingerprint)
      assert_equal fingerprint, Image.normalize_fingerprint(image.original_fingerprint)
      assert_equal bytes.bytesize, image.bytesize
      assert_operator image.width, :>, 0
      assert_operator image.height, :>, 0
      assert_match(/\A\h{6}\z/, image.placeholder_color)
      assert_nil image.feed_id
      assert_equal({"source" => "remote_files"}, image.data)
      assert_empty BackfillTwitterAvatars.pending
    end
  end

  test "a batch copies a PNG with the png extension and content type" do
    stored do
      url = "https://abs.twimg.com/sticky/default_profile_images/default_profile.png"
      row = remote_file(url)
      bytes = File.binread(support_file("image.png"))
      stub_request(:get, row.storage_url).to_return(body: bytes)
      path = Image.content_storage_path_for(Digest::MD5.hexdigest(bytes), "400x400", "png")
      put = stub_request(:put, store_url(path)).with(body: bytes, headers: {"Content-Type" => "image/png"})

      BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(row.id))

      assert_requested put
      assert_equal path, Image.provider_twitter_avatar.find_by!(provider_id: TwitterAvatar.fingerprint(url)).storage_path
    end
  end

  # The default avatar is one object many URLs point at: each URL gets its
  # own row, and both rows share the stored object.
  test "two rows with identical bytes share one stored object" do
    stored do
      bytes = File.binread(support_file("image.png"))
      rows = [
        remote_file("https://pbs.twimg.com/profile_images/1/a.png"),
        remote_file("https://pbs.twimg.com/profile_images/2/b.png")
      ]
      rows.each { stub_request(:get, it.storage_url).to_return(body: bytes) }
      path = Image.content_storage_path_for(Digest::MD5.hexdigest(bytes), "400x400", "png")
      put = stub_request(:put, store_url(path))

      rows.map { BackfillTwitterAvatars.batch_for(it.id) }.uniq.each { BackfillTwitterAvatars.new.update(it) }

      assert_requested put, times: 2
      assert_equal [path, path], Image.provider_twitter_avatar.order(:id).pluck(:storage_path)
    end
  end

  test "a missing object is skipped and stays pending" do
    stored do
      row = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
      stub_request(:get, row.storage_url).to_return(status: 404)

      assert_equal [0, 1], BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(row.id))
      assert_equal [row.id], BackfillTwitterAvatars.pending.pluck(:id)
    end
  end

  test "an unsupported format is skipped and stays pending" do
    stored do
      row = remote_file("https://pbs.twimg.com/profile_images/1/a.ico")
      stub_request(:get, row.storage_url).to_return(body: File.binread(support_file("favicon.ico")))

      assert_equal [0, 1], BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(row.id))
      assert_equal [row.id], BackfillTwitterAvatars.pending.pluck(:id)
    end
  end

  # A PNG signature over garbage passes the format check and fails in the
  # decoder: that is this row's problem, not the batch's.
  test "an undecodable object is skipped and the batch continues" do
    stored do
      broken = remote_file("https://pbs.twimg.com/profile_images/1/broken.png", id: 2_000_001)
      good = remote_file("https://pbs.twimg.com/profile_images/2/good.png", id: 2_000_002)
      bytes = File.binread(support_file("image.png"))
      stub_request(:get, broken.storage_url).to_return(body: "\x89PNG\r\n\x1a\n".b + SecureRandom.random_bytes(512))
      stub_request(:get, good.storage_url).to_return(body: bytes)
      stub_request(:put, store_url(Image.content_storage_path_for(Digest::MD5.hexdigest(bytes), "400x400", "png")))

      assert_equal [1, 1], BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(broken.id))
      assert_equal [broken.id], BackfillTwitterAvatars.pending.pluck(:id)
    end
  end

  # A store failure is the batch's: Sidekiq retries it, and the retry
  # resumes at the first row not copied.
  test "a store error raises" do
    stored do
      row = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
      bytes = File.binread(support_file("image.jpeg"))
      stub_request(:get, row.storage_url).to_return(body: bytes)
      stub_request(:put, store_url(Image.content_storage_path_for(Digest::MD5.hexdigest(bytes), "400x400", "jpg"))).to_return(status: 403)

      assert_raises(Excon::Error) do
        BackfillTwitterAvatars.new.update(BackfillTwitterAvatars.batch_for(row.id))
      end
      assert_equal [row.id], BackfillTwitterAvatars.pending.pluck(:id)
    end
  end

  test "perform with a batch runs update" do
    stored do
      row = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
      stub_request(:get, row.storage_url).to_return(status: 404)

      BackfillTwitterAvatars.new.perform(BackfillTwitterAvatars.batch_for(row.id))

      assert_requested :get, row.storage_url
    end
  end

  test "sizing reports the rows and a sample and writes nothing" do
    good = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
    missing = remote_file("https://pbs.twimg.com/profile_images/2/b.jpg")
    remote_file("https://micro.blog/someone/avatar.jpg")
    stub_request(:get, good.storage_url).to_return(body: File.binread(support_file("image.jpeg")))
    stub_request(:get, missing.storage_url).to_return(status: 404)
    out = StringIO.new

    assert_no_difference "Image.count" do
      BackfillTwitterAvatars.sizing(sample: 10, out: out)
    end

    report = out.string
    assert_includes report, "remote_files rows: 3"
    assert_includes report, "pbs.twimg.com: 2"
    assert_includes report, "micro.blog: 1"
    assert_includes report, "twitter rows: 2"
    assert_includes report, "pending rows: 2"
    assert_includes report, "images rows with provider remote_file: 0"
    assert_includes report, "sample: 2"
    assert_includes report, "failed: 50.0%"
    assert_includes report, "download failed (Feedkit::NotFound): 1"
    assert_includes report, "formats: jpg=1"
    assert_includes report, "estimated thread-hours:"
    assert_not_requested :put, /storage\.example\.com/
  end

  test "sizing with nothing pending reports an empty sample" do
    out = StringIO.new

    BackfillTwitterAvatars.sizing(sample: 10, out: out)

    assert_includes out.string, "pending rows: 0"
    assert_includes out.string, "sample: 0"
  end

  private

  def stored(&)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test", &)
  end

  def store_url(path)
    "https://test-account.storage.example.com/images-test/#{path}"
  end

  def remote_file(url, storage_url: "https://icons.example.net/#{SecureRandom.hex}.jpg", **attributes)
    RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: storage_url, **attributes)
  end
end
