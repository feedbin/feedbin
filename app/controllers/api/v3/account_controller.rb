module Api
  module V3
    class AccountController < ApiController
      before_action -> { require_scope("account") }, only: :destroy

      def show
        render json: AccountSerializer.new(@user).to_h
      end

      def update
        SettingsPatch.new(@user, object("settings")).apply if body["settings"]
        render json: AccountSerializer.new(@user).to_h
      end

      def destroy
        UserDeleter.perform_async(@user.id)
        @token.revoke
        head :no_content
      end

      private

      # A suspended account must still be able to see why, or leave.
      def lapsed_account_allowed?
        %w[show destroy].include?(action_name)
      end
    end
  end
end
