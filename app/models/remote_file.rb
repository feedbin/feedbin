class RemoteFile < ApplicationRecord
  BUCKET = ENV["AWS_S3_BUCKET_ICONS"]
  HOST = ENV["ICONS_HOST"]

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

  def self.decode(string)
    string.scan(/../).map { |x| x.hex.chr }.join
  end

  def self.secret_key
    ENV.fetch("CAMO_KEY", "secret")
  end

  def self.signature_valid?(signature, data)
    signature == OpenSSL::HMAC.hexdigest("sha1", secret_key, data)
  end

  def signed_url
    self.class.signed_url(original_url)
  end
end
