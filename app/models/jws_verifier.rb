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

  def chain
    @chain ||= begin
      parts = @token.split(".").map { |part| Base64.decode64(part) }
      header = JSON.parse(parts.first)
      header["x5c"].map { |part| OpenSSL::X509::Certificate.new(Base64.decode64(part))}
    end
  end

  def root_ends_chain?
    chain.last == ROOT_CERT
  end

  def chain_valid?
    chain.each_cons(2).all? do |(first, second)|
      first.verify(second.public_key)
    end
  end

  def jwt_valid?
    decoded = JWT.decode(@token, chain.first.public_key, true, { algorithms: ["ES256"] })
    !decoded.nil?
  rescue JWT::JWKError
    false
  rescue JWT::DecodeError
    false
  end
end