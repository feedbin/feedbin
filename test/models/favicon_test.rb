require "test_helper"

class FaviconTest < ActiveSupport::TestCase
  test "should add to created_at cache" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Favicon.create!(url: nil)
    end
  end

  # The fan-out is gone: the favicon row is in the view cache digest, so
  # invalidation is the row's own updated_at and nothing needs to write to the
  # feeds that reference it. Asserted through the queue rather than
  # `defined?(TouchFeeds)`, which is nil in a non-eager-loading environment
  # whether the class exists or not.
  test "changing a favicon's url enqueues no fan-out" do
    Feed.create!(feed_url: "http://fanout.example.com/feed", host: "fanout.example.com", title: "F")
    favicon = Favicon.create!(host: "fanout.example.com", url: "http://cdn.example.com/a.png")
    flush_redis

    favicon.update!(url: "http://cdn.example.com/b.png")

    assert_empty Sidekiq::Worker.jobs
  end

  # favicons fallback: remove with the favicons table. The same name as
  # Image#public_url, so a reader resolves either record and never asks
  # which one it got.
  test "public_url is the cdn url" do
    favicon = Favicon.create!(host: "example.com", url: "http://example.com/favicon.ico")

    assert_equal "https://favicons.example.com/favicon.ico", favicon.public_url
    assert_equal favicon.cdn_url, favicon.public_url
  end
end
