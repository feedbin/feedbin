# Camo URLs for code outside the HTML pipeline: avatars a view links to
# directly, and the Twitter avatar route's miss. CAMO_HOST is an origin:
# scheme, host and port.
module Camo
  def self.url(url)
    url = url.to_s
    origin = URI(ENV["CAMO_HOST"])
    signature = OpenSSL::HMAC.hexdigest("sha1", secret_key, url)

    URI::Generic.build(
      scheme: origin.scheme,
      host: origin.host,
      port: (origin.port unless origin.port == origin.default_port),
      path: "/#{signature}/#{url.unpack1("H*")}"
    ).to_s
  end

  def self.secret_key
    ENV.fetch("CAMO_KEY", "secret")
  end
end
