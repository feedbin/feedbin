class Push
  def self.callback_url(feed)
    protocol = Feedbin::Application.config.force_ssl ? "https" : "http"
    Rails.application.routes.url_helpers.push_feed_url(feed, protocol: protocol, host: ENV['PUSH_URL'])
  end

  def self.hub_secret(feed_id)
    Digest::SHA1.hexdigest([feed_id, Feedbin::Application.config.secret_key_base].join('-'))
  end
end