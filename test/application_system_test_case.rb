require "test_helper"
require "capybara/cuprite"

Capybara.default_max_wait_time = 5

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1400, 1400], process_timeout: 30)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite

  parallelize(workers: 1)

  # Sign in via the dev/test auto_sign_in route rather than the login form —
  # same session, none of the form driving. LoginTest covers the real form.
  def login_as(user)
    visit auto_sign_in_path(email: user.email)
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

  # Polls rather than sleeping a fixed interval; most requests settle in a
  # few milliseconds.
  def wait_for_ajax(duration: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration
    until finished_all_ajax_requests?
      raise "timed out waiting for ajax" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active").zero?
  end
end
