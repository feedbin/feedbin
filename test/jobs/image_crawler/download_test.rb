require "test_helper"
module ImageCrawler
  class DownloadTest < ActiveSupport::TestCase
    def test_should_download_valid_image
      url = "http://example.com/image.jpg"
      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "12345678")
      download = Download.download!(url, minimum_size: 8)
      assert download.valid?
    end

    def test_should_be_too_small
      url = "http://example.com/image.jpg"
      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "1234567")
      download = Download.download!(url, minimum_size: 8)
      refute download.valid?
    end

    def test_should_ignore_size
      url = "http://example.com/image.jpg"
      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: "1")
      download = Download.download!(url, minimum_size: nil)
      assert download.valid?
    end

    def test_should_persist_file
      url = "http://example.com/image.jpg"
      body = "body"
      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: body)
      download = Download.download!(url)
      path = download.path
      download.persist!
      refute path == download.path
      FileUtils.rm download.path
    end

    def test_should_use_camo
      url = "http://example.com/image.jpg"
      stub_request(:get, RemoteFile.camo_url(url)).to_return(headers: {content_type: "image/jpg"}, body: "12345678")
      download = Download.download!(url, camo: true, minimum_size: 8)
      assert download.valid?
    end

    def test_should_send_conditional_headers_when_given
      url = "http://example.com/favicon.ico"
      request = stub_request(:get, url)
        .with(headers: {"If-None-Match" => "\"abc123\"", "If-Modified-Since" => "Wed, 21 Oct 2026 07:28:00 GMT"})
        .to_return(body: File.new(support_file("image.png")), status: 200, headers: {"Content-Type" => "image/png"})

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"", last_modified: "Wed, 21 Oct 2026 07:28:00 GMT")

      assert_requested request
      assert download.valid?
      refute download.not_modified?
      download.delete!
    end

    def test_should_send_no_conditional_headers_when_not_given
      url = "http://example.com/favicon.ico"
      stub_request(:get, url)
        .to_return(body: File.new(support_file("image.png")), status: 200, headers: {"Content-Type" => "image/png"})

      download = Download.download!(url, minimum_size: nil)

      # No `headers:` filter: WebMock's `headers: {}` demands an exactly
      # empty header set, which no real request has. The block proves the
      # absence of the two conditional headers.
      assert_requested :get, url do |request|
        !request.headers.key?("If-None-Match") && !request.headers.key?("If-Modified-Since")
      end
      download.delete!
    end

    # A 304 is the success case for a conditional request, not a failure.
    # Feedkit treats it as success and returns a bodiless response, so it
    # arrives as an ordinary answer rather than as an exception to translate.
    def test_should_treat_304_as_not_modified_rather_than_an_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 304, body: "")

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"")

      assert download.not_modified?
      refute download.valid?, "a 304 carries no bytes, so there is nothing valid to process"
    end

    # Only 304: a 404 or 500 reported as "unchanged" would make a dead icon
    # look permanently current. Exercises #download_file directly because
    # Download::Default's `rescue Down::Error` would swallow the re-raise.
    def test_should_still_raise_for_a_non_304_response_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 404, body: "")

      assert_raises Feedkit::NotFound do
        Download.new(url, minimum_size: nil, etag: "\"abc123\"").download_file(url)
      end
    end

    # An unsolicited 304 (no validator sent) is a broken server, not an
    # unchanged icon; only this layer knows whether a validator went out.
    def test_should_not_treat_an_unsolicited_304_as_not_modified
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 304, body: "")

      download = Download.download!(url, minimum_size: nil)

      refute download.not_modified?, "nobody asked conditionally, so this 304 is a broken server, not a fresh icon"
    end

    # Through the real entry point (whose rescue swallows the raise): a
    # failure must not read as valid or as unchanged.
    def test_should_leave_a_404_invalid_and_not_modified_through_download_bang
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 404, body: "")

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"")

      refute download.valid?
      refute download.not_modified?
    end

    # Candidate urls are attacker-chosen; the crawl must not be aimable at
    # the private network. Asserted at the seam -- webmock intercepts above
    # the socket layer that would refuse the address.
    def test_should_block_private_network_addresses
      captured = nil
      Feedkit::Request.stub(:download, ->(_url, **args) { captured = args; raise Feedkit::Error }) do
        Download.download!("http://example.com/favicon.ico", minimum_size: nil)
      end

      assert captured[:block_ssrf], "image downloads must refuse private-network addresses"
    end

    def test_should_expose_the_response_validators
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(
        body: File.new(support_file("image.png")), status: 200,
        headers: {"Content-Type" => "image/png", "ETag" => "\"xyz789\"", "Last-Modified" => "Wed, 21 Oct 2026 07:28:00 GMT"}
      )

      download = Download.download!(url, minimum_size: nil)

      assert_equal "\"xyz789\"", download.response_etag
      assert_equal "Wed, 21 Oct 2026 07:28:00 GMT", download.response_last_modified
      download.delete!
    end
  end
end