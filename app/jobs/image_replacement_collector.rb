# The other half of image garbage collection. ImageGarbageCollector starts
# from rows that are going away (an entry was deleted); this starts from a
# stored object a row has already stopped pointing at, because its source
# served new bytes. Both share sweep's locked survivor check and batched R2
# delete, but not the legacy-S3 half: ImageGarbageCollector#perform also
# harvests data["legacy_storage_url"] and enqueues ImageDeleter, while this
# discards sweep's return value and does neither. That's correct only
# because content-addressed presets -- the only callers of this path -- are
# never legacy_store?, so there is no legacy object to leak.
#
# Unreachable for entry previews (entries never re-crawl), routine for every
# icon tenant: /favicon.ico serving new bytes is the whole problem the icon
# family exists to solve.
class ImageReplacementCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths)
    ImageGarbageCollector.new.sweep([*storage_paths])
  end
end
