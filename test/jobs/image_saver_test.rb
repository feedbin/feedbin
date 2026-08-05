require "test_helper"

class ImageSaverTest < ActiveSupport::TestCase
  setup do
    @entry = create_entry(Feed.first)
    @entry.update!(content: '<img src="http://example.com/image.jpg">')
  end

  test "swallows a network failure from the image host and finishes the entry" do
    Download.stub(:new, ->(*) { raise HTTP::ConnectionError.new("refused") }) do
      assert_nothing_raised do
        ImageSaver.new.perform(@entry.id)
      end
    end

    assert @entry.reload.archived_images?, "one dead host should not abandon the rest of the entry"
  end

  test "swallows a timeout from the image host" do
    Download.stub(:new, ->(*) { raise HTTP::TimeoutError.new("too slow") }) do
      assert_nothing_raised do
        ImageSaver.new.perform(@entry.id)
      end
    end
  end

  test "swallows an entry deleted between enqueue and perform" do
    id = @entry.id
    @entry.destroy!

    assert_nothing_raised do
      ImageSaver.new.perform(id)
    end
  end
end
