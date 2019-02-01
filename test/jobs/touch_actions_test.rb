require "test_helper"

class TouchActionsTest < ActiveSupport::TestCase
  test "should touch action" do
    action = actions(:ben_one)
    TouchActions.new.perform([action.id])
    assert_not_equal action.updated_at, action.reload.updated_at
  end
end
