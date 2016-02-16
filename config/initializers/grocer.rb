def apns_pool(certificate_path)
  contents = File.read(certificate_path)
  p12 = OpenSSL::PKCS12.new(contents)
  certificate = StringIO.new(p12.certificate.to_pem + p12.key.to_pem)
  ConnectionPool.new(size: 2, timeout: 5) do
    Grocer.pusher(certificate: certificate)
  end
end

if ENV['APPLE_PUSH_CERT']
  $grocer = apns_pool(ENV['APPLE_PUSH_CERT'])
end
