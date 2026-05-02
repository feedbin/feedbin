require "test_helper"

class NewsletterTest < ActiveSupport::TestCase
  def base_params(overrides = {})
    {
      "X-Mailgun-Incoming" => "Yes",
      "recipient" => "subscribe+abc123@newsletters.feedbin.com",
      "from" => "Author <author@example.com>",
      "subject" => "Hello!",
      "body-plain" => "Plain text body",
      "body-html" => "<p>HTML body</p>",
      "timestamp" => "1700000000",
      "token" => "tok",
      "signature" => "ignored",
      "List-Unsubscribe" => "<https://example.com/u/1>"
    }.merge(overrides)
  end

  setup do
    @newsletter = Newsletter.new(base_params)
  end

  test "to_email returns the recipient field" do
    assert_equal "subscribe+abc123@newsletters.feedbin.com", @newsletter.to_email
  end

  test "full_token strips the recipient suffixes and the subscribe prefix" do
    assert_equal "abc123", @newsletter.full_token
  end

  test "full_token strips test-subscribe and the development host" do
    nl = Newsletter.new(base_params("recipient" => "test-subscribe+xyz@development.newsletters.feedbin.com"))
    assert_equal "xyz", nl.full_token
  end

  test "token returns the part of full_token before the +" do
    nl = Newsletter.new(base_params("recipient" => "subscribe+abc+meta@newsletters.feedbin.com"))
    assert_equal "abc", nl.token
  end

  test "from_email and from_name come from a parsed Mail::Address" do
    assert_equal "author@example.com", @newsletter.from_email
    assert_equal "Author", @newsletter.from_name
    assert_equal "Author", @newsletter.name
  end

  test "from_name falls back to from_email when no display name is present" do
    nl = Newsletter.new(base_params("from" => "noname@example.com"))
    assert_equal "noname@example.com", nl.from_email
    assert_equal "noname@example.com", nl.from_name
    assert_nil nl.name
  end

  test "parsed_from rescues Mail::Field::ParseError and returns an OpenStruct" do
    raw = "Bad Name <author@example.com>"
    Mail::Address.stub :new, ->(_) { raise Mail::Field::ParseError.new(Mail::Field, raw, "bad") } do
      nl = Newsletter.new(base_params("from" => raw))
      assert_equal "author@example.com", nl.from_email
      assert_equal "Bad Name", nl.from_name
      assert_equal "example.com", nl.domain
    end
  end

  test "subject text html content timestamp expose underlying data" do
    assert_equal "Hello!", @newsletter.subject
    assert_equal "Plain text body", @newsletter.text
    assert_equal "<p>HTML body</p>", @newsletter.html
    assert_equal "<p>HTML body</p>", @newsletter.content
    assert_equal "1700000000", @newsletter.timestamp
  end

  test "content falls back to text when html is missing" do
    nl = Newsletter.new(base_params("body-html" => nil))
    assert_equal "Plain text body", nl.content
  end

  test "domain comes from the parsed sender address" do
    assert_equal "example.com", @newsletter.domain
  end

  test "feed_id is the SHA1 of full_token+from_email" do
    expected = Digest::SHA1.hexdigest("abc123author@example.com")
    assert_equal expected, @newsletter.feed_id
  end

  test "entry_id is the SHA1 of feed_id+subject+timestamp" do
    expected = Digest::SHA1.hexdigest("#{@newsletter.feed_id}Hello!1700000000")
    assert_equal expected, @newsletter.entry_id
  end

  test "site_url builds an http URL from the sender domain" do
    assert_equal "http://example.com", @newsletter.site_url
  end

  test "feed_url appends the feed_id as a query string" do
    assert_equal "http://example.com?#{@newsletter.feed_id}", @newsletter.feed_url
  end

  test "format is html when html body is present" do
    assert_equal "html", @newsletter.format
  end

  test "format is text when html body is missing" do
    nl = Newsletter.new(base_params("body-html" => nil))
    assert_equal "text", nl.format
  end

  test "headers exposes List-Unsubscribe" do
    assert_equal({"List-Unsubscribe" => "<https://example.com/u/1>"}, @newsletter.headers)
  end

  test "valid? requires the mailgun header and a matching signature" do
    ENV.stub :[], ->(k) { k == "MAILGUN_INBOUND_KEY" ? "key" : nil } do
      digest = OpenSSL::Digest::SHA256.new
      signature = OpenSSL::HMAC.hexdigest(digest, "key", "1700000000tok")
      nl = Newsletter.new(base_params("signature" => signature))
      assert nl.valid?
    end
  end

  test "valid? is false when X-Mailgun-Incoming header is missing" do
    nl = Newsletter.new(base_params("X-Mailgun-Incoming" => nil))
    refute nl.valid?
  end

  test "valid? is false when the signature does not match" do
    ENV.stub :[], ->(k) { k == "MAILGUN_INBOUND_KEY" ? "key" : nil } do
      nl = Newsletter.new(base_params("signature" => "wrong"))
      refute nl.valid?
    end
  end
end
