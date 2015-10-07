class APNConnection

  def initialize
    setup
  end

  def setup
    contents = File.read(ENV['APPLE_PUSH_CERT_IOS'])
    p12 = OpenSSL::PKCS12.new(contents)

    @certificate = p12.certificate.to_pem + p12.key.to_pem
    @uri = (Rails.env.production?) ? Houston::APPLE_PRODUCTION_GATEWAY_URI : Houston::APPLE_DEVELOPMENT_GATEWAY_URI
    @connection = Houston::Connection.new(@uri, @certificate, nil)
    @connection.open
  end

  def write(data)
    begin
      raise "Connection is closed" unless @connection.open?
      @connection.write(data)
    rescue Exception => e
      attempts ||= 0
      attempts += 1

      if attempts < 5
        setup
        retry
      else
        raise e
      end
    end
  end

end