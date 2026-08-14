class CacheEntryViews
  include Sidekiq::Worker
  include SidekiqHelper

  SET_NAME = "#{name}-ids"

  def perform(entry_id, process = false)
    if process
      cache_views
    else
      add_to_queue(SET_NAME, entry_id)
    end
  end

  def cache_views
    entry_ids = dequeue_ids(SET_NAME)
    entries = Entry.where(id: entry_ids).includes(feed: [:favicon, :icon_image_record, :channel_image_record]).preload(:preview_image_record).to_a
    favicons = Favicon.for_entries(entries)

    # The same lambda and the same locals the entry list renders with. A bare
    # `cached: true` here would warm a key nothing ever looks up.
    ApplicationController.render({
      partial: "entries/entry",
      collection: entries,
      format: :html,
      locals: {favicons: favicons},
      cached: ->(entry) { EntriesHelper.entries_cache_key(entry, favicons) }
    })
    ApplicationController.render({
      layout: nil,
      template: "api/v2/entries/index",
      assigns: {entries: entries},
      format: :html,
      locals: {
        params: {mode: "extended"}
      }
    })
  end
end
