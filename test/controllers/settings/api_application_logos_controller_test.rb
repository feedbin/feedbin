require "test_helper"

class Settings::ApiApplicationLogosControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
  end

  test "removes a logo and returns to the edit form" do
    Api::V3::ApplicationLogo.replace(@application, upload)
    login_as @user

    delete :destroy, params: {api_application_id: @application.id}

    assert_redirected_to edit_settings_api_application_path(@application)
    assert_nil Api::V3::ApplicationLogo.for(@application)
  end

  test "cannot remove the logo of another person's application" do
    theirs = users(:ann).oauth_applications.create!(name: "Theirs", redirect_uri: "")
    Api::V3::ApplicationLogo.replace(theirs, upload)
    login_as @user

    assert_raises ActiveRecord::RecordNotFound do
      delete :destroy, params: {api_application_id: theirs.id}
    end

    assert Api::V3::ApplicationLogo.for(theirs)
  end

  private

  def upload
    Rack::Test::UploadedFile.new(support_file("image.png"), "image/png")
  end
end
