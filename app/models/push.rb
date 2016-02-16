class Push
  def self.callback_url(feed)
    uri = URI(ENV['PUSH_URL'])
    Rails.application.routes.url_helpers.push_feed_url(feed, protocol: uri.scheme, host: uri.host)
  end

  def self.hub_secret(feed_id)
    Digest::SHA1.hexdigest([feed_id, Feedbin::Application.config.secret_key_base].join('-'))
  end
end