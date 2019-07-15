require 'test_helper'

class PagesControllerTest < ActionController::TestCase
  test "creates a new job to find page" do
    user = users(:ben)

    Sidekiq::Worker.clear_all
    assert_difference "SavePage.jobs.size", +1 do
      post :create, params: { page_token: user.page_token, url: "http://example.com/article" }
    end
  end
end