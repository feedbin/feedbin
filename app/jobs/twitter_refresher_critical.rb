class TwitterRefresherCritical
  include Sidekiq::Worker
  sidekiq_options queue: :twitter_refresher_critical, retry: false
  def perform(*args)
    TwitterRefresher.new.perform(*args)
  end
end
