require "rmagick"

class FaviconCleaner
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(favicon_id = nil, schedule = false)
    if schedule
      build
    else
      clean(favicon_id)
    end
  rescue ActiveRecord::RecordNotFound
  end

  def clean(favicon_id)
    favicon = Favicon.unscoped.find(favicon_id)
    if favicon.favicon && favicon_blank?(favicon.favicon)
      favicon.destroy
    end
  end

  def favicon_blank?(data)
    data = Base64.decode64(data)
    layers = Magick::Image.from_blob(data)
    layer = layers.first.scale(1, 1)
    pixel = layer.pixel_color(0, 0)
    color = layer.to_color(pixel)
    %w[none white #FFFFFF].include?(color) || color.include?("#FFFFFF")
  ensure
    layer&.destroy!
    layers&.map(&:destroy!)
  end

  def build
    enqueue_all(Favicon, self.class)
  end
end
