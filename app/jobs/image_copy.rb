class ImageCopy
  include Sidekiq::Worker
  sidekiq_options queue: :image_mover

  attr_reader :entry

  def perform(entry_id)
    @entry = Entry.find(entry_id)

    if entry.image && entry.image["processed_url"]
      url = s3_copy(entry.image["processed_url"])
      image = entry.image
      image["processed_url"] = url
      entry.update(image: image)
    end

    if entry.data && entry.data["itunes_image_processed"]
      url = s3_copy(entry.data["itunes_image_processed"], "-itunes")
      data = entry.data
      data["itunes_image_processed"] = url
      entry.update(data: data)
    end
  rescue ActiveRecord::RecordNotFound, Excon::Error::NotFound
  end

  private

  STORAGE_OPTIONS = {
    "Cache-Control" => "max-age=315360000, public",
    "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
    "x-amz-storage-class" => "REDUCED_REDUNDANCY",
  }

  def s3_copy(url, append = "")
    url = URI.parse(url)
    source_object_name = url.path[1..-1]
    destination_object_name = File.join(entry.public_id[0..6], "#{entry.public_id}#{append}.jpg")

    S3_POOL.with do |connection|
      connection.copy_object(ENV["AWS_S3_BUCKET"], source_object_name, ENV["AWS_S3_BUCKET_NEW"], destination_object_name, STORAGE_OPTIONS)
    end

    url.host = url.host.sub(ENV["AWS_S3_BUCKET"], ENV["AWS_S3_BUCKET_NEW"])
    url.path = "/#{destination_object_name}"
    url.to_s
  end
end
