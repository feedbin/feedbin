class CacheEntryViews
  include Sidekiq::Worker
  include BatchJobs

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
    entries = Entry.where(id: entry_ids).includes(feed: [:favicon])
    ApplicationController.render({
      partial: "entries/entry",
      collection: entries,
      format: :html,
      cached: true
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
