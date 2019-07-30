require 'test_helper'

class BookmarkletControllerTest < ActionController::TestCase

  test "should get save_webpage bookmarklet" do
    get :script, params: {cache_buster: Time.now.to_i }
    assert_response :found
  end

end
