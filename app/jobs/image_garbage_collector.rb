# Removes images-table usage rows for deleted entries and deletes stored
# objects once nothing references them. Designed for feed-sized batches:
# one lock acquisition, one row delete, one survivor query, and one batched
# DeleteObjects call per run — not one request per image.
#
# The advisory locks, keyed on storage_path, serialize the zero-reference
# check against Dedupe/create_image attaching a new reference to the same
# object. The R2 delete happens inside the locks because its keys are shared
# and deterministic (a resurrecting upload would recreate the same key); the
# legacy S3 delete happens outside because fresh uploads write new per-entry
# keys, so there is nothing to collide with.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    rows = Image.entry_owned.where(provider_id: entry_ids).to_a
    return if rows.empty?

    grouped = rows.group_by(&:storage_path)
    surviving_legacy = []

    Image.with_storage_locks(grouped.keys) do
      Image.where(id: rows.map(&:id)).delete_all
      surviving_legacy = Image.where(storage_path: grouped.keys).filter_map { _1.data["legacy_storage_url"] }
      orphaned = orphaned_paths(grouped.keys)
      delete_r2_objects(orphaned)
    end

    # Exact under both keying schemes. Entry previews share one legacy object
    # per storage_path -- Dedupe.attach (dedupe.rb) copies legacy_storage_url
    # verbatim onto every row it dedupes onto -- so a surviving row's value is
    # the same one the deleted rows carried, and subtracting it leaves the
    # still-referenced object alone. Content-addressed rows (the podcast
    # family) never go through Dedupe, so each carries its own per-row legacy
    # key even though the path is shared with a surviving show or sibling
    # episode; that key is not one any survivor references, so it is never
    # subtracted and is always queued for deletion.
    legacy_urls = rows.filter_map { _1.data["legacy_storage_url"] }.uniq - surviving_legacy
    ImageDeleter.perform_async(legacy_urls) if legacy_urls.present?

    Librato.increment("image.gc_rows", by: rows.size)
  end

  # The locked half of collection, on its own so the replacement path can use
  # it without having rows to delete first.
  def sweep(paths)
    paths = Array(paths).compact.uniq
    return [] if paths.empty?

    orphaned = []
    Image.with_storage_locks(paths) do
      orphaned = orphaned_paths(paths)
      delete_r2_objects(orphaned)
    end
    orphaned
  end

  # Every provider counts, not just the entry ones: a stored object can be
  # referenced by an icon row and an entry row at once, and deleting it out
  # from under either is the same bug.
  def orphaned_paths(paths)
    paths - Image.where(storage_path: paths).distinct.pluck(:storage_path)
  end

  def delete_r2_objects(paths)
    return if paths.empty?
    return if ENV["R2_BUCKET_IMAGES"].blank?

    client = Fog::Storage.new(STORAGE_R2)
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(ENV["R2_BUCKET_IMAGES"], slice, {quiet: true})
    end
    Librato.increment("image.gc_objects", by: paths.size)
  end
end
