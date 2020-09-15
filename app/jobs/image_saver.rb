class ImageSaver
  include Sidekiq::Worker
  sidekiq_options retry: false

  attr_reader :entry

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    Nokogiri::HTML5(content).css("img").each do |image|
      src = image["src"]
      next unless src.start_with?("http")
      file = Download.new(src)
      unless already_uploaded? file
        upload file
      end
    ensure
      file.delete if file
    end
    @entry.update(archived_images: true)
  rescue ActiveRecord::RecordNotFound, HTTP
  end

  private

  STORAGE_OPTIONS = {
    "Cache-Control" => "max-age=315360000, public",
    "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
    "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY"
  }

  def content
    ContentFormatter.absolute_source(entry.content, entry, entry.url)
  end

  def already_uploaded?(file)
    S3_POOL.with do |connection|
      connection.head_object(ENV["AWS_S3_BUCKET_ARCHIVE"], file.path)
    end
  rescue Excon::Error::NotFound
    false
  end

  def upload(file)
    path = file.download
    S3_POOL.with do |connection|
      connection.put_object(ENV["AWS_S3_BUCKET_ARCHIVE"], file.path, File.open(path), STORAGE_OPTIONS.dup.merge("Content-Type" => file.content_type))
    end
  end
end
