require "test_helper"

class SendStatsTest < ActiveSupport::TestCase
  test "should run" do
    assert_nothing_raised do
      SendStats.new.perform
    end
  end

  test "plan_count skips a user whose plan no longer exists" do
    users(:ann).update_column(:plan_id, Plan.maximum(:id) + 1)

    assert_nothing_raised do
      SendStats.new.plan_count
    end
  end

  test "plan_count skips a user with no plan at all" do
    users(:new).update_column(:plan_id, nil)

    assert_nothing_raised do
      SendStats.new.plan_count
    end
  end

  test "one failing measurement does not take the rest of the run down with it" do
    measured = []

    stats = SendStats.new
    stats.define_singleton_method(:plan_count) { raise "librato is down" }
    stats.define_singleton_method(:sidekiq_queue_depth) { measured << :queue_depth }
    stats.define_singleton_method(:sidekiq_latency) { measured << :latency }

    assert_nothing_raised do
      stats.perform
    end

    assert_equal [:queue_depth, :latency], measured,
      "the Sidekiq telemetry after the failure is the only Sidekiq telemetry there is"
  end
end
