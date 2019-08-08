require "test_helper"

class SavePageTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
  end

  test "should build" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, headers: {"Content-Type" => "application/json; charset=utf-8"})
    url = "http://example.com/saved_page"
    Sidekiq::Worker.clear_all
    assert_difference "Feed.count", +1 do
      assert_difference "Entry.count", +1 do
        SavePage.new.perform(@user.id, url, "Title")
      end
    end
    entry = Entry.find_by_url url
  end

end
