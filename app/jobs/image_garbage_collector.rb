# Removes images-table usage rows for deleted entries and hands the objects
# they referenced to the sweep. Object deletion is deferred rather than
# serialised against attachment: see
# docs/superpowers/plans/2026-08-15-image-pipeline-simplification.md.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  SWEEP_DELAY = 15.minutes

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    # pluck rather than instantiating: the rows are about to be deleted, and
    # only these three values are needed. transpose turns the row tuples into
    # one named array per column.
    rows = Image.entry_owned.where(provider_id: entry_ids)
      .pluck(:id, :storage_path, Image.data_projection(:legacy_storage_url))
    return if rows.empty?

    ids, storage_paths, legacy_urls = rows.transpose

    Image.where(id: ids).delete_all

    SweepStoredImages.perform_in(SWEEP_DELAY, storage_paths.uniq, legacy_urls.compact.uniq)
    Librato.increment("image.gc_rows", by: ids.size)
  end
end
