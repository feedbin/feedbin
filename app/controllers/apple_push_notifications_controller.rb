class ApplePushNotificationsController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize
  before_action :find_user, only: [:update, :delete]

  def create
    user_info = JSON.parse(request.body.read)
    user_id = verify_push_token(user_info['authentication_token'])
    @user = User.find(user_id)

    p12 = OpenSSL::PKCS12.new(File.read(ENV['APPLE_PUSH_CERT']))
    package = Grocer::Pushpackager::Package.new({
      websiteName: 'Feedbin',
      websitePushID: ENV['APPLE_PUSH_WEBSITE_ID'],
      allowedDomains: [ENV['PUSH_URL']],
      urlFormatString: "#{ENV['PUSH_URL']}/entries/%@/push_view?user=%@",
      authenticationToken: user_info['authentication_token'],
      webServiceURL: "#{ENV['PUSH_URL']}/apple_push_notifications",
      certificate: p12.certificate,
      key: p12.key,
      iconSet: {
        :'16x16'      => File.open(Rails.application.assets['push-iconset/16x16.png'].pathname),
        :'16x16@2x'   => File.open(Rails.application.assets['push-iconset/16x16@2x.png'].pathname),
        :'32x32'      => File.open(Rails.application.assets['push-iconset/32x32.png'].pathname),
        :'32x32@2x'   => File.open(Rails.application.assets['push-iconset/32x32@2x.png'].pathname),
        :'128x128'    => File.open(Rails.application.assets['push-iconset/128x128.png'].pathname),
        :'128x128@2x' => File.open(Rails.application.assets['push-iconset/128x128@2x.png'].pathname)
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
    render nothing: true
  end

  private

  def find_user
    # Authorization header should look like:
    # Authorization: ApplePushNotifications AUTH_TOKEN
    name, authentication_token = request.authorization.split(' ')
    user_id = nil
    if name == 'ApplePushNotifications'
      user_id = verify_push_token(authentication_token)
    end
    @user = User.find(user_id)
  end

end
