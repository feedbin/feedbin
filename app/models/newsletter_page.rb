# The stored web page for a newsletter entry: an HTML document, gzipped, on B2.
# It uses the image store's account and key (STORAGE_IMAGES) with its own bucket.
# The saver writes one for each new entry and the backfill rewrites the old ones.
class NewsletterPage
  HEADERS = {
    "Content-Type" => "text/html; charset=utf-8",
    "Content-Encoding" => "gzip",
    "Cache-Control" => "max-age=315360000, public"
  }.freeze

  CLIENT_LOCK = Mutex.new

  # One client for the process. Without persistent: fog drops the connection
  # after every request, so each put would pay a new TLS handshake. Excon keeps
  # a socket for each thread, so Sidekiq threads can share the client, and
  # put_object is idempotent, so Excon retries a put on a stale socket.
  def self.storage_client
    CLIENT_LOCK.synchronize { @storage_client ||= Fog::Storage.new(storage_options) }
  end

  def self.storage_options
    STORAGE_IMAGES.merge(persistent: true)
  end

  # A blank bucket would reach B2 as a path that starts with the key.
  def self.bucket
    ENV["NEWSLETTERS_BUCKET"].presence || raise("NEWSLETTERS_BUCKET is not set")
  end

  def initialize(entry)
    @entry = entry
  end

  def key
    File.join(@entry.public_id[0..2], "#{@entry.public_id}.html")
  end

  # Built from the key, not from the storage response: with path-style access
  # the response path starts with the bucket name, which is not in the public URL.
  def url
    host = ENV["NEWSLETTER_HOST"]
    return nil if host.blank?
    URI::HTTPS.build(host: host, path: "/#{key}").to_s
  end

  def headers
    HEADERS
  end

  # Memoized: the saver puts the same body to S3 and to B2.
  def body
    @body ||= ActiveSupport::Gzip.compress(document.to_html)
  end

  def save
    self.class.storage_client.put_object(self.class.bucket, key, body, headers)
    url
  end

  def document
    title = document_title

    document = if @entry.content_format == "text"
      document = ContentFormatter.html_document(ContentFormatter.text_email(@entry.content))

      heading = document.create_element("h1", title)
      document.at("body").prepend_child(heading)

      style = document.create_element("style", text_email_css)
      document.at("head").add_child(style)

      document
    else
      ContentFormatter.html_document(@entry.content)
    end

    if document.title.blank?
      document.title = title
    end

    document
  end

  private

  # entry.title is the email's Subject and is nil when the message carried no
  # Subject: header, which Nokogiri's title= rejects outright. Name it the way
  # a mail client does instead.
  def document_title
    @entry.title.presence ||
      [@entry.author.presence, @entry.published&.to_formatted_s(:date)].compact.join(" — ").presence ||
      "Newsletter"
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
end
