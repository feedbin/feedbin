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

    rows = Image.entry_owned.where(provider_id: entry_ids)
      .pluck(:id, :storage_path, Arel.sql("data->>'legacy_storage_url'"))
    return if rows.empty?

    Image.where(id: rows.map { _1[0] }).delete_all

    SweepStoredImages.perform_in(SWEEP_DELAY, rows.map { _1[1] }.uniq, rows.filter_map { _1[2] }.uniq)
    Librato.increment("image.gc_rows", by: rows.size)
  end
end
