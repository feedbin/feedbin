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

  # The whole point of the rescue on select_content is to carry on with the
  # stored entry when the extract service is unavailable.
  test "falls back to the stored entry when extraction fails" do
    entry = create_entry(Feed.first)

    MercuryParser.stub(:parse, ->(*) { raise "extract service is down" }) do
      assert_difference "ActionMailer::Base.deliveries.count", +1 do
        MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com", true)
      end
    end
  end

  test "an image over the size budget is left out of the epub" do
    entry = create_entry(Feed.first)
    url = "http://example.com/huge.jpg"
    entry.update!(content: "<img src='#{url}' />")

    stub_request(:get, url).to_return(
      body: SecureRandom.bytes(10.megabytes),
      headers: {"Content-Type" => "image/jpeg"}
    )

    epub = capture_epub do
      MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com")
    end

    images = epub.select { _1.start_with?("OEBPS/images/") && !_1.end_with?("/") }
    assert_empty images, "an image over the budget must not be zipped into the epub"
  end

  test "images after an oversized one are still bundled" do
    entry = create_entry(Feed.first)
    huge = "http://example.com/huge.jpg"
    small = "http://example.com/small.jpg"
    entry.update!(content: "<img src='#{huge}' /><img src='#{small}' />")

    stub_request(:get, huge).to_return(
      body: SecureRandom.bytes(10.megabytes),
      headers: {"Content-Type" => "image/jpeg"}
    )
    stub_request(:get, small).to_return(
      body: SecureRandom.bytes(1024),
      headers: {"Content-Type" => "image/jpeg"}
    )

    epub = capture_epub do
      MakeEpub.new.perform(entry.id, users(:ben).id, "example@example.com")
    end

    images = epub.select { _1.start_with?("OEBPS/images/") && !_1.end_with?("/") }
    assert_equal 1, images.count, "the image under the budget must still be bundled"
  end

  # UserMailer.kindle is the last thing build does before ensure deletes the
  # file, so the archive has to be read from there.
  def capture_epub
    names = nil
    UserMailer.stub(:kindle, ->(_address, _title, path) {
      Zip::File.open(path) { |zip| names = zip.map(&:name) }
      OpenStruct.new(deliver_now: true)
    }) do
      yield
    end
    names
  end
end
