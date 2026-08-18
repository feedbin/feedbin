# Deletes stored objects no images row references any more -- unified and
# legacy both. The 15-minute delay is what replaces a lock: any crawl about
# to reference one of these paths has long since written its row.
# legacy_urls is passed in because the rows that carried them are gone.
class SweepStoredImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths, legacy_urls = [])
    paths = [*storage_paths].compact.uniq
    return if paths.empty?

    # Every provider counts: an icon row and an entry row can share one
    # stored object.
    surviving = Image.where(storage_path: paths)
      .pluck(:storage_path, Image.data_projection(:legacy_storage_url))

    delete_unified_objects(paths - surviving.map(&:first).uniq)

    # Exact under both keying schemes: deduped rows share one legacy url per
    # storage_path, so a survivor's value subtracts the deleted rows'.
    # Content-addressed rows carry per-row legacy keys no survivor
    # references, so theirs are always queued.
    stale = [*legacy_urls].compact.uniq - surviving.filter_map(&:last)
    ImageDeleter.perform_async(stale) if stale.present?
  end

  def delete_unified_objects(paths)
    return if paths.empty?
    return unless Image.unified_enabled?

    client = Image.unified_client
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(Image.unified_bucket, slice, {quiet: true})
    end
    Librato.increment("image.gc_objects", by: paths.size)
  end
end
