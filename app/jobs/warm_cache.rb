class WarmCache
  include Sidekiq::Worker

  def perform(*args)
    true
  end
end
