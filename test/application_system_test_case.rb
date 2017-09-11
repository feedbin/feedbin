require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :headless_chrome

  def show_article
    @user = users(:ben)
    @feed = create_feeds(@user, 1).first
    @entries = @user.entries

    visit login_path
    fill_in 'Email', with: @user.email
    fill_in 'Password', with: default_password
    click_button 'Login'

    click_link(@entries.first.title)
  end
end
