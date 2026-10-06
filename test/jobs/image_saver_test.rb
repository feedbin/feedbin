require "test_helper"

class ImageSaverTest < ActiveSupport::TestCase
  setup do
    @entry = create_entry(Feed.first)
    @entry.update!(content: '<img src="http://example.com/image.jpg">')
  end

  test "swallows a network failure or timeout from the image host and finishes the entry" do
    [HTTP::ConnectionError.new("refused"), HTTP::TimeoutError.new("too slow")].each do |error|
      @entry.update!(archived_images: false)

      Download.stub(:new, ->(*) { raise error }) do
        assert_nothing_raised do
          ImageSaver.new.perform(@entry.id)
        end
      end

      assert @entry.reload.archived_images?, "#{error.class}: one dead host should not abandon the rest of the entry"
    end
  end

  test "skips images without a src" do
    @entry.update!(content: "<img>")

    ImageSaver.new.perform(@entry.id)

    assert @entry.reload.archived_images?
  end

  test "continues after a private address is refused" do
    Download.stub(:new, ->(*) { raise Feedkit::PrivateNetworkAddress }) do
      ImageSaver.new.perform(@entry.id)
    end

    assert @entry.reload.archived_images?
  end

  test "swallows an entry deleted between enqueue and perform" do
    id = @entry.id
    @entry.destroy!

    assert_nothing_raised do
      ImageSaver.new.perform(id)
    end
  end
end
