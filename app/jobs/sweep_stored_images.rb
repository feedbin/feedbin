# Deletes stored objects no images row references any more. The 15-minute
# delay is what replaces a lock: any crawl about to reference one of these
# paths has long since written its row.
class SweepStoredImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths)
    paths = [*storage_paths].compact.uniq
    return if paths.empty?

    # Every provider counts: an icon row and an entry row can share one
    # stored object.
    surviving = Image.where(storage_path: paths).distinct.pluck(:storage_path)

    delete_objects(paths - surviving)
  end

  def delete_objects(paths)
    return if paths.empty?
    return unless Image.storage_configured?

    client = Image.storage_client
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(Image.bucket, slice, {quiet: true})
    end
    Librato.increment("image.gc_objects", by: paths.size)
  end
end
