require "test_helper"

class EntryDeleterSchedulerTest < ActiveSupport::TestCase
  test "should schedult jobs" do
    Sidekiq::Queues["worker_slow"].clear
    assert_difference "Sidekiq::Queues['worker_slow'].count", +Feed.count do
      EntryDeleterScheduler.new.perform
    end
  end
end
