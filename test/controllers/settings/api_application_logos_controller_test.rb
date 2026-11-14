require "test_helper"

class Settings::ApiApplicationLogosControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
  end

  test "removes a logo, keeps the details, and returns to the edit form" do
    with_image_store do
      Api::V3::ApplicationProfile.for(@application).update!(description: "Reads feeds.", logo_file: upload)
      login_as @user

      delete :destroy, params: {api_application_id: @application.id}

      assert_redirected_to edit_settings_api_application_path(@application)
      refute Api::V3::ApplicationProfile.for(@application).logo?
      assert_equal "Reads feeds.", Api::V3::ApplicationProfile.for(@application).description
    end
  end

  test "removing a logo that is not there stores nothing" do
    login_as @user

    delete :destroy, params: {api_application_id: @application.id}

    assert_redirected_to edit_settings_api_application_path(@application)
    assert_equal 0, Api::V3::ApplicationProfile.count
  end

  test "cannot remove the logo of another person's application" do
    with_image_store do
      theirs = users(:ann).oauth_applications.create!(name: "Theirs", redirect_uri: "")
      Api::V3::ApplicationProfile.for(theirs).update!(logo_file: upload)
      login_as @user

      assert_raises ActiveRecord::RecordNotFound do
        delete :destroy, params: {api_application_id: theirs.id}
      end

      assert Api::V3::ApplicationProfile.for(theirs).logo?
    end
  end

  private

  def upload
    Rack::Test::UploadedFile.new(support_file("image.png"), "image/png")
  end
end
