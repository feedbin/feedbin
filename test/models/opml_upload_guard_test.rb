require "test_helper"

# There is no JS test runner in this project, so the client guard is asserted
# against its own source. The point is that the two ends agree about what a
# valid OPML file is -- the server accepts a document with no XML declaration,
# and the onboarding drop zone refused to send one.
class OpmlUploadGuardTest < ActiveSupport::TestCase
  UPLOAD_CONTROLLER = Rails.root.join("app/javascript/controllers/upload_controller.js")

  PROLOGLESS_OPML = <<~XML
    <opml version="1.0">
      <head><title>Subscriptions</title></head>
      <body>
        <outline text="Example" title="Example" type="rss" xmlUrl="http://example.com/atom.xml"/>
      </body>
    </opml>
  XML

  test "the server parses OPML that omits the XML declaration" do
    assert Opml::Parser.parse(PROLOGLESS_OPML).any?
  end

  test "the client does not require an XML declaration" do
    source = File.read(UPLOAD_CONTROLLER)

    refute_match(/startsWith\(["']<\?xml/, source,
      "the drop zone rejects valid OPML that has no prolog")
  end
end
