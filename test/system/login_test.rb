require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  # The one place the real login form gets driven end-to-end — everywhere
  # else uses the auto_sign_in shortcut.
  test "Login" do
    user = users(:ben)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: default_password
    click_button "Sign In"
    find("[data-behavior~=show_subscribe]")
  end
end
