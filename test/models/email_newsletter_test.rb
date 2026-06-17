require "test_helper"

class EmailNewsletterTest < ActiveSupport::TestCase
  test "to_email returns nil when To header is missing" do
    source = <<~EMAIL
      From: Ben Ubois <ben@benubois.com>
      Subject: No To Header
      Date: Tue, 18 May 2021 14:16:22 -0700

      This is a plain text email with no To header.
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_nil newsletter.to_email
  end

  test "to_email returns the address when To header is present" do
    source = <<~EMAIL
      From: Ben Ubois <ben@benubois.com>
      To: token@newsletters.feedbin.com
      Subject: Has To Header
      Date: Tue, 18 May 2021 14:16:22 -0700

      This is a plain text email.
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_equal "token@newsletters.feedbin.com", newsletter.to_email
  end
end
