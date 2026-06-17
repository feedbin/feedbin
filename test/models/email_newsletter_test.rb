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

  test "content fields are coerced to valid UTF-8 when the body has no usable charset" do
    # A header and body with no declared charset and raw high bytes (0xF1 = ñ in
    # Latin-1) decode as ASCII-8BIT. valid_encoding? is true for binary, but
    # Postgres rejects the raw bytes as invalid UTF-8 on INSERT, so the invalid
    # bytes get replaced with the U+FFFD replacement character.
    source = <<~EMAIL.dup.force_encoding("ASCII-8BIT")
      From: Hola <hola@example.com>
      To: token@newsletters.feedbin.com
      Subject: Hola Espa\xF1a
      Date: Tue, 18 May 2021 14:16:22 -0700

      Espa\xF1a, hello
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_equal "Hola Espa�a", newsletter.subject
    assert_equal "Espa�a, hello\r\n", newsletter.text
    assert_equal "Espa�a, hello\r\n", newsletter.content

    [newsletter.subject, newsletter.text, newsletter.content, newsletter.to_s].each do |value|
      assert_equal Encoding::UTF_8, value.encoding
      assert value.valid_encoding?
    end
  end
end
