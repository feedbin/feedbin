module Api
  module V3
    # A merge patch over settings, keyed by AccountSerializer::SETTINGS names.
    class SettingsPatch
      include BodyFields

      attr_reader :body

      def initialize(user, settings)
        @user = user
        @body = settings
        @pointer = "/settings"
      end

      def apply
        stored = @user.settings.dup
        body.slice(*AccountSerializer::SETTINGS.keys).each do |name, value|
          key, type = AccountSerializer::SETTINGS.fetch(name)
          stored[key] = stored_value(name, type, value)
        end
        @user.update!(settings: stored)
      end

      private

      def stored_value(name, type, value)
        case type
        when :sort
          one_of(name, AccountSerializer::SORTS, value)
        when :integer
          raise invalid(name, "invalid_value", "#{name} must be a positive integer.") unless value.is_a?(Integer) && value.positive?
          value.to_s
        when :boolean
          boolean(name, value) ? "1" : "0"
        end
      end
    end
  end
end
