require "test_helper"

class PagesControllerTest < ActionController::TestCase
  test "creates a new job to find page" do
    user = users(:ben)

    Sidekiq::Worker.clear_all
    assert_difference "SavePage.jobs.size", +1 do
      post :create, params: {page_token: user.page_token, url: "http://example.com/article"}
    end
  end

  test "does not enqueue a save that cannot succeed" do
    user = users(:ben)

    Sidekiq::Worker.clear_all
    assert_no_difference "SavePage.jobs.size" do
      post :create, params: {page_token: user.page_token}
    end
    assert_response :bad_request
  end

  test "does not report a page saved when there was no url" do
    user = users(:ben)
    login_as user

    Sidekiq::Worker.clear_all
    assert_no_difference "SavePage.jobs.size" do
      get :fallback
    end
    assert_nil flash[:notice]
    assert flash[:alert].present?
  end
end
