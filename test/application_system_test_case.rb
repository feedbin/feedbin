require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :headless_chrome

  def login_as(user)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: default_password
    click_button "Login"
  end

  def show_article_setup
    @user = users(:ben)
    @feed = create_feeds(@user, 1).first
    @entries = @user.entries
  end

  def show_article
    show_article_setup

    login_as(@user)

    click_link(@entries.first.title)
  end

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active").zero?
  end
end
