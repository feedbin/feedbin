require "application_system_test_case"

class ArticleTest < ApplicationSystemTestCase
  test "Show article" do
    user = users(:ben)
    feeds = create_feeds(user, 1)
    entries = user.entries

    visit login_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: default_password
    click_button 'Login'
  end
end
