require "test_helper"

class Settings::ApiApplicationLogosControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
  end

  test "uploads a logo" do
    login_as @user

    post :create, params: {api_application_id: @application.id, logo: upload("image.png")}

    assert_redirected_to settings_api_application_path(@application)
    assert Api::V3::ApplicationLogo.for(@application)
  end

  test "says so when the file is not an image" do
    login_as @user

    post :create, params: {api_application_id: @application.id, logo: upload("atom.xml")}

    assert_redirected_to settings_api_application_path(@application)
    assert_equal "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB.", flash[:alert]
    assert_nil Api::V3::ApplicationLogo.for(@application)
  end

  test "says so when no file was chosen" do
    login_as @user

    post :create, params: {api_application_id: @application.id}

    assert_equal "Logo must be a PNG, JPEG, GIF or WebP image under 5 MB.", flash[:alert]
  end

  test "removes a logo" do
    Api::V3::ApplicationLogo.replace(@application, upload("image.png"))
    login_as @user

    delete :destroy, params: {api_application_id: @application.id}

    assert_redirected_to settings_api_application_path(@application)
    assert_nil Api::V3::ApplicationLogo.for(@application)
  end

  test "cannot change another person's application" do
    theirs = users(:ann).oauth_applications.create!(name: "Theirs", redirect_uri: "")
    login_as @user

    assert_raises ActiveRecord::RecordNotFound do
      post :create, params: {api_application_id: theirs.id, logo: upload("image.png")}
    end

    assert_nil Api::V3::ApplicationLogo.for(theirs)
  end

  private

  def upload(name)
    Rack::Test::UploadedFile.new(support_file(name), "image/png")
  end
end
