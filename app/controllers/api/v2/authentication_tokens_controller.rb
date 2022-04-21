module Api
  module V2
    class AuthenticationTokensController < ApiController
      respond_to :json
      before_action :validate_content_type, only: [:create]
      skip_before_action :valid_user

      def create
        @user.authentication_tokens.icloud.create_with(skip_generate: true).find_or_create_by(authentication_token_params)
        head :ok
      rescue ActiveRecord::RecordNotUnique
        head :ok
      end

      private

      def authentication_token_params
        params.require(:authentication_token).permit(:token)
      end
    end
  end
end
