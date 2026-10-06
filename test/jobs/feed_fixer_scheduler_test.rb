require "test_helper"

class FeedFixerSchedulerTest < ActiveSupport::TestCase
  test "enqueues FeedFixer for subscribed feeds with a fixable error" do
    Sidekiq::Worker.clear_all
    broken = users(:ben).subscriptions.first.feed
    24.times { broken.crawl_data.download_error(Exception.new) }
    broken.save!

    FeedFixer.stub_any_instance(:job_args, [[1]]) do
      FeedFixer.stub_any_instance(:build_ids, Feed.pluck(:id)) do
        FeedFixerScheduler.new.perform
      end
    end

    assert_equal [[broken.id]], FeedFixer.jobs.map { it["args"] }
  end
end
