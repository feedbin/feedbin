Feedbin::Application.config.vapid_key = if ENV["WEB_PUSH_CERT"] && File.exist?(ENV["WEB_PUSH_CERT"])
  WebPush::VapidKey.from_pem(File.read(ENV["WEB_PUSH_CERT"]))
end
