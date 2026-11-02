module Api
  module V3
    class TokensController < ApiController
      before_action -> { require_scope("account") }, only: :index

      def index
        tokens = active_tokens.includes(:application).order(created_at: :desc)
        render_list(tokens.map { TokenSerializer.new(_1, current_token: @token).to_h })
      end

      # A token can revoke itself; revoking another needs account.
      def destroy
        token = active_tokens.find(params[:id])
        return require_scope("account") unless token.id == @token.id || @token.scopes.include?("account")
        token.revoke
        head :no_content
      end

      private

      def active_tokens
        @user.oauth_access_tokens.where(revoked_at: nil)
      end
    end
  end
end
