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

    wait_for_ajax(duration: 1)

    assert_not find("button[type=submit]").disabled?

    numbers = find("[data-behavior~=token_suffix]").text()

    address = "ben.#{numbers}@newsletters.com"

    assert_selector "[data-behavior~=token_message]", text: address

    click_button "Create"

    wait_for_ajax

    description = "Description"

    fill_in "authentication_token[description]", with: description

    wait_for_ajax(duration: 0.5)

    token = AuthenticationToken.last

    assert_equal(description, token.description)
  end
end
