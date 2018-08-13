require "test_helper"

class FaviconTest < ActiveSupport::TestCase
  test "should add to created_at cache" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Favicon.create!(url: nil)
    end
  end
end
