require "test_helper"

class EntryMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:ben)
    @entry = @user.feeds.first.entries.create!(
      title: "Title",
      url: "https://example.com/entry",
      content: "<p>content</p>",
      public_id: SecureRandom.hex
    )
    ENV["NOTIFICATION_EMAIL"] = "notifications@feedbin.com"
  end

  teardown do
    ENV.delete("NOTIFICATION_EMAIL")
  end

  test "sends from one address when the name is ordinary" do
    mail = deliver("Ben Ubois")

    assert_equal ["notifications@feedbin.com"], mail.from
    assert_equal "Ben Ubois", mail[:from].addrs.first.display_name
  end

  test "sends from one address when the name contains a comma" do
    mail = deliver("Ubois, Ben")

    assert_equal ["notifications@feedbin.com"], mail.from,
      "a comma is the address separator, so an unquoted display name becomes a second address"
    assert_equal "Ubois, Ben", mail[:from].addrs.first.display_name
  end

  test "sends from the notification address when no name is configured" do
    mail = deliver(nil)

    assert_equal ["notifications@feedbin.com"], mail.from
  end

  private

  def deliver(email_name)
    EntryMailer.mailer(@entry.id, "to@example.com", "Subject", "Body", "reply@example.com", email_name, false).message
  end
end
