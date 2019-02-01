require "test_helper"

class ImportWorkerTest < ActiveSupport::TestCase
  test "should build import" do
    user = users(:new)

    import = Import.create!(user: user).tap do |record|
      def record.upload
        xml = <<-eot
          <?xml version="1.0" encoding="UTF-8"?>
          <opml version="1.0">
            <body>
              <outline text="Hypercritical" title="Hypercritical" type="rss" xmlUrl="http://hypercritical.co/feeds/main" htmlUrl="http://hypercritical.co/"/>
            </body>
          </opml>
        eot
        OpenStruct.new(
          file: OpenStruct.new(extension: "xml"),
          read: xml,
        )
      end
    end
    assert_difference "ImportItem.count", +1 do
      Import.stub :find, import do
        ImportWorker.new.perform(1)
      end
    end
  end
end
