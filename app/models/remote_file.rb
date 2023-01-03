class RemoteFile < ApplicationRecord
  BUCKET = ENV["AWS_S3_BUCKET_ICONS"]
  REGION = ENV["AWS_S3_BUCKET_ICONS_REGION"]
  HOST = ENV["FILES_HOST"] || ENV["PUSH_URL"]

  store_accessor :settings, :width, :height

  def self.fingerprint(data)
    Digest::MD5.hexdigest(data)
  end

  def self.icon_url(url, params: {})
    encoded = encode(url)
    host = URI(HOST)
    Rails.application.routes.url_helpers.icon_remote_files_url(encoded.signature, encoded.url, protocol: host.scheme, host: host.host, params: params)
  end

  def self.favicon_url(url, fingerprint, params: {})
    encoded = encode(url)
    host = URI(HOST)
    Rails.application.routes.url_helpers.favicon_remote_files_url(fingerprint, encoded.signature, encoded.url, protocol: host.scheme, host: host.host, params: params)
  end

  def self.encode(url)
    url = url.to_s
    signature = OpenSSL::HMAC.hexdigest("sha1", secret_key, url)
    url = url.to_enum(:each_byte).map { |byte| "%02x" % byte }.join
    OpenStruct.new(url:, signature:)
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

  def self.camo_url(url)
    host = URI(ENV["CAMO_HOST"]).host
    signature = OpenSSL::HMAC.hexdigest("sha1", secret_key, url)
    hex_url = url.to_enum(:each_byte).map { |byte| "%02x" % byte }.join

    URI::HTTPS.build(
      host: host,
      path: "/#{signature}/#{hex_url}"
    ).to_s
  end

  def icon_url
    self.class.icon_url(original_url)
  end
end
