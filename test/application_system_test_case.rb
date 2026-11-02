require "test_helper"
require "capybara/cuprite"

Capybara.default_max_wait_time = 5

# Counts the fetch requests in flight, so wait_for_ajax can wait on them the
# way it waits on jQuery.active. A request counts until its response arrives,
# not until the page has read the body. Runs before the page's own scripts on
# every document.
FETCH_COUNTER = <<~JS
  (() => {
    if (window.pendingFetches !== undefined) return
    window.pendingFetches = 0
    const fetch = window.fetch
    window.fetch = function (...args) {
      window.pendingFetches += 1
      return fetch.apply(this, args).finally(() => { window.pendingFetches -= 1 })
    }
  })()
JS

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # driven_by registers the :cuprite driver itself, over any
  # Capybara.register_driver(:cuprite) block, so the options go here.
  driven_by :cuprite, screen_size: [1400, 1400], options: {process_timeout: 30, extensions: [{source: FETCH_COUNTER}]}

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

  # jQuery.active counts jQuery requests; FETCH_COUNTER counts fetch, which
  # @rails/request.js uses.
  def finished_all_ajax_requests?
    page.evaluate_script("jQuery.active + (window.pendingFetches || 0)").zero?
  end
end
