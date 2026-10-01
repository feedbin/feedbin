require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "discovered feed URLs are checked for private addresses" do
    url = "https://example.com/discovered-feed.xml"
    stub_request_file("atom.xml", url)
    response = Feedkit::Request.download(url)
    options = nil
    download = ->(_url, **args) do
      options = args
      response
    end

    Feedkit::Request.stub(:download, download) do
      Source.new(nil).create_from_url!(url)
    end

    assert_equal true, options[:block_ssrf]
  end
end
