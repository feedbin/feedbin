module Api
  module V3
    # A token identifies one physical device across accounts, so registering it
    # again moves that device to this account.
    class DeviceRegistration
      include BodyFields

      PLATFORMS = DeviceSerializer::PLATFORMS.invert.freeze
      OPTIONAL = {"app_bundle_id" => :application, "model" => :model, "operating_system" => :operating_system}.freeze

      attr_reader :body

      def initialize(user, body)
        @user = user
        @body = body
      end

      # => [device, created]
      def register
        attributes = self.attributes
        registered = @user.devices.where_lower(token: attributes[:token]).exists?
        [Device.register(@user, attributes[:token], attributes), !registered]
      end

      private

      # registered_with: v3 makes the device reachable by action pushes (Device.v3_ios).
      def attributes
        token = required_string("push_token")
        device_type = one_of("platform", PLATFORMS)
        attributes = {token: token, device_type: device_type, active: true, data: {"registered_with" => "v3"}}
        OPTIONAL.each { |field, column| attributes[column] = optional_string(field) }

        if device_type == "notifier"
          raise invalid("app_bundle_id", "missing", "app_bundle_id is required for ios.") if attributes[:application].blank?
          attributes[:device_type] = "podcast" if attributes[:application] == ENV["APPLE_PUSH_TOPIC_PODCAST"]
        end
        attributes
      end
    end
  end
end
