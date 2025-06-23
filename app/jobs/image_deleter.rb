class ImageDeleter
  include Sidekiq::Worker

  BUCKET = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]

  def perform(image_urls)
    client = Fog::Storage.new(STORAGE)
    paths = extract_paths(image_urls)
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(BUCKET, slice, {quiet: true})
    end
    Librato.increment "entry_image.delete", by: image_urls.length
  end

  def extract_paths(image_urls)
    image_urls.map do |image_url|
      URI.parse(image_url).path[1..-1]
    end
  end
end
