module Api
  module V3
    class CustomShareServiceSerializer
      def initialize(service)
        @service = service
      end

      def to_h
        {object: "custom_share_service", id: @service.id, label: @service.label, url: @service.url}
      end
    end
  end
end
