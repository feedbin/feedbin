require "test_helper"

class BatchJobsTests < ActiveSupport::TestCase
  include BatchJobs

  test "should enqueue all records" do
    klass = MockModel
    sidekiq_class = BatchJobsJob
    queue_name = sidekiq_class.get_sidekiq_options["queue"].to_s
    queue = Sidekiq::Queues[queue_name]

    queue.clear

    assert_difference -> { queue.count }, +klass.id do
      enqueue_all(klass, sidekiq_class)
    end

    last_job = queue.last

    assert_equal last_job["class"], sidekiq_class.to_s
    assert_equal last_job["queue"], queue_name
    assert_equal [klass.id], last_job["args"]
  end

  private

  class BatchJobsJob
    include Sidekiq::Worker
    sidekiq_options queue: :my_queue, retry: true
  end

  class MockModel
    def self.last
      self
    end

    def self.id
      1_000
    end
  end
end
