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
    assert_equal({pending: 1, saved: 0, skipped: 0}, NewsletterBackfill.progress)
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
    assert_equal({pending: 0, saved: @feed.entries.count, skipped: 0}, NewsletterBackfill.progress)
  end

  test "perform skips an entry with no content and counts it" do
    entry = create_entry(@feed)
    entry.update_columns(content: nil)
    stub_request(:put, B2)

    NewsletterBackfill.new.build
    NewsletterBackfill.new.perform(@feed.id)

    assert_not_requested :put, "https://test-account.storage.example.com/newsletters-test/#{entry.public_id[0..2]}/#{entry.public_id}.html"
    assert_equal 1, NewsletterBackfill.progress[:skipped]
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
