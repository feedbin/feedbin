if ENV['APPLE_PUSH_CERT']
  p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT']))
  certificate = StringIO.new(p12.certificate.to_pem + p12.key.to_pem)
  $grocer = ConnectionPool.new(size: 1, timeout: 5) do
    Grocer.pusher(certificate: certificate)
  end
end


if ENV['APPLE_PUSH_CERT_IOS']
  p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT_IOS']))
  certificate = StringIO.new(p12.certificate.to_pem + p12.key.to_pem)
  $grocer_ios = ConnectionPool.new(size: 1, timeout: 5) do
    Grocer.pusher(certificate: certificate)
  end
end