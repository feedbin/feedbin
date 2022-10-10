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
end
