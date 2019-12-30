class WarmCache
  include Sidekiq::Worker

  def perform(feed_id)
    entries = Entry.where(feed_id: feed_id).order(published: :desc).limit(WillPaginate.per_page)
    ApplicationController.render partial: "entries/entry", collection: entries, cached: true
  end
end
