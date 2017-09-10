require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "Login" do
    user = users(:ben)
    visit login_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: default_password
    click_button 'Login'
    find_button(class: ['show-subscribe']).visible?
  end
end
