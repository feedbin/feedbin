module Api
  module V3
    class TokensController < ApiController
      before_action -> { require_scope("account") }, only: :index
      before_action :ensure_may_revoke, only: :destroy

      def index
        tokens = active_tokens.includes(:application).order(created_at: :desc)
        render_list(tokens.map { TokenSerializer.new(_1, current_token: @token).to_h })
      end

      def destroy
        active_tokens.find(params[:id]).revoke
        head :no_content
      end

      private

      def active_tokens
        @user.oauth_access_tokens.where(revoked_at: nil)
      end

      # Scope is checked before the lookup so the response doesn't reveal which ids exist.
      def ensure_may_revoke
        require_scope("account") unless params[:id].to_s == @token.id.to_s
      end
    end
  end
end
