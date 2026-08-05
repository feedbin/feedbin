require "test_helper"

class DownloadTest < ActiveSupport::TestCase
  # `src` reaches here verbatim out of entry content, filtered only by
  # start_with?("http"), so it is whatever a CMS published.
  test "builds a path for src values RFC 3986 rejects but browsers accept" do
    {
      "http://example.com/a b.png" => ".png",
      "http:logo.png" => ".png",
      "http://example.com/x.png?cache=1" => ".png",
      "http://example.com/no-extension" => ""
    }.each do |url, extension|
      path = Download.new(url).path

      assert path.end_with?(extension), "#{url} should keep its #{extension.presence || "empty"} extension"
    end
  end
end
