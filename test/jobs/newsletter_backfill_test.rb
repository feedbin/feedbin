require "test_helper"

class NewsletterBackfillTest < ActiveSupport::TestCase
  B2 = %r{test-account\.storage\.example\.com/newsletters-test/}

  setup do
    Sidekiq::Worker.clear_all
    flush_redis
    @feed = Feed.first
    @feed.update!(feed_type: :newsletter)
    @other = Feed.where.not(id: @feed.id).first
  end

  test "build enqueues only newsletter feeds and sets pending" do
    NewsletterBackfill.new.build

    assert_equal [[@feed.id]], NewsletterBackfill.jobs.map { it["args"] }
    assert_equal({pending: 1, saved: 0, mismatched: 0}, NewsletterBackfill.progress)
  end

  test "perform puts one object for each entry" do
    entries = 2.times.map { create_entry(@feed) }
    request = stub_request(:put, B2)

    NewsletterBackfill.new.build
    NewsletterBackfill.new.perform(@feed.id)

    entries.each do |entry|
      assert_requested :put, "https://test-account.storage.example.com/newsletters-test/#{entry.public_id[0..2]}/#{entry.public_id}.html"
    end
    assert_requested request, times: @feed.entries.count
    assert_equal({pending: 0, saved: @feed.entries.count, mismatched: 0}, NewsletterBackfill.progress)
  end

  test "perform saves an entry with no content" do
    entry = create_entry(@feed)
    entry.update_columns(content: nil)
    stub_request(:put, B2)

    NewsletterBackfill.new.build
    NewsletterBackfill.new.perform(@feed.id)

    assert_requested :put, "https://test-account.storage.example.com/newsletters-test/#{entry.public_id[0..2]}/#{entry.public_id}.html"
  end

  test "perform counts a url on the newsletter host that is not the page url" do
    matching = create_entry(@feed)
    with_bucket = create_entry(@feed)
    elsewhere = create_entry(@feed)
    stub_request(:put, B2)

    with_env("NEWSLETTER_HOST" => "newsletters.example.com") do
      matching.update_columns(url: NewsletterPage.new(matching).url)
      with_bucket.update_columns(url: "https://newsletters.example.com/old-bucket/#{NewsletterPage.new(with_bucket).key}")
      elsewhere.update_columns(url: "https://example.com/newsletters/#{elsewhere.public_id}")

      NewsletterBackfill.new.build
      NewsletterBackfill.new.perform(@feed.id)
    end

    assert_equal 1, NewsletterBackfill.progress[:mismatched]
  end

  test "build refuses while a pass is running" do
    NewsletterBackfill.new.build

    assert_raises(RuntimeError) { NewsletterBackfill.new.build }
    NewsletterBackfill.new.build(force: true)
    assert_equal 1, NewsletterBackfill.progress[:pending]
  end

  test "perform never writes to S3 or changes a row" do
    create_entry(@feed)
    stub_request(:put, B2)
    before = @feed.entries.pluck(:id, :url, :updated_at)

    with_env("AWS_S3_BUCKET_NEWSLETTERS" => "legacy-newsletters") do
      NewsletterBackfill.new.perform(@feed.id)
    end

    assert_not_requested :put, /s3\.amazonaws\.com/
    assert_equal before, @feed.entries.reload.pluck(:id, :url, :updated_at)
  end

  test "a failed put leaves pending unchanged" do
    create_entry(@feed)
    stub_request(:put, B2).to_return(status: 500)

    NewsletterBackfill.new.build
    assert_raises(Excon::Error) { NewsletterBackfill.new.perform(@feed.id) }

    assert_equal 1, NewsletterBackfill.progress[:pending]
  end

  test "a deleted feed finishes its job" do
    NewsletterBackfill.new.build
    NewsletterBackfill.new.perform(0)

    assert_equal 0, NewsletterBackfill.progress[:pending]
  end
end
