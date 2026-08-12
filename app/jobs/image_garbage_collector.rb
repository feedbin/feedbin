# Removes images-table usage rows for deleted entries and deletes the shared
# R2 object once nothing references it. The advisory lock serializes the
# zero-reference check against Dedupe/create_image attaching a new reference
# to the same object.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    rows = Image.entry_images.where(provider_id: entry_ids).to_a
    return if rows.empty?

    rows.group_by(&:url_fingerprint).each do |fingerprint, group|
      Image.with_url_lock(fingerprint) do
        Image.where(id: group.map(&:id)).delete_all
        unless Image.entry_images.where(url_fingerprint: fingerprint).exists?
          delete_object(group.first.storage_path)
        end
      end
    end

    Librato.increment("image.gc_rows", by: rows.size)
  end

  def delete_object(path)
    return if ENV["R2_BUCKET_IMAGES"].blank?
    Fog::Storage.new(STORAGE_R2).delete_object(ENV["R2_BUCKET_IMAGES"], path)
    Librato.increment("image.gc_objects")
  rescue Excon::Error::NotFound
  end
end
