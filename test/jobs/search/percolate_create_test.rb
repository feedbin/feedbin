require "test_helper"

module Search
  class PercolateCreateTest < ActiveSupport::TestCase
    test "does nothing when the action was destroyed before the job ran" do
      action = actions(:ben_one)
      id = action.id
      action.destroy

      assert_nothing_raised do
        PercolateCreate.new.perform(id)
      end
    end

    # A suspended account must have no percolators. Converting a stray
    # create into a destroy makes the invariant self-heal, whatever path
    # saved the action.
    test "removes the percolator instead when the user is suspended" do
      action = actions(:ben_one)
      users(:ben).update_columns(suspended: true)
      Sidekiq::Worker.clear_all

      PercolateCreate.new.perform(action.id)

      assert_equal [[action.id]], PercolateDestroy.jobs.map { |job| job["args"] }
    end

    test "for_users enqueues one create per action the users own" do
      Sidekiq::Worker.clear_all

      PercolateCreate.for_users(users(:ben).id)

      created = PercolateCreate.jobs.map { |job| job["args"].first }
      assert_equal users(:ben).actions.pluck(:id).sort, created.sort
    end

    test "for_users enqueues one destroy per action the users own" do
      Sidekiq::Worker.clear_all

      PercolateDestroy.for_users(users(:ben).id)

      removed = PercolateDestroy.jobs.map { |job| job["args"].first }
      assert_equal users(:ben).actions.pluck(:id).sort, removed.sort
    end
  end
end
