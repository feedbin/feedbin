class TwitterLinkFeed
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, activate)
    if activate
      # turn on feed
    else
      # turn off feed
    end
  end

end
