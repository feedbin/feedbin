require "test_helper"

class PagesControllerTest < ActionController::TestCase
  test "creates a new job to find page" do
    user = users(:ben)

    Sidekiq::Worker.clear_all
    assert_difference "SavePage.jobs.size", +1 do
      post :create, params: {page_token: user.page_token, url: "http://example.com/article"}
    end
  end

  test "a cookie authenticated save needs a forgery token" do
    Sidekiq::Worker.clear_all
    login_as users(:ben)

    with_forgery_protection do
      assert_no_difference "SavePage.jobs.size" do
        assert_raises ActionController::InvalidAuthenticityToken do
          post :create, params: {url: "http://attacker.example.com/beacon"}
        end
      end
    end
  end

  test "a page_token save does not need a forgery token" do
    Sidekiq::Worker.clear_all
    user = users(:ben)

    with_forgery_protection do
      assert_difference "SavePage.jobs.size", +1 do
        post :create, params: {page_token: user.page_token, url: "http://example.com/article"}
      end
    end
  end

  test "GET /pages is not routable" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path("/pages", method: :get)
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

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
