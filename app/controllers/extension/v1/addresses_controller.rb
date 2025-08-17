module Extension
  module V1
    class AddressesController < ApiController
      def new
        @user = current_user
        @token = AuthenticationToken.generate_alpha_token
        @verified_token = Rails.application.message_verifier(:address_token).generate(@token)
        @addresses = @user.authentication_tokens.newsletters.active.order(token: :asc)
      end

      def create
        @user = current_user
        @addresses = @user.authentication_tokens.newsletters.active.order(token: :asc)
        if params[:button_action] == "save"
          token = Rails.application.message_verifier(:address_token).verify(params[:verified_token])
          @record = @user.authentication_tokens.newsletters.create(token: token)
          @record.update(address_params)
          @record
        else
          if clean_token.present?
            @token = AuthenticationToken.newsletters.generate_custom_token(clean_token)
            @verified_token = Rails.application.message_verifier(:address_token).generate(@token)
            @numbers = @token.split(".").last
          else
            render json: {error: true} and return
          end
        end
      end

      private

      def clean_token
        params[:address].present? && params[:address].downcase.gsub(/[^a-z0-9\-\._]+/, "")
      end

      def address_params
        params.permit(:description, :tag)
      end
    end
  end
end