class JwsVerifier
  ROOT_CERT = OpenSSL::X509::Certificate.new(File.read(File.join(Rails.root, "config", "AppleRootCA-G3.cer")))

  def initialize(token)
    @token = token
  end

  def self.valid?(token)
    new(token).verify
  end

  def verify
    [root_ends_chain?, chain_valid?, jwt_valid?].all?
  end

  private

  # A verifier's contract is to answer false for anything it cannot validate,
  # so everything malformed resolves to an empty chain rather than raising.
  # This gates an endpoint with every authentication filter skipped, where a
  # raise is an anonymous 500 that Apple then retries.
  def chain
    @chain ||= begin
      # JWT is base64url; decode64 mangles any part containing - or _.
      parts = @token.to_s.split(".").map { |part| Base64.urlsafe_decode64(part) }
      header = JSON.parse(parts.first.to_s)
      certificates = header["x5c"]
      certificates = [] unless certificates.is_a?(Array)
      # x5c members are standard base64, per RFC 7515.
      certificates.map { |part| OpenSSL::X509::Certificate.new(Base64.decode64(part)) }
    end
  rescue JSON::ParserError, ArgumentError, TypeError, OpenSSL::X509::CertificateError
    []
  end

  def root_ends_chain?
    chain.last == ROOT_CERT
  end

  # each_cons(2) is vacuously true for a chain of one, which would let a
  # single self-supplied certificate through this check.
  def chain_valid?
    return false if chain.length < 2

    chain.each_cons(2).all? do |(first, second)|
      first.verify(second.public_key)
    end
  end

  def jwt_valid?
    decoded = JWT.decode(@token, chain.first&.public_key, true, { algorithms: ["ES256"] })
    !decoded.nil?
  rescue JWT::JWKError
    false
  rescue JWT::DecodeError
    false
  end
end