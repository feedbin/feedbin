module Api
  module V3
    # GET, PATCH and DELETE /account. Purchases are Account::Purchases.
    class AccountController < ApiController
      before_action -> { require_scope("account") }, only: :destroy

      def show
        render json: AccountSerializer.new(@user).to_h
      end

      # A merge patch over settings (SettingsPatch). Anything else in the
      # body (email, password) is ignored: those change in the web app.
      def update
        SettingsPatch.new(@user, object("settings")).apply if body["settings"]
        render json: AccountSerializer.new(@user).to_h
      end

      # Deletion runs in the background, as the web app's does (it mails an
      # OPML export first). The token that asked is revoked now.
      def destroy
        UserDeleter.perform_async(@user.id)
        @token.revoke
        head :no_content
      end

      private

      # TrialExpiration suspends every lapsed trial and timed plan, so a
      # suspended account must still see why, or leave.
      def lapsed_account_allowed?
        %w[show destroy].include?(action_name)
      end
    end
  end
end
