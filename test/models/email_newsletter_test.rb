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

  test "content fields are valid UTF-8 when the body has no usable charset" do
    # A body with no declared charset and raw high bytes (0xF1 = ñ in Latin-1)
    # is decoded as an ASCII-8BIT string. valid_encoding? is true for binary,
    # but Postgres rejects the raw bytes as invalid UTF-8 on INSERT.
    source = +"From: Hola <hola@example.com>\r\n"
    source << "To: token@newsletters.feedbin.com\r\n"
    source << "Subject: Hola Espa\xF1a\r\n"
    source << "Date: Tue, 18 May 2021 14:16:22 -0700\r\n"
    source << "\r\n"
    source << "Espa\xF1a, hello\r\n"
    source.force_encoding("ASCII-8BIT")

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    {
      text: newsletter.text,
      content: newsletter.content,
      subject: newsletter.subject,
      to_s: newsletter.to_s
    }.each do |name, value|
      assert_equal Encoding::UTF_8, value.encoding, "#{name} should be UTF-8"
      assert value.valid_encoding?, "#{name} should be valid UTF-8"
    end
  end
end
