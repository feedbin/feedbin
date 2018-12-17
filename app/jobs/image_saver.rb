class ImageSaver
  include Sidekiq::Worker

  attr_reader :entry

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    Nokogiri::HTML5(content).css("img").each do |image|
      file = Download.new(image["src"])
      unless already_uploaded? file
        upload file
      end
    end
  rescue ActiveRecord::RecordNotFound
  end

  private

  STORAGE_OPTIONS = {
    "Cache-Control" => "max-age=315360000, public",
    "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
    "x-amz-storage-class" => "REDUCED_REDUNDANCY",
  }

  def content
    ContentFormatter.absolute_source(entry.content, entry)
  end

  private

  def already_uploaded?(file)
    S3_POOL.with do |connection|
      connection.head_object(ENV["AWS_S3_BUCKET_STARRED"], file.path)
    end
  rescue Excon::Error::NotFound
    false
  end

  def upload(file)
    path = file.download

    response = S3_POOL.with do |connection|
      connection.put_object(ENV["AWS_S3_BUCKET_STARRED"], file.path, File.open(path), STORAGE_OPTIONS.dup.merge("Content-Type" => file.content_type))
    end

    URI::HTTPS.build(
      host: response.data[:host],
      path: response.data[:path],
    ).to_s
  end

end
