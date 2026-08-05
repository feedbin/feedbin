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

  test "takes the sender from a From name containing an unquoted comma" do
    source = <<~EMAIL
      From: Foo, Inc. <news@foo.com>
      To: token@newsletters.feedbin.com
      Subject: Hi
      Date: Tue, 18 May 2021 14:16:22 -0700

      body
    EMAIL

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_equal "news@foo.com", newsletter.from_email,
      "a comma is the address separator, so addresses.first is the display-name fragment"
    assert_equal "foo.com", newsletter.domain
    assert_equal "http://foo.com", newsletter.site_url
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

  test "a From header with no usable address is invalid rather than a crash" do
    sources = {
      "display name only" => "From: Some Newsletter",
      "empty angle addr" => "From: <>",
      "empty From value" => "From: ",
      "empty group" => "From: undisclosed-recipients:;",
      "no From header" => nil
    }

    sources.each do |description, from|
      source = [from, "To: token@newsletters.feedbin.com", "Subject: Hi", "", "body", ""].compact.join("\n")
      newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

      assert_not newsletter.valid?, "#{description} should not be a usable newsletter"

      %i[from_email from_name name from domain].each do |accessor|
        assert_nothing_raised { newsletter.public_send(accessor) }
      end
    end
  end

  test "a From header with a real address is valid" do
    source = <<~EMAIL
      From: Ben Ubois <ben@benubois.com>
      To: token@newsletters.feedbin.com
      Subject: Hi
      Date: Tue, 18 May 2021 14:16:22 -0700

      body
    EMAIL

    assert EmailNewsletter.new(Mail.from_source(source), "token").valid?
  end

  test "a NUL byte in the body is removed, because Postgres cannot store one" do
    # U+0000 is valid UTF-8, so valid_encoding? is true and scrub leaves it
    # alone. Postgres rejects it anyway: the wire protocol is C strings.
    source = "From: news@example.com\r\n" \
             "To: token@newsletters.feedbin.com\r\n" \
             "Subject: Hi\r\n" \
             "Content-Type: text/plain; charset=UTF-8\r\n\r\n" \
             "before\0after\r\n"

    newsletter = EmailNewsletter.new(Mail.from_source(source), "token")

    assert_equal "beforeafter\n", newsletter.text
    assert_equal "beforeafter\n", newsletter.content
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
