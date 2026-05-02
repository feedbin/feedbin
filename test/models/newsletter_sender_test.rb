require "test_helper"

class NewsletterSenderTest < ActiveSupport::TestCase
  test "search_data joins token, full_token, email, name and downcases" do
    sender = NewsletterSender.new(
      token: "Tok",
      full_token: "Full Token",
      email: "Sender@Example.COM",
      name: "Some Sender"
    )

    assert_equal "tokfulltokensender@example.comsomesender", sender.search_data
  end

  test "search_data strips whitespace from joined parts" do
    sender = NewsletterSender.new(
      token: "a b",
      full_token: "c\td",
      email: "user@example.com",
      name: "  Name  "
    )

    assert_equal "abcduser@example.comname", sender.search_data
  end
end
