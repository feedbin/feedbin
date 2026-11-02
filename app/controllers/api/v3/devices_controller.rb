module Api
  module V3
    # Push devices. A token identifies one physical device across accounts
    # (see Device.register), so registering it again updates that device and
    # moves it to this account.
    class DevicesController < ApiController
      PLATFORMS = DeviceSerializer::PLATFORMS.invert.freeze
      OPTIONAL = {"app_bundle_id" => :application, "model" => :model, "operating_system" => :operating_system}.freeze

      def create
        body = request.request_parameters
        token = body["push_token"]
        raise invalid("push_token", "missing", "push_token is required.") unless token.is_a?(String) && token.strip.present?
        device_type = PLATFORMS.fetch(body["platform"]) { raise invalid("platform", "invalid_value", "platform must be one of #{PLATFORMS.keys.join(", ")}.") }
        attributes = {token: token.strip, device_type: device_type, active: true}
        OPTIONAL.each do |field, column|
          value = body[field]
          raise invalid(field, "invalid_value", "#{field} must be a string.") unless value.nil? || value.is_a?(String)
          attributes[column] = value
        end

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
