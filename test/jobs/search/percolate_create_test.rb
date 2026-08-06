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
  end
end
