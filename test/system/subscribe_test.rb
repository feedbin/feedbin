require "application_system_test_case"

class SubscribeTest < ApplicationSystemTestCase
  test "Subscribe form" do
    feed_url = "http://www.example.com/atom.xml"
    stub_request_file('atom.xml', feed_url)

    user = users(:ben)
    visit login_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: default_password
    click_button 'Login'
    click_button(class: ['show-subscribe'])

    within("#add_form_modal") do
      fill_in 'q', with: feed_url
      page.execute_script("$('#add_form_modal [data-behavior~=feeds_search]').submit()")
      find("[data-behavior~=subscription_options]")
      click_button 'Add'
    end

    count = find("[data-behavior~=entries_target] li:first-child .feed-title")
    count = all("[data-behavior~=entries_target] li .feed-title").count

    assert_equal(3, count)
  end
end
