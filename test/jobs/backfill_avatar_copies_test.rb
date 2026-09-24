require "test_helper"

class BackfillAvatarCopiesTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def cached(url, storage_url = "https://icons.example.net/abc/#{SecureRandom.hex(4)}.jpg")
    RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: storage_url)
  end

  def batches_for(*records)
    records.map { |record| ((record.id - 1) / BackfillAvatarCopies::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*records)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batches_for(*records).each { |batch| BackfillAvatarCopies.new.perform(batch) }
    end
  end

  def stub_legacy_object(storage_url)
    stub_request_file("image.png", storage_url, headers: {content_type: "image/png"})
  end

  test "pending is every cached avatar with no remote_file row, joined on the bare fingerprint" do
    todo = cached("https://pbs.twimg.com/1.jpg")
    done = cached("https://pbs.twimg.com/2.jpg")
    create_image_row(provider: :remote_file, provider_id: done.fingerprint.to_s.delete("-"), feed_id: nil, kind: :avatar, url: done.original_url, variant: "200x200")

    assert_equal [todo.id], BackfillAvatarCopies.pending.where(id: [todo.id, done.id]).pluck(:id)

    sql = BackfillAvatarCopies.batch_scope(1).order(:id).to_sql
    assert_includes sql, %(LEFT OUTER JOIN "images" ON "images"."provider" = 4 AND "images"."provider_id" = replace(CAST("remote_files"."fingerprint" AS text), '-', ''))
    assert_includes sql, %("images"."id" IS NULL)
    assert_includes sql, %("remote_files"."id" BETWEEN 1 AND #{BackfillAvatarCopies::BATCH_SIZE})
    refute_includes sql, "NOT IN"
  end

  # The copy re-encodes the legacy object (jpg or png, up to 400px) to the
  # icon preset's 200px png, keyed by the url's bare-hex fingerprint on the
  # remote_file provider, kind avatar, with the original url on the row so
  # a micropost crawler's lookup by url_fingerprint finds it.
  test "copies a cached avatar into a content-addressed row" do
    remote = cached("https://pbs.twimg.com/1.jpg")
    stub_legacy_object(remote.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)

    perform_batches_for(remote)

    row = Image.provider_remote_file.find_by!(provider_id: remote.fingerprint.to_s.delete("-"))
    assert row.kind_avatar?
    assert_equal "https://pbs.twimg.com/1.jpg", row.url
    assert_equal "200x200", row.variant
    assert_match(/\.png\z/, row.storage_path)
    assert_equal "icon", row.data["preset"]
    assert_equal remote.storage_url, row.data["legacy_storage_url"]
    assert_nil row.feed_id
    assert Image.same_fingerprint?(Image.url_fingerprint_for(row.url, "200x200"), row.url_fingerprint)
    assert_requested :put, %r{\Ahttps://test-account\.storage\.example\.com/.*#{Regexp.escape(row.storage_path)}\z}, times: 1
    assert_empty BackfillAvatarCopies.pending.where(id: remote.id)
  end

  # The copy crops with the icon preset's recipe, so changing the preset
  # changes the copies and the variant they are recorded under together.
  test "copies with the icon preset's recipe" do
    remote = cached("https://pbs.twimg.com/1.jpg")
    stub_legacy_object(remote.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)
    presets = ImageCrawler::Image::PRESETS.merge(icon: ImageCrawler::Image::PRESETS[:icon].merge(width: 16, height: 16))

    swap_const(ImageCrawler::Image, :PRESETS, presets) do
      perform_batches_for(remote)
    end

    row = Image.provider_remote_file.find_by!(provider_id: remote.fingerprint.to_s.delete("-"))
    assert_equal "16x16", row.variant
    assert_operator row.width, :<=, 16
  end

  # STORE_ERRORS is batch-level: a storage outage must fail the batch
  # visibly so Sidekiq retries it, not log this one row as "skipped"
  # alongside rows that copied fine.
  test "a storage error aborts the batch instead of skipping the row" do
    remote = cached("https://pbs.twimg.com/1.jpg")
    stub_legacy_object(remote.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/).to_raise(Excon::Error::Timeout)

    assert_raises(Excon::Error) { perform_batches_for(remote) }

    assert_equal [remote.id], BackfillAvatarCopies.pending.where(id: remote.id).pluck(:id)
  end

  # A database error out of create_image is the same kind of batch-level
  # failure as a storage error: the retry must resume at this row, not
  # skip it as though it were merely a dead legacy object.
  test "a database error aborts the batch instead of skipping the row" do
    remote = cached("https://pbs.twimg.com/1.jpg")
    stub_legacy_object(remote.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)

    ::Image.stub(:attach!, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert_raises(ActiveRecord::ActiveRecordError) { perform_batches_for(remote) }
    end

    assert_equal [remote.id], BackfillAvatarCopies.pending.where(id: remote.id).pluck(:id)
  end

  # ROW_ERRORS is per-row: a data error must not poison the rows after it,
  # the way a storage or database error does. The row that raised stays
  # pending; the next row in the same batch still copies.
  test "a row error is skipped instead of aborting the batch" do
    first = cached("https://pbs.twimg.com/1.jpg")
    second = cached("https://pbs.twimg.com/2.jpg")
    stub_legacy_object(first.storage_url)
    stub_legacy_object(second.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)

    original_attach = ::Image.method(:attach!)
    calls = 0
    attach_stub = lambda { |attributes|
      calls += 1
      raise ActiveRecord::NotNullViolation, "boom" if calls == 1
      original_attach.call(attributes)
    }

    ::Image.stub(:attach!, attach_stub) do
      assert_nothing_raised { perform_batches_for(first, second) }
    end

    assert_equal [first.id], BackfillAvatarCopies.pending.where(id: [first.id, second.id]).pluck(:id)
    assert Image.provider_remote_file.exists?(provider_id: second.fingerprint.to_s.delete("-"))
  end

  test "a dead legacy object stays pending and does not stop the batch" do
    dead = cached("https://pbs.twimg.com/dead.jpg")
    live = cached("https://pbs.twimg.com/live.jpg")
    stub_request(:get, dead.storage_url).to_return(status: 404)
    stub_legacy_object(live.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)

    perform_batches_for(dead, live)

    assert_equal [dead.id], BackfillAvatarCopies.pending.where(id: [dead.id, live.id]).pluck(:id)
  end

  test "reruns skip copied rows" do
    remote = cached("https://pbs.twimg.com/1.jpg")
    stub_legacy_object(remote.storage_url)
    stub_request(:put, /test-account\.storage\.example\.com/)

    2.times { perform_batches_for(remote) }

    assert_requested :get, remote.storage_url, times: 1
    assert_equal 1, Image.provider_remote_file.where(provider_id: remote.fingerprint.to_s.delete("-")).count
  end

  test "schedule pushes one job per batch" do
    first = cached("https://pbs.twimg.com/first.jpg")
    last = cached("https://pbs.twimg.com/last.jpg")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillAvatarCopies.new.perform(nil, true)
      jobs = BackfillAvatarCopies.jobs
      assert_equal batches_for(first).first, jobs.first["args"].first
      assert_equal batches_for(last).first, jobs.last["args"].first
    end
  end

  test "refuses to run without unified storage configured" do
    remote = cached("https://pbs.twimg.com/1.jpg")

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillAvatarCopies.new.perform(nil, true) }
      assert_raises(RuntimeError) { BackfillAvatarCopies.new.perform(batches_for(remote).first) }
    end
  end
end
