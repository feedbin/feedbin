class ImageDeleter
  include Sidekiq::Worker

  def perform(image_urls)
    paths = extract_paths(image_urls)
    S3_POOL.with do |connection|
      paths.each_slice(999) do |slice|
        connection.delete_multiple_objects(ENV["AWS_S3_BUCKET_IMAGES"], slice, {quiet: true})
      end
    end
    Librato.increment "entry_image.delete", by: image_urls.length
  end

  def extract_paths(image_urls)
    image_urls.map do |image_url|
      URI.parse(image_url).path[1..-1]
    end
  end
end
