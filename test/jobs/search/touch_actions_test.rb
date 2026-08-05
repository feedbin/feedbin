require "test_helper"

module Search
  class TouchActionsTest < ActiveSupport::TestCase
    test "should touch action" do
      action = actions(:ben_one)
      TouchActions.new.perform([action.id])
      assert_not_equal action.updated_at, action.reload.updated_at
    end

    test "should touch the actions that survive when one in the batch was destroyed" do
      action = actions(:ben_one)
      destroyed = Action.maximum(:id).to_i + 10_000

      assert_nothing_raised do
        TouchActions.new.perform([action.id, destroyed])
      end

      assert_not_equal action.updated_at, action.reload.updated_at
    end
  end
end