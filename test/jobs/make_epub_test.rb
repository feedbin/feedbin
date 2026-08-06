require "test_helper"

class MakeEpubTest < ActiveSupport::TestCase
  test "Should build epub" do
    entry = create_entry(Feed.first)
    url = "http://example.com/image.jpg"
    entry.content = "<img src='#{url}' />"
    entry.save

    stub_request_file("index.html", url)

    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com")
    end
  end

  # The scratch directory is assigned three statements into build, so anything
  # that fails before it arrives at an ensure with nothing to clean up. A raise
  # from an ensure discards the exception that was propagating, which is how
  # this path reports every early failure as the same TypeError in FileUtils.
  test "a failure before the scratch directory exists is the error that escapes" do
    entry = create_entry(Feed.first)

    Dir.stub(:mktmpdir, ->(*) { raise Errno::ENOSPC }) do
      assert_raises(Errno::ENOSPC) do
        MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com")
      end
    end
  end
end
