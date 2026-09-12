require "test_helper"

class BackfillFaviconsTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  def legacy(host, url = "https://s3.amazonaws.com/favicons/#{SecureRandom.hex(2)}/#{SecureRandom.hex(20)}.png")
    Favicon.create!(host: host, url: url)
  end

  # The batch that holds an id, in SidekiqHelper's numbering. Sequences do
  # not reset between tests, so the rows can straddle a batch boundary.
  def batches_for(*records)
    records.map { |record| ((record.id - 1) / SidekiqHelper::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*records)
    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      batches_for(*records).each { |batch| BackfillFavicons.new.perform(batch) }
    end
  end

  def stub_legacy_png(favicon)
    stub_request_file("image.png", favicon.url, headers: {content_type: "image/png"})
  end

  def stub_unified_put
    stub_request(:put, %r{\Ahttps://test-account\.storage\.example\.com/images-test/})
  end

  test "copies a legacy favicon into the unified store and writes its row" do
    favicon = legacy("Example.com")
    stub_legacy_png(favicon)
    put = stub_unified_put.with(headers: {"Content-Type" => "image/png"})

    perform_batches_for(favicon)

    row = Image.provider_website_favicon.find_by!(provider_id: "example.com")
    expected = Digest::MD5.file(support_file("image.png")).hexdigest
    assert_equal "site_icon", row.kind
    assert_equal "32x32", row.variant
    assert_equal favicon.url, row.url
    assert_equal favicon.url, row.legacy_storage_url
    assert_equal "favicon", row.preset
    assert_nil row.feed_id
    assert_nil row.etag
    assert Image.same_fingerprint?(expected, row.original_fingerprint)
    assert Image.same_fingerprint?(expected, row.image_fingerprint)
    assert_equal Image.content_storage_path_for(expected, "32x32", "png"), row.storage_path
    assert_equal 1064, row.width
    assert_equal 622, row.height
    assert_equal File.size(support_file("image.png")), row.bytesize
    assert_requested put
  end

  # The join lower-cases favicons.host, so a mixed-case legacy row leaves
  # pending once its lower-cased copy exists.
  test "a copied host leaves pending, whatever case its legacy row carries" do
    favicon = legacy("Mixed.Example.com")
    stub_legacy_png(favicon)
    stub_unified_put

    assert_equal ["Mixed.Example.com"], BackfillFavicons.pending.pluck(:host)
    perform_batches_for(favicon)

    assert_empty BackfillFavicons.pending.pluck(:host)
  end

  test "reruns skip copied hosts but retry hosts whose copy never landed" do
    stored = legacy("stored.example.com")
    failed = legacy("failed.example.com")
    create_favicon_row("stored.example.com")
    stub_request(:get, failed.url).to_return(status: 404)

    2.times { perform_batches_for(stored, failed) }

    assert_requested :get, failed.url, times: 2
    assert_not_requested :get, stored.url
    assert_equal ["failed.example.com"], BackfillFavicons.pending.pluck(:host)
  end

  test "a missing legacy object leaves the host pending and the batch continues" do
    missing = legacy("missing.example.com")
    present = legacy("present.example.com")
    stub_request(:get, missing.url).to_return(status: 404)
    stub_legacy_png(present)
    stub_unified_put

    perform_batches_for(missing, present)

    assert_nil Image.provider_website_favicon.find_by(provider_id: "missing.example.com")
    assert_not_nil Image.provider_website_favicon.find_by(provider_id: "present.example.com")
    assert_equal ["missing.example.com"], BackfillFavicons.pending.pluck(:host)
  end

  test "a non-image body leaves the host pending" do
    favicon = legacy("html.example.com")
    stub_request(:get, favicon.url).to_return(body: "<html></html>", status: 200, headers: {"Content-Type" => "text/html"})

    perform_batches_for(favicon)

    assert_nil Image.provider_website_favicon.find_by(provider_id: "html.example.com")
    assert_equal ["html.example.com"], BackfillFavicons.pending.pluck(:host)
  end

  # Content-addressed: identical legacy bytes on two hosts store one object.
  test "two hosts with byte-identical legacy PNGs share one object" do
    a = legacy("a.example.com")
    b = legacy("b.example.com")
    stub_legacy_png(a)
    stub_legacy_png(b)
    stub_unified_put

    perform_batches_for(a, b)

    rows = Image.provider_website_favicon.where(provider_id: %w[a.example.com b.example.com]).to_a
    assert_equal 2, rows.size
    assert_equal 1, rows.map(&:storage_path).uniq.size
  end

  test "a rerun writes no second row and fetches nothing for a copied host" do
    favicon = legacy("once.example.com")
    stub_legacy_png(favicon)
    stub_unified_put

    perform_batches_for(favicon)
    assert_no_difference -> { Image.count } do
      perform_batches_for(favicon)
    end

    assert_requested :get, favicon.url, times: 1
  end

  test "a batch copies only its own ids" do
    inside = legacy("inside.example.com")
    stub_legacy_png(inside)
    stub_unified_put
    batch = batches_for(inside).first

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFavicons.new.perform(batch + 1)
      assert_not_requested :get, inside.url

      BackfillFavicons.new.perform(batch)
      assert_requested :get, inside.url
    end
  end

  # The fan-out: one job per batch of favicon ids, pushed at once, drained
  # by the utility workers. No delay and no chain.
  test "schedule pushes one job per batch of favicon ids" do
    first = legacy("first.example.com")
    last = legacy("last.example.com")

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFavicons.new.perform(nil, true)
    end

    jobs = BackfillFavicons.jobs
    expected = BackfillFavicons.new.job_args(Favicon.unscoped.maximum(:id), Favicon.unscoped.minimum(:id))
    assert_equal expected, jobs.map { it["args"] }
    assert_includes jobs.map { it["args"].first }, batches_for(first).first
    assert_includes jobs.map { it["args"].first }, batches_for(last).first
  end

  test "schedule with no rows pushes nothing" do
    Favicon.unscoped.delete_all

    with_env("UNIFIED_BUCKET_IMAGES" => "images-test") do
      BackfillFavicons.new.perform(nil, true)
    end

    assert_empty BackfillFavicons.jobs
  end

  # NOT IN would hash every website_favicon provider_id per query; a LEFT
  # JOIN anti-join uses index_images_on_provider_and_provider_id instead.
  # The join lower-cases the host, and the id range is qualified because the
  # join puts images.id in scope.
  test "scopes a batch as a lower-cased anti-join with a qualified id range" do
    sql = BackfillFavicons.batch_scope(1).order(:id).to_sql

    assert_includes sql, "LEFT OUTER JOIN"
    refute_includes sql, "NOT IN"
    assert_includes sql, %(lower("favicons"."host"))
    assert_includes sql, %("images"."provider" = 6)
    assert_includes sql, %("favicons"."id" BETWEEN 1 AND #{SidekiqHelper::BATCH_SIZE})
    assert_nothing_raised { BackfillFavicons.batch_scope(1).order(:id).load }
  end

  test "refuses to run without unified storage configured" do
    favicon = legacy("valid.example.com")

    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      assert_raises(RuntimeError) { BackfillFavicons.new.perform(nil, true) }
      assert_raises(RuntimeError) { BackfillFavicons.new.perform(batches_for(favicon).first) }
    end

    assert_empty BackfillFavicons.jobs
    assert_not_requested :get, favicon.url
  end
end
