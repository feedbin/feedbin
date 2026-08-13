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
end
