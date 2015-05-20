class DeviceFeedback
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform
    if ENV['APPLE_PUSH_CERT_IOS']
      attempts = get_attempts
      tokens = attempts.keys
      devices = Device.where("lower(token) IN (?)", tokens.map(&:downcase))
      devices.each do |device|
        failed_at = attempts[device.token.downcase]
        if push_failed_since_device_was_added?(device.updated_at, failed_at)
          device.destroy
        end
      end
    end
  end

  def get_attempts
    attempts = {}
    p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT_IOS']))
    certificate = StringIO.new(p12.certificate.to_pem + p12.key.to_pem)
    feedback = Grocer.feedback(certificate: certificate)
    feedback.each do |attempt|
      attempts[attempt.device_token.downcase] = attempt.timestamp
    end
    attempts
  end

  def push_failed_since_device_was_added?(device_updated_at, failed_at)
    failed_at > device_updated_at
  end

end