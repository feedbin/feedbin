require "test_helper"

class SendStatsTest < ActiveSupport::TestCase
  test "should run" do
    assert_nothing_raised do
      SendStats.new.perform
    end
  end
end
