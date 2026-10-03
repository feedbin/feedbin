require "test_helper"

module FeedCrawler
  class EntryUpdateTest < ActiveSupport::TestCase
    setup do
      @feed = users(:ben).subscriptions.first.feed
      @old_content = "<p>#{"Original sentence. " * 5}</p>"
      @entry = @feed.entries.create!(url: "url", public_id: SecureRandom.hex, content: @old_content, published: Time.now)
    end

    test "first significant change stores the old content as the original" do
      new_content = significant(@old_content)

      EntryUpdate.create!(update_data(new_content), @entry)

      entry = @entry.reload
      assert_equal new_content, entry.content
      assert_equal @old_content, entry.original_content
    end

    test "second significant change keeps the first original" do
      second = significant(@old_content)
      EntryUpdate.create!(update_data(second), @entry)

      EntryUpdate.create!(update_data(significant(second)), @entry.reload)

      assert_equal @old_content, @entry.reload.original_content
    end

    test "small change keeps the original" do
      second = significant(@old_content)
      EntryUpdate.create!(update_data(second), @entry)
      third = second.sub("Original", "Changed")

      EntryUpdate.create!(update_data(third), @entry.reload)

      entry = @entry.reload
      assert_equal third, entry.content
      assert_equal @old_content, entry.original_content
    end

    test "small change on an entry without an original stores nothing" do
      EntryUpdate.create!(update_data(@old_content.sub("Original", "Changed")), @entry)

      assert_nil @entry.reload.compressed_original_content
    end

    test "significant change on an old entry stores nothing" do
      @entry.update_columns(published: 8.days.ago)

      EntryUpdate.create!(update_data(significant(@old_content)), @entry.reload)

      assert_nil @entry.reload.compressed_original_content
    end

    test "significant change on an unconverted entry writes a temporary original" do
      Entry.where(id: @entry.id).update_all(original: {"content" => "<p>Legacy original.</p>"}.to_json)

      EntryUpdate.create!(update_data(significant(@old_content)), @entry.reload)

      assert_equal @old_content, @entry.reload.original_content
      assert_equal({"content" => "<p>Legacy original.</p>"}, Entry.where(id: @entry.id).pick(:original))
    end

    private

    def update_data(content)
      {
        "author" => @entry.author,
        "content" => content,
        "title" => @entry.title,
        "url" => @entry.url,
        "entry_id" => @entry.entry_id,
        "data" => @entry.data
      }
    end

    # significant_change? needs more than 50 more characters of text.
    def significant(content)
      content + "<p>#{"An added paragraph with many more words. " * 3}</p>"
    end
  end
end
