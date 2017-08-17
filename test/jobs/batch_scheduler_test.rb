require 'test_helper'

class BatchSchedulerTest < ActiveSupport::TestCase
  test "should bulk load jobs" do
    Sidekiq::Queues["worker_slow"].clear
    StarredEntry.create(user_id: 1, feed_id: 1, entry_id: 1)
    worker = "NonExistentWorker"
    count = (StarredEntry.last.id.to_f/BatchJobs::BATCH_SIZE.to_f).ceil

    assert_difference "Sidekiq::Queues['worker_slow'].size", +count do
      BatchScheduler.new().perform("StarredEntry", worker)
    end
    assert_equal worker, Sidekiq::Queues["worker_slow"].first["class"]
  end
end
