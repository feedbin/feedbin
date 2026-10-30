require "test_helper"

class Settings::ApiApplicationsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
  end

  test "is hidden without the feature flag" do
    @user.setting_off!(:api_v3)
    login_as @user

    get :index

    assert_response :not_found
  end

  test "lists applications" do
    @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :index

    assert_response :success
    assert_includes response.body, "My Reader"
  end

  test "lists apps the user authorized" do
    other = users(:ann).oauth_applications.create!(name: "Someone Else's Reader", redirect_uri: "myreader://callback")
    other.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    get :index

    assert_includes response.body, "Someone Else&#39;s Reader"
  end

  test "renders the new form" do
    login_as @user

    get :new

    assert_response :success
  end

  test "creates a public application" do
    login_as @user

    assert_difference -> { @user.oauth_applications.count }, 1 do
      post :create, params: {doorkeeper_application: {name: "My Reader", redirect_uri: "myreader://callback", confidential: "0"}}
    end

    application = @user.oauth_applications.last
    assert_redirected_to settings_api_application_path(application)
    refute application.confidential?
    assert_nil flash[:plaintext_secret]
  end

  test "shows a confidential application's secret once" do
    login_as @user

    post :create, params: {doorkeeper_application: {name: "My Server", redirect_uri: "https://example.com/callback", confidential: "1"}}

    application = @user.oauth_applications.last
    assert application.confidential?
    assert flash[:plaintext_secret].present?
    assert application.secret_matches?(flash[:plaintext_secret])
  end

  test "rejects an invalid application" do
    login_as @user

    assert_no_difference -> { Doorkeeper::Application.count } do
      post :create, params: {doorkeeper_application: {name: "", redirect_uri: "http://example.com/callback"}}
    end

    assert_response :unprocessable_content
  end

  test "shows an application" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    application.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    login_as @user

    get :show, params: {id: application}

    assert_response :success
    assert_includes response.body, application.uid
    assert_includes response.body, "curl on my Mac"
  end

  test "does not show another user's application" do
    application = users(:ann).oauth_applications.create!(name: "Not Yours", redirect_uri: "")
    login_as @user

    assert_raises(ActiveRecord::RecordNotFound) do
      get :show, params: {id: application}
    end
  end

  test "deletes an application and its tokens" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    assert_difference -> { Doorkeeper::AccessToken.count }, -1 do
      delete :destroy, params: {id: application}
    end

    assert_redirected_to settings_api_applications_path
    refute Doorkeeper::Application.exists?(application.id)
  end
end
