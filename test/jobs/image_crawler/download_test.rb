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
  end
end