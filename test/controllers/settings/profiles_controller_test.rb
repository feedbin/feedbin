require "test_helper"

class Settings::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get settings_profiles_index_url
    assert_response :success
  end

  test "should get show" do
    get settings_profiles_show_url
    assert_response :success
  end

  test "should get edit" do
    get settings_profiles_edit_url
    assert_response :success
  end
end
