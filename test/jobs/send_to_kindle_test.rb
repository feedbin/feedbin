require "test_helper"

class SendToKindleTest < ActiveSupport::TestCase
  test "Should send email" do
    if ENV["KINDLEGEN_PATH"]
      assert_difference "ActionMailer::Base.deliveries.count", +1 do
        entry = create_entry(Feed.first)
        SendToKindle.new.perform(entry.id, "example@example.com")
      end
    end
  end
end
