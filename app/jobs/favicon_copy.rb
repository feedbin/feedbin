class FaviconCopy
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  attr_reader :favicon

  def perform(favicon_id = nil, schedule = false)
    if schedule
      build
    else
      @favicon = Favicon.find(favicon_id)
      move
    end
  rescue ActiveRecord::RecordNotFound, Excon::Error::NotFound
  end

  private

  STORAGE_OPTIONS = {
    "Cache-Control" => "max-age=315360000, public",
    "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
    "x-amz-storage-class" => "REDUCED_REDUNDANCY",
  }

  def move
    if favicon.url
      url = s3_copy(favicon.url)
      favicon.update(url: url)
    end
  end

  def s3_copy(url)
    url = URI.parse(url)
    source_object_name = url.path[1..-1]

    filename = url.path.split("/").last
    destination_object_name = File.join(filename[0..2], filename)

    S3_POOL.with do |connection|
      connection.copy_object(ENV["AWS_S3_BUCKET"], source_object_name, ENV["AWS_S3_BUCKET_FAVICONS"], destination_object_name, STORAGE_OPTIONS)
    end

    url.host = url.host.sub(ENV["AWS_S3_BUCKET"], ENV["AWS_S3_BUCKET_FAVICONS"])
    url.path = "/#{destination_object_name}"
    url.to_s
  end

  def build
    enqueue_all(Favicon, self.class)
  end
end
