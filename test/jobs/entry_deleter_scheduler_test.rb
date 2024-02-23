require "test_helper"

class EntryDeleterSchedulerTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  test "should schedule jobs" do
    assert_difference -> { EntryDeleter.jobs.size }, +Feed.count do
      EntryDeleterScheduler.new.perform
    end
  end

  test "should not schedule jobs" do
    Sidekiq::Testing.disable! do
      Search::SearchServerSetup.perform_async(1)
      assert_no_difference -> { EntryDeleter.jobs.size } do
        EntryDeleterScheduler.new.perform
      end
    end
  end
end
