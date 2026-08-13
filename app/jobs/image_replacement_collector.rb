# The other half of image garbage collection. ImageGarbageCollector starts
# from rows that are going away (an entry was deleted); this starts from a
# stored object a row has already stopped pointing at, because its source
# served new bytes. Both end in the same locked survivor check and the same
# batched delete -- only the starting set differs.
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
