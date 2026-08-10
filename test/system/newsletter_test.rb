require "application_system_test_case"

class NewsletterTest < ApplicationSystemTestCase
  test "Create Newsletter Address" do
    user = users(:ben)
    user.setting_on!(:addresses_available)
    login_as(user)

    visit settings_newsletters_path

    click_link "New Address"

    fill_in "authentication_token[token]", with: "ben"

    assert find("button[type=submit]").disabled?

    # The availability check debounces before it fires, so wait on the button
    # itself rather than on the request being in flight.
    assert_selector "button[type=submit]:not([disabled])"

    numbers = find("[data-behavior~=token_suffix]").text()

    address = "ben.#{numbers}@newsletters.com"

    assert_selector "[data-behavior~=token_message]", text: address

    click_button "Create"

    wait_for_ajax

    description = "Description"

    fill_in "authentication_token[description]", with: description

    # The description autosaves per keystroke behind a debounce, so poll the
    # record rather than the request counter.
    token = AuthenticationToken.last
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    until token.reload.description == description
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end

    assert_equal(description, token.description)
  end
end
