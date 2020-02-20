require "test_helper"

class SparklineTest < ActiveSupport::TestCase
  test "should generate line points" do
    sparkline = Sparkline.new(width: 10, height: 10, stroke: 2, percentages: [0.5, 0.1])
    assert_equal("1,5.0 9.0,9.0", sparkline.line)
    assert_equal("0,10.0 0.0,5.0 10.0,9.0 10.0,10.0", sparkline.fill)
  end

  test "should generate points with zeros" do
    sparkline = Sparkline.new(width: 10, height: 10, stroke: 2, percentages: [0, 0])
    assert_equal("1,9.0 9.0,9.0", sparkline.line)
    assert_equal("0,10.0 0.0,10.0 10.0,10.0 10.0,10.0", sparkline.fill)
  end
end
