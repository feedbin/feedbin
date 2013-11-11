class PushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false

  # ENV['RAILS_ENV'] = 'production'; reload!; p = PushNotificationSend.new; p.perform(1, [1])
  def perform(entry_id, user_ids)

    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    entry = Entry.find(entry_id)
    users = User.where(id: user_ids)
    p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT']))
    cert = [p12.certificate.to_pem, p12.key.to_pem]

    notifications = []
    title = CGI.unescapeHTML(entry.title)
    title = ApplicationController.helpers.sanitize(title, tags: []).squish.mb_chars.limit(36).to_s

    feed_title = CGI.unescapeHTML(entry.feed.title)
    feed_title = ApplicationController.helpers.sanitize(feed_title, tags: []).squish.mb_chars.limit(36).to_s

    users.each do |user|
      unless user.apple_push_notification_device_token.blank?
        notifications << Grocer::Notification.new(
          device_token: user.apple_push_notification_device_token,
          custom: {
            aps: {
              alert: {
                title: title,
                body: feed_title,
                action: "Read"
              },
              :"url-args" => [entry.id.to_s, CGI::escape(verifier.generate(user.id))]
            }
          }
        )
      end
    end

    if notifications.any?
      pusher = Grocer.pusher(
        certificate: StringIO.new(cert.join("\n")),
      )
      notifications.each do |notification|
        results = pusher.push(notification)
      end
      Librato.increment 'push_notifications_sent', by: notifications.length
    end

  end

end
