module Api
  module V3
    class TokensController < ApiController
      before_action -> { require_scope("account") }, only: :index

      def index
        tokens = active_tokens.includes(:application).order(created_at: :desc)
        render_list(tokens.map { TokenSerializer.new(_1, current_token: @token).to_h })
      end

      # A token can revoke itself; revoking another needs account, checked
      # before the lookup so the answer doesn't say which ids exist.
      def destroy
        return require_scope("account") unless params[:id].to_s == @token.id.to_s || @token.includes_scope?("account")
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
