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

  test "lists the user's sign-ins to their own apps under Authorized Apps, one row per app" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    2.times { application.access_tokens.create!(resource_owner_id: @user.id, scopes: "") }
    login_as @user

    get :index

    assert_select "form[action=?]", settings_api_authorization_path(application), count: 1
  end

  test "Authorized Apps leaves out tokens created on an application's page" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    application.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    login_as @user

    get :index

    assert_select "form[action=?]", settings_api_authorization_path(application), count: 0
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

  test "Feedbin's own apps have no token section, since their tokens come from signing in" do
    application = @user.oauth_applications.create!(name: "Feedbin", redirect_uri: "", scopes: "read write account")
    application.access_tokens.create!(resource_owner_id: @user.id, device_name: "Development", scopes: "")
    login_as @user

    get :show, params: {id: application}

    assert_response :success
    refute_includes response.body, "Your Tokens"
    refute_includes response.body, "Development"
  end

  test "lists only the tokens created on the application's page, not sign-ins" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    application.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    get :show, params: {id: application}

    assert_includes response.body, "curl on my Mac"
    refute_includes response.body, "Unnamed token"
  end

  test "an application cannot be deleted" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :show, params: {id: application}

    assert_select "form[action=?]", settings_api_application_path(application), count: 0
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

  test "an application's page offers a logo upload, and removal once it has one" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :show, params: {id: application.id}
    assert_select "form[action=?][enctype='multipart/form-data'] input[type=file][name=logo]", settings_api_application_logo_path(application)
    assert_select "img[alt=?]", "My Reader logo", count: 0

    Api::V3::ApplicationLogo.replace(application, Rack::Test::UploadedFile.new(support_file("image.png"), "image/png"))
    get :show, params: {id: application.id}
    assert_select "img[alt=?]", "My Reader logo"
    assert_includes response.body, "Remove"
  end

  test "an application's page links to its edit form" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :show, params: {id: application}

    assert_select "a[href=?]", edit_settings_api_application_path(application), text: "Edit"
  end

  test "renders the edit form without the client type" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    login_as @user

    get :edit, params: {id: application}

    assert_response :success
    assert_select "input[name='doorkeeper_application[name]'][value=?]", "My Reader"
    assert_select "textarea[name='doorkeeper_application[redirect_uri]']", text: "myreader://callback"
    assert_select "input[name='doorkeeper_application[confidential]']", count: 0
  end

  test "renames an application and changes its redirect URIs without touching its tokens" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    patch :update, params: {id: application, doorkeeper_application: {name: "Reader Pro", redirect_uri: "myreader://callback\nhttp://127.0.0.1/callback"}}

    assert_redirected_to settings_api_application_path(application)
    application.reload
    assert_equal "Reader Pro", application.name
    assert_equal %w[myreader://callback http://127.0.0.1/callback], application.redirect_uri.split
    assert_nil token.reload.revoked_at
  end

  test "an update cannot change the client type" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "", confidential: false)
    login_as @user

    patch :update, params: {id: application, doorkeeper_application: {name: "My Reader", confidential: "1"}}

    refute application.reload.confidential?
  end

  test "rejects an invalid update" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    patch :update, params: {id: application, doorkeeper_application: {name: "", redirect_uri: "http://example.com/callback"}}

    assert_response :unprocessable_content
    assert_equal "My Reader", application.reload.name
  end

  test "cannot edit another user's application" do
    application = users(:ann).oauth_applications.create!(name: "Not Yours", redirect_uri: "")
    login_as @user

    assert_raises(ActiveRecord::RecordNotFound) do
      patch :update, params: {id: application, doorkeeper_application: {name: "Mine Now"}}
    end
    assert_equal "Not Yours", application.reload.name
  end
end
