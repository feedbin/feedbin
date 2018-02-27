class ImageDeleter
  include Sidekiq::Worker

  S3_POOL = ConnectionPool.new(size: 4, timeout: 5) do
    Fog::Storage.new(
      provider: "AWS",
      aws_access_key_id: ENV["IMAGE_STORAGE_KEY"],
      aws_secret_access_key: ENV["IMAGE_STORAGE_SECRET"],
      persistent: true
    )
  end

  def perform(images)
    S3_POOL.with do |connection|
      connection.delete_multiple_objects(ENV["IMAGE_STORAGE_BUCKET"], images, {quiet: true})
    end
    Librato.increment 'entry_image.delete', by: images.length
  end

end