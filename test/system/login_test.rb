require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "Login" do
    user = users(:ben)
    login_as(user)
    find("[data-behavior~=show_subscribe]")
  end
end
