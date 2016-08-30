require 'test_helper'

class UpdateFaviconHashTest < ActiveSupport::TestCase
  test "should update hash" do
    user = users(:ben)
    UpdateFaviconHash.new().perform(user.id)
    assert_not_equal user.favicon_hash, user.reload.favicon_hash
  end
end
