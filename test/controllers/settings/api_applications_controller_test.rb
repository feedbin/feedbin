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

  test "the API page is for developers: no Authorized Apps" do
    other = users(:ann).oauth_applications.create!(name: "Someone Else's Reader", redirect_uri: "myreader://callback")
    other.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    get :index

    refute_includes response.body, "Authorized Apps"
  end

  test "renders the new form" do
    login_as @user

    get :new

    assert_response :success
  end

  test "creates an application, public whatever the form sends" do
    login_as @user

    assert_difference -> { @user.oauth_applications.count }, 1 do
      post :create, params: {doorkeeper_application: {name: "My Reader", redirect_uri: "myreader://callback", confidential: "1"}}
    end

    application = @user.oauth_applications.last
    assert_redirected_to settings_api_application_path(application)
    refute application.confidential?
    assert_nil flash[:plaintext_secret]
  end

  test "the new form takes a logo and has no client type" do
    login_as @user

    get :new

    assert_select "form[action=?][enctype='multipart/form-data'] input[type=file][name=logo]", settings_api_applications_path
    assert_select "input[name='doorkeeper_application[confidential]']", count: 0
  end

  test "creates an application with its logo" do
    login_as @user

    post :create, params: {doorkeeper_application: {name: "My Reader", redirect_uri: ""}, logo: logo_upload("image.png")}

    assert Api::V3::ApplicationLogo.for(@user.oauth_applications.last)
  end

  test "a logo that is not an image creates nothing and says why" do
    login_as @user

    assert_no_difference -> { Doorkeeper::Application.count } do
      post :create, params: {doorkeeper_application: {name: "My Reader", redirect_uri: ""}, logo: logo_upload("atom.xml")}
    end

    assert_response :unprocessable_content
    assert_includes response.body, "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB."
    assert_select "form[action=?] input[name='doorkeeper_application[name]'][value=?]", settings_api_applications_path, "My Reader"
  end

  test "Feedbin's own apps offer token creation like any other" do
    application = @user.oauth_applications.create!(name: "Feedbin", redirect_uri: "", scopes: "read write account")
    login_as @user

    get :show, params: {id: application}

    assert_select "form[action=?] input[name='token[device_name]']", settings_api_application_tokens_path(application)
  end

  test "a new token's value is shown once, in its own row" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    application.access_tokens.create!(resource_owner_id: @user.id, device_name: "older", scopes: "")
    token = application.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    login_as @user

    get :show, params: {id: application}, flash: {plaintext_token: token.plaintext_token}

    assert_select "#token_#{token.id} [data-copyable-data-value=?]", token.plaintext_token
    assert_select "[data-copyable-data-value=?]", token.plaintext_token, count: 1
    assert_select "#token_#{token.id}", text: /won’t be shown again/
  end

  test "a token's value is not shown on a later visit" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    token = application.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    login_as @user

    get :show, params: {id: application}

    refute_includes response.body, token.plaintext_token
    assert_select "#token_#{token.id}", text: /Created/
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

  test "an application's page offers a copy button for each value a client needs" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback\nhttp://127.0.0.1/callback")
    login_as @user

    get :show, params: {id: application}

    [application.uid, "myreader://callback", "http://127.0.0.1/callback", oauth_authorization_url, oauth_token_url].each do |value|
      assert_select "[data-controller=copyable][data-copyable-data-value=?]", value
    end
  end

  test "an application's page shows its logo, and changes nothing itself" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    Api::V3::ApplicationLogo.replace(application, logo_upload("image.png"))
    login_as @user

    get :show, params: {id: application}

    assert_select "img[alt=?]", "My Reader logo"
    assert_select "input[type=file]", count: 0
  end

  test "the edit form takes a logo, and offers removal once there is one" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :edit, params: {id: application}
    assert_select "form[action=?][enctype='multipart/form-data'] input[type=file][name=logo]", settings_api_application_path(application)
    assert_select "button[form=remove_logo]", count: 0

    Api::V3::ApplicationLogo.replace(application, logo_upload("image.png"))
    get :edit, params: {id: application}
    assert_select "img[alt=?]", "My Reader logo"
    assert_select "form#remove_logo[action=?]", settings_api_application_logo_path(application)
    assert_select "button[form=remove_logo]", text: "Remove"
  end

  test "saves a logo with the rest of the form" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    patch :update, params: {id: application, doorkeeper_application: {name: "Reader Pro", redirect_uri: ""}, logo: logo_upload("image.png")}

    assert_redirected_to settings_api_application_path(application)
    assert_equal "Reader Pro", application.reload.name
    assert Api::V3::ApplicationLogo.for(application)
  end

  test "a file that is not an image saves nothing and says why" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    patch :update, params: {id: application, doorkeeper_application: {name: "Reader Pro", redirect_uri: ""}, logo: logo_upload("atom.xml")}

    assert_response :unprocessable_content
    assert_includes response.body, "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB."
    assert_equal "My Reader", application.reload.name
    assert_nil Api::V3::ApplicationLogo.for(application)
  end

  test "an application's page links to its edit form" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    login_as @user

    get :show, params: {id: application}

    assert_select "a[href=?]", edit_settings_api_application_path(application), text: "Edit"
  end

  test "renders the edit form" do
    application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "myreader://callback")
    login_as @user

    get :edit, params: {id: application}

    assert_response :success
    assert_select "input[name='doorkeeper_application[name]'][value=?]", "My Reader"
    assert_select "textarea[name='doorkeeper_application[redirect_uri]']", text: "myreader://callback"
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

  private

  def logo_upload(name)
    Rack::Test::UploadedFile.new(support_file(name), "image/png")
  end
end
