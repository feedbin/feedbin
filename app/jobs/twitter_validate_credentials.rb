class TwitterValidateCredentials
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform
    return unless account_credentials_valid?
    User.where(suspended: false).where("twitter_auth_failures <= ?", 2).find_each do |user|
      unless user.twitter_credentials_valid?
        user.increment!(:twitter_auth_failures)
        if user.twitter_auth_failures > 1
          user.twitter_log_out
          UserMailer.delay(retry: false).twitter_connection_error(user.id)
        end
      end
    end
  end

  def account_credentials_valid?
    Twitter::REST::Client.new { |config|
      config.consumer_key = ENV["TWITTER_KEY"]
      config.consumer_secret = ENV["TWITTER_SECRET"]
    }.search("example", count: 1) && true
  rescue Twitter::Error => e
    Honeybadger.notify(e)
    false
  end
end
