class CacheEntryViews
  include Sidekiq::Worker

  def perform(entry_id)
    entry = Entry.find(entry_id)
    ApplicationController.render partial: "api/v2/entries/entry_extended", locals: {entry: entry}, cached: true
  rescue ActiveRecord::RecordNotFound
  end
end
