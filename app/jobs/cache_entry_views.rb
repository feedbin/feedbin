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
    entries = Entry.where(id: entry_ids).includes(feed: Feed::ICON_PRELOADS).preload_image_records.to_a
    favicons = Favicon.for_entries(entries)

    # The same invocation the entry list renders with, or this warms keys
    # nothing ever looks up.
    ApplicationController.render(EntriesHelper.entry_collection(entries, favicons).merge(format: :html))
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
