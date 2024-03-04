class NewsletterSaver
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(entry_id)
    entry = Entry.find(entry_id)
    content = entry.content
    if entry.content_format == "text"
      content = ContentFormatter.text_email(content)
      content = "<h1>#{entry.title}</h1>#{content}"
    end
    content = ActiveSupport::Gzip.compress(content)

    response = Fog::Storage.new(STORAGE).put_object(ENV["AWS_S3_BUCKET_NEWSLETTERS"], File.join(entry.public_id[0..2], "#{entry.public_id}.html"), content, s3_options)
    host = ENV["NEWSLETTER_HOST"] || response.data[:host]
    url = URI::HTTPS.build(
      host: host,
      path: response.data[:path]
    ).to_s
    entry.update(url: url)
  end

  def s3_options
    {
      "Content-Type"        => "text/html; charset=utf-8",
      "Cache-Control"       => "max-age=315360000, public",
      "Expires"             => "Sun, 29 Jun 2036 17:48:34 GMT",
      "Content-Encoding"    => "gzip",
      "x-amz-acl"           => "public-read",
      "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY"
    }
  end
end
