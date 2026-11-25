module Api
  module V3
    module Account
      # The subscription the app's store account holds, presented by the
      # signed-in account so it pays for that account.
      class StoreSubscriptionsController < ApiController
        include StoreSubscriptionProof

        def create
          @user.claim_store_subscription(**proof_params)
          render json: AccountSerializer.new(@user.reload).to_h
        end
      end
    end
  end
end
