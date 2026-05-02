require "test_helper"

class WellKnownControllerTest < ActionController::TestCase
  test "apple_site_association renders JSON listing the configured apps" do
    ENV["APPLE_SITE_ASSOCIATION"] = "team.app1,team.app2"
    begin
      get :apple_site_association
      assert_response :success
      assert_equal({"webcredentials" => {"apps" => ["team.app1", "team.app2"]}}, parse_json)
    ensure
      ENV.delete("APPLE_SITE_ASSOCIATION")
    end
  end

  test "apple_pay renders the configured apple pay key as plain text" do
    ENV["APPLE_PAY_KEY"] = "the-key-content"
    begin
      get :apple_pay
      assert_response :success
      assert_equal "the-key-content", @response.body
    ensure
      ENV.delete("APPLE_PAY_KEY")
    end
  end

  test "change_password redirects to settings_account_url with 301" do
    get :change_password
    assert_response :moved_permanently
    assert_redirected_to settings_account_url
  end

  def parse_json
    JSON.parse(@response.body)
  end
end
