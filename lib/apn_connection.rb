class APNConnection

  def initialize
    contents = File.read(ENV['APPLE_PUSH_CERT_IOS'])
    p12 = OpenSSL::PKCS12.new(contents)
    certificate = p12.certificate.to_pem + p12.key.to_pem
    uri = (Rails.env.production?) ? Houston::APPLE_PRODUCTION_GATEWAY_URI : Houston::APPLE_DEVELOPMENT_GATEWAY_URI
    @connection = Houston::Connection.new(uri, certificate, nil)
    open
  end

  def open
    @connection.open
  end

  def close
    @connection.close
  end

  def write(data)
    @connection.write(data)
  end

end