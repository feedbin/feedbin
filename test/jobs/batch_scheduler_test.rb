require "test_helper"

class BatchSchedulerTest < ActiveSupport::TestCase
  test "should bulk load jobs" do
    Sidekiq::Queues["worker_slow"].clear

    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries

    StarredEntry.create!(user_id: @user.id, feed_id: @entries.first.feed_id, entry_id: @entries.first.id)
    worker = "NonExistentWorker"
    count = (StarredEntry.last.id.to_f / BatchJobs::BATCH_SIZE.to_f).ceil

    assert_difference "Sidekiq::Queues['worker_slow'].size", +count do
      BatchScheduler.new.perform("StarredEntry", worker)
    end
    assert_equal worker, Sidekiq::Queues["worker_slow"].first["class"]
  end
end
