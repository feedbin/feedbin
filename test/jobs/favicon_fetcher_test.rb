require "test_helper"

class FaviconFetcherTest < ActiveSupport::TestCase
  setup do
    @page_url = URI.parse("http://example.com")
    @icon_url = @page_url.dup
    @icon_url.path = "/icons/favicon.ico"
    @default_url = @page_url.dup
    @default_url.path = "/favicon.ico"
  end

  test "should get favicon from icon link" do
    body = <<-eot
    <html>
        <head>
            <link rel="icon" href="#{@icon_url.path}">
        </head>
    </html>
    eot

    stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
    stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

    stub_request(:get, @page_url).
      to_return(body: body, status: 200)

    stub_request_file("favicon.ico", @icon_url)

    FaviconFetcher.new.perform(@page_url.host)

    assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
  end

  test "should get favicon from shortcut icon link" do
    body = <<-eot
    <html>
        <head>
            <link rel="shortcut icon" href="#{@icon_url}">
        </head>
    </html>
    eot

    stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
    stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

    stub_request(:get, @page_url).
      to_return(body: body, status: 200)

    stub_request_file("favicon.ico", @icon_url)

    FaviconFetcher.new.perform(@page_url.host)

    assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
  end

  test "should get favicon from default location" do
    body = <<-eot
    <html>
        <head>
        </head>
    </html>
    eot

    stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
    stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

    stub_request(:get, @page_url).
      to_return(body: body, status: 200)

    stub_request_file("favicon.ico", @default_url)

    FaviconFetcher.new.perform(@page_url.host)

    assert_not_nil Favicon.unscoped.where(host: @page_url.host).take!.favicon
  end

  test "should skip blank favicon" do
    body = <<-eot
    <html>
        <head>
        </head>
    </html>
    eot

    stub_request(:any, "https://s3.amazonaws.com/public-favicons/c7a9/c7a91374735634df325fbcfda3f4119278d36fc2.png")
    stub_request(:any, "https://s3.amazonaws.com/c7a/c7a91374735634df325fbcfda3f4119278d36fc2.png")

    stub_request(:get, @page_url).
      to_return(body: body, status: 200)

    stub_request_file("favicon-blank.ico", @default_url)

    FaviconFetcher.new.perform(@page_url.host)

    assert_nil Favicon.unscoped.where(host: @page_url.host).take
  end
end
