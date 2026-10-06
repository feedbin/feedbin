require "test_helper"

class NewsletterPageTest < ActiveSupport::TestCase
  setup do
    @entry = create_entry(Feed.first)
    @page = NewsletterPage.new(@entry)
  end

  test "key uses the public id prefix" do
    assert_equal "#{@entry.public_id[0..2]}/#{@entry.public_id}.html", @page.key
  end

  test "url has the host and no bucket name" do
    with_env("NEWSLETTER_HOST" => "newsletters.example.com") do
      assert_equal "https://newsletters.example.com/#{@page.key}", @page.url
      assert_equal @entry.newsletter_url, @page.url
    end
  end

  test "url is nil without a host" do
    with_env("NEWSLETTER_HOST" => nil) do
      assert_nil @page.url
    end
  end

  test "body is the gzipped document" do
    document = ActiveSupport::Gzip.decompress(@page.body)
    assert_includes document, "<title>#{@entry.title}</title>"
    assert_includes document, @entry.content
  end

  test "headers tell the browser the body is gzip" do
    assert_equal "gzip", @page.headers["Content-Encoding"]
    assert_equal "text/html; charset=utf-8", @page.headers["Content-Type"]
    assert_equal "max-age=315360000, public", @page.headers["Cache-Control"]
    assert_empty @page.headers.keys.grep(/\Ax-amz/i)
  end

  test "text email gets a heading and style" do
    @entry.update(data: {format: "text"})
    document = ActiveSupport::Gzip.decompress(NewsletterPage.new(@entry).body)
    assert_includes document, "<h1>#{@entry.title}</h1>"
    assert_includes document, "<style>"
  end

  test "document nested past the HTML5 tree depth limit" do
    nested = ("<div>" * 450) + "newsletter body" + ("</div>" * 450)
    @entry.update_columns(content: nested)
    assert_includes ActiveSupport::Gzip.decompress(NewsletterPage.new(@entry).body), "newsletter body"
  end

  test "document for an email with no Subject" do
    @entry.update_columns(title: nil, content: "<html><body><p>hi</p></body></html>")
    assert_includes ActiveSupport::Gzip.decompress(NewsletterPage.new(@entry).body), "<title>"
  end

  test "save puts the object on B2" do
    request = stub_request(:put, "https://test-account.storage.example.com/newsletters-test/#{@page.key}")
      .with(headers: {"Content-Encoding" => "gzip", "Content-Type" => "text/html; charset=utf-8"})
      .with { |req| ActiveSupport::Gzip.decompress(req.body).include?(@entry.content) }

    @page.save
    assert_requested request
  end
end
