# Removes images-table usage rows for deleted entries and hands the objects
# they referenced to the deferred sweep.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  SWEEP_DELAY = 15.minutes

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    # pluck: the rows are about to be deleted and only three values are
    # needed. transpose gives one array per column.
    rows = Image.entry_owned.where(provider_id: entry_ids)
      .pluck(:id, :storage_path, Image.data_projection(:legacy_storage_url))
    return if rows.empty?

    ids, storage_paths, legacy_urls = rows.transpose

    Image.where(id: ids).delete_all

    SweepStoredImages.perform_in(SWEEP_DELAY, storage_paths.uniq, legacy_urls.compact.uniq)
    Librato.increment("image.gc_rows", by: ids.size)
  end
end
