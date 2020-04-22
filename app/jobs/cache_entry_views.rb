class CacheEntryViews
  include Sidekiq::Worker

  def perform(entry_id)
    entries = Entry.where(id: entry_id)
    ApplicationController.render({
      layout: nil,
      template: "api/v2/entries/index.html.erb",
      assigns: {entries: entries},
      locals: {
        params: {mode: "extended"}
      }
    })
  end
end
