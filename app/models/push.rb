class Push
  def self.hub_secret(feed_id)
    Digest::SHA1.hexdigest([feed_id, Feedbin::Application.config.secret_key_base].join('-'))
  end
end