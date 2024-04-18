class NewsletterSaver
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(entry_id)
    entry = Entry.find(entry_id)
    document = build_document(entry)
    content = ActiveSupport::Gzip.compress(document.to_html)
    response = Fog::Storage.new(STORAGE).put_object(ENV["AWS_S3_BUCKET_NEWSLETTERS"], File.join(entry.public_id[0..2], "#{entry.public_id}.html"), content, s3_options)
    host = ENV["NEWSLETTER_HOST"] || response.data[:host]
    url = URI::HTTPS.build(
      host: host,
      path: response.data[:path]
    ).to_s
    entry.update(url: url)
  end

  def build_document(entry)
    document = if entry.content_format == "text"
      document = Nokogiri::HTML5(ContentFormatter.text_email(entry.content))

      title = document.create_element("h1", entry.title)
      document.at("body").prepend_child(title)

      style = document.create_element("style", text_email_css)
      document.at("head").add_child(style)

      document
    else
      Nokogiri::HTML5(entry.content)
    end

    if document.title.blank?
      document.title = entry.title
    end

    document
  end

  def text_email_css
    %Q(
      html {
        font-family: system-ui;
      }
      body {
        max-width: 30rem;
        margin: 2rem auto;
        padding: 1rem;
        line-height: 1.5;
      }
    )
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
