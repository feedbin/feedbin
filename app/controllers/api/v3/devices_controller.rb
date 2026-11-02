module Api
  module V3
    # Push devices. A token identifies one physical device across accounts
    # (see Device.register), so registering it again updates that device and
    # moves it to this account.
    class DevicesController < ApiController
      before_action -> { require_scope("account") }
      PLATFORMS = DeviceSerializer::PLATFORMS.invert.freeze
      APNS_ENVIRONMENTS = %w[production development].freeze
      OPTIONAL = {"app_bundle_id" => :application, "model" => :model, "operating_system" => :operating_system}.freeze

      def create
        body = request.request_parameters
        token = body["push_token"]
        raise invalid("push_token", "missing", "push_token is required.") unless token.is_a?(String) && token.strip.present?
        device_type = PLATFORMS.fetch(body["platform"]) { raise invalid("platform", "invalid_value", "platform must be one of #{PLATFORMS.keys.join(", ")}.") }
        # registered_with marks a device action pushes may reach (Device.v3_ios).
        attributes = {token: token.strip, device_type: device_type, active: true, data: {"registered_with" => "v3"}}
        environment = body["apns_environment"] || "production"
        raise invalid("apns_environment", "invalid_value", "apns_environment must be production or development.") unless APNS_ENVIRONMENTS.include?(environment)
        attributes[:data]["apns_environment"] = environment
        OPTIONAL.each do |field, column|
          value = body[field]
          raise invalid(field, "invalid_value", "#{field} must be a string.") unless value.nil? || value.is_a?(String)
          attributes[column] = value
        end
        # Pushes go out under the app's bundle id.
        raise invalid("app_bundle_id", "missing", "app_bundle_id is required for ios.") if device_type == "notifier" && attributes[:application].blank?
        # Airshow's pushes are podcast episodes, sent by PodcastPushNotification.
        attributes[:device_type] = "podcast" if device_type == "notifier" && attributes[:application] == ENV["APPLE_PUSH_TOPIC_PODCAST"]

        registered = @user.devices.where_lower(token: attributes[:token]).exists?
        device = Device.register(@user, attributes[:token], attributes)
        render json: DeviceSerializer.new(device).to_h, status: registered ? :ok : :created
      end

      def destroy
        @user.devices.find(params[:id]).destroy
        head :no_content
      end

      private

      def invalid(field, code, detail)
        Problems::InvalidParameter.new(detail, pointer: "/#{field}", code: code)
      end
    end
  end
end
