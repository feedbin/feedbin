class Push
  def self.hub_secret(feed_id)
    Digest::SHA1.hexdigest([feed_id, Rails.application.secrets.secret_key_base].join("-"))
  end
end
