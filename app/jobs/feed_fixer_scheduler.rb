class FeedFixerScheduler
  include Sidekiq::Worker
  include SidekiqHelper

  def perform
    FeedFixer.new.build
  end
end
