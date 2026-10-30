module Api
  module V3
    class TokensController < ApiController
      def index
        tokens = active_tokens.includes(:application).order(created_at: :desc)
        render_list(tokens.map { TokenSerializer.new(_1, current_token: @token).to_h })
      end

      # A token can revoke itself.
      def destroy
        active_tokens.find(params[:id]).revoke
        head :no_content
      end

      private

      def active_tokens
        @user.oauth_access_tokens.where(revoked_at: nil)
      end
    end
  end
end
