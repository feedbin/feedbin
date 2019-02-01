class NewsletterSaver
  include Sidekiq::Worker

  attr_reader :entry

  def perform(entry_id)
    entry = Entry.find(entry_id)
    content = entry.content
    if entry.content_format == "text"
      content = ContentFormatter.text_email(content)
      content = "<h1>#{entry.title}</h1>#{content}"
    end

    S3_POOL.with do |connection|
      connection.put_object(ENV["AWS_S3_BUCKET_NEWSLETTERS"], File.join(entry.public_id[0..2], "#{entry.public_id}.html"), content, s3_options)
    end
  end

  def s3_options
    {
      "Content-Type" => "text/html; charset=utf-8",
      "Cache-Control" => "max-age=315360000, public",
      "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
      "x-amz-acl" => "public-read",
      "x-amz-storage-class" => "REDUCED_REDUNDANCY",
    }
  end
end
