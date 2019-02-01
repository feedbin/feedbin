require "test_helper"

class FeedRefresherSchedulerTest < ActiveSupport::TestCase
  test "should enqueue FeedRefresher" do
    flush_redis
    assert_difference "Sidekiq::Queues['worker_slow_critical'].count", +1 do
      job = perform
      assert job.priority?
    end

    assert_not perform.priority?
  end

  test "should periodically force_refresh" do
    flush_redis
    results = 16.times.each_with_object([]) { |count, array|
      job = perform
      array.push job.force_refresh?
    }
    assert_equal(3, results.count(true))
  end

  private

  def perform
    FeedRefresherScheduler.new.tap do |job|
      def job.job_args(*args)
        [[1]]
      end
      job.perform
    end
  end
end
