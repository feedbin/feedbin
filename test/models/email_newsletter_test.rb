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

  test "the body is coerced to valid UTF-8 when it has no usable charset" do
    # A body with no declared charset and raw high bytes (0xF1 = ñ in Latin-1)
    # decodes as ASCII-8BIT. valid_encoding? is true for binary, but Postgres
    # rejects the raw bytes as invalid UTF-8 on INSERT, so the invalid bytes get
    # replaced with the U+FFFD replacement character.
    source = <<~EMAIL.dup.force_encoding("ASCII-8BIT")
      From: Hola <hola@example.com>
      To: token@newsletters.feedbin.com
      Subject: Hola
      Date: Tue, 18 May 2021 14:16:22 -0700

      Espa\xF1a, hello
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_equal "Espa�a, hello\r\n", newsletter.text
    assert_equal "Espa�a, hello\r\n", newsletter.content

    [newsletter.text, newsletter.content].each do |value|
      assert_equal Encoding::UTF_8, value.encoding
      assert value.valid_encoding?
    end
  end

  test "text and content are nil when a multipart email has no text or html part" do
    # A multipart message with neither a text/plain nor a text/html part (here,
    # only an image attachment). Mail::Message#decoded raises NoMethodError on a
    # multipart message, so the whole-message fallback must not be reached.
    source = <<~EMAIL
      From: Ben Ubois <ben@benubois.com>
      To: token@newsletters.feedbin.com
      Subject: Multipart with no body
      Date: Tue, 18 May 2021 14:16:22 -0700
      Content-Type: multipart/mixed; boundary="boundary"

      --boundary
      Content-Type: image/png
      Content-Transfer-Encoding: base64
      Content-Disposition: attachment; filename="pixel.png"

      iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==

      --boundary--
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_nil newsletter.text
    assert_nil newsletter.html
    assert_nil newsletter.content
  end
end
