class RemoteFile < ApplicationRecord
  BUCKET = ENV["AWS_S3_BUCKET_ICONS"]
  REGION = ENV["AWS_S3_BUCKET_ICONS_REGION"]
  HOST = ENV["FILES_HOST"]

  store_accessor :settings, :width, :height

  def self.fingerprint(data)
    Digest::MD5.hexdigest(data)
  end

  def self.signed_url(url)
    url = url.to_s
    signature = OpenSSL::HMAC.hexdigest("sha1", secret_key, url)
    url = url.to_enum(:each_byte).map { |byte| "%02x" % byte }.join

    if HOST
      host = URI(HOST)
      Rails.application.routes.url_helpers.icon_remote_files_url(signature, url, protocol: host.scheme, host: host.host)
    else
      Rails.application.routes.url_helpers.icon_remote_files_path(signature, url)
    end
  end

  # The legacy icons bucket's object for a url, or nil. The bucket is
  # public-read, so a crawler can hand the object to Find as the candidate
  # after the original: a dead source still lands as a copy of what the
  # proxy cached. Deploy A only: once the backfills finish, no crawler
  # needs it.
  def self.legacy_object_url(url)
    find_by(fingerprint: fingerprint(url.to_s))&.storage_url
  end

  def self.decode(string)
    string.scan(/../).map { |x| x.hex.chr }.join
  end

  def self.secret_key
    ENV.fetch("CAMO_KEY", "secret")
  end

  def self.signature_valid?(signature, data)
    signature == OpenSSL::HMAC.hexdigest("sha1", secret_key, data)
  end

  # host is an origin (scheme, host, port); key signs for that host. The
  # defaults are production's camo. ImageCrawler::OutsideCamo passes its
  # own fleet and key.
  def self.camo_url(url, host: ENV["CAMO_HOST"], key: secret_key)
    origin = URI(host)
    signature = OpenSSL::HMAC.hexdigest("sha1", key, url)
    hex_url = url.to_enum(:each_byte).map { |byte| "%02x" % byte }.join

    URI::Generic.build(
      scheme: origin.scheme,
      host: origin.host,
      port: (origin.port unless origin.port == origin.default_port),
      path: "/#{signature}/#{hex_url}"
    ).to_s
  end

  def signed_url
    self.class.signed_url(original_url)
  end
end
