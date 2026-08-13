# The other half of image garbage collection. ImageGarbageCollector starts
# from rows that are going away (an entry was deleted); this starts from a
# stored object a row has already stopped pointing at, because its source
# served new bytes. Both share sweep's locked survivor check and batched R2
# delete, but not the legacy-S3 half: ImageGarbageCollector#perform also
# harvests data["legacy_storage_url"] and enqueues ImageDeleter, while this
# discards sweep's return value and does neither. That was safe only while
# content-addressed presets were never legacy_store? -- podcast and
# podcast_feed are now both, so this path can leave a legacy S3 object
# behind. The exposure is narrow: the legacy key is id-derived, and a
# bytes-only change at a stable URL overwrites that same key in place --
# only a show's itunes_image moving to a genuinely different URL (its id
# folds in a hash of the URL; see ItunesFeedImage#schedule) orphans one.
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
