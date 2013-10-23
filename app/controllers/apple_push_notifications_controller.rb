class ApplePushNotificationsController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize
  before_action :find_user, only: [:update, :delete]

  def create
    user_id = verify_token(params[:authentication_token])
    @user = User.find(user_id)

    path = Rails.application.assets['push-iconset/icon.png'].pathname
    p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT']))
    package = Grocer::Pushpackager::Package.new({
      websiteName: 'Feedbin',
      websitePushID: ENV['APPLE_PUSH_WEBSITE_ID'],
      allowedDomains: ['http://feedbin.dev', 'https://feedbin.me', 'https://www.feedbin.me'],
      urlFormatString: 'https://feedbin.me/view/%@',
      authenticationToken: params[:authentication_token],
      webServiceURL: 'https://feedbin.me/apple_push_notifications',
      certificate: p12.certificate,
      key: p12.key,
      iconSet: {
        :'16x16' => File.open(path),
        :'16x16@2x' => File.open(path),
        :'32x32' => File.open(path),
        :'32x32@2x' => File.open(path),
        :'128x128' => File.open(path),
        :'128x128@2x' => File.open(path)
      }
    })
    send_data package.buffer, type: :zip
  end

  def update
    @user.apple_push_notification_device_token = params[:device_token]
    @user.free_ok = (@user.plan.stripe_id == 'free')
    @user.save
    render nothing: true
  end

  def delete
    @user.apple_push_notification_device_token = nil
    @user.free_ok = (@user.plan.stripe_id == 'free')
    @user.save
    render nothing: true
  end

  def log
    Honeybadger.notify(
      error_class: "Apple Push Notification",
      error_message: "Apple Push Notification Failure",
      parameters: params
    )
  end

  private

  def find_user
    # Authorization header should look like:
    # Authorization: ApplePushNotifications AUTH_TOKEN
    name, authentication_token = request.authorization.split(' ')
    user_id = nil
    if name == 'ApplePushNotifications'
      user_id = verify_token(authentication_token)
    end
    @user = User.find(user_id)
  end

  def verify_token(authentication_token)
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    verifier.verify(authentication_token)
  end

  #   verifier.generate(user_id)

end
