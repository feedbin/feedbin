class NewsletterProcessor
  include Sidekiq::Worker
  sidekiq_options queue: :network_default

  def perform(to, url)
    NewsletterReceiver.new.perform(to, url)
  end
end
