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

  test "apple_site_association renders an empty app list when the variable is unset" do
    original = ENV.delete("APPLE_SITE_ASSOCIATION")
    begin
      get :apple_site_association
      assert_response :success
      assert_equal({"webcredentials" => {"apps" => []}}, parse_json)
    ensure
      ENV["APPLE_SITE_ASSOCIATION"] = original if original
    end
  end

  test "android_asset_links groups the configured fingerprints by package" do
    ENV["ANDROID_ASSET_LINKS"] = "com.feedbin.airshow=AA:BB, com.feedbin.airshow=CC:DD,com.feedbin.airshow.debug=EE:FF"
    begin
      get :android_asset_links
      assert_response :success
      assert_equal "application/json", @response.media_type
      statements = parse_json
      assert_equal 2, statements.size
      assert_equal(
        {
          "relation" => ["delegate_permission/common.get_login_creds"],
          "target" => {"namespace" => "android_app", "package_name" => "com.feedbin.airshow", "sha256_cert_fingerprints" => ["AA:BB", "CC:DD"]}
        },
        statements.first
      )
      assert_equal ["EE:FF"], statements.last.dig("target", "sha256_cert_fingerprints")
    ensure
      ENV.delete("ANDROID_ASSET_LINKS")
    end
  end

  test "android_asset_links renders no statements when the variable is unset" do
    original = ENV.delete("ANDROID_ASSET_LINKS")
    begin
      get :android_asset_links
      assert_response :success
      assert_equal [], parse_json
    ensure
      ENV["ANDROID_ASSET_LINKS"] = original if original
    end
  end

  test "android_asset_links is served at the exact path Android fetches" do
    assert_recognizes({controller: "well_known", action: "android_asset_links"}, "/.well-known/assetlinks.json")
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
