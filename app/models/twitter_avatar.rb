# A Twitter user's avatar by the URL a tweet carries. Twitter has no crawler:
# the only stored copies are the ones BackfillTwitterAvatars moved out of
# remote_files, one images row per URL, keyed by the URL's MD5. The signing
# is RemoteFile's, so the icons path's existing URLs, and the CDN's cache of
# them, stay valid.
class TwitterAvatar
  def self.fingerprint(url)
    Digest::MD5.hexdigest(url.to_s)
  end

  def self.sign(url)
    OpenSSL::HMAC.hexdigest("sha1", Camo.secret_key, url.to_s)
  end

  def self.signature_valid?(signature, url)
    ActiveSupport::SecurityUtils.secure_compare(signature.to_s, sign(url))
  end

  # Garbage in is garbage out, not an exception: a bad hex string decodes to
  # bytes no signature matches, so the route answers 404.
  def self.decode(hex)
    [hex.to_s].pack("H*").force_encoding(Encoding::UTF_8)
  end

  def self.path(url)
    url = url.to_s
    helpers = Rails.application.routes.url_helpers
    signature = sign(url)
    hex = url.unpack1("H*")

    if (host = ENV["FILES_HOST"].presence)
      host = URI(host)
      helpers.twitter_avatar_url(signature, hex, protocol: host.scheme, host: host.host)
    else
      helpers.twitter_avatar_path(signature, hex)
    end
  end

  def self.resolve(url)
    Image.provider_twitter_avatar.find_by(provider_id: fingerprint(url))&.public_url
  end
end
