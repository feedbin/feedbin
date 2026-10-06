require "test_helper"

class NewsletterPageTest < ActiveSupport::TestCase
  setup do
    @entry = create_entry(Feed.first)
    @page = NewsletterPage.new(@entry)
  end

  test "key is the first three characters of the public id, then the id" do
    @entry.update_columns(public_id: "abcdef0123")
    assert_equal "abc/abcdef0123.html", NewsletterPage.new(@entry).key
  end

  test "url is the host and the key, without a bucket name" do
    @entry.update_columns(public_id: "abcdef0123")
    with_env("NEWSLETTER_HOST" => "newsletters.example.com") do
      assert_equal "https://newsletters.example.com/abc/abcdef0123.html", NewsletterPage.new(@entry).url
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

  test "save refuses a blank bucket" do
    with_env("NEWSLETTERS_BUCKET" => "") do
      error = assert_raises(RuntimeError) { @page.save }
      assert_equal "NEWSLETTERS_BUCKET is not set", error.message
    end
  end

  test "save puts the object on B2" do
    request = stub_request(:put, "https://test-account.storage.example.com/newsletters-test/#{@page.key}")
      .with(headers: {
        "Content-Encoding" => "gzip",
        "Content-Type" => "text/html; charset=utf-8",
        "Cache-Control" => "max-age=315360000, public"
      })
      .with { |req| ActiveSupport::Gzip.decompress(req.body).include?(@entry.content) }

    @page.save
    assert_requested request
  end
end
