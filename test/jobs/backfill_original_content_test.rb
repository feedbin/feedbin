require "test_helper"

class BackfillOriginalContentTest < ActiveSupport::TestCase
  setup do
    @feed = users(:ben).feeds.first
  end

  test "perform converts the legacy original and clears it" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "perform replaces a temporary original with the legacy value" do
    content = "<p>Old text.</p><p>Newer text.</p><p>Newest text.</p>"
    entry = entry_with_legacy_original(content: content, original_content: "<p>Old text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p><p>Newer text.</p>", base: content))

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "perform does not change updated_at" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    updated_at = entry.updated_at

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_equal updated_at, entry.reload.updated_at
  end

  test "perform clears both columns for a blank original" do
    entry = entry_with_legacy_original(content: "<p>New text.</p>", original_content: "")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_nil entry.reload.compressed_original_content
  end

  test "perform clears both columns for blank current content" do
    entry = entry_with_legacy_original(content: "<p>New text.</p>", original_content: "<p>Old text.</p>")
    entry.update_columns(content: "")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_nil entry.reload.compressed_original_content
  end

  test "perform a second time keeps the converted value" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    job = BackfillOriginalContent.new
    job.perform(batch_for(entry))
    blob = entry.reload.compressed_original_content

    job.perform(batch_for(entry))

    assert_equal blob, entry.reload.compressed_original_content
    assert_equal "<p>Old text.</p>", entry.original_content
  end

  test "convert leaves a row alone when updated_at changed after the read" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    stale = Entry.select(:id, :content, :original, :updated_at).find(entry.id)
    entry.update_columns(updated_at: entry.updated_at + 1.second)

    BackfillOriginalContent.new.convert(stale)

    assert_equal "<p>Old text.</p>", legacy_original(entry)["content"]
    assert_nil entry.reload.compressed_original_content
  end

  test "build queues one job for each range, newest range first" do
    BackfillOriginalContent.jobs.clear
    entry_with_legacy_original(content: "<p>New text.</p>", original_content: "<p>Old text.</p>")
    batches = (Entry.maximum(:id) / BackfillOriginalContent::BATCH_SIZE.to_f).ceil

    BackfillOriginalContent.new.build

    assert_equal batches, BackfillOriginalContent.jobs.size
    assert_equal [batches], BackfillOriginalContent.jobs.first["args"]
    assert_equal [1], BackfillOriginalContent.jobs.last["args"]
  end

  private

  def entry_with_legacy_original(content:, original_content:)
    entry = @feed.entries.create!(public_id: SecureRandom.hex, content: content)
    Entry.where(id: entry.id)
      .update_all(original: {"author" => "Author", "content" => original_content, "title" => "Title"}.to_json)
    entry.reload
  end

  def legacy_original(entry)
    Entry.where(id: entry.id).pick(:original)
  end

  def batch_for(entry)
    (entry.id - 1) / BackfillOriginalContent::BATCH_SIZE + 1
  end
end
