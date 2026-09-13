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
    assert_requested :put, /test-account\.storage\.example\.com/, times: 1
    assert_empty BackfillAvatarCopies.pending.where(id: remote.id)
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

  test "schedule pushes one job per batch from a starting batch" do
    first = cached("https://pbs.twimg.com/first.jpg")
    last = cached("https://pbs.twimg.com/last.jpg")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillAvatarCopies.new.perform(nil, true)
      jobs = BackfillAvatarCopies.jobs
      assert_equal 1, jobs.first["args"].first
      assert_equal batches_for(last).first, jobs.last["args"].first
      assert_includes jobs.map { it["args"].first }, batches_for(first).first

      Sidekiq::Worker.clear_all
      BackfillAvatarCopies.new.perform(nil, true, batches_for(last).first)
      assert_equal [batches_for(last).first], BackfillAvatarCopies.jobs.map { it["args"].first }
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
