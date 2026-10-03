# Moves each legacy original value into compressed_original_content and
# clears the legacy column. One job for each range of ids: production ids are sparse
# (about 2.6% in use), so the range is larger than SidekiqHelper::BATCH_SIZE.
# Entry ignores the original column, so this job selects it by name.
class BackfillOriginalContent
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000

  def perform(batch)
    first = (batch - 1) * BATCH_SIZE + 1
    Entry.where(id: first..(first + BATCH_SIZE - 1)).where.not(original: nil)
      .select(:id, :content, :original, :updated_at)
      .find_each(batch_size: 500) { |entry| convert(entry) }
  end

  # The updated_at condition skips a row the crawler changed after the read.
  # That row keeps its legacy original, and a second build converts it. The
  # legacy value replaces any temporary original EntryUpdate wrote meanwhile.
  # update_all skips callbacks and leaves updated_at as it is.
  def convert(entry)
    compressed = OriginalContent.compress(entry.original&.dig("content"), base: entry.content)
    Entry.where(id: entry.id, updated_at: entry.updated_at)
      .update_all(compressed_original_content: compressed, original: nil)
  end

  # Newest ranges first: recently updated entries are the ones people read.
  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq::Client.push_bulk(
      "args" => batches.downto(1).map { [it] },
      "class" => self.class
    )
  end
end
