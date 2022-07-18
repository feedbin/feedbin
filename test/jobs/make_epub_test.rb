require "test_helper"

class MakeEpubTest < ActiveSupport::TestCase
  test "Should build epub" do
    entry = create_entry(Feed.first)
    url = "http://example.com/image.jpg"
    entry.content = "<img src='#{url}' />"
    entry.save

    stub_request_file("index.html", url)

    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com")
    end
  end
end
