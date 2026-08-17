# Deletes stored objects that no images row references any more, both the R2
# object at storage_path and the legacy S3 object the rows carried. Runs a
# quarter of an hour after the rows went away, which is what lets it work
# without a lock: the whole Find -> Process -> Upload chain is a couple of
# minutes at worst, so a crawl that is about to reference one of these paths
# has long since written its row.
#
# legacy_urls has to be passed in rather than re-derived: the rows that
# carried them are already gone by the time this runs.
class SweepStoredImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths, legacy_urls = [])
    paths = [*storage_paths].compact.uniq
    return if paths.empty?

    # Every provider counts, not just the entry ones: a stored object can be
    # referenced by an icon row and an entry row at once, and deleting it out
    # from under either is the same bug.
    surviving = Image.where(storage_path: paths)
      .pluck(:storage_path, Arel.sql("data->>'legacy_storage_url'"))

    delete_r2_objects(paths - surviving.map(&:first).uniq)

    # Exact under both keying schemes. Entry previews share one legacy object
    # per storage_path -- Dedupe.attach (dedupe.rb) copies legacy_storage_url
    # verbatim onto every row it dedupes onto -- so a surviving row's value is
    # the same one the deleted rows carried, and subtracting it leaves the
    # still-referenced object alone. Content-addressed rows (the podcast
    # family) never go through Dedupe, so each carries its own per-row legacy
    # key even though the path is shared with a surviving show or sibling
    # episode; that key is not one any survivor references, so it is never
    # subtracted and is always queued for deletion.
    stale = [*legacy_urls].compact.uniq - surviving.filter_map(&:last)
    ImageDeleter.perform_async(stale) if stale.present?
  end

  def delete_r2_objects(paths)
    return if paths.empty?
    return unless Image.r2_enabled?

    client = Image.r2_client
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(Image.r2_bucket, slice, {quiet: true})
    end
    Librato.increment("image.gc_objects", by: paths.size)
  end
end
