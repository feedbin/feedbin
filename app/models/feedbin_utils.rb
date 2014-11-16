class FeedbinUtils
  def self.update_public_id_cache(public_id, content)
    content_length = (content.present?) ? content.length : 1
    key = Feedbin::Application.config.public_id_cache % public_id[0..4]
    Sidekiq.redis do |client|
      client.hset(key, public_id, content_length)
    end
  end
end
