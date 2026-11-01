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
    entries = Entry.where(id: entry_ids).with_list_associations.to_a
    favicons = Image.favicons_for_entries(entries)

    # The same invocation the entry list renders with, or this warms keys
    # nothing ever looks up. The API isn't warmed: its responses come from
    # stored renderings, not a fragment cache.
    ApplicationController.render(EntriesHelper.entry_collection(entries, favicons).merge(format: :html))
  end
end
