class CacheEntryViews
  include Sidekiq::Worker

  def perform(entry_id)
    entries = Entry.where(id: entry_id)
    ApplicationController.render template: "api/v2/entries/index", assigns: {entries: entries}, locals: {params: {mode: "extended"}}, cached: true, format: :json
  rescue ActiveRecord::RecordNotFound
  end
end
