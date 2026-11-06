module Api
  module V3
    class DeviceSerializer
      PLATFORMS = {"notifier" => "ios", "safari" => "safari"}.freeze
      # Airshow registers as ios but is stored as podcast.
      SHOWN = PLATFORMS.merge("podcast" => "ios").freeze

      def initialize(device)
        @device = device
      end

      def to_h
        {
          object: "device",
          id: @device.id,
          platform: SHOWN.fetch(@device.device_type, @device.device_type),
          app_bundle_id: @device.application,
          model: @device.model,
          operating_system: @device.operating_system,
          created_at: @device.created_at&.utc&.iso8601
        }
      end
    end
  end
end
