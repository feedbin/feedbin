class NewsletterSaver
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(entry_id)
    entry = Entry.find(entry_id)
    page = NewsletterPage.new(entry)
    page.save
    url = page.url
    entry.update(url: url) if url && entry.url != url
  end
end
