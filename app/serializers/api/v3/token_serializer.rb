module Api
  module V3
    # The token object: one app's access to an account, without its secret.
    class TokenSerializer
      def initialize(token, current_token:)
        @token = token
        @current_token = current_token
      end

      def to_h
        {
          object: "token",
          id: @token.id,
          # Tokens from the OAuth flow have no device name of their own.
          device_name: @token.device_name || @token.application.name,
          created_at: @token.created_at.utc.iso8601,
          last_used_at: @token.last_used_at&.utc&.iso8601,
          current: @token.id == @current_token.id
        }
      end
    end
  end
end
