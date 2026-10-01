require "test_helper"

class OnboardingControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "show renders without the phlex-rails helpers deprecation warning" do
    login_as @user

    _stdout, stderr = capture_io { get :show }

    assert_response :success
    assert_select "form[action=?]", onboarding_imports_path
    refute_match(/`helpers` method is deprecated/, stderr)
  end
end
