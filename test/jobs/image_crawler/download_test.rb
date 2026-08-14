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

      # No `headers:` filter here (deviation from the plan's literal test code):
      # WebMock's `headers: {}` demands an exact match against an empty header set,
      # which no real request ever has (Connection/Host/User-Agent are always present).
      # Confirmed by direct experiment -- with that filter this assertion can never
      # pass, regardless of what conditional_headers actually sends. The block alone
      # already proves the absence of the two conditional headers.
      assert_requested :get, url do |request|
        !request.headers.key?("If-None-Match") && !request.headers.key?("If-Modified-Since")
      end
      download.delete!
    end

    # A 304 is the success case for a conditional request, not a failure. Down
    # raises on every non-2xx, so it arrives as an exception and has to be
    # translated back into an ordinary answer.
    def test_should_treat_304_as_not_modified_rather_than_an_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 304, body: "")

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"")

      assert download.not_modified?
      refute download.valid?, "a 304 carries no bytes, so there is nothing valid to process"
    end

    # Only 304. A 404 or a 500 is still a real failure and must not be
    # silently reported as "unchanged", which would make a dead icon look
    # permanently current.
    #
    # Exercises #download_file directly (deviation from the plan's literal test
    # code, which called Download.download!). That entry point resolves this URL
    # to Download::Default, whose #download has its own long-standing, unrelated
    # `rescue Down::Error` -- pre-dating this task and shared with Youtube/Instagram/
    # Vimeo -- which would swallow the very re-raise this test means to observe.
    # Task 3's attempt_icon wraps Download.download! in its own rescue too, so
    # nothing downstream depends on the exception surviving past Default; the
    # property this task owns is narrower and lives entirely in #download_file:
    # a confirmed 304 sets not_modified? and nothing else may.
    def test_should_still_raise_for_a_non_304_response_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 404, body: "")

      assert_raises Down::ResponseError do
        Download.new(url, minimum_size: nil, etag: "\"abc123\"").download_file(url)
      end
    end

    # The gate that gives not_modified? its meaning: without it, an
    # unsolicited 304 from a non-conformant server (one that answers 304 even
    # though no If-None-Match/If-Modified-Since went out) would be swallowed
    # as "unchanged" the same way a real conditional 304 is. That is
    # indistinguishable from a fresh icon at every other layer, so the gate
    # has to live here, at the one place that knows whether a validator was
    # actually sent.
    def test_should_not_treat_an_unsolicited_304_as_not_modified
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 304, body: "")

      download = Download.download!(url, minimum_size: nil)

      refute download.not_modified?, "nobody asked conditionally, so this 304 is a broken server, not a fresh icon"
    end

    # Down::Default's own `rescue Down::Error` swallows whatever #download_file
    # raises, so the sibling of test_should_still_raise_for_a_non_304_response_error
    # above can only observe the outcome here, through the same entry point
    # attempt_icon actually calls -- a real failure must never be reported as
    # valid or as an unchanged (not_modified) icon.
    def test_should_leave_a_404_invalid_and_not_modified_through_download_bang
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 404, body: "")

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"")

      refute download.valid?
      refute download.not_modified?
    end

    # The :net_http backend raises Down::NotModified for a 304, not
    # Down::ResponseError -- a sibling under Down::Error, not a subtype (see
    # download.rb's comment on download_file). This app configures :http
    # (config/initializers/down.rb), which webmock can only make raise
    # Down::ResponseError, so Down::NotModified is stubbed directly to prove
    # the rescue branch itself still behaves correctly if the backend ever
    # changes, rather than relying on today's backend choice to make it
    # unreachable.
    def test_should_treat_a_down_not_modified_error_as_not_modified_too
      url = "http://example.com/favicon.ico"
      download = Download.new(url, minimum_size: nil, etag: "\"abc123\"")

      Down.stub(:download, ->(*) { raise Down::NotModified, "not modified" }) do
        download.download_file(url)
      end

      assert download.not_modified?
    end

    # Same gate as the ResponseError branch: an unsolicited Down::NotModified
    # (no validator was actually sent) must still raise, not be swallowed.
    def test_should_still_raise_a_down_not_modified_error_when_not_conditional
      url = "http://example.com/favicon.ico"
      download = Download.new(url, minimum_size: nil)

      Down.stub(:download, ->(*) { raise Down::NotModified, "not modified" }) do
        assert_raises Down::NotModified do
          download.download_file(url)
        end
      end
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