require "test_helper"

class XmlTest < ActiveSupport::TestCase
  test "should create feed" do
    url = "https://example.com/atom.xml"
    stub_request_file("atom.xml", url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::Xml.find(response)
    end
  end
end
